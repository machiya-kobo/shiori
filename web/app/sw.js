// Shiori's service worker: the app's own files, so it opens (and installs)
// like an app, fetched fresh when the network answers and from the cache
// when it doesn't. Hister, SearXNG and the settings are never cached here:
// what you see is what the server has.
const CACHE = 'shiori-app-__VERSION__';
const SHELL = [
  '/',
  '/manifest.webmanifest',
  '/_shiori/app.js',
  '/_shiori/api.js',
  '/_shiori/app.css',
  '/_shiori/theme.css',
  '/_shiori/search-core.js',
  '/_shiori/web-icon-64.png',
  '/_shiori/icon-256.png',
];

// A new build waits until the page's "New Version · Reload" asks it to
// take over, so files never change under an open page.
self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)));
});

self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== location.origin) return;
  const shell = url.pathname === '/' || url.pathname === '/manifest.webmanifest' || url.pathname.startsWith('/_shiori/');
  if (!shell) return; // Hister, SearXNG, Konbini, settings: straight to the network.
  event.respondWith(
    fetch(event.request)
      .then((response) => {
        // Only a good copy: a 404 or a 502 (the app's host restarting)
        // would have replaced the shell, and the app opened on an error
        // page until the next good fetch.
        if (response.ok) {
          const copy = response.clone();
          caches.open(CACHE).then((cache) => cache.put(url.pathname === '/' ? '/' : event.request, copy));
        }
        return response;
      })
      // Offline and never cached (a first visit, a file added since):
      // a network error, as without the worker. `respondWith(undefined)`
      // would throw instead.
      .catch(() => caches.match(url.pathname === '/' ? '/' : event.request).then((cached) => cached || Response.error())),
  );
});
