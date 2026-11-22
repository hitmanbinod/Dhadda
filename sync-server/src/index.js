// Dhadda sync Worker. Stores only {t,id,ua,d,iv,ct,seq} per vault.
// No secrets in source; no request bodies are logged.

const MAX_BODY = 512 * 1024;
const MAX_ROWS = 500;
const MAX_LIMIT = 500;
const TOMBSTONE_DAYS = 180;

const enc = new TextEncoder();

function cors(env, request) {
  const origin = env.ALLOWED_ORIGIN || '';
  const h = {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
    'Cache-Control': 'no-store',
  };
  // Local wrangler dev has no Pages origin; allow same-origin there only.
  if (new URL(request.url).hostname === '127.0.0.1' && !origin) {
    h['Access-Control-Allow-Origin'] = '*';
  }
  return h;
}

function reply(env, request, body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(env, request), 'Content-Type': 'application/json' },
  });
}

function err(env, request, message, status = 400) {
  return reply(env, request, { error: message }, status);
}

async function sha256Hex(text) {
  const d = await crypto.subtle.digest('SHA-256', enc.encode(text));
  return [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, '0')).join('');
}

function constantTimeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function token() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return [...bytes].map(b => b.toString(16).padStart(2, '0')).join('');
}

async function body(req) {
  const len = Number(req.headers.get('Content-Length') || 0);
  if (len > MAX_BODY) return null;
  const text = await req.text();
  if (enc.encode(text).byteLength > MAX_BODY) return null;
  try { return JSON.parse(text || '{}'); } catch { return null; }
}

async function auth(env, request) {
  const header = request.headers.get('Authorization') || '';
  if (!header.startsWith('Bearer ')) return null;
  const hash = await sha256Hex(header.slice(7).trim());
  const row = await env.DB.prepare('SELECT vault_id, token_hash FROM vaults WHERE token_hash = ?').bind(hash).first();
  if (!row || !constantTimeEqual(row.token_hash, hash)) return null;
  return row.vault_id;
}

// Per-vault in-memory sliding window. An isolate-local limit is sufficient
// for one user; D1-level accounting is unnecessary at this scale.
const hits = new Map();
function rateLimit(vaultId) {
  const now = Date.now();
  const arr = (hits.get(vaultId) || []).filter(t => now - t < 60000);
  if (arr.length >= 120) return false;
  arr.push(now);
  hits.set(vaultId, arr);
  return true;
}

function validRow(r) {
  return r && typeof r === 'object' &&
    typeof r.t === 'string' && r.t.length > 0 && r.t.length <= 32 &&
    typeof r.id === 'string' && r.id.length > 0 && r.id.length <= 128 &&
    Number.isFinite(r.ua) && r.ua >= 0 &&
    (r.d === 0 || r.d === 1) &&
    typeof r.device_id === 'string' && r.device_id.length <= 64 &&
    typeof r.iv === 'string' && r.iv.length <= 64 &&
    typeof r.ct === 'string' && r.ct.length <= 2 * 1024 * 1024;
}

function incomingWins(incoming, current) {
  if (!current) return true;
  if (incoming.ua !== current.ua) return incoming.ua > current.ua;
  return incoming.device_id > current.device_id;
}

function wire(r) {
  return { t: r.t, id: r.id, ua: r.ua, d: r.d, device_id: r.device_id, iv: r.iv, ct: r.ct, seq: r.seq };
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') return new Response(null, { headers: cors(env, request) });
    try {
      if (request.method === 'POST' && url.pathname === '/v1/vault') {
        const vaultId = crypto.randomUUID();
        const tok = token();
        const hash = await sha256Hex(tok);
        await env.DB.prepare('INSERT INTO vaults (vault_id, token_hash, created_at, last_seq) VALUES (?, ?, ?, 0)')
          .bind(vaultId, hash, Date.now()).run();
        return reply(env, request, { vault_id: vaultId, token: tok }, 201);
      }

      const vaultId = await auth(env, request);
      if (!vaultId) return err(env, request, 'unauthorized', 401);
      if (!rateLimit(vaultId)) return err(env, request, 'rate limited', 429);

      if (request.method === 'POST' && url.pathname === '/v1/push') {
        const b = await body(request);
        if (!b || !Array.isArray(b.rows)) return err(env, request, 'invalid body');
        if (b.rows.length > MAX_ROWS) return err(env, request, 'too many rows');
        for (const r of b.rows) if (!validRow(r)) return err(env, request, 'invalid row');

        let accepted = 0, seq = 0, lastSeq = 0;
        const vault = await env.DB.prepare('SELECT last_seq FROM vaults WHERE vault_id = ?').bind(vaultId).first();
        lastSeq = vault ? vault.last_seq : 0;

        for (const r of b.rows) {
          const current = await env.DB.prepare('SELECT * FROM rows WHERE vault_id = ? AND t = ? AND id = ?')
            .bind(vaultId, r.t, r.id).first();
          if (!incomingWins(r, current) &&
              !(current && r.ua === current.ua && r.device_id === current.device_id && r.d === current.d)) continue;
          if (current && r.ua === current.ua && r.device_id === current.device_id && r.d === current.d) {
            seq = current.seq;
          } else {
            seq = ++lastSeq;
            await env.DB.prepare(
              'INSERT INTO rows (vault_id,t,id,ua,d,device_id,iv,ct,seq,pushed_at) VALUES (?,?,?,?,?,?,?,?,?,?) ' +
              'ON CONFLICT(vault_id,t,id) DO UPDATE SET ua=excluded.ua,d=excluded.d,device_id=excluded.device_id,' +
              'iv=excluded.iv,ct=excluded.ct,seq=excluded.seq,pushed_at=excluded.pushed_at'
            ).bind(vaultId, r.t, r.id, r.ua, r.d, r.device_id, r.iv, r.ct, seq, Date.now()).run();
            accepted++;
          }
        }
        if (lastSeq !== (vault ? vault.last_seq : 0)) {
          await env.DB.prepare('UPDATE vaults SET last_seq = ? WHERE vault_id = ?').bind(lastSeq, vaultId).run();
        }
        return reply(env, request, { accepted, rejected_older: [], server_seq: lastSeq });
      }

      if (request.method === 'GET' && url.pathname === '/v1/pull') {
        const since = Math.max(0, Number(url.searchParams.get('since') || 0) || 0);
        const limit = Math.min(MAX_LIMIT, Math.max(1, Number(url.searchParams.get('limit') || MAX_LIMIT) || MAX_LIMIT));
        const rows = await env.DB.prepare('SELECT * FROM rows WHERE vault_id = ? AND seq > ? ORDER BY seq ASC LIMIT ?')
          .bind(vaultId, since, limit + 1).all();
        const more = rows.results.length > limit;
        const page = more ? rows.results.slice(0, limit) : rows.results;
        const total = await env.DB.prepare('SELECT COUNT(*) AS n FROM rows WHERE vault_id = ?').bind(vaultId).first();
        return reply(env, request, {
          rows: page.map(wire),
          next: page.length ? page[page.length - 1].seq : since,
          more,
          total: total ? total.n : 0,
        });
      }

      if (request.method === 'POST' && url.pathname === '/v1/rotate') {
        const tok = token();
        const hash = await sha256Hex(tok);
        await env.DB.prepare('UPDATE vaults SET token_hash = ? WHERE vault_id = ?').bind(hash, vaultId).run();
        return reply(env, request, { vault_id: vaultId, token: tok });
      }

      if (request.method === 'DELETE' && url.pathname === '/v1/vault') {
        await env.DB.prepare('DELETE FROM rows WHERE vault_id = ?').bind(vaultId).run();
        await env.DB.prepare('DELETE FROM vaults WHERE vault_id = ?').bind(vaultId).run();
        return reply(env, request, { deleted: true });
      }

      return err(env, request, 'not found', 404);
    } catch (e) {
      // Never log request bodies or tokens. A generic message is enough.
      return err(env, request, 'server error', 500);
    }
  },
};
