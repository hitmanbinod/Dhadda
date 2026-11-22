/* Dhadda service worker - versioned app-shell precache, cache-first static,
   never cache sync API calls. */
const VERSION = 'dhadda-web-v2-1';
const SHELL = [
  '/', '/index.html', '/app.css', '/app.js', '/sync.js', '/config.js',
  '/tokens.css', '/icons.svg', '/manifest.webmanifest',
  '/icon-192.png', '/icon-512.png',
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('message', e => {
  if (e.data === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (url.origin !== self.location.origin) return; // never intercept Worker API
  if (url.pathname.startsWith('/v1/')) return;
  if (e.request.method !== 'GET') return;
  e.respondWith(
    caches.match(e.request).then(hit => {
      const net = fetch(e.request).then(res => {
        if (res.ok) caches.open(VERSION).then(c => c.put(e.request, res.clone()));
        return res;
      }).catch(() => hit);
      return hit || net;
    }),
  );
});
