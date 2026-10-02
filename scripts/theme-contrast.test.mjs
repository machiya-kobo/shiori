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
const TEXT = ['text', 'secondary', 'accent', 'kept', 'visited', 'tab-general', 'tab-images', 'tab-videos', 'tab-news', 'notes', 'konbini', 'niwa', 'web', 'obsidian', 'smallweb'];

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
    for (const tab of ['accent', 'kept', 'notes', 'web', 'smallweb', 'tab-general', 'tab-images', 'tab-videos', 'tab-news']) {
      const r = ratio(v.bg, v[tab]);
      assert.ok(r >= 4.5, `--bg on --${tab} is ${r.toFixed(2)}:1`);
    }
  });
}

test('the two copies of Tokyo Night Day (system light, and chosen) are the same', () => {
  assert.deepEqual(block(':root:not([data-theme="night"])'), themes.day);
});

// Tinted cards (your pages blue, notes orange, opened purple): the tint mixed
// into the card at the theme's --tint-mix must leave every text colour,
// chips included, at 4.5:1 or better.
function tintMix(selector) {
  const start = css.indexOf(selector);
  const body = css.slice(css.indexOf('{', start) + 1, css.indexOf('}', start));
  const m = body.match(/--tint-mix:\s*(\d+)%/);
  assert.ok(m, `no --tint-mix in ${selector}`);
  return Number(m[1]) / 100;
}
function mix(a, b, p) {
  const ch = (h, i) => parseInt(h.slice(i, i + 2), 16);
  return '#' + [1, 3, 5].map((i) => Math.round(ch(a, i) * p + ch(b, i) * (1 - p)).toString(16).padStart(2, '0')).join('');
}
for (const [name, selector] of [['night', ':root {'], ['day', ':root[data-theme="day"]']]) {
  test(`${name}: text on a tinted card is at least 4.5:1`, () => {
    const v = themes[name];
    const p = tintMix(selector);
    for (const tint of ['accent', 'notes', 'tab-news']) {
      const bg = mix(v[tint], v.card, p);
      for (const fg of TEXT) {
        const r = ratio(v[fg], bg);
        assert.ok(r >= 4.5, `--${fg} on --card with ${p * 100}% --${tint} is ${r.toFixed(2)}:1`);
      }
    }
  });
}
