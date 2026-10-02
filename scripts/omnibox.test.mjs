// Tests for patches/ext/omnibox.js, Firefox's address-bar keyword ("sh
// lantern"), loaded as the Firefox background has it: host-local, core,
// search-core, omnibox. A fake address bar and Hister.
// Run: node --test scripts/*.test.mjs

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const read = (rel) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8');
const FIREFOX_BACKGROUND = ['patches/ext/host-local.js', 'patches/ext/core.js', 'patches/shiori/search-core.js', 'patches/ext/omnibox.js'];
const source = FIREFOX_BACKGROUND.map((f) => read('../' + f)).join('\n');
const plain = (v) => JSON.parse(JSON.stringify(v));
const BASE = 'https://hister.example/';

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

// hister(query) answers searches; every fetch is recorded. `settings` are
// this device's own (host-local's store): the background rebuilds the
// shioriSettings cache from them as it starts.
function load({ hister = () => ({ documents: [] }), settings = {}, storage } = {}) {
  storage = storage || fakeStorage({ histerURL: BASE, shioriLocalSettings: settings, shioriCachedRules: '{"skip":[]}' });
  const omnibox = { changed: [], entered: [], defaultSuggestion: null };
  const fetched = [];
  const opened = [];
  const ctx = {
    chrome: {
      storage: { local: storage },
      runtime: {
        getManifest: () => ({ version: '9.8.7' }),
        getURL: (p) => `moz-extension://x/${p}`,
        onMessage: { addListener() {} },
      },
      tabs: {
        onUpdated: { addListener() {} },
        query: async () => [{ id: 3 }],
        update: async (id, props) => opened.push(['update', id, props.url]),
        create: async (props) => opened.push([props.active === false ? 'background' : 'create', props.url]),
      },
      omnibox: {
        setDefaultSuggestion: (s) => (omnibox.defaultSuggestion = s),
        onInputChanged: { addListener: (l) => omnibox.changed.push(l) },
        onInputEntered: { addListener: (l) => omnibox.entered.push(l) },
      },
    },
    fetch: async (input, init) => {
      const url = typeof input === 'string' ? input : input.url;
      fetched.push({ url, init });
      if (url.startsWith(BASE + 'search?')) {
        const query = JSON.parse(new URL(url).searchParams.get('query'));
        return new Response(JSON.stringify(hister(query)));
      }
      return new Response('{}');
    },
    Response, Headers, URL, URLSearchParams, TypeError, JSON, setTimeout, clearTimeout, console, Date, AbortController, Promise, Map, Set,
  };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(source, ctx);
  const type = (text) => new Promise((resolve) => omnibox.changed.forEach((l) => l(text, resolve)));
  const enter = async (text, disposition = 'currentTab') => {
    for (const l of omnibox.entered) await l(text, disposition);
  };
  return { type, enter, fetched, opened, omnibox, storage };
}

const page = (url, title) => ({ url, title });
const settle = () => new Promise((r) => setTimeout(r, 30));

test('typing searches Hister as every Shiori search does: last word a prefix, never the notes', async () => {
  let asked = null;
  const { type, omnibox } = load({ hister: (q) => ((asked = q), { documents: [] }) });
  await type('paper lant');
  assert.deepEqual(plain(asked), { text: 'paper lant* -label:vault -metadata.source:vault', limit: 6 });
  assert.match(omnibox.defaultSuggestion.description, /Shiori Search/);
});

test('pages opened for this search come first, each page once, web pages only, never a note', async () => {
  const { type } = load({
    settings: { niwaURL: 'https://notes.example/' },
    hister: () => ({
      history: [page('https://a.example/', 'Opened before')],
      documents: [
        page('https://www.a.example/#top', 'Same page again'),
        page('https://b.example/x', 'Lanterns\nof Kyoto'),
        page('gemini://c.example/', 'A capsule'),
        page('https://notes.example/n/lanterns', 'A note'),
        page('https://d.example/', ''),
      ],
    }),
  });
  const list = plain(await type('lantern'));
  assert.deepEqual(list.map((s) => s.content), ['https://a.example/', 'https://b.example/x', 'https://d.example/']);
  assert.equal(list[1].description, 'Lanterns of Kyoto — b.example');
  assert.equal(list[2].description, 'https://d.example/ — d.example');
});

test('at most six suggestions', async () => {
  const docs = Array.from({ length: 10 }, (_, i) => page(`https://p${i}.example/`, `Page ${i}`));
  const { type } = load({ hister: () => ({ documents: docs }) });
  assert.equal((await type('page')).length, 6);
});

test('fast typing sends one search, for the latest text', async () => {
  const asked = [];
  const { type } = load({ hister: (q) => (asked.push(q.text), { documents: [page('https://a.example/', q.text)] }) });
  const first = type('lan');
  const last = await type('lantern');
  assert.deepEqual(asked, ['lantern* -label:vault -metadata.source:vault']);
  assert.equal(last[0].title, undefined, 'only content and description are suggested');
  void first;
});

test('no server, no text, or Hister out of reach: no suggestions, nothing thrown', async () => {
  assert.deepEqual(plain(await load().type('   ')), []);
  const none = load({ storage: fakeStorage({}) });
  assert.deepEqual(plain(await none.type('lantern')), []);
  assert.equal(none.fetched.filter((f) => f.url.includes('search?')).length, 0);
  const down = load({ hister: () => { throw new Error('down'); } });
  assert.deepEqual(plain(await down.type('lantern')), []);
});

test('Enter on the text opens Shiori Search for it, in the tab the person chose', async () => {
  const { enter, opened } = load();
  await enter('paper lanterns');
  await enter('kyoto', 'newForegroundTab');
  await enter('osaka', 'newBackgroundTab');
  assert.deepEqual(plain(opened), [
    ['update', 3, 'moz-extension://x/search.html?q=paper%20lanterns'],
    ['create', 'moz-extension://x/search.html?q=kyoto'],
    ['background', 'moz-extension://x/search.html?q=osaka'],
  ]);
});

test('Enter on a suggestion opens it and tells Hister it was opened for that search', async () => {
  const { type, enter, opened, fetched } = load({ hister: () => ({ documents: [page('https://b.example/x', 'Lanterns')] }) });
  await type('lant');
  await enter('https://b.example/x');
  await settle();
  assert.deepEqual(plain(opened), [['update', 3, 'https://b.example/x']]);
  const history = fetched.find((f) => f.url === BASE + 'api/history');
  assert.ok(history, 'api/history was sent');
  assert.deepEqual(JSON.parse(history.init.body), { url: 'https://b.example/x', title: 'Lanterns', query: 'lant* -label:vault -metadata.source:vault' });
});

test('with Remember What You Open off, an opened suggestion is not told to Hister', async () => {
  const { type, enter, fetched } = load({ settings: { rememberOpened: false }, hister: () => ({ documents: [page('https://b.example/x', 'Lanterns')] }) });
  await type('lant');
  await enter('https://b.example/x');
  await settle();
  assert.equal(fetched.some((f) => f.url.endsWith('api/history')), false);
});

test('a typed address opens as it is, and is not recorded', async () => {
  const { enter, opened, fetched } = load();
  await enter('https://example.org/page');
  await settle();
  assert.deepEqual(plain(opened), [['update', 3, 'https://example.org/page']]);
  assert.equal(fetched.some((f) => f.url.endsWith('api/history')), false);
});
