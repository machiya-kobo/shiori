// Tests for the Machiya sign-in: search-core.js's twin of HisterKit's
// Machiya (pairing, the token's header, the host rule). The cases match
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
