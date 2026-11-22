/* Dhadda web vault sync - IndexedDB + WebCrypto + HTTP. No dependencies.
   Loaded before app.js. Presentation screens are unchanged by this module. */
(() => {
'use strict';

const WORKER = window.DHADDA_SYNC_URL || 'http://127.0.0.1:8787';
const DB_NAME = 'dhadda-sync';
const STORES = ['rows', 'meta', 'outbox', 'prebackup'];
const PUSH_DELAY = 2000;
const PULL_INTERVAL = 30000;

let db = null, key = null, vaultId = null, token = null;
let lastSeq = 0, lastSync = 0, lastSeenUa = 0, deviceId = 'web-' + Math.random().toString(36).slice(2);
let pushTimer = null, pollTimer = null, inFlight = false, backoff = 1000, lastError = '';
let hooks = { onData: () => {}, onStatus: () => {} };
let status = 'Not connected';
let counts = { rows: 0, pending: 0 };

const now = () => Date.now();
const keyPath = t => ({ categories:'categories', accounts:'accounts', entries:'transactions', events:'projects', people:'loans', lent_txns:'lentTxns', settings:'settings' }[t] || t);
const rowKey = (t, id) => `${t}:${id}`;

function setStatus(s) { status = s; hooks.onStatus(s, counts, lastSync); }

function openDB() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => {
      const d = req.result;
      for (const s of STORES) if (!d.objectStoreNames.contains(s)) d.createObjectStore(s);
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}
function tx(store, mode = 'readonly') { return db.transaction(store, mode).objectStore(store); }
function get(store, k) { return new Promise((res, rej) => { const r = tx(store).get(k); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); }); }
function put(store, k, v) { return new Promise((res, rej) => { const r = tx(store, 'readwrite').put(v, k); r.onsuccess = () => res(); r.onerror = () => rej(r.error); }); }
function del(store, k) { return new Promise((res, rej) => { const r = tx(store, 'readwrite').delete(k); r.onsuccess = () => res(); r.onerror = () => rej(r.error); }); }
function all(store) { return new Promise((res, rej) => { const r = tx(store).getAll(); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); }); }
function clear(store) { return new Promise((res, rej) => { const r = tx(store, 'readwrite').clear(); r.onsuccess = () => res(); r.onerror = () => rej(r.error); }); }

async function sha256Hex(text) {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, '0')).join('');
}
const b64u = bytes => btoa(String.fromCharCode(...bytes)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
const unb64u = s => Uint8Array.from(atob(s.replace(/-/g,'+').replace(/_/g,'/')), c => c.charCodeAt(0));

async function importKey(b64) {
  return crypto.subtle.importKey('raw', unb64u(b64), { name: 'AES-GCM' }, false, ['encrypt','decrypt']);
}
async function encryptRow(row) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const plain = new TextEncoder().encode(JSON.stringify({ id: row.id, t: row.t, data: row.data }));
  const ct = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, plain);
  return { t: row.t, id: row.id, ua: row.ua, d: row.d, device_id: deviceId,
    iv: b64u(iv), ct: b64u(new Uint8Array(ct)) };
}
async function decryptRow(w) {
  const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: unb64u(w.iv) }, key, unb64u(w.ct));
  const obj = JSON.parse(new TextDecoder().decode(plain));
  return { t: obj.t || w.t, id: obj.id || w.id, data: obj.data, ua: w.ua, d: w.d, seq: w.seq };
}

function wins(incoming, current) {
  if (!current) return true;
  if (incoming.ua !== current.ua) return incoming.ua > current.ua;
  return incoming.device_id > current.device_id;
}
async function mergeWire(w) {
  const r = await decryptRow(w);
  lastSeenUa = Math.max(lastSeenUa, r.ua);
  const cur = await get('rows', rowKey(r.t, r.id));
  if (wins({ ...r, device_id: w.device_id }, cur)) await put('rows', rowKey(r.t, r.id), { ...r, device_id: w.device_id });
}
function hybridUa() {
  const ua = Math.max(now(), lastSeenUa + 1);
  lastSeenUa = Math.max(lastSeenUa, ua);
  return ua;
}

async function saveMeta() {
  await put('meta', 'vault_id', vaultId);
  await put('meta', 'token', token);
  await put('meta', 'last_seq', lastSeq);
  await put('meta', 'last_sync', lastSync);
}

async function request(path, options = {}) {
  const h = { ...(options.headers || {}) };
  if (token) h.Authorization = `Bearer ${token}`;
  const res = await fetch(WORKER + path, { ...options, headers: h });
  if (!res.ok) {
    let detail = '';
    try { detail = (await res.json()).error || ''; } catch {}
    throw new Error('HTTP ' + res.status + (detail ? ' ' + detail : ''));
  }
  return res.json();
}

async function push() {
  if (!key || inFlight) return;
  const outbox = await all('outbox');
  if (!outbox.length) return;
  inFlight = true;
  setStatus('Syncing…');
  try {
    const rows = [];
    for (const r of outbox) rows.push(await encryptRow(r));
    const res = await request('/v1/push', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device_id: deviceId, rows }),
    });
    for (const r of rows) await del('outbox', rowKey(r.t, r.id));
    for (const older of res.rejected_older || []) {
      const w = await decryptRow(older);
      const cur = await get('rows', rowKey(w.t, w.id));
      if (wins(w, cur)) { await put('rows', rowKey(w.t, w.id), w); hooks.onData(); }
    }
    if (res.server_seq > lastSeq) { lastSeq = res.server_seq; await saveMeta(); }
    lastSync = now(); backoff = 1000;
    counts.pending = (await all('outbox')).length;
    setStatus('Synced just now');
  } catch (e) {
    lastError = String(e && e.message || e);
    counts.pending = outbox.length;
    setStatus(navigator.onLine ? 'Sync error (tap for details)' : `Offline, ${counts.pending} changes waiting`);
    backoff = Math.min(300000, backoff * 2);
  } finally { inFlight = false; }
}

async function pull() {
  if (!key || inFlight || document.hidden) return;
  inFlight = true;
  setStatus('Syncing…');
  try {
    const res = await request(`/v1/pull?since=${lastSeq}&limit=500`);
    for (const w of res.rows) await mergeWire(w);
    if (res.next > lastSeq) { lastSeq = res.next; await saveMeta(); }
    lastSync = now(); backoff = 1000;
    counts.rows = (await all('rows')).length;
    counts.pending = (await all('outbox')).length;
    hooks.onData();
    setStatus('Synced just now');
    if (res.more) setTimeout(pull, 0);
  } catch (e) {
    counts.pending = (await all('outbox')).length;
    setStatus(navigator.onLine ? 'Sync error (tap for details)' : `Offline, ${counts.pending} changes waiting`);
    backoff = Math.min(300000, backoff * 2);
  } finally { inFlight = false; }
}

function schedulePush() {
  clearTimeout(pushTimer);
  counts.pending = 1;
  setStatus(navigator.onLine ? 'Syncing…' : 'Offline, 1 change waiting');
  pushTimer = setTimeout(() => { push().then(pull); }, PUSH_DELAY);
}
function startPolling() {
  clearInterval(pollTimer);
  pollTimer = setInterval(() => { if (!document.hidden) pull(); }, PULL_INTERVAL);
}

async function exportOldBackup() {
  const old = {};
  for (const k of ['expense_cats_v1','expense_txns_v1','expense_loans_v1','expense_projects_v1','expense_meta_v1']) {
    old[k] = localStorage.getItem(k);
  }
  if (Object.values(old).every(v => v == null)) return false;
  await put('prebackup', 'old', JSON.stringify(old));
  return true;
}
function downloadBackup() {
  get('prebackup', 'old').then(v => {
    if (!v) return;
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([v], { type: 'application/json' }));
    a.download = 'dhadda-web-backup.json'; a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  });
}

async function connect(link) {
  const m = link.match(/[#&]v=([^&]+).*[#&]t=([^&]+).*[#&]k=([^&\s]+)/);
  if (!m) throw new Error('Invalid link');
  vaultId = decodeURIComponent(m[1]); token = decodeURIComponent(m[2]);
  const rawKey = decodeURIComponent(m[3]);
  key = await importKey(rawKey);
  await storeKey(rawKey);
  await clear('outbox');
  lastSeq = 0;
  await saveMeta();
  setStatus('Connecting');
  await pull();
  return true;
}

async function firstPullProgress(onProgress) {
  const res = await request(`/v1/pull?since=0&limit=500`);
  let seen = 0;
  for (const w of res.rows) { await mergeWire(w); seen++; onProgress(seen, res.total || res.rows.length); }
  if (res.next > lastSeq) { lastSeq = res.next; await saveMeta(); }
  return seen;
}

async function init(h) {
  hooks = { ...hooks, ...h };
  db = await openDB();
  vaultId = await get('meta', 'vault_id');
  token = await get('meta', 'token');
  lastSeq = (await get('meta', 'last_seq')) || 0;
  lastSync = (await get('meta', 'last_sync')) || 0;
  const rawKey = await get('meta', 'key');
  if (vaultId && token && rawKey) key = await importKey(rawKey);

  const frag = location.hash;
  if (frag.includes('v=') && frag.includes('t=') && frag.includes('k=')) {
    const link = location.href;
    const saved = await exportOldBackup();
    await connect(link);
    history.replaceState(null, '', location.pathname + location.search);
    if (saved) h.onBackupAvailable?.();
    return true;
  }
  if (key) {
    counts.rows = (await all('rows')).length;
    counts.pending = (await all('outbox')).length;
    setStatus(lastSync ? `Synced ${Math.round((now()-lastSync)/60000)} min ago` : 'Not connected');
    startPolling();
    setTimeout(pull, 0);
  }
  return !!key;
}

async function storeKey(b64) { await put('meta', 'key', b64); }

async function setLocal(t, id, data, deleted = 0) {
  const k = rowKey(t, id);
  const ua = hybridUa();
  if (deleted) await del('rows', k);
  else await put('rows', k, { t, id, data, ua, d: 0, device_id: deviceId });
  await put('outbox', k, { t, id, data, ua, d: deleted });
  schedulePush();
}

async function getAll() {
  const rows = await all('rows');
  const out = {};
  for (const r of rows) {
    const group = keyPath(r.t);
    (out[group] ||= []).push({ ...r.data, id: r.id, ...(r.d ? { _deleted: 1 } : {}) });
  }
  return out;
}

window.DhaddaSync = {
  init, connect, isPaired: () => !!key, getAll, setLocal, push, pull,
  status: () => status, counts: () => counts, lastError: () => lastError, inFlight: () => inFlight, downloadBackup,
  setKeyForTest: async b64 => { key = await importKey(b64); await storeKey(b64); },
  getMeta: async () => ({ vaultId, token, lastSeq, lastSync }),
  firstPullProgress,
  setWorker: url => { window.DHADDA_SYNC_URL = url; },
};
})();
