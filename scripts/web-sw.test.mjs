// Tests for web/app/sw.js, the web app's service worker, run in a context
// standing in for the worker's: its own files from the network, else the
// cache, else a network error (never `respondWith(undefined)`).
// Run: node --test scripts/*.test.mjs

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const source = readFileSync(fileURLToPath(new URL('../web/app/sw.js', import.meta.url)), 'utf8');

/** The worker with `network` (a function, or null: offline) and a cache holding `cached` (path → body). */
function worker({ network = null, cached = {} } = {}) {
  const listeners = {};
  const store = new Map(Object.entries(cached).map(([k, v]) => [k, new Response(v)]));
  const keyOf = (r) => (typeof r === 'string' ? r : new URL(r.url).pathname);
  const cache = { put: async (r, res) => store.set(keyOf(r), res), addAll: async () => {} };
  const ctx = {
    URL, Response, Request,
    location: new URL('https://shiori.example/sw.js'),
    caches: { open: async () => cache, match: async (r) => store.get(keyOf(r)), keys: async () => [], delete: async () => true },
    fetch: async (r) => {
      if (!network) throw new TypeError('Failed to fetch');
      return network(r);
    },
    self: { addEventListener: (type, fn) => (listeners[type] = fn), skipWaiting() {}, clients: { claim() {} } },
  };
  vm.createContext(ctx);
  vm.runInContext(source, ctx);
  /** What the worker answers for `path` (undefined: left to the network). */
  return async (path) => {
    let answer;
    let called = false;
    listeners.fetch({
      request: new Request('https://shiori.example' + path),
      respondWith(p) {
        called = true;
        answer = p;
      },
    });
    return called ? await answer : undefined;
  };
}

test("offline, a file of the app's never cached is a network error, not a thrown respondWith", async () => {
  const get = worker();
  const res = await get('/_shiori/app.js');
  assert.ok(res instanceof Response, 'a Response');
  assert.equal(res.type, 'error');
});

test('offline, a cached file comes from the cache', async () => {
  const get = worker({ cached: { '/': 'shell', '/_shiori/app.css': 'css' } });
  assert.equal(await (await get('/')).text(), 'shell');
  assert.equal(await (await get('/_shiori/app.css')).text(), 'css');
});

test("online, the network's answer; Hister and the rooms are never the worker's", async () => {
  const get = worker({ network: () => new Response('fresh') });
  assert.equal(await (await get('/_shiori/app.js')).text(), 'fresh');
  assert.equal(await get('/search?q=x'), undefined);
  assert.equal(await get('/kura/api/vaults'), undefined);
});
