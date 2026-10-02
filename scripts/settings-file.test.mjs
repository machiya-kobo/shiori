// Tests for patches/ext/settings-file.js: settings to a file and back, for
// setting up another device (Firefox's settings page).
// Run: node --test scripts/*.test.mjs

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const ctx = { JSON, URL, Date };
ctx.globalThis = ctx;
vm.createContext(ctx);
vm.runInContext(readFileSync(fileURLToPath(new URL('../patches/ext/settings-file.js', import.meta.url)), 'utf8'), ctx);
const F = ctx.ShioriSettingsFile;
const plain = (v) => JSON.parse(JSON.stringify(v));
const NOW = new Date('2026-10-02T05:00:00Z');

test('the file holds the server and the settings, never the recent searches', () => {
  const doc = plain(F.exportSettings({
    server: 'https://hister.example/',
    settings: { theme: 'night', histerCount: 10, recentSearches: ['private', 'searches'] },
    now: NOW,
  }));
  assert.deepEqual(doc, {
    kind: 'shiori-settings', version: 1, exported: '2026-10-02T05:00:00.000Z',
    server: 'https://hister.example/', settings: { theme: 'night', histerCount: 10 },
  });
  assert.equal(F.fileName(NOW), 'shiori-settings-2026-10-02.json');
});

test('a file read back gives the same server and settings', () => {
  const text = JSON.stringify(F.exportSettings({ server: 'https://hister.example/', settings: { combinedSearch: false } }));
  assert.deepEqual(plain(F.readImport(text)), { server: 'https://hister.example/', settings: { combinedSearch: false } });
});

test('anything but a Shiori settings file is refused, in words', () => {
  assert.match(F.readImport('not json').error, /isn't JSON/);
  assert.match(F.readImport('{"kind":"something-else"}').error, /isn't Shiori's settings/);
  assert.match(F.readImport('{"kind":"shiori-settings","version":2}').error, /another version/);
  assert.match(F.readImport('null').error, /isn't Shiori's settings/);
});

test('a server that is not http(s) is dropped; recent searches in a file are ignored', () => {
  const read = plain(F.readImport(JSON.stringify({
    kind: 'shiori-settings', version: 1, server: 'javascript:alert(1)',
    settings: { theme: 'day', recentSearches: ['planted'] },
  })));
  assert.deepEqual(read, { server: null, settings: { theme: 'day' } });
  assert.equal(plain(F.readImport(JSON.stringify({ kind: 'shiori-settings', version: 1, server: 'http://hister.lan:4433' }))).server, 'http://hister.lan:4433/');
  assert.deepEqual(plain(F.readImport(JSON.stringify({ kind: 'shiori-settings', version: 1, settings: ['x'] }))).settings, {});
});

test('what applying it would change, before it is applied', () => {
  assert.equal(F.describeImport({ server: 'https://new.example/', settings: { a: 1, b: 2 } }, 'https://old.example/'),
    'This file sets the Hister server to https://new.example/, plus 2 settings.');
  assert.equal(F.describeImport({ server: 'https://same.example/', settings: { a: 1 } }, 'https://same.example/'), 'This file sets 1 setting.');
  assert.equal(F.describeImport({ server: 'https://new.example/', settings: {} }, ''), 'This file sets the Hister server to https://new.example/.');
  assert.equal(F.describeImport({ server: null, settings: {} }, ''), 'This file changes nothing here.');
});
