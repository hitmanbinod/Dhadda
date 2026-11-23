// Cross-language interop: the *web client's* real crypto module drives a live
// Dart LanServer on loopback (pairing, snapshot, push, replay, trusted reconnect).
// Phase 1 vector check is included as a prerequisite.
// Run: node scripts/lan-simulate.mjs
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import * as L from '../webapp/lan-crypto.js';

await import('./lan-vectors.mjs');

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
// Windows exposes dart.bat on PATH, which Node cannot spawn; use flutter's
// dart.exe directly unless the caller supplies DART_EXE.
const guessedDart = path.join(process.env.USERPROFILE ?? '',
  'flutter', 'bin', 'cache', 'dart-sdk', 'bin', 'dart.exe');
const dartExe = process.env.DART_EXE ||
  (process.platform === 'win32' && existsSync(guessedDart) ? guessedDart : 'dart');
const port = 18765 + Math.floor(Math.random() * 500);
const child = spawn(dartExe, ['run', 'tool/lan_test_server.dart'], {
  cwd: root,
  env: { ...process.env, LAN_TEST_PORT: String(port) },
  stdio: ['pipe', 'pipe', 'pipe'],
});
let stderr = '';
child.stderr.on('data', d => { stderr += d; });

const base = await new Promise((resolve, reject) => {
  let buf = '';
  const timer = setTimeout(() => reject(new Error('test server did not start: ' + stderr)), 60000);
  child.stdout.on('data', d => {
    buf += d;
    const line = buf.split('\n').find(x => x.startsWith('READY '));
    if (line) { clearTimeout(timer); resolve(line.slice(6).trim()); }
  });
  child.on('exit', code => { clearTimeout(timer); reject(new Error('server exited ' + code + ': ' + stderr)); });
});

async function call(method, urlPath, body) {
  const res = await fetch(base + urlPath, {
    method,
    headers: body ? { 'content-type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let parsed = {};
  try { parsed = JSON.parse(text); } catch { /* plain text */ }
  return { status: res.status, body: parsed };
}

async function sealed(sid, key, n, payload) {
  return {
    sid,
    n,
    ct: L.hex(L.seal(key, L.nonce(L.DIR_PC_TO_PHONE, n),
      L.aad(sid, L.DIR_PC_TO_PHONE, n), L.utf8(JSON.stringify(payload)))),
  };
}

async function opened(reply, sid, key) {
  assert.equal(reply.status, 200, JSON.stringify(reply.body));
  const n = reply.body.n;
  const plain = L.open(key, L.nonce(L.DIR_PHONE_TO_PC, n),
    L.aad(sid, L.DIR_PHONE_TO_PC, n), L.unhex(reply.body.ct));
  return JSON.parse(L.text(plain));
}

try {
  const code = (await call('GET', '/test/code')).body.code;
  assert.match(code, /^[A-HJ-NP-Z2-9]{8}$/);

  const epcPriv = L.randomBytes(32);
  const epcPub = L.x25519Public(epcPriv);
  const hello = await call('POST', '/pair/hello', {
    epc: L.hex(epcPub), name: 'Chrome on Windows', trust: true,
  });
  assert.equal(hello.status, 200);
  const { sid, ephone: ephoneHex } = hello.body;
  const ephone = L.unhex(ephoneHex);
  const z = L.x25519Shared(epcPriv, ephone);
  const t = L.transcript(epcPub, ephone, sid);
  const key = L.codeKey(code, t);
  const proof = L.proof(key, 'pc', t);

  const confirming = call('POST', '/pair/confirm', { sid, proof: L.hex(proof) });
  await call('POST', '/test/approve', { sid }); // scan/Allow equivalent
  const confirmed = await confirming;
  assert.equal(confirmed.status, 200, JSON.stringify(confirmed.body));
  assert.deepEqual(L.unhex(confirmed.body.proof_phone), L.proof(key, 'phone', t));

  const sessionKey = L.sessionKey(z, t);
  const secretFrame = confirmed.body.secret;
  const secretBody = await opened({ status: 200, body: secretFrame }, sid, sessionKey);
  const deviceId = secretBody.device_id;
  const deviceSecret = L.unhex(secretBody.device_secret);
  assert.match(deviceId, /^dev-/);

  const snap = await call('POST', '/api/snapshot',
    await sealed(sid, sessionKey, 1, { get: 'rows' }));
  assert.deepEqual((await opened(snap, sid, sessionKey)).rows, []);

  const row = { t: 'entries', id: 'node-txn', ua: 1, d: 0, data: { amount: 42 } };
  const push = await call('POST', '/api/push',
    await sealed(sid, sessionKey, 2, { rows: [row] }));
  assert.equal((await opened(push, sid, sessionKey)).ok, true);

  const replay = await call('POST', '/api/snapshot',
    await sealed(sid, sessionKey, 1, { get: 'rows' }));
  assert.equal(replay.status, 403, 'replay must be rejected');

  const epc2 = L.randomBytes(32);
  const epcPub2 = L.x25519Public(epc2);
  const hello2 = L.trustedHello(deviceId, epc2);
  assert.equal(hello2.epc, L.hex(epcPub2), 'hello must carry the public key');
  const rehello = await call('POST', '/session/hello', hello2);
  assert.equal(rehello.status, 200);
  const ephone2 = L.unhex(rehello.body.ephone);
  const nonce = L.unhex(rehello.body.nonce);
  const t2 = L.trustedTranscript(epcPub2, ephone2, nonce);
  const reconfirm = await call('POST', '/session/confirm', {
    device_id: deviceId,
    proof_pc: L.hex(L.proof(deviceSecret, 'pc', t2, nonce)),
  });
  assert.equal(reconfirm.status, 200);
  assert.deepEqual(L.unhex(reconfirm.body.proof_phone),
    L.proof(deviceSecret, 'phone', t2, nonce));

  console.log('lan-simulate: web client paired, synced, pushed, rejected a replay and reconnected to the Dart server');
} finally {
  child.stdin.end();
  const stopped = new Promise(resolve => child.once('exit', resolve));
  setTimeout(() => child.kill(), 5000).unref();
  await stopped;
}
