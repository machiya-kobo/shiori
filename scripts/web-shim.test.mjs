// The web page's stand-in for the extension APIs (web/shim.js), run
// against a fake browser: localStorage, location and fetch (which it must
// never call: settings are this browser's own).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

// Values made inside the sandbox have its own Array/Object: compare copies.
const plain = (v) => JSON.parse(JSON.stringify(v));

const source = readFileSync(new URL('../web/shim.js', import.meta.url), 'utf8');

function browser(serverDoc) {
  const storage = new Map();
  const requests = [];
  let doc = serverDoc;
  const window = {};
  const context = {
    window,
    location: { origin: 'https://shiori.example' },
    localStorage: {
      getItem: (k) => (storage.has(k) ? storage.get(k) : null),
      setItem: (k, v) => storage.set(k, String(v)),
    },
    fetch: async (url, options = {}) => {
      requests.push({ url, method: options.method || 'GET', body: options.body });
      if ((options.method || 'GET') === 'PUT') {
        doc = JSON.parse(options.body);
        return { ok: true, status: 204, json: async () => ({}) };
      }
      if (!doc) return { ok: false, status: 404, json: async () => null };
      return { ok: true, status: 200, json: async () => doc };
    },
  };
  vm.runInNewContext(source, context);
  const send = (message) => new Promise((resolve) => window.chrome.runtime.sendMessage(message, resolve));
  return { chrome: window.chrome, send, requests, doc: () => doc, storage };
}

test('addresses are this host, whatever was stored', async () => {
  const b = browser(null);
  const got = await b.chrome.storage.local.get(['histerURL', 'shioriSettings']);
  assert.equal(got.histerURL, 'https://shiori.example/');
  assert.equal(got.shioriSettings.searxngURL, 'https://shiori.example/searx/');
  assert.equal(got.shioriSettings.konbiniAPIURL, 'https://shiori.example/konbini/');
});

test('settings stay in this browser: the server is never asked', async () => {
  const b = browser({ version: 1, updatedAt: 5, values: { theme: 'day' } });
  await b.send({ shiori: 'refresh-settings' });
  await b.send({ shiori: 'set-settings', values: { theme: 'night', bogus: 1, searxngURL: 'https://elsewhere/' } });
  const { shioriSettings } = await b.chrome.storage.local.get(['shioriSettings']);
  assert.equal(shioriSettings.theme, 'night');
  assert.equal('bogus' in shioriSettings, false);
  assert.equal(shioriSettings.searxngURL, 'https://shiori.example/searx/');
  assert.equal(b.requests.length, 0);
});

test('the notes\' homes start from the build, and a browser\'s own choice wins', async () => {
  const stamped = source.replace('__SHIORI_NIWA_URL__', 'https://kura.example/');
  const window = {};
  const storage = new Map();
  vm.runInNewContext(stamped, {
    window,
    location: { origin: 'https://shiori.example' },
    localStorage: { getItem: (k) => storage.get(k) ?? null, setItem: (k, v) => storage.set(k, String(v)) },
  });
  const get = async () => (await window.chrome.storage.local.get(['shioriSettings'])).shioriSettings;
  assert.equal((await get()).niwaURL, 'https://kura.example/');
  assert.equal('konbiniURL' in (await get()), false);
  await new Promise((r) => window.chrome.runtime.sendMessage({ shiori: 'set-settings', values: { niwaURL: 'https://mine.example/' } }, r));
  assert.equal((await get()).niwaURL, 'https://mine.example/');
});

test('recent searches stay in this browser: five, newest first, once each', async () => {
  const b = browser(null);
  for (const q of ['Rust', 'rust', 'a', 'b', 'c', 'd', 'e']) await b.send({ shiori: 'record-search', q });
  const { shioriSettings } = await b.chrome.storage.local.get(['shioriSettings']);
  assert.deepEqual(plain(shioriSettings.recentSearches), ['e', 'd', 'c', 'b', 'a']);
  assert.equal(b.requests.length, 0);
});

test('history off keeps none and clears what was there', async () => {
  const b = browser({ version: 1, updatedAt: 1, values: {} });
  await b.send({ shiori: 'record-search', q: 'rust' });
  await b.send({ shiori: 'set-settings', values: { searchHistory: false } });
  await b.send({ shiori: 'record-search', q: 'go' });
  const { shioriSettings } = await b.chrome.storage.local.get(['shioriSettings']);
  assert.deepEqual(plain(shioriSettings.recentSearches), []);
});

test('the page cache round-trips through storage', async () => {
  const b = browser(null);
  await b.chrome.storage.local.set({ shioriPageCache: { k: 1 } });
  assert.deepEqual(plain((await b.chrome.storage.local.get(['shioriPageCache'])).shioriPageCache), { k: 1 });
});

test("the theme is the house's: read from machiya_palette, written back on a change", async () => {
  const window = {};
  const storage = new Map();
  const document = {};
  const written = [];
  Object.defineProperty(document, 'cookie', {
    get: () => 'machiya_palette=nord; machiya_theme=day',
    set: (v) => written.push(v),
  });
  const context = {
    window,
    document,
    location: { origin: 'https://shiori.example', hostname: 'shiori.tail.example' },
    localStorage: { getItem: (k) => storage.get(k) ?? null, setItem: (k, v) => storage.set(k, String(v)) },
  };
  vm.runInNewContext(readFileSync(new URL('../patches/shiori/search-core.js', import.meta.url), 'utf8'), context);
  window.ShioriSearch = context.ShioriSearch;
  vm.runInNewContext(source, context);
  const get = async () => (await window.chrome.storage.local.get(['shioriSettings'])).shioriSettings;
  assert.equal((await get()).palette, 'nord');
  assert.equal((await get()).theme, 'day');
  await new Promise((resolve) => window.chrome.runtime.sendMessage({ shiori: 'set-settings', values: { palette: 'dracula' } }, resolve));
  assert.ok(written.some((c) => c.startsWith('machiya_palette=dracula;') && c.includes('domain=tail.example')), written.join(' | '));
  assert.equal(written.some((c) => c.startsWith('machiya_theme=')), false);
});
