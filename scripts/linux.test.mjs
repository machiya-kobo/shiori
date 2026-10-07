// Shiori for Linux: its pure modules (linux/src/), which GJS runs as they
// are (docs/linux.md). Node's own URL is the reference for the shim,
// and HisterKit's outbox and save rules for the rest.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { ShimURL, ShimURLSearchParams, installURL } from '../linux/src/url.js';
import { newPage, addRequest, titleIn, capped, MAX_HTML_CHARACTERS } from '../linux/src/page.js';
import * as outbox from '../linux/src/outbox.js';
import { parseArgs, saveLinksTarget } from '../linux/src/cli.js';
import { providerQuery, providerResults, activation, notesFromHister, notesSearch, notesFromReply } from '../linux/src/provider.js';
import { roomHeaders, roomOrigins, signInStatus, pairedMessage } from '../linux/src/machiya.js';
import { histerHeaders, histerTokenStatus } from '../linux/src/hister.js';

const plain = (v) => JSON.parse(JSON.stringify(v));

test('the URL shim reads URLs as Node does', () => {
  const urls = [
    'https://www.Example.com/a/b?x=1&utm_source=z&q=hello+world#frag',
    'http://kura.example:8080/n/Projects/Garden%20Plan',
    'https://duckduckgo.com/?q=raspberry+pi&ia=web',
    'https://user:pw@host.example/path/',
    'https://host.example',
    'https://host.example:443/x',
    'https://host.example/?',
    'https://[::1]:3000/v6',
    'https://kura.example@evil.example/api/search',
    'https://user@host.example/',
    'https://KURA.example:443/api',
  ];
  for (const raw of urls) {
    const ours = new ShimURL(raw);
    const node = new URL(raw);
    for (const part of ['protocol', 'username', 'password', 'hostname', 'host', 'port', 'pathname', 'search', 'hash', 'origin', 'href']) {
      assert.equal(ours[part], node[part], `${part} of ${raw}`);
    }
    assert.deepEqual([...ours.searchParams], [...node.searchParams], `params of ${raw}`);
  }
  assert.throws(() => new ShimURL('not a url'));
  assert.throws(() => new ShimURL('/relative/path'));
});

test('URLSearchParams encodes and decodes as Node does', () => {
  const inits = [{ q: 'raspberry pi', title: 'Pages & Notes: 町家', exclude_label: 'vault' }, [['a', '1'], ['a', '2'], ['b', 'x/y+z']], '?a=1&b=two+words&c=%E7%94%BA'];
  for (const init of inits) {
    const ours = new ShimURLSearchParams(init);
    const node = new URLSearchParams(init);
    assert.equal(ours.toString(), node.toString());
    assert.deepEqual([...ours], [...node]);
  }
  const p = new ShimURLSearchParams('a=1&a=2&b=3');
  p.set('a', '9');
  assert.equal(p.toString(), 'a=9&b=3');
  assert.equal(p.get('b'), '3');
  assert.equal(p.get('zzz'), null);
});

test('search-core runs on the shim alone, as in GJS', () => {
  const source = readFileSync(new URL('../patches/shiori/search-core.js', import.meta.url), 'utf8');
  const run = (withShim) => {
    const ctx = withShim ? {} : { URL, URLSearchParams };
    if (withShim) installURL(ctx);
    vm.createContext(ctx);
    vm.runInContext(source, ctx);
    const S = ctx.ShioriSearch;
    return plain([
      S.normalizeURL('https://www.Example.com/a/b/?utm_source=x&q=1'),
      S.shouldRedirect('https://duckduckgo.com/?q=hister&ia=web', 'navigate'),
      S.kuraURL('https://kura.example/', 'hister', { limit: 5 }),
      S.feedURL('https://shiori.example/', { query: 'rust', title: 'Rust' }),
      S.isNoteURL('https://kura.example/n/Projects/Example', 'https://kura.example/'),
      S.histerText('hist'),
    ]);
  };
  assert.deepEqual(run(true), run(false));
});

test('a save is a deliberate, tagged add with Origin hister://', () => {
  const page = newPage({ url: 'https://example.com/a', title: 'A', label: 'books', added: 1790000000.7, clientVersion: '0.9' });
  assert.deepEqual(plain(page), {
    url: 'https://example.com/a', title: 'A', label: 'books', added: 1790000000,
    metadata: { source: 'shiori', client: 'shiori', client_version: '0.9', via: 'linux', ignore_skip_rules: true },
  });
  const req = addRequest('https://hister.example', page);
  assert.equal(req.url, 'https://hister.example/api/add');
  assert.equal(req.headers.Origin, 'hister://');
  assert.deepEqual(JSON.parse(req.body), plain(page));
  assert.throws(() => newPage({ url: 'file:///etc/passwd' }));
  assert.equal(titleIn('<html><head><TITLE> Caf&eacute; &amp; &#x2014; <b>x</b>\n </title>'), 'Caf&eacute; & — x');
  assert.equal(titleIn('<p>none</p>'), '');
  const big = '<p>' + 'x'.repeat(MAX_HTML_CHARACTERS) + '</p>';
  assert.ok(capped(big).endsWith('<p>') && capped(big).length <= MAX_HTML_CHARACTERS);
});

function memoryStore() {
  const files = new Map();
  return {
    files,
    list: async () => [...files.keys()],
    read: async (n) => files.get(n) ?? null,
    write: async (n, t) => void files.set(n, t),
    remove: async (n) => void files.delete(n),
  };
}

test('the outbox keeps one entry per page, and its first time', async () => {
  const store = memoryStore();
  await outbox.enqueue(store, { url: 'https://a.example/', title: 'A' }, { now: 100, id: 'a' });
  await outbox.enqueue(store, { url: 'https://b.example/', title: 'B' }, { now: 200, id: 'b' });
  await outbox.enqueue(store, { url: 'https://a.example/', title: 'A again' }, { now: 300, id: 'c' });
  assert.equal(store.files.size, 2);
  const s = await outbox.status(store);
  assert.equal(s.count, 2);
  const again = [...store.files.values()].map((t) => JSON.parse(t).page).find((p) => p.url === 'https://a.example/');
  assert.equal(again.title, 'A again');
  assert.equal(again.added, 100);
});

test('the outbox sends oldest first and follows the iOS rules', async () => {
  assert.equal(outbox.outcome(201), 'sent');
  for (const s of [406, 413, 422, 400, 404]) assert.equal(outbox.outcome(s), 'drop');
  // Not signed in, or a rotated token: kept until a sign-in, as the apps keep them.
  for (const s of [401, 403]) assert.equal(outbox.outcome(s), 'hold');
  for (const s of [429, 500, 502, 503]) assert.equal(outbox.outcome(s), 'retry');

  const store = memoryStore();
  await outbox.enqueue(store, { url: 'https://old.example/' }, { now: 1, id: 'o' });
  await outbox.enqueue(store, { url: 'https://skip.example/' }, { now: 2_000_000, id: 's' });
  await outbox.enqueue(store, { url: 'https://ok.example/' }, { now: 2_000_001, id: 'k' });
  await outbox.enqueue(store, { url: 'https://down.example/' }, { now: 2_000_002, id: 'd' });
  await outbox.enqueue(store, { url: 'https://later.example/' }, { now: 2_000_003, id: 'l' });
  const replies = { 'https://skip.example/': 406, 'https://ok.example/': 201, 'https://down.example/': 502 };
  const sentTo = [];
  const r = await outbox.drain(store, async (p) => (sentTo.push(p.url), replies[p.url]), { now: 2_000_010 });
  // The 14-day-old page is dropped unsent; the skip-listed one dropped; the
  // drain stops at the 502, leaving it (one attempt counted) and the rest.
  assert.deepEqual(plain(r), { sent: 1, dropped: 2, stopped: true });
  assert.deepEqual(sentTo, ['https://skip.example/', 'https://ok.example/', 'https://down.example/']);
  const left = [...store.files.values()].map((t) => JSON.parse(t));
  assert.deepEqual(left.map((e) => [e.page.url, e.attempts]), [['https://down.example/', 1], ['https://later.example/', 0]]);

  for (let i = 1; i < outbox.MAX_ATTEMPTS; i++) await outbox.drain(store, async () => 503, { now: 2_000_010 });
  assert.deepEqual((await outbox.status(store)).count, 1, 'dropped after five 5xx replies');

  const unreachable = await outbox.drain(store, async () => { throw new Error('offline'); }, { now: 2_000_010 });
  assert.equal(unreachable.stopped, true);
  // Signed out (or a rotated token): kept, no try counted, the drain stops.
  const before = [...store.files.values()].map((t) => JSON.parse(t).attempts);
  const held = await outbox.drain(store, async () => 403, { now: 2_000_010 });
  assert.deepEqual(plain(held), { sent: 0, dropped: 0, stopped: true, signedOut: true });
  assert.deepEqual([...store.files.values()].map((t) => JSON.parse(t).attempts), before);
  store.files.set('000000000000-broken.json', '{not json');
  const fixed = await outbox.drain(store, async () => 201, { now: 2_000_010 });
  assert.deepEqual(plain(fixed), { sent: 1, dropped: 1, stopped: false });
});

test('the command line', () => {
  assert.deepEqual(plain(parseArgs([])), { command: 'open' });
  assert.deepEqual(plain(parseArgs(['--quick'])), { command: 'quick' });
  assert.deepEqual(plain(parseArgs(['search', 'raspberry', 'pi'])), { command: 'search', query: 'raspberry pi' });
  assert.deepEqual(plain(parseArgs(['save', 'https://a.example/x', 'books'])), { command: 'save', url: 'https://a.example/x', label: 'books' });
  assert.equal(parseArgs(['save', 'a.example']).command, 'error');
  assert.equal(parseArgs(['save', 'https://a/', 'b', 'c']).command, 'error');
  assert.deepEqual(plain(parseArgs(['shiori://settings'])), { command: 'link', url: 'shiori://settings' });
  assert.equal(parseArgs(['send']).command, 'send');
  assert.equal(parseArgs(['bogus']).command, 'error');
  assert.deepEqual(plain(parseArgs(['provider-search', 'raspberry', 'pi'])), { command: 'provider-search', query: 'raspberry pi' });
  assert.deepEqual(plain(parseArgs(['save-links', 'Notes/Sample.md', 'books'])), { command: 'save-links', path: 'Notes/Sample.md', label: 'books', dryRun: false });
  assert.deepEqual(plain(parseArgs(['save-links', '--folder', 'Reading/', '--dry-run'])), { command: 'save-links', folder: 'Reading', dryRun: true });
  assert.equal(parseArgs(['save-links']).command, 'error');
  assert.equal(parseArgs(['save-links', 'a.md', 'b', 'c']).command, 'error');
});

test("Kura's save-links link names a note or a folder", () => {
  assert.deepEqual(plain(saveLinksTarget('shiori://save-links?path=Reading%2FSample%20Note.md')), { path: 'Reading/Sample Note.md' });
  assert.deepEqual(plain(saveLinksTarget('shiori://save-links?folder=Reading%2F')), { folder: 'Reading' });
  assert.equal(saveLinksTarget('shiori://save-links?folder=%2F'), null);
  assert.equal(saveLinksTarget('shiori://settings'), null);
  assert.equal(saveLinksTarget('shiori://save-links?path=%E0%A4%A'), null);
});

test("a note's links are saved in bulk without overriding the skip rules", () => {
  const page = newPage({ url: 'https://a.example/', title: 'A', via: 'note-links', ignoreSkipRules: false, extra: { from_note: 'Notes/Sample.md' } });
  assert.equal(page.metadata.ignore_skip_rules, undefined);
  assert.equal(page.metadata.via, 'note-links');
  assert.equal(page.metadata.from_note, 'Notes/Sample.md');
  // `shiori save` is a deliberate save, as before.
  assert.equal(newPage({ url: 'https://a.example/', via: 'linux' }).metadata.ignore_skip_rules, true);
});

test('the desktop search provider: pages, then notes', () => {
  assert.equal(providerQuery(['raspberry', 'pi']), 'raspberry pi');
  const hister = { documents: [
    { url: 'https://www.boards.example/', title: 'Raspberry Pi' },
    { url: 'https://kura.example/n/X', title: 'Leaked note', label: 'vault' },
    { url: 'https://www.boards.example/', title: 'Duplicate' },
    { url: 'ftp://nope/', title: 'No' },
  ] };
  const kura = { documents: [{ url: 'https://kura.example/n/Projects/Sample', title: 'Sample', path: 'Projects/Sample.md' }] };
  const rows = providerResults(hister, kura);
  assert.deepEqual(plain(rows), [
    { id: 'page:https://www.boards.example/', kind: 'page', name: 'Raspberry Pi', description: 'boards.example', url: 'https://www.boards.example/' },
    { id: 'note:https://kura.example/n/Projects/Sample', kind: 'note', name: 'Sample', description: 'Projects › Sample', url: 'https://kura.example/n/Projects/Sample' },
  ]);
  assert.deepEqual(plain(activation(rows[1].id)), { kind: 'note', url: 'https://kura.example/n/Projects/Sample' });
  assert.equal(activation('bogus'), null);
});

test('quick search notes: from Kura, or from Hister when chosen or without a Kura', () => {
  const S = shimmedCore();
  const withKura = { server: 'https://hister.example', kura: 'https://kura.example' };
  const noKura = { server: 'https://hister.example' };
  // until chosen: Kura when the config names one, else Hister
  assert.equal(notesFromHister(S, withKura), false);
  assert.equal(notesFromHister(S, noKura), true);
  assert.equal(notesFromHister(S, { ...withKura, notesSource: 'hister' }), true);
  assert.equal(notesFromHister(S, { ...noKura, notesSource: 'kura' }), true);
  // Kura: its API
  const kura = notesSearch(S, withKura, 'lantern');
  assert.equal(kura.hister, false);
  assert.match(kura.url, /^https:\/\/kura\.example\/api\/search\?/);
  // Hister: its label:vault search, the newest first with no words
  const hister = notesSearch(S, noKura, 'lantern');
  assert.equal(hister.hister, true);
  assert.equal(JSON.parse(new URL(hister.url).searchParams.get('query')).text, '(lantern|lantern*) label:vault');
  assert.equal(JSON.parse(new URL(notesSearch(S, noKura, '').url).searchParams.get('query')).sort, 'date');
  assert.equal(notesSearch(S, { notesSource: 'hister' }, 'x'), null);
  // Hister's reply: the default vault's notes alone, in Kura's shape
  const notes = notesFromReply(S, { total: 2, documents: [
    { url: 'https://kura.example/n/Projects/Lantern%20festival%20kit', title: 'Lantern festival kit', metadata: { vault_path: 'Projects/Lantern festival kit.md' } },
    { url: 'https://kura.example/v/work/n/Secret', title: 'Secret' },
  ] }, true);
  assert.deepEqual(notes.documents.map((d) => d.url), ['https://kura.example/n/Projects/Lantern%20festival%20kit']);
  const rows = providerResults(null, notes);
  assert.deepEqual(plain(rows.map((r) => r.description)), ['Projects › Lantern festival kit']);
  assert.equal(notesFromReply(S, null, true), null);
});


// --- the Machiya sign-in (linux/src/machiya.js), on search-core under the shim as in GJS ---

function shimmedCore() {
  const source = readFileSync(new URL('../patches/shiori/search-core.js', import.meta.url), 'utf8');
  const ctx = {};
  installURL(ctx);
  vm.createContext(ctx);
  vm.runInContext(source, ctx);
  return ctx.ShioriSearch;
}

const TOKEN = 'mch_q9xa_' + 'A'.repeat(43);
const CONFIG = {
  server: 'https://hister.example/',
  kura: 'https://kura.example/',
  smallweb: 'https://smallweb.example/',
  webApp: 'https://shiori.example/',
  machiyaToken: TOKEN,
};

test('the token goes to the configured Kura only, read with the shim as GJS reads it', () => {
  const S = shimmedCore();
  assert.deepEqual(plain(roomOrigins(CONFIG, S)), ['https://kura.example']);
  assert.deepEqual(plain(roomHeaders(CONFIG, 'https://kura.example/api/search?q=x', S)), { Authorization: 'Bearer ' + TOKEN });
  assert.deepEqual(plain(roomHeaders(CONFIG, 'https://KURA.example:443/api/note', S)), { Authorization: 'Bearer ' + TOKEN });
  for (const url of [
    'https://hister.example/search', 'https://smallweb.example/api/save', 'https://shiori.example/',
    'https://kura.example@evil.example/api/search', 'https://user:pw@kura.example/api/search',
    'https://kura.example.evil.example/', 'https://kura.example:8443/', 'http://kura.example/',
  ]) {
    assert.deepEqual(plain(roomHeaders(CONFIG, url, S)), {}, url);
  }
  // No token, or not a token: nothing.
  assert.deepEqual(plain(roomHeaders({ ...CONFIG, machiyaToken: '' }, 'https://kura.example/', S)), {});
  assert.deepEqual(plain(roomHeaders({ ...CONFIG, machiyaToken: 'hunter2' }, 'https://kura.example/', S)), {});
  // Kura on the web app's host (one host, /kura/ under it): no token at all.
  assert.deepEqual(plain(roomOrigins({ ...CONFIG, kura: 'https://shiori.example/kura/' }, S)), []);
});

test("Hister's requests never carry the token, and a signed-in request follows no redirect", () => {
  const http = readFileSync(new URL('../linux/gjs/http.js', import.meta.url), 'utf8');
  assert.match(http, /const room = signIn && !hister \? roomHeaders\(config, url, globalThis\.ShioriSearch\) : \{\};/);
  assert.match(http, /if \(auth \|\| token \|\| cookie \|\| Object\.keys\(extra\)\.length \|\| !redirects\) message\.set_flags\(Soup\.MessageFlags\.NO_REDIRECT\);/);
});

test("Hister's token goes to the configured server only, as X-Access-Token", () => {
  const S = shimmedCore();
  const config = { ...CONFIG, histerToken: 'ABCDEFGHJKLMNPQRSTUVWXYZ23' };
  assert.deepEqual(plain(histerHeaders(config, 'https://hister.example/search?query=x', S)), { 'X-Access-Token': 'ABCDEFGHJKLMNPQRSTUVWXYZ23' });
  assert.deepEqual(plain(histerHeaders(config, 'https://HISTER.example:443/api/add', S)), { 'X-Access-Token': 'ABCDEFGHJKLMNPQRSTUVWXYZ23' });
  for (const url of [
    'https://smallweb.example/api/save', 'https://kura.example/api/search', 'https://shiori.example/',
    'https://hister.example@evil.example/', 'https://u:p@hister.example/', 'http://hister.example/', 'https://hister.example:8443/',
  ]) {
    assert.deepEqual(plain(histerHeaders(config, url, S)), {}, url);
  }
  assert.deepEqual(plain(histerHeaders(CONFIG, 'https://hister.example/search', S)), {});
  assert.deepEqual(plain(histerHeaders({ ...config, histerToken: 'not a token' }, 'https://hister.example/search', S)), {});
  assert.match(histerTokenStatus(CONFIG, 0o600, S), /no token/);
  assert.match(histerTokenStatus({ histerToken: 'no' }, 0o600, S), /isn’t a token/);
  assert.equal(histerTokenStatus(config, 0o100600, S), 'Hister: a token in config.json.');
  assert.match(histerTokenStatus(config, 0o100644, S), /mode 644\): chmod 600/);
  const http = readFileSync(new URL('../linux/gjs/http.js', import.meta.url), 'utf8');
  assert.match(http, /const token = hister && credentials \? histerHeaders\(config, url, globalThis\.ShioriSearch\)\['X-Access-Token'\] : undefined;/);
  assert.match(http, /if \(auth \|\| token \|\| cookie \|\| Object\.keys\(extra\)\.length \|\| !redirects\) message\.set_flags\(Soup\.MessageFlags\.NO_REDIRECT\);/);
});

test("rooms get the sign-in's id, else a room token (mht_), else the identity token: never Hister's token", () => {
  const S = shimmedCore();
  const HISTER = 'ABCDEFGHJKLMNPQRSTUVWXYZ23';
  const ROOM = 'mht_' + 'r'.repeat(43);
  assert.deepEqual(plain(roomHeaders({ ...CONFIG, histerToken: HISTER }, 'https://kura.example/api/search', S)), { Authorization: 'Bearer ' + TOKEN });
  assert.deepEqual(plain(roomHeaders({ ...CONFIG, machiyaToken: '', histerToken: HISTER }, 'https://kura.example/api/search', S)), {});
  assert.deepEqual(plain(roomHeaders({ ...CONFIG, roomToken: ROOM, histerToken: HISTER }, 'https://kura.example/api/search', S)), { Authorization: 'Bearer ' + ROOM });
  assert.deepEqual(plain(roomHeaders({ ...CONFIG, roomToken: 'mch_not_a_room_token' }, 'https://kura.example/api/search', S)), { Authorization: 'Bearer ' + TOKEN });
  assert.deepEqual(plain(roomHeaders({ ...CONFIG, roomToken: ROOM }, 'https://hister.example/search', S)), {});
  const sid = 'mhs_' + 'Z'.repeat(43);
  assert.deepEqual(plain(roomHeaders({ ...CONFIG, roomToken: ROOM, histerToken: HISTER, histerSignIn: { sid } }, 'https://kura.example/api/search', S)), { Authorization: 'Bearer ' + sid });
});

test("status says who can read the token, and pair prints the line to add", () => {
  const S = shimmedCore();
  assert.equal(signInStatus({}, 0o600, S), 'Machiya: not signed in.');
  assert.match(signInStatus({ machiyaToken: 'nope' }, 0o600, S), /isn’t a token/);
  assert.equal(signInStatus(CONFIG, 0o100600, S), 'Machiya: signed in (a token in config.json).');
  assert.match(signInStatus(CONFIG, 0o100644, S), /mode 644\): chmod 600/);
  const printed = pairedMessage({ token: TOKEN, principal: 'alex' });
  assert.match(printed, /Paired as alex/);
  assert.ok(printed.includes(`"machiyaToken": "${TOKEN}"`));
});

test('the command line pairs with a code, in one piece or two', () => {
  assert.deepEqual(plain(parseArgs(['pair', 'ABCD-EFGH'])), { command: 'pair', code: 'ABCD-EFGH', device: 'Linux' });
  assert.deepEqual(plain(parseArgs(['pair', 'abcd', 'efgh', 'Desk', 'Mint'])), { command: 'pair', code: 'abcdefgh', device: 'Desk Mint' });
  assert.equal(parseArgs(['pair']).command, 'error');
});

test("Hister's sign-in on Linux: the file, the cookie, the rooms' id, the requests", async () => {
  const S = shimmedCore();
  const h = await import('../linux/src/hister.js');
  const session = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-abcde';
  const sid = 'mhs_' + 'Z'.repeat(43);
  // The file: checked, and only for the server it was made for.
  assert.deepEqual(plain(h.signInRecord({ server: 'https://hister.example', session, sid, username: 'alex' }, 'https://hister.example/')), { session, sid, username: 'alex' });
  assert.equal(h.signInRecord({ server: 'https://other.example', session, sid }, 'https://hister.example/'), null);
  assert.equal(h.signInRecord({ server: 'https://hister.example', session: 'short', sid }, 'https://hister.example/'), null);
  assert.equal(h.signInRecord({ server: 'https://hister.example', session, sid: 'mch_x' }, 'https://hister.example/'), null);
  assert.deepEqual(JSON.parse(h.signInFileContent('https://hister.example/', { session, sid, username: 'alex' })), { server: 'https://hister.example', session, sid, username: 'alex' });
  // The session goes to Hister only; the id to the rooms only.
  const config = { ...CONFIG, histerSignIn: { session, sid, username: 'alex' } };
  assert.equal(h.histerCookie(config, 'https://hister.example/search'), `hister=${session}`);
  for (const url of ['https://kura.example/api/search', 'https://smallweb.example/api/save', 'https://shiori.example/', 'http://hister.example/']) assert.equal(h.histerCookie(config, url), '', url);
  assert.deepEqual(plain(roomHeaders(config, 'https://kura.example/api/search', S)), { Authorization: `Bearer ${sid}` });
  assert.deepEqual(plain(roomHeaders(config, 'https://hister.example/search', S)), {});
  // Hister's Set-Cookie, the requests, the helper's answer.
  assert.equal(h.sessionFromSetCookie([`other=1; Path=/`, `hister=${session}; Path=/; Max-Age=2592000; HttpOnly; SameSite=Lax`]), session);
  assert.equal(h.sessionFromSetCookie([`hister=${session}; Max-Age=0`]), '');
  assert.equal(h.loginRequest('https://hister.example', 'a', 'b').url, 'https://hister.example/api/login');
  assert.equal(h.appSessionRequest('https://hister.example/', session, 'x'.repeat(100)).url, 'https://hister.example/machiya/api/app-session');
  assert.equal(JSON.parse(h.appSessionRequest('https://hister.example/', session, 'x'.repeat(100)).body).label.length, 80);
  assert.deepEqual(plain(h.signOutRequest('https://hister.example/', sid).headers), { Authorization: `Bearer ${sid}` });
  assert.equal(h.signInAvailable(200, { ok: true, hister: 'ok' }), true);
  assert.equal(h.signInAvailable(200, { ok: true, hister: 'user-handling-off' }), false);
  assert.equal(h.signInAvailable(503, null), false);
  assert.match(h.loginProblem(401), /didn't recognise/);
  assert.equal(h.histerSignInStatus(null), 'Hister: not signed in.');
  assert.equal(h.histerSignInStatus({ username: 'alex' }), 'Hister: signed in as alex (sign-in.json).');
  // The command line, and http.js sending the cookie under the no-redirect rule.
  assert.deepEqual(plain(parseArgs(['sign-in'])), { command: 'sign-in' });
  assert.deepEqual(plain(parseArgs(['sign-out'])), { command: 'sign-out' });
  assert.equal(parseArgs(['sign-in', 'x']).command, 'error');
  const http = readFileSync(new URL('../linux/gjs/http.js', import.meta.url), 'utf8');
  assert.match(http, /const cookie = hister && credentials \? histerCookie\(config, url\) : '';/);
  assert.match(http, /if \(auth \|\| token \|\| cookie \|\| Object\.keys\(extra\)\.length \|\| !redirects\) message\.set_flags\(Soup\.MessageFlags\.NO_REDIRECT\);/);
});

// The modules and search-core in real GJS, where it's installed (the Linux
// test machines; skipped on a Mac).
test('the GJS self-test passes (linux/gjs/selftest.js)', { skip: spawnSync('gjs', ['--version']).error ? 'no gjs here' : false }, () => {
  const r = spawnSync('gjs', ['-m', fileURLToPath(new URL('../linux/gjs/selftest.js', import.meta.url))], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.doesNotMatch(r.stdout, /FAIL/);
});
