// Tests for the web app's manifest and head (web/app/) and its build
// (scripts/build-pwa.sh). Run: node --test scripts/*.test.mjs

import { execFileSync } from 'node:child_process';
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
