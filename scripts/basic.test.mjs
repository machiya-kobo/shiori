// Basic Search (web/basic.mjs): Shiori's search as plain HTML for a browser without JavaScript. The shiori-web image
// runs it in nginx's njs (QuickJS, no URL or Intl); tools/container-test checks it there. Run: node --test scripts/

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';
import { basic, carriedOver, esc, httpLink, parseQuery, request, snippetHTML } from '../web/basic.mjs';

const read = (rel) => readFileSync(fileURLToPath(new URL(`../${rel}`, import.meta.url)), 'utf8');
// search-core in a bare context, as njs has it: no URL, URLSearchParams or fetch there.
const context = vm.createContext({});
vm.runInContext(read('patches/shiori/search-core.js'), context);
const S = context.ShioriSearch;
assert.equal(vm.runInContext('typeof URL + typeof URLSearchParams', context), 'undefinedundefined');

const SITE = { kura: true, signIn: '/auth', kuraSignIn: 'https://kura.example/signin', self: 'https://search.example/' };

/** A fake host: each route's answer by path prefix, every path asked kept. */
function host(answers = {}) {
  const asked = [];
  const get = async (path) => {
    asked.push(path);
    for (const [prefix, answer] of Object.entries(answers)) {
      if (path.startsWith(prefix)) {
        if (answer instanceof Error) throw answer;
        return typeof answer === 'number' ? { status: answer, body: '{}' } : { status: 200, body: JSON.stringify(answer) };
      }
    }
    return { status: 200, body: JSON.stringify({ documents: [], results: [], total: 0 }) };
  };
  return { asked, get };
}

const hister = (n, extra = {}) => ({
  total: 42,
  documents: Array.from({ length: n }, (_, i) => ({ url: `https://example.com/page${i}`, title: `Page ${i}`, text: `about <mark>rust</mark> ${i}` })),
  ...extra,
});
const kura = (n, total = n) => ({ total, results: Array.from({ length: n }, (_, i) => ({ url: `https://kura.example/n/note${i}`, title: `Note ${i}`, path: `Notes/note${i}.md`, snippet: 'a <mark>note</mark>' })) });
const searx = (n) => ({ results: Array.from({ length: n }, (_, i) => ({ url: `https://web.example/${i}`, title: `Web &#34;${i}&#34;`, content: `web text ${i}` })) });

function args(o) {
  return Object.entries(o).map(([k, v]) => `${k}=${encodeURIComponent(v)}`).join('&');
}

test('the renderer and what it uses of search-core need no URL, URLSearchParams, Intl or DOM (njs has none)', () => {
  const src = read('web/basic.mjs').replace(/^\s*\/\/.*$/gm, '');
  for (const word of ['new URL', 'URLSearchParams', 'Intl.', 'toLocale', 'document.', 'window.', 'fetch(']) {
    assert.ok(!src.includes(word), word);
  }
});

test('parseQuery decodes as a form does, and request() checks every value', () => {
  assert.deepEqual(parseQuery('q=rust+book&t=pages&x=%E2%9C%93&bad=%E0'), { q: 'rust book', t: 'pages', x: '✓', bad: '%E0' });
  assert.deepEqual(request('q=+hi+&t=evil&p=-3'), { q: 'hi', tab: 'all', page: 1, key: '', hasQ: true });
  assert.equal(request('q=a&p=999').page, 50);
  assert.equal(request(`q=${'x'.repeat(900)}`).q.length, 500);
  assert.equal(request('').hasQ, false);
});

test('httpLink keeps http(s) only, as a browser would read the address', () => {
  assert.equal(httpLink('https://example.com/a?b'), 'https://example.com/a?b');
  for (const bad of ['javascript:alert(1)', 'java\tscript:alert(1)', ' \u0001javascript:x', 'data:text/html,x', 'file:///etc/passwd', '//example.com', 'https://', 'http:/x', 42, null]) {
    assert.equal(httpLink(bad), '', String(bad));
  }
  assert.equal(httpLink('\n https://ex\tample.com/'), 'https://example.com/');
});

test('a snippet keeps only its <mark>s: every other tag goes, its text is escaped', () => {
  const html = snippetHTML('a <mark>b</mark> <img src=x onerror=alert(1)> &lt;script&gt;x &amp;amp; <b>bold</b>', S);
  assert.equal(html, 'a <mark>b</mark> &lt;script&gt;x &amp;amp; bold');
  assert.doesNotMatch(snippetHTML('<scr<script>ipt>alert(1)</script>', S), /<script|<scr/i);
  assert.equal(snippetHTML('x'.repeat(500), S).length, 361);
  assert.equal(esc(`<a href="x">'&`), '&lt;a href=&quot;x&quot;&gt;&#39;&amp;');
});

test('the start page: a search field, no tabs, no script', async () => {
  const h = host();
  const out = await basic({ args: '', cookie: '', referer: '', host: 'search.example' }, { S, get: h.get, site: SITE });
  assert.equal(out.status, 200);
  assert.match(out.body, /<form action="\/basic" method="get" role="search">/);
  assert.match(out.body, /name="q" value=""[^>]*autofocus/);
  assert.doesNotMatch(out.body, /<script|<nav class="tabs"/);
  assert.deepEqual(h.asked, []);
});

test("a search from the search page's address comes along (its <noscript> refresh carries it as the Referer)", async () => {
  assert.equal(carriedOver('https://search.example/?q=rust%20book&cat=hister', 'search.example'), '/basic?q=rust%20book&t=pages');
  assert.equal(carriedOver('https://search.example/?q=x&cat=vault', 'search.example'), '/basic?q=x&t=notes');
  assert.equal(carriedOver('https://search.example/?q=x&cat=images', 'search.example'), '/basic?q=x&t=web');
  assert.equal(carriedOver('https://search.example/index.html?q=x', 'search.example'), '/basic?q=x');
  assert.equal(carriedOver('https://other.example/?q=x', 'search.example'), '', 'another site');
  assert.equal(carriedOver('https://search.example/somewhere?q=x', 'search.example'), '', 'another page');
  assert.equal(carriedOver('https://search.example/?cat=hister', 'search.example'), '', 'no words');
  const out = await basic({ args: '', referer: 'https://search.example/?q=rust', host: 'search.example' }, { S, get: host().get, site: SITE });
  assert.equal(out.status, 303);
  assert.equal(out.headers.Location, '/basic?q=rust');
  // An empty search asked for on purpose is the start page, whatever the Referer.
  const empty = await basic({ args: 'q=', referer: 'https://search.example/?q=rust', host: 'search.example' }, { S, get: host().get, site: SITE });
  assert.equal(empty.status, 200);
});

test('All: your top five pages and notes, then the web, each asked as the search page asks', async () => {
  const h = host({ '/search?': hister(10), '/kura/api/search?': kura(5, 12), '/searx/search?': searx(3) });
  const out = await basic({ args: args({ q: 'rust label:lang @tech' }) }, { S, get: h.get, site: SITE });
  assert.equal(out.status, 200);
  const histerAsk = h.asked.find((p) => p.startsWith('/search?'));
  const body = JSON.parse(parseQuery(histerAsk.split('?')[1]).query);
  assert.equal(body.text, S.histerText('rust label:lang @tech'));
  assert.equal(body.limit, 5);
  assert.equal(body.highlight, 'HTML');
  const kuraAsk = parseQuery(h.asked.find((p) => p.startsWith('/kura/')).split('?')[1]);
  assert.equal(kuraAsk.q, S.kuraQuery('rust label:lang @tech'));
  assert.equal(kuraAsk.vault, undefined, 'the default vault only');
  const webAsk = parseQuery(h.asked.find((p) => p.startsWith('/searx/')).split('?')[1]);
  assert.deepEqual(webAsk, { q: 'rust', format: 'json', pageno: '1', categories: 'general' });
  assert.equal((out.body.match(/class="result pages"/g) || []).length, 5);
  assert.equal((out.body.match(/class="result notes"/g) || []).length, 5);
  assert.equal((out.body.match(/class="result web"/g) || []).length, 3);
  assert.match(out.body, /<h2>Your Pages <span class="count"><a href="\/basic\?q=rust%20label%3Alang%20%40tech&amp;t=pages">42 results ›<\/a>/);
  assert.match(out.body, /12 results ›/);
  assert.match(out.body, /<div class="url">Notes\/note0<\/div>/);
  assert.match(out.body, />Web &quot;0&quot;<\/a>/, "a web title escaped twice is decoded once, then escaped");
  assert.match(out.body, /<span aria-current="page">All<\/span>/);
  assert.match(out.body, /<title>rust label:lang @tech · Shiori<\/title>/);
  assert.doesNotMatch(out.body, /<script/i);
});

test('without Kura there is no Notes tab and Kura is never asked', async () => {
  const h = host({ '/search?': hister(2) });
  const out = await basic({ args: 'q=rust&t=notes' }, { S, get: h.get, site: { ...SITE, kura: false } });
  assert.ok(!h.asked.some((p) => p.startsWith('/kura/')));
  assert.doesNotMatch(out.body, />Notes</);
  assert.match(out.body, /<span aria-current="page">All<\/span>/);
});

test('only Hister syntax: no web search (each one counts)', async () => {
  const h = host({ '/search?': hister(1) });
  await basic({ args: args({ q: 'label:rust' }) }, { S, get: h.get, site: SITE });
  assert.ok(!h.asked.some((p) => p.startsWith('/searx/')));
});

test("a result's address must be http(s); its title and text are escaped", async () => {
  const h = host({
    '/search?': { total: 3, documents: [
      { url: 'javascript:alert(1)', title: 'bad', text: '' },
      { url: 'java\tscript:alert(1)', title: 'bad too', text: '' },
      { url: 'https://example.com/"><script>alert(1)</script>', title: '<script>alert(2)</script>', text: '<img src=x onerror=alert(3)>' },
    ] },
    '/searx/search?': { results: [{ url: 'data:text/html,hi', title: 'data' }, { url: 'https://ok.example/', title: '<b>x</b>', content: '<script>y</script>' }] },
  });
  const out = await basic({ args: 'q=x' }, { S, get: h.get, site: SITE });
  assert.doesNotMatch(out.body, /javascript:|data:text|<script>|<img src=x|onerror|<b>x/i);
  assert.match(out.body, /href="https:\/\/example\.com\/&quot;&gt;&lt;script&gt;alert\(1\)&lt;\/script&gt;"/);
  assert.match(out.body, />&lt;script&gt;alert\(2\)&lt;\/script&gt;<\/a>/);
  assert.equal((out.body.match(/class="result /g) || []).length, 2);
});

test('Pages pages by Hister\'s key; Notes by offset; Web by number', async () => {
  const pages = host({ '/search?': hister(20, { page_key: 'key-2' }) });
  const out = await basic({ args: 'q=rust&t=pages' }, { S, get: pages.get, site: SITE });
  assert.equal(JSON.parse(parseQuery(pages.asked[0].split('?')[1]).query).limit, 20);
  assert.match(out.body, /href="\/basic\?q=rust&amp;t=pages&amp;p=2&amp;k=key-2">Next page ›/);
  assert.match(out.body, /<h2>Your Pages <span class="count">42 results<\/span>/);
  const again = host({ '/search?': hister(3) });
  const second = await basic({ args: 'q=rust&t=pages&p=2&k=key-2' }, { S, get: again.get, site: SITE });
  assert.equal(JSON.parse(parseQuery(again.asked[0].split('?')[1]).query).page_key, 'key-2');
  assert.doesNotMatch(second.body, /Next page|Previous page/);

  const notes = host({ '/kura/api/search?': kura(20, 70) });
  const n = await basic({ args: 'q=rust&t=notes&p=3' }, { S, get: notes.get, site: SITE });
  assert.equal(parseQuery(notes.asked[0].split('?')[1]).offset, '40');
  assert.match(n.body, /p=2">‹ Previous page<\/a><a href="\/basic\?q=rust&amp;t=notes&amp;p=4">Next page ›/);

  const recent = host({ '/kura/api/recent?': kura(1) });
  await basic({ args: 'q=*&t=notes' }, { S, get: recent.get, site: SITE });
  assert.match(recent.asked[0], /^\/kura\/api\/recent\?limit=20&offset=0$/);

  const web = host({ '/searx/search?': searx(10) });
  await basic({ args: 'q=rust&t=web&p=2' }, { S, get: web.get, site: SITE });
  assert.equal(parseQuery(web.asked[0].split('?')[1]).pageno, '2');
});

test('a refused search says to sign in, back to this search; a failed one says so', async () => {
  const own = await basic({ args: 'q=rust' }, { S, get: host({ '/search?': 403, '/kura/': 401, '/searx/': new Error('down') }).get, site: SITE });
  assert.match(own.body, /<a href="\/auth">Sign In<\/a> to see your pages\./);
  assert.match(own.body, /<a href="https:\/\/kura\.example\/signin">Sign In to Kura<\/a> to see your notes\./);
  assert.match(own.body, /The web didn&#39;t answer\.|The web didn't answer\./);
  const helper = await basic({ args: 'q=rust&t=pages' }, {
    S, get: host({ '/search?': 401 }).get, site: { ...SITE, signIn: 'https://hister.example/machiya/signin' },
  });
  assert.match(helper.body, /href="https:\/\/hister\.example\/machiya\/signin\?return=https%3A%2F%2Fsearch\.example%2Fbasic%3Fq%3Drust%26t%3Dpages"/);
  const nowhere = await basic({ args: 'q=rust&t=pages' }, { S, get: host({ '/search?': 401 }).get, site: { ...SITE, signIn: '' } });
  assert.match(nowhere.body, /<p class="status">Sign in to see your pages\.<\/p>/);
  const json = await basic({ args: 'q=rust&t=web' }, { S, get: host({ '/searx/': 403 }).get, site: SITE });
  assert.match(json.body, /SearXNG doesn't allow JSON results\./);
  const broken = await basic({ args: 'q=rust&t=pages' }, { S, get: async () => ({ status: 200, body: 'not json' }), site: SITE });
  assert.match(broken.body, /Your pages didn't answer\./);
});

test("the house's theme and palette from its cookies; anything else is left out", async () => {
  const day = await basic({ args: '', cookie: 'machiya_theme=day; machiya_palette=nord' }, { S, get: host().get, site: SITE });
  assert.match(day.body, /<html lang="en" data-theme="day" data-palette="nord">/);
  const odd = await basic({ args: '', cookie: 'machiya_theme="><x; machiya_palette=evil' }, { S, get: host().get, site: SITE });
  assert.match(odd.body, /<html lang="en">/);
});

test('the search page sends a browser without JavaScript to Basic Search; the web app links it', () => {
  const page = read('patches/shiori/search.html');
  assert.match(page, /<noscript>\s*<meta http-equiv="refresh" content="0; url=\/basic" \/>/);
  assert.match(page, /<noscript><p class="noscript">[^<]*<a href="\/basic">Basic Search<\/a>/);
  const app = read('web/app/index.html');
  assert.match(app, /<noscript><p class="noscript">[^<]*<a href="\/basic">Basic Search<\/a>/);
  assert.doesNotMatch(app, /http-equiv="refresh"/, 'the web app only links it');
});
