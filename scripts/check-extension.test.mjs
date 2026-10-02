// Tests for scripts/check-extension.py, the bundle check at the end of
// build-extension.sh: a minimal valid bundle per browser passes, and each
// rule broken alone fails it.
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
  'search.html': 'search-core.js search.js',
  'shiori-options.html': 'shiori-options.js search.css',
  'shiori-settings.html': 'shiori-settings.js shiori-settings.css search.css',
  'search-core.js': '',
  'shiori-redirect.js': '',
  'assets/icons/icon-16.png': '',
};

function manifest(target) {
  const m = {
    permissions: ['tabs', 'storage'],
    icons: { 16: 'assets/icons/icon-16.png' },
    action: { default_icon: { 16: 'assets/icons/icon-16.png' }, default_popup: 'popup.html' },
    content_scripts: [
      { js: ['content.js'], matches: ['<all_urls>'] },
      { js: ['search-core.js', 'shiori-redirect.js'], matches: ['https://duckduckgo.com/*'] },
    ],
    commands: {},
  };
  if (target === 'safari') {
    m.permissions.push('nativeMessaging');
    m.background = { service_worker: 'background.js' };
    m.options_page = 'shiori-options.html';
  } else {
    m.background = { scripts: ['background.js'] };
    m.options_ui = { page: 'shiori-settings.html', open_in_tab: true };
    m.incognito = 'not_allowed';
    m.omnibox = { keyword: 'sh' };
    m.browser_specific_settings = {
      gecko: {
        id: 'shiori@machiya-kobo.github.io',
        strict_min_version: '153.0',
        update_url: 'https://github.com/machiya-kobo/shiori/releases/latest/download/updates.json',
      },
      gecko_android: { strict_min_version: '153.0' },
    };
  }
  return m;
}

const BACKGROUND = {
  safari: 'installIconShim const shioriHost installCaptureQueue installCombinedSearch',
  firefox: "const shioriHost 'shioriLocalSettings' installCaptureQueue installCombinedSearch root.ShioriSearch installOmnibox",
};

function check(target, change = () => {}) {
  const root = mkdtempSync(join(tmpdir(), 'shiori-bundle-'));
  try {
    const files = { ...FILES, 'background.js': BACKGROUND[target] };
    const m = manifest(target);
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

test('a complete bundle passes, for each browser', () => {
  for (const target of ['safari', 'firefox']) {
    const r = check(target);
    assert.ok(r.ok, `${target}: ${r.out}`);
  }
});

test('either browser fails on cookies, a missing file or a missing shim', () => {
  for (const target of ['safari', 'firefox']) {
    assert.match(check(target, (m) => m.permissions.push('cookies')).out, /cookies/);
    assert.match(check(target, (m, f) => delete f['popup.js'] && delete f['assets/icons/icon-16.png']).out, /missing files/);
    assert.match(check(target, (m, f) => (f['content.js'] = '')).out, /installPageSizeCap/);
  }
});

test('Safari fails with a fifth suggested shortcut', () => {
  const r = check('safari', (m) => {
    for (const k of ['a', 'b', 'c', 'd', 'e']) m.commands[k] = { suggested_key: { default: 'Ctrl+Shift+' + k.toUpperCase() } };
  });
  assert.equal(r.ok, false);
  assert.match(r.out, /at most 4/);
});

test("Firefox fails on each of its rules broken alone", () => {
  const cases = {
    'nativeMessaging': (m) => m.permissions.push('nativeMessaging'),
    'private windows': (m) => delete m.incognito,
    'add-on ID': (m) => (m.browser_specific_settings.gecko.id = 'other@example.org'),
    'update URL': (m) => (m.browser_specific_settings.gecko.update_url = 'https://example.org/updates.json'),
    'strict_min_version': (m) => (m.browser_specific_settings.gecko_android.strict_min_version = '140.0'),
    'event page': (m) => (m.background = { service_worker: 'background.js' }),
    'native messaging': (m, f) => (f['background.js'] += ' chrome.runtime.sendNativeMessage(__SHIORI_APP_ID__)'),
    'shioriLocalSettings': (m, f) => (f['background.js'] = BACKGROUND.safari),
    'settings page': (m) => (m.options_ui.page = 'shiori-options.html'),
    'omnibox': (m) => delete m.omnibox,
    'installOmnibox': (m, f) => (f['background.js'] = f['background.js'].replace('installOmnibox', '')),
  };
  for (const [rule, change] of Object.entries(cases)) {
    const r = check('firefox', change);
    assert.equal(r.ok, false, rule);
    assert.ok(r.out.toLowerCase().includes(rule.toLowerCase()), `${rule}: ${r.out}`);
  }
});
