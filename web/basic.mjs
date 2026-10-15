// Basic Search: Shiori's search for a browser without JavaScript, as plain HTML from the host (the shiori-web image's
// nginx runs it in njs; docker/shiori-web/basic-njs.mjs). The search page's and the web app's <noscript> send such a
// browser here. Your pages from Hister, your notes from Kura, then the web from SearXNG, each asked through this
// host's own routes, so sign-in and cookies work exactly as for the pages. No script, no image, no cache.
//
// Pure: the host hands in the request and a `get(path)` for its own routes, and gets the answer back. It runs under
// njs's QuickJS as well as Node (scripts/basic.test.mjs): no URL, URLSearchParams, Intl or DOM here, and from
// search-core.js only what needs none of them.

const TABS = ['all', 'pages', 'notes', 'web'];
const TAB_TITLES = { all: 'All', pages: 'Pages', notes: 'Notes', web: 'Web' };
const ALL_COUNT = 5;
const PAGE_SIZE = 20;
const MAX_QUERY = 500;
const MAX_PAGE = 50;

const ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
/** Text for HTML, in an element or a quoted attribute. */
export function esc(text) {
  return String(text ?? '').replace(/[&<>"']/g, (c) => ESCAPES[c]);
}

/** `a=b&c=d` as an object of decoded values (a later repeat wins; a bad escape keeps the raw text). */
export function parseQuery(raw) {
  const out = {};
  for (const part of String(raw || '').split('&')) {
    if (!part) continue;
    const i = part.indexOf('=');
    const key = i < 0 ? part : part.slice(0, i);
    const value = i < 0 ? '' : part.slice(i + 1);
    const decode = (s) => {
      const t = s.replace(/\+/g, ' ');
      try {
        return decodeURIComponent(t);
      } catch (_) {
        return t;
      }
    };
    out[decode(key)] = decode(value);
  }
  return out;
}

/** An object as `a=b&c=d`, values encoded; empty values left out. */
export function query(params) {
  return Object.entries(params)
    .filter(([, v]) => v !== '' && v !== undefined && v !== null)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`)
    .join('&');
}

/**
 * An address a result may link to: http(s) only, else ''. A browser drops tabs and newlines anywhere in an address
 * and leading spaces and control characters, so those go first ("java\tscript:" is javascript:).
 */
export function httpLink(url) {
  if (typeof url !== 'string') return '';
  // eslint-disable-next-line no-control-regex
  const u = url.replace(/[\t\n\r]/g, '').replace(/^[\u0000- ]+/, '');
  return /^https?:\/\/[^\s/?#]/i.test(u) ? u : '';
}

/** An address as shown under a title: no scheme, no trailing slash, at most 90 characters. */
function shownURL(url) {
  const s = url.replace(/^https?:\/\//i, '').replace(/\/$/, '');
  return s.length > 90 ? `${s.slice(0, 89)}…` : s;
}

/** A count in words: "1 result", "1,234 results". */
function countText(n) {
  const digits = String(Math.max(0, Math.floor(Number(n) || 0)));
  const grouped = digits.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return `${grouped} ${digits === '1' ? 'result' : 'results'}`;
}

/**
 * A snippet from Hister or Kura (escaped text whose only markup is <mark>) as HTML: the marks kept, any other tag
 * dropped, every piece of text decoded and escaped again, so nothing but <mark> can come through.
 */
export function snippetHTML(raw, S, max = 360) {
  let out = '';
  let length = 0;
  let marked = false;
  for (const piece of String(raw || '').split(/(<\/?mark>)/i)) {
    if (/^<mark>$/i.test(piece)) {
      marked = true;
      continue;
    }
    if (/^<\/mark>$/i.test(piece)) {
      marked = false;
      continue;
    }
    let text = S.decodeEntities(piece.replace(/<[^>]*>?/g, '')).replace(/\s+/g, ' ');
    if (!text) continue;
    if (length + text.length > max) text = `${text.slice(0, Math.max(0, max - length))}…`;
    length += text.length;
    out += marked ? `<mark>${esc(text)}</mark>` : esc(text);
    if (length >= max) break;
  }
  return out.trim();
}

/** Plain text (a web result's, perhaps escaped twice) as HTML. */
function textHTML(raw, S, max = 360) {
  const text = S.decodeEntities(String(raw || '').replace(/<[^>]*>?/g, '')).replace(/\s+/g, ' ').trim();
  return esc(text.length > max ? `${text.slice(0, max - 1)}…` : text);
}

/** What was asked for: the words, the tab, the page and Hister's page key, each checked. */
export function request(args) {
  const a = parseQuery(args);
  const q = String(a.q || '').trim().slice(0, MAX_QUERY);
  const tab = TABS.includes(a.t) ? a.t : 'all';
  const page = Math.min(MAX_PAGE, Math.max(1, parseInt(a.p, 10) || 1));
  const key = typeof a.k === 'string' && a.k.length <= 512 ? a.k : '';
  return { q, tab, page, key, hasQ: Object.prototype.hasOwnProperty.call(a, 'q') };
}

/**
 * A search carried over from the search page (`/?q=…&cat=…`, the Referer of its <noscript> refresh, which can't
 * carry the address itself): the `/basic?…` to go to, or ''. Only this host's own page counts.
 */
export function carriedOver(referer, host) {
  const m = /^https?:\/\/([^/?#]+)\/(?:index\.html)?\?([^#]*)/i.exec(String(referer || ''));
  if (!m || !host || m[1].toLowerCase() !== String(host).toLowerCase()) return '';
  const a = parseQuery(m[2]);
  const q = String(a.q || '').trim().slice(0, MAX_QUERY);
  if (!q) return '';
  const tab = a.cat === 'hister' ? 'pages' : a.cat === 'vault' ? 'notes' : a.cat && a.cat !== 'general' ? 'web' : '';
  return `/basic?${query({ q, t: tab })}`;
}

/** JSON from `get`, or the failure: { ok, status, data }. */
async function fetchJSON(get, path) {
  try {
    const r = await get(path);
    if (r.status < 200 || r.status >= 300) return { ok: false, status: r.status };
    return { ok: true, status: r.status, data: JSON.parse(r.body) };
  } catch (_) {
    return { ok: false, status: 0 };
  }
}

function histerPath(S, q, limit, key) {
  const body = { text: S.histerText(q), limit, highlight: 'HTML' };
  if (key) body.page_key = key;
  return `/search?${query({ format: 'json', query: JSON.stringify(body) })}`;
}

function kuraPath(S, q, limit, offset) {
  // No `vault`: the default vault's notes only, as All's Your Notes on the pages.
  const words = S.kuraQuery(q);
  if (!words) return `/kura/api/recent?${query({ limit, offset })}`;
  return `/kura/api/search?${query({ limit, offset, q: words, sort: 'relevance' })}`;
}

function searxPath(S, q, page) {
  return `/searx/search?${query({ q: S.webQuery(q), format: 'json', pageno: page, categories: 'general' })}`;
}

/** Hister's reply as rows: its documents, the notes and files left out by the query itself. */
function histerRows(data) {
  const docs = (data && Array.isArray(data.documents) && data.documents) || [];
  return docs
    .map((d) => ({ url: httpLink(d && d.url), title: d && d.title, text: d && d.text }))
    .filter((d) => d.url);
}

function kuraRows(S, data) {
  return S.kuraDocuments(data).documents
    .map((d) => ({ url: httpLink(d.url), title: d.title, text: d.text, place: d.path }))
    .filter((d) => d.url);
}

function webRows(data) {
  const results = (data && Array.isArray(data.results) && data.results) || [];
  return results
    .map((r) => ({ url: httpLink(r && r.url), title: r && r.title, content: r && r.content }))
    .filter((r) => r.url);
}

function resultsHTML(rows, kind, S) {
  const items = rows.map((r) => {
    const title = esc(S.decodeEntities(String(r.title || '').trim()) || shownURL(r.url));
    const snippet = kind === 'web' ? textHTML(r.content, S) : snippetHTML(r.text, S);
    const place = r.place ? esc(r.place.replace(/\.md$/i, '')) : esc(shownURL(r.url));
    return `<li class="result ${kind}"><a class="title" href="${esc(r.url)}" rel="noreferrer">${title}</a>`
      + `<div class="url">${place}</div>${snippet ? `<p class="snippet">${snippet}</p>` : ''}</li>`;
  });
  return `<ol class="results">${items.join('')}</ol>`;
}

/** The sign-in link for a refused Hister search, back to this search; '' when there's nowhere to go. */
function histerSignIn(site, back) {
  if (site.signIn === '/auth') return '/auth';
  if (/^https:\/\//i.test(site.signIn || '')) return `${site.signIn}?${query({ return: back })}`;
  return '';
}

function failure(kind, status, site, back) {
  if (kind === 'pages' && (status === 401 || status === 403)) {
    const link = histerSignIn(site, back);
    return link ? `<p class="status"><a href="${esc(link)}">Sign In</a> to see your pages.</p>` : '<p class="status">Sign in to see your pages.</p>';
  }
  if (kind === 'notes' && status === 401) {
    const link = /^https?:\/\//i.test(site.kuraSignIn || '') ? site.kuraSignIn : '';
    return link ? `<p class="status"><a href="${esc(link)}">Sign In to Kura</a> to see your notes.</p>` : '<p class="status">Sign in to Kura to see your notes.</p>';
  }
  if (kind === 'web' && status === 403) return "<p class=\"status\">SearXNG doesn't allow JSON results.</p>";
  return `<p class="status">${{ pages: 'Your pages', notes: 'Your notes', web: 'The web' }[kind]} didn't answer.</p>`;
}

const EMPTY = { pages: 'No pages match.', notes: 'No notes match.', web: 'No web results.' };
const HEADINGS = { pages: 'Your Pages', notes: 'Your Notes', web: 'Web' };

const STYLE = `
:root { color-scheme: light dark; }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text); font: 16px/1.45 -apple-system, system-ui, sans-serif; }
.wrap { max-width: 46rem; margin: 0 auto; padding: 16px; }
header { display: flex; flex-direction: column; gap: 12px; padding-bottom: 12px; border-bottom: 1px solid var(--line); }
.brand { display: inline-flex; align-items: center; gap: 8px; color: var(--text); font-weight: 600; font-size: 1.15rem; text-decoration: none; }
form { display: flex; gap: 8px; }
input[type=search] { flex: 1; min-width: 0; font: inherit; padding: 8px 12px; border-radius: 10px; border: 1px solid var(--line2, var(--line)); background: var(--card); color: var(--text); }
button { font: inherit; padding: 8px 16px; border-radius: 10px; border: 0; background: var(--accent); color: var(--bg); font-weight: 600; cursor: pointer; }
nav.tabs { display: flex; flex-wrap: wrap; gap: 6px; }
nav.tabs a, nav.tabs span { padding: 3px 12px; border-radius: 999px; border: 1px solid var(--line2, var(--line)); color: var(--text); text-decoration: none; font-size: .9rem; }
nav.tabs span { background: var(--accent); border-color: var(--accent); color: var(--bg); font-weight: 600; }
h2 { font-size: 1rem; margin: 24px 0 8px; display: flex; gap: 8px; align-items: baseline; }
h2 .count { font-weight: 400; font-size: .875rem; color: var(--secondary); }
h2 .count a { color: var(--secondary); }
.results { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 12px; }
.result { padding: 10px 12px; border-radius: 10px; background: var(--card); border: 1px solid var(--line); }
.result.pages { border-color: color-mix(in srgb, var(--accent) 45%, var(--line)); }
.result.notes { border-color: color-mix(in srgb, var(--notes) 45%, var(--line)); }
.title { color: var(--accent); font-weight: 600; text-decoration: none; overflow-wrap: anywhere; }
.title:hover { text-decoration: underline; }
.url { color: var(--secondary); font-size: .8125rem; overflow-wrap: anywhere; }
.snippet { margin: 4px 0 0; font-size: .9375rem; overflow-wrap: anywhere; }
mark { background: none; color: var(--hit); font-weight: 600; }
.status { color: var(--secondary); }
.status a, footer a, .pager a { color: var(--accent); }
.pager { display: flex; justify-content: space-between; margin: 24px 0 8px; }
body.start header, body.start footer { border: 0; }
footer { margin-top: 32px; padding-top: 12px; border-top: 1px solid var(--line); color: var(--secondary); font-size: .875rem; }
`;

function pageHTML({ title, theme, body, q, tab, tabs }) {
  const attrs = (theme.theme === 'night' || theme.theme === 'day' ? ` data-theme="${theme.theme}"` : '')
    + (theme.palette && theme.palette !== 'tokyo-night' ? ` data-palette="${esc(theme.palette)}"` : '');
  const tabLinks = q
    ? `<nav class="tabs" aria-label="Categories">${tabs.map((t) => (t === tab
      ? `<span aria-current="page">${TAB_TITLES[t]}</span>`
      : `<a href="/basic?${esc(query({ q, t: t === 'all' ? '' : t }))}">${TAB_TITLES[t]}</a>`)).join('')}</nav>`
    : '';
  return `<!doctype html>
<html lang="en"${attrs}>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="referrer" content="no-referrer">
<title>${esc(title)}</title>
<link rel="icon" href="/_shiori/shiori-small.svg" type="image/svg+xml">
<link rel="stylesheet" href="/_shiori/theme.css">
<link rel="stylesheet" href="/_shiori/palettes.css">
<style>${STYLE}</style>
</head>
<body${q ? '' : ' class="start"'}>
<div class="wrap">
<header>
<a class="brand" href="/basic"><img src="/_shiori/shiori-small.svg" alt="" width="24" height="24">Shiori</a>
<form action="/basic" method="get" role="search">
<input type="search" name="q" value="${esc(q)}" placeholder="Search pages, notes and the web" aria-label="Search" autocapitalize="off" spellcheck="false"${q ? '' : ' autofocus'}>
${tab !== 'all' ? `<input type="hidden" name="t" value="${tab}">` : ''}<button type="submit">Search</button>
</form>
${tabLinks}
</header>
<main>
${body}
</main>
<footer><p>Basic Search, for browsers without JavaScript.</p></footer>
</div>
</body>
</html>
`;
}

/**
 * The answer to `/basic?…`: { status, headers, body }.
 *
 * - `req`: { args (the raw query string), cookie, referer, host }.
 * - `get(path)`: this host's own route (`/search?…`, `/kura/api/…`, `/searx/search?…`) with the browser's cookies,
 *   resolving to { status, body }.
 * - `site`: { kura (whether Kura is set up), signIn ('/auth', the helper's https sign-in, or ''), kuraSignIn (Kura's
 *   own sign-in page, or ''), self (this site's address, for coming back after a sign-in) }.
 */
export async function basic(req, { S, get, site }) {
  const r = request(req.args);
  const headers = { 'Content-Type': 'text/html; charset=utf-8' };
  if (!r.hasQ) {
    const go = carriedOver(req.referer, req.host);
    if (go) return { status: 303, headers: { ...headers, Location: go }, body: '' };
  }
  const theme = S.houseSettings(req.cookie || '');
  const tabs = TABS.filter((t) => t !== 'notes' || site.kura);
  const tab = tabs.includes(r.tab) ? r.tab : 'all';
  if (!r.q) {
    return { status: 200, headers, body: pageHTML({ title: 'Shiori', theme, body: '', q: '', tab, tabs }) };
  }
  const q = r.q;
  const back = `${String(site.self || '/').replace(/\/?$/, '/')}basic?${query({ q, t: tab === 'all' ? '' : tab, p: r.page > 1 ? r.page : '' })}`;
  const wantsWeb = !!S.webQuery(q);
  const parts = [];
  if (tab === 'all') {
    const [pages, notes, web] = await Promise.all([
      fetchJSON(get, histerPath(S, q, ALL_COUNT, '')),
      site.kura ? fetchJSON(get, kuraPath(S, q, ALL_COUNT, 0)) : Promise.resolve(null),
      wantsWeb ? fetchJSON(get, searxPath(S, q, 1)) : Promise.resolve(null),
    ]);
    const section = (kind, reply, rows, total) => {
      if (!reply.ok) return `<section><h2>${HEADINGS[kind]}</h2>${failure(kind, reply.status, site, back)}</section>`;
      if (!rows.length) return kind === 'web' ? `<section><h2>Web</h2><p class="status">${EMPTY.web}</p></section>` : '';
      const more = kind === 'web' ? '' : ` <span class="count"><a href="/basic?${esc(query({ q, t: kind }))}">${countText(total)} ›</a></span>`;
      return `<section><h2>${HEADINGS[kind]}${more}</h2>${resultsHTML(rows, kind, S)}</section>`;
    };
    const pageRows = pages.ok ? histerRows(pages.data).slice(0, ALL_COUNT) : [];
    parts.push(section('pages', pages, pageRows, pages.ok ? Number(pages.data.total) || pageRows.length : 0));
    if (notes) {
      const docs = notes.ok ? kuraRows(S, notes.data).slice(0, ALL_COUNT) : [];
      parts.push(section('notes', notes, docs, notes.ok ? S.kuraDocuments(notes.data).total : 0));
    }
    if (web) parts.push(section('web', web, web.ok ? webRows(web.data) : [], 0));
    if (pages.ok && !pageRows.length && (!notes || (notes.ok && !kuraRows(S, notes.data).length)) && !web) {
      parts.push('<p class="status">Nothing in your pages or notes matches.</p>');
    }
    if (web && web.ok && webRows(web.data).length) {
      parts.push(`<nav class="pager" aria-label="Pages"><span></span><a href="/basic?${esc(query({ q, t: 'web', p: 2 }))}">Next page ›</a></nav>`);
    }
  } else {
    let reply;
    let rows = [];
    let next = '';
    let total = 0;
    if (tab === 'pages') {
      reply = await fetchJSON(get, histerPath(S, q, PAGE_SIZE, r.key));
      if (reply.ok) {
        rows = histerRows(reply.data);
        total = Number(reply.data.total) || 0;
        const key = typeof reply.data.page_key === 'string' ? reply.data.page_key : '';
        if (key && rows.length >= PAGE_SIZE && r.page < MAX_PAGE) next = query({ q, t: 'pages', p: r.page + 1, k: key });
      }
    } else if (tab === 'notes') {
      reply = await fetchJSON(get, kuraPath(S, q, PAGE_SIZE, (r.page - 1) * PAGE_SIZE));
      if (reply.ok) {
        rows = kuraRows(S, reply.data);
        total = S.kuraDocuments(reply.data).total;
        if (r.page * PAGE_SIZE < total && r.page < MAX_PAGE) next = query({ q, t: 'notes', p: r.page + 1 });
      }
    } else if (wantsWeb) {
      reply = await fetchJSON(get, searxPath(S, q, r.page));
      if (reply.ok) {
        rows = webRows(reply.data);
        if (rows.length && r.page < MAX_PAGE) next = query({ q, t: 'web', p: r.page + 1 });
      }
    } else {
      reply = { ok: true };
    }
    const count = tab === 'web' || !reply.ok ? '' : ` <span class="count">${countText(total)}</span>`;
    parts.push(`<section><h2>${HEADINGS[tab]}${count}</h2>`
      + (!reply.ok ? failure(tab, reply.status, site, back) : rows.length ? resultsHTML(rows, tab, S) : `<p class="status">${EMPTY[tab]}</p>`)
      + '</section>');
    // Hister pages by key, not number: Previous is the browser's Back.
    const prev = r.page > 1 && tab !== 'pages' ? `<a href="/basic?${esc(query({ q, t: tab, p: r.page - 1 }))}">‹ Previous page</a>` : '<span></span>';
    if (next || r.page > 1) parts.push(`<nav class="pager" aria-label="Pages">${prev}${next ? `<a href="/basic?${esc(next)}">Next page ›</a>` : ''}</nav>`);
  }
  return { status: 200, headers, body: pageHTML({ title: `${q} · Shiori`, theme, body: parts.join('\n'), q, tab, tabs }) };
}
