// Tests for patches/ext/containers.js: pages in the containers you choose
// are never captured on their own (Firefox). Upstream's listeners are fakes,
// added after it, as upstream's are.
// Run: node --test scripts/*.test.mjs

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const source = readFileSync(fileURLToPath(new URL('../patches/ext/containers.js', import.meta.url)), 'utf8');
const plain = (v) => JSON.parse(JSON.stringify(v));
const SETTINGS_PAGE = { url: 'moz-extension://x/shiori-settings.html', tab: { id: 9 } };

function load(stored = {}) {
  const data = structuredClone(stored);
  const messageListeners = [];
  const tabListeners = [];
  const changed = [];
  const ctx = {
    chrome: {
      runtime: { getURL: (p) => `moz-extension://x/${p}`, onMessage: { addListener: (l) => messageListeners.push(l) } },
      tabs: { onUpdated: { addListener: (l) => tabListeners.push(l) } },
      storage: {
        local: {
          get: async (keys) => Object.fromEntries(keys.filter((k) => k in data).map((k) => [k, structuredClone(data[k])])),
          set: async (items) => {
            Object.assign(data, structuredClone(items));
            for (const [k, v] of Object.entries(items)) changed.forEach((l) => l({ [k]: { newValue: v } }, 'local'));
          },
        },
        onChanged: { addListener: (l) => changed.push(l) },
      },
    },
    Promise, Set, JSON,
  };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(source, ctx);
  // Upstream adds its listeners after Shiori's code has run.
  const upstream = { messages: [], tabs: [] };
  ctx.chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
    upstream.messages.push(request);
    sendResponse({ status: 'ok', status_code: 201 });
    return true;
  });
  ctx.chrome.tabs.onUpdated.addListener((tabId) => upstream.tabs.push(tabId));
  const send = (request, sender) =>
    new Promise((resolve) => {
      for (const l of messageListeners) if (l(request, sender, resolve) === true) return;
      resolve(undefined);
    });
  const update = (tab) => tabListeners.forEach((l) => l(tab.id, { status: 'complete' }, tab));
  return { send, update, upstream, data };
}

const capture = { pageData: { url: 'https://bank.example/', html: '<p>x</p>' } };
const tabIn = (container, id = 3) => ({ tab: { id, cookieStoreId: container, url: 'https://bank.example/' } });

test("a page captured in a chosen container is skipped, as a skip rule would answer; elsewhere it's captured", async () => {
  const t = load({ shioriSkipContainers: ['firefox-container-3'] });
  assert.deepEqual(plain(await t.send(capture, tabIn('firefox-container-3'))), { status: 'ok', status_code: 406 });
  assert.equal(t.upstream.messages.length, 0);
  assert.deepEqual(plain(await t.send(capture, tabIn('firefox-container-1'))), { status: 'ok', status_code: 201 });
  assert.deepEqual(plain(await t.send(capture, tabIn('firefox-default'))), { status: 'ok', status_code: 201 });
  assert.equal(t.upstream.messages.length, 2);
});

test('a deliberate save there still goes through, as do other messages', async () => {
  const t = load({ shioriSkipContainers: ['firefox-container-3'] });
  await t.send({ ...capture, action: 'reindex' }, tabIn('firefox-container-3'));
  await t.send({ action: 'getTabState' }, tabIn('firefox-container-3'));
  assert.equal(t.upstream.messages.length, 2);
});

test('a PDF tab in a chosen container never reaches upstream', () => {
  const t = load({ shioriSkipContainers: ['firefox-container-3'] });
  return new Promise((resolve) => setTimeout(resolve, 5)).then(() => {
    t.update({ id: 5, cookieStoreId: 'firefox-container-3' });
    t.update({ id: 6, cookieStoreId: 'firefox-container-1' });
    assert.deepEqual(plain(t.upstream.tabs), [6]);
  });
});

test('only the settings page sets the list, and only container IDs', async () => {
  const t = load();
  const reply = await t.send({ shiori: 'set-skip-containers', ids: ['firefox-container-3', 'firefox-default', 'firefox-container-3', 7] }, SETTINGS_PAGE);
  assert.deepEqual(plain(reply), { ok: true, ids: ['firefox-container-3'] });
  assert.deepEqual(t.data.shioriSkipContainers, ['firefox-container-3']);
  assert.equal((await t.send({ shiori: 'set-skip-containers', ids: ['firefox-container-1'] }, { url: 'moz-extension://x/search.html' })).ok, false);
  assert.equal((await t.send({ shiori: 'set-skip-containers', ids: ['firefox-container-1'] }, { url: 'https://evil.example/', tab: { id: 1 } })).ok, false);
  assert.deepEqual(t.data.shioriSkipContainers, ['firefox-container-3']);
});

test('a change of list counts from the next capture', async () => {
  const t = load();
  await t.send({ shiori: 'set-skip-containers', ids: ['firefox-container-2'] }, SETTINGS_PAGE);
  assert.equal((await t.send(capture, tabIn('firefox-container-2'))).status_code, 406);
  await t.send({ shiori: 'set-skip-containers', ids: [] }, SETTINGS_PAGE);
  assert.equal((await t.send(capture, tabIn('firefox-container-2'))).status_code, 201);
});

// The real order (build-extension.sh's Firefox BACKGROUND): the core hides
// shiori: messages from listeners added after it, so this file must come first.
test('in the Firefox background as built, the settings page reaches the list', async () => {
  const build = readFileSync(fileURLToPath(new URL('../scripts/build-extension.sh', import.meta.url)), 'utf8');
  const files = /firefox\)[\s\S]*?BACKGROUND=\(([^)]*)\)/.exec(build)[1].split(/\s+/).filter(Boolean);
  const background = files.map((f) => readFileSync(fileURLToPath(new URL('../' + f, import.meta.url)), 'utf8')).join('\n');
  const data = {};
  const listeners = [];
  const ctx = {
    chrome: {
      runtime: { getURL: (p) => `moz-extension://x/${p}`, getManifest: () => ({ version: '1' }), onMessage: { addListener: (l) => listeners.push(l) } },
      tabs: { onUpdated: { addListener() {} }, query: async () => [] },
      storage: {
        local: {
          get: async (keys) => Object.fromEntries([].concat(keys).filter((k) => k in data).map((k) => [k, data[k]])),
          set: async (items) => void Object.assign(data, items),
          remove: async () => {},
        },
        onChanged: { addListener() {} },
      },
    },
    fetch: async () => new Response('{}'),
    Response, Headers, URL, URLSearchParams, TypeError, JSON, Promise, Set, Map, setTimeout, clearTimeout, console, Date, AbortController,
  };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(background, ctx);
  const reply = await new Promise((resolve) => {
    for (const l of listeners) if (l({ shiori: 'set-skip-containers', ids: ['firefox-container-3'] }, SETTINGS_PAGE, resolve) === true) return;
    resolve(undefined);
  });
  assert.equal(reply && reply.ok, true, 'someone answered');
  assert.deepEqual(plain(data.shioriSkipContainers), ['firefox-container-3']);
});
