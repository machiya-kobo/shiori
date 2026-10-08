// The web app's themes: the Machiya rooms' ten palettes (vaultkit/palettes.py
// in machiya), each dark and light, in the web app's own tokens.
//
// web/app/palettes.json is the rooms' table as vaultkit makes it readable
// (refresh it from a machiya checkout:
//   python3 -c "from vaultkit import palettes as P; import json; print(json.dumps({k: {'name': P.PALETTES[k][0], 'dark': P.variant(k, 'dark'), 'light': P.variant(k, 'light')} for k in P.PALETTES}, indent=1, ensure_ascii=False))" > web/app/palettes.json
// ), and web/app/palettes.css and the apps' Packages/HisterKit/Sources/
// HisterKit/Palettes.swift are made from it here:
//   node scripts/palettes.mjs
// Tokyo Night stays as search.css and app.css have it (no data-palette); the
// others key off <html data-palette="…">, data-theme choosing the variant as
// before. The web app holds text to more than the rooms do (4.5:1 on cards
// and tinted cards too, scripts/theme-contrast.test.mjs), so a colour short of
// that moves in lightness only, never hue, until it isn't.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const TEXT = ['text', 'secondary', 'accent', 'kept', 'visited', 'tab-general', 'tab-images', 'tab-videos', 'tab-news',
  'notes', 'konbini', 'niwa', 'web', 'obsidian', 'smallweb', 'danger'];
// The tinted surfaces text sits on: cards (Pages, Notes, Opened), and the
// heading rows and panels (Web; AI Answer and Info wear All's tab-general).
// Every tinted surface: the cards (pages, notes, opened, files, code, Small
// Web) and the heading rows and panels (All, Web).
export const TINTS = ['accent', 'notes', 'tab-news', 'tab-general', 'web', 'kept', 'tab-videos', 'smallweb'];
// The pills' colours: under the pointer a pill lifts onto --<pill>-hover-bg
// (24% of its colour over --raised), its text moved to --<pill>-hover, the
// shade that reads at 4.5:1 there (the apps' Palette.pillHover, twins).
export const HOVER_MIX = 0.24;
export const PILLS = ['tab-general', 'accent', 'notes', 'web', 'tab-images', 'tab-videos', 'tab-news', 'smallweb', 'kept'];

function rgb(hex) { return [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255); }
function hex(c) { return '#' + c.map((v) => Math.round(Math.min(1, Math.max(0, v)) * 255).toString(16).padStart(2, '0')).join(''); }
export function luminance(h) {
  const c = rgb(h).map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}
export function ratio(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}
export function mix(a, b, p) {
  const ch = (h, i) => parseInt(h.slice(i, i + 2), 16);
  return '#' + [1, 3, 5].map((i) => Math.round(ch(a, i) * p + ch(b, i) * (1 - p)).toString(16).padStart(2, '0')).join('');
}

// HSL lightness, as Python's colorsys.rgb_to_hls (vaultkit does the same)
function toHls([r, g, b]) {
  const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2;
  if (max === min) return [0, l, 0];
  const d = max - min, s = l <= 0.5 ? d / (max + min) : d / (2 - max - min);
  const h = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [((h / 6) + 1) % 1, l, s];
}
function fromHls([h, l, s]) {
  if (s === 0) return [l, l, l];
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
  const f = (t) => { t = (t + 1) % 1; return t < 1 / 6 ? p + (q - p) * 6 * t : t < 1 / 2 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p; };
  return [f(h + 1 / 3), f(h), f(h - 1 / 3)];
}
export function readableOn(colour, surfaces, light) {
  const ok = (c) => surfaces.every((s) => ratio(c, s) >= 4.5);
  if (ok(colour)) return colour;
  const [h, l0, s] = toHls(rgb(colour));
  for (let l = l0; l >= 0 && l <= 1; l += light ? -0.005 : 0.005) {
    const out = hex(fromHls([h, l, s]));
    if (ok(out)) return out;
  }
  return light ? '#000000' : '#ffffff';
}

/** One variant of a palette in the web app's tokens (room: the rooms' tokens, mode 'dark' | 'light'). */
export function variant(room, mode) {
  const light = mode === 'light';
  const v = {
    bg: room.bg, card: light ? room.hl : room.dark, raised: light ? room.dark : room.hl, line: room.line, line2: room.line2,
    text: room.fg, secondary: room.fg2, accent: room.blue, hit: room.yellow, kept: room.green, visited: room.cyan,
    'tab-general': room.cyan, 'tab-images': room.green, 'tab-videos': room.red, 'tab-news': room.magenta,
    notes: room.orange, konbini: room.magenta, niwa: room.green, web: room.yellow, obsidian: room.teal, smallweb: room.teal,
    danger: room.red, 'tint-mix': light ? 8 : 9,
  };
  for (let pass = 0; pass < 6; pass++) {                      // the tints follow the colours they're made of
    const surfaces = [v.bg, v.card, ...TINTS.map((t) => mix(v[t], v.card, v['tint-mix'] / 100))];
    let changed = false;
    for (const t of [...TEXT, 'hit']) {
      const next = readableOn(v[t], surfaces, light);
      if (next !== v[t]) { v[t] = next; changed = true; }
    }
    if (!changed) break;
  }
  ['accent', 'visited', 'konbini', 'kept', 'notes', 'danger', 'hit', 'obsidian']
    .forEach((t, i) => { v[`chip${i}`] = v[t]; });
  for (const t of PILLS) {
    v[`${t}-hover-bg`] = mix(v[t], v.raised, HOVER_MIX);
    v[`${t}-hover`] = readableOn(v[t], [v[`${t}-hover-bg`]], light);
  }
  // The Rooms menu, as the rooms draw it (vaultkit's switcher): their --dark
  // panel, the current row on their --hl, in either variant. Its text is
  // the rooms' --fg and its roles their --muted, each moved in lightness
  // only until 4.5:1 on both (vaultkit's --menu-fg is the same: the rooms'
  // own fg is 3.99:1 in Tokyo Night Day).
  v['rooms-bg'] = room.dark;
  v['rooms-on'] = room.hl;
  v['rooms-text'] = readableOn(room.fg, [room.dark, room.hl], light);
  v['rooms-muted'] = readableOn(room.muted, [room.dark, room.hl], light);
  return v;
}

/** The rooms' second shadow (their --shadow-2): black in dark, the text's colour in light. */
export function roomsShadow(v, light) {
  const [r, g, b] = rgb(v.text).map((c) => Math.round(c * 255));
  return light ? `0 1px 2px rgb(${r} ${g} ${b} / 0.12), 0 6px 18px rgb(${r} ${g} ${b} / 0.12)` : '0 1px 2px rgb(0 0 0 / 0.35), 0 6px 18px rgb(0 0 0 / 0.25)';
}

function decl(v, light) {
  const [r, g, b] = rgb(v.hit).map((c) => Math.round(c * 255));
  const [sr, sg, sb] = rgb(v.text).map((c) => Math.round(c * 255));
  const rows = [
    ['bg', 'card', 'raised', 'line', 'line2'],
    ['text', 'secondary', 'accent', 'hit', 'kept', 'visited'],
    ['tab-general', 'tab-images', 'tab-videos', 'tab-news'],
    ['notes', 'konbini', 'niwa', 'web', 'obsidian', 'smallweb', 'danger'],
    ['chip0', 'chip1', 'chip2', 'chip3', 'chip4', 'chip5', 'chip6', 'chip7'],
    ['rooms-bg', 'rooms-on', 'rooms-text', 'rooms-muted'],
    PILLS.flatMap((t) => [`${t}-hover-bg`, `${t}-hover`]),
  ].map((keys) => keys.map((k) => `--${k}: ${v[k]};`).join(' '));
  rows.push(`--rooms-shadow: ${roomsShadow(v, light)};`);
  rows.push(`--highlight: rgb(${r} ${g} ${b} / ${light ? '0.22' : '0.30'}); --tint-mix: ${v['tint-mix']}%;`);
  rows.push(light ? `--shadow: 0 1px 2px rgb(${sr} ${sg} ${sb} / 0.12); color-scheme: light;` : '--shadow: 0 1px 2px rgb(0 0 0 / 0.35); color-scheme: dark;');
  return rows;
}
function block(selector, rows, indent = '') {
  return `${indent}${selector} {\n${rows.map((r) => `${indent}  ${r}`).join('\n')}\n${indent}}\n`;
}

/** web/app/palettes.css from the table. */
export function css(table) {
  let out = '/* Generated by scripts/palettes.mjs from web/app/palettes.json (the Machiya rooms\' themes): edit those, not this. */\n';
  for (const [key, p] of Object.entries(table)) {
    if (key === 'tokyo-night') continue;                       // search.css and app.css have it
    const dark = decl(variant(p.dark, 'dark'), false), light = decl(variant(p.light, 'light'), true);
    const at = `:root[data-palette="${key}"]`;
    out += `/* ${p.name} */\n` + block(at, dark) + block(`${at}[data-theme="day"]`, light)
      + `@media (prefers-color-scheme: light) {\n${block(`${at}:not([data-theme="night"])`, light, '  ')}}\n`;
  }
  return out;
}

/** {key: {name, night, day}}: the names and the browser bar's colours (the rooms' --dark), for the app. */
export function bars(table) {
  return Object.fromEntries(Object.entries(table).map(([k, p]) => [k, { name: p.name, night: p.dark.dark, day: p.light.dark }]));
}

/**
 * Packages/HisterKit/Sources/HisterKit/Palettes.swift from the table: the
 * same variants as palettes.css, in the apps' Palette (surface is the web's
 * card; chips are chip0…7, the order Palette.Tint names). Their cards are
 * tinted as the web's are (`--tint-mix` over the card), so the colours stay
 * the rooms'. Tokyo Night stays as Theme.swift has it.
 */
export function swift(table) {
  const h = (c) => '0x' + c.slice(1).toUpperCase();
  const pal = (v, light) => {
    const chips = [0, 1, 2, 3, 4, 5, 6, 7].map((i) => h(v[`chip${i}`])).join(', ');
    return `Palette(
                hex: Palette.Hex(
                    background: ${h(v.bg)}, surface: ${h(v.card)}, raised: ${h(v.raised)},
                    text: ${h(v.text)}, secondaryText: ${h(v.secondary)}, accent: ${h(v.accent)},
                    highlight: ${h(v.hit)}, danger: ${h(v.danger)},
                    chips: [${chips}]),
                highlightOpacity: ${light ? '0.22' : '0.30'}, isDark: ${!light}, tintOpacity: ${v['tint-mix'] / 100}, tintsOverSurface: true)`;
  };
  let out = `// Generated by scripts/palettes.mjs from web/app/palettes.json (the Machiya
// rooms' themes): edit those, not this.

extension AppPalette {
    /// Every theme but Tokyo Night, as web/app/palettes.css has them.
    static let generated: [AppPalette] = [
`;
  for (const [key, p] of Object.entries(table)) {
    if (key === 'tokyo-night') continue;
    out += `        AppPalette(
            key: "${key}", name: "${p.name}",
            dark: ${pal(variant(p.dark, 'dark'), false)},
            light: ${pal(variant(p.light, 'light'), true)}),
`;
  }
  return out + '    ]\n}\n';
}

export const TABLE_PATH = new URL('../web/app/palettes.json', import.meta.url);
export const CSS_PATH = new URL('../web/app/palettes.css', import.meta.url);
export const SWIFT_PATH = new URL('../Packages/HisterKit/Sources/HisterKit/Palettes.swift', import.meta.url);

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const table = JSON.parse(readFileSync(TABLE_PATH, 'utf8'));
  writeFileSync(CSS_PATH, css(table));
  writeFileSync(SWIFT_PATH, swift(table));
}
