// Tests for the Safari shims in patches/ (and Shiori's core in patches/ext/,
// with the app as its host). Each test loads a shim into a fresh vm context
// with fake chrome.* and fetch.
// Run: node --test scripts/

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const read = (rel) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8');
// What build-extension.sh prepends to Safari's background.js, in its order.
const SAFARI_BACKGROUND = ['patches/safari-shims.js', 'patches/ext/host-native.js', 'patches/ext/core.js', 'patches/shiori/search-core.js', 'patches/ext/badge.js', 'patches/ext/menus.js'];
const backgroundShim = SAFARI_BACKGROUND.map((f) => read('../' + f)).join('\n');
const contentShim = read('../patches/safari-content-shim.js');

const BASE = 'https://hister.example/';
const settle = () => new Promise((r) => setTimeout(r, 20));

// With `events`, it has the browser's storage.onChanged (else none, as
// before Shiori listened).
function fakeStorage(initial = {}, { events = false } = {}) {
  const data = structuredClone(initial);
  const changed = [];
  return {
    data,
    onChanged: events ? { addListener: (l) => changed.push(l) } : undefined,
    async get(keys) {
      const out = {};
      for (const k of keys) if (k in data) out[k] = structuredClone(data[k]);
      return out;
    },
    async set(items) {
      const changes = {};
      for (const [k, v] of Object.entries(items)) changes[k] = { oldValue: data[k], newValue: v };
      Object.assign(data, structuredClone(items));
      // The browser tells listeners after the write, never inside it.
      setTimeout(() => changed.forEach((l) => l(structuredClone(changes), 'local')));
    },
    async remove(keys) {
      for (const k of [].concat(keys)) delete data[k];
    },
  };
}

// network(url, init) returns a Response or throws; calls are recorded.
const RULES = { shioriCachedRules: '{"skip":[]}' };

function loadBackground({ network, storage = fakeStorage({ histerURL: BASE, ...RULES }), source = backgroundShim }) {
  const calls = [];
  const fetch = async (input, init) => {
    const url = typeof input === 'string' ? input : input.url;
    calls.push({ url, init });
    return network(url, init);
  };
  const ctx = {
    chrome: { storage: { local: storage, onChanged: storage.onChanged }, runtime: { getManifest: () => ({ version: '9.8.7' }) } },
    fetch,
    Response,
    Headers,
    URL,
    TypeError,
    JSON,
    setTimeout,
    clearTimeout,
    console,
    AbortController,
  };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(source, ctx);
  return { ctx, calls, storage };
}

const addInit = (doc) => ({
  method: 'POST',
  headers: { 'Content-type': 'application/json; charset=UTF-8' },
  body: JSON.stringify(doc),
});
const offline = () => {
  throw new TypeError('Load failed');
};
const queued = (storage) => storage.data.shioriQueueIndex ?? [];

test('an automatic capture made offline is queued with a visit time and answers 201', async () => {
  const { ctx, storage } = loadBackground({ network: offline });
  const before = Math.floor(Date.now() / 1000);
  const r = await ctx.fetch(BASE + 'api/add', addInit({ url: 'https://a.example/', text: 'x' }));
  assert.equal(r.status, 201);
  assert.equal(r.headers.get('X-Shiori-Queued'), '1');
  const [entry] = queued(storage);
  assert.equal(entry.pageURL, 'https://a.example/');
  const item = storage.data[entry.key];
  assert.equal(item.url, BASE + 'api/add');
  const doc = JSON.parse(item.body);
  assert.ok(Number.isInteger(doc.added) && doc.added >= before);
});

test("a work vault's note is never sent or queued, however it's captured", async () => {
  for (const network of [offline, async () => new Response('{}', { status: 201 })]) {
    const { ctx, calls, storage } = loadBackground({ network });
    // Kura serves the same note at //v/… and /%76/… (search-core's noteVault).
    for (const url of ['https://kura.example/v/work/n/plan', 'https://kura.example//v/work/n/plan', 'https://kura.example/%76/work/n/plan']) {
      for (const metadata of [{}, { ignore_skip_rules: true }]) {
        const r = await ctx.fetch(BASE + 'api/add', addInit({ url, html: '<p>x</p>', metadata }));
        assert.equal(r.status, 406, url);
        assert.equal(r.headers.get('X-Shiori-Refused'), 'work-note');
      }
    }
    assert.equal(calls.some((c) => c.url === BASE + 'api/add'), false);
    assert.deepEqual(queued(storage), []);
  }
});

test('a shared vault\'s note is captured once Kura says so; a private one, or Kura out of reach, is refused', async () => {
  const KURA = 'https://kura.example/';
  const vaults = { vaults: [
    { name: 'personal', default: true, private: false },
    { name: 'work', default: false, private: false },
    { name: 'client', default: false, private: true },
  ] };
  const settings = { shioriSettings: { niwaURL: KURA } };
  const kuraUp = async (url) =>
    url === KURA + 'api/vaults' ? new Response(JSON.stringify(vaults)) : new Response('{}', { status: 201 });
  const up = loadBackground({ network: kuraUp, storage: fakeStorage({ histerURL: BASE, ...RULES, ...settings }) });
  assert.equal((await up.ctx.fetch(BASE + 'api/add', addInit({ url: KURA + 'v/work/n/plan', html: '<p>x</p>' }))).status, 201);
  assert.equal((await up.ctx.fetch(BASE + 'api/add', addInit({ url: KURA + 'v/client/n/plan', html: '<p>x</p>' }))).status, 406);
  assert.equal((await up.ctx.fetch(BASE + 'api/add', addInit({ url: KURA + 'n/plan', html: '<p>x</p>' }))).status, 201);
  assert.equal(up.calls.filter((c) => c.url === KURA + 'api/vaults').length, 2, "asked before each other vault's note, never for the default's");

  const kuraDown = async (url) => {
    if (url.startsWith(KURA)) throw new TypeError('Load failed');
    return new Response('{}', { status: 201 });
  };
  const down = loadBackground({ network: kuraDown, storage: fakeStorage({ histerURL: BASE, ...RULES, ...settings }) });
  assert.equal((await down.ctx.fetch(BASE + 'api/add', addInit({ url: KURA + 'v/work/n/plan', html: '<p>x</p>' }))).status, 406);
  assert.equal(down.calls.some((c) => c.url === BASE + 'api/add'), false);
});

test('a vault made private between two captures is refused at once, never from a copy', async () => {
  const KURA = 'https://kura.example/';
  let shared = true;
  const network = async (url) =>
    url === KURA + 'api/vaults'
      ? new Response(JSON.stringify({ vaults: [{ name: 'personal', default: true, private: false }, { name: 'work', default: false, private: !shared }] }))
      : new Response('{}', { status: 201 });
  const { ctx, calls } = loadBackground({ network, storage: fakeStorage({ histerURL: BASE, ...RULES, shioriSettings: { niwaURL: KURA } }) });
  assert.equal((await ctx.fetch(BASE + 'api/add', addInit({ url: KURA + 'v/work/n/plan', html: '<p>x</p>' }))).status, 201);
  shared = false;
  const r = await ctx.fetch(BASE + 'api/add', addInit({ url: KURA + 'v/work/n/plan', html: '<p>x</p>' }));
  assert.equal(r.status, 406);
  assert.equal(calls.filter((c) => c.url === BASE + 'api/add').length, 1);
});

test("on a fresh install (no settings stored yet) Kura's address is the build's", async () => {
  const KURA = 'https://kura.example/';
  const network = async (url) =>
    url === KURA + 'api/vaults'
      ? new Response(JSON.stringify({ vaults: [{ name: 'personal', default: true, private: false }, { name: 'work', default: false, private: false }] }))
      : new Response('{}', { status: 201 });
  const source = backgroundShim.replaceAll('__SHIORI_NIWA_URL__', KURA);
  const { ctx, calls } = loadBackground({ network, source });
  assert.equal((await ctx.fetch(BASE + 'api/add', addInit({ url: KURA + 'v/work/n/plan', html: '<p>x</p>' }))).status, 201);
  assert.equal(calls.filter((c) => c.url === KURA + 'api/vaults').length, 1);
  // A Kura address cleared in the settings is no Kura: private.
  const cleared = loadBackground({ network, source, storage: fakeStorage({ histerURL: BASE, ...RULES, shioriSettings: { niwaURL: '' } }) });
  assert.equal((await cleared.ctx.fetch(BASE + 'api/add', addInit({ url: KURA + 'v/work/n/plan', html: '<p>x</p>' }))).status, 406);
});

test('a manual capture made offline is queued but still reports failure', async () => {
  const { ctx, storage } = loadBackground({ network: offline });
  const init = addInit({ url: 'https://a.example/', metadata: { ignore_skip_rules: true } });
  await assert.rejects(ctx.fetch(BASE + 'api/add', init), /Queued/);
  assert.equal(queued(storage).length, 1);
});

test('a newer snapshot of the same page replaces the queued one and keeps the first visit time', async () => {
  const { ctx, storage } = loadBackground({ network: offline });
  await ctx.fetch(BASE + 'api/add', addInit({ url: 'https://a.example/', text: 'old', added: 100 }));
  await ctx.fetch(BASE + 'api/add', addInit({ url: 'https://a.example/', text: 'new' }));
  const index = queued(storage);
  assert.equal(index.length, 1);
  const doc = JSON.parse(storage.data[index[0].key].body);
  assert.equal(doc.text, 'new');
  assert.equal(doc.added, 100);
});

test('the queue drains in order once the server answers, dropping 406/413/422', async () => {
  let online = false;
  const sent = [];
  const status = { 'https://a.example/': 201, 'https://skip.example/': 406, 'https://big.example/': 413 };
  const { ctx, storage } = loadBackground({
    network: (url, init) => {
      if (!online) offline();
      if (url.endsWith('api/add')) {
        const doc = JSON.parse(init.body);
        sent.push(doc.url);
        return new Response('', { status: status[doc.url] ?? 201 });
      }
      return new Response('{"skip":[]}', { status: 200 });
    },
  });
  for (const u of Object.keys(status)) await ctx.fetch(BASE + 'api/add', addInit({ url: u }));
  assert.equal(queued(storage).length, 3);

  online = true;
  await ctx.fetch(BASE + 'api/rules');
  await settle();
  assert.deepEqual(sent, Object.keys(status));
  assert.equal(queued(storage).length, 0);
  assert.deepEqual(
    Object.keys(storage.data).filter((k) => k.startsWith('shioriQueueItem:')),
    [],
  );
});

test('a 5xx during a drain keeps the capture for later, up to the retry budget', async () => {
  let mode = 'offline';
  const { ctx, storage } = loadBackground({
    network: (url) => {
      if (mode === 'offline') offline();
      if (url.endsWith('api/add')) return new Response('', { status: 502 });
      return new Response('{}', { status: 200 });
    },
  });
  await ctx.fetch(BASE + 'api/add', addInit({ url: 'https://a.example/' }));
  mode = 'broken';
  for (let i = 1; i <= 4; i++) {
    await ctx.fetch(BASE + 'api/rules');
    await settle();
    assert.equal(queued(storage)[0].attempts, i);
  }
  await ctx.fetch(BASE + 'api/rules');
  await settle();
  assert.equal(queued(storage).length, 0);
});

test("a capture Hister refuses for want of a credential (401/403) is kept, with no try counted, until a token works", async () => {
  // Hister's users on, no token here yet: every call answers 403.
  let token = false;
  const sent = [];
  const { ctx, storage } = loadBackground({
    network: (url, init) => {
      const authorised = token && init && init.headers && init.headers['X-Access-Token'] === 'ABCDEFGHJKLMNPQRSTUVWXYZ23';
      if (!url.endsWith('api/add')) return new Response('{}', { status: authorised || !token ? (token ? 200 : 403) : 403 });
      if (!authorised) return new Response('', { status: 403 });
      sent.push(JSON.parse(init.body).url);
      return new Response('', { status: 201 });
    },
  });
  const r = await ctx.fetch(BASE + 'api/add', addInit({ url: 'https://a.example/' }));
  assert.equal(r.status, 403);
  assert.equal(queued(storage).length, 1);
  // Refusals don't set off drains, and a drain that meets one counts nothing.
  for (let i = 0; i < 6; i++) await ctx.fetch(BASE + 'api/rules');
  await settle();
  assert.equal(queued(storage).length, 1);
  assert.equal(queued(storage)[0].attempts ?? 0, 0);
  // The token arrives: the next answer drains it, with the token.
  storage.data.histerToken = 'ABCDEFGHJKLMNPQRSTUVWXYZ23';
  token = true;
  await ctx.fetch(BASE + 'api/rules', { headers: { 'X-Access-Token': 'ABCDEFGHJKLMNPQRSTUVWXYZ23' } });
  await settle();
  assert.deepEqual(sent, ['https://a.example/']);
  assert.equal(queued(storage).length, 0);
});

test('a direct success for a page forgets its queued copy', async () => {
  let online = false;
  const sent = [];
  const { ctx, storage } = loadBackground({
    network: (url, init) => {
      if (!online) offline();
      if (!url.endsWith('api/add')) return new Response('{}', { status: 200 });
      sent.push(JSON.parse(init.body).text);
      return new Response('', { status: 201 });
    },
  });
  await ctx.fetch(BASE + 'api/add', addInit({ url: 'https://a.example/', text: 'queued' }));
  online = true;
  await ctx.fetch(BASE + 'api/add', addInit({ url: 'https://a.example/', text: 'direct' }));
  await settle();
  assert.deepEqual(sent, ['direct']);
  assert.equal(queued(storage).length, 0);
});

test('rules are remembered and answer while offline', async () => {
  let online = true;
  const { ctx } = loadBackground({
    network: () => {
      if (!online) offline();
      return new Response('{"skip":["bank"]}', { status: 200 });
    },
  });
  await ctx.fetch(BASE + 'api/rules');
  await settle();
  online = false;
  const r = await ctx.fetch(BASE + 'api/rules');
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { skip: ['bank'] });
});

test('with no remembered rules an offline rules fetch still fails', async () => {
  const { ctx } = loadBackground({ network: offline, storage: fakeStorage({ histerURL: BASE }) });
  await assert.rejects(ctx.fetch(BASE + 'api/rules'));
});

test('requests to other hosts and endpoints pass through untouched', async () => {
  const { ctx, calls, storage } = loadBackground({ network: offline });
  await assert.rejects(ctx.fetch('https://a.example/favicon.ico'));
  await assert.rejects(ctx.fetch('https://other.example/api/add', addInit({ url: 'x' })));
  await assert.rejects(ctx.fetch(BASE + 'api/add_pdf', addInit({ url: 'x' })));
  assert.equal(calls.filter((c) => !c.url.endsWith('api/rules')).length, 3);
  assert.equal(queued(storage).length, 0);
});

test('the queue keeps the newest captures within its item cap', async () => {
  const { ctx, storage } = loadBackground({ network: offline });
  for (let i = 0; i < 105; i++) {
    await ctx.fetch(BASE + 'api/add', addInit({ url: `https://a.example/${i}` }));
  }
  const index = queued(storage);
  assert.equal(index.length, 100);
  assert.equal(index[0].pageURL, 'https://a.example/5');
  const items = Object.keys(storage.data).filter((k) => k.startsWith('shioriQueueItem:'));
  assert.equal(items.length, 100);
});

function loadContent() {
  const sent = [];
  const ctx = {
    chrome: {
      runtime: {
        sendMessage: (message, cb) => {
          sent.push(message);
          cb?.({ status: 'ok', status_code: 201 });
        },
      },
    },
  };
  vm.createContext(ctx);
  vm.runInContext(contentShim, ctx);
  return { ctx, sent };
}

test('page data under the caps, with no HTML, is sent unchanged', () => {
  const { ctx, sent } = loadContent();
  const msg = { pageData: { url: 'u', html: '', text: 'hi' } };
  ctx.chrome.runtime.sendMessage(msg);
  assert.equal(sent[0], msg);
});

test("a capture with HTML goes without its text (Hister derives it), and the page's copy is untouched", () => {
  const { ctx, sent } = loadContent();
  const pageData = { url: 'u', title: 't', html: '<p>hi</p>', text: 'hi', faviconURL: 'f' };
  ctx.chrome.runtime.sendMessage({ pageData, action: 'reindex' });
  assert.deepEqual(JSON.parse(JSON.stringify(sent[0])), {
    pageData: { url: 'u', title: 't', html: '<p>hi</p>', faviconURL: 'f' },
    action: 'reindex',
  });
  assert.equal(pageData.text, 'hi');
});

test('other messages pass through as they are', () => {
  const { ctx, sent } = loadContent();
  const msg = { resultData: { url: 'u', title: 't', query: 'q' } };
  ctx.chrome.runtime.sendMessage(msg);
  assert.equal(sent[0], msg);
});

test('oversized html is cut after a complete tag', () => {
  const { ctx, sent } = loadContent();
  const html = '<p>' + 'a'.repeat(3 * 1024 * 1024) + '</p><p>' + 'b'.repeat(10) + '</p>';
  const text = 'c'.repeat(2 * 1024 * 1024);
  let replied;
  ctx.chrome.runtime.sendMessage({ pageData: { url: 'u', html, text } }, (r) => (replied = r));
  const d = sent[0].pageData;
  assert.ok(d.html.length <= 2 * 1024 * 1024);
  assert.equal(d.html, html.slice(0, d.html.length));
  assert.ok(d.html.endsWith('>'));
  assert.equal('text' in d, false);
  assert.equal(replied.status_code, 201);
});

test('without HTML, oversized text is cut at the cap', () => {
  const { ctx, sent } = loadContent();
  ctx.chrome.runtime.sendMessage({ pageData: { url: 'u', html: '', text: 'c'.repeat(2 * 1024 * 1024) } });
  assert.equal(sent[0].pageData.text.length, 1024 * 1024);
});

test('text is never cut inside a surrogate pair', () => {
  const { ctx, sent } = loadContent();
  const text = 'x'.repeat(1024 * 1024 - 1) + '😀' + 'y';
  ctx.chrome.runtime.sendMessage({ pageData: { url: 'u', html: '', text } });
  assert.equal(sent[0].pageData.text, 'x'.repeat(1024 * 1024 - 1));
});

test('every capture is tagged with the client, keeping existing metadata', async () => {
  const bodies = [];
  const { ctx, storage } = loadBackground({
    network: (url, init) => {
      if (!url.endsWith('api/add')) return new Response('{}', { status: 200 });
      bodies.push(JSON.parse(init.body));
      return new Response('', { status: 201 });
    },
  });
  await ctx.fetch(BASE + 'api/add', addInit({ url: 'https://a.example/', metadata: { ignore_skip_rules: true } }));
  assert.deepEqual(bodies[0].metadata, { source: 'shiori', ignore_skip_rules: true, client: 'shiori', client_version: '9.8.7' });
  assert.equal(queued(storage).length, 0);
});

test("a PDF saved with Safari's placeholder title gets one from its file name, and the client tag", async () => {
  const bodies = [];
  const { ctx } = loadBackground({
    network: (url, init) => {
      if (url.endsWith('api/add_pdf')) bodies.push(JSON.parse(init.body));
      return new Response('', { status: 201 });
    },
  });
  const pdfURL = 'https://files.example/docs/Sample_Report_2021.pdf';
  await ctx.fetch(BASE + 'api/add_pdf', addInit({ document: { url: pdfURL, title: 'Start Page' }, pdf: 'JVBERi0=' }));
  assert.equal(bodies[0].document.title, 'Sample Report 2021');
  assert.equal(bodies[0].document.metadata.client, 'shiori');
  assert.equal(bodies[0].pdf, 'JVBERi0=');
  await ctx.fetch(BASE + 'api/add_pdf', addInit({ document: { url: pdfURL, title: 'Quarterly Report' }, pdf: 'x' }));
  assert.equal(bodies[1].document.title, 'Quarterly Report');
});

test("a page keeps its own title, even 'Start Page'; only a missing one comes from the URL", async () => {
  const bodies = [];
  const { ctx } = loadBackground({
    network: (url, init) => {
      if (url.endsWith('api/add')) bodies.push(JSON.parse(init.body));
      return new Response('', { status: 201 });
    },
  });
  await ctx.fetch(BASE + 'api/add', addInit({ url: 'https://intranet.example/start', title: 'Start Page' }));
  await ctx.fetch(BASE + 'api/add', addInit({ url: 'https://a.example/docs/read-me.html', title: '' }));
  assert.equal(bodies[0].title, 'Start Page');
  assert.equal(bodies[1].title, 'read me');
});

test('a queued capture keeps its client tag', async () => {
  const { ctx, storage } = loadBackground({ network: offline });
  await ctx.fetch(BASE + 'api/add', addInit({ url: 'https://a.example/' }));
  const [entry] = queued(storage);
  const { metadata } = JSON.parse(storage.data[entry.key].body);
  assert.equal(metadata.client, 'shiori');
  assert.equal(metadata.source, 'shiori');
  assert.equal(metadata.client_version, '9.8.7');
});

test('with no rules ever fetched, an offline capture is not queued', async () => {
  const storage = fakeStorage({ histerURL: BASE });
  const { ctx } = loadBackground({ network: offline, storage });
  await assert.rejects(ctx.fetch(BASE + 'api/add', addInit({ url: 'https://bank.example/' })));
  assert.equal(queued(storage).length, 0);
});

test('the worker fetches the rules at start, so the next offline capture can queue', async () => {
  let online = true;
  const storage = fakeStorage({ histerURL: BASE });
  const { ctx } = loadBackground({
    network: (url) => {
      if (!online) offline();
      return new Response('{"skip":["bank"]}', { status: 200 });
    },
    storage,
  });
  await settle();
  assert.equal(storage.data.shioriCachedRules, '{"skip":["bank"]}');
  online = false;
  const r = await ctx.fetch(BASE + 'api/add', addInit({ url: 'https://a.example/' }));
  assert.equal(r.status, 201);
  assert.equal(queued(storage).length, 1);
});

test('queued captures never store credentials, and replays use the current token', async () => {
  let online = false;
  const replayed = [];
  const storage = fakeStorage({ histerURL: BASE, ...RULES, histerToken: 'new-token' });
  const { ctx } = loadBackground({
    network: (url, init) => {
      if (!online) offline();
      if (url.endsWith('api/add')) replayed.push(init.headers);
      return new Response('{}', { status: url.endsWith('api/add') ? 201 : 200 });
    },
    storage,
  });
  const init = addInit({ url: 'https://a.example/' });
  init.headers = { ...init.headers, 'X-Access-Token': 'old-token', Cookie: 'a=b' };
  await ctx.fetch(BASE + 'api/add', init);
  const [entry] = queued(storage);
  const stored = storage.data[entry.key].headers;
  assert.equal(stored['X-Access-Token'], undefined);
  assert.equal(stored.Cookie, undefined);
  online = true;
  await ctx.fetch(BASE + 'api/rules');
  await settle();
  assert.equal(replayed[0]['X-Access-Token'], 'new-token');
});

test('captures queued more than 14 days ago are dropped, not sent', async () => {
  let online = false;
  const sent = [];
  const { ctx, storage } = loadBackground({
    network: (url, init) => {
      if (!online) offline();
      if (url.endsWith('api/add')) sent.push(JSON.parse(init.body).url);
      return new Response('{}', { status: 200 });
    },
  });
  await ctx.fetch(BASE + 'api/add', addInit({ url: 'https://old.example/' }));
  const index = storage.data.shioriQueueIndex;
  index[0].queuedAt = Date.now() - 15 * 24 * 60 * 60 * 1000;
  online = true;
  await ctx.fetch(BASE + 'api/rules');
  await settle();
  assert.deepEqual(sent, []);
  assert.equal(queued(storage).length, 0);
});

// searchPage: the hosted results page's address (build-time), answering
// `pageUp`. nativeGate: a promise each native message waits for first.
function loadCombinedSearch({
  nativeReply,
  nativeThrows = false,
  storage = fakeStorage({}),
  searchPage = '',
  pageUp = async () => new Response('<OpenSearchDescription/>'),
  nativeGate = null,
  network = async () => new Response('{}'),
}) {
  const listeners = [];
  const updates = [];
  const native = [];
  const fetched = [];
  const tabListeners = [];
  const ctx = {
    chrome: {
      storage: { local: storage, onChanged: storage.onChanged },
      runtime: {
        getManifest: () => ({ version: '9.8.7' }),
        getURL: (p) => `safari-web-extension://x/${p}`,
        sendNativeMessage: async (_app, message) => {
          native.push(message);
          if (nativeGate) await nativeGate();
          if (nativeThrows) throw new Error('no native');
          return nativeReply;
        },
        onMessage: { addListener: (l) => listeners.push(l) },
      },
      tabs: {
        update: async (id, props) => updates.push([id, props.url]),
        onUpdated: { addListener: (l) => tabListeners.push(l) },
      },
    },
    fetch: async (input, init) => {
      const url = typeof input === 'string' ? input : input.url;
      fetched.push(url);
      return searchPage && url.startsWith(searchPage) ? pageUp(url, init) : network(url, init);
    },
    Response, Headers, URL, TypeError, JSON, setTimeout, clearTimeout, console, Date, AbortController,
  };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(backgroundShim.replace('__SHIORI_SEARCH_PAGE_URL__', searchPage), ctx);
  const tabLoading = (url, tabId = 7) => tabListeners.forEach((l) => l(tabId, { status: 'loading', url }, { id: tabId, url }));
  const send = (request, tabId = 7) =>
    new Promise((resolve) => {
      let answered = false;
      for (const l of listeners) {
        const keepOpen = l(request, { tab: { id: tabId } }, (r) => {
          answered = true;
          resolve(r);
        });
        if (keepOpen === true) return;
      }
      if (!answered) resolve(undefined);
    });
  return { ctx, send, updates, storage, listeners, native, fetched, tabLoading };
}

test("a search from the results page joins the app's recent searches", async () => {
  const { send, storage, native } = loadCombinedSearch({
    nativeReply: { combinedSearch: true, recentSearches: ['rust async', 'go'] },
  });
  await settle();
  const reply = await send({ shiori: 'record-search', q: '  rust async ' });
  assert.equal(reply.ok, true);
  const plain = (v) => JSON.parse(JSON.stringify(v));
  assert.deepEqual(plain(native.filter((m) => m.type === 'recent')), [{ type: 'recent', q: 'rust async' }]);
  assert.deepEqual(plain(storage.data.shioriSettings.recentSearches), ['rust async', 'go']);
});

test("the results page's settings go to the app, and a fresh copy comes back", async () => {
  const { send, native } = loadCombinedSearch({ nativeReply: { combinedSearch: true, histerCount: 10 } });
  await settle();
  const reply = await send({ shiori: 'set-settings', values: { histerCount: 10 } });
  assert.equal(reply.ok, true);
  assert.equal(reply.settings.histerCount, 10);
  const sets = JSON.parse(JSON.stringify(native.filter((m) => m.type === 'set-settings')));
  assert.deepEqual(sets, [{ type: 'set-settings', values: { histerCount: 10 } }]);
});

test('without the app, a settings change still holds on this device', async () => {
  const { send, storage } = loadCombinedSearch({ nativeThrows: true });
  await settle();
  const reply = await send({ shiori: 'set-settings', values: { theme: 'day', showInfobox: false } });
  assert.equal(reply.ok, true);
  assert.equal(storage.data.shioriSettings.theme, 'day');
  assert.equal(storage.data.shioriSettings.showInfobox, false);
});

test("the extension's Hister server follows the app's", async () => {
  const storage = fakeStorage({ histerURL: 'https://old.example/' });
  loadCombinedSearch({ nativeReply: { combinedSearch: true, serverURL: 'https://hister.example', textSize: 'xLarge' }, storage });
  await settle();
  assert.equal(storage.data.histerURL, 'https://hister.example/');
  assert.equal(storage.data.shioriSettings.textSize, 'xLarge');
});

test('without the app, the extension keeps its own Hister server', async () => {
  const storage = fakeStorage({ histerURL: 'https://mine.example/' });
  loadCombinedSearch({ nativeThrows: true, storage });
  await settle();
  assert.equal(storage.data.histerURL, 'https://mine.example/');
});

test('recording a search survives the app being unreachable, and ignores blanks', async () => {
  const { send, native } = loadCombinedSearch({ nativeThrows: true });
  await settle();
  assert.equal((await send({ shiori: 'record-search', q: 'go' })).ok, true);
  assert.equal(await send({ shiori: 'record-search', q: '   ' }), undefined);
  assert.equal(native.filter((m) => m.type === 'recent').length, 1);
});

test('combined search takes a DuckDuckGo search over when the app says so', async () => {
  const { send, updates, storage } = loadCombinedSearch({
    nativeReply: { combinedSearch: true, searxngURL: 'https://searx.example/', theme: 'night' },
  });
  await settle();
  const reply = await send({ shiori: 'search', q: 'go concurrency' });
  assert.equal(reply.redirect, true);
  assert.deepEqual(updates, [[7, 'safari-web-extension://x/search.html?q=go%20concurrency']]);
  assert.equal(storage.data.shioriSettings.searxngURL, 'https://searx.example/');
  assert.equal(storage.data.shioriSettings.theme, 'night');
});

test('combined search leaves DuckDuckGo alone when switched off in the app', async () => {
  const { send, updates } = loadCombinedSearch({ nativeReply: { combinedSearch: false } });
  await settle();
  const reply = await send({ shiori: 'search', q: 'go' });
  assert.equal(reply.redirect, false);
  assert.equal(updates.length, 0);
});

test('without the app (native messaging fails) combined search defaults to on', async () => {
  const { send, updates } = loadCombinedSearch({ nativeThrows: true });
  await settle();
  const reply = await send({ shiori: 'search', q: 'go' });
  assert.equal(reply.redirect, true);
  assert.equal(updates.length, 1);
});

test("upstream's message listeners never see Shiori's messages", async () => {
  const { ctx, listeners } = loadCombinedSearch({ nativeReply: {} });
  const seen = [];
  ctx.chrome.runtime.onMessage.addListener((request) => {
    seen.push(request);
  });
  const upstream = listeners[listeners.length - 1];
  upstream({ shiori: 'search', q: 'x' }, {}, () => {});
  upstream({ pageData: { url: 'u' } }, {}, () => {});
  assert.equal(seen.length, 1);
  assert.equal(seen[0].pageData.url, 'u');
});

test('coming Back to a search Shiori took over stays on DuckDuckGo, once', async () => {
  const { send, updates } = loadCombinedSearch({ nativeReply: { combinedSearch: true } });
  await settle();
  assert.equal((await send({ shiori: 'search', q: 'go' })).redirect, true);
  // Back: DuckDuckGo loads again in the same tab with the same search.
  assert.equal((await send({ shiori: 'search', q: 'go' })).redirect, false);
  // A different search, or the same one later, is taken over again.
  assert.equal((await send({ shiori: 'search', q: 'rust' })).redirect, true);
  assert.equal((await send({ shiori: 'search', q: 'go' })).redirect, true);
  // Other tabs are separate.
  assert.equal((await send({ shiori: 'search', q: 'go' }, 8)).redirect, true);
  assert.equal(updates.length, 4);
});

test('a switch flipped in the app counts for the very next search', async () => {
  const reply = { combinedSearch: true };
  const { send } = loadCombinedSearch({ nativeReply: reply });
  await settle();
  assert.equal((await send({ shiori: 'search', q: 'a' })).redirect, true);
  reply.combinedSearch = false;
  assert.equal((await send({ shiori: 'search', q: 'b' })).redirect, false);
});

test('coming back via DuckDuckGo after opening a result returns to the results page', async () => {
  const { send, updates } = loadCombinedSearch({ nativeReply: { combinedSearch: true } });
  await settle();
  assert.equal((await send({ shiori: 'search', q: 'pi' })).redirect, true);
  // The results page (at ?q=pi&page=2) says the tab left for a result.
  await send({ shiori: 'left-for-result', q: 'pi', search: '?q=pi&page=2' });
  // Back skips the extension page and lands on DuckDuckGo with the same search.
  assert.equal((await send({ shiori: 'search', q: 'pi' })).redirect, true);
  assert.equal(updates[1][1], 'safari-web-extension://x/search.html?q=pi&page=2');
  // Back again from the results page itself stays on DuckDuckGo.
  assert.equal((await send({ shiori: 'search', q: 'pi' })).redirect, false);
});

test('the results page opening just after a search is answered without asking the app again', async () => {
  const { send, native } = loadCombinedSearch({ nativeReply: { combinedSearch: true } });
  await settle();
  await send({ shiori: 'search', q: 'go' });
  const asked = native.filter((m) => m.type === 'settings').length;
  assert.equal((await send({ shiori: 'refresh-settings' })).ok, true);
  assert.equal(native.filter((m) => m.type === 'settings').length, asked);
});

test('a settings change waits out a request that set off before it, then asks again', async () => {
  let release;
  let gate = null;
  const reply = { combinedSearch: true, histerCount: 5 };
  const { send, native } = loadCombinedSearch({ nativeReply: reply, nativeGate: () => gate });
  await settle();
  gate = new Promise((r) => (release = r));
  const search = send({ shiori: 'search', q: 'go' }); // asks the app, held back
  await settle();
  reply.histerCount = 10;
  const change = send({ shiori: 'set-settings', values: { histerCount: 10 } });
  release();
  gate = null;
  await search;
  const answer = await change;
  assert.equal(answer.settings.histerCount, 10);
  assert.equal(native.filter((m) => m.type === 'settings').length, 3); // start, search, after the change
});

test("the hosted page is checked alongside the app's settings, not after them", async () => {
  let release;
  let gate = null;
  const { send, fetched } = loadCombinedSearch({
    nativeReply: { combinedSearch: true },
    searchPage: 'https://search.example/',
    nativeGate: () => gate,
  });
  await settle();
  gate = new Promise((r) => (release = r));
  const reply = send({ shiori: 'search', q: 'go' });
  await settle();
  // The app hasn't answered yet, and the check is already out.
  assert.ok(fetched.includes('https://search.example/_shiori/opensearch.xml'));
  release();
  gate = null;
  const answer = await reply;
  assert.equal(answer.redirect, true);
  assert.equal(answer.url, 'https://search.example/?q=go');
});

test('a DuckDuckGo search starting to load checks the hosted page early, once a minute at most', async () => {
  const { send, fetched, tabLoading } = loadCombinedSearch({
    nativeReply: { combinedSearch: true },
    searchPage: 'https://search.example/',
  });
  await settle();
  const checks = () => fetched.filter((u) => u.endsWith('opensearch.xml')).length;
  tabLoading('https://example.com/?q=go');
  tabLoading('https://duckduckgo.com/about');
  await settle();
  assert.equal(checks(), 0);
  tabLoading('https://duckduckgo.com/?t=h_&q=go');
  tabLoading('https://duckduckgo.com/?q=go');
  await settle();
  assert.equal(checks(), 1);
  assert.equal((await send({ shiori: 'search', q: 'go' })).url, 'https://search.example/?q=go');
  assert.equal(checks(), 1);
});

test("with the hosted page down, results open on the extension's own page", async () => {
  const { send, updates } = loadCombinedSearch({
    nativeReply: { combinedSearch: true },
    searchPage: 'https://search.example/',
    pageUp: async () => {
      throw new TypeError('Load failed');
    },
  });
  await settle();
  const answer = await send({ shiori: 'search', q: 'go' });
  assert.equal(answer.redirect, true);
  assert.equal(answer.url, undefined);
  assert.deepEqual(updates, [[7, 'safari-web-extension://x/search.html?q=go']]);
});

test('the build prepends the Safari background files in the order these tests load them', () => {
  const build = read('../scripts/build-extension.sh');
  assert.ok(build.includes('BACKGROUND=(' + SAFARI_BACKGROUND.join(' ') + ')\n'));
  assert.ok(build.includes('prepend background.js "${BACKGROUND[@]}"'));
});

test('on Safari the app owns the server: the extension never sets it', async () => {
  const storage = fakeStorage({ histerURL: 'https://kept.example/' });
  const { listeners } = loadCombinedSearch({ nativeReply: {}, storage });
  // Even from the settings page's own address: the app sets the server.
  const sender = { url: 'safari-web-extension://x/shiori-settings.html', tab: { id: 9 } };
  const reply = await new Promise((resolve) => {
    for (const l of listeners) if (l({ shiori: 'set-server', url: 'https://evil.example/' }, sender, resolve) === true) return;
    resolve(undefined);
  });
  assert.equal(reply.ok, false);
  assert.equal(storage.data.histerURL, 'https://kept.example/');
});

// --- the queue follows a server set elsewhere (the app, a fresh install) ---

const queuedItem = (key, url, pageURL = 'https://a.example/') => ({
  index: { key, pageURL, bytes: 2, attempts: 0, queuedAt: Date.now() },
  item: { url, headers: {}, body: JSON.stringify({ url: pageURL }) },
});

test("the app's new server: queued pages follow it, its rules replace the old ones, the queue drains", async () => {
  const q = queuedItem('shioriQueueItem:1', 'https://old.example/api/add');
  const storage = fakeStorage(
    { histerURL: 'https://old.example/', shioriCachedRules: '{"skip":["old"]}', shioriQueueIndex: [q.index], [q.index.key]: q.item },
    { events: true },
  );
  const sent = [];
  const { fetched } = loadCombinedSearch({
    nativeReply: { serverURL: 'https://new.example' },
    storage,
    network: async (url, init) => {
      if (url.startsWith('https://old.example/')) throw new TypeError('the old server is gone');
      if (url === 'https://new.example/api/rules') return new Response('{"skip":["new"]}');
      if (init && init.method === 'POST') sent.push(url);
      return new Response('{}', { status: 201 });
    },
  });
  for (let i = 0; i < 10 && !sent.length; i++) await settle();
  assert.equal(storage.data.histerURL, 'https://new.example/');
  assert.equal(storage.data.shioriCachedRules, '{"skip":["new"]}');
  assert.ok(fetched.includes('https://new.example/api/rules'));
  assert.deepEqual(sent, ['https://new.example/api/add']);
  assert.equal(queued(storage).length, 0);
});

test('a fresh install fetches the rules once its server is stored, so the first offline capture is queued', async () => {
  const storage = fakeStorage({}, { events: true });
  const { ctx } = loadBackground({
    storage,
    network: async (url) => {
      if (url === BASE + 'api/rules') return new Response('{"skip":[]}');
      throw new TypeError('Load failed');
    },
  });
  await settle();
  assert.equal('shioriCachedRules' in storage.data, false);
  await storage.set({ histerURL: BASE }); // upstream's default, written on install
  await settle();
  assert.equal(storage.data.shioriCachedRules, '{"skip":[]}');
  const r = await ctx.fetch(BASE + 'api/add', addInit({ url: 'https://a.example/' }));
  assert.equal(r.status, 201);
  assert.equal(queued(storage).length, 1);
});

test('the same server written again changes nothing', async () => {
  const storage = fakeStorage({ histerURL: BASE, ...RULES }, { events: true });
  const { calls } = loadBackground({ storage, network: offline });
  await settle();
  const before = calls.length;
  await storage.set({ histerURL: BASE.slice(0, -1) }); // without its slash
  await settle();
  assert.equal(storage.data.shioriCachedRules, RULES.shioriCachedRules);
  assert.equal(calls.length, before);
});

test('a server moved inside the old address moves each queued page once', async () => {
  const a = queuedItem('shioriQueueItem:1', 'https://h.example/api/add', 'https://a.example/');
  const b = queuedItem('shioriQueueItem:2', 'https://h.example/x/api/add', 'https://b.example/');
  const storage = fakeStorage(
    { histerURL: 'https://h.example/', ...RULES, shioriQueueIndex: [a.index, b.index], [a.index.key]: a.item, [b.index.key]: b.item },
    { events: true },
  );
  loadBackground({ storage, network: offline });
  await settle();
  await storage.set({ histerURL: 'https://h.example/x/' });
  await settle();
  assert.equal(storage.data[a.index.key].url, 'https://h.example/x/api/add');
  assert.equal(storage.data[b.index.key].url, 'https://h.example/x/api/add');
});

test("Safari's whole background on the Mac: the badge counts the queue and the right-click menu is made", async () => {
  const created = [];
  const badge = [];
  const ctx = {
    chrome: {
      storage: { local: fakeStorage({ histerURL: BASE, ...RULES, shioriQueueIndex: [{ key: 'k', pageURL: 'https://a.example/' }] }), onChanged: { addListener() {} } },
      runtime: { getManifest: () => ({ version: '9.8.7' }), getURL: (p) => `safari-web-extension://x/${p}`, onMessage: { addListener() {} } },
      action: {
        setIcon: () => Promise.resolve(),
        setBadgeText: (d) => (badge.push(d.text), Promise.resolve()),
        setBadgeBackgroundColor: () => Promise.resolve(),
        setTitle: () => Promise.resolve(),
      },
      contextMenus: { removeAll: (done) => void setTimeout(done), create: (item) => created.push(item.id), onClicked: { addListener() {} } },
      commands: { onCommand: { addListener() {} } },
      tabs: { update: async () => {}, onUpdated: { addListener() {} } },
    },
    fetch: async () => new Response('{}'),
    Response, Headers, URL, URLSearchParams, TypeError, JSON, setTimeout, clearTimeout, console, Date, AbortController,
  };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(backgroundShim, ctx);
  await settle();
  assert.deepEqual(badge, ['1']);
  assert.deepEqual(created, ['shiori-search', 'shiori-save-link', 'shiori-save-page', 'shiori-never-page', 'shiori-never-site']);
  assert.equal(typeof ctx.ShioriSearch.histerText, 'function');
});
