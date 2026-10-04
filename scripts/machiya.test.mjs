// Tests for the Machiya sign-in: search-core.js's twin of HisterKit's
// Machiya (pairing, the token's header, the host rule), and the
// extension's background using it (patches/ext/core.js on
// host-native.js: the app keeps it). The cases match
// MachiyaTests.swift.
// Run: node --test scripts/*.test.mjs

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const read = (rel) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8');
const coreSource = read('../patches/shiori/search-core.js');
const ctx = { URL, URLSearchParams };
ctx.globalThis = ctx;
vm.createContext(ctx);
vm.runInContext(coreSource, ctx);
const S = ctx.ShioriSearch;
const plain = (v) => JSON.parse(JSON.stringify(v));

const KURA = 'https://kura.example/';
const KONBINI = 'https://konbini.example/';
const HISTER = 'https://hister.example/';
const SEARX = 'https://searx.example/';
const ROOMS = S.machiyaRooms([KURA, KONBINI], [HISTER, SEARX]);
const TOKEN = 'mch_q9xa_' + 'A'.repeat(43);
const DEVICE_TOKEN = 'mcd_eyJwIjoiYWxleCJ9.c2lnbmF0dXJl';

// --- the shared logic ---

test('a pairing code is uppercased, its spaces and dashes gone', () => {
  assert.equal(S.machiyaCode('abcd-efgh'), 'ABCDEFGH');
  assert.equal(S.machiyaCode('  abcd efgh '), 'ABCDEFGH');
  assert.equal(S.machiyaCode('ab-cd - ef\tgh'), 'ABCDEFGH');
  assert.equal(S.machiyaCode(''), '');
  assert.equal(S.machiyaCode(' - '), '');
  assert.equal(S.machiyaCode('abcd/efgh'), '');
  assert.equal(S.machiyaCode(null), '');
});

test('a token is mch_ or mcd_, trimmed, with nothing that could split a header', () => {
  assert.equal(S.machiyaToken(`  ${TOKEN}\n`), TOKEN);
  assert.equal(S.machiyaToken(DEVICE_TOKEN), DEVICE_TOKEN);
  assert.equal(S.machiyaToken('Bearer ' + TOKEN), '');
  assert.equal(S.machiyaToken('mch_short'), '');
  assert.equal(S.machiyaToken(TOKEN + '\r\nX-Evil: 1'), '');
  assert.equal(S.machiyaToken('mcx_' + 'A'.repeat(20)), '');
  assert.equal(S.machiyaToken(undefined), '');
  assert.equal(S.machiyaAuthHeader(TOKEN), 'Bearer ' + TOKEN);
});

test("a device's label has no control characters and at most 64 characters", () => {
  assert.equal(S.machiyaDevice(' iPhone\n'), 'iPhone');
  assert.equal(S.machiyaDevice(''), 'Shiori');
  assert.equal(S.machiyaDevice('\u0007', 'Firefox'), 'Firefox');
  assert.equal([...S.machiyaDevice('é'.repeat(80))].length, 64);
});

test('the token goes to exactly the configured Kura and Konbini, by origin', () => {
  const yes = [
    'https://kura.example/api/search?q=x',
    'https://KURA.example/api/vaults',
    'https://kura.example:443/api/note',
    'https://konbini.example/api/cards',
    'https://kura.example/other/path',
  ];
  for (const url of yes) assert.equal(S.mayCarryMachiyaToken(url, ROOMS), true, url);
  const no = [
    HISTER + 'api/add', // Hister
    SEARX + 'search?q=x', // SearXNG
    'https://kura.example@evil.example/api/search', // userinfo trick: the host is evil.example
    'https://user:pw@kura.example/api/search', // userinfo on the room itself: not plain, refused
    'https://kura.example.evil.example/', // lookalike: a longer host
    'https://evilkura.example/', // lookalike: a prefix
    'https://kura.example:8443/', // another port
    'http://kura.example/', // http where https is configured
    'https://evil.example/?u=https://kura.example/', // the room only in the query
    'ftp://kura.example/',
    'javascript:alert(1)',
    'not a url',
    '',
  ];
  for (const url of no) assert.equal(S.mayCarryMachiyaToken(url, ROOMS), false, url);
});

test('the rooms: http(s) bases only, never on Hister or SearXNG', () => {
  assert.deepEqual(plain(ROOMS), ['https://kura.example', 'https://konbini.example']);
  // A room on Hister's origin (one host, /kura/ under it) gets no token at all.
  assert.deepEqual(plain(S.machiyaRooms(['https://hister.example/kura/', KONBINI], [HISTER, SEARX])), ['https://konbini.example']);
  assert.deepEqual(plain(S.machiyaRooms(['', '__SHIORI_NIWA_URL__', 'ftp://kura.example/', 'https://u:p@kura.example/'], [])), []);
  // An http room counts only as configured: http, its own port.
  const local = S.machiyaRooms(['http://localhost:8080/'], []);
  assert.equal(S.mayCarryMachiyaToken('http://localhost:8080/api/vaults', local), true);
  assert.equal(S.mayCarryMachiyaToken('https://localhost:8080/api/vaults', local), false);
  assert.equal(S.mayCarryMachiyaToken('http://localhost/api/vaults', local), false);
});

test("a room's fetch gets the header and refuses redirects; anything else is left alone", () => {
  const init = { credentials: 'omit', headers: { Accept: 'application/json' } };
  const kura = S.machiyaFetchOptions(KURA + 'api/search', TOKEN, ROOMS, init);
  assert.deepEqual(plain(kura), { credentials: 'omit', headers: { Accept: 'application/json', Authorization: 'Bearer ' + TOKEN }, redirect: 'error' });
  for (const url of [HISTER + 'search', SEARX + 'search', 'https://kura.example@evil.example/']) {
    assert.equal(S.machiyaFetchOptions(url, TOKEN, ROOMS, init), init, url);
  }
  assert.equal(S.machiyaFetchOptions(KURA, '', ROOMS, init), init);
  assert.equal(S.machiyaFetchOptions(KURA, 'not a token', ROOMS, init), init);
});

/** A fake fetch answering `status` with `body`, recording the call. */
function fakeFetch(status, body) {
  const calls = [];
  const fn = async (url, init) => {
    calls.push({ url, init });
    return new Response(typeof body === 'string' ? body : JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
  };
  return { fn, calls };
}

test('pairing posts the normalised code and the device, and answers the token and who', async () => {
  const { fn, calls } = fakeFetch(200, { token: DEVICE_TOKEN, principal: 'alex' });
  const reply = await S.machiyaPair('https://kura.example', 'abcd-efgh', 'Firefox', fn);
  assert.deepEqual(plain(reply), { token: DEVICE_TOKEN, principal: 'alex' });
  const [call] = calls;
  assert.equal(call.url, 'https://kura.example/api/pair');
  assert.equal(call.init.method, 'POST');
  assert.equal(call.init.headers['Content-Type'], 'application/json');
  assert.equal(call.init.credentials, 'omit');
  assert.equal(call.init.redirect, 'error');
  assert.deepEqual(JSON.parse(call.init.body), { code: 'ABCDEFGH', device: 'Firefox' });
});

test("pairing's refusals say what to do", async () => {
  const cases = [
    [401, { error: 'unknown or expired code' }, 'bad-code', /wrong or has expired/],
    [429, { error: 'too many tries' }, 'throttled', /Wait ten minutes/],
    [415, { error: 'send JSON' }, 'not-json', /JSON/],
    [404, { error: 'not found' }, 'no-signin', /no sign-in/],
    [400, { error: 'send {"code": ...}' }, 'invalid', /pairing code/],
    [503, 'unavailable', 'server', /HTTP 503/],
    [200, { principal: 'alex' }, 'bad-reply', /no token/],
    [200, { token: 'Bearer x', principal: 'alex' }, 'bad-reply', /no token/],
  ];
  for (const [status, body, kind, message] of cases) {
    const { fn } = fakeFetch(status, body);
    await assert.rejects(S.machiyaPair(KURA, 'ABCD-EFGH', 'Firefox', fn), (error) => {
      assert.equal(error.kind, kind, String(status));
      assert.match(error.message, message);
      return true;
    });
  }
  await assert.rejects(S.machiyaPair(KURA, 'ABCD', 'x', async () => { throw new TypeError('offline'); }), (e) => e.kind === 'unreachable');
});

test("rooms in Hister sign-in mode get Hister's token as X-Access-Token, beside the identity token, under the same host rule", () => {
  const init = { headers: { Accept: 'application/json' }, credentials: 'omit' };
  const HISTER = 'ABCDEFGHJKLMNPQRSTUVWXYZ23';
  const both = S.machiyaFetchOptions(KURA + 'api/search', TOKEN, ROOMS, init, { histerToken: HISTER });
  assert.deepEqual(plain(both.headers), { Accept: 'application/json', Authorization: 'Bearer ' + TOKEN, 'X-Access-Token': HISTER });
  assert.equal(both.redirect, 'error');
  const only = S.machiyaFetchOptions(KURA + 'api/search', '', ROOMS, init, { histerToken: HISTER });
  assert.deepEqual(plain(only.headers), { Accept: 'application/json', 'X-Access-Token': HISTER });
  // Never to Hister, SearXNG or any other host; nothing that isn't a token.
  for (const url of ['https://hister.example/search', 'https://evil.example/', 'https://kura.example.evil.example/']) {
    assert.equal(S.machiyaFetchOptions(url, '', ROOMS, init, { histerToken: HISTER }), init, url);
  }
  assert.equal(S.machiyaFetchOptions(KURA, '', ROOMS, init, { histerToken: 'not a token' }), init);
});

test('pairing sends nothing without a code or a room', async () => {
  const { fn, calls } = fakeFetch(200, {});
  await assert.rejects(S.machiyaPair(KURA, ' - ', 'x', fn), (e) => e.kind === 'invalid');
  await assert.rejects(S.machiyaPair('', 'ABCD', 'x', fn), (e) => e.kind === 'no-room');
  await assert.rejects(S.machiyaPair('https://u:p@kura.example/', 'ABCD', 'x', fn), (e) => e.kind === 'no-room');
  assert.equal(calls.length, 0);
});

test("the sign-in field takes a token or a code, and the status line names who", () => {
  assert.deepEqual(plain(S.machiyaEntry(` ${TOKEN} `)), { token: TOKEN });
  assert.deepEqual(plain(S.machiyaEntry('abcd-efgh')), { code: 'ABCDEFGH' });
  assert.equal(S.machiyaEntry(''), null);
  assert.equal(S.machiyaEntry('what?'), null);
  assert.equal(S.machiyaStatusText({}), 'Not signed in');
  assert.equal(S.machiyaStatusText({ token: TOKEN, principal: 'alex' }), 'Signed in as alex');
  assert.equal(S.machiyaStatusText({ token: TOKEN, principal: '' }), 'Signed in with a token');
  assert.equal(S.machiyaSignInURL('https://kura.example'), 'https://kura.example/signin');
  assert.equal(S.machiyaSignInURL(''), '');
});

// --- the extension's background ---

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

const RULES = { shioriCachedRules: '{"skip":[]}' };
const SETTINGS = { niwaURL: KURA, konbiniURL: KONBINI, searxngURL: SEARX };

/** The background as Safari runs it, `native` answering for the app. */
function loadBackground({ storage, network = async () => new Response('{}'), native = async () => ({}) }) {
  const listeners = [];
  const fetched = [];
  const nativeSent = [];
  const scheme = 'safari-web-extension';
  const sandbox = {
    chrome: {
      storage: { local: storage },
      runtime: {
        getManifest: () => ({ version: '9.8.7' }),
        getURL: (p) => `${scheme}://x/${p}`,
        onMessage: { addListener: (l) => listeners.push(l) },
        sendNativeMessage: async (_app, message) => (nativeSent.push(message), native(message)),
      },
      tabs: { update: async () => {}, onUpdated: { addListener() {} } },
    },
    fetch: async (input, init) => {
      const url = typeof input === 'string' ? input : input.url;
      fetched.push({ url, init });
      return network(url, init);
    },
    Response, Headers, URL, URLSearchParams, TypeError, JSON, setTimeout, clearTimeout, console, Date, AbortController, Promise,
  };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext([read('../patches/ext/host-native.js'), read('../patches/ext/core.js'), coreSource].join('\n'), sandbox);
  const send = (request, sender) =>
    new Promise((resolve) => {
      for (const l of listeners) if (l(request, sender, resolve) === true) return;
      resolve(undefined);
    });
  const page = (name) => ({ url: `${scheme}://x/${name}`, tab: { id: 9 } });
  return { sandbox, send, page, fetched, nativeSent, storage };
}

const settle = () => new Promise((r) => setTimeout(r, 20));
/** The app: its settings, and the sign-in from its Keychain (none when token is empty). */
const app = (settings = SETTINGS, token = TOKEN) => async (message) =>
  message.type === 'machiya' ? (token ? { token, principal: 'alex' } : {}) : message.type === 'settings' ? settings : {};
const CONTENT_SCRIPT = { url: 'https://evil.example/', tab: { id: 3 } };

test('nothing in the extension signs in or out; a web page never gets the token', async () => {
  const storage = fakeStorage({ histerURL: HISTER, ...RULES, shioriSettings: SETTINGS });
  const { send, page } = loadBackground({ storage, native: app() });
  await settle();
  for (const sender of [CONTENT_SCRIPT, page('search.html'), page('shiori-options.html'), { tab: { id: 3 } }]) {
    assert.equal((await send({ shiori: 'machiya-sign-out' }, sender)).ok, false);
    assert.equal((await send({ shiori: 'machiya-sign-in', entry: 'mch_evil_' + 'B'.repeat(40) }, sender)).ok, false);
  }
  for (const sender of [CONTENT_SCRIPT, { tab: { id: 3 } }, { url: 'safari-web-extension://other/search.html' }]) {
    const reply = await send({ shiori: 'machiya' }, sender);
    assert.equal(reply.ok, false);
    assert.equal(reply.token, undefined);
  }
  // The results page (an extension page) gets it, for its own fetches.
  assert.equal((await send({ shiori: 'machiya' }, page('search.html'))).token, TOKEN);
});

test("Kura's vaults are asked with the token; Hister's captures never carry it, queued or sent", async () => {
  const storage = fakeStorage({ histerURL: HISTER, ...RULES, shioriSettings: SETTINGS });
  let online = true;
  const { sandbox, fetched } = loadBackground({
    storage,
    native: app(),
    network: async (url) => {
      if (url === KURA + 'api/vaults') return new Response(JSON.stringify({ vaults: [{ name: 'work', private: false }] }));
      if (!online) throw new TypeError('offline');
      return new Response('{}', { status: 201 });
    },
  });
  await settle();
  // A shared vault's note: Kura is asked afresh, with the sign-in.
  const add = (url, headers = {}) => sandbox.fetch(HISTER + 'api/add', { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify({ url, html: '<p>x</p>' }) });
  await add('https://kura.example/v/work/n/Plan');
  const vaults = fetched.find((f) => f.url === KURA + 'api/vaults');
  assert.equal(vaults.init.headers.Authorization, 'Bearer ' + TOKEN);
  assert.equal(vaults.init.credentials, 'omit');
  assert.equal(vaults.init.redirect, 'error');
  for (const f of fetched.filter((x) => x.url.startsWith(HISTER))) {
    assert.ok(!JSON.stringify(f.init || {}).includes(TOKEN), f.url);
  }
  // Even handed an Authorization header, the queue never stores it, and the replay never sends one.
  online = false;
  await add('https://a.example/', { Authorization: 'Bearer ' + TOKEN });
  const [entry] = storage.data.shioriQueueIndex;
  assert.ok(!JSON.stringify(storage.data[entry.key]).includes(TOKEN));
  online = true;
  fetched.length = 0;
  await sandbox.fetch(HISTER + 'api/rules');
  await settle();
  const replay = fetched.find((f) => f.url === HISTER + 'api/add');
  assert.ok(replay, 'replayed');
  assert.ok(!JSON.stringify(replay.init).includes(TOKEN));
  assert.equal(Object.keys(replay.init.headers).some((k) => k.toLowerCase() === 'authorization'), false);
});

test('Kura on another origin than the settings say gets no token', async () => {
  const evil = { ...SETTINGS, niwaURL: 'https://kura.example.evil.example/' };
  const storage = fakeStorage({ histerURL: HISTER, ...RULES, shioriSettings: evil });
  // The rooms are the settings' Kura and Konbini, nothing else.
  const loaded = loadBackground({ storage, native: app(evil) });
  await settle();
  const run = vm.runInContext('shioriMachiya.rooms()', loaded.sandbox);
  assert.deepEqual(plain(await run), ['https://kura.example.evil.example', 'https://konbini.example']);
  const hister = await vm.runInContext(`shioriMachiya.fetchOptions(${JSON.stringify(HISTER + 'search')}, { credentials: 'omit' })`, loaded.sandbox);
  assert.deepEqual(plain(hister), { credentials: 'omit' });
  const kura = await vm.runInContext(`shioriMachiya.fetchOptions('https://kura.example/api/vaults', { credentials: 'omit' })`, loaded.sandbox);
  assert.deepEqual(plain(kura), { credentials: 'omit' });
});

test('Safari: the token comes from the app over native messaging, and only the app signs in', async () => {
  const storage = fakeStorage({ histerURL: HISTER, ...RULES });
  const { send, page, nativeSent } = loadBackground({ storage, native: app() });
  await settle();
  const reply = await send({ shiori: 'machiya' }, page('search.html'));
  assert.equal(reply.token, TOKEN);
  assert.ok(nativeSent.some((m) => m.type === 'machiya'));
  const status = await send({ shiori: 'machiya-status' }, page('shiori-options.html'));
  assert.deepEqual([status.text, status.owns], ['Signed in as alex', false]);
  assert.equal((await send({ shiori: 'machiya-sign-in', entry: TOKEN }, page('shiori-options.html'))).ok, false);
  assert.equal((await send({ shiori: 'machiya-sign-out' }, page('shiori-options.html'))).ok, false);
  // Never stored by the extension.
  assert.ok(!JSON.stringify(storage.data).includes(TOKEN));
});

test("Safari: the app's handler answers the machiya message from the Keychain", () => {
  const handler = read('../ShioriExtension/SafariWebExtensionHandler.swift');
  assert.match(handler, /case "machiya":[\s\S]*MachiyaKeychain/);
});

test("the results page asks the rooms with the sign-in, and nothing else", () => {
  const page = read('../patches/shiori/search.js');
  const calls = page.split('\n').filter((line) => line.includes('fetchJSON(') && !line.includes('async function fetchJSON'));
  const rooms = calls.filter((line) => /kuraBase|konbiniAPIBase|S\.kuraURL/.test(line));
  assert.ok(rooms.length >= 4, 'Kura search, vaults, note, Konbini cards');
  for (const line of rooms) assert.match(line, /room: true/, line);
  for (const line of calls.filter((l) => !rooms.includes(l))) assert.doesNotMatch(line, /room: true/, line);
  // The hosted page's own host gets its cookie; elsewhere credentials stay 'omit'.
  assert.match(page, /if \(sameOrigin\(url\)\) return \{ \.\.\.init, credentials: 'same-origin' \};/);
  // Every fetchJSON: the page's own host with its cookie (its nginx signs Hister calls in), else 'omit'.
  assert.match(page, /const init = \{ headers, signal: controller\.signal, credentials: sameOrigin\(url\) \? 'same-origin' : 'omit' \};/);
});
