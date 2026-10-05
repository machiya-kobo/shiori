// Tests for the web app's manifest and head (web/app/) and its build
// (scripts/build-pwa.sh), and the build setting both web builds share
// (SHIORI_AI). Run: node --test scripts/*.test.mjs

import { execFileSync } from 'node:child_process';
import vm from 'node:vm';
import { mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import assert from 'node:assert/strict';

const read = (rel) => readFileSync(rel.startsWith('/') ? rel : fileURLToPath(new URL(rel, import.meta.url)), 'utf8');

test("the manifest's shortcuts are hash routes the app draws, with its language and categories", () => {
  const manifest = JSON.parse(read('../web/app/manifest.webmanifest'));
  assert.equal(manifest.lang, 'en');
  assert.ok(Array.isArray(manifest.categories) && manifest.categories.includes('productivity'));
  assert.deepEqual(manifest.shortcuts.map((s) => [s.name, s.url]), [['Search', '/#/search'], ['Labels', '/#/labels'], ['Notes', '/#/library?s=notes']]);
  const app = read('../web/app/app.js');
  for (const view of ['search', 'labels']) assert.match(app, new RegExp(`view === '${view}'`), view);
  assert.match(app, /if \(!q\) \{\s*go\('library', \{ s: scope \}, \{ replace: true \}\);\s*return searchInput\.focus\(\);/);
  assert.match(app, /\['notes', 'Notes', 'orange'\]/, 'a scope the Library knows');
  for (const s of manifest.shortcuts) for (const i of s.icons) assert.match(i.src, /^\/_shiori\/web-icon-\d+\.png$/);
});

test("the head says it's an installable app on every browser", () => {
  const html = read('../web/app/index.html');
  assert.match(html, /<meta name="mobile-web-app-capable" content="yes" \/>/);
  assert.match(html, /<meta name="apple-mobile-web-app-capable" content="yes" \/>/);
  assert.match(html, /<html lang="en">/);
});

// One build into a temporary folder, for the tests below.
const repo = fileURLToPath(new URL('..', import.meta.url));
function build(env = {}, status = '') {
  const out = mkdtempSync(join(tmpdir(), 'shiori-pwa-'));
  execFileSync('bash', ['scripts/build-pwa.sh', out, ...(status ? [status] : [])], { cwd: repo, env: { ...process.env, SHIORI_ROOM_LOGOS: '', ...env }, stdio: 'pipe' });
  return out;
}

test('the build copies only the icons the web app uses', () => {
  const out = build();
  try {
    const icons = readdirSync(join(out, '_shiori')).filter((f) => f.endsWith('.png')).sort();
    assert.deepEqual(icons, ['icon-256.png', 'web-icon-192.png', 'web-icon-512.png', 'web-icon-64.png', 'web-maskable-512.png']);
    const used = read('../web/app/index.html') + read('../web/app/manifest.webmanifest') + read('../web/app/sw.js');
    for (const icon of icons) assert.ok(used.includes(`/_shiori/${icon}`), `${icon} is used`);
  } finally {
    rmSync(out, { recursive: true, force: true });
  }
});

test("the service worker's cache name is a hash of the built files: other settings, a new one", () => {
  const version = (out) => read(join(out, 'sw.js')).match(/const CACHE = 'shiori-app-([0-9a-f]+)'/)[1];
  const outs = [build(), build(), build({ SHIORI_NIWA_URL: 'https://kura.example/' }), build({}, 'https://status.example/')];
  try {
    const [a, b, c, d] = outs.map(version);
    assert.match(a, /^[0-9a-f]{12}$/);
    assert.equal(a, b, 'the same files, the same version');
    assert.notEqual(a, c, 'another Kura, a new version');
    assert.notEqual(a, d, 'another status page, a new version');
    // Every address the app loads carries it.
    for (const out of outs.slice(0, 1)) {
      const html = read(join(out, 'index.html'));
      for (const f of ['theme.css', 'app.css', 'search-core.js', 'app.js']) assert.ok(html.includes(`/_shiori/${f}?v=${a}`), f);
      assert.ok(read(join(out, '_shiori', 'app.js')).includes(`from './api.js?v=${a}'`));
      assert.ok(read(join(out, 'sw.js')).includes(`'/_shiori/app.js?v=${a}'`));
    }
  } finally {
    for (const out of outs) rmSync(out, { recursive: true, force: true });
  }
});

// --- SHIORI_AI: the companion AI service (/shiori/ai/*), only when the build says so ---

function buildWeb(env = {}) {
  const out = mkdtempSync(join(tmpdir(), 'shiori-web-'));
  execFileSync('bash', ['scripts/build-web.sh', out, 'https://shiori.example/'], { cwd: repo, env: { ...process.env, SHIORI_ROOM_LOGOS: '', SHIORI_AI: '', ...env }, stdio: 'pipe' });
  return out;
}

/** The hosted search page's settings, as its built shim hands them over. */
async function shimSettings(out) {
  const window = {};
  vm.runInNewContext(read(join(out, '_shiori', 'web-shim.js')), {
    window,
    location: { origin: 'https://shiori.example', hostname: 'shiori.example' },
    document: { cookie: '' },
    localStorage: { getItem: () => null, setItem: () => {} },
  });
  return (await window.chrome.storage.local.get(['shioriSettings'])).shioriSettings;
}

test('the search page asks for /shiori/ai/ only when built with SHIORI_AI=1', async () => {
  const off = buildWeb();
  const on = buildWeb({ SHIORI_AI: '1' });
  const other = buildWeb({ SHIORI_AI: 'yes' });
  try {
    assert.equal((await shimSettings(off)).aiURL, '', 'unset: no AI address');
    assert.equal((await shimSettings(other)).aiURL, '', 'only "1" turns it on');
    assert.equal((await shimSettings(on)).aiURL, 'https://shiori.example/shiori/ai/');
  } finally {
    for (const out of [off, on, other]) rmSync(out, { recursive: true, force: true });
  }
  // The page reaches the service only through aiBase (settings.aiURL), and
  // never without one: no status request, no AI Answer. Its cards have no
  // Summarize (the web app's ✦ is the web's one).
  const page = read('../patches/shiori/search.js');
  assert.doesNotMatch(page, /['"`]\/?shiori\/ai/, 'no address of its own (comments aside)');
  assert.match(page, /const aiBase = withSlash\(settings\.aiURL \|\| ''\);/);
  assert.match(page, /const aiStatus = aiBase \? fetchJSON\(`\$\{aiBase\}status`/);
  assert.equal(page.match(/\$\{aiBase\}/g).length, 2, 'status, and aiPost');
  assert.doesNotMatch(page, /summarize-link|aiPost\('summarize'/, 'no Summarize on the cards');
  assert.match(page, /if \(!aiBase \|\| !webLike \|\| page !== 1/);
});

test('the web app asks for /shiori/ai/ only when built with SHIORI_AI=1', () => {
  const off = build();
  const on = build({ SHIORI_AI: '1' });
  try {
    const flag = (out) => read(join(out, '_shiori', 'app.js')).match(/const AI_BUILT = fromBuild\('([^']*)'\) === '1';/)[1];
    assert.equal(flag(off), '__SHIORI_AI__', 'unset: the placeholder, which reads as empty');
    assert.equal(flag(on), '1');
  } finally {
    for (const out of [off, on]) rmSync(out, { recursive: true, force: true });
  }
  // Every AI request goes through api.js's three calls, and the app makes
  // them only behind the flag: the status first, the others only once it
  // said the service is on.
  const apiSource = read('../web/app/api.js');
  assert.equal(apiSource.match(/shiori\/ai\//g).length, 3);
  const app = read('../web/app/app.js');
  assert.doesNotMatch(app, /['"`]\/?shiori\/ai/, 'no address of its own');
  assert.deepEqual(app.match(/api\.(aiStatus|answer|summarize)\(/g), ['api.aiStatus(', 'api.answer(', 'api.summarize(']);
  assert.match(app, /\(AI_BUILT \? api\.aiStatus\(\) : Promise\.resolve\(null\)\)\.then\(\(status\) => \{\s*aiOn = !!\(status && status\.enabled\);\s*aiAnswers = aiOn && !!status\.answer;/);
  assert.match(app, /if \(!aiAnswers \|\| !settings\.webResults/, 'the answer only when the status said so');
  assert.match(app, /const canSummarize = \(doc, n\) => aiOn && /, 'Summarize only when the status said so');
});

// --- Add Page and the share target: only with the small-web gateway ---

test("the manifest's share target lands on the app's own page, as GET url, title and text", () => {
  const manifest = JSON.parse(read('../web/app/manifest.webmanifest'));
  assert.deepEqual(manifest.share_target, { action: '/', method: 'GET', params: { url: 'url', title: 'title', text: 'text' } });
  assert.ok(manifest.share_target.action.startsWith(manifest.scope), 'inside the scope');
  // From a cold start: the worker serves the app for / with any query.
  const sw = read('../web/app/sw.js');
  assert.match(sw, /const shell = url\.pathname === '\/' \|\|/);
  assert.match(sw, /caches\.match\(url\.pathname === '\/' \? '\/' : event\.request\)/);
  // The app reads the share once, drops the query, and opens the sheet;
  // only its Save button sends.
  const app = read('../web/app/app.js');
  assert.match(app, /const shared = api\.sharedPage\(new URLSearchParams\(location\.search\)\);\s*if \(shared\) history\.replaceState\(null, '', '\/' \+ location\.hash\);/);
  assert.match(app, /render\(\);\s*if \(shared\) addPage\(shared\);/);
  assert.equal(app.match(/api\.savePage\(/g).length, 1);
  assert.match(app, /form\.addEventListener\('submit', async \(event\) => \{[\s\S]*?api\.savePage\(/);
});

test('without SHIORI_SMALLWEB_URL the build offers no Add Page and no share target', () => {
  const off = build();
  const on = build({ SHIORI_SMALLWEB_URL: 'https://smallweb.example/' });
  try {
    const manifest = (out) => JSON.parse(read(join(out, 'manifest.webmanifest')));
    assert.equal('share_target' in manifest(off), false);
    assert.deepEqual(manifest(on).share_target, JSON.parse(read('../web/app/manifest.webmanifest')).share_target);
    assert.deepEqual(manifest(off).shortcuts, manifest(on).shortcuts, 'the rest as it was');
    const flag = (out) => read(join(out, '_shiori', 'app.js')).match(/const SMALLWEB = fromBuild\('([^']*)'\) !== '';/)[1];
    assert.equal(flag(off), '__SHIORI_SMALLWEB_URL__', 'unset: reads as empty');
    assert.equal(flag(on), 'https://smallweb.example/');
  } finally {
    for (const out of [off, on]) rmSync(out, { recursive: true, force: true });
  }
  // Every way in goes through SMALLWEB: the sheet, the sidebar's +, the tab.
  const app = read('../web/app/app.js');
  assert.match(app, /function addPage\(prefill = \{\}\) \{\s*if \(!SMALLWEB\) return;/);
  assert.match(app, /const add = SMALLWEB \? h\('button', \{ type: 'button', class: 'sidebar-gear sidebar-add'/);
  assert.match(app, /const add = SMALLWEB \? h\('button', \{ type: 'button', class: 'add-tab'/);
  assert.equal(app.match(/addPage\(/g).length, 4, 'defined, the +, the tab, the share');
});

// --- status.json: what the house's status page reads of a hosted build ---

test('both web builds publish _shiori/status.json: version, build, built, hister, and nothing else', () => {
  const project = read('../project.yml').match(/MARKETING_VERSION:\s*"?([0-9][0-9A-Za-z.\-]*)/)[1];
  for (const out of [build(), buildWeb()]) {
    try {
      const status = JSON.parse(read(join(out, '_shiori', 'status.json')));
      assert.deepEqual(Object.keys(status).sort(), ['build', 'built', 'hister', 'version']);
      // The Hister release Shiori is built against: the tag, or the pinned commit.
      assert.match(status.hister, /^(v\d+\.\d+\.\d+.*|[0-9a-f]{7})$/);
      assert.equal(status.version, project);
      assert.match(status.build, /^[0-9a-f]{7,}(-dirty)?$/);
      assert.match(status.built, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
    } finally {
      rmSync(out, { recursive: true, force: true });
    }
  }
});

test('one version everywhere: project.yml, Linux, and a CHANGELOG section for it, served by both builds', () => {
  const version = read('../project.yml').match(/MARKETING_VERSION:\s*"?([0-9][0-9A-Za-z.\-]*)/)[1];
  assert.equal(read('../linux/gjs/save.js').match(/export const VERSION = '([^']+)';/)[1], version);
  const changelog = read('../CHANGELOG.md');
  assert.match(changelog, new RegExp(`^## ${version.replace(/\./g, '\\.')} \\(\\d{4}-\\d\\d-\\d\\d\\)$`, 'm'), `a "## ${version} (date)" section`);
  for (const out of [build(), buildWeb()]) {
    try {
      assert.equal(read(join(out, '_shiori', 'CHANGELOG.md')), changelog);
    } finally {
      rmSync(out, { recursive: true, force: true });
    }
  }
});
