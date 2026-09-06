const http = require("http");
const fs = require("fs");
const os = require("os");
const path = require("path");
const root = process.argv[2];
const port = +(process.argv[3] || 8080);

// This machine's LAN address, so QR codes never contain "localhost"
// (which only works on the PC itself, never on the phone).
function lanOrigin(req) {
  const ips = [];
  for (const nets of Object.values(os.networkInterfaces())) {
    for (const a of nets || []) {
      if (a.family !== "IPv4" || a.internal) continue;
      ips.push(a.address);
    }
  }
  const pick = (fn) => ips.find(fn) || "";
  const ip = pick((s) => s.startsWith("192.168.")) ||
    pick((s) => s.startsWith("10.")) ||
    pick((s) => s.startsWith("172.")) || ips[0] || "";
  const host = (req && req.headers && req.headers.host) || "";
  const p = host.includes(":") ? host.split(":").pop() : String(port);
  return ip ? "http://" + ip + ":" + p : "";
}

// Crash diagnostics: never die silently (log file sits next to this script).
process.on("uncaughtException", (e) => {
  try { fs.appendFileSync(__dirname + "/serve-expense.crash.log", new Date().toISOString() + " UNCAUGHT " + (e && e.stack || e) + "\n"); } catch (_) {}
  process.exit(1);
});
process.on("unhandledRejection", (e) => {
  try { fs.appendFileSync(__dirname + "/serve-expense.crash.log", new Date().toISOString() + " UNHANDLED " + (e && e.stack || e) + "\n"); } catch (_) {}
  process.exit(1);
});

// ---- LAN sync relay (in-memory, $0, never leaves your network) ----
// Desktop shows a code -> phone scans it -> both devices sync.
// Sessions auto-expire after 5 minutes. PIN checked on every call.
const sessions = new Map(); // id -> {pin, offer:{snapshot,name,time}, answer:null|{...}, created}
// Persistent link mailboxes: pair once by scan, then both devices push
// their latest snapshot and pull the other's. 7-day sliding TTL.
const links = new Map(); // id -> {pin, slots: {deviceId: {snapshot,name,time}}, created, touched}
const LINK_TTL_MS = 7 * 24 * 3600 * 1000;
const lid = () => { let id = nid() + nid().substring(0, 2); while (links.has(id)) id = nid() + nid().substring(0, 2); return id; };
const ABC = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const nid = () => Array.from({length: 6}, () => ABC[Math.floor(Math.random() * ABC.length)]).join("");
const TTL_MS = 5 * 60 * 1000;
setInterval(() => {
  const now = Date.now();
  for (const [id, s] of sessions) if (now - s.created > TTL_MS) sessions.delete(id);
  for (const [id, l] of links) if (now - l.touched > LINK_TTL_MS) links.delete(id);
}, 60000).unref();

function readJson(req, max) {
  max = max || 6 * 1024 * 1024;
  return new Promise((resolve, reject) => {
    let n = 0; const chunks = [];
    req.on("data", (c) => {
      n += c.length;
      if (n > max) { reject(Object.assign(new Error("too big"), {code: 413})); req.destroy(); }
      else chunks.push(c);
    });
    req.on("end", () => {
      try { resolve(JSON.parse(Buffer.concat(chunks).toString("utf8"))); }
      catch (e) { reject(Object.assign(new Error("bad json"), {code: 400})); }
    });
    req.on("error", reject);
  });
}
function send(res, code, obj) {
  const b = Buffer.from(JSON.stringify(obj));
  res.writeHead(code, {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*", "Content-Length": b.length});
  res.end(b);
}
function apiSend(res, code, obj) { send(res, code, obj); return true; }
function getSession(id) {
  const s = sessions.get(id);
  if (!s) return null;
  if (Date.now() - s.created > TTL_MS) { sessions.delete(id); return null; }
  return s;
}
async function api(req, res) {
  const u = new URL(req.url, "http://x");
  if (req.method === "OPTIONS" && u.pathname.startsWith("/api/")) {
    res.writeHead(204, {"Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "Content-Type", "Access-Control-Allow-Methods": "GET, POST, OPTIONS"});
    res.end(); return true;
  }
  if (req.method === "POST" && u.pathname === "/api/sync/offer") {
    const b = await readJson(req);
    if (typeof b.pin !== "string" || b.pin.length < 4 || b.pin.length > 12) return apiSend(res, 400, {error: "bad pin"});
    if (typeof b.snapshot !== "string" || !b.snapshot.length) return apiSend(res, 400, {error: "bad snapshot"});
    if (sessions.size >= 20) { const oldest = [...sessions.entries()].sort((a, c) => a[1].created - c[1].created)[0]; sessions.delete(oldest[0]); }
    let id = nid(); while (sessions.has(id)) id = nid();
    sessions.set(id, {pin: b.pin, offer: {snapshot: b.snapshot, name: String(b.name || "device"), time: String(b.time || "")}, answer: null, created: Date.now()});
    return apiSend(res, 200, {session: id, origin: lanOrigin(req)});
  }
  if (req.method === "GET" && u.pathname === "/api/sync/session") {
    const s = getSession(u.searchParams.get("id") || "");
    if (!s) return apiSend(res, 404, {error: "expired"});
    if (u.searchParams.get("pin") !== s.pin) return apiSend(res, 403, {error: "wrong pin"});
    return apiSend(res, 200, {stage: s.answer ? "done" : "waiting", offer: s.offer, answer: s.answer});
  }
  if (req.method === "POST" && u.pathname === "/api/sync/answer") {
    const b = await readJson(req);
    const s = getSession(b.session || "");
    if (!s) return apiSend(res, 404, {error: "expired"});
    if (b.pin !== s.pin) return apiSend(res, 403, {error: "wrong pin"});
    if (s.answer) return apiSend(res, 410, {error: "already answered"});
    s.answer = {snapshot: typeof b.snapshot === "string" ? b.snapshot : null, name: String(b.name || "device"), time: String(b.time || "")};
    return apiSend(res, 200, {ok: true});
  }
  if (req.method === "POST" && u.pathname === "/api/sync/link") {
    const b = await readJson(req);
    if (typeof b.pin !== "string" || b.pin.length < 4 || b.pin.length > 12) return apiSend(res, 400, {error: "bad pin"});
    if (typeof b.snapshot !== "string" || !b.snapshot.length) return apiSend(res, 400, {error: "bad snapshot"});
    if (typeof b.deviceId !== "string" || !b.deviceId.length) return apiSend(res, 400, {error: "bad device"});
    if (links.size >= 50) { const oldest = [...links.entries()].sort((a, c) => a[1].touched - c[1].touched)[0]; links.delete(oldest[0]); }
    const id = lid();
    const slot = {snapshot: b.snapshot, name: String(b.name || "device"), time: String(b.time || "")};
    const now = Date.now();
    links.set(id, {pin: b.pin, slots: {[b.deviceId]: slot}, created: now, touched: now});
    return apiSend(res, 200, {link: id, origin: lanOrigin(req)});
  }
  if (req.method === "POST" && u.pathname === "/api/sync/push") {
    const b = await readJson(req);
    const l = links.get(b.link || "");
    if (!l || Date.now() - l.touched > LINK_TTL_MS) { links.delete(b.link || ""); return apiSend(res, 404, {error: "link gone - pair again"}); }
    if (b.pin !== l.pin) return apiSend(res, 403, {error: "wrong pin"});
    if (typeof b.deviceId !== "string" || !b.deviceId.length) return apiSend(res, 400, {error: "bad device"});
    if (typeof b.snapshot !== "string" || !b.snapshot.length) return apiSend(res, 400, {error: "bad snapshot"});
    l.slots[b.deviceId] = {snapshot: b.snapshot, name: String(b.name || "device"), time: String(b.time || "")};
    l.touched = Date.now();
    return apiSend(res, 200, {ok: true});
  }
  if (req.method === "GET" && u.pathname === "/api/sync/pull") {
    const l = links.get(u.searchParams.get("link") || "");
    if (!l || Date.now() - l.touched > LINK_TTL_MS) { links.delete(u.searchParams.get("link") || ""); return apiSend(res, 404, {error: "link gone - pair again"}); }
    if (u.searchParams.get("pin") !== l.pin) return apiSend(res, 403, {error: "wrong pin"});
    l.touched = Date.now();
    const me = u.searchParams.get("deviceId") || "";
    const peers = Object.entries(l.slots)
      .filter(([id]) => id !== me)
      .map(([deviceId, s]) => ({deviceId, snapshot: s.snapshot, name: s.name, time: s.time}));
    return apiSend(res, 200, {peers});
  }
  if (req.method === "POST" && u.pathname === "/api/sync/unlink") {
    const b = await readJson(req).catch(() => ({}));
    const l = links.get(b.link || "");
    if (l && b.pin === l.pin) links.delete(b.link);
    return apiSend(res, 200, {ok: true});
  }
  if (req.method === "POST" && u.pathname === "/api/sync/close") {
    const b = await readJson(req).catch(() => ({}));
    const s = sessions.get(b.session || "");
    if (s && b.pin === s.pin) sessions.delete(b.session);
    return apiSend(res, 200, {ok: true});
  }
  return false;
}

// ---- static app hosting (same origin keeps phone/desktop data) ----
const MIME = {".html":"text/html",".js":"text/javascript",".json":"application/json",".wasm":"application/wasm",".otf":"font/otf",".ttf":"font/ttf",".png":"image/png",".ico":"image/x-icon",".css":"text/css",".map":"application/json",".webmanifest":"application/manifest+json"};
http.createServer((req, res) => {
  (async () => {
    try {
      if (req.url.startsWith("/api/")) {
        if (!(await api(req, res)) && !res.headersSent) send(res, 404, {error: "no such api"});
        return;
      }
    } catch (e) { if (!res.headersSent) send(res, e.code || 500, {error: String((e && e.message) || e)}); return; }
    let p = decodeURIComponent(req.url.split("?")[0]);
    if (p.endsWith("/")) p += "index.html";
    const f = path.normalize(path.join(root, p));
    if (!f.startsWith(root)) { res.writeHead(403); res.end(); return; }
    fs.readFile(f, (err, data) => {
      if (err) {
        fs.readFile(path.join(root, "index.html"), (e2, d2) => {
          if (e2) { res.writeHead(404); res.end(); return; }
          res.writeHead(200, {"Content-Type": "text/html"}); res.end(d2);
        });
        return;
      }
      res.writeHead(200, {"Content-Type": MIME[path.extname(f).toLowerCase()] || "application/octet-stream", "Cache-Control": "no-cache"});
      res.end(data);
    });
  })();
}).listen(port, "0.0.0.0", () => console.log("SERVING " + root + " on :" + port + " (+ /api/sync relay)"));