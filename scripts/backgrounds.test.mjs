// Backgrounds (patches/shiori/backgrounds.js, bg.js from annai): the scene list, the Settings choices and the
// previews agree; Off starts nothing (no canvas, no timers, bg.js not even loaded); a scene loads bg.js once; the
// sheet previews and only Save keeps; the signs say only Shiori's own words. Run: node --test scripts/*.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import vm from 'node:vm';

const read = (p) => readFileSync(new URL(p, import.meta.url), 'utf8');
const BG_JS = read('../patches/shiori/bg.js');
const CONTROLLER = read('../patches/shiori/backgrounds.js');
const CSS = read('../patches/shiori/backgrounds.css');

/** bg.js's own scene list, from running it with only a window. */
function engineScenes() {
  const window = {};
  vm.runInNewContext(BG_JS, { window, document: {}, matchMedia: () => ({ matches: false }) });
  return window.annaiBg.scenes;
}

// ---- a little DOM: enough of one for backgrounds.js -------------------------------------------------------------
class El {
  constructor(tag, doc) {
    Object.assign(this, { tagName: tag.toUpperCase(), doc, children: [], parent: null, attrs: {}, style: {}, listeners: {} });
    this.id = '';
    this.className = '';
    this.hidden = false;
    this.textContent = '';
    this.classList = {
      add: (c) => (this.className = [...new Set([...this.className.split(' ').filter(Boolean), c])].join(' ')),
      remove: (c) => (this.className = this.className.split(' ').filter((x) => x && x !== c).join(' ')),
      contains: (c) => this.className.split(' ').includes(c),
      toggle: (c, on) => ((on ?? !this.classList.contains(c)) ? this.classList.add(c) : this.classList.remove(c), on),
    };
  }
  setAttribute(k, v) { this.attrs[k] = String(v); }
  getAttribute(k) { return this.attrs[k] ?? null; }
  removeAttribute(k) { delete this.attrs[k]; }
  addEventListener(type, fn) { (this.listeners[type] ||= []).push(fn); }
  append(...nodes) { for (const n of nodes) { n.remove?.(); n.parent = this; this.children.push(n); } }
  prepend(...nodes) { for (const n of nodes.reverse()) { n.remove?.(); n.parent = this; this.children.unshift(n); } }
  remove() { if (this.parent) this.parent.children = this.parent.children.filter((c) => c !== this); this.parent = null; }
  get options() { return this.all().filter((e) => e.tagName === 'OPTION'); }
  all() { return this.children.flatMap((c) => [c, ...c.all()]); }
  querySelector(sel) { return this.querySelectorAll(sel)[0] || null; }
  querySelectorAll(sel) {
    // '#id .cls', 'body > .a, body > .b', '.cls'
    return sel.split(',').flatMap((one) => {
      const parts = one.trim().replace(/\s*>\s*/g, ' ').split(/\s+/);
      const last = parts.pop();
      return this.all().filter((e) => match(e, last));
    });
  }
  focus() {}
  click() { (this.listeners.click || []).forEach((f) => f({ stopPropagation() {}, preventDefault() {} })); }
}
const match = (e, sel) => (sel.startsWith('#') ? e.id === sel.slice(1) : sel.startsWith('.') ? e.classList.contains(sel.slice(1)) : e.tagName === sel.toUpperCase());

function page({ stored = null, src = 'https://shiori.example/_shiori/backgrounds.js?v=abc' } = {}) {
  const counts = { timeouts: 0, intervals: 0, frames: 0 };
  const local = new Map(stored ? [['shioriBackground', JSON.stringify(stored)]] : []);
  const doc = {
    hidden: false,
    listeners: {},
    currentScript: { src },
    createElement: (tag) => new El(tag, doc),
    addEventListener(type, fn) { (this.listeners[type] ||= []).push(fn); },
    getElementById: (id) => [doc.documentElement, ...doc.documentElement.all()].find((e) => e.id === id) || null,
    querySelector: (sel) => doc.documentElement.querySelector(sel),
    querySelectorAll: (sel) => doc.documentElement.querySelectorAll(sel),
  };
  doc.documentElement = new El('html', doc);
  doc.head = new El('head', doc);
  doc.body = new El('body', doc);
  doc.documentElement.append(doc.head, doc.body);
  const window = {
    document: doc,
    location: { href: 'https://shiori.example/' },
    localStorage: { getItem: (k) => local.get(k) ?? null, setItem: (k, v) => local.set(k, String(v)), removeItem: (k) => local.delete(k) },
    // No IndexedDB here: the stored picture reads as none.
    indexedDB: { open() { const q = {}; setImmediate(() => q.onerror && q.onerror()); return q; } },
    matchMedia: () => ({ matches: false }),
    setTimeout: (...a) => (counts.timeouts++, setTimeout(...a)),
    setInterval: () => (counts.intervals++, 0),
    requestAnimationFrame: () => (counts.frames++, 0),
    URL, Blob, Promise, JSON, Math, Set, Map, Object, String, Array, Error,
  };
  window.window = window;
  vm.runInNewContext(CONTROLLER, window);
  return { window, doc, local, counts, B: window.ShioriBackgrounds };
}
const tick = () => new Promise((ok) => setImmediate(ok));
// Objects made inside the page's context, compared as plain data.
const plain = (x) => JSON.parse(JSON.stringify(x));

test("the scene list is bg.js's, every scene has its preview, and there are no others", () => {
  const ids = page().B.SCENES.map(([id]) => id);
  assert.deepEqual(plain([...ids].sort()), plain([...engineScenes()].sort()));
  const files = readdirSync(new URL('../assets/backgrounds/', import.meta.url)).sort();
  assert.deepEqual(files, plain(ids.map((id) => `bg-${id}.jpg`).sort()));
  for (const f of files) {
    const bytes = readFileSync(new URL(`../assets/backgrounds/${f}`, import.meta.url));
    assert.ok(bytes[0] === 0xff && bytes[1] === 0xd8 && bytes.length < 20000, `${f}: a small JPEG`);
  }
});

test('Settings offers Off, every scene by group, and Your Picture or Video', () => {
  const { B } = page();
  const rows = B.rows({ row: (label, control) => Object.assign(new El('div', null), { label, control }), redraw() {} });
  const select = rows[0].control;
  assert.equal(rows[0].label, 'Background');
  assert.deepEqual(plain(select.options.map((o) => o.value)), ['off', ...B.SCENES.map(([id]) => id), 'custom']);
  const groups = select.children.filter((c) => c.tagName === 'OPTGROUP').map((g) => g.label);
  assert.deepEqual(plain(groups), ['Japan', 'Asia', 'Americas', 'Films and Games', 'Yours']);
  assert.equal(select.value, 'off');
  // Off: no preview and no Rain row, only the picture's.
  assert.deepEqual(plain(rows.map((r) => r.label).filter(Boolean)), ['Background', 'Your Picture or Video']);
});

test('Off starts nothing: no canvas, no timers, bg.js not loaded', async () => {
  for (const stored of [null, { scene: 'off', rain: true }, { scene: 'nowhere', rain: true }]) {
    const { B, doc, counts } = page({ stored });
    B.init({ words: () => ['All', 'Pages'] });
    await tick();
    assert.deepEqual(doc.head.children, [], 'no script added');
    assert.deepEqual(doc.body.children, [], 'nothing in the page');
    assert.equal(doc.documentElement.className, '');
    assert.deepEqual(counts, { timeouts: 0, intervals: 0, frames: 0 });
  }
});

test('a scene loads bg.js once, beside the controller with its build stamp, and starts it with the words', async () => {
  const { B, doc, window } = page({ stored: { scene: 'seoul', rain: true } });
  B.init({ words: () => ['All', 'Small Web'] });
  await tick();
  const [script] = doc.head.children;
  assert.equal(script.src, 'https://shiori.example/_shiori/bg.js?v=abc');
  const calls = [];
  window.annaiBg = { start: (...a) => calls.push(['start', ...a]), stop: () => calls.push(['stop']), rain: (on) => calls.push(['rain', on]) };
  script.onload();
  await tick();
  await tick();
  assert.deepEqual(plain(calls.filter(([k]) => k !== 'stop')), [['start', 'seoul', ['Shiori', 'All', 'Small Web']], ['rain', true]]);
  assert.ok(doc.documentElement.classList.contains('has-bg'));
  // The corner: Rain (on) and Watch (off), labelled.
  const corner = doc.getElementById('bgctl');
  assert.ok(corner);
  assert.deepEqual(plain(corner.children.map((b) => [b.attrs['aria-label'], b.attrs['aria-pressed']])), [['Rain', 'true'], ['Watch', 'false']]);
  // Off again: stopped, the corner gone, no second script.
  await B.change({ scene: 'off' });
  assert.deepEqual(plain(calls.slice(-2)), [['stop'], ['rain', false]]);
  assert.equal(doc.getElementById('bgctl'), null);
  assert.ok(!doc.documentElement.classList.contains('has-bg'));
  await B.change({ scene: 'city' });
  assert.equal(doc.head.children.length, 1);
});

test('in the sheet a change previews and only Save keeps it; Cancel puts it back', async () => {
  const { B, local, window } = page({ stored: { scene: 'city', rain: false } });
  window.annaiBg = { start() {}, stop() {}, rain() {} };
  const plainOff = { frostHeader: false, frostResults: false };
  B.init();
  B.begin();
  await B.change({ scene: 'hk', rain: true });
  assert.deepEqual(plain(B.state()), { scene: 'hk', rain: true, ...plainOff });
  assert.deepEqual(JSON.parse(local.get('shioriBackground')), { scene: 'city', rain: false });
  await B.cancel();
  assert.deepEqual(plain(B.state()), { scene: 'city', rain: false, ...plainOff });
  B.begin();
  await B.change({ scene: 'off' });
  await B.save();
  assert.equal(local.get('shioriBackground'), undefined, 'Off keeps nothing');
  assert.deepEqual(plain(B.kept()), { scene: 'off', rain: false, ...plainOff });
  // Outside the sheet (the corner's Rain) a change is kept at once.
  await B.change({ scene: 'lv' });
  assert.deepEqual(JSON.parse(local.get('shioriBackground')), { scene: 'lv', rain: false, ...plainOff });
});

test('Frosted Header and Frosted Results are kept with the background and mark the page only while one shows', async () => {
  const { B, local, window, doc } = page({ stored: { scene: 'city', rain: false, frostResults: true } });
  window.annaiBg = { start() {}, stop() {}, rain() {} };
  B.init();
  await B.apply();
  const root = doc.documentElement.classList;
  assert.ok(root.contains('frost-results') && !root.contains('frost-header'));
  await B.change({ frostHeader: true });
  assert.ok(root.contains('frost-header'));
  assert.deepEqual(JSON.parse(local.get('shioriBackground')), { scene: 'city', rain: false, frostHeader: true, frostResults: true });
  await B.change({ scene: 'off' });
  assert.ok(!root.contains('frost-header') && !root.contains('frost-results'), 'no background, no frost');
  assert.match(CONTROLLER, /frost = \['Frosted Header', 'Frosted Results'\]/);
});

test("the signs say Shiori's words, not annai's: only these names, each as kanji and in Hangul", () => {
  const map = (name) => {
    const m = BG_JS.match(new RegExp(`const ${name} = \\{([^}]*)\\}`));
    assert.ok(m, `${name} map`);
    return Object.fromEntries([...m[1].matchAll(/(\w+):\s*"([^"]+)"/g)].map((x) => [x[1], x[2]]));
  };
  const words = ['shiori', 'pages', 'notes', 'web', 'smallweb', 'code', 'media'];
  for (const name of ['KANJI', 'HANGUL']) assert.deepEqual(Object.keys(map(name)), words, name);
  assert.equal(map('KANJI').shiori, '栞');
  assert.equal(map('HANGUL').shiori, '시오리');
  // A single character is a sign of its own (栞, 웹).
  assert.match(BG_JS, /w\.length >= 2 \|\| \/\[\^\\x00-\\x7f\]\/\.test\(w\)/);
});

test('the new files name no site, address or private name', () => {
  const files = { 'bg.js': BG_JS, 'backgrounds.js': CONTROLLER, 'backgrounds.css': CSS };
  for (const [name, text] of Object.entries(files)) {
    assert.doesNotMatch(text, /https?:\/\//, `${name}: no web address`);
    assert.doesNotMatch(text, /[\w.-]+@[\w-]+\.[a-z]{2,}/i, `${name}: no e-mail address`);
    assert.doesNotMatch(text, /\b[\w-]+\.(?:com|net|org|io|dev|app|ts\.net)\b/i, `${name}: no host name`);
  }
  // The maintainers' list of private names (tests/test_private_names.py reads the same file), when it's here.
  const path = process.env.MACHIYA_PRIVATE_NAMES || `${homedir()}/.config/machiya/private-names`;
  if (!existsSync(path)) return;
  const names = readFileSync(path, 'utf8').split('\n').map((l) => l.split('#')[0].trim().toLowerCase()).filter(Boolean);
  for (const [name, text] of Object.entries(files)) {
    const words = new Set(text.toLowerCase().match(/[a-z0-9]+(?:-[a-z0-9]+)*/g));
    for (const n of names) assert.ok(!words.has(n), `${name} holds a private name`);
  }
});

test('the background is this browser\'s own: never in the settings that sync or go to Safari\'s app', () => {
  const core = read('../patches/shiori/search-core.js');
  const shared = read('../Shared/Settings/SharedSettings.swift');
  for (const text of [core, shared, read('../patches/ext/core.js')]) {
    assert.doesNotMatch(text, /shioriBackground|ShioriBackgrounds/);
  }
  assert.match(CONTROLLER, /localStorage\.setItem\(KEY/);
  assert.doesNotMatch(CONTROLLER, /fetch\(|sendMessage|XMLHttpRequest/);
});

test("the pages and builds carry it: both pages load it, the builds copy it, the worker caches it, the CSP plays your video", () => {
  assert.match(read('../patches/shiori/search.html'), /<link rel="stylesheet" href="backgrounds\.css" \/>[\s\S]*<script src="backgrounds\.js"><\/script>\s*<script src="search\.js">/);
  assert.match(read('../web/app/index.html'), /href="\/_shiori\/backgrounds\.css"[\s\S]*<script src="\/_shiori\/backgrounds\.js"><\/script>/);
  for (const script of ['build-web.sh', 'build-pwa.sh', 'build-extension.sh']) {
    const text = read(`./${script}`);
    assert.match(text, /patches\/shiori\/backgrounds\.js patches\/shiori\/backgrounds\.css patches\/shiori\/bg\.js/, script);
    assert.match(text, /assets\/backgrounds\/bg-\*\.jpg/, script);
  }
  const sw = read('../web/app/sw.js');
  for (const f of ['backgrounds.js', 'backgrounds.css', 'bg.js']) assert.ok(sw.includes(`'/_shiori/${f}'`), f);
  const csp = read('../docker/shiori-web/configure.py').match(/default "default-src[^"]*"/)[0];
  assert.match(csp, /media-src 'self' blob:/);
  assert.match(csp, /img-src 'self' data: https:;/, 'pictures go as data:, so img-src needs no blob:');
});

test("the corner is pinned lower right with the safe-area insets, and the lists scroll clear of it", () => {
  const corner = CSS.match(/\.bgctl \{[^}]*\}/)[0];
  assert.match(corner, /right: calc\(16px \+ env\(safe-area-inset-right\)\); bottom: calc\(16px \+ env\(safe-area-inset-bottom\)\)/);
  assert.doesNotMatch(corner, /\bleft:/);
  // The search page pads its body; the web app pads its list, on a phone past the tab bar too.
  assert.match(read('../patches/shiori/search.css'), /html\.has-bgctl body:not\(\.home\) \{ padding-bottom: 88px; \}/);
  const app = read('../web/app/app.css');
  assert.match(app, /html\.has-bgctl #list \{ padding-bottom: calc\(88px \+ env\(safe-area-inset-bottom\)\); \}/);
  assert.match(app, /html\.has-bgctl #list \{ padding-bottom: calc\(140px \+ env\(safe-area-inset-bottom\)\); \}/);
  assert.doesNotMatch(app, /has-bgctl #sidebar/);
});

test("the preview ends above the corner and fits the window in the zoomed page's own units", () => {
  const page = read('../patches/shiori/search.css');
  const pane = page.match(/#preview-pane \{[^}]*\}/)[0];
  // Level with the results (main's 8px), under the header, and never 100vh: on a Mac the body's zoom made it 1.2 windows tall.
  assert.match(pane, /top: calc\(var\(--header-h, 0px\) \+ 8px\)/);
  assert.match(pane, /height: calc\(var\(--vh, 100vh\) - var\(--header-h, 0px\) - 16px\); margin-top: 8px;/);
  assert.doesNotMatch(pane, /height: calc\(100vh/);
  assert.match(page, /html\.has-bgctl #preview-pane \{ height: calc\(var\(--vh, 100vh\) - var\(--header-h, 0px\) - 90px\); \}/);
  assert.match(read('../web/app/app.css'), /html\.has-bgctl #preview \{ padding-bottom: calc\(74px \+ env\(safe-area-inset-bottom\)\); \}/);
});

test("the preview's frame stays at zoom 1 and its page takes Text Size's zoom (WebKit cut a sixth off the right)", () => {
  const js = read('../patches/shiori/search.js');
  assert.match(js, /if \(frame\) frame\.style\.zoom = z === 1 \? '' : String\(1 \/ z\);/);
  assert.match(js, /return `:root\{color-scheme:light dark\$\{z === 1 \? '' : `;zoom:\$\{z\}`\}\}/);
});

test("the preview's text is the system's sans in every browser, not only Safari", () => {
  const js = read('../patches/shiori/search.js');
  // -apple-system-body is Safari's alone: Chrome and Firefox drop the shorthand and fell back to serif.
  assert.match(js, /body\{margin:0;padding:18px 22px 40px;font:-apple-system-body;font-family:-apple-system,system-ui,sans-serif;/);
  assert.match(js, /\.meta\{color:\$\{v\('--secondary'\)\};font-size:\.8125em;font:-apple-system-footnote;/);
});

test("off Apple only: the scene at 15 fps and the glass without a blur while it moves; Apple's browsers keep both", () => {
  // One test of the platform, the same in both files: an iPad says MacIntel.
  const apple = /\/Mac\|iPhone\|iPad\|iPod\/\.test\(\(typeof navigator === (?:'object'|"object") && navigator\.platform\) \|\| (?:''|"")\)/;
  assert.match(BG_JS, new RegExp('const SCENE_MS = ' + apple.source + ' \\? 33 : 66;'));
  assert.match(BG_JS, /if \(t - last < SCENE_MS\) return;/);
  assert.match(BG_JS, /function rainLoop\(t\) \{\s+R\.raf = requestAnimationFrame\(rainLoop\);\s+if \(t - R\.last < 33\) return;/, 'the rain keeps 30 fps');
  assert.match(CONTROLLER, new RegExp('const APPLE = ' + apple.source + ';'));
  assert.match(CONTROLLER, /root\.classList\.toggle\('bg-lite', on && !APPLE\);/);
  for (const platform of ['MacIntel', 'iPhone', 'iPad', 'MacPPC']) assert.ok(/Mac|iPhone|iPad|iPod/.test(platform), platform);
  for (const platform of ['Linux x86_64', 'Win32', 'Linux armv8l', '']) assert.ok(!/Mac|iPhone|iPad|iPod/.test(platform), platform);
  // Every rule that drops the blur is gated on bg-lite as well as bg-moving.
  for (const css of [CSS, read('../web/app/app.css'), read('../patches/shiori/search.css')]) {
    for (const [sel] of css.replace(/\/\*[\s\S]*?\*\//g, '').matchAll(/[^{}]*bg-moving[^{]*\{/g)) assert.match(sel, /html\.bg-lite\.bg-moving/, sel.trim());
  }
});
