// Dhadda LAN remote store. Same window.DhaddaSync interface as the shelved
// cloud engine, but the phone is the source of truth and nothing is uploaded.
import * as C from './lan-crypto.js';

const DB = 'dhadda-lan';
const TRUST_STORE = 'trust';
const TRUST_KEY = 'device';
const SESSION_KEY = 'dhadda-lan-session';
const TRUST_DAYS = 30;
const IDLE_MS = 12 * 60 * 60 * 1000;

let api = location.origin;
let hooks = {};
let session = null; // {sid,key,deviceId,deviceSecret,expires,trusted,counters}
let rows = new Map();
let status = 'Not connected';
let lastError = '';
let inFlight = 0;
let socket = null;
let pollTimer = null;
let reconnectTimer = null;
let reconnectDelay = 1000;
let pendingQr = null;

const groupOf = t => ({
  cat: 'categories', txn: 'transactions', proj: 'projects',
  loan: 'loans', settings: 'settings',
}[t] || null);
const outboundType = t => ({
  categories: 'cat', entries: 'txn', events: 'proj',
  people: 'loan', settings: 'settings',
}[t] || t);

function setStatus(s) {
  status = s;
  hooks.onStatus?.(s);
}
function openDB() {
  return new Promise((res, rej) => {
    const r = indexedDB.open(DB, 1);
    r.onupgradeneeded = () => r.result.createObjectStore(TRUST_STORE);
    r.onsuccess = () => res(r.result);
    r.onerror = () => rej(r.error);
  });
}
async function idbGet(key) {
  const db = await openDB();
  return new Promise((res, rej) => {
    const r = db.transaction(TRUST_STORE).objectStore(TRUST_STORE).get(key);
    r.onsuccess = () => res(r.result);
    r.onerror = () => rej(r.error);
  });
}
async function idbSet(key, value) {
  const db = await openDB();
  return new Promise((res, rej) => {
    const r = db.transaction(TRUST_STORE, 'readwrite').objectStore(TRUST_STORE).put(value, key);
    r.onsuccess = () => res();
    r.onerror = () => rej(r.error);
  });
}
async function idbDel(key) {
  const db = await openDB();
  return new Promise((res, rej) => {
    const r = db.transaction(TRUST_STORE, 'readwrite').objectStore(TRUST_STORE).delete(key);
    r.onsuccess = () => res();
    r.onerror = () => rej(r.error);
  });
}

async function post(path, body) {
  const res = await fetch(api + path, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let parsed = {};
  try { parsed = JSON.parse(text); } catch { /* plain text */ }
  if (!res.ok) {
    const e = new Error(parsed.error || ('HTTP ' + res.status));
    e.status = res.status;
    throw e;
  }
  return parsed;
}
async function get(path) {
  const res = await fetch(api + path);
  const parsed = await res.json();
  if (!res.ok) throw new Error(parsed.error || ('HTTP ' + res.status));
  return parsed;
}

async function envelope(path, payload) {
  if (!session) throw new Error('Not connected');
  const n = ++session.pcCounter;
  const ct = C.seal(session.key, C.nonce(C.DIR_PC_TO_PHONE, n),
    C.aad(session.sid, C.DIR_PC_TO_PHONE, n), C.utf8(JSON.stringify(payload)));
  return post(path, { sid: session.sid, n, ct: C.hex(ct) });
}
async function openEnvelope(reply) {
  const n = reply.n;
  const plain = C.open(session.key, C.nonce(C.DIR_PHONE_TO_PC, n),
    C.aad(session.sid, C.DIR_PHONE_TO_PC, n), C.unhex(reply.ct));
  return JSON.parse(C.text(plain));
}

function ingest(rowsIn) {
  let changed = false;
  for (const r of rowsIn || []) {
    const t = r.t, id = r.id;
    if (!t || !id) continue;
    const key = t + '/' + id;
    const prev = rows.get(key);
    const ua = Number(r.ua) || 0;
    if (prev && prev.ua >= ua) continue;
    rows.set(key, { ...r, ua, _deleted: r.d === 1 });
    changed = true;
  }
  if (changed) hooks.onData?.();
}

function buildOutput() {
  const out = { categories: [], transactions: [], loans: [], projects: [], settings: [] };
  const loanChildren = [];
  for (const r of rows.values()) {
    if (r._deleted) continue;
    const g = groupOf(r.t);
    if (!g) continue;
    const item = { ...(r.data || {}), id: r.id };
    if (r.t === 'topup' || r.t === 'repay') {
      loanChildren.push({ ...item, kind: r.t, parent: r.parent });
      continue;
    }
    if (r.t === 'settings') out.settings.push({ id: r.id, value: item.value });
    else out[g].push(item);
  }
  for (const child of loanChildren) {
    const loan = out.loans.find(l => l.id === child.parent);
    if (!loan) continue;
    const bucket = child.kind === 'topup' ? 'topups' : 'repayments';
    (loan[bucket] ||= []).push(child);
  }
  return out;
}

async function pull() {
  if (!session) return 0;
  inFlight++;
  setStatus('Syncing…');
  try {
    const reply = await envelope('/api/snapshot', { get: 'rows' });
    const body = await openEnvelope(reply);
    ingest(body.rows);
    session.lastSeen = Date.now();
    setStatus(session.trusted ? 'Live · this phone' : 'Live');
    return (body.rows || []).length;
  } catch (e) {
    lastError = e.message;
    setStatus('Phone not reachable');
    scheduleReconnect();
    return 0;
  } finally {
    inFlight--;
  }
}

async function push() {
  if (!session || !rows.size) return 0;
  inFlight++;
  try {
    const queued = [...rows.values()].filter(r => r._outbox);
    if (!queued.length) return 0;
    const wireRows = queued.map(r => ({
      t: r.t, id: r.id, ua: r.ua, d: r._deleted ? 1 : 0,
      device_id: session.deviceId || 'web',
      data: r.data || {}, ...(r.parent ? { parent: r.parent } : {}),
    }));
    const reply = await envelope('/api/push', { rows: wireRows });
    await openEnvelope(reply);
    for (const r of queued) r._outbox = false;
    return queued.length;
  } catch (e) {
    lastError = e.message;
    setStatus('Phone not reachable');
    scheduleReconnect();
    return 0;
  } finally {
    inFlight--;
  }
}

async function connectSocket() {
  if (!session || socket) return;
  try {
    socket = new WebSocket(`${api.replace(/^http/, 'ws')}/api/events?sid=${encodeURIComponent(session.sid)}`);
    socket.onopen = () => { reconnectDelay = 1000; setStatus('Live'); };
    socket.onmessage = async (ev) => {
      try {
        const frame = JSON.parse(ev.data);
        const body = await openEnvelope(frame);
        if (body.changed) ingest(body.changed);
      } catch { /* ignore a bad frame; next one still works */ }
    };
    socket.onclose = () => {
      socket = null;
      setStatus('Reconnecting…');
      scheduleReconnect();
    };
    socket.onerror = () => socket?.close();
  } catch { scheduleReconnect(); }
}

function scheduleReconnect() {
  clearTimeout(reconnectTimer);
  reconnectTimer = setTimeout(async () => {
    if (!session) return;
    if (Date.now() - (session.lastSeen || 0) > IDLE_MS) {
      endSession('Session expired');
      return;
    }
    reconnectDelay = Math.min(reconnectDelay * 2, 5000);
    await trustedReconnect().catch(() => pull());
    connectSocket();
  }, reconnectDelay);
}

function rememberSession(s, trust) {
  session = s;
  if (trust && s.deviceId && s.deviceSecret) {
    idbSet(TRUST_KEY, {
      id: s.deviceId, secret: C.hex(s.deviceSecret), expires: s.expires,
    });
  } else {
    try { sessionStorage.setItem(SESSION_KEY, JSON.stringify({
      sid: s.sid, key: C.hex(s.key), expires: s.expires,
    })); } catch { /* sessionStorage may be unavailable */ }
  }
}
function endSession(message) {
  clearTimeout(pollTimer);
  clearTimeout(reconnectTimer);
  try { socket?.close(); } catch { /* ignore */ }
  socket = null;
  session = null;
  setStatus(message);
}

async function completePairing(hello, result, z, t, trust, name) {
  if (!C.constantTimeEquals(
    C.unhex(result.proof_phone),
    C.proof(hello.qrKey || hello.codeKey, 'phone', t))) {
    throw new Error('The phone could not be verified.');
  }
  const key = C.sessionKey(z, t);
  const s = {
    sid: result.sid || hello.sid,
    key, trusted: !!trust, deviceId: null, deviceSecret: null,
    expires: Date.now() + IDLE_MS, lastSeen: Date.now(), pcCounter: 0,
  };
  if (result.secret) {
    const frame = result.secret;
    const plain = C.open(key, C.nonce(C.DIR_PHONE_TO_PC, frame.n),
      C.aad(s.sid, C.DIR_PHONE_TO_PC, frame.n), C.unhex(frame.ct));
    const body = JSON.parse(C.text(plain));
    s.deviceId = body.device_id;
    s.deviceSecret = C.unhex(body.device_secret);
    s.expires = Date.parse(body.expires);
  }
  rememberSession(s, trust);
  await pull();
  connectSocket();
  return true;
}

async function trustedReconnect() {
  const saved = await idbGet(TRUST_KEY);
  if (!saved || !saved.id || Date.now() > Date.parse(saved.expires || 0)) {
    throw new Error('This computer was removed, pair again');
  }
  const epc = C.randomBytes(32);
  const h = await post('/session/hello', { device_id: saved.id, epc: C.hex(epc) });
  const ephone = C.unhex(h.ephone);
  const nonce = C.unhex(h.nonce);
  const epcPub = C.x25519Public(epc);
  const t = C.trustedTranscript(epcPub, ephone, nonce);
  const secret = C.unhex(saved.secret);
  const c = await post('/session/confirm', {
    device_id: saved.id,
    proof_pc: C.hex(C.proof(secret, 'pc', t, nonce)),
  });
  if (!C.constantTimeEquals(C.unhex(c.proof_phone),
      C.proof(secret, 'phone', t, nonce))) throw new Error('Phone verification failed');
  const z = C.x25519Shared(epc, ephone);
  const s = {
    sid: saved.id, key: C.trustedSessionKey(z, t, secret),
    trusted: true, deviceId: saved.id, deviceSecret: secret,
    expires: Date.parse(saved.expires), lastSeen: Date.now(), pcCounter: 0,
  };
  session = s;
  return true;
}

/* ---------------- public interface (same shape as before) ---------------- */

async function init(h) {
  hooks = h || {};
  const saved = await idbGet(TRUST_KEY).catch(() => null);
  if (!saved || Date.now() > Date.parse(saved.expires || 0)) return false;
  try {
    await trustedReconnect();
    await pull();
    connectSocket();
    return true;
  } catch (e) {
    lastError = e.message;
    return false;
  }
}

async function connectCode(code, trust, name) {
  const normalized = C.normalizeCode(code);
  const epc = C.randomBytes(32);
  const epcPub = C.x25519Public(epc);
  const h = await post('/pair/hello', {
    epc: C.hex(epcPub), name: name || 'Chrome on this computer', trust: !!trust,
  });
  const ephone = C.unhex(h.ephone);
  const z = C.x25519Shared(epc, ephone);
  const t = C.transcript(epcPub, ephone, h.sid);
  const codeKey = C.codeKey(normalized, t);
  setStatus('Waiting for approval on the phone…');
  const result = await post('/pair/confirm', {
    sid: h.sid, proof: C.hex(C.proof(codeKey, 'pc', t)),
  });
  return completePairing({ ...h, codeKey }, result, z, t, trust, name);
}

async function beginQr(trust, name) {
  const epc = C.randomBytes(32);
  const epcPub = C.x25519Public(epc);
  const h = await post('/pair/hello', {
    epc: C.hex(epcPub), name: name || 'Chrome on this computer',
    trust: !!trust, mode: 'qr',
  });
  const ephone = C.unhex(h.ephone);
  const s = C.unhex(h.s);
  const t = C.transcript(epcPub, ephone, h.sid);
  const qrKey = C.qrKey(s, t);
  pendingQr = {
    sid: h.sid, epc, epcPub, ephone, s, z: C.x25519Shared(epc, ephone),
    t, trust, qrKey,
  };
  const qr = { v: 1, sid: h.sid, epc: C.hex(epcPub), s: C.hex(s) };
  return { qr: JSON.stringify(qr), text: 'On your phone tap Scan computer’s QR' };
}

async function pollQr() {
  if (!pendingQr) throw new Error('Start a QR pairing first');
  const p = pendingQr;
  const r = await get('/pair/poll?sid=' + encodeURIComponent(p.sid) +
    '&epc=' + encodeURIComponent(C.hex(p.epcPub)));
  if (r.status === 'waiting') return false;
  const result = await completePairing({ ...p, qrKey: p.qrKey }, r, p.z, p.t, p.trust);
  pendingQr = null;
  return true;
}

async function getAll() {
  if (session) await pull();
  return buildOutput();
}
async function setLocal(t, id, data, deleted = 0) {
  if (!session) return;
  const type = outboundType(t);
  const key = type + '/' + id;
  const ua = Date.now();
  rows.set(key, {
    t: type, id, ua, d: deleted, data, device_id: session.deviceId || 'web',
    _deleted: !!deleted, _outbox: true,
  });
  await push();
}
async function forget() {
  if (session?.deviceId) await post('/pair/forget', { device_id: session.deviceId }).catch(() => {});
  await idbDel(TRUST_KEY);
  endSession('Disconnected');
  rows = new Map();
  hooks.onData?.();
}
function downloadBackup() {
  const blob = new Blob([JSON.stringify(buildOutput(), null, 2)],
    { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'dhadda-web-backup.json';
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

window.DhaddaSync = {
  init, connect: connectCode, connectCode, beginQr, pollQr,
  isPaired: () => !!session,
  getAll, setLocal, push, pull, forget, endSession,
  status: () => status,
  counts: () => ({ categories: rows.size }),
  lastError: () => lastError,
  inFlight: () => inFlight,
  downloadBackup,
  getMeta: async () => ({ sid: session?.sid || '', deviceId: session?.deviceId || '' }),
  firstPullProgress: async () => ({ done: true }),
  setWorker: url => { api = url.replace(/\/$/, ''); },
};
