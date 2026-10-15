// The results page's colours (patches/shiori/search.css) are copied by hand
// from the app's palette (HisterKit's Theme.swift, which has its own test).
// These hold the page to the same rule: text at least 4.5:1 (WCAG AA) on
// what it sits on, in both themes.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const css = readFileSync(new URL('../patches/shiori/search.css', import.meta.url), 'utf8');

function block(selector) {
  const start = css.indexOf(selector);
  assert.ok(start >= 0, `no ${selector} block`);
  const body = css.slice(css.indexOf('{', start) + 1, css.indexOf('}', start));
  return Object.fromEntries([...body.matchAll(/--([\w-]+):\s*(#[0-9a-f]{6})/gi)].map((m) => [m[1], m[2]]));
}

function luminance(hex) {
  const c = [1, 3, 5]
    .map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}
function ratio(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

const themes = { night: block(':root {'), day: block(':root[data-theme="day"]') };
const TEXT = ['text', 'secondary', 'accent', 'kept', 'visited', 'tab-general', 'tab-images', 'tab-videos', 'tab-news', 'notes', 'konbini', 'niwa', 'web', 'obsidian', 'smallweb', 'opened'];

for (const [name, v] of Object.entries(themes)) {
  test(`${name}: every text colour is at least 4.5:1 on the page and on cards`, () => {
    for (const fg of TEXT) {
      for (const bg of ['bg', 'card']) {
        const r = ratio(v[fg], v[bg]);
        assert.ok(r >= 4.5, `--${fg} ${v[fg]} on --${bg} ${v[bg]} is ${r.toFixed(2)}:1`);
      }
    }
  });

  test(`${name}: a selected category pill's text (the page colour on the tab's) is at least 4.5:1`, () => {
    for (const tab of ['accent', 'kept', 'notes', 'web', 'smallweb', 'tab-general', 'tab-images', 'tab-videos', 'tab-news', 'opened']) {
      const r = ratio(v.bg, v[tab]);
      assert.ok(r >= 4.5, `--bg on --${tab} is ${r.toFixed(2)}:1`);
    }
  });
}

test('the two copies of Tokyo Night Day (system light, and chosen) are the same', () => {
  assert.deepEqual(block(':root:not([data-theme="night"])'), themes.day);
});

// Tinted cards (your pages blue, notes orange, opened slate): the tint mixed
// into the card at the theme's --tint-mix must leave every text colour,
// chips included, at 4.5:1 or better.
function tintMix(selector) {
  const start = css.indexOf(selector);
  const body = css.slice(css.indexOf('{', start) + 1, css.indexOf('}', start));
  const m = body.match(/--tint-mix:\s*(\d+)%/);
  assert.ok(m, `no --tint-mix in ${selector}`);
  return Number(m[1]) / 100;
}
// Every card's tint: pages, notes, media, files, code, Small Web, opened.
const CARD_TINTS = ['accent', 'notes', 'tab-news', 'kept', 'tab-videos', 'smallweb', 'opened'];
function mix(a, b, p) {
  const ch = (h, i) => parseInt(h.slice(i, i + 2), 16);
  return '#' + [1, 3, 5].map((i) => Math.round(ch(a, i) * p + ch(b, i) * (1 - p)).toString(16).padStart(2, '0')).join('');
}
for (const [name, selector] of [['night', ':root {'], ['day', ':root[data-theme="day"]']]) {
  test(`${name}: text on a tinted card is at least 4.5:1`, () => {
    const v = themes[name];
    const p = tintMix(selector);
    for (const tint of CARD_TINTS) {
      const bg = mix(v[tint], v.card, p);
      for (const fg of TEXT) {
        const r = ratio(v[fg], bg);
        assert.ok(r >= 4.5, `--${fg} on --card with ${p * 100}% --${tint} is ${r.toFixed(2)}:1`);
      }
    }
  });
}

// The web app's own surfaces (web/app/app.css, the Machiya rooms' over the
// search page's tokens): the same rule on its cards, tinted or not.
const appCSS = readFileSync(new URL('../web/app/app.css', import.meta.url), 'utf8');
function appBlock(selector) {
  const start = appCSS.indexOf(selector);
  assert.ok(start >= 0, `no ${selector} block in app.css`);
  const body = appCSS.slice(appCSS.indexOf('{', start) + 1, appCSS.indexOf('}', start));
  return Object.fromEntries([...body.matchAll(/--([\w-]+):\s*(#[0-9a-f]{6})/gi)].map((m) => [m[1], m[2]]));
}
const appThemes = {
  night: { ...themes.night, ...appBlock(':root {') },
  day: { ...themes.day, ...appBlock(':root[data-theme="day"]') },
};

test("the web app's two copies of Day (system light, and chosen) are the same", () => {
  assert.deepEqual(appBlock(':root:not([data-theme="night"])'), appBlock(':root[data-theme="day"]'));
});

for (const [name, selector] of [['night', ':root {'], ['day', ':root[data-theme="day"]']]) {
  test(`web app, ${name}: every text colour is at least 4.5:1 on the page, on cards and on tinted cards`, () => {
    const v = appThemes[name];
    const p = tintMix(selector);
    for (const fg of [...TEXT, 'danger']) {
      for (const bg of [v.bg, v.card, ...CARD_TINTS.map((t) => mix(v[t], v.card, p))]) {
        const r = ratio(v[fg], bg);
        assert.ok(r >= 4.5, `--${fg} ${v[fg]} on ${bg} is ${r.toFixed(2)}:1`);
      }
    }
  });
}

test("the web app's Night surfaces are the rooms' Tokyo Night", () => {
  const n = appThemes.night;
  assert.deepEqual([n.bg, n.card, n.raised, n.line, n.line2, n.obsidian], ['#1a1b26', '#16161e', '#292e42', '#232433', '#33395a', '#73daca']);
  const d = appThemes.day;
  assert.deepEqual([d.bg, d.raised, d.line, d.line2], ['#e1e2e7', '#d0d5e3', '#c4c8da', '#aab1cb']);
});

test("the installed app's bar colours are the rooms' (#16161e Night, #d0d5e3 Day)", () => {
  const html = readFileSync(new URL('../web/app/index.html', import.meta.url), 'utf8');
  assert.match(html, /<meta name="theme-color" content="#16161e" media="\(prefers-color-scheme: dark\)" \/>/);
  assert.match(html, /<meta name="theme-color" content="#d0d5e3" media="\(prefers-color-scheme: light\)" \/>/);
  const manifest = JSON.parse(readFileSync(new URL('../web/app/manifest.webmanifest', import.meta.url), 'utf8'));
  assert.equal(manifest.theme_color, '#16161e');
  assert.equal(manifest.background_color, '#1a1b26');
});

// The wordmark in the header is the accent colour (the rooms' header), and
// its hover shade, on the frosted header, which is the page's colour.
for (const [name, v] of Object.entries(themes)) {
  test(`${name}: the header's wordmark, accent and its hover shade, is at least 4.5:1 on the frosted header`, () => {
    for (const fg of ['accent', 'accent-hover']) {
      const r = ratio(v[fg], v.bg);
      assert.ok(r >= 4.5, `--${fg} on --bg is ${r.toFixed(2)}:1`);
    }
  });
}

// Over a background (patches/shiori/backgrounds.css): a dark theme's glass is its panel's colour at --glass-mix over
// what's behind, dimmed by the filter's brightness and blurred. Text on it stays 4.5:1 against the brightest a scene
// gets under that blur (measured in Chrome at 1280×800 and 390×844, every scene: the frost's 20px blur and 180%
// saturation over bg.js's canvas) and against white, your own picture or video at its brightest. A light theme's glass
// is solid. The web app's and the search page's glass are only these two variables, never a translucency of their own.
const bgCSS = readFileSync(new URL('../patches/shiori/backgrounds.css', import.meta.url), 'utf8');
const BRIGHTEST_UNDER_GLASS = ['#d97750', '#9a948e', '#7562c4', '#847db2', '#6b81a0', '#757c8c', '#ea42a8', '#797b81', '#19b078',
  '#5a72c9', '#4d7660', '#a49f93', '#53a17d', '#91868b', '#3a709f', '#875b99', '#11bc90', '#34688f', '#aeaba8', '#aea299', '#ffffff'];
test('over a background, glass: text stays 4.5:1 in every dark theme, and a light theme\'s glass is solid', async () => {
  const root = bgCSS.match(/^:root \{ --glass-mix: (\d+)%; --glass-filter: ([^;]+);[^}]*\}/m);
  assert.ok(root, 'backgrounds.css sets --glass-mix and --glass-filter on :root');
  const alpha = Number(root[1]) / 100;
  const k = Number(root[2].match(/brightness\(([\d.]+)\)/)[1]);
  assert.match(root[2], /blur\(20px\) saturate\(180%\) brightness/, 'the blur and saturation the brightest colours were measured under');
  for (const light of [':root:not([data-theme="night"]) {', ':root[data-theme="day"] {', ':root:root {']) {
    const i = bgCSS.indexOf(light);
    assert.ok(i >= 0, light);
    assert.match(bgCSS.slice(i, bgCSS.indexOf('}', i)), /--glass-mix: 100%; --glass-filter: none;/, light);
  }
  const { variant } = await import('./palettes.mjs');
  const table = JSON.parse(readFileSync(new URL('../web/app/palettes.json', import.meta.url), 'utf8'));
  const dim = (hex, f) => '#' + [1, 3, 5].map((i) => Math.round(parseInt(hex.slice(i, i + 2), 16) * f).toString(16).padStart(2, '0')).join('');
  const darks = [['search.css Tokyo Night', themes.night], ['app.css Tokyo Night', appThemes.night],
    ...Object.entries(table).map(([key, p]) => [key, variant(p.dark, 'dark')])];
  for (const [name, v] of darks) {
    for (const surface of ['bg', 'card']) {
      for (const behind of BRIGHTEST_UNDER_GLASS) {
        const glass = mix(v[surface], dim(behind, k), alpha);
        for (const fg of TEXT.filter((t) => v[t])) {
          const r = ratio(v[fg], glass);
          assert.ok(r >= 4.5, `${name}: --${fg} on --${surface} glass over ${behind} is ${r.toFixed(2)}:1`);
        }
      }
    }
  }
  // While the background moves there is no filter: the panel is mixed with black at 1 - the brightness, which lets
  // the same share through (the panel's half, then (1 - alpha) * k of what's behind), so the check above holds it.
  assert.match(bgCSS, /^:root \{[^}]*--glass-under: transparent; \}/m);
  const moving = bgCSS.match(/^html\.bg-moving \{ --glass-filter: none; --glass-under: rgb\(0 0 0 \/ ([\d.]+)\); \}/m);
  assert.ok(moving, 'html.bg-moving drops the filter and dims with black');
  assert.equal(Number(moving[1]), Number((1 - k).toFixed(2)), 'black at 1 - the brightness');
  assert.match(bgCSS, /^html\.bg-moving \{ --frost: color-mix\(in srgb, var\(--bg\) var\(--glass-mix\), var\(--glass-under\)\); --frost-filter: none; \}/m,
    'the frosted bars inside the glass take its fill');
  // Every glass surface in the pages is these variables, filter and colour together.
  for (const file of ['../web/app/app.css', '../patches/shiori/search.css']) {
    const css = readFileSync(new URL(file, import.meta.url), 'utf8');
    const rules = [...css.matchAll(/([^{}]+)\{([^{}]*var\(--glass-mix\)[^{}]*)\}/g)];
    assert.ok(rules.length >= 2, `${file}: glass rules`);
    for (const [, sel, body] of rules) {
      assert.match(body, /color-mix\(in srgb, var\(--(bg|card)\) var\(--glass-mix\), var\(--glass-under\)\)/, `${file} ${sel.trim()}`);
      assert.match(body, /-webkit-backdrop-filter: var\(--glass-filter\); backdrop-filter: var\(--glass-filter\);/, `${file} ${sel.trim()}`);
    }
  }
});
