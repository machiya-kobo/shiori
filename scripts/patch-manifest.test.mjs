import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import assert from 'node:assert/strict';

import { merge } from './patch-manifest.mjs';

const script = fileURLToPath(new URL('./patch-manifest.mjs', import.meta.url));

test('merge keeps upstream keys, overlays nested objects, and drops $ comments', () => {
  const merged = merge(
    {
      name: 'Hister',
      icons: { 128: 'assets/icons/icon128.png' },
      action: { default_icon: { 128: 'assets/icons/icon128.png' }, default_popup: 'popup.html' },
      key: 'UPSTREAM-KEY',
    },
    {
      $comment: 'ignored',
      key: null,
      icons: { 16: 'assets/icons/icon-16.png', 32: 'assets/icons/icon-32.png' },
      action: { default_icon: { 16: 'assets/icons/icon-16.png' } },
    },
  );

  assert.equal(merged.name, 'Hister');
  assert.equal(merged.key, undefined);
  assert.equal(merged.$comment, undefined);
  assert.deepEqual(merged.icons, {
    128: 'assets/icons/icon128.png',
    16: 'assets/icons/icon-16.png',
    32: 'assets/icons/icon-32.png',
  });
  assert.deepEqual(merged.action, {
    default_icon: {
      128: 'assets/icons/icon128.png',
      16: 'assets/icons/icon-16.png',
    },
    default_popup: 'popup.html',
  });
});

test('CLI writes the merged manifest', () => {
  const dir = mkdtempSync(join(tmpdir(), 'hister-manifest-'));
  try {
    const upstream = join(dir, 'upstream.json');
    const override = join(dir, 'override.json');
    const out = join(dir, 'out.json');
    writeFileSync(upstream, JSON.stringify({ name: 'Hister', key: 'K' }));
    writeFileSync(override, JSON.stringify({ key: null, icons: { 16: 'a.png' } }));

    const result = spawnSync(process.execPath, [script, upstream, override, out], {
      encoding: 'utf8',
    });
    assert.equal(result.status, 0, result.stderr);
    const written = JSON.parse(readFileSync(out, 'utf8'));
    assert.equal(written.name, 'Hister');
    assert.equal(written.key, undefined);
    assert.equal(written.icons[16], 'a.png');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('CLI applies several overrides in order, the last winning', () => {
  const dir = mkdtempSync(join(tmpdir(), 'hister-manifest-'));
  try {
    const upstream = join(dir, 'upstream.json');
    const first = join(dir, 'first.json');
    const second = join(dir, 'second.json');
    const out = join(dir, 'out.json');
    writeFileSync(upstream, JSON.stringify({ name: 'Hister', permissions: ['tabs', 'cookies'] }));
    writeFileSync(first, JSON.stringify({ name: 'Shiori', permissions: ['tabs', 'nativeMessaging'] }));
    writeFileSync(second, JSON.stringify({ permissions: ['tabs'] }));
    const result = spawnSync(process.execPath, [script, upstream, first, second, out], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    const written = JSON.parse(readFileSync(out, 'utf8'));
    assert.equal(written.name, 'Shiori');
    assert.deepEqual(written.permissions, ['tabs']);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// The real overlays, over a stand-in for upstream's manifests.
const overlay = (name) => JSON.parse(readFileSync(new URL(`../patches/manifest.${name}.json`, import.meta.url), 'utf8'));
const UPSTREAM = {
  name: 'Hister',
  permissions: ['tabs', 'storage', 'cookies'],
  options_page: 'options.html',
  key: 'K',
  commands: { 'index-current-page': { suggested_key: { default: 'Ctrl+I', mac: 'Command+I' } } },
  web_accessible_resources: [{ resources: ['assets/*'], matches: [] }],
};

test("Safari's manifest: the app's messaging, Control-Shift keys, no cookies", () => {
  const m = merge(merge(UPSTREAM, overlay('shiori')), overlay('safari'));
  assert.deepEqual(m.permissions, ['tabs', 'storage', 'nativeMessaging']);
  assert.deepEqual(m.commands['index-current-page'].suggested_key, { default: 'Ctrl+Shift+S', mac: 'MacCtrl+Shift+S' });
  assert.equal(m.options_page, 'shiori-options.html');
  assert.equal(m.key, undefined);
  assert.equal(m.web_accessible_resources, undefined);
});

test("Firefox's manifest: no messaging, never private, Alt-Shift keys (the Mac's kept), its own ID and floor", () => {
  const m = merge(merge({ ...UPSTREAM, background: { scripts: ['background.js'] } }, overlay('shiori')), overlay('firefox'));
  assert.deepEqual(m.permissions, ['tabs', 'storage']);
  assert.equal(m.incognito, 'not_allowed');
  for (const name of ['index-current-page', 'disable-indexing-current-page', 'disable-indexing-current-domain', 'open-shiori-search']) {
    assert.match(m.commands[name].suggested_key.default, /^Alt\+Shift\+/, name);
    assert.match(m.commands[name].suggested_key.mac, /^MacCtrl\+Shift\+/, name);
  }
  assert.equal(m.options_page, undefined);
  assert.deepEqual(m.options_ui, { page: 'shiori-options.html', open_in_tab: true });
  const { gecko, gecko_android } = m.browser_specific_settings;
  assert.equal(gecko.id, 'shiori@machiya-kobo.github.io');
  assert.equal(gecko.strict_min_version, gecko_android.strict_min_version);
  assert.ok(Number.parseFloat(gecko.strict_min_version) >= 153);
});
