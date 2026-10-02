// Tests for patches/ext/host-local.js, the host where there is no app
// (Firefox): the twin of SharedSettings.swift's apply, applyFromPage,
// recordSearch and extensionPayload. The key lists are read from the Swift
// source, so a key added there and not here fails. Also: Shiori's core
// (patches/ext/core.js) running on it.
// Run: node --test scripts/*.test.mjs

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const read = (rel) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8');
const hostSource = read('../patches/ext/host-local.js');
const coreSource = read('../patches/ext/core.js');
const swift = read('../Shared/Settings/SharedSettings.swift');

// --- SharedSettings.swift, read as text ---

const keyName = Object.fromEntries([...swift.matchAll(/static let (\w+) = "(\w+)"/g)].map((m) => [m[1], m[2]]));
function items(list) {
  return list
    .split(',')
    .map((x) => x.trim())
    .filter(Boolean)
    .map((x) => {
      if (!x.startsWith('Key.')) return JSON.parse(x);
      const name = keyName[x.slice(4)];
      assert.ok(name, `SharedSettings.Key.${x.slice(4)} not found`);
      return name;
    });
}
function swiftList(pattern) {
  const m = swift.match(pattern);
  assert.ok(m, `not found in SharedSettings.swift: ${pattern}`);
  return items(m[1]);
}
const SWIFT = {
  flagKeys: swiftList(/static let flagKeys = \[([^\]]*)\]/),
  countKeys: swiftList(/static let countKeys = \[([^\]]*)\]/),
  urlKeys: swiftList(/static let urlKeys = \[([^\]]*)\]/),
  textSizes: swiftList(/static let textSizes = \[([^\]]*)\]/),
  pageCounts: swiftList(/static let pageCounts = \[([^\]]*)\]/),
  resultStyles: swiftList(/static let resultStyles = \[([^\]]*)\]/),
  smallWebOpens: swiftList(/static let smallWebOpens = \[([^\]]*)\]/),
  themes: swiftList(/\[([^\]]*)\]\.contains\(value\) \{ set\(value, Key\.theme\) \}/),
  recentLimit: Number(swift.match(/static let recentLimit = (\d+)/)[1]),
  // extensionPayload: keys it sets one by one (payload[Key.x] = …), then its lists.
  payloadSingles: [...swift.matchAll(/payload\[Key\.(\w+)\] =/g)].map((m) => keyName[m[1]]),
  payloadFlags: swiftList(/let flags = \[([^\]]*)\]/),
  payloadCounts: swiftList(/for key in \[([^\]]*)\] where defaults\.object/),
  payloadStrings: swiftList(/for key in \[([^\]]*)\] \{\s*if let value = defaults\.string/),
};

// --- loading ---

function fakeStorage(initial = {}) {
  const data = structuredClone(initial);
  return {
    data,
    async get(keys) {
      const out = {};
      for (const k of [].concat(keys)) if (k in data) out[k] = structuredClone(data[k]);
      return out;
    },
    async set(items) {
      Object.assign(data, structuredClone(items));
    },
    async remove(keys) {
      for (const k of [].concat(keys)) delete data[k];
    },
  };
}

function loadHost(storage = fakeStorage()) {
  const ctx = { chrome: { storage: { local: storage } }, JSON, console };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(hostSource + '\nglobalThis.host = shioriHost;', ctx);
  return { host: ctx.host, storage };
}
const stored = (storage) => storage.data.shioriLocalSettings || {};
// Objects made inside the vm have its prototypes; compare their content.
const plain = (v) => JSON.parse(JSON.stringify(v));

// The core on this host, as a Firefox background would run it.
// network(url, init) answers the background's fetches (recorded in `fetched`).
function loadCore(storage = fakeStorage({}), network = async () => new Response('{}')) {
  const listeners = [];
  const updates = [];
  const fetched = [];
  const installed = [];
  const opened = [];
  const ctx = {
    chrome: {
      storage: { local: storage },
      runtime: {
        getManifest: () => ({ version: '9.8.7' }),
        getURL: (p) => `moz-extension://x/${p}`,
        onMessage: { addListener: (l) => listeners.push(l) },
        onInstalled: { addListener: (l) => installed.push(l) },
        openOptionsPage: async () => opened.push(true),
      },
      tabs: { update: async (id, props) => updates.push([id, props.url]), onUpdated: { addListener() {} } },
    },
    fetch: async (input, init) => {
      const url = typeof input === 'string' ? input : input.url;
      fetched.push(url);
      return network(url, init);
    },
    Response, Headers, URL, TypeError, JSON, setTimeout, clearTimeout, console, Date, AbortController, Promise,
  };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(hostSource + '\n' + coreSource, ctx);
  // From a tab (a content script or the results page) unless `sender` says otherwise.
  const send = (request, sender = { tab: { id: 7 } }) =>
    new Promise((resolve) => {
      if (typeof sender === 'number') sender = { tab: { id: sender } };
      for (const l of listeners) if (l(request, sender, resolve) === true) return;
      resolve(undefined);
    });
  const install = (reason) => installed.forEach((l) => l({ reason }));
  return { send, updates, storage, fetched, install, opened, ctx };
}

// --- the app's rules ---

test("SharedSettings.swift's lists are all found (else the tests below prove nothing)", () => {
  for (const [name, list] of Object.entries(SWIFT)) {
    if (Array.isArray(list)) assert.ok(list.length > 0 && list.every((x) => x !== undefined), name);
  }
  assert.ok(SWIFT.flagKeys.includes('combinedSearch') && SWIFT.payloadSingles.includes('recentSearches'));
  assert.equal(SWIFT.recentLimit, 5);
});

test('every flag the app accepts is accepted, as a boolean only', async () => {
  for (const key of SWIFT.flagKeys) {
    const { host, storage } = loadHost();
    await host.setSettings({ [key]: false });
    assert.equal(stored(storage)[key], false, key);
    await host.setSettings({ [key]: 'false' });
    await host.setSettings({ [key]: 0 });
    assert.equal(stored(storage)[key], false, `${key} kept its boolean`);
  }
});

test('counts are the page sizes the app allows, whole numbers only', async () => {
  for (const key of SWIFT.countKeys) {
    for (const n of SWIFT.pageCounts) {
      const { host, storage } = loadHost();
      await host.setSettings({ [key]: n });
      assert.equal(stored(storage)[key], n, `${key}=${n}`);
    }
    const { host, storage } = loadHost();
    for (const bad of [4, 5.5, '5', 100]) await host.setSettings({ [key]: bad });
    assert.equal(key in stored(storage), false, key);
  }
});

test('addresses are http(s) or empty, as the app takes them', async () => {
  for (const key of SWIFT.urlKeys) {
    const { host, storage } = loadHost();
    await host.setSettings({ [key]: 'https://example.org/' });
    assert.equal(stored(storage)[key], 'https://example.org/', key);
    await host.setSettings({ [key]: '' });
    assert.equal(stored(storage)[key], '', `${key} cleared`);
    for (const bad of ['javascript:alert(1)', 'ftp://example.org/', 'example.org', 7]) await host.setSettings({ [key]: bad });
    assert.equal(stored(storage)[key], '', `${key} refused bad values`);
  }
});

test('choices take only the values the app knows', async () => {
  const cases = { textSize: SWIFT.textSizes, theme: SWIFT.themes, resultStyle: SWIFT.resultStyles, smallWebOpen: SWIFT.smallWebOpens };
  for (const [key, allowed] of Object.entries(cases)) {
    for (const value of allowed) {
      const { host, storage } = loadHost();
      await host.setSettings({ [key]: value });
      assert.equal(stored(storage)[key], value, `${key}=${value}`);
    }
    const { host, storage } = loadHost();
    await host.setSettings({ [key]: 'nonsense' });
    assert.equal(key in stored(storage), false, key);
  }
});

test("the Obsidian vault's name is 1 to 200 characters", async () => {
  const { host, storage } = loadHost();
  await host.setSettings({ obsidianVault: 'Notes' });
  await host.setSettings({ obsidianVault: '' });
  await host.setSettings({ obsidianVault: 'x'.repeat(201) });
  assert.equal(stored(storage).obsidianVault, 'Notes');
});

test('nothing outside the whitelist is kept: no AI settings, no server, no unknown keys', async () => {
  const { host, storage } = loadHost();
  await host.setSettings({ aiEnabled: true, aiProvider: 'anthropic', aiKey: 'sk-x', serverURL: 'https://evil.example/', histerURL: 'https://evil.example/', recentSearches: ['planted'] });
  assert.deepEqual(stored(storage), {});
});

test('the payload is what was set plus the recent searches, keyed as the app sends it', async () => {
  const { host } = loadHost(fakeStorage({ shioriLocalSettings: { showInfobox: false, histerCount: 10, theme: 'night', semanticSearch: true, newsBlurURL: 'https://nb.example/' } }));
  assert.deepEqual(plain(await host.settings()), { showInfobox: false, histerCount: 10, theme: 'night', recentSearches: [] });

  const everything = {};
  for (const k of SWIFT.flagKeys) everything[k] = true;
  for (const k of SWIFT.countKeys) everything[k] = 5;
  for (const k of [...SWIFT.urlKeys, ...SWIFT.payloadStrings]) everything[k] = 'https://example.org/';
  const expected = [...SWIFT.payloadSingles, ...SWIFT.payloadFlags, ...SWIFT.payloadCounts, ...SWIFT.payloadStrings];
  for (const k of expected) if (!(k in everything) && k !== 'recentSearches') everything[k] = 'night';
  const full = await loadHost(fakeStorage({ shioriLocalSettings: everything })).host.settings();
  assert.deepEqual(Object.keys(full).sort(), [...new Set(expected)].sort());
});

test('a search goes to the top of the recent searches, once whatever its case, within the limit', async () => {
  const { host, storage } = loadHost();
  for (const q of ['one', 'two', 'three', 'four', 'five', 'six']) await host.recordSearch(q);
  await host.recordSearch('  FOUR ');
  assert.deepEqual(stored(storage).recentSearches, ['FOUR', 'six', 'five', 'three', 'two']);
  assert.equal(stored(storage).recentSearches.length, SWIFT.recentLimit);
  await host.recordSearch('   ');
  await host.recordSearch('x'.repeat(501));
  assert.equal(stored(storage).recentSearches[0], 'FOUR');
});

test('with history off nothing is recorded, and turning it off or clearing empties the list', async () => {
  const { host, storage } = loadHost();
  await host.recordSearch('kept');
  await host.setSettings({ clearRecentSearches: true });
  assert.equal('recentSearches' in stored(storage), false);
  await host.recordSearch('again');
  await host.setSettings({ searchHistory: false });
  assert.equal('recentSearches' in stored(storage), false);
  await host.recordSearch('not kept');
  assert.equal('recentSearches' in stored(storage), false);
  assert.deepEqual(plain((await host.settings()).recentSearches), []);
});

test('there is no app to tell about the queue', () => {
  const { host } = loadHost();
  assert.equal(host.canReportQueue(), false);
});

// --- the core on this host ---

test("the results page's settings are kept on this device and survive the next refresh", async () => {
  const { send, storage } = loadCore();
  const reply = await send({ shiori: 'set-settings', values: { combinedSearch: false, theme: 'day', aiProvider: 'x' } });
  assert.equal(reply.ok, true);
  assert.equal(reply.settings.combinedSearch, false);
  assert.equal(reply.settings.theme, 'day');
  assert.equal('aiProvider' in reply.settings, false);
  await send({ shiori: 'refresh-settings' });
  await new Promise((r) => setTimeout(r, 5100)); // past the page's freshness window
  await send({ shiori: 'refresh-settings' });
  assert.equal(storage.data.shioriSettings.combinedSearch, false);
  assert.equal(storage.data.shioriSettings.theme, 'day');
});

test('a switch turned off on this device counts for the next search', async () => {
  const { send, updates } = loadCore();
  assert.equal((await send({ shiori: 'search', q: 'lantern' })).redirect, true);
  await send({ shiori: 'set-settings', values: { combinedSearch: false } });
  assert.equal((await send({ shiori: 'search', q: 'paper' }, 8)).redirect, false);
  assert.equal(updates.length, 1);
});

test("a search recorded from the results page reaches the page's settings", async () => {
  const { send, storage } = loadCore();
  await send({ shiori: 'record-search', q: ' lantern ' });
  assert.deepEqual(storage.data.shioriSettings.recentSearches, ['lantern']);
});

test("the Firefox build prepends the host and the core in the order these tests load them", () => {
  const build = read('../scripts/build-extension.sh');
  assert.ok(build.includes('BACKGROUND=(patches/ext/host-local.js patches/ext/containers.js patches/ext/core.js patches/shiori/search-core.js patches/ext/pages.js patches/ext/omnibox.js patches/ext/badge.js patches/ext/menus.js)\n'));
});

// --- the settings page's messages ---

const SETTINGS_PAGE = { url: 'moz-extension://x/shiori-settings.html', tab: { id: 9 } };
const settle = () => new Promise((r) => setTimeout(r, 20));

test('the settings page sets the server: new rules fetched, old ones gone, queued pages follow', async () => {
  const storage = fakeStorage({
    histerURL: 'https://old.example/',
    shioriCachedRules: '{"skip":["old"]}',
    shioriQueueIndex: [{ key: 'shioriQueueItem:1', pageURL: 'https://a.example/', bytes: 2, attempts: 0, queuedAt: Date.now() }],
    'shioriQueueItem:1': { url: 'https://old.example/api/add', headers: {}, body: '{"url":"https://a.example/"}' },
  });
  const sent = [];
  const { send } = loadCore(storage, async (url, init) => {
    if (url.startsWith('https://old.example/')) throw new TypeError('the old server is gone');
    if (url === 'https://new.example/api/rules') return new Response('{"skip":["new"]}');
    if (init && init.method === 'POST') sent.push(url);
    return new Response('{}', { status: 201 });
  });
  await settle();
  const reply = await send({ shiori: 'set-server', url: 'https://new.example' }, SETTINGS_PAGE);
  assert.equal(reply.ok, true);
  assert.equal(reply.reachable, true);
  assert.equal(storage.data.histerURL, 'https://new.example/');
  assert.equal(storage.data.shioriCachedRules, '{"skip":["new"]}');
  await settle();
  assert.deepEqual(sent, ['https://new.example/api/add']);
  assert.equal((storage.data.shioriQueueIndex || []).length, 0);
});

test('a server out of reach is still saved, its pages wait, and the old rules are gone', async () => {
  const storage = fakeStorage({ histerURL: 'https://old.example/', shioriCachedRules: '{"skip":[]}' });
  const { send } = loadCore(storage, async () => {
    throw new TypeError('offline');
  });
  const reply = await send({ shiori: 'set-server', url: 'http://hister.lan:4433/' }, SETTINGS_PAGE);
  assert.equal(reply.ok, true);
  assert.equal(reply.reachable, false);
  assert.equal(storage.data.histerURL, 'http://hister.lan:4433/');
  assert.equal('shioriCachedRules' in storage.data, false);
});

test('only the settings page sets the server, and only to an http(s) address', async () => {
  const storage = fakeStorage({ histerURL: 'https://kept.example/' });
  const { send } = loadCore(storage);
  const tries = [
    [{ shiori: 'set-server', url: 'https://evil.example/' }, { tab: { id: 7 }, url: 'https://duckduckgo.com/?q=x' }],
    [{ shiori: 'set-server', url: 'https://evil.example/' }, { url: 'moz-extension://x/search.html', tab: { id: 7 } }],
    [{ shiori: 'set-server', url: 'javascript:alert(1)' }, SETTINGS_PAGE],
    [{ shiori: 'set-server', url: 'ftp://hister.example/' }, SETTINGS_PAGE],
    [{ shiori: 'set-server', url: '' }, SETTINGS_PAGE],
  ];
  for (const [request, sender] of tries) assert.equal((await send(request, sender)).ok, false, JSON.stringify([request, sender]));
  assert.equal(storage.data.histerURL, 'https://kept.example/');
});

test('the queue is counted, and Retry sends it', async () => {
  const queuedAt = Date.now() - 60_000;
  const storage = fakeStorage({
    histerURL: 'https://h.example/',
    shioriCachedRules: '{"skip":[]}',
    shioriQueueIndex: [{ key: 'shioriQueueItem:1', pageURL: 'https://a.example/', bytes: 2, attempts: 0, queuedAt }],
    'shioriQueueItem:1': { url: 'https://h.example/api/add', headers: {}, body: '{}' },
  });
  let up = false;
  const { send } = loadCore(storage, async () => {
    if (!up) throw new TypeError('offline');
    return new Response('{}', { status: 201 });
  });
  await settle();
  assert.deepEqual(plain(await send({ shiori: 'queue-status' }, SETTINGS_PAGE)), { ok: true, count: 1, oldest: queuedAt });
  up = true;
  assert.deepEqual(plain(await send({ shiori: 'retry-queue' }, SETTINGS_PAGE)), { ok: true, count: 0, oldest: null });
});

test('the settings page opens on first install, not on an update', () => {
  const { install, opened } = loadCore();
  install('update');
  assert.equal(opened.length, 0);
  install('install');
  assert.equal(opened.length, 1);
});
