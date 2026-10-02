// Shiori for Linux: its pure modules (linux/src/), which GJS runs as they
// are (docs/linux.md). Node's own URL is the reference for the shim,
// and HisterKit's outbox and save rules for the rest.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { ShimURL, ShimURLSearchParams, installURL } from '../linux/src/url.js';
import { newPage, addRequest, titleIn, capped, MAX_HTML_CHARACTERS } from '../linux/src/page.js';
import * as outbox from '../linux/src/outbox.js';
import { parseArgs, saveLinksTarget } from '../linux/src/cli.js';
import { providerQuery, providerResults, activation } from '../linux/src/provider.js';

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
  ];
  for (const raw of urls) {
    const ours = new ShimURL(raw);
    const node = new URL(raw);
    for (const part of ['protocol', 'hostname', 'host', 'port', 'pathname', 'search', 'hash', 'origin', 'href']) {
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
