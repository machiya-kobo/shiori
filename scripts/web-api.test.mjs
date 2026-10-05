// Tests for web/app/api.js, the web app's server calls, against a fake
// server: which vaults are shared comes from Kura, and another vault's note
// reaches Hister only while Kura, asked afresh, still shares it. Also how
// the search page (patches/shiori/search.js) and the web app (web/app/app.js)
// are wired to it: those need a browser, so their source is checked.
// Run: node --test scripts/*.test.mjs

import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const read = (rel) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8');

// search-core in its own context, as the page has it on globalThis.
const core = { URL, URLSearchParams };
core.globalThis = core;
vm.createContext(core);
vm.runInContext(read('../patches/shiori/search-core.js'), core);
globalThis.ShioriSearch = core.ShioriSearch;
const S = core.ShioriSearch;

// The fake server: `vaults` is Kura's answer (null: Kura is down); every
// request is recorded.
const server = { vaults: null, calls: [], save: { status: 202 } };
globalThis.fetch = async (url, init = {}) => {
  server.calls.push({ url, init });
  // The small-web gateway's save: a status, or `down` (no answer).
  if (url === '/smallweb/api/save') {
    if (server.save.down) throw new TypeError('Load failed');
    const { status } = server.save;
    const body = status === 202 ? { queued: true, url: JSON.parse(init.body).url } : { error: 'nope' };
    return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
  }
  if (url === '/kura/api/vaults') {
    if (!server.vaults) throw new TypeError('Load failed');
    return new Response(JSON.stringify({ vaults: server.vaults }));
  }
  if (url === '/api/delete') return new Response(JSON.stringify({ matched: 1 }));
  return new Response('{}');
};
const api = await import('../web/app/api.js');

const WORK = 'https://kura.example/v/work/n/Plan';
const vaults = (workPrivate) => [
  { name: 'personal', default: true, private: false },
  { name: 'work', default: false, private: workPrivate },
];
const sentToHister = () => server.calls.filter((c) => /^\/api\/(history|label|delete)$/.test(c.url));
function reset(list) {
  server.vaults = list;
  server.calls = [];
}

test("the web app's vaults come from Kura and say which are shared; a failure shares none", async () => {
  reset(vaults(false));
  assert.equal((await api.kuraVaults()).length, 2);
  assert.equal(S.isPrivateNote(WORK), false);
  reset(null);
  assert.equal((await api.kuraVaults()).length, 0);
  assert.equal(S.isPrivateNote(WORK), true);
});

test('a vault made private after the app read it: nothing about its note reaches Hister', async () => {
  reset(vaults(false));
  await api.kuraVaults();
  assert.equal(S.isPrivateNote(WORK), false, 'shared, as cached');
  reset(vaults(true));
  await api.recordOpened(WORK, 'Plan', 'plan');
  await assert.rejects(api.setLabel(WORK, 'x'));
  await assert.rejects(api.deletePage(WORK));
  await assert.rejects(api.forgetOpened(WORK, 'plan'));
  assert.deepEqual(sentToHister(), []);
  assert.equal(server.calls.filter((c) => c.url === '/kura/api/vaults').length, 4, 'Kura asked before each');
});

test("Kura out of reach: another vault's note is private; while Kura shares it, it goes", async () => {
  reset(vaults(false));
  await api.kuraVaults();
  reset(null);
  await api.recordOpened(WORK, 'Plan', 'plan');
  assert.deepEqual(sentToHister(), []);
  // Shared again: the label asks afresh (and keeps the answer); an open,
  // already refused by the copy, then goes too.
  reset(vaults(false));
  await api.setLabel(WORK, 'x');
  await api.recordOpened(WORK, 'Plan', 'plan');
  assert.deepEqual(sentToHister().map((c) => c.url), ['/api/label', '/api/history']);
});

test("the default vault's notes and pages never wait on Kura", async () => {
  reset(null);
  await api.recordOpened('https://kura.example/n/Plan', 'Plan', 'plan');
  await api.setLabel('https://example.com/', 'x');
  assert.equal(server.calls.some((c) => c.url === '/kura/api/vaults'), false);
  assert.equal(sentToHister().length, 2);
});

test('a file from the folders Hister watches is never recorded, labelled or deleted', async () => {
  reset(vaults(false));
  const FILE = 'file:///home/u/notes/pi.md';
  await api.recordOpened(FILE, 'Pi', 'pi');
  await assert.rejects(api.setLabel(FILE, 'x'));
  await assert.rejects(api.deletePage(FILE));
  assert.deepEqual(sentToHister(), []);
  // The search page's own open: refused by address too.
  assert.match(read('../patches/shiori/search.js'), /S\.isPrivateNote\(url\) \|\| S\.isLocalFile\(url\)\) return;/);
});

test('the search page and the web app read the vaults through S.loadVaults, and ask afresh before Hister', () => {
  const page = read('../patches/shiori/search.js');
  assert.match(page, /const vaultsReady = \(\) => S\.loadVaults\(readVaultsNow\)/);
  assert.match(page, /S\.isPrivateNoteNow\(url, readVaultsNow\)\.then/);
  assert.doesNotMatch(page, /S\.useVaults\(/, 'only through S.loadVaults');
  const app = read('../web/app/app.js');
  assert.match(app, /const loadVaults = \(\) => \{[\s\S]*?api\.kuraVaults\(\)/);
  assert.match(app, /Promise\.all\(\[[^\]]*loadVaults\(\)/, 'read at start');
  assert.doesNotMatch(app, /S\.useVaults\(/, 'only through api.kuraVaults');
});

test("the web app's look sets the theme-color metas from S.themeColorMetas", () => {
  const app = read('../web/app/app.js');
  const look = app.slice(app.indexOf('function applyLook()'), app.indexOf('function recordSearch('));
  assert.match(look, /S\.themeColorMetas\(theme, palette\)/);
  assert.match(look, /meta\[name="theme-color"\]/);
});

test("the web app's type is rem-sized, so Text Size scales it in Safari too", () => {
  const css = read('../web/app/app.css').replace(/\/\*[\s\S]*?\*\//g, '');
  assert.doesNotMatch(css, /font:\s*-apple-system-/, 'a system font keyword sets an absolute size in WebKit');
  const app = read('../web/app/app.js');
  // This device's own size (Use This Device's Size) over the shared one.
  assert.match(app, /const size = deviceTextSize\(\) \|\| settings\.textSize;/);
  assert.match(app, /style\.fontSize = `\$\{Math\.round\(100 \* \(TEXT_SCALE\[size\] \|\| systemTextScale\(\)\)\)\}%`/);
});

test("Kura's own sign-in: read with where you stand, never throwing (the Machiya row)", async () => {
  const real = globalThis.fetch;
  let answer = () => new Response(JSON.stringify({ prefs: { theme: 'day' } }));
  globalThis.fetch = async () => answer();
  try {
    assert.equal((await api.kuraPrefs()).status, 200);
    answer = () => new Response('{"error":"sign in first"}', { status: 401 });
    assert.equal((await api.kuraPrefs()).status, 401);
    answer = () => { throw new TypeError('Load failed'); };
    assert.equal((await api.kuraPrefs()).status, 0);
  } finally {
    globalThis.fetch = real;
  }
});

test("the account's preferences: /machiya/api/prefs on this host, its revision as the ETag, never throwing", async () => {
  const real = globalThis.fetch;
  const sent = [];
  let answer = () => new Response(JSON.stringify({ v: 1, rev: 7, prefs: { theme: 'day' }, updated: { theme: 100 } }));
  globalThis.fetch = async (url, init = {}) => {
    sent.push({ url, init });
    return answer();
  };
  try {
    assert.deepEqual(JSON.parse(JSON.stringify(await api.accountPrefs())), { status: 200, snapshot: { rev: 7, prefs: { theme: 'day' }, updated: { theme: 100 } } });
    assert.equal(sent[0].url, '/machiya/api/prefs');
    assert.equal(sent[0].init.credentials, 'same-origin');
    assert.equal(sent[0].init.headers['If-None-Match'], undefined);
    sent.length = 0;
    answer = () => new Response(null, { status: 304 });
    assert.equal((await api.accountPrefs(7)).status, 304);
    assert.equal(sent[0].init.headers['If-None-Match'], '"7"');
    answer = () => new Response('{"error":"sign in"}', { status: 401 });
    assert.equal((await api.accountPrefs()).status, 401);
    answer = () => { throw new TypeError('Load failed'); };
    assert.equal((await api.accountPrefs()).status, 0);
    sent.length = 0;
    answer = () => new Response(JSON.stringify({ v: 1, rev: 8, prefs: { theme: 'night' }, updated: { theme: 200 } }));
    assert.equal((await api.putAccountPrefs({ theme: 'night', palette: null })).status, 200);
    assert.equal(sent[0].init.method, 'PUT');
    assert.deepEqual(JSON.parse(sent[0].init.body), { prefs: { theme: 'night', palette: null } });
  } finally {
    globalThis.fetch = real;
  }
});

test('the web app follows the account: one contact on load, on return and after a change here', () => {
  const app = read('../web/app/app.js');
  assert.match(app, /void contactAccount\(\);/, 'on load, after the first draw');
  assert.match(app, /Date\.now\(\) - prefsAt >= 30_000\) void contactAccount\(\)/, 'on return after 30 s');
  assert.match(app, /if \(!fromAccount && \(\['theme', 'palette', 'textSize', 'pills'\]\.includes\(key\) \|\| Object\.hasOwn\(S\.prefsShioriKeys\(\), key\)\)\) soonContact\(\);/);
  assert.match(app, /S\.prefsSync\(\{ mine: now, seen, answer \}\)/);
  assert.doesNotMatch(app, /putKuraPrefs|kura\/api\/prefs'.*PUT/, 'Kura is no longer written');
});

test("the web app's Settings say whether Kura knows you, and All says when it asks", () => {
  const app = read('../web/app/app.js');
  const row = app.slice(app.indexOf('function machiyaRow()'), app.indexOf('/** Settings → Export & Feed'));
  assert.match(row, /200: \['Signed in'/);
  assert.match(row, /401: \['Not signed in', link\(signIn, 'Sign In'\)\]/);
  assert.match(row, /loadKuraStatus\(\)\.then/, 'asked afresh');
  assert.match(app, /group\('Notes', \[[^\n]*machiyaRow\(\)\]/);
  // All: a 401 from Kura is the Notes pill's notice, not silence.
  assert.match(app, /error\.status === 401 \? \{ signIn: true/);
  assert.match(app, /if \(notes && notes\.signIn\) container\.append\(h\('section', \{ class: 'list-section' \}, signInStatus\(/);
  assert.match(app, /if \(error\.status === 401\) notesWantSignIn = true;/);
});

test("the web app marks web results you already have, with the search page's lookup", () => {
  const app = read('../web/app/app.js');
  assert.match(app, /markSaved\(list, shown\.map\(\(r\) => r\.url\)\);/);
  const fn = app.slice(app.indexOf('async function markSaved('), app.indexOf('// --- Preview -----'));
  // In batches short enough to send (a single lookup got 414 from nginx).
  assert.match(fn, /S\.urlLookupQueries\(urls\)/);
  assert.match(fn, /S\.savedLabels\(replies\.flatMap/);
  assert.match(read('../patches/shiori/search.js'), /const lookups = S\.urlLookupQueries\(cards\.map/);
});

test("the web app's Settings are a tab on a phone, with no title row on the tabs' own views", () => {
  const app = read('../web/app/app.js');
  const css = read('../web/app/app.css');
  assert.doesNotMatch(read('../web/app/index.html'), /settings-button/);
  assert.match(app.slice(app.indexOf('function tabs('), app.indexOf('// --- Render')), /tab\('settings', 'Settings', 'gear', 'settings'\)/);
  assert.match(app, /function viewSettings\(\) \{\n[^\n]*\n  setTitle\('Settings'\);/);
  // Hidden at every width, not only beside the sidebar.
  const rule = '#list-column > .bar:has(#title.sidebar-says):has(#back[hidden]) { display: none; }';
  assert.ok(css.includes(rule));
  assert.ok(css.lastIndexOf('@media', css.indexOf(rule)) < css.lastIndexOf('}', css.indexOf(rule)), 'not inside a media query');
});

test("the web app's sidebar has no empty heading", () => {
  const app = read('../web/app/app.js');
  assert.doesNotMatch(app, /h\('h2', \{\}, ''\)/);
  assert.match(app, /statusURL \? h\('div', \{ class: 'sidebar-rule', role: 'separator' \}\) : null/);
});

test("the web app's Obsidian Vault field takes a name, not an address", () => {
  const app = read('../web/app/app.js');
  assert.match(app, /text\('obsidianVault', 'Obsidian Vault', 'Your vault’s name', 'text'\)/);
  assert.match(app, /const text = \(key, title, placeholder, type = 'url'\) => \{\s*const input = h\('input', \{ type,/);
});

test("the web app's preview empties when the list beside it no longer has its page", () => {
  const app = read('../web/app/app.js');
  const fn = app.slice(app.indexOf('function dropStaleSelection('), app.indexOf('function status('));
  assert.match(fn, /if \(!wide\(\) \|\| !selected \|\| !container\.isConnected\) return;/);
  assert.match(fn, /r\._doc && r\._doc\.url === selected\.url/);
  assert.match(fn, /selected = null;/);
  // Every list calls it once it's drawn: Hister's and Kura's, All, Opened, the web, the small web.
  assert.equal((app.match(/dropStaleSelection\(container\);/g) || []).length, 5);
});

test("a note's address never goes to Hister's extractors (the ⋯ menu's Show As)", async () => {
  for (const url of [WORK, 'https://kura.example//v/work/n/Plan', 'https://kura.example/%76/work/n/Plan', 'not a url']) {
    reset(vaults(false));
    assert.deepEqual(await api.extractors(url), [], url);
    assert.deepEqual(server.calls, [], `nothing sent for ${url}`);
  }
  reset(null);
  await api.extractors('https://example.com/page');
  assert.deepEqual(server.calls.map((c) => c.url), ['/api/extractors?url=https%3A%2F%2Fexample.com%2Fpage'], 'a web page still asks');
});

test("the web app's ⋯ menu asks for Show As only for a web page, and places it without Delete", () => {
  const app = read('../web/app/app.js');
  const menu = app.slice(app.indexOf('function pageMenu('), app.indexOf('// --- Dialogs'));
  assert.ok(menu.length > 100);
  assert.match(menu, /if \(isNoteDoc\(doc, n\)\) return;\s*try \{\s*const names = await api\.extractors\(doc\.url\)/, 'notes return before asking');
  assert.doesNotMatch(menu, /querySelector\('\.danger'\)/, 'Show As has its own place, Delete or not');
  assert.match(app, /function isNoteDoc\(doc, n = note\(doc\)\) \{\s*return !!n \|\| doc\.label === 'vault' \|\| S\.noteVault\(doc\.url\) !== null \|\| S\.isNoteURL\(/);
});

test("Hister's preview is never asked for another vault's note, shared or not", async () => {
  for (const url of [WORK, 'https://kura.example//v/team/n/Plan', 'not a url']) {
    reset(vaults(false));
    await assert.rejects(api.preview(url), url);
    assert.deepEqual(server.calls, [], `nothing sent for ${url}`);
  }
  reset(null);
  await api.preview('https://example.com/page');
  await api.preview('https://kura.example/n/Plan');
  assert.equal(server.calls.length, 2, "a page and the default vault's note still ask");
});

test("the web app's page view, given only a note's address, previews it as a note", () => {
  const app = read('../web/app/app.js');
  assert.match(app, /\{ url, title: '', domain: hostOf\(url\), \.\.\.\(isNoteDoc\(\{ url \}\) \? \{ label: 'vault' \} : \{\}\) \}/);
});

// --- Add Page and the share target (the small-web gateway's POST /api/save) ---

const KURA = 'https://kura.example/';
const KONBINI = 'https://konbini.example/';
// As the app's isNoteDoc reads a bare address.
const isNote = (url) => S.noteVault(url) !== null || S.isNoteURL(url, KURA, KONBINI);
const check = (text) => api.checkPageURL(text, { isNote });

test('Add Page takes http, https, gemini and gopher addresses, and adds https:// to a bare one', () => {
  for (const [text, url] of [
    ['https://example.com/a?b=1#c', 'https://example.com/a?b=1#c'],
    ['  http://example.com/  ', 'http://example.com/'],
    ['gemini://geminiprotocol.net/docs/', 'gemini://geminiprotocol.net/docs/'],
    ['gopher://gopher.example/1/phlog', 'gopher://gopher.example/1/phlog'],
    ['example.com/article', 'https://example.com/article'],
  ]) assert.deepEqual(check(text), { url }, text);
  for (const text of ['', '   ', 'ftp://example.com/f', 'file:///etc/passwd', 'javascript:alert(1)', 'data:text/html,x', 'mailto:a@example.com', 'two words', 'gemini:nohost', 'https://']) {
    assert.ok(check(text).error, `refused: ${JSON.stringify(text)}`);
  }
});

test('Add Page refuses a user name or password in the address', () => {
  for (const text of ['https://user@example.com/', 'https://user:pw@example.com/', 'gemini://me@example.org/', 'https://:pw@example.com/']) {
    assert.match(check(text).error, /user name and password/, text);
  }
});

test("Add Page never takes a note: a private vault's /v/ path in any form, on any host, or any Kura note", () => {
  for (const text of [
    'https://kura.example/v/work/n/Plan',
    'https://anywhere.example/v/work/n/Plan',
    'https://anywhere.example/v/work/',
    'https://anywhere.example/v/work',
    'https://anywhere.example//v/work/n/Plan',
    'https://anywhere.example///v/work/x',
    'https://anywhere.example/%76/work/n/Plan',
    'https://anywhere.example/%2fv/work/n/Plan',
    'https://anywhere.example/a/../v/work/n/Plan',
    'https://anywhere.example/a/%2e%2e/v/work/n/Plan',
    'https://anywhere.example/v/%2577ork/n/Plan',
    'gemini://capsule.example/v/work/n/Plan',
    'gopher://hole.example//v/work/0/Plan',
    'kura.example/v/work/n/Plan',
    // The default vault's notes and Konbini's cards, by their homes or hosts.
    'https://kura.example/n/Plan',
    'https://konbini.example/p/plan',
    'https://niwa.other.example/n/Plan',
    'https://kura.other.example/n/Plan',
  ]) assert.match(check(text).error || '', /note/, text);
  // A /v/ that doesn't start the path is just a page.
  assert.deepEqual(check('https://example.com/docs/v/work/'), { url: 'https://example.com/docs/v/work/' });
  assert.deepEqual(check('https://example.com/vv/work/'), { url: 'https://example.com/vv/work/' });
});

test("the share target's url, title and text: the url, else the first http(s) link in the text", () => {
  const shared = (qs) => api.sharedPage(new URLSearchParams(qs));
  assert.equal(shared(''), null, 'not a share');
  assert.equal(shared('q=lantern'), null, 'not a share');
  assert.deepEqual(shared('url=https%3A%2F%2Fexample.com%2Fa&title=A%20page&text=ignored'), { url: 'https://example.com/a', title: 'A page' });
  assert.deepEqual(shared('title=Lanterns&text=Read%20this%3A%20https%3A%2F%2Fexample.com%2Flantern%3Fx%3D1.%20So%20good'), { url: 'https://example.com/lantern?x=1', title: 'Lanterns' });
  assert.deepEqual(shared('url=&text=(see%20https%3A%2F%2Fen.wikipedia.org%2Fwiki%2FLantern_(disambiguation))'), { url: 'https://en.wikipedia.org/wiki/Lantern_(disambiguation)', title: '' });
  assert.deepEqual(shared('text=%22http%3A%2F%2Fexample.com%2Fq%22!'), { url: 'http://example.com/q', title: '' });
  assert.deepEqual(shared('text=gemini%3A%2F%2Fcapsule.example%2F%20only'), { url: '', title: '' }, 'only http(s) is looked for in text');
  assert.deepEqual(shared('text=nothing%20here&title=%20T%20'), { url: '', title: 'T' });
  assert.equal(shared(`title=${'x'.repeat(400)}`).title.length, 300);
});

test("Add Page's save: the body, and what each answer says", async () => {
  reset(null);
  server.save = { status: 202 };
  const ok = await api.savePage('gemini://capsule.example/', 'A capsule');
  assert.deepEqual(ok, { ok: true, message: 'Saving… it’ll be in your pages shortly.' });
  assert.doesNotMatch(ok.message, /^Saved/);
  const [call] = server.calls;
  assert.equal(call.url, '/smallweb/api/save');
  assert.equal(call.init.method, 'POST');
  assert.equal(call.init.credentials, 'same-origin');
  assert.equal(call.init.headers['Content-Type'], 'application/json');
  assert.equal('Origin' in call.init.headers, false, 'same-origin: no Origin of its own');
  assert.deepEqual(JSON.parse(call.init.body), { url: 'gemini://capsule.example/', title: 'A capsule' });
  reset(null);
  await api.savePage('https://example.com/');
  assert.deepEqual(JSON.parse(server.calls[0].init.body), { url: 'https://example.com/' }, 'no title, none sent');
  const said = async (save) => {
    server.save = save;
    const reply = await api.savePage('https://example.com/');
    assert.equal(reply.ok, false);
    return reply.message;
  };
  assert.match(await said({ status: 400 }), /can’t save that address/);
  assert.match(await said({ status: 403 }), /doesn’t take saves from here/);
  assert.match(await said({ status: 429 }), /20 pages waiting/);
  assert.match(await said({ status: 500 }), /answered 500/);
  assert.match(await said({ down: true }), /didn’t answer/);
  server.save = { status: 202 };
});

test("the web app's tab bar is the rooms' shared one: edge to edge, its tabs sharing the width", () => {
  const css = read('../web/app/app.css');
  // A rule of its own at the top level (the wide layout's `#tabs { display: none }` is indented).
  const block = (sel) => { const at = css.indexOf(`\n${sel} {`); return css.slice(at, css.indexOf('}', at)); };
  const bar = block('#tabs');
  // Centred and sized to its content, five tabs ran off a phone.
  assert.doesNotMatch(bar, /translateX/);
  assert.match(bar, /left: calc\(8px \+ env\(safe-area-inset-left\)\); right: calc\(8px \+ env\(safe-area-inset-right\)\)/);
  assert.match(block('#tabs button'), /flex: 1 1 0; min-width: 0;/);
  // The rooms' see-through glass: the card colour at 70%, blurred and saturated.
  assert.match(bar, /background: color-mix\(in srgb, var\(--card\) 70%, transparent\)/);
  assert.match(bar, /-webkit-backdrop-filter: blur\(20px\) saturate\(180%\); backdrop-filter: blur\(20px\) saturate\(180%\)/);
  assert.match(css, /#tabs button > span \{[^}]*text-overflow: ellipsis/);
});

test("every phone search field has the rooms' X and submit magnifier", () => {
  const app = read('../web/app/app.js');
  const appCSS = read('../web/app/app.css');
  const html = read('../patches/shiori/search.html');
  const pageCSS = read('../patches/shiori/search.css');
  // The web app's main field and a list's "Search in" field.
  assert.match(app, /h\('div', \{ class: 'searchfield' \}, searchInput, ghost, \.\.\.searchButtons\)/);
  assert.match(app, /h\('div', \{ class: 'searchfield' \}, field, \.\.\.fieldButtons\)/);
  assert.match(appCSS, /input:placeholder-shown ~ \.field-clear \{ display: none; \}/);
  assert.match(appCSS, /@media \(max-width: 759px\) \{\n  \.field-go \{ display: grid; \}/);
  // The search page: its X (line glyph) and a submit magnifier, phones only.
  assert.match(html, /<button id="go" class="field-button" type="submit"/);
  assert.doesNotMatch(html, /title="Clear search">×</);
  assert.match(pageCSS, /#go \{ display: none; \}\n@media \(max-width: 759px\) \{\n  #go \{ display: grid; \}/);
});

test('installed on an iPhone, the web app starts 24px under the status bar, as the rooms do', () => {
  const appCSS = read('../web/app/app.css');
  // Installed on an iPhone only: safe area + 24px.
  assert.match(appCSS, /@supports \(-webkit-touch-callout: none\) \{\n  @media \(display-mode: standalone\) and \(max-width: 759px\) \{[^}]*padding-top: calc\(24px \+ env\(safe-area-inset-top\)\);/);
});

test("the web app's modules parse (the other tests read them as text)", () => {
  const dir = mkdtempSync(join(tmpdir(), 'shiori-parse-'));
  try {
    for (const name of ['app.js', 'api.js', 'sw.js']) {
      const copy = join(dir, name.replace(/\.js$/, '.mjs'));
      writeFileSync(copy, read(`../web/app/${name}`));
      const r = spawnSync(process.execPath, ['--check', copy], { encoding: 'utf8' });
      assert.equal(r.status, 0, `${name}: ${r.stderr}`);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('the web is searched only on purpose: Return, a recent search, Did you mean, the Web pill (each web search counts)', () => {
  const app = read('../web/app/app.js');
  // Typing searches with no w; Return (record) adds w=1.
  assert.match(app, /go\('search', \{ q, s, \.\.\.\(record \? \{ w: '1' \} : \{\}\) \}, \{ replace: view === 'search' \}\);/);
  assert.match(app, /item\(text, 'search', \{ q: text, s: params\.get\('s'\) \|\| 'all', w: '1' \}/);
  assert.match(app, /go\('search', \{ q: fix, s: scope, w: '1' \}\)/);
  assert.match(app, /keep\(\{ s, \.\.\.\(s === 'web' \? \{ w: '1' \} : \{\}\) \}\)/);
  // All and Web ask the web only with it.
  assert.match(app, /if \(!settings\.webResults \|\| !web\) \{/);
  assert.match(app, /if \(web\) webList\(\$\('list'\), q\);/);
  // Respellings come from the autocompleter, never a web search.
  assert.doesNotMatch(app, /api\.web\([^)]*\)\.then\(\(d\) => d\.suggestions/);
});

test("Settings opens on who's signed in, read without a trip to the sign-in", () => {
  const app = read('../web/app/app.js');
  const api = read('../web/app/api.js');
  assert.match(app, /accountGroup\(group\),\n\s+\/\/ Shared first[^\n]*\n\s+group\('Shared'/);
  assert.match(app, /const account = S\.histerAccount\(status, json\);/);
  const fn = api.slice(api.indexOf('export async function profile('), api.indexOf('export async function profile(') + 900);
  assert.doesNotMatch(fn, /request\(/);
  assert.match(fn, /credentials: 'same-origin'/);
  assert.match(read('../patches/shiori/search.js'), /const body = \[\.\.\.accountGroup\(\)\];/);
});
