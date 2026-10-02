// Tests for patches/shiori/search-core.js. Run: node --test scripts/

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const source = readFileSync(fileURLToPath(new URL('../patches/shiori/search-core.js', import.meta.url)), 'utf8');
const ctx = { URL, URLSearchParams };
ctx.globalThis = ctx;
vm.createContext(ctx);
vm.runInContext(source, ctx);
const S = ctx.ShioriSearch;

test('bangs are left to DuckDuckGo', () => {
  assert.equal(S.hasBang('!w tokyo'), true);
  assert.equal(S.hasBang('tokyo !w'), true);
  assert.equal(S.hasBang('hello!'), false);
  assert.equal(S.hasBang('wow ! really'), false);
});

test('the web query drops Hister-only syntax', () => {
  assert.equal(S.webQuery('rust label:programming async'), 'rust async');
  assert.equal(S.webQuery('label:(alpha|mac) added:>2026-01-01'), '');
  assert.equal(S.webQuery('-domain:www.example.com go'), 'go');
  assert.equal(S.webQuery('site:example.com go'), 'site:example.com go');
});

test('URLs normalise for comparison', () => {
  assert.equal(S.normalizeURL('https://www.Example.com/a/?utm_source=x&b=2&a=1#top'), 'example.com/a?a=1&b=2');
  assert.equal(S.normalizeURL('http://example.com/'), 'example.com');
  assert.equal(S.normalizeURL('not a url'), 'not a url');
});

test('one lookup query covers many URLs, both slash forms, and skips unsafe ones', () => {
  const q = S.urlLookupQuery(['https://a.example/x', 'https://b.example/', 'https://w.example/wiki/A_(b)']);
  assert.equal(q, 'url:(https://a.example/x|https://a.example/x/|https://b.example/|https://b.example)');
  assert.equal(S.urlLookupQuery(['https://w.example/(x)']), '');
});

test('the fallback is plain DuckDuckGo, marked so it is not taken over again', () => {
  const url = S.fallbackURL('a & b');
  assert.equal(url, 'https://duckduckgo.com/?q=a%20%26%20b&shiori=off');
  assert.equal(S.shouldRedirect(url, 'navigate'), false);
});

test('only fresh DuckDuckGo web searches are taken over', () => {
  assert.equal(S.shouldRedirect('https://duckduckgo.com/?q=go+concurrency&t=iphone', 'navigate'), true);
  assert.equal(S.shouldRedirect('https://duckduckgo.com/?q=go&ia=web', 'navigate'), true);
  assert.equal(S.shouldRedirect('https://duckduckgo.com/?q=go&iax=images&ia=images', 'navigate'), false);
  assert.equal(S.shouldRedirect('https://duckduckgo.com/?q=!w+go', 'navigate'), false);
  assert.equal(S.shouldRedirect('https://duckduckgo.com/?q=go', 'back_forward'), false);
  assert.equal(S.shouldRedirect('https://duckduckgo.com/?q=go', 'reload'), false);
  assert.equal(S.shouldRedirect('https://duckduckgo.com/settings', 'navigate'), false);
  assert.equal(S.shouldRedirect('https://duckduckgo.com/', 'navigate'), false);
  assert.equal(S.shouldRedirect('https://evil.example/?q=go', 'navigate'), false);
});

test('web results drop what Hister already showed and carry what it knows', () => {
  const web = [
    { url: 'https://docs.example/tour/' },
    { url: 'https://www.docs.example/tour' },
    { url: 'https://blog.example/post/' },
    { url: 'https://kept.example/page' },
    { url: 'https://new.example/' },
  ];
  const hister = [{ url: 'https://blog.example/post/' }];
  const lookup = [{ url: 'https://docs.example/tour', label: '' }, { url: 'https://kept.example/page/', label: 'programming' }];
  const out = S.annotateWeb(web, hister, lookup);
  assert.deepEqual(
    JSON.parse(JSON.stringify(out.map((r) => [r.url, r.saved, r.label]))),
    [
      ['https://docs.example/tour/', true, ''],
      ['https://kept.example/page', true, 'programming'],
      ['https://new.example/', false, ''],
    ],
  );
});

test('the URL line is the origin then path crumbs', () => {
  const b = S.breadcrumb('https://www.boards.example/products/raspberry-pi-5/?x=1');
  assert.equal(b.origin, 'https://www.boards.example');
  assert.deepEqual([...b.crumbs], ['products', 'raspberry-pi-5']);
  assert.deepEqual([...S.breadcrumb('https://en.wikipedia.org/wiki/Caf%C3%A9').crumbs], ['wiki', 'Café']);
});

test('query words to bold skip operators, bangs and one-letter bits', () => {
  assert.deepEqual([...S.highlightTerms('Raspberry pi label:alpha -zero a "cases"')], ['raspberry', 'pi', 'cases']);
});

test('snippets split into runs around the query words, case-insensitively', () => {
  const runs = S.splitHighlights('Raspberry Pi is a Pi.', ['pi', 'raspberry']);
  assert.deepEqual(
    JSON.parse(JSON.stringify(runs)),
    [
      { text: 'Raspberry', hit: true },
      { text: ' ', hit: false },
      { text: 'Pi', hit: true },
      { text: ' is a ', hit: false },
      { text: 'Pi', hit: true },
      { text: '.', hit: false },
    ],
  );
  assert.equal(S.splitHighlights('a.b', ['.'])[0].text, 'a');
});

test('dates and durations read like SearXNG', () => {
  assert.equal(S.shortDate('None'), '');
  assert.equal(S.shortDate('2026-06-25T03:32:37', 'en-US'), 'Jun 25, 2026');
  assert.equal(S.duration('17:00'), '17:00');
  assert.equal(S.duration('206.0'), '3:26');
  assert.equal(S.duration(3725), '1:02:05');
  assert.equal(S.duration('None'), '');
  assert.equal(S.cachedURL('https://a.example/x'), 'https://web.archive.org/web/https://a.example/x');
  assert.equal(S.archiveURL('https://a.example/x?y=1'), 'https://archive.is/newest/https://a.example/x?y=1');
});

const cards = [
  { slug: 'example', path: 'Projects/Example.md' },
  { slug: 'garden-plan', path: 'Projects/Garden Plan.md' },
];

test('vault notes map from Niwa and Konbini URLs to their vault paths', () => {
  assert.equal(S.notePath('https://niwa.example/n/Topics/Sample%20Note', cards), 'Topics/Sample Note.md');
  assert.equal(S.notePath('https://konbini.example/p/garden-plan', cards), 'Projects/Garden Plan.md');
  assert.equal(S.notePath('https://konbini.example/p/unknown', cards), null);
  assert.equal(S.notePath('https://example.com/other', cards), null);
});

test('a vault path links to Obsidian, Niwa, and its Konbini card', () => {
  assert.equal(S.obsidianURL('personal', 'Projects/Garden Plan.md'), 'obsidian://open?vault=personal&file=Projects%2FGarden%20Plan');
  assert.equal(S.niwaURL('https://niwa.example', 'Projects/Garden Plan.md'), 'https://niwa.example/n/Projects/Garden%20Plan');
  assert.equal(S.konbiniURL('https://konbini.example/', 'Projects/Example.md', cards), 'https://konbini.example/p/example');
  assert.equal(S.konbiniURL('https://konbini.example/', 'Tools/Tools.md', cards), null);
  assert.equal(S.vaultQuery('garden'), 'garden label:vault');
});

test('a label keeps its colour everywhere: the app\'s djb2 over its scalars', () => {
  // The same sums as Palette.chipHex(for:) (UInt32 wrapping), one of eight.
  const swift = (label) => {
    let h = 5381n;
    for (const ch of label) h = (h * 33n + BigInt(ch.codePointAt(0))) & 0xffffffffn;
    return Number(h % 8n);
  };
  for (const label of ['books', 'mac', 'blog', 'vault', 'konbini', 'a much longer label to wrap the hash', '栞', 'café']) {
    assert.equal(S.labelChipIndex(label), swift(label), label);
  }
});

test('suggestions as you type: the words so far, the last one a title prefix', () => {
  assert.deepEqual([...S.suggestionQueries('raspberry ze')], ['raspberry title:ze*', 'raspberry ze']);
  assert.deepEqual([...S.suggestionQueries(' RaspberryPi ')], ['title:raspberrypi*', 'raspberrypi']);
  assert.deepEqual([...S.suggestionQueries('jellyf')], ['title:jellyf*', 'jellyf']);
  assert.deepEqual([...S.suggestionQueries('r')], []);
  assert.deepEqual([...S.suggestionQueries('')], []);
  assert.deepEqual([...S.suggestionQueries('label:books')], []);
  assert.deepEqual([...S.suggestionQueries('rust -crate')], []);
  assert.deepEqual([...S.suggestionQueries('"exact')], []);
  assert.deepEqual([...S.suggestionQueries('jelly*')], []);
});

test('a title fits when every typed word is in it, spaces aside', () => {
  assert.equal(S.titleMatches('Raspberry Pi', 'raspberrypi'), true);
  assert.equal(S.titleMatches('Raspberry Pi Zero V1.3', 'raspberry ze'), true);
  assert.equal(S.titleMatches('Learn Python 3', 'pytho'), true);
  assert.equal(S.titleMatches('Enhancing my Macintosh 512Ke', 'raspberrypi'), false);
  assert.equal(S.titleMatches('', 'x'), false);
  assert.equal(S.titleMatches('Anything', ''), false);
});

test("SearXNG's autocompleter reply: up to five, without what's typed", () => {
  const reply = ['raspberrypi', ['raspberry pi', 'RaspberryPi', 'raspberry pi 5', 'raspberry pi imager', 'raspberry pi os', 'raspberry pi connect', 'raspberry pi zero'], [], []];
  assert.deepEqual([...S.parseAutocomplete(reply, 'raspberrypi')], ['raspberry pi', 'raspberry pi 5', 'raspberry pi imager', 'raspberry pi os', 'raspberry pi connect']);
  assert.deepEqual([...S.parseAutocomplete(['x', ['a', 'A', ' ', 7, 'b']], 'x')], ['a', 'b']);
  assert.deepEqual([...S.parseAutocomplete({ results: [] }, 'x')], []);
  assert.deepEqual([...S.parseAutocomplete(null, 'x')], []);
  assert.deepEqual([...S.parseAutocomplete(['x', 'not a list'], 'x')], []);
});

test('a section count is always there: some of all, or all', () => {
  assert.equal(S.countText(3, 8), '8 results'); // the full count, not "3 of 8"
  assert.equal(S.countText(6, 5), '6 results'); // more on screen than the total says
  assert.equal(S.countText(6, 6), '6 results');
  assert.equal(S.countText(1, 1), '1 result');
  assert.equal(S.countText(0, 0), '');
});

test('a collection gets an icon from a word in its name', () => {
  assert.equal(S.collectionIcon('arts'), 'palette');
  assert.equal(S.collectionIcon('games'), 'controller');
  assert.equal(S.collectionIcon('k8s'), 'helm');
  assert.equal(S.collectionIcon('kept'), 'bookmark');
  assert.equal(S.collectionIcon('life'), 'leaf');
  assert.equal(S.collectionIcon('tech'), 'cpu');
  assert.equal(S.collectionIcon('misc'), 'stack');
  assert.equal(S.collectionIcon('@retro'), 'clock');
  assert.equal(S.collectionIcon('@unix'), 'terminal');
  assert.equal(S.collectionIcon('@smallweb'), 'globe');
  assert.equal(S.collectionIcon('@gear'), 'wrench');
  assert.equal(S.collectionIcon('@culture'), 'masks');
  assert.equal(S.collectionIcon('@homelab'), 'server');
  assert.equal(S.collectionTitle('@work'), 'work');
  assert.equal(S.collectionTitle('kept'), 'kept');
});

test('labels and collections for the word being typed', () => {
  const aliases = {
    '@vintage': 'label:(vintage-tech|vintage-games|mac)',
    '@systems': 'label:(linux|solaris)',
    everything: 'label:(vintage-tech|vintage-games|mac|linux|solaris|books)',
  };
  const { labels } = S.labelsFromAliases(aliases);
  assert.deepEqual(JSON.parse(JSON.stringify(labels)), ['solaris', 'books', 'linux', 'mac', 'vintage-games', 'vintage-tech'].sort());
  assert.deepEqual(JSON.parse(JSON.stringify(S.labelSuggestions('so', labels, aliases).map((i) => i.name))), ['solaris']);
  assert.deepEqual(JSON.parse(JSON.stringify(S.labelSuggestions('some vintage', labels, aliases).map((i) => [i.kind, i.name, i.query]))), [
    ['collection', 'vintage', '@vintage'],
    ['label', 'vintage-games', 'label:vintage-games'],
    ['label', 'vintage-tech', 'label:vintage-tech'],
  ]);
  // Starts-with before contains.
  assert.deepEqual(JSON.parse(JSON.stringify(S.labelSuggestions('ix', ['unix', 'ixl', 'mix'], {}).map((i) => i.name))), ['ixl', 'mix', 'unix']);
  assert.deepEqual(JSON.parse(JSON.stringify(S.labelSuggestions('b', labels, aliases))), []);
  assert.deepEqual(JSON.parse(JSON.stringify(S.labelSuggestions('label:x', labels, aliases))), []);
  // An alias naming every label never shows; the cap holds.
  assert.equal(S.labelSuggestions('e', labels, aliases).length, 0);
  assert.ok(!S.labelSuggestions('ev', labels, aliases).some((i) => i.query === 'everything'));
  // Only "@" aliases are collections: a plain one is the user's own query.
  assert.ok(!S.labelSuggestions('mi', ['mine'], { mine: 'label:mine' }).some((i) => i.kind === 'collection'));
  assert.equal(S.isCollectionKeyword('@vintage'), true);
  assert.equal(S.isCollectionKeyword('everything'), false);
  assert.equal(S.isCollectionKeyword('@'), false);
  assert.equal(S.labelSuggestions('re', ['rea', 'reb', 'rec', 'red', 'ree', 'ref', 'reg'], {}).length, 6);
});

test('a note reads on its own reader page, else one built on the reader address', () => {
  assert.equal(S.readerURL('https://kura.example/n/Guides/Example', 'https://kura.example/', 'Guides/Example.md'), 'https://kura.example/n/Guides/Example');
  assert.equal(S.readerURL('https://konbini.example/p/example', 'https://kura.example/', 'Projects/Example.md'), 'https://kura.example/n/Projects/Example');
  assert.equal(S.readerURL('https://konbini.example/p/example', '', 'Projects/Example.md'), null);
  assert.equal(S.isNoteURL('https://kura.example/n/Topics/Sample'), true);
});

test('the web search leaves out Hister syntax and @collections', () => {
  assert.equal(S.webQuery('label:alpha'), '');
  assert.equal(S.webQuery('@vintage amiga'), 'amiga');
  assert.equal(S.webQuery('rust -domain:reddit.com'), 'rust');
});

test('a vault tag links to its Kura page', () => {
  assert.equal(S.kuraTagURL('https://kura.example', 'topic/docker'), 'https://kura.example/t/topic/docker');
  assert.equal(S.kuraTagURL('https://kura.example/', '#area/home lab'), 'https://kura.example/t/area/home%20lab');
  assert.equal(S.kuraTagURL('', 'x'), null);
});

test('edit distance counts a swapped pair as one edit', () => {
  assert.equal(S.editDistance('rasbperry', 'raspberry'), 1);
  assert.equal(S.editDistance('javscript', 'javascript'), 1);
  assert.equal(S.editDistance('pi', 'pi'), 0);
  assert.equal(S.editDistance('', 'abc'), 3);
});

test('a respelling from the web\'s related searches, for a search that found nothing', () => {
  assert.equal(S.correctedQuery('rasbperry pi', ['raspberry pi 5', 'raspberry pi price']), 'raspberry pi');
  assert.equal(S.correctedQuery('Javscript', ['javascript 2026 guide']), 'javascript');
  // The first suggestion that fits every word wins.
  assert.equal(S.correctedQuery('javscript docker', ['javascript 2026 guide', 'update javascript docker']), 'javascript docker');
  // Too far, or too short to guess at.
  assert.equal(S.correctedQuery('rust', ['python tutorial']), null);
  assert.equal(S.correctedQuery('go pi', ['go pie']), null);
  // Nothing to change, no suggestions, operators.
  assert.equal(S.correctedQuery('raspberry pi', ['raspberry pi 5']), null);
  assert.equal(S.correctedQuery('rasbperry', []), null);
  assert.equal(S.correctedQuery('rasbperry', undefined), null);
  assert.equal(S.correctedQuery('label:books rasbperry', ['raspberry']), null);
  assert.equal(S.correctedQuery('"rasbperry pi"', ['raspberry pi']), null);
  assert.equal(S.correctedQuery('', ['x']), null);
});

test('site runs: three or more from one site in a row show the first, then the rest folded', () => {
  const page = (url, extra = {}) => ({ url, domain: new URL(url).host, ...extra });
  const shape = (items) => Array.from(items, (i) => (i.page ? i.page.url : `${i.folded} +${i.pages.length}`));
  const pages = [
    page('https://a.example/accounts/login/'),
    page('https://a.example/'),
    page('https://www.a.example/projects/'),
    page('https://b.example/search?q=x'),
    page('https://a.example/docs/'),
  ];
  assert.deepEqual(shape(S.siteRuns(pages)), [
    'https://a.example/accounts/login/', 'a.example +2', 'https://b.example/search?q=x', 'https://a.example/docs/',
  ]);
  // Two in a row stay as they are.
  const two = [page('https://a.example/1'), page('https://a.example/2'), page('https://b.example/')];
  assert.deepEqual(shape(S.siteRuns(two)), two.map((p) => p.url));
  // Notes never fold, though they share a host.
  const notes = [1, 2, 3, 4].map((n) => page(`https://konbini.example/p/${n}`, { label: 'vault' }));
  assert.deepEqual(shape(S.siteRuns(notes)), notes.map((p) => p.url));
  // No site, no fold.
  const files = [1, 2, 3].map((n) => ({ url: `file:///doc${n}.pdf`, domain: '' }));
  assert.deepEqual(shape(S.siteRuns(files)), files.map((p) => p.url));
});

test('a note by its URL: Niwa pages and Konbini cards, for lists without labels', () => {
  assert.equal(S.isNoteURL('https://niwa.example.ts.net/n/Projects/Example'), true);
  assert.equal(S.isNoteURL('https://konbini.example.ts.net/p/garden-plan'), true);
  assert.equal(S.isNoteURL('https://notes.example/n/x', 'https://notes.example/'), true);
  assert.equal(S.isNoteURL('https://niwa.example.ts.net/about'), false);
  assert.equal(S.isNoteURL('https://www.boards.example/'), false);
  assert.equal(S.isNoteURL('not a url'), false);
});

test('relative dates as the apps say them', () => {
  const now = Date.UTC(2026, 8, 28, 12) ;
  const s = now / 1000;
  assert.equal(S.relativeTime(s - 20, now), 'just now');
  assert.equal(S.relativeTime(s - 300, now), '5 minutes ago');
  assert.equal(S.relativeTime(s - 86400, now), 'yesterday');
  assert.equal(S.relativeTime(s - 3 * 86400, now), '3 days ago');
  assert.equal(S.relativeTime(0, now), '');
});

test('export in the app\'s formats: JSON for hister import, CSV, RSS', () => {
  const pages = [{ url: 'https://a.example/x', title: '=SUM(1)', domain: 'a.example', label: 'books', added: 1790380800, updated: 1790600000, text: 'Some <text> & more' }];
  const json = JSON.parse(S.exportData(pages, 'json', 'Books'));
  assert.deepEqual(Object.keys(json[0]), ['added', 'domain', 'label', 'title', 'updated', 'url']);
  assert.equal(json[0].updated, 1790600000);
  const csv = S.exportData(pages, 'csv', 'Books');
  assert.equal(csv.split('\r\n')[0], 'url,title,domain,label,added,updated');
  assert.match(csv, /,'=SUM\(1\),/);
  assert.match(csv, /2026-09-26T00:00:00Z/);
  const rss = S.exportData(pages, 'rss', 'Books', 'https://feed.example/');
  assert.match(rss, /<title>Shiori – Books<\/title>/);
  assert.match(rss, /<category>books<\/category>/);
  assert.match(rss, /Some &lt;text&gt; &amp; more/);
  assert.match(rss, /<pubDate>Sat, 26 Sep 2026 00:00:00 \+0000<\/pubDate>/);
  assert.equal(S.csvField('a,b'), '"a,b"');
  assert.equal(S.csvField('say "hi"'), '"say ""hi"""');
  assert.equal(S.exportFileName('Library · Pages!', 'csv'), 'shiori-library-pages.csv');
  assert.equal(S.exportFileName('', 'json'), 'shiori-results.json');
});

test('a list\'s feed, as the app builds it', () => {
  const base = 'https://shiori.example/';
  // Every feed but a notes list's leaves the notes out; those are Kura's.
  assert.equal(S.feedURL(base, { query: '*', source: 'all' }), 'https://shiori.example/api/history?format=rss');
  assert.equal(S.feedURL(base, { query: '*', title: 'Pages' }), 'https://shiori.example/shiori/feed?q=*&exclude_label=vault&title=Pages');
  assert.equal(S.feedURL(base, { query: 'label:books', title: 'books' }), 'https://shiori.example/shiori/feed?q=label%3Abooks&exclude_label=vault&title=books');
  assert.equal(S.feedURL(base, { query: 'rust', title: 'rust' }), 'https://shiori.example/shiori/feed?q=rust&exclude_label=vault');
  assert.equal(S.feedURL(base, { query: 'rust', source: 'notes', kuraBase: 'https://shiori.example/kura/' }), 'https://shiori.example/kura/feed.xml?q=rust');
  assert.equal(S.feedURL(base, { query: '*', source: 'notes', kuraBase: 'https://shiori.example/kura' }), 'https://shiori.example/kura/feed.xml');
  assert.equal(S.feedURL(base, { opened: true }), 'https://shiori.example/api/history?opened=true&format=rss');
  assert.equal(S.newsBlurSubscribeURL('https://newsblur.example', 'https://f/x?a=1'), 'https://newsblur.example/?url=https%3A%2F%2Ff%2Fx%3Fa%3D1');
  assert.equal(S.newsBlurSubscribeURL('', 'https://f/'), null);
});

test('vi keys: j/k, h/l, open, preview, copy, help, search, label', () => {
  const k = (key, extra = {}) => S.vimKey({}, { key, now: 1000, ...extra }).action;
  assert.equal(k('j'), 'next');
  assert.equal(k('k'), 'prev');
  assert.equal(k('h'), 'tabPrev');
  assert.equal(k('l'), 'tabNext');
  assert.equal(k('o'), 'open');
  assert.equal(k('Enter'), 'open');
  assert.equal(k('p'), 'preview');
  assert.equal(k('y'), 'copy');
  assert.equal(k('e'), 'label');
  assert.equal(k('?', { shiftKey: true }), 'help');
  assert.equal(k('/'), 'focusSearch');
  assert.equal(k('Escape'), 'escape');
  assert.equal(k('G', { shiftKey: true }), 'bottom');
  assert.equal(k('x'), null);
});

test('vi keys: gg and dd within 600 ms; slower, or another key between, is not', () => {
  for (const [key, action] of [['g', 'top'], ['d', 'delete']]) {
    let r = S.vimKey({}, { key, now: 1000 });
    assert.equal(r.action, null);
    assert.equal(r.state.pendingKey, key);
    assert.equal(r.state.at, 1000);
    assert.equal(S.vimKey(r.state, { key, now: 1500 }).action, action);
    r = S.vimKey({}, { key, now: 1000 });
    const late = S.vimKey(r.state, { key, now: 1700 });
    assert.equal(late.action, null);
    assert.equal(late.state.at, 1700); // a fresh first press
    r = S.vimKey({}, { key, now: 1000 });
    r = S.vimKey(r.state, { key: 'j', now: 1100 });
    assert.equal(S.vimKey(r.state, { key, now: 1200 }).action, null);
  }
  // g then d is neither.
  const r = S.vimKey({}, { key: 'g', now: 1000 });
  assert.equal(S.vimKey(r.state, { key: 'd', now: 1100 }).action, null);
});

test('vi keys: modifiers belong to the browser; in a field only Escape counts', () => {
  for (const mod of ['metaKey', 'ctrlKey', 'altKey']) assert.equal(S.vimKey({}, { key: 'j', [mod]: true }).action, null);
  assert.equal(S.vimKey({}, { key: 'j', inField: true }).action, null);
  assert.equal(S.vimKey({}, { key: '/', inField: true }).action, null);
  assert.equal(S.vimKey({}, { key: 'Escape', inField: true }).action, 'escape');
});

test('summaries: web pages only, never notes', () => {
  assert.equal(S.summarizable('https://example.com/a', ''), true);
  assert.equal(S.summarizable('https://example.com/a', 'vault'), false);
  assert.equal(S.summarizable('https://notes.example/v/work/n/x', ''), false, "another vault's note, whatever its label");
  assert.equal(S.summarizable('https://kura.example.ts.net/n/x', ''), false);
  assert.equal(S.summarizable('https://konbini.example.ts.net/p/x', 'alpha'), false);
  assert.equal(S.summarizable('https://niwa.example.ts.net/n/x', ''), false);
  assert.equal(S.summarizable('file:///etc/passwd', ''), false);
  assert.equal(S.summarizable('not a url', ''), false);
});

test('summaries: byline, parts and errors', () => {
  assert.equal(S.summaryByline({ engine: 'anthropic' }), 'By Anthropic');
  assert.equal(S.summaryByline({ engine: 'anthropic', partial: true }), 'By Anthropic · from the first part of a long page');
  assert.deepEqual(
    JSON.parse(JSON.stringify(S.summaryParts('A page about C64s.\n• One\n- Two\n\n* Three'))),
    { opening: 'A page about C64s.', points: ['One', 'Two', 'Three'] },
  );
  assert.match(S.summaryError(429, 'cap', ''), /used up/);
  assert.match(S.summaryError(403, 'note', ''), /Notes/);
  assert.match(S.summaryError(0, '', ''), /network or VPN/);
  assert.equal(S.summaryError(500, 'weird', 'Something odd'), 'Something odd');
});

test('AI answers: citations become runs, cited sources in order', () => {
  const runs = JSON.parse(JSON.stringify(S.answerRuns('Bristol band [1][3]. Formed 1988 [2].')));
  assert.deepEqual(runs, [{ text: 'Bristol band ' }, { cite: 1 }, { cite: 3 }, { text: '. Formed 1988 ' }, { cite: 2 }, { text: '.' }]);
  const sources = [
    { n: 3, title: 'c', url: 'https://c.example/' },
    { n: 1, title: 'a', url: 'https://a.example/' },
    { n: 2, title: 'b', url: 'javascript:alert(1)' },
    { n: 4, title: 'd', url: 'https://d.example/' },
  ];
  assert.deepEqual(S.citedSources('x [1] y [2] z [3]', sources).map((s) => s.n), [1, 3]);
  assert.equal(S.answerRuns('').length, 0);
});

test('entities left in web snippets are decoded', () => {
  assert.equal(S.decodeEntities('&#34;First&#34; &amp; &quot;Second&quot;'), '"First" & "Second"');
  assert.equal(S.decodeEntities('caf&#xe9; &nbsp;x'), 'café  x');
  assert.equal(S.decodeEntities('AT&T &bogus; &#0;'), 'AT&T &bogus; &#0;');
  assert.equal(S.decodeEntities('<b>not markup</b>'), '<b>not markup</b>');
  assert.equal(S.decodeEntities(undefined), '');
  assert.match(S.summaryError(422, 'no_results', ''), /nothing to answer/);
});

test('did you mean: respellings from the web, even when something was found', () => {
  const orwell = ['george orwell', 'george orwell 1984', 'george orwell books', 'george orwell quotes'];
  assert.equal(S.didYouMean('george orewell', orwell), 'george orwell');
  assert.equal(S.didYouMean('George  Orewell', orwell), 'george orwell');
  // Run together, letters swapped: the spaced form most suggestions start with.
  const pi = ['raspberry pi imager', 'raspberry pi 5', 'raspberry pi connect', 'raspberry pi 4', 'raspberry pie', 'raspberrypi', 'raspberry pi pico'];
  assert.equal(S.didYouMean('rapsberrypi', pi), 'raspberry pi');
  assert.equal(S.didYouMean('raspbery pi pico', ['raspberry pi pico', 'raspberry pi pico pinout', 'raspberry pi pico 2']), 'raspberry pi pico');
  // Only the spacing: when the web agrees.
  assert.equal(S.didYouMean('raspberrypi', pi), 'raspberry pi');
  // Already right, too far, too short, or Hister syntax: nothing.
  assert.equal(S.didYouMean('george orwell', orwell), null);
  assert.equal(S.didYouMean('orwell essays', orwell), null);
  assert.equal(S.didYouMean('rust', ['rest', 'rust lang']), null);
  assert.equal(S.didYouMean('label:alpha orewell', orwell), null);
  assert.equal(S.didYouMean('george orewell', []), null);
  // Each changed word within its own room, not the whole query's.
  assert.equal(S.didYouMean('github machiya', ['github machine', 'github machine learning']), null);
  assert.equal(S.didYouMean('github machne', ['github machine', 'github machine learning']), 'github machine');
  // Right already, with completions around it: nothing ("raspberry pi 5" is one edit away).
  assert.equal(S.didYouMean('raspberry pi', ['raspberry pi 5', 'raspberry pi 4', 'raspberry pi pico', 'raspberrypi']), null);
});

test('type-ahead: the rest of the first candidate that starts with what is typed', () => {
  const candidates = ['raspberry pi', 'raspberry pi 5', 'Rust lang'];
  assert.equal(S.typeAhead('raspb', candidates), 'erry pi');
  assert.equal(S.typeAhead('RASPB', candidates), 'erry pi');
  assert.equal(S.typeAhead('raspberry ', candidates), 'pi');
  assert.equal(S.typeAhead('rus', candidates), 't lang');
  assert.equal(S.typeAhead('raspberry pi', candidates), ' 5');
  assert.equal(S.typeAhead('r', candidates), '');
  assert.equal(S.typeAhead('zebra', candidates), '');
  assert.equal(S.typeAhead('raspberry pi 5', candidates), '');
});

test('Kura: queries, URLs and replies as Hister documents', () => {
  assert.equal(S.kuraQuery('shiori label:vault'), 'shiori*');
  assert.equal(S.kuraQuery('title:shio* tag:area/projects'), 'title:shio* tag:area/projects');
  assert.equal(S.kuraQuery('* label:vault'), '');
  assert.equal(S.kuraQuery('@vintage'), '');
  const base = 'https://kura.example/';
  assert.equal(S.kuraURL(base, 'hister label:vault', { limit: 5 }), 'https://kura.example/api/search?limit=5&offset=0&q=hister*&sort=relevance');
  assert.equal(S.kuraURL(base, 'hister', { sort: 'date', offset: 20 }), 'https://kura.example/api/search?limit=20&offset=20&q=hister*&sort=changed');
  assert.equal(S.kuraURL(base, '* label:vault', { limit: 30 }), 'https://kura.example/api/recent?limit=30&offset=0');
  const reply = {
    total: 25,
    results: [
      { path: 'Projects/Garden Plan.md', title: 'Garden Plan', url: 'https://kura.example/n/Projects/Garden%20Plan', snippet: '<mark>Garden</mark> Plan', tags: ['type/idea'], created: 1790380800, changed: 1790553600, vault: 'personal', card_url: 'https://konbini.example/p/garden-plan' },
      { path: 'x.md', title: 'bad', url: 'javascript:alert(1)' },
    ],
  };
  const r = JSON.parse(JSON.stringify(S.kuraDocuments(reply)));
  assert.equal(r.total, 25);
  assert.equal(r.documents.length, 1);
  assert.deepEqual(r.documents[0], {
    url: 'https://kura.example/n/Projects/Garden%20Plan', title: 'Garden Plan', text: '<mark>Garden</mark> Plan', label: 'vault',
    added: 1790380800, updated: 1790553600, metadata: { tags: ['type/idea'] }, path: 'Projects/Garden Plan.md', vault: 'personal', card_url: 'https://konbini.example/p/garden-plan',
  });
  assert.equal(S.kuraDocuments(null).documents.length, 0);
});

// HisterKit's SearchTextAndMergeTests, case for case.
test('the last plain word is a prefix', () => {
  const cases = [
    ['hist', 'hist*'], ['raspberry pi', 'raspberry pi*'], ['raspberry pi ', 'raspberry pi '], ['pi 5', 'pi 5'],
    ['a', 'a'], ['hist*', 'hist*'], ['label:alpha', 'label:alpha'], ['c++', 'c++'], ['"exact phrase', '"exact phrase'],
    ['"exact" phrase', '"exact" phrase*'], ['@vintage', '@vintage'], ['*', '*'], ['', ''], ['町家', '町家*'],
  ];
  for (const [typed, sent] of cases) assert.equal(S.prefixLastWord(typed), sent, typed);
});

test('Hister never gets the notes', () => {
  assert.equal(S.histerText('hist'), 'hist* -label:vault -metadata.source:vault');
  assert.equal(S.histerText('*'), '* -label:vault -metadata.source:vault');
  assert.equal(S.histerText(''), '-label:vault -metadata.source:vault');
  assert.equal(S.histerText('x -label:vault -metadata.source:vault'), 'x -label:vault -metadata.source:vault');
  assert.equal(S.typedQuery('rust* -label:vault -metadata.source:vault'), 'rust');
});

test('merges newest first and waits for the other list', () => {
  const page = (url, at) => ({ url, updated: at });
  const m = S.newestFirstMerge();
  m.addPages([page('p9', 9), page('p5', 5)], 'k');
  m.addNotes([page('n7', 7), page('n6', 6), page('n1', 1)], null);
  assert.deepEqual([...m.take().map((d) => d.url)], ['p9', 'n7', 'n6', 'p5']);
  assert.ok(m.needsPages() && !m.needsNotes() && !m.finished());
  m.addPages([page('p3', 3), page('p0', 0)], null);
  assert.deepEqual([...m.take().map((d) => d.url)], ['p3', 'n1', 'p0']);
  assert.ok(m.finished());
  const n = S.newestFirstMerge();
  n.addPages([page('p2', 2), page('p1', 1)], 'k');
  n.endNotes();
  assert.deepEqual([...n.take().map((d) => d.url)], ['p2', 'p1']);
  assert.ok(n.needsPages());
});

test("Hister's own @notes and @pages aren't collections", () => {
  const kept = S.collectionAliases({ '@notes': 'label:vault', '@pages': '* -label:vault -metadata.source:vault', '@systems': 'label:(linux|solaris)', '@tools': 'label:passwords', '@mixed': 'label:(books|vault)' });
  assert.deepEqual(Object.keys(kept).sort(), ['@systems', '@tools']);
});

test('the rooms switcher: known addresses, in the house order', () => {
  const r = S.rooms('kura=https://kura.example/,hister=https://hister.example/,konbini=nope,searxng=https://searx.example/', 'https://shiori.example');
  assert.deepEqual([...r.map((x) => x.key)], ['shiori', 'kura', 'hister', 'searxng']);
  assert.equal(r[0].url, 'https://shiori.example/');
  assert.equal(r[1].tint, 'notes');
  assert.equal(S.rooms('__SHIORI_ROOMS__').length, 0);
  assert.equal(S.rooms('shiori=https://s.example/').length, 1);
});

test("the house's shared settings: cookies in Shiori's terms", () => {
  const c = 'a=1; machiya_theme=day; machiya_textSize=large; machiya_show_niwa=false; machiya_show_kura=true';
  assert.deepEqual(JSON.parse(JSON.stringify(S.houseSettings(c))), { hidden: ['niwa'], theme: 'day', textSize: 'xLarge' });
  // Shiori's Medium is written as the house's "small": reading it back keeps Medium.
  assert.equal(S.houseSettings('machiya_textSize=small', { mine: 'medium' }).textSize, undefined);
  assert.equal(S.houseSettings('machiya_textSize=small', { mine: 'system' }).textSize, 'small');
  assert.equal(S.houseSettings('machiya_theme=auto').theme, 'system');
  assert.equal(S.houseSettings('machiya_theme=purple').theme, undefined);
  assert.equal(S.houseDomain('shiori.tail.ts.net'), 'tail.ts.net');
  assert.equal(S.houseDomain('127.0.0.1'), '');
  assert.equal(S.houseDomain('localhost'), '');
  assert.equal(S.houseCookie('theme', 'night', 'search.tail.ts.net'), 'machiya_theme=night; path=/; max-age=31536000; samesite=lax; domain=tail.ts.net');
  assert.equal(S.houseCookie('textSize', 'xxxLarge', 'localhost'), 'machiya_textSize=xlarge; path=/; max-age=31536000; samesite=lax');
  assert.equal(S.houseCookie('resultStyle', 'tint', 'x.y.z'), null);
});

// HisterKit's SmallWebTests, case for case.
test('Small Web: the gateway search, results and marks', () => {
  assert.equal(S.smallwebSearchURL('https://smallweb.example', '  sample   query ', 2), 'https://smallweb.example/api/search?q=sample+query&page=2');
  assert.equal(S.smallwebSearchURL('https://smallweb.example/', '   '), '');
  assert.equal(S.smallwebSearchURL('', 'x'), '');
  const reply = {
    results: [
      { title: 'A Sample Post', url: 'gemini://capsule.example/sample_post', proxy_url: 'https://smallweb.example/page?url=g', snippet: 'sample notes … my query', marks: [[18, 23], [0, 6]], source: 'tlgs', sources: ['tlgs', 'kennedy'], scheme: 'gemini' },
      { title: '', url: 'gopher://gopher.example/1/phlog', proxy_url: 'https://smallweb.example/page?url=x', source: 'veronica', sources: ['veronica'] },
      { title: 'Not ours', url: 'https://example.com/', proxy_url: 'https://smallweb.example/page?url=y' },
      { title: 'Broken' },
    ],
    sources: { tlgs: { ok: true, next: true }, veronica: { ok: false, next: false } },
    errors: { veronica: 'timeout' },
  };
  const out = S.smallwebResults(reply);
  assert.deepEqual([...out.results.map((r) => r.url)], ['gemini://capsule.example/sample_post', 'gopher://gopher.example/1/phlog']);
  assert.equal(out.results[1].title, 'gopher://gopher.example/1/phlog');
  assert.equal(out.results[1].scheme, 'gopher');
  assert.equal(out.results[0].engines, 'TLGS · Kennedy');
  assert.equal(out.results[0].place, 'capsule.example/sample_post');
  assert.equal(out.more, true);
  assert.deepEqual([...out.failures], ['Veronica-2 timed out']);
  const runs = S.markRuns('sample notes … my query', [[18, 23], [0, 6], [3, 4], [30, 40]]);
  assert.equal(runs.map((r) => (r.marked ? `[${r.text}]` : r.text)).join(''), '[sample] notes … my [query]');
  const r = out.results[0];
  assert.deepEqual(JSON.parse(JSON.stringify(S.smallwebOpen(r, 'direct'))), { href: r.url, other: r.proxy_url, direct: true });
  assert.equal(S.smallwebOpen(r, 'gateway').href, r.proxy_url);
});

// HisterKit's VaultTests, case for case.
test("a vault is private until Kura marks it shared, and again when it can't be read", () => {
  const work = 'https://kura.example/v/work/n/X';
  const client = 'https://kura.example/v/client/n/X';
  S.useVaults([]);
  assert.equal(S.isPrivateNote(work), true);
  assert.equal(S.isPrivateNote('https://kura.example/n/Projects/Example'), false);
  assert.equal(S.isPrivateNote('https://example.com/'), false);
  S.useVaults([
    { name: 'personal', default: true, private: false },
    { name: 'work', default: false, private: false },
    { name: 'client', default: false, private: true },
    { name: 'other', default: false },
  ]);
  assert.equal(S.isPrivateNote(work), false);
  assert.equal(S.isPrivateNote(client), true);
  assert.equal(S.isPrivateNote('https://kura.example/v/other/n/X'), true, 'no flag: private');
  assert.equal(S.isPrivateNote('https://kura.example/v/new/n/X'), true, 'not listed: private');
  S.useVaults(null);
  assert.equal(S.isPrivateNote(work), true, 'a failed read shares nothing');
});


// HisterKit's VaultTests.kuraIsAskedAgainBeforeAnythingIsSent, case for case.
test('Kura is asked again before anything is sent: shared when cached, private when asked, refused', async () => {
  const work = 'https://kura.example/v/work/n/X';
  const shared = [{ name: 'work', default: false, private: false }];
  const madePrivate = [{ name: 'work', default: false, private: true }];
  S.useVaults(shared);
  assert.equal(S.isPrivateNote(work), false);
  assert.equal(await S.isPrivateNoteNow(work, async () => madePrivate), true, 'shared when cached, private when asked: refused');
  assert.equal(S.isPrivateNote(work), true, 'the fresh answer is kept');
  S.useVaults(shared);
  assert.equal(await S.isPrivateNoteNow(work, async () => { throw new Error('unreachable'); }), true, 'Kura out of reach: private');
  assert.equal(await S.isPrivateNoteNow(work, async () => null), true, 'no list: private');
  assert.equal(await S.isPrivateNoteNow(work, async () => shared), false);
  let asked = 0;
  const count = async () => (asked++, shared);
  assert.equal(await S.isPrivateNoteNow('https://kura.example/n/X', count), false);
  assert.equal(await S.isPrivateNoteNow('https://example.com/', count), false);
  assert.equal(asked, 0, "the default vault's notes and pages ask nothing");
  S.useVaults([]);
});

test('loadVaults passes what Kura says to useVaults, and [] when it fails', async () => {
  const list = [{ name: 'personal', default: true, private: false }, { name: 'team', default: false, private: false }];
  assert.deepEqual(await S.loadVaults(async () => list), list);
  assert.equal(S.isPrivateNote('https://kura.example/v/team/n/X'), false);
  assert.equal((await S.loadVaults(async () => { throw new Error('down'); })).length, 0);
  assert.equal(S.isPrivateNote('https://kura.example/v/team/n/X'), true);
});

test('work vaults: known by the address alone', () => {
  assert.equal(S.noteVault('https://kura.example/v/work/n/Literature%20Notes/Weekly'), 'work');
  assert.equal(S.noteVault('https://kura.example/n/Projects/Example'), null);
  assert.equal(S.noteVault('https://example.com/v/x'), null);
  assert.equal(S.isPrivateNote('https://kura.example/v/client/n/X'), true);
  assert.equal(S.notePath('https://kura.example/v/work/n/Literature%20Notes/Weekly', []), 'Literature Notes/Weekly.md');
  assert.equal(S.readerURL('https://kura.example/v/work/n/X', 'https://kura.example/', 'X.md'), 'https://kura.example/v/work/n/X');
  assert.equal(S.isNoteURL('https://kura.example/v/work/n/X', 'https://kura.example/'), true);
  assert.ok(!S.kuraURL('https://kura.example/', 'cost').includes('vault='));
  assert.ok(S.kuraURL('https://kura.example/', 'cost', { vault: 'all' }).includes('vault=all'));
});

test('a scrolling row fades at the ends with more to see', () => {
  assert.equal(S.edgeFade({ scrollLeft: 0, scrollWidth: 300, clientWidth: 300 }), '');
  assert.equal(S.edgeFade({ scrollLeft: 0, scrollWidth: 500, clientWidth: 300 }), 'end');
  assert.equal(S.edgeFade({ scrollLeft: 100, scrollWidth: 500, clientWidth: 300 }), 'both');
  assert.equal(S.edgeFade({ scrollLeft: 200, scrollWidth: 500, clientWidth: 300 }), 'start');
  // A fraction of a pixel short at either end still counts as there.
  assert.equal(S.edgeFade({ scrollLeft: 199.5, scrollWidth: 500, clientWidth: 300 }), 'start');
  assert.equal(S.edgeFade({ scrollLeft: 1, scrollWidth: 500, clientWidth: 300 }), 'end');
  assert.equal(S.edgeFade(), '');
});

test('"wiki" in a search asks for Wikipedia', () => {
  assert.equal(S.wikiQuery('wiki moon phases'), 'moon phases');
  assert.equal(S.wikiQuery('moon phases Wikipedia'), 'moon phases');
  assert.equal(S.wikiQuery('WIKI  tokyo'), 'tokyo');
  assert.equal(S.wikiQuery('wikis tokyo'), null);
  assert.equal(S.wikiQuery('mediawiki setup'), null);
  assert.equal(S.wikiQuery('wiki'), null);
  assert.equal(S.wikiQuery(''), null);
});

test('the first Wikipedia article among web results', () => {
  const r = (url) => ({ url });
  const list = [
    r('http://www.stars.example/moon.htm'),
    r('https://www.wikipedia.org/'),
    r('https://en.wikipedia.org/wiki/Main_Page'),
    r('https://en.wikipedia.org/wiki/Special:Search?search=x'),
    r('https://en.wikipedia.org/wiki/Category:Moon'),
    r('https://en.m.wikipedia.org/wiki/Moon'),
    r('https://en.wikipedia.org/wiki/Sun'),
  ];
  assert.deepEqual({ ...S.wikipediaArticle(list) }, {
    url: 'https://en.wikipedia.org/wiki/Moon',
    title: 'Moon',
    lang: 'en',
    index: 5,
  });
  // Titles that only start like a namespace are articles.
  assert.equal(S.wikipediaArticle([r('https://en.wikipedia.org/wiki/Special_relativity')]).title, 'Special relativity');
  assert.equal(S.wikipediaArticle([r('https://en.wikipedia.org/wiki/User_interface')]).title, 'User interface');
  assert.equal(S.wikipediaArticle([r('https://de.wikipedia.org/wiki/Z%C3%BCrich')]).title, 'Zürich');
  assert.equal(S.wikipediaArticle([r('https://cards.wiki.example/wiki/Moon')]), null);
  assert.equal(S.wikipediaArticle([r('https://en.wikipedia.org/wiki/Talk:Moon')]), null);
  // Namespaces are translated: known by shape, not name.
  assert.equal(S.wikipediaArticle([r('https://sw.wikipedia.org/wiki/Faili:Moon.jpg')]), null);
  assert.equal(S.wikipediaArticle([r('https://en.wikipedia.org/wiki/Example:_Subtitle')]).title, 'Example: Subtitle');
  // The reader's language first, else the first in any.
  const mixed = [r('https://sw.wikipedia.org/wiki/Paris'), r('https://en.wikipedia.org/wiki/Moon')];
  assert.equal(S.wikipediaArticle(mixed, ['en-US']).lang, 'en');
  assert.equal(S.wikipediaArticle(mixed, ['fr']).lang, 'sw');
  assert.equal(S.wikipediaArticle(mixed).lang, 'sw');
  assert.equal(S.wikipediaArticle([]), null);
});

test('Wikipedia first: moved up, or put in front', () => {
  const list = [{ url: 'https://a.example/' }, { url: 'https://en.wikipedia.org/wiki/Moon', title: 'G' }, { url: 'https://b.example/' }];
  const article = S.wikipediaArticle(list);
  assert.deepEqual([...S.wikiFirst(list, article).map((x) => x.url)], [
    'https://en.wikipedia.org/wiki/Moon',
    'https://a.example/',
    'https://b.example/',
  ]);
  const found = { url: 'https://en.wikipedia.org/wiki/Lisbon', title: 'Lisbon - Wikipedia', content: 'Capital of Portugal' };
  const other = S.wikipediaArticle([found]);
  const out = S.wikiFirst([{ url: 'https://a.example/' }], other, found);
  assert.equal(out[0], found);
  assert.equal(out.length, 2);
  assert.equal(S.wikiFirst(list, null).length, 3);
});

test("save this note's links: deduplicated across notes, capped (HisterKit's SaveLinks twin)", () => {
  const note = (path, urls) => ({ path, title: path, external_links: urls.map((url) => ({ url, text: 't' })) });
  const rows = S.saveLinkRows([
    note('A', ['https://example.com/a', 'https://www.example.com/a/#top', 'ftp://example.com/x', 'mailto:x@y']),
    note('B', ['https://example.com/a?utm_source=x', 'https://example.org/b']),
  ]);
  assert.deepEqual([...rows.map((r) => r.url)], ['https://example.com/a', 'https://example.org/b']);
  assert.deepEqual([...rows.map((r) => r.notePath)], ['A', 'B']);
  const many = note('C', Array.from({ length: 250 }, (_, i) => `https://example.net/${i}`));
  assert.equal(S.saveLinkRows([many]).length, 200);
  assert.equal(S.saveLinkRows([{ path: 'D' }]).length, 0);
});

test("a note's tags offer only labels that exist", () => {
  const labels = ['vintage-tech', 'books', 'Linux'];
  assert.deepEqual([...S.tagLabelCandidates(['type/idea', 'topic/vintage-tech', '#books', 'linux', 'made-up'], labels)], ['vintage-tech', 'books', 'Linux']);
  assert.deepEqual([...S.tagLabelCandidates(['books', 'Books'], labels)], ['books']);
  assert.deepEqual([...S.tagLabelCandidates([], labels)], []);
});

test('the source link: only a plain web address (HisterKit SourceLink twin)', () => {
  assert.equal(S.sourceLink('https://github.com/example/shiori'), 'https://github.com/example/shiori');
  assert.equal(S.sourceLink(' http://git.example/shiori '), 'http://git.example/shiori');
  assert.equal(S.sourceLink(''), '');
  assert.equal(S.sourceLink(undefined), '');
  assert.equal(S.sourceLink('javascript:alert(1)'), '');
  assert.equal(S.sourceLink('ftp://example.com/x'), '');
  assert.equal(S.sourceLink('https://user:pw@example.com/'), '');
  assert.equal(S.sourceLink('https://exa mple.com/'), '');
  assert.equal(S.sourceLink('__SHIORI_SOURCE_URL__'), '');
  assert.equal(S.LICENCE, 'GNU AGPL-3.0-or-later');
});

test('a link to a file is not a page (HisterKit SaveLinks.looksLikeFile twin)', () => {
  assert.equal(S.linkLooksLikeFile('https://archive.boards.example/debian/pool/main/x_1.0+git_armhf.deb'), true);
  assert.equal(S.linkLooksLikeFile('https://example.com/a/paper.PDF'), true);
  assert.equal(S.linkLooksLikeFile('https://example.com/files.tar.gz'), true);
  assert.equal(S.linkLooksLikeFile('https://github.com/mpv-player/mpv/releases/tag/v0.35.1'), false);
  assert.equal(S.linkLooksLikeFile('https://example.com/index.html'), false);
  assert.equal(S.linkLooksLikeFile('https://example.com/v1.2/notes'), false);
  assert.equal(S.linkLooksLikeFile('not a url'), false);
});

test("a note's chip names its vault (HisterKit Notes.vaultChip twin)", () => {
  const vaults = [{ name: 'personal', title: 'Personal', default: true }, { name: 'work', title: 'Work' }];
  assert.deepEqual({ ...S.vaultChip('https://kura.example/n/Projects/Example', vaults) }, { name: 'personal', text: 'Personal vault' });
  assert.deepEqual({ ...S.vaultChip('https://kura.example/v/work/n/X', vaults) }, { name: 'work', text: 'Work vault' });
  assert.deepEqual({ ...S.vaultChip('https://kura.example/v/client/n/X', vaults) }, { name: 'client', text: 'client vault' });
  assert.deepEqual({ ...S.vaultChip('https://kura.example/n/X', []) }, { name: '', text: 'vault' });
});

test("a note's gemini and gopher links are offered, compared conservatively (SaveLinks twin)", () => {
  const note = (path, urls) => ({ path, title: path, external_links: urls.map((url) => ({ url, text: '' })) });
  const rows = S.saveLinkRows([
    note('A', ['gemini://Example.org:1965/log/', 'gopher://hole.example:70/1/users', 'https://example.com/']),
    note('B', ['gemini://example.org/log/', 'gemini://example.org/log', 'GOPHER://HOLE.EXAMPLE/1/users', 'mailto:x@y']),
  ]);
  assert.deepEqual([...rows.map((r) => r.url)], ['gemini://Example.org:1965/log/', 'gopher://hole.example:70/1/users', 'https://example.com/', 'gemini://example.org/log']);
  assert.equal(S.isSmallWebLink('gemini://a/'), true);
  assert.equal(S.isSmallWebLink('https://a/'), false);
  assert.equal(S.smallWebKey('gemini://Example.org:1965/Log/'), 'gemini://example.org/Log/');
  assert.equal(S.smallWebKey('gopher://h:7070/x'), 'gopher://h:7070/x');
});
