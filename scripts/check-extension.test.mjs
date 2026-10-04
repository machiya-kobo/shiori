// Tests for scripts/check-extension.py, the bundle check at the end of
// build-extension.sh: a minimal valid Safari bundle passes, and each rule
// broken alone fails it.
// Run: node --test scripts/*.test.mjs

import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import assert from 'node:assert/strict';

const script = fileURLToPath(new URL('./check-extension.py', import.meta.url));

const FILES = {
  'content.js': 'installPageSizeCap',
  'popup.html': 'safari-popup.css shiori-popup.js',
  'popup.js': '',
  'search.html': 'search-core.js search.js palettes.css',
  'palettes.css': ':root[data-palette="nord"]',
  'shiori-options.html': 'shiori-options.js search.css',
  'search-core.js': '',
  'assets/icons/icon-16.png': '',
};

function manifest() {
  return {
    permissions: ['tabs', 'storage', 'nativeMessaging', 'contextMenus'],
    icons: { 16: 'assets/icons/icon-16.png' },
    action: { default_icon: { 16: 'assets/icons/icon-16.png' }, default_popup: 'popup.html' },
    content_scripts: [
      { js: ['content.js'], matches: ['<all_urls>'] },
      { js: ['search-core.js', 'shiori-redirect.js'], matches: ['https://duckduckgo.com/*'] },
    ],
    background: { service_worker: 'background.js' },
    options_page: 'shiori-options.html',
    commands: {},
  };
}

const BACKGROUND = 'installIconShim const shioriHost installCaptureQueue installCombinedSearch root.ShioriSearch installQueueBadge installMenus';

function check(change = () => {}, target = 'safari') {
  const root = mkdtempSync(join(tmpdir(), 'shiori-bundle-'));
  try {
    const files = { ...FILES, 'background.js': BACKGROUND, 'shiori-redirect.js': '' };
    const m = manifest();
    change(m, files);
    for (const [name, text] of Object.entries(files)) {
      mkdirSync(join(root, name, '..'), { recursive: true });
      writeFileSync(join(root, name), text);
    }
    writeFileSync(join(root, 'manifest.json'), JSON.stringify(m));
    const r = spawnSync('python3', [script, root, target], { encoding: 'utf8' });
    return { ok: r.status === 0, out: r.stdout + r.stderr };
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test('a complete bundle passes', () => {
  const r = check();
  assert.ok(r.ok, r.out);
});

test('it fails on cookies, a missing file, a missing shim or another target', () => {
  assert.match(check((m) => m.permissions.push('cookies')).out, /cookies/);
  assert.match(check((m, f) => delete f['popup.js'] && delete f['assets/icons/icon-16.png']).out, /missing files/);
  assert.match(check((m, f) => (f['content.js'] = '')).out, /installPageSizeCap/);
  assert.match(check(() => {}, 'firefox').out, /unknown target/);
});

test('Safari fails with a fifth suggested shortcut', () => {
  const r = check((m) => {
    for (const k of ['a', 'b', 'c', 'd', 'e']) m.commands[k] = { suggested_key: { default: 'Ctrl+Shift+' + k.toUpperCase() } };
  });
  assert.equal(r.ok, false);
  assert.match(r.out, /at most 4/);
});

test('Safari fails without its badge, its menu or the permission the menu needs', () => {
  const cases = {
    installQueueBadge: (m, f) => (f['background.js'] = f['background.js'].replace('installQueueBadge', '')),
    installMenus: (m, f) => (f['background.js'] = f['background.js'].replace('installMenus', '')),
    'root.ShioriSearch': (m, f) => (f['background.js'] = f['background.js'].replace('root.ShioriSearch', '')),
    contextMenus: (m) => (m.permissions = m.permissions.filter((p) => p !== 'contextMenus')),
  };
  for (const [rule, change] of Object.entries(cases)) {
    const r = check(change);
    assert.equal(r.ok, false, rule);
    assert.ok(r.out.includes(rule), `${rule}: ${r.out}`);
  }
});
