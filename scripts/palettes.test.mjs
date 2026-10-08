// The web app's ten themes (scripts/palettes.mjs, web/app/palettes.css): the
// rooms' table, every variant as readable as Tokyo Night is here, and the app
// and search-core knowing the same ten.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { TABLE_PATH, CSS_PATH, SWIFT_PATH, TEXT, TINTS, PILLS, css, swift, bars, variant, roomsShadow, ratio, mix, luminance } from './palettes.mjs';

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

test("the settings' whitelist knows the same ten: SharedSettings.palettes", () => {
  const keys = Object.keys(table);
  const list = (text, pattern) => [...text.match(pattern)[1].matchAll(/["']([a-z-]+)["']/g)].map((m) => m[1]);
  assert.deepEqual(list(read('../Shared/Settings/SharedSettings.swift'), /static let palettes = \[([^\]]*)\]/), keys);
});

test('tinted heading rows and panels (Pages, Notes, Web, AI Answer, Info) read at 4.5:1 at --tint-mix', () => {
  for (const [key, p] of Object.entries(table)) {
    for (const mode of ['dark', 'light']) {
      const v = variant(p[mode], mode);
      for (const tint of ['accent', 'notes', 'web', 'tab-general']) {
        const surface = mix(v[tint], v.card, v['tint-mix'] / 100);
        for (const fg of [tint, 'text', 'secondary', 'accent']) {
          const r = ratio(v[fg], surface);
          assert.ok(r >= 4.5, `${key} ${mode}: --${fg} on --${tint} at --tint-mix is ${r.toFixed(2)}:1`);
        }
      }
    }
  }
  // Never stronger than that: at 12% they fell under it.
  for (const rel of ['../patches/shiori/search.css', '../web/app/app.css']) assert.doesNotMatch(read(rel), /var\(--tint\) 12%/, rel);
});

test("the Rooms menu's text reads at 4.5:1 on the rooms' panel and current row, every variant", () => {
  for (const [key, p] of Object.entries(table)) {
    for (const mode of ['dark', 'light']) {
      const v = variant(p[mode], mode);
      assert.equal(v['rooms-bg'], p[mode].dark, key);
      assert.equal(v['rooms-on'], p[mode].hl, key);
      for (const fg of ['rooms-text', 'rooms-muted']) {
        for (const bg of ['rooms-bg', 'rooms-on']) {
          const r = ratio(v[fg], v[bg]);
          assert.ok(r >= 4.5, `${key} ${mode}: --${fg} ${v[fg]} on --${bg} ${v[bg]} is ${r.toFixed(2)}:1`);
        }
      }
    }
  }
});

test("search.css's Tokyo Night has the generator's Rooms menu colours", () => {
  const css = read('../patches/shiori/search.css');
  const block = (selector) => {
    const at = css.indexOf(selector);
    return css.slice(css.indexOf('{', at) + 1, css.indexOf('}', at));
  };
  const tokens = (body) => Object.fromEntries([...body.matchAll(/--(rooms-[\w-]+):\s*([^;]+);/g)].map((m) => [m[1], m[2].trim()]));
  const want = (mode) => {
    const v = variant(table['tokyo-night'][mode], mode);
    return { 'rooms-bg': v['rooms-bg'], 'rooms-on': v['rooms-on'], 'rooms-text': v['rooms-text'], 'rooms-muted': v['rooms-muted'], 'rooms-shadow': roomsShadow(v, mode === 'light') };
  };
  assert.deepEqual(tokens(block(':root {')), want('dark'));
  assert.deepEqual(tokens(block(':root:not([data-theme="night"]) {')), want('light'));
  assert.deepEqual(tokens(block(':root[data-theme="day"] {')), want('light'));
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
  assert.match(app, /choice\('theme', 'Mode', \[\['system', 'System'\], \['day', 'Light'\], \['night', 'Dark'\]\]\)/);
  assert.match(app, /document\.documentElement\.dataset\.palette = palette/);
  // The palette follows the person through the account (S.accountValues).
  assert.match(app, /S\.accountValues\(settings, \{ steps: 'rooms' \}\)/);
  assert.match(read('../web/app/index.html'), /<link rel="stylesheet" href="\/_shiori\/palettes\.css" \/>/);
  assert.match(read('../web/app/sw.js'), /'\/_shiori\/palettes\.css'/);
  assert.match(read('../scripts/build-pwa.sh'), /web\/app\/palettes\.css/);
});

test('a hovered pill reads on --raised: every theme, every pill (--<pill>-raised; the apps\' tintOnRaised)', () => {
  for (const [key, p] of Object.entries(table)) {
    for (const mode of ['dark', 'light']) {
      const v = variant(p[mode], mode);
      for (const t of PILLS) assert.ok(ratio(v[`${t}-raised`], v.raised) >= 4.5, `${key} ${mode} ${t}: ${v[`${t}-raised`]} on ${v.raised}`);
    }
  }
  // search.css's Tokyo Night carries the generator's, and they read on its own --raised.
  const css = read('../patches/shiori/search.css');
  const block = (selector) => {
    const at = css.indexOf(selector);
    return css.slice(css.indexOf('{', at) + 1, css.indexOf('}', at));
  };
  for (const [selector, mode] of [[':root {', 'dark'], [':root:not([data-theme="night"]) {', 'light'], [':root[data-theme="day"] {', 'light']]) {
    const body = block(selector);
    const tokens = Object.fromEntries([...body.matchAll(/--([\w-]+):\s*([^;]+);/g)].map((m) => [m[1], m[2].trim()]));
    const v = variant(table['tokyo-night'][mode], mode);
    for (const t of PILLS) {
      assert.equal(tokens[`${t}-raised`], v[`${t}-raised`], `${selector} ${t}-raised`);
      assert.ok(ratio(tokens[`${t}-raised`], tokens.raised) >= 4.5, `${selector} ${t}-raised on ${tokens.raised}`);
    }
  }
});
