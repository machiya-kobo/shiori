// Tests for web/app/api.js, the web app's server calls, against a fake
// server: which vaults are shared comes from Kura, and another vault's note
// reaches Hister only while Kura, asked afresh, still shares it. Also how
// the search page (patches/shiori/search.js) and the web app (web/app/app.js)
// are wired to it: those need a browser, so their source is checked.
// Run: node --test scripts/*.test.mjs

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
const server = { vaults: null, calls: [] };
globalThis.fetch = async (url, init = {}) => {
  server.calls.push({ url, init });
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
  assert.match(look, /S\.themeColorMetas\(theme\)/);
  assert.match(look, /meta\[name="theme-color"\]/);
});

test("the web app's type is rem-sized, so Text Size scales it in Safari too", () => {
  const css = read('../web/app/app.css').replace(/\/\*[\s\S]*?\*\//g, '');
  assert.doesNotMatch(css, /font:\s*-apple-system-/, 'a system font keyword sets an absolute size in WebKit');
  const app = read('../web/app/app.js');
  assert.match(app, /style\.fontSize = `\$\{Math\.round\(100 \* \(TEXT_SCALE\[settings\.textSize\] \|\| systemTextScale\(\)\)\)\}%`/);
});

test("Kura's preferences: read with where you stand, written as the rooms write them, never throwing", async () => {
  const real = globalThis.fetch;
  const sent = [];
  let answer = () => new Response(JSON.stringify({ prefs: { theme: 'day', text_size: 'large' } }));
  globalThis.fetch = async (url, init = {}) => {
    sent.push({ url, init });
    return answer();
  };
  try {
    assert.deepEqual(await api.kuraPrefs(), { status: 200, prefs: { theme: 'day', text_size: 'large' } });
    answer = () => new Response('{"error":"sign in first"}', { status: 401 });
    assert.deepEqual(await api.kuraPrefs(), { status: 401, prefs: {} });
    answer = () => new Response('', { status: 404 });
    assert.equal((await api.kuraPrefs()).status, 404);
    answer = () => { throw new TypeError('Load failed'); };
    assert.equal((await api.kuraPrefs()).status, 0);
    assert.equal(await api.putKuraPrefs({ theme: 'night', text_size: 'standard' }), false, 'silent');
    answer = () => new Response(JSON.stringify({ prefs: {} }));
    sent.length = 0;
    assert.equal(await api.putKuraPrefs({ theme: 'night', text_size: 'standard' }), true);
    const [put] = sent;
    assert.equal(put.url, '/kura/api/prefs');
    assert.equal(put.init.method, 'PUT');
    assert.equal(put.init.credentials, 'same-origin');
    assert.equal(put.init.headers['Content-Type'], 'application/json');
    assert.deepEqual(JSON.parse(put.init.body), { prefs: { theme: 'night', text_size: 'standard' } });
  } finally {
    globalThis.fetch = real;
  }
});

test('the web app reads Kura’s preferences on launch and writes them only when signed in', () => {
  const app = read('../web/app/app.js');
  assert.match(app, /Promise\.all\(\[[^\]]*loadKuraAccount\(\)/);
  assert.match(app, /if \(!fromKura && kuraAccount\.status === 200\) pushPrefs\(\);/);
  assert.match(app, /if \(status !== 200 \|\| lookChangedHere\) return;/);
  assert.match(app, /\['system', 'night', 'day'\]\.includes\(theme\)/, 'only known values');
});

test("the web app's Settings say whether Kura knows you, and All says when it asks", () => {
  const app = read('../web/app/app.js');
  const row = app.slice(app.indexOf('function machiyaRow()'), app.indexOf('/** Settings → Export & Feed'));
  assert.match(row, /200: \['Signed in'/);
  assert.match(row, /401: \['Not signed in', link\(signIn, 'Sign In'\)\]/);
  assert.match(row, /loadKuraAccount\(\)\.then/, 'asked afresh');
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
  assert.match(fn, /S\.urlLookupQuery\(urls\)/);
  assert.match(fn, /S\.savedLabels\(known\.documents\)/);
  assert.match(read('../patches/shiori/search.js'), /const labels = S\.savedLabels\(known\.documents\);/);
});

test("the web app's Settings hide their own gear (Back is the way out)", () => {
  const app = read('../web/app/app.js');
  assert.match(app.slice(app.indexOf('function setTitle('), app.indexOf('function viewLibrary(')), /\$\('settings-button'\)\.hidden = text === 'Settings';/);
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
