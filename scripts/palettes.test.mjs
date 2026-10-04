// The web app's ten themes (scripts/palettes.mjs, web/app/palettes.css): the
// rooms' table, every variant as readable as Tokyo Night is here, and the app
// and search-core knowing the same ten.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { TABLE_PATH, CSS_PATH, SWIFT_PATH, TEXT, TINTS, css, swift, bars, variant, ratio, mix, luminance } from './palettes.mjs';

const table = JSON.parse(readFileSync(TABLE_PATH, 'utf8'));
const read = (rel) => readFileSync(new URL(rel, import.meta.url), 'utf8');

function core() {
  const ctx = vm.createContext({});
  vm.runInContext(read('../patches/shiori/search-core.js'), ctx);
  return ctx.ShioriSearch;
}

test('the ten themes, each with a dark and a light variant', () => {
  assert.deepEqual(Object.keys(table), ['tokyo-night', 'solarized', 'nord', 'dracula', 'catppuccin', 'gruvbox', 'rose-pine',
    'kanagawa', 'everforest', 'ayu']);
  for (const [key, p] of Object.entries(table)) {
    assert.ok(p.name && p.dark && p.light, key);
    assert.ok(luminance(p.dark.bg) < luminance(p.light.bg), key);
  }
  assert.equal(table['tokyo-night'].dark.bg, '#1a1b26');           // the rooms' Tokyo Night, as app.css has it
  assert.equal(table['tokyo-night'].light.dark, '#d0d5e3');
});

test('palettes.css is made from the table (node scripts/palettes.mjs)', () => {
  assert.equal(readFileSync(CSS_PATH, 'utf8'), css(table));
});

test("the apps' Palettes.swift is made from the table too (node scripts/palettes.mjs)", () => {
  assert.equal(readFileSync(SWIFT_PATH, 'utf8'), swift(table));
});

for (const [key, p] of Object.entries(table)) {
  for (const mode of ['dark', 'light']) {
    test(`${key} ${mode}: every text colour is at least 4.5:1 on the page, on cards and on tinted cards`, () => {
      const v = variant(p[mode], mode);
      const surfaces = [v.bg, v.card, ...TINTS.map((t) => mix(v[t], v.card, v['tint-mix'] / 100))];
      for (const fg of [...TEXT, 'hit']) {
        for (const bg of surfaces) {
          const r = ratio(v[fg], bg);
          assert.ok(r >= 4.5, `--${fg} ${v[fg]} on ${bg} is ${r.toFixed(2)}:1`);
        }
      }
    });
  }
}

test("the settings' whitelists know the same ten: SharedSettings.palettes and host-local.js", () => {
  const keys = Object.keys(table);
  const list = (text, pattern) => [...text.match(pattern)[1].matchAll(/["']([a-z-]+)["']/g)].map((m) => m[1]);
  assert.deepEqual(list(read('../Shared/Settings/SharedSettings.swift'), /static let palettes = \[([^\]]*)\]/), keys);
  assert.deepEqual(list(read('../patches/ext/host-local.js'), /const PALETTES = \[([^\]]*)\]/), keys);
});

test("search-core's PALETTES is the table's names and bar colours", () => {
  const S = core();
  assert.ok(S, 'search-core exports');
  assert.deepEqual(JSON.parse(JSON.stringify(S.PALETTES)), bars(table));
});

test('the palette is shared with the rooms: cookie, house value, bar colours', () => {
  const S = core();
  assert.equal(S.houseSettings('machiya_palette=nord').palette, 'nord');
  assert.equal(S.houseSettings('machiya_palette=<x>').palette, undefined);
  assert.equal(S.houseCookie('palette', 'gruvbox', 'localhost'), 'machiya_palette=gruvbox; path=/; max-age=31536000; samesite=lax');
  assert.equal(S.houseCookie('palette', 'purple', 'localhost'), null);
  assert.deepEqual(JSON.parse(JSON.stringify(S.themeColorMetas('night', 'dracula'))), [{ content: '#21222c', media: '' }]);
  assert.deepEqual(JSON.parse(JSON.stringify(S.themeColorMetas('day', 'nope'))), [{ content: '#d0d5e3', media: '' }]);
  assert.equal(JSON.parse(JSON.stringify(S.themeColorMetas('system', 'nord')))[1].content, '#e5e9f0');
});

test('the app offers the ten as Theme, System / Light / Dark as Appearance, and loads palettes.css', () => {
  const app = read('../web/app/app.js');
  assert.match(app, /choice\('palette', 'Theme', Object\.entries\(S\.PALETTES\)/);
  assert.match(app, /choice\('theme', 'Appearance', \[\['system', 'System'\], \['day', 'Light'\], \['night', 'Dark'\]\]\)/);
  assert.match(app, /document\.documentElement\.dataset\.palette = palette/);
  assert.match(app, /palette: S\.houseValue\('palette', settings\.palette\)/);
  assert.match(read('../web/app/index.html'), /<link rel="stylesheet" href="\/_shiori\/palettes\.css" \/>/);
  assert.match(read('../web/app/sw.js'), /'\/_shiori\/palettes\.css'/);
  assert.match(read('../scripts/build-pwa.sh'), /web\/app\/palettes\.css/);
});
