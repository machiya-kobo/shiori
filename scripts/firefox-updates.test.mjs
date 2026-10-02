// Tests for scripts/firefox-updates.mjs, the update manifest each Firefox
// release carries.
// Run: node --test scripts/*.test.mjs

import { createHash } from 'node:crypto';
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import assert from 'node:assert/strict';

import { updatesManifest } from './firefox-updates.mjs';

const script = fileURLToPath(new URL('./firefox-updates.mjs', import.meta.url));
const MANIFEST = {
  version: '0.2.0',
  browser_specific_settings: { gecko: { id: 'shiori@machiya-kobo.github.io', strict_min_version: '153.0' } },
};
const LINK = 'https://github.com/machiya-kobo/shiori/releases/download/v0.2.0/shiori-firefox-0.2.0.xpi';

test("names this version, its file, the file's hash and the floor, under the add-on's ID", () => {
  const xpi = Buffer.from('signed bytes');
  const out = updatesManifest(MANIFEST, xpi, LINK);
  assert.deepEqual(out, {
    addons: {
      'shiori@machiya-kobo.github.io': {
        updates: [
          {
            version: '0.2.0',
            update_link: LINK,
            update_hash: 'sha256:' + createHash('sha256').update(xpi).digest('hex'),
            applications: { gecko: { strict_min_version: '153.0' } },
          },
        ],
      },
    },
  });
});

test('refuses a manifest without an ID or version, and a link that is not https', () => {
  assert.throws(() => updatesManifest({ version: '1' }, Buffer.alloc(1), LINK), /ID/);
  assert.throws(() => updatesManifest({ ...MANIFEST, version: '' }, Buffer.alloc(1), LINK), /version/);
  assert.throws(() => updatesManifest(MANIFEST, Buffer.alloc(1), LINK.replace('https', 'http')), /https/);
});

test('the CLI writes it from the built manifest and the signed file', () => {
  const dir = mkdtempSync(join(tmpdir(), 'shiori-updates-'));
  try {
    writeFileSync(join(dir, 'manifest.json'), JSON.stringify(MANIFEST));
    writeFileSync(join(dir, 'shiori.xpi'), 'signed bytes');
    const r = spawnSync(process.execPath, [script, join(dir, 'manifest.json'), join(dir, 'shiori.xpi'), LINK, join(dir, 'updates.json')], { encoding: 'utf8' });
    assert.equal(r.status, 0, r.stderr);
    const written = JSON.parse(readFileSync(join(dir, 'updates.json'), 'utf8'));
    assert.equal(written.addons['shiori@machiya-kobo.github.io'].updates[0].version, '0.2.0');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("the add-on's update URL is where the release workflow puts this file", () => {
  const firefox = JSON.parse(readFileSync(new URL('../patches/manifest.firefox.json', import.meta.url), 'utf8'));
  const workflow = readFileSync(new URL('../.github/workflows/firefox-release.yml', import.meta.url), 'utf8');
  assert.equal(firefox.browser_specific_settings.gecko.update_url, 'https://github.com/machiya-kobo/shiori/releases/latest/download/updates.json');
  assert.match(workflow, /build\/updates\.json/);
});
