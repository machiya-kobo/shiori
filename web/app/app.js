// Shiori as a web app: the native app's Library (All · Pages · Notes ·
// Opened) with its search field on top (All · Pages · Notes · Web, live as
// you type), Sort · Group · Filter, Labels and collections, the preview,
// label and delete, Export & Feed, and Settings (this browser's own). It looks and works as the apps do; the apps are the reference.
// No build step: modules and the DOM. `window.ShioriSearch` (search-core.js,
// shared with the search page) has the note and link rules.

import * as api from './api.js';

const S = window.ShioriSearch;
const $ = (id) => document.getElementById(id);
const wide = () => matchMedia('(min-width: 1100px)').matches;
const sidebarShown = () => matchMedia('(min-width: 760px)').matches;

// --- Small things ----------------------------------------------------------------

function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === undefined || v === null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'style') el.setAttribute('style', v);
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const child of children.flat()) {
    if (child === null || child === undefined || child === false) continue;
    el.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return el;
}

const ICONS = {
  back: '<path d="M15 18l-6-6 6-6"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.6 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.6a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>',
  library: '<path d="M4 4h4v16H4zM10 4h4v16h-4zM16 5l4 1-3 14-4-1z"/>',
  tag: '<path d="M20.6 13.4L13.4 20.6a2 2 0 0 1-2.8 0L3 13V3h10l7.6 7.6a2 2 0 0 1 0 2.8z"/><circle cx="7.5" cy="7.5" r="1.5"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/>',
  globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
  note: '<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6M8 13h8M8 17h6"/>',
  open: '<circle cx="12" cy="12" r="9"/><path d="M15.5 8.5l-2.2 5-5 2.2 2.2-5z"/>',
  share: '<path d="M12 3v12M7 8l5-5 5 5"/><path d="M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7"/>',
  more: '<circle cx="5" cy="12" r="1.2"/><circle cx="12" cy="12" r="1.2"/><circle cx="19" cy="12" r="1.2"/>',
  stack: '<path d="M4 7h16M6 4h12M4 7v12a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1V7"/>',
  close: '<path d="M6 6l12 12M18 6L6 18"/>',
  // Collections (S.collectionIcon), matching the app's SF Symbols.
  palette: '<path d="M12 3a9 9 0 1 0 0 18c1.1 0 1.7-.9 1.2-1.8-.6-1-.1-2.2 1.1-2.2H17a4 4 0 0 0 4-4c0-5.5-4-10-9-10z"/><circle cx="7.5" cy="11" r="1"/><circle cx="10" cy="7" r="1"/><circle cx="15" cy="7.5" r="1"/>',
  controller: '<path d="M6 8h12a4 4 0 0 1 4 4v1a3 3 0 0 1-5.4 1.8L15 13H9l-1.6 1.8A3 3 0 0 1 2 13v-1a4 4 0 0 1 4-4z"/><path d="M7 11v3M5.5 12.5h3"/><circle cx="16" cy="11" r=".6"/><circle cx="18" cy="12.8" r=".6"/>',
  helm: '<circle cx="12" cy="12" r="6"/><circle cx="12" cy="12" r="2"/><path d="M12 2v4M12 18v4M2 12h4M18 12h4M4.9 4.9l2.8 2.8M16.3 16.3l2.8 2.8M4.9 19.1l2.8-2.8M16.3 7.7l2.8-2.8"/>',
  bookmark: '<path d="M6 3h12v18l-6-4-6 4z"/>',
  cpu: '<rect x="6" y="6" width="12" height="12" rx="2"/><rect x="9.5" y="9.5" width="5" height="5"/><path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>',
  book: '<path d="M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2z"/><path d="M4 19V5M8 7h7"/>',
  music: '<path d="M9 18V5l11-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="17" cy="16" r="3"/>',
  food: '<path d="M7 2v8M5 2v5a2 2 0 0 0 4 0V2M7 10v12M17 2c-2 2-2 6 0 8v12"/>',
  travel: '<path d="M2 16l20-8-3-2-8 3-5-3-2 1 4 4-4 2z"/><path d="M4 21h16"/>',
  work: '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M9 7V5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2M3 13h18"/>',
  film: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 4v16M17 4v16M3 9h4M3 15h4M17 9h4M17 15h4"/>',
  heart: '<path d="M12 20s-7-4.4-9-9a5 5 0 0 1 9-3 5 5 0 0 1 9 3c-2 4.6-9 9-9 9z"/>',
  server: '<rect x="4" y="3" width="16" height="7" rx="1.5"/><rect x="4" y="14" width="16" height="7" rx="1.5"/><path d="M8 6.5h.01M8 17.5h.01"/>',
  shield: '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><rect x="9.5" y="10" width="5" height="4" rx="1"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  terminal: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 9l3 3-3 3M12 15h5"/>',
  wrench: '<path d="M14.5 6.5a4 4 0 0 0 5 5L12 19a2 2 0 0 1-3-3l7.5-7.5a4 4 0 0 0-2-2z"/><path d="M4 20l3-3"/>',
  masks: '<path d="M4 5h9v5a4.5 4.5 0 0 1-9 0z"/><path d="M11 12h9v5a4.5 4.5 0 0 1-9 0"/><path d="M6.5 8h.01M10.5 8h.01M14 15h.01M17.5 15h.01"/>',
  leaf: '<path d="M5 19c0-8 5-13 15-14-1 10-6 15-14 15"/><path d="M5 19l8-8"/>',
  // Kura (read a note on the web): an open book, not an archive box, which
  // reads as "archive this" elsewhere.
  openbook: '<path d="M12 6c-2-1.5-5-2-8-1.5V19c3-.5 6 0 8 1.5 2-1.5 5-2 8-1.5V4.5C17 4 14 4.5 12 6z"/><path d="M12 6v14.5"/>',
  columns: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M9 4v16M15 4v16"/>',
  sort: '<path d="M7 4v16M3 8l4-4 4 4M17 20V4M13 16l4 4 4-4"/>',
  group: '<rect x="3" y="4" width="8" height="7" rx="1.5"/><rect x="13" y="4" width="8" height="16" rx="1.5"/><rect x="3" y="13" width="8" height="7" rx="1.5"/>',
  filter: '<circle cx="12" cy="12" r="9"/><path d="M7.5 9h9M9.5 12.5h5M11 16h2"/>',
  chevron: '<path d="M9 6l6 6-6 6"/>',
  copy: '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>',
  refresh: '<path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 4v7h-7"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  sparkles: '<path d="M10 3l1.6 4.4L16 9l-4.4 1.6L10 15l-1.6-4.4L4 9l4.4-1.6z"/><path d="M18 14l.8 2.2L21 17l-2.2.8L18 20l-.8-2.2L15 17l2.2-.8z"/>',
};
function icon(name) {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('aria-hidden', 'true');
  svg.innerHTML = ICONS[name] || '';
  return svg;
}
/** replaceChildren, leaving out null and false (it would print "null"). */
function fill(el, ...children) {
  el.replaceChildren(...children.flat().filter((c) => c !== null && c !== undefined && c !== false));
  return el;
}

function iconButton(name, label, onclick) {
  return h('button', { class: 'icon-button', type: 'button', 'aria-label': label, title: label, onclick }, icon(name));
}

/** The app's colour for a label (search-core's hash, one of eight). */
const chipVar = (label) => `var(--chip${S.labelChipIndex(label)})`;
const chip = (label) => h('span', { class: 'chip', style: `--chip: ${chipVar(label)}` }, label);
/** A result's label tag: opens that label's pages (not the row it sits on). */
const labelTag = (label) =>
  h('button', {
    type: 'button', class: 'chip link-chip', style: `--chip: ${chipVar(label)}`, title: `Pages labelled ${label}`,
    onclick: (e) => (e.stopPropagation(), go('list', { q: `label:${label}`, t: label })),
    onkeydown: (e) => e.stopPropagation(),
  }, label);

/**
 * A note's chip names its vault ("Work vault"), since Notes mix vaults.
 * A click shows
 * Notes from that vault.
 */
const vaultTag = (url) => {
  const { name, text } = S.vaultChip(url, kuraVaults);
  return h('button', {
    type: 'button', class: 'chip link-chip', style: `--chip: ${chipVar(text)}`, title: name ? `Notes in ${text}` : 'A note',
    onclick: (e) => {
      e.stopPropagation();
      if (!name) return;
      changeSetting('notesVault', name);
      const { view, params } = route();
      if (view === 'search') go('search', { q: params.get('q') || '', s: 'notes' });
      else go('library', { s: 'notes' });
    },
    onkeydown: (e) => e.stopPropagation(),
  }, text);
};

const relative = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' });
function ago(seconds) {
  if (!seconds) return '';
  const diff = seconds - Date.now() / 1000;
  const units = [['year', 31536000], ['month', 2592000], ['week', 604800], ['day', 86400], ['hour', 3600], ['minute', 60]];
  for (const [unit, size] of units) if (Math.abs(diff) >= size) return relative.format(Math.round(diff / size), unit);
  return 'just now';
}

/** Hister's snippet HTML, keeping only <mark>: text everywhere else. */
function snippet(html) {
  const out = h('div', { class: 'snippet' });
  const doc = new DOMParser().parseFromString(`<div>${html || ''}</div>`, 'text/html');
  (function walk(node, into) {
    for (const child of node.childNodes) {
      if (child.nodeType === Node.TEXT_NODE) into.append(child.textContent);
      else if (child.nodeName === 'MARK') into.append(h('mark', {}, child.textContent));
      else walk(child, into);
    }
  })(doc.body.firstChild, out);
  return out;
}

function toast(text) {
  const t = h('div', { class: 'status', role: 'status', style: 'position:fixed;left:50%;bottom:90px;transform:translateX(-50%);background:var(--card);border:1px solid var(--line);border-radius:12px;padding:10px 16px;z-index:30' }, text);
  document.body.append(t);
  setTimeout(() => t.remove(), 2200);
}

async function copy(text) {
  try {
    await navigator.clipboard.writeText(text);
    toast('Link copied');
  } catch (_) {
    prompt('Copy the link:', text);
  }
}

// --- Settings: this browser's own (nothing is shared between devices) --------

const DEFAULTS = {
  theme: 'system', palette: 'tokyo-night', textSize: 'system', previewImages: true, rememberOpened: true, searchHistory: true,
  histerCount: 5, vaultCount: 3, webResults: true,
  // The build's SHIORI_OBSIDIAN_VAULT, else none.
  obsidianVault: fromBuild('__SHIORI_OBSIDIAN_VAULT__'),
  // The notes' homes, from the build (the server passes them in).
  niwaURL: fromBuild('__SHIORI_NIWA_URL__'), konbiniURL: fromBuild('__SHIORI_KONBINI_URL__'),
  foldRepeats: true, searchFilters: true, labelSuggestions: true, newsBlurURL: '', aiAnswer: true,
  showOpened: false, resultStyle: 'tint', smallWebTab: true, smallWebOpen: 'gateway',
  // Which of Kura's vaults the Notes lists search: 'all', or one's name.
  notesVault: 'all',
};
// Result Style back to Tint, once, whatever was saved before (the user's
// call, 0.5.0); a style chosen after that is kept.
if (!readLocal('shioriResultStyleReset')) {
  const saved = readLocal('shioriAppSettings');
  if (saved && saved.resultStyle) writeLocal('shioriAppSettings', { ...saved, resultStyle: 'tint' });
  writeLocal('shioriResultStyleReset', true);
}
let settings = { ...DEFAULTS, ...readLocal('shioriAppSettings') };
// The house's shared choices: theme and text size set in
// any Machiya room on this device count here too, and ours count there.
const HOUSE = S.houseSettings(document.cookie, { mine: settings.textSize, steps: 'rooms' });
if (HOUSE.theme) settings.theme = HOUSE.theme;
if (HOUSE.palette) settings.palette = HOUSE.palette;
if (HOUSE.textSize) settings.textSize = HOUSE.textSize;
let recents = readLocal('shioriAppRecents') || [];

/** A value the build stamps in, or '' when it wasn't. */
/** Where this build's source is (SHIORI_SOURCE_URL), if it says. */
const SOURCE_URL = S.sourceLink(fromBuild('__SHIORI_SOURCE_URL__'));

/**
 * Whether the build has the small-web gateway (SHIORI_SMALLWEB_URL; the
 * hosted pages reach it at /smallweb/): Add Page and the share target save
 * through it, so without it neither is offered.
 */
const SMALLWEB = fromBuild('__SHIORI_SMALLWEB_URL__') !== '';
/** The build's privacy front ends (SHIORI_FRONTENDS: Redlib, Invidious…), for a page's menu. */
const FRONTENDS = S.frontendInstances(fromBuild('__SHIORI_FRONTENDS__'));

function fromBuild(value) {
  return value.startsWith('__') ? '' : value;
}

function readLocal(key) {
  try {
    return JSON.parse(localStorage.getItem(key) || 'null');
  } catch (_) {
    return null;
  }
}
function writeLocal(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch (_) {}
}

function changeSetting(key, value, { fromKura = false } = {}) {
  settings = { ...settings, [key]: value };
  writeLocal('shioriAppSettings', settings);
  // Theme and text size are the house's too (the other rooms read them).
  const shared = S.houseCookie(key, value, location.hostname, { steps: 'rooms' });
  if (shared) document.cookie = shared;
  applyLook();
  // Signed in to Machiya: the rooms' copy follows (a choice made here wins
  // over Kura's answer still on its way).
  if (key === 'theme' || key === 'palette' || key === 'textSize') {
    if (!fromKura) lookChangedHere = true;
    if (!fromKura && kuraAccount.status === 200) pushPrefs();
  }
  if (key === 'searchHistory' && value === false) {
    recents = [];
    writeLocal('shioriAppRecents', recents);
  }
}

// The rooms' steps (machiya.css: 12, 13, 14, 15 and 16 px for Extra Small to
// Extra Large), so a size chosen here or in Kura looks the same in both and
// reads back as itself (S.houseSettings' `rooms` steps); Medium and the two
// largest are Shiori's own, between and beyond them.
const TEXT_SCALE = { xSmall: 12 / 14, small: 13 / 14, medium: 0.96, large: 15 / 14, xLarge: 16 / 14, xxLarge: 1.24, xxxLarge: 1.36 };
/**
 * Standard's scale: 1, or in Safari the system's text size (Dynamic Type)
 * over its default body size (17 px), read from the system body font. The
 * app's sizes are rem, so the root's size scales them all.
 */
function systemTextScale() {
  if (!(window.CSS && CSS.supports && CSS.supports('font', '-apple-system-body'))) return 1;
  const probe = h('span', { style: 'font: -apple-system-body; position: absolute; visibility: hidden' }, 'x');
  document.body.append(probe);
  const px = parseFloat(getComputedStyle(probe).fontSize) || 17;
  probe.remove();
  return px / 17;
}
function applyLook() {
  const theme = settings.theme === 'day' || settings.theme === 'night' ? settings.theme : '';
  if (theme) document.documentElement.dataset.theme = theme;
  else delete document.documentElement.dataset.theme;
  // The rooms' themes (palettes.css): Tokyo Night is the page's own colours.
  const palette = Object.hasOwn(S.PALETTES, settings.palette) ? settings.palette : 'tokyo-night';
  if (palette !== 'tokyo-night') document.documentElement.dataset.palette = palette;
  else delete document.documentElement.dataset.palette;
  // The browser's (and the installed app's) bar follows the chosen theme:
  // one colour for Night or Day, the system's pair for System.
  const metas = S.themeColorMetas(theme, palette);
  const shown = [...document.querySelectorAll('meta[name="theme-color"]')];
  if (shown.length !== metas.length || metas.some((m, i) => shown[i].content !== m.content || (shown[i].media || '') !== m.media)) {
    shown.forEach((m) => m.remove());
    const at = document.querySelector('meta[name="color-scheme"]');
    for (const m of metas.slice().reverse()) at.after(h('meta', { name: 'theme-color', content: m.content, media: m.media || undefined }));
  }
  // How your pages, notes and opened pages stand apart: app.css keys off it.
  document.body.dataset.resultStyle = ['tint', 'solid', 'bar', 'none'].includes(settings.resultStyle) ? settings.resultStyle : 'tint';
  document.documentElement.style.fontSize = `${Math.round(100 * (TEXT_SCALE[settings.textSize] || systemTextScale()))}%`;
}

// --- Theme and text size with the rooms (Kura's /api/prefs) ------------------------
// Signed in to Machiya, the rooms keep your theme and text size on the
// server (machiya.js): read on launch, replacing this device's when they
// differ and are values the house knows, and written on a change here.
// Any failure is silent; the cookies and this browser's copy stay.

/** Where you stand with Kura's sign-in: {status} from api.kuraPrefs (-1: not asked yet). */
let kuraAccount = { status: -1 };
let lookChangedHere = false;

function pushPrefs() {
  void api.putKuraPrefs({ theme: S.houseValue('theme', settings.theme) || 'system',
    palette: S.houseValue('palette', settings.palette) || 'tokyo-night',
    text_size: S.houseValue('textSize', settings.textSize, 'rooms') || 'standard' });
}

async function loadKuraAccount() {
  const { status, prefs } = await api.kuraPrefs();
  kuraAccount = { status };
  if (status !== 200 || lookChangedHere) return;
  const theme = prefs.theme === 'auto' ? 'system' : prefs.theme;
  if (['system', 'night', 'day'].includes(theme) && theme !== settings.theme) changeSetting('theme', theme, { fromKura: true });
  if (Object.hasOwn(S.PALETTES, prefs.palette) && prefs.palette !== settings.palette) changeSetting('palette', prefs.palette, { fromKura: true });
  const size = typeof prefs.text_size === 'string' && /^[a-z]+$/.test(prefs.text_size)
    ? S.houseSettings(`machiya_textSize=${prefs.text_size}`, { mine: settings.textSize, steps: 'rooms' }).textSize
    : undefined;
  if (size && size !== settings.textSize) changeSetting('textSize', size, { fromKura: true });
}

function recordSearch(q) {
  const query = q.trim();
  if (!settings.searchHistory || !query || query.length > 500) return;
  recents = [query, ...recents.filter((r) => r.toLowerCase() !== query.toLowerCase())].slice(0, 5);
  writeLocal('shioriAppRecents', recents);
}

// --- Rules (collections and labels) ----------------------------------------

let aliases = {};
let labels = [];
let collections = [];

async function loadRules() {
  try {
    aliases = await api.rules();
  } catch (_) {
    aliases = {};
  }
  const found = new Set();
  const byAlias = {};
  for (const [alias, expansion] of Object.entries(aliases)) {
    for (const m of String(expansion).matchAll(/label:\(([^)]*)\)|label:([A-Za-z0-9_-]+)/g)) {
      for (const name of (m[1] || m[2] || '').split('|').filter(Boolean)) {
        found.add(name);
        (byAlias[alias] ||= new Set()).add(name);
      }
    }
  }
  labels = [...found].sort();
  // Collections are "@" aliases only (S.isCollectionKeyword), and not one
  // that names every label: it'd group nothing.
  const all = Object.entries(byAlias).filter(([alias]) => S.isCollectionKeyword(alias));
  collections = all
    .filter(([, set]) => all.length === 1 || set.size < found.size)
    .map(([name, set]) => ({ name, labels: [...set].sort() }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

// --- Notes -----------------------------------------------------------------------

let konbiniCards = [];
/** Kura's vaults (/api/vaults), for the Notes filter and a work note's place. */
let kuraVaults = [];
function note(doc) {
  if (doc.label !== 'vault') return null;
  const path = S.notePath(doc.url, konbiniCards);
  // A work vault's note: its own vault's name and Obsidian vault, read in
  // Kura, never a Konbini card.
  const other = S.noteVault(doc.url);
  if (other) {
    const v = kuraVaults.find((x) => x.name === other);
    return {
      path,
      vault: other,
      place: path ? [v ? v.title : other, ...path.replace(/\.md$/, '').split('/')].join(' › ') : '',
      obsidian: S.obsidianURL(v ? v.obsidian || other : other, path),
      niwa: doc.url,
      konbini: null,
    };
  }
  const niwaBase = settings.niwaURL ? settings.niwaURL.replace(/\/?$/, '/') : '';
  const konbiniBase = settings.konbiniURL ? settings.konbiniURL.replace(/\/?$/, '/') : '';
  return {
    path,
    place: path ? [settings.obsidianVault || 'vault', ...path.replace(/\.md$/, '').split('/')].join(' › ') : '',
    obsidian: S.obsidianURL(settings.obsidianVault, path),
    niwa: S.readerURL(doc.url, niwaBase, path),
    konbini: S.konbiniURL(konbiniBase, path, konbiniCards) || (/^https?:\/\/konbini\./.test(doc.url) ? doc.url : null),
  };
}

/**
 * Whether a page is a note (Kura's, by label or by address): for the
 * phone's page view, which may know only the address, and for what must
 * never ask Hister about a note.
 */
function isNoteDoc(doc, n = note(doc)) {
  return !!n || doc.label === 'vault' || S.noteVault(doc.url) !== null || S.isNoteURL(doc.url, settings.niwaURL, settings.konbiniURL);
}

// --- Routing: #/view?params, so Back works in the installed app ----------------

function route() {
  const [path, qs] = location.hash.replace(/^#\/?/, '').split('?');
  return { view: path || 'library', params: new URLSearchParams(qs || '') };
}
function go(view, params = {}, { replace = false } = {}) {
  const qs = new URLSearchParams(params).toString();
  const hash = `#/${view}${qs ? `?${qs}` : ''}`;
  if (replace) history.replaceState(null, '', hash);
  else if (location.hash !== hash) location.hash = hash;
  render();
}
addEventListener('hashchange', render);

// --- Lists -----------------------------------------------------------------------

let selected = null; // the page shown in the preview pane
let listSearch = ''; // the query the list came from, for Remember What You Open
let lastPage = null;

/**
 * The Code pill: your repos in Hister (code-import's), searched as
 * you type (Hister's own index: nothing spent), never in All or any other
 * list. Above it, the kind, Open Only and Private, as metadata terms
 * (S.codeQuery), kept for this visit.
 */
let codeFilters = {};
function codeList(container, q, { sort = '' } = {}) {
  shownList = { title: q || 'Code' };
  const box = h('div', {});
  const draw = () => resultsList(box, { query: S.codeQuery(q, codeFilters), sort, group: '', source: 'pages', empty: q ? `No code matches “${q}”.` : 'Your repos show up here once code-import has indexed them.', opened: false });
  const kind = h('select', { 'aria-label': 'Kind' },
    h('option', { value: '' }, 'Everything'),
    ...S.CODE_KINDS.map(([value, name]) => h('option', { value, selected: codeFilters.kind === value }, name)));
  kind.addEventListener('change', () => ((codeFilters = { ...codeFilters, kind: kind.value || undefined }), draw()));
  // Which forge: All Hosts, Forgejo or GitHub.
  const host = h('select', { 'aria-label': 'Host' },
    h('option', { value: '' }, 'All Hosts'),
    ...S.CODE_HOSTS.map(([value, name]) => h('option', { value, selected: codeFilters.host === value }, name)));
  host.addEventListener('change', () => ((codeFilters = { ...codeFilters, host: host.value || undefined }), draw()));
  const toggle = (key, text) => {
    const b = h('button', { type: 'button', 'aria-pressed': codeFilters[key] ? 'true' : 'false' }, text);
    b.addEventListener('click', () => {
      codeFilters = { ...codeFilters, [key]: !codeFilters[key] };
      b.setAttribute('aria-pressed', codeFilters[key] ? 'true' : 'false');
      draw();
    });
    return b;
  };
  container.replaceChildren(h('div', { class: 'code-filters', role: 'group', 'aria-label': 'Filters' }, kind, host, toggle('open', 'Open Only'), toggle('private', 'Private')), box);
  draw();
}

/** A code row: its kind's glyph, the title, the repo, its state, a lock when private, the date. */
function codeRow(doc, code) {
  const [glyph, kindName] = CODE_GLYPHS[code.kind] || ['‹›', 'Code'];
  const when = ago(doc.updated || doc.added);
  const row = h(
    'li',
    { class: 'row doc-row code-row', role: 'button', tabindex: '0', 'aria-selected': selected && selected.url === doc.url ? 'true' : 'false' },
    h('span', { class: 'icon code-glyph', role: 'img', 'aria-label': kindName }, glyph),
    h(
      'div',
      {},
      h('div', { class: 'title' }, doc.title || doc.url),
      h('div', { class: 'meta' },
        // Which forge it's on: most are Forgejo, and the rows looked alike.
        code.host ? [h('span', { class: `code-host code-host-${code.host}` }, S.codeHostName(code.host)), ' '] : null,
        code.private ? h('span', { 'aria-label': 'Private', title: 'Private' }, '🔒 ') : null,
        h('span', { class: 'domain' }, code.repoName || doc.domain || hostOf(doc.url)),
        code.state ? [' · ', h('span', { class: `code-state${code.state === 'open' ? ' open' : ''}` }, code.state)] : null,
        when ? ` · ${when}` : ''),
      doc.text ? snippet(doc.text) : null,
    ),
  );
  row._doc = doc;
  const open = () => openDoc(doc, row);
  row.addEventListener('click', open);
  row.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      open();
    }
  });
  return row;
}

// A code row's kind, as a glyph and in words.
const CODE_GLYPHS = { repo: ['▣', 'Repository'], readme: ['¶', 'README'], doc: ['¶', 'Document'], issue: ['◉', 'Issue'], pr: ['⇄', 'Pull request'], release: ['◆', 'Release'] };

function docRow(doc) {
  const n = note(doc);
  const code = S.codeInfo(doc);
  if (code) return codeRow(doc, code);
  const favicon = doc.favicon_key ? h('img', { class: 'icon', src: api.faviconURL(doc.favicon_key), alt: '', loading: 'lazy' }) : null;
  const file = S.isLocalFile(doc.url);
  const iconEl = favicon || h('span', { class: 'icon' }, icon(n || file ? 'note' : 'globe'));
  if (favicon) favicon.addEventListener('error', () => favicon.replaceWith(h('span', { class: 'icon' }, icon('globe'))));
  const when = ago(doc.updated || doc.added);
  const row = h(
    'li',
    { class: `row doc-row${file ? ' file-row' : n ? ' note-row' : doc.opened ? ' opened-row' : ''}`, role: 'button', tabindex: '0', 'aria-selected': selected && selected.url === doc.url ? 'true' : 'false' },
    iconEl,
    h(
      'div',
      {},
      h('div', { class: 'title' }, doc.title || doc.url),
      // A file: where it lives on the server, not Hister's "local".
      h('div', { class: 'meta' }, n && n.place ? n.place : h('span', { class: 'domain' }, file ? S.localFilePath(doc.url) : doc.domain || hostOf(doc.url)), when ? ` · ${when}` : ''),
      doc.text ? snippet(doc.text) : null,
      doc.label === 'vault' ? vaultTag(doc.url) : doc.label ? labelTag(doc.label) : null,
    ),
  );
  // The page it shows, for the keyboard (vi keys) and delete's undo.
  row._doc = doc;
  const open = () => openDoc(doc, row);
  row.addEventListener('click', open);
  row.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      open();
    }
  });
  return row;
}

function hostOf(url) {
  try {
    return new URL(url).host;
  } catch (_) {
    return url;
  }
}

function openDoc(doc, row) {
  if (settings.rememberOpened && listSearch) api.recordOpened(doc.url, doc.title || '', listSearch);
  if (wide()) {
    selected = doc;
    document.querySelectorAll('.row[aria-selected="true"]').forEach((r) => r.setAttribute('aria-selected', 'false'));
    if (row) row.setAttribute('aria-selected', 'true');
    showPreview(doc);
  } else {
    lastPage = doc;
    go('page', { url: doc.url });
  }
}

/**
 * A list drawn without the page in the preview beside it (another list, a
 * search that doesn't find it): the preview empties, as the Mac app's
 * selection does, rather than keep a page the list no longer shows.
 */
function dropStaleSelection(container) {
  if (!wide() || !selected || !container.isConnected) return;
  if ([...container.querySelectorAll('.row')].some((r) => r._doc && r._doc.url === selected.url)) return;
  selected = null;
  $('preview').replaceChildren(status('No Page Selected', 'Select a page to preview it.'));
}

function status(title, text, retry, link = null) {
  return h(
    'div',
    { class: 'status' },
    h('h2', {}, title),
    text ? h('p', {}, text) : null,
    link ? h('p', {}, h('a', { href: link.href }, link.text)) : null,
    retry ? h('button', { type: 'button', onclick: retry }, 'Try Again') : null,
  );
}

/**
 * A room that wants the Machiya sign-in (401, with the identity file): the
 * room's own sign-in page, whose machiya_session cookie then rides along on
 * this host's same-origin /kura/ and /konbini/ (docs/signing-in.md).
 */
function signInStatus(retry) {
  const href = S.machiyaSignInURL(settings.niwaURL);
  return status('Sign In to See Your Notes', 'Kura asks who you are. Sign in there, then come back.', retry, href ? { href, text: 'Sign In to Kura' } : null);
}

/**
 * Rows appended one by one, with runs of one site folded (Fold Repeated
 * Sites, as the apps' SiteRuns): a run's first row, then from the third a
 * "N more from site" row that opens the rest in place; a run of two shows
 * both. Notes never fold. Streaming, since results come a page at a time.
 */
function folder(list) {
  let site = null;
  let pending = null; // a run's second row, held until the third decides
  let fold = null; // {button, rows, open}
  const key = (d) => (settings.foldRepeats === false || d.label === 'vault' || S.isLocalFile(d.url) || S.isCodeDoc(d) ? null : S.siteOf(d) || null);
  const label = () => (fold.open ? `Hide ${fold.rows.length} more from ${site}` : `${fold.rows.length} more from ${site}`);
  const close = () => {
    if (pending) list.append(docRow(pending));
    pending = null;
    fold = null;
  };
  return {
    add(doc) {
      const k = key(doc);
      if (k && k === site) {
        if (fold) {
          const row = docRow(doc);
          row.hidden = !fold.open;
          fold.rows.push(row);
          list.append(row);
          fold.button.lastChild.textContent = label();
        } else if (pending) {
          const rows = [docRow(pending), docRow(doc)];
          pending = null;
          const button = h('button', { type: 'button', class: 'fold-more', 'aria-expanded': 'false' }, icon('chevron'), h('span'));
          fold = { button, rows, open: false };
          const mine = fold;
          const run = site;
          button.addEventListener('click', () => {
            mine.open = !mine.open;
            button.setAttribute('aria-expanded', String(mine.open));
            button.lastChild.textContent = mine.open ? `Hide ${mine.rows.length} more from ${run}` : `${mine.rows.length} more from ${run}`;
            for (const r of mine.rows) r.hidden = !mine.open;
          });
          button.lastChild.textContent = label();
          for (const r of rows) r.hidden = true;
          list.append(h('li', { class: 'fold-row' }, button), ...rows);
        } else {
          pending = doc;
        }
        return;
      }
      close();
      list.append(docRow(doc));
      site = k;
    },
    flush: close,
  };
}

/** A group's title for a page: its day, month, site or label. */
function groupKey(doc, grouping) {
  const seconds = doc.updated || doc.added || 0;
  const date = new Date(seconds * 1000);
  if (grouping === 'day') {
    const days = Math.floor((new Date().setHours(0, 0, 0, 0) - new Date(date).setHours(0, 0, 0, 0)) / 86400000);
    if (days === 0) return 'Today';
    if (days === 1) return 'Yesterday';
    return date.toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' });
  }
  if (grouping === 'month') return date.toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
  if (grouping === 'site') return S.siteOf(doc) || 'Other';
  if (grouping === 'label') return doc.label || 'No Label';
  return '';
}

/**
 * A Hister query as a list, page after page as you scroll: in groups when
 * `group` is set (by day and month in date order; by site and label, what's
 * loaded), with repeats folded. `respell`: a search that found nothing
 * tries the web's spelling (S.correctedQuery), as the search page does.
 */
function resultsList(container, options) {
  // `source`: 'pages' from Hister
  // (which never sends notes, S.histerText), 'notes' from Kura, or 'all',
  // both newest first (the Library's All; `merge` says it may, since Kura
  // has no other order and no filter words), as the apps' ResultsModel.
  const { query, sort = '', source = 'pages', merge = false, empty = 'Nothing here.', opened = true, group = '', heading = '', respell = null } = options;
  const merging = source === 'all' && merge;
  const merger = S.newestFirstMerge();
  let mergedTotal = 0;
  let notesWantSignIn = false;
  /** One page of this list, in api.search's shape. */
  async function fetchPage(first) {
    // A Notes list searches the vaults its filter names (All, or one).
    if (source === 'notes') return api.kura(query, { sort, pageKey: first ? '' : next, vault: settings.notesVault || 'all' });
    if (!merging) return api.search(query, { sort, pageKey: first ? '' : next });
    // Kura asking who you are (401) leaves the notes out, and says so.
    const notesPage = (key) => api.kura('*', { sort: 'date', pageKey: key }).catch((error) => {
      if (error.status === 401) notesWantSignIn = true;
      return null;
    });
    const addNotes = (n) => (n ? merger.addNotes(n.documents, n.next) : merger.endNotes());
    if (first) {
      const [pages, notes] = await Promise.all([api.search(query, { sort }), notesPage('')]);
      merger.addPages(pages.documents, pages.next);
      addNotes(notes);
      mergedTotal = pages.total + ((notes && notes.total) || 0);
    }
    let placed = merger.take();
    for (let tries = 0; !first && !placed.length && !merger.finished() && tries < 6; tries++) {
      if (merger.needsPages()) {
        const pages = await api.search(query, { sort, pageKey: merger.pagesKey });
        merger.addPages(pages.documents, pages.next);
      }
      if (merger.needsNotes()) addNotes(await notesPage(merger.notesKey));
      placed = merger.take();
    }
    return { total: mergedTotal, documents: placed, next: merger.finished() ? '' : 'merge', opened: [], suggestion: '' };
  }
  const list = h('ul', { class: 'rows' });
  const sentinel = h('div', {});
  const seen = new Set();
  const groups = new Map(); // title → folder
  const plain = folder(list);
  let next = '';
  let loading = false;
  let done = false;
  container.replaceChildren(h('div', { class: 'spinner' }));

  const into = (doc) => {
    if (!group) return plain;
    const title = groupKey(doc, group);
    if (!groups.has(title)) {
      const ul = h('ul', { class: 'rows' });
      // One item per group, heading and rows: the heading sticks while its
      // rows scroll by, and the next group's pushes it off.
      list.append(h('li', { class: 'group-body' }, h('div', { class: 'section-head' }, title), ul));
      groups.set(title, folder(ul));
    }
    return groups.get(title);
  };

  async function page(first) {
    if (loading || done) return;
    loading = true;
    try {
      const reply = await fetchPage(first);
      if (first && respell && !reply.total && !reply.documents.length && !reply.opened.length) {
        // The autocompleter's respellings, never a web search (each one counts).
        const suggestions = await api.autocomplete(S.webQuery(respell.text) || respell.text).catch(() => []);
        const close = S.correctedQuery(respell.text, suggestions);
        if (close) {
          loading = false;
          return resultsList(container, { ...options, query: respell.wrap(close), respell: null, heading: `${respell.title} · for “${close}”` });
        }
      }
      if (first) {
        container.replaceChildren();
        if (notesWantSignIn) container.append(signInStatus(() => resultsList(container, options)));
        if (heading) container.append(h('div', { class: 'section-head' }, heading));
        if (opened && settings.showOpened === true && reply.opened.length) {
          container.append(h('div', { class: 'section-head' }, 'You Opened'));
          const openedList = h('ul', { class: 'rows' });
          for (const o of reply.opened) openedList.append(docRow({ url: o.url, title: o.title, updated: o.updated, domain: o.domain, opened: true }));
          container.append(openedList);
        }
        container.append(list, sentinel);
      }
      let added = 0;
      for (const doc of reply.documents) {
        if (seen.has(doc.url)) continue;
        seen.add(doc.url);
        into(doc).add(doc);
        added++;
      }
      next = reply.next;
      done = !next;
      if (done) {
        plain.flush();
        for (const f of groups.values()) f.flush();
      }
      if (first) dropStaleSelection(container);
      if (first && !seen.size && !reply.opened.length) container.replaceChildren(...[notesWantSignIn ? signInStatus(() => resultsList(container, options)) : null, status('Nothing Found', empty)].filter(Boolean));
      loading = false;
      // A short page (all seen, or a merge waiting on the other list): keep going.
      if (!done && (added === 0 || list.querySelectorAll('.row').length < 15)) page(false);
    } catch (error) {
      loading = false;
      const retry = () => resultsList(container, options);
      if (first) container.replaceChildren(error.status === 401 && source !== 'pages' ? signInStatus(retry) : status(error.unreachable ? "Can't Reach Hister" : 'Something Went Wrong', error.message, retry));
    }
  }
  new IntersectionObserver((entries) => entries.some((e) => e.isIntersecting) && page(false), { root: $('list'), rootMargin: '600px' }).observe(sentinel);
  page(true);
}

// --- Sort · Group · Filter, as the apps' row under the tabs ----------------------

const SORTS = [['best', 'Best Match', ''], ['newest', 'Newest', 'date'], ['oldest', 'Oldest', '-date'], ['visits', 'Most Visited', 'visits'], ['site', 'Site', 'domain']];
const GROUPS = [['', 'No Groups'], ['day', 'Day'], ['month', 'Month'], ['site', 'Site'], ['label', 'Label']];
const DATES = [['updated:<24h', 'Past 24 Hours'], ['updated:<7d', 'Past Week'], ['updated:<30d', 'Past Month'], ['updated:<365d', 'Past Year'], ['updated:>365d', 'Older']];

/** A small menu: a quiet button and its list, closed by a click elsewhere. */
function dropMenu(button, items) {
  const wrap = h('div', { class: 'menu' });
  const listEl = h('div', { class: 'menu-list', hidden: true, role: 'menu' });
  const fillItems = () =>
    fill(listEl, ...(typeof items === 'function' ? items() : items).map((it) =>
      it === '-'
        ? h('hr')
        : h('button', { type: 'button', role: 'menuitemradio', 'aria-checked': it.checked ? 'true' : 'false', class: it.danger ? 'danger' : undefined, onclick: () => ((listEl.hidden = true), it.pick()) }, h('span', { class: 'check' }, it.checked ? '✓' : ''), it.text),
    ));
  button.addEventListener('click', (e) => {
    e.stopPropagation();
    const opening = listEl.hidden;
    document.querySelectorAll('.menu-list').forEach((m) => (m.hidden = true));
    if (opening) fillItems();
    listEl.hidden = !opening;
  });
  wrap.append(button, listEl);
  return wrap;
}
document.addEventListener('click', (e) => {
  document.querySelectorAll('.menu-list').forEach((m) => !m.parentElement.contains(e.target) && (m.hidden = true));
});
// A click in the preview (a sandboxed iframe) never reaches this document,
// so an open menu stayed open: the window losing
// focus to the frame closes it, and so does Escape.
const closeMenus = () => document.querySelectorAll('.menu-list').forEach((m) => (m.hidden = true));
window.addEventListener('blur', closeMenus);
document.addEventListener('keydown', (e) => e.key === 'Escape' && closeMenus());

/** The list's choices from its hash params: sort, group, filter word. */
function listChoices(params, { search = false } = {}) {
  let sort = params.get('o') || (search ? 'best' : 'newest');
  const group = params.get('g') || '';
  // Day and month groups follow the date order.
  if ((group === 'day' || group === 'month') && sort !== 'newest' && sort !== 'oldest') sort = 'newest';
  return { sort, group, word: params.get('w') || '', hister: (SORTS.find((x) => x[0] === sort) || SORTS[1])[2] };
}

function controls(view, params, { search = false, notes = false } = {}) {
  const c = listChoices(params, { search });
  const set = (change) => {
    const next = Object.fromEntries(params);
    for (const [k, v] of Object.entries(change)) if (v) next[k] = v; else delete next[k];
    go(view, next, { replace: true });
  };
  const quiet = (iconName, text, active) => h('button', { type: 'button', class: `quiet${active ? ' active' : ''}`, 'aria-haspopup': 'menu' }, icon(iconName), text);
  const sorts = SORTS.filter(([k]) => search || k !== 'best');
  const sortName = (sorts.find(([k]) => k === c.sort) || sorts[0])[1];
  const groupName = c.group ? (GROUPS.find(([k]) => k === c.group) || GROUPS[0])[1] : 'Group';
  const dateName = (DATES.find(([w]) => w === c.word) || [])[1];
  return h(
    'div',
    { class: 'controls' },
    dropMenu(quiet('sort', sortName, false), () => sorts.map(([k, t]) => ({ text: t, checked: k === c.sort, pick: () => set({ o: k }) }))),
    dropMenu(quiet('group', groupName, !!c.group), () =>
      GROUPS.map(([k, t]) => ({ text: t, checked: k === c.group, pick: () => set({ g: k, o: (k === 'day' || k === 'month') && c.sort !== 'oldest' ? 'newest' : params.get('o') }) })),
    ),
    settings.searchFilters === false
      ? null
      : dropMenu(quiet('filter', dateName || 'Filter', !!c.word), () => [
          { text: 'Any Time', checked: !c.word, pick: () => set({ w: '' }) },
          ...DATES.map(([w, t]) => ({ text: t, checked: w === c.word, pick: () => set({ w }) })),
        ]),
    // A Notes list: which of Kura's vaults (All, or one; work vaults are
    // searchable in Notes wherever Shiori runs).
    notes && kuraVaults.length > 1
      ? dropMenu(quiet('stack', (kuraVaults.find((v) => v.name === settings.notesVault) || { title: 'All Vaults' }).title, (settings.notesVault || 'all') !== 'all'), () => [
          { text: 'All Vaults', checked: (settings.notesVault || 'all') === 'all', pick: () => (changeSetting('notesVault', 'all'), render()) },
          ...kuraVaults.map((v) => ({ text: v.title, checked: settings.notesVault === v.name, pick: () => (changeSetting('notesVault', v.name), render()) })),
        ])
      : null,
  );
}

/** The Machiya rooms, as the build stamped them (scripts/rooms-stamp.py); Shiori is here. */
const ROOMS_STAMP = '__SHIORI_ROOMS__';
const ROOMS = S.rooms(ROOMS_STAMP, location.origin).filter((r) => r.key === 'shiori' || !HOUSE.hidden.includes(r.key));

// Signing in (docs/signing-in.md): this host's nginx asks the sign-in
// helper about every Hister call. A 401 or 403 from Hister's routes (not
// the rooms', which say so themselves) goes to the helper's sign-in and
// back here, at most once in 30 s; a 500 there says sign-in is unavailable.
// Inert while Hister has no users: nothing answers 401 or 403.
const ROOM_PATHS = /^(kura|konbini|searx|smallweb)\//;
let unavailableSaid = false;
api.setRefusedHandler((status, path) => {
  if (ROOM_PATHS.test(path)) return;
  const asked = S.signInAsked(status);
  if (asked === 'signin') {
    const url = S.histerSignInURL(ROOMS_STAMP, location.origin, location.href);
    if (!url) return;
    // From now on Settings offers the helper's sessions page (sign-out).
    writeLocal('shioriSignInSeen', true);
    let storage = null;
    try {
      storage = sessionStorage;
    } catch (_) {}
    if (S.signInDue(storage || { getItem: () => null, setItem() {} })) location.assign(url);
  } else if (asked === 'unavailable' && !unavailableSaid && readLocal('shioriSignInSeen')) {
    unavailableSaid = true;
    toast("Sign-in is unavailable right now: Hister or its sign-in helper isn't answering.");
  }
});
/** The Rooms menu's last row, as the rooms end theirs: Shiori's Settings. */
const ROOMS_SETTINGS = { href: '#/settings', open: () => go('settings') };

/** Kura on this host (web/README.md), for the notes lists' feeds. */
const KURA_BASE = location.origin + '/kura/';

/** The list last on screen, for Settings → Export & Feed (as the apps). */
let shownList = null;
const withWord = (query, word) => (word ? `${query} ${word}` : query);

/** A total on a pill (All's search finds Pages' and Notes'): "Pages 31". */
function setSegmentCount(value, n) {
  const pill = document.querySelector(`#list-top .segments button[data-value="${value}"]`);
  if (!pill || !n) return;
  pill.querySelector('.pill-count')?.remove();
  pill.append(h('span', { class: 'pill-count' }, n.toLocaleString()));
}

function segments(choices, current, onpick) {
  return fadeEdges(
    h(
      'div',
      { class: 'segments', role: 'group' },
      choices.map(([value, title, tint]) =>
        h('button', { type: 'button', 'aria-pressed': String(value === current), 'data-tint': tint || 'blue', 'data-value': value, onclick: () => onpick(value) }, title),
      ),
    ),
  );
}

/**
 * A sideways-scrolling row fades out at an end with more to scroll to
 * (`data-fade`, drawn by app.css), as the search page's tabs: a pill cut off
 * at the edge looked like a mistake. Once laid
 * out, the chosen pill is brought into view if it's past the edge.
 */
function fadeEdges(row) {
  let placed = false;
  const update = () => {
    if (!placed && row.isConnected && row.clientWidth) {
      placed = true;
      const chosen = row.querySelector('[aria-pressed="true"]');
      if (chosen) {
        const box = row.getBoundingClientRect();
        const pill = chosen.getBoundingClientRect();
        if (pill.right > box.right || pill.left < box.left) row.scrollLeft += pill.left - box.left - 24;
      }
    }
    const fade = S.edgeFade(row);
    if (fade) row.dataset.fade = fade;
    else delete row.dataset.fade;
  };
  row.addEventListener('scroll', update, { passive: true });
  if (window.ResizeObserver) new ResizeObserver(update).observe(row);
  return row;
}

// --- Views ---------------------------------------------------------------------

function setTitle(text, back = false) {
  $('title').textContent = text;
  // A title only where no sidebar says what's shown: the Mac app has none
  // beside its sidebar either.
  $('title').classList.toggle('sidebar-says', !back);
  document.title = text === 'Library' ? 'Shiori' : `${text} – Shiori`;
  $('back').hidden = !back;
}

function viewLibrary(params) {
  const filter = scopeOf(params);
  setTitle('Library');
  listSearch = '';
  searchInput.placeholder = PROMPTS[filter];
  fill($('list-top'), 
    segments(scopes(), filter, (s) => go('library', { s }, { replace: true })),
    filter === 'opened' || filter === 'web' ? null : controls('library', params, { notes: filter === 'notes' }),
  );
  const list = $('list');
  if (filter === 'opened') {
    shownList = { title: 'Opened', feed: S.feedURL(location.origin, { opened: true }) };
    return viewOpened(list);
  }
  if (filter === 'web') {
    return list.replaceChildren(status('Search the Web', 'Type in the search field to search the web.'));
  }
  if (filter === 'smallweb') {
    return list.replaceChildren(status('Search the Small Web', 'Type in the search field and press Return to search Gemini and Gopher.'));
  }
  if (filter === 'code') return codeList(list, '', { sort: 'date' });
  if (filter === 'files') {
    // The folders Hister watches, newest first; never mixed into the rest.
    shownList = { title: 'Files' };
    return resultsList(list, { query: S.filesQuery(''), sort: 'date', group: '', source: 'pages', empty: 'Files show up here once your Hister server watches a folder.', opened: false });
  }
  const c = listChoices(params);
  const query = withWord('*', c.word);
  const title = { all: 'Library', hister: 'Pages', notes: 'Notes' }[filter] || 'Library';
  const source = { all: 'all', hister: 'pages', notes: 'notes' }[filter] || 'all';
  shownList = { title, query, sort: c.hister, source, feed: S.feedURL(location.origin, { query, title, source, kuraBase: KURA_BASE }) };
  resultsList(list, {
    query,
    sort: c.hister,
    group: c.group,
    source,
    // All mixes in your notes newest first, unfiltered (Kura has no visits,
    // sites or filter words); otherwise it's your pages.
    merge: c.hister === 'date' && !c.word && (c.group === '' || c.group === 'day' || c.group === 'month'),
    empty: 'Pages you visit show up here once Hister has them.',
    opened: false,
  });
}

/** What you opened, newest first; with `filter`, only what matches (Hister's). */
async function viewOpened(container, filter = '') {
  container.replaceChildren(h('div', { class: 'spinner' }));
  try {
    const { entries } = await api.opened(null, filter);
    if (!entries.length) {
      return container.replaceChildren(filter
        ? status('Nothing Opened Matches', `You haven’t opened anything that matches “${filter}”.`)
        : status('Nothing Opened Yet', 'Results you open from a search show up here.'));
    }
    const list = h('ul', { class: 'rows' });
    for (const e of entries) {
      const row = docRow({ url: e.url, title: e.title, added: e.added, domain: hostOf(e.url), opened: true });
      row.querySelector('.meta').textContent = `For “${S.typedQuery(e.query)}” · ${ago(e.added)}`;
      list.append(row);
    }
    container.replaceChildren(list);
    dropStaleSelection(container);
  } catch (error) {
    container.replaceChildren(status("Can't Reach Hister", error.message, () => viewOpened(container, filter)));
  }
}

function viewLabels() {
  setTitle('Labels');
  listSearch = '';
  fill($('list-top'), );
  const list = h('ul', { class: 'rows' });
  const item = (name, query, iconName, color) =>
    h(
      'li',
      { class: 'row', role: 'button', tabindex: '0', onclick: () => go('list', { q: query, t: name }) },
      color ? h('span', { class: 'icon', style: 'display:flex;align-items:center;justify-content:center' }, h('span', { class: 'dot', style: `width:10px;height:10px;border-radius:50%;background:${color}` })) : h('span', { class: 'icon' }, icon(iconName)),
      h('div', { class: 'title', style: 'color:var(--text)' }, name),
    );
  if (!labels.length) {
    $('list').replaceChildren(status('No Labels Yet', 'Labels come from your Hister server’s aliases.', async () => {
      await loadRules();
      render();
    }));
    return;
  }
  // Each group with its heading in one item, so the heading sticks while
  // the group scrolls by.
  const group = (title, rows) => list.append(h('li', { class: 'group-body' }, h('div', { class: 'section-head' }, title), h('ul', { class: 'rows' }, rows)));
  if (Object.keys(aliases).length) {
    group('Collections', Object.keys(aliases).sort().map((alias) => {
      const row = item(S.collectionTitle(alias), alias, S.collectionIcon(alias));
      const glyph = row.querySelector('.icon svg');
      if (glyph) glyph.style.stroke = chipVar(alias);
      return row;
    }));
  }
  group('Labels', labels.map((label) => item(label, `label:${label}`, null, chipVar(label))));
  $('list').replaceChildren(list);
}

function viewList(params) {
  const q = params.get('q') || '*';
  const title = params.get('t') || q;
  setTitle(title, !sidebarShown());
  listSearch = '';
  // Search within the list ("Search in bsd", as the apps have it): the
  // words go in the address (in) so Back keeps them, and typing reloads
  // only the list, so the field keeps its focus.
  const field = h('input', {
    type: 'search', class: 'list-search', value: params.get('in') || '',
    placeholder: `Search in ${title}`, autocapitalize: 'off', autocorrect: 'off', spellcheck: 'false',
    'aria-label': `Search in ${title}`,
  });
  selectOnFocus(field);
  const load = () => {
    const words = field.value.trim();
    const c = listChoices(params, { search: !!words });
    const query = withWord(words ? `${q} ${words}` : q, c.word);
    shownList = { title, query, sort: c.hister, feed: S.feedURL(location.origin, { query, title }) };
    resultsList($('list'), {
      query, sort: c.hister, group: c.group, opened: false,
      empty: words ? `Nothing in ${title} matches “${words}”.` : 'No pages have this yet.',
    });
  };
  let timer = 0;
  const apply = () => {
    const next = new URLSearchParams(params);
    if (field.value.trim()) next.set('in', field.value.trim()); else next.delete('in');
    history.replaceState(null, '', `#/list?${next.toString()}`);
    // The sort button's label follows (Best Match while searching); the
    // field is the same element, re-placed, and keeps its focus.
    const focused = document.activeElement === field;
    drawControls();
    if (focused) field.focus();
    load();
  };
  // On Enter (below) or the magnifier, never while typing; clearing shows
  // the whole list at once.
  field.addEventListener('input', () => {
    clearTimeout(timer);
    if (!field.value.trim()) apply();
  });
  field.addEventListener('keydown', (e) => {
    if (e.key !== 'Enter') return;
    e.preventDefault();
    clearTimeout(timer);
    apply();
  });
  // Its X, and on a phone its magnifier: the search at once.
  const fieldButtons = S.fieldButtons(field, () => {
    clearTimeout(timer);
    apply();
  });
  const drawControls = () => fill($('list-top'), h('div', { class: 'searchfield' }, field, ...fieldButtons), controls('list', params, { search: !!field.value.trim() }));
  drawControls();
  load();
}

// The app's colours and names: All cyan, Pages blue, Notes green, the web
// orange ("Pages" is your pages; 'hister' stays the value).
// Notes wear Kura's orange and the web Shiori's lens yellow (the Machiya
// rooms' colours).
// Files: the folders Hister watches, green (a hue no room wears).
// Code: your repos (code-import's), red, the one hue left.
const ALL_SCOPES = [['all', 'All', 'cyan'], ['hister', 'Pages', 'blue'], ['notes', 'Notes', 'orange'], ['web', 'Web', 'yellow'], ['smallweb', 'Small Web', 'teal'], ['files', 'Files', 'green'], ['code', 'Code', 'red'], ['opened', 'Opened', 'purple']];
/** The pills: Opened only while Show Opened is on (off by default); Files only while Hister has some. */
const availableScopes = () => ALL_SCOPES.filter(([v]) => (v !== 'opened' || settings.showOpened === true) && (v !== 'smallweb' || settings.smallWebTab !== false) && (v !== 'files' || hasLocalFiles) && (v !== 'code' || hasCodeDocs));
/** The pill's key in the shared vocabulary (S.PILLS). */
const pillKey = (scope) => (scope === 'hister' ? 'pages' : scope);
/** The pills in the order set in Settings → Pills, less the ones switched off (S.orderPills). */
const scopes = () => {
  const available = availableScopes();
  return S.orderPills(available.map(([v]) => pillKey(v)), settings.pills).map((key) => available.find(([v]) => pillKey(v) === key));
};
/** Hister holds files from folders it watches (`type:local`): asked once at launch, before the first draw. */
let hasLocalFiles = false;
/** Hister holds your repos (metadata.source:code): asked with the files. */
let hasCodeDocs = false;
async function loadLocalFiles() {
  api.search(S.codeQuery(''), { limit: 1 }).then((r) => (hasCodeDocs = r.total > 0)).catch(() => {});
  try {
    hasLocalFiles = (await api.search(S.filesQuery(''), { limit: 1 })).total > 0;
  } catch (_) {}
}
// One row over every list, browsing or searching, as in the apps (it had
// been two: the Library's and a search's). `s` in the address is the
// choice for both, so typing searches whichever is picked.
const PROMPTS = { all: 'Search All', hister: 'Search Your Pages', notes: 'Search Notes', web: 'Search the Web', smallweb: 'Search Gemini and Gopher', files: 'Search Your Files', code: 'Search Your Code', opened: 'Search What You Opened' };
function scopeOf(params) {
  const s = params.get('s') || { pages: 'hister' }[params.get('f')] || params.get('f') || 'all';
  return scopes().some(([v]) => v === s) ? s : 'all';
}

function viewSearch(params) {
  const q = params.get('q') || '';
  const scope = scopeOf(params);
  setTitle('Search');
  searchInput.placeholder = PROMPTS[scope];
  // No words (the installed app's Search shortcut, #/search): the
  // Library, its field ready to type in.
  if (!q) {
    go('library', { s: scope }, { replace: true });
    return searchInput.focus();
  }
  // The web only for a search run on purpose (w=1, searchTo); a tap on
  // the Web pill is one too.
  const web = params.get('w') === '1';
  const keep = (next) => ({ q, ...(web ? { w: '1' } : {}), ...next });
  const listed = scope === 'hister' || scope === 'notes';
  fill($('list-top'), 
    segments(scopes(), scope, (s) => go('search', keep({ s, ...(s === 'web' ? { w: '1' } : {}) }), { replace: true })),
    listed ? controls('search', params, { search: true, notes: scope === 'notes' }) : null,
  );
  if (scope !== 'opened') didYouMean(q, scope);
  const c = listChoices(params, { search: true });
  const text = q;
  listSearch = text;
  const source = scope === 'notes' ? 'notes' : 'pages';
  shownList = { title: q, query: withWord(text, c.word), sort: c.hister, source, feed: S.feedURL(location.origin, { query: withWord(text, c.word), title: q, source, kuraBase: KURA_BASE }) };
  if (listed) {
    const notes = scope === 'notes';
    resultsList($('list'), {
      query: withWord(text, c.word),
      sort: c.hister,
      group: c.group,
      // Pages from Hister, notes from Kura.
      source,
      empty: notes ? `No notes match “${q}”.` : `Nothing in your pages matches “${q}”.`,
      respell: { text: q, wrap: (t) => withWord(t, c.word), title: notes ? 'Your Notes' : 'Your Pages' },
    });
  } else if (scope === 'web') {
    if (web) webList($('list'), q);
    else $('list').replaceChildren(status('Search the Web', 'Press Return to search the web for this.'));
  } else if (scope === 'smallweb') smallwebList($('list'), q);
  else if (scope === 'code') codeList($('list'), q);
  else if (scope === 'files') {
    shownList = { title: q };
    resultsList($('list'), { query: S.filesQuery(q), sort: '', group: '', source: 'pages', empty: `No files match “${q}”.` });
  } else if (scope === 'opened') {
    shownList = { title: 'Opened', feed: S.feedURL(location.origin, { opened: true }) };
    viewOpened($('list'), q);
  } else searchAll($('list'), q, { web });
}

/**
 * "Did you mean …?" under the pills, as the search page has it: a
 * respelling from SearXNG's autocomplete, even when the search found
 * something ("george orewell", "rapsberrypi").
 */
async function didYouMean(q, scope) {
  const wq = S.webQuery(q);
  if (!settings.webResults || !wq || S.hasBang(q)) return;
  const fix = S.didYouMean(wq, await api.autocomplete(wq));
  const { view, params } = route();
  if (!fix || view !== 'search' || params.get('q') !== q) return;
  $('list-top').querySelector('.correction')?.remove();
  $('list-top').append(h('p', { class: 'correction' }, 'Did you mean ', h('a', { href: '#', onclick: (e) => (e.preventDefault(), (searchInput.value = fix), go('search', { q: fix, s: scope, w: '1' })) }, fix), '?'));
}

/** Your pages and your notes in All: a page of each (as the Pages list's),
 *  all of them among the web results. */
const ALL_COUNT = 20;

async function searchAll(container, q, { web = true } = {}) {
  container.replaceChildren(h('div', { class: 'spinner' }));
  // Pages from Hister (which sends no notes), notes from Kura.
  const both = (text) => Promise.all([
    api.search(text, { limit: ALL_COUNT }).catch(() => null),
    // Kura asking who you are (401): a Sign In notice where the notes go.
    api.kura(text, { limit: ALL_COUNT }).catch((error) => (error.status === 401 ? { signIn: true, total: 0, documents: [], opened: [] } : null)),
  ]);
  let [pages, notes] = await both(q);
  const found = (r) => r && (r.total || r.documents.length || r.opened.length);
  // Nothing of yours: the web's spelling (as the search page), marked.
  let respelled = '';
  if (!found(pages) && !found(notes)) {
    // The autocompleter's respellings, never a web search (each one counts).
    const suggestions = await api.autocomplete(S.webQuery(q) || q).catch(() => []);
    const close = S.correctedQuery(q, suggestions);
    if (close) {
      [pages, notes] = await both(close);
      if (found(pages) || found(notes)) respelled = close;
    }
  }
  // An opened note (Hister's `history` carries no label) is known by its address.
  const isPage = (d) => d.label !== 'vault' && !S.isNoteURL(d.url, settings.niwaURL, settings.konbiniURL);
  if (pages) {
    // The pages you opened for this search first (Hister ranks them first
    // and counts them in the total), then the rest: without them, "6
    // results" showed one page once "You Opened" left All.
    const opened = settings.showOpened === true ? (pages.opened || []).map((o) => ({ url: o.url, title: o.title, updated: o.updated, domain: o.domain, opened: true })) : [];
    const seen = new Set();
    pages.documents = [...opened, ...pages.documents].filter((d) => isPage(d) && !seen.has(d.url) && seen.add(d.url)).slice(0, ALL_COUNT);
  }
  container.replaceChildren();
  const answer = answerCard(q);
  if (answer) container.append(answer);
  // Your pages and notes have no sections here, as on the search page:
  // a page of each goes among the web results, pages and notes taking
  // turns, spread evenly (S.alternate, S.mixCounts), each row saying whose
  // it is, and their totals go on the Pages and Notes pills.
  const hiddenOpened = settings.showOpened === true ? 0 : ((pages && pages.opened) || []).filter((o) => !S.isNoteURL(o.url, settings.niwaURL, settings.konbiniURL)).length;
  if (pages) setSegmentCount('hister', Math.max((pages.total || 0) - hiddenOpened, pages.documents.length));
  // The Code pill's count (Hister's own index, nothing spent); code is never listed here.
  if (hasCodeDocs) api.search(S.codeQuery(q), { limit: 1 }).then((r) => setSegmentCount('code', r.total)).catch(() => {});
  if (notes && !notes.signIn) setSegmentCount('notes', Math.max(notes.total || 0, (notes.documents || []).length));
  const mine = (reply, label) => ((reply && reply.documents) || []).slice(0, ALL_COUNT).map((d) => {
    const row = docRow(d);
    row.classList.add('mixed');
    row.querySelector('.title').dataset.label = respelled ? `${label} · for “${respelled}”` : label;
    return row;
  });
  const myPages = mine(pages, 'Your page');
  const myNotes = notes && notes.signIn ? [] : mine(notes, 'Your note');
  const mix = S.alternate(myPages, myNotes);
  const rows = mix;
  if (notes && notes.signIn) container.append(h('section', { class: 'list-section' }, signInStatus(() => searchAll(container, q, { web }))));
  dropStaleSelection(container);
  if (!settings.webResults || !web) {
    if (rows.length) container.append(h('ul', { class: 'rows' }, rows));
    else if (!container.children.length) container.replaceChildren(status('Nothing Found', `Nothing matches “${q}”.`));
    // While typing: yours only; Return adds the web (each web search counts).
    if (settings.webResults && !web) container.append(h('p', { class: 'more web-on-return' }, 'Press Return to add the web.'));
    return;
  }
  const webBox = h('div', {}, h('div', { class: 'spinner' }));
  container.append(webBox);
  webList(webBox, q, { embedded: true, mix });
}

/**
 * Gemini and Gopher results through the gateway (docs/smallweb.md),
 * searched on Return only. A result opens where Settings says: the
 * gateway's page, or the gemini:// / gopher:// link for an app such as
 * Lagrange (then the gateway is asked to save it to Hister, since it
 * never passes through); the other is the chip beside it.
 */
async function smallwebList(container, q) {
  container.replaceChildren(h('div', { class: 'spinner' }));
  const list = h('ul', { class: 'rows' });
  const seen = new Set();
  let page = 1;
  const direct = settings.smallWebOpen === 'direct';
  const opened = (r, isDirect) => {
    if (settings.rememberOpened) api.recordOpened(r.url, r.title, q);
    if (isDirect) api.smallwebSave(r.url);
  };
  const link = (r, isDirect, content, attrs = {}) =>
    h('a', { href: isDirect ? r.url : r.proxy_url, ...(isDirect ? {} : { target: '_blank', rel: 'noopener noreferrer' }), onclick: () => opened(r, isDirect), ...attrs }, content);
  const row = (r) =>
    h(
      'li',
      // Tinted in Small Web's teal, as the pill (the web's own rows stay plain).
      { class: 'row web-row doc-row smallweb-row' },
      h('span', { class: 'icon' }, icon('globe')),
      h(
        'div',
        {},
        link(r, direct, [
          h('div', { class: 'title' }, r.title),
          h('div', { class: 'meta' }, h('span', { class: 'scheme' }, r.scheme === 'gopher' ? 'Gopher' : 'Gemini'), ' ', h('span', { class: 'domain' }, r.place)),
          r.snippet ? h('div', { class: 'snippet' }, S.markRuns(r.snippet, r.marks).map((run) => (run.marked ? h('mark', {}, run.text) : run.text))) : null,
        ], { style: 'text-decoration:none;color:inherit;display:block' }),
        h(
          'div',
          { class: 'meta' },
          r.engines,
          ' · ',
          link(r, !direct, direct ? 'gateway' : r.scheme, { class: 'chip-link', title: direct ? 'Open Through the Gateway' : 'Open in a Gemini App' }),
        ),
      ),
    );
  const more = h('button', { type: 'button', class: 'text-button more-button', hidden: true }, 'More Results');
  async function load() {
    try {
      const reply = await api.smallweb(q, page);
      if (page === 1) {
        if (!reply.results.length) return container.replaceChildren(status('No Small Web Results', reply.failures.join(' · ')));
        container.replaceChildren(reply.failures.length ? h('p', { class: 'correction' }, reply.failures.join(' · ')) : '', list, more);
        dropStaleSelection(container);
      }
      for (const r of reply.results) if (!seen.has(r.url)) (seen.add(r.url), list.append(row(r)));
      more.hidden = !reply.more;
    } catch (error) {
      if (page === 1) container.replaceChildren(status("The Small Web Didn't Answer", error.message || '', () => smallwebList(container, q)));
    }
  }
  more.addEventListener('click', () => {
    page += 1;
    more.hidden = true;
    load();
  });
  load();
}

/**
 * "wiki" as a word in a search: Wikipedia's article first, as on the search
 * page. The article is the first in the
 * results in the reader's language, else from the search without "wiki".
 */
async function wikipediaFirst(results, wq) {
  const words = S.wikiQuery(wq);
  if (!words) return results;
  const langs = navigator.languages || [];
  const readers = (a) => langs.some((l) => l.toLowerCase().split('-')[0] === a.lang);
  let article = S.wikipediaArticle(results, langs);
  let found = null;
  if (!article || !readers(article)) {
    const other = await api.web(words).catch(() => null);
    const better = other && S.wikipediaArticle(other.results, langs);
    if (better && (!article || readers(better))) {
      article = better;
      found = other.results[better.index];
    }
  }
  return S.wikiFirst(results, article, found);
}

/**
 * The web's results. `mix` (All): your pages and notes, in order, one after
 * each web row from the first (a hole skipped); without web results, theirs
 * is the list.
 */
async function webList(container, q, { embedded = false, mix = [] } = {}) {
  if (!embedded) container.replaceChildren(h('div', { class: 'spinner' }));
  const wq = S.webQuery(q);
  const mineOnly = (...rest) => container.replaceChildren(...[...rest, mix.some(Boolean) ? h('ul', { class: 'rows' }, mix.filter(Boolean)) : null].filter(Boolean));
  if (!wq) return mineOnly(status('Hister Only', 'That query is Hister syntax only, so the web isn’t searched.'));
  try {
    const data = await api.web(wq);
    const results = (await wikipediaFirst(data.results || [], wq)).filter((r) => typeof r.url === 'string' && /^https?:/.test(r.url));
    if (!results.length) return mix.some(Boolean) ? mineOnly() : container.replaceChildren(status('No Web Results', ''));
    const list = h('ul', { class: 'rows' });
    const shown = results.slice(0, embedded ? 10 : 30);
    for (const r of shown) {
      const thumb = api.proxiedImage(r.thumbnail || r.thumbnail_src || r.img_src);
      list.append(
        h(
          'li',
          { class: 'row web-row', 'data-url': r.url },
          h('span', { class: 'icon' }, icon('globe')),
          h(
            'a',
            { href: r.url, target: '_blank', rel: 'noopener noreferrer', style: 'text-decoration:none;color:inherit' },
            thumb ? h('img', { class: 'thumb', src: thumb, alt: '', loading: 'lazy', onerror: (e) => e.target.remove() }) : null,
            h('div', { class: 'title' }, S.decodeEntities(r.title) || r.url),
            h('div', { class: 'meta' }, h('span', { class: 'domain' }, hostOf(r.url))),
            r.content ? h('div', { class: 'snippet' }, S.decodeEntities(r.content)) : null,
          ),
        ),
      );
    }
    // Yours among them, spread evenly from the first web row to the last.
    const webRows = [...list.children];
    const counts = S.mixCounts(webRows.length, mix.length);
    let next = 0;
    webRows.forEach((row, i) => {
      row.after(...mix.slice(next, next + counts[i]));
      next += counts[i];
    });
    if (!webRows.length) list.append(...mix);
    // Not `null` as a child: replaceChildren writes it out as the text "null"
    // (it showed under All's Web heading).
    container.replaceChildren(...[embedded ? null : answerCard(q), list].filter(Boolean));
    if (!embedded) dropStaleSelection(container);
    markSaved(list, shown.map((r) => r.url));
  } catch (error) {
    mineOnly(status("The Web Search Didn't Answer", '', () => webList(container, q, { embedded, mix })));
  }
}

/**
 * Web results you already have, marked as the search page marks them: the
 * page's label as its chip, or "visited" for one with none (one Hister
 * lookup per batch, S.urlLookupQueries and S.savedLabels). Best effort.
 */
async function markSaved(list, urls) {
  const lookups = S.urlLookupQueries(urls);
  if (!lookups.length) return;
  try {
    const replies = await Promise.all(lookups.map((q) => api.search(q, { limit: 100 }).catch(() => null)));
    const labels = S.savedLabels(replies.flatMap((r) => (r && r.documents) || []));
    for (const row of list.querySelectorAll('.web-row')) {
      const key = S.normalizeURL(row.dataset.url || '');
      if (!labels.has(key)) continue;
      const label = labels.get(key);
      const meta = row.querySelector('.meta');
      if (!meta || meta.querySelector('.saved-chip')) continue;
      meta.prepend(h('span', { class: 'chip saved-chip', style: `--chip: ${label ? chipVar(label) : 'var(--visited)'}`, title: label ? `In your pages, labelled ${label}` : 'In your pages' }, label || 'visited'), ' ');
    }
  } catch (_) {}
}

// --- Preview -----------------------------------------------------------------------

// --- Summarize (docs/ai.md) ------------------------------------------
// Your server's AI, as the apps' ✦: a card above the preview with Copy,
// Regenerate and Close. Web pages only; the server refuses notes too.

let aiOn = false;
let aiAnswers = false;
// Only a build with the companion service (SHIORI_AI=1) asks for it: without
// it every /shiori/ai/ request would be a 404 in the console.
const AI_BUILT = fromBuild('__SHIORI_AI__') === '1';
(AI_BUILT ? api.aiStatus() : Promise.resolve(null)).then((status) => {
  aiOn = !!(status && status.enabled);
  aiAnswers = aiOn && !!status.answer;
  if (aiOn && selected) showPreview(selected);
  // A search already on screen gets its answer row.
  if (aiAnswers && route().view === 'search') render();
});

// --- The AI answer (All and Web): the search page's, as a row at the top ------------
// Your server answers from the web results' snippets; only when opened.

const answers = new Map();

function answerCard(q) {
  const text = S.webQuery(q);
  if (!aiAnswers || !settings.webResults || settings.aiAnswer === false || !text || S.hasBang(q)) return null;
  const body = h('div', { class: 'answer', 'aria-live': 'polite', hidden: true });
  const head = h('button', { type: 'button', class: 'answer-head', 'aria-expanded': 'false' }, h('span', { class: 'chevron-icon' }, icon('chevron')), icon('sparkles'), 'AI Answer');
  head.addEventListener('click', () => {
    const open = head.getAttribute('aria-expanded') !== 'true';
    head.setAttribute('aria-expanded', String(open));
    body.hidden = !open;
    if (open) load(false);
  });
  const draw = (state) => {
    if (state.working) return body.replaceChildren(h('p', { class: 'summary-working' }, h('span', { class: 'spinner small' }), 'Answering…'));
    if (state.error) return body.replaceChildren(h('p', {}, state.error), h('button', { type: 'button', class: 'text-button', onclick: () => load(false) }, 'Try Again'));
    const reply = state.reply;
    const sources = S.citedSources(reply.answer, reply.sources);
    const byNumber = new Map(sources.map((src) => [Number(src.n), src]));
    const line = (t) =>
      h('span', {}, ...S.answerRuns(t).map((run) => {
        if (run.text) return run.text;
        const src = byNumber.get(run.cite);
        return src ? h('sup', { class: 'cite' }, h('a', { href: src.url, target: '_blank', rel: 'noopener noreferrer', title: src.title || src.url }, String(run.cite))) : null;
      }));
    const parts = S.summaryParts(reply.answer);
    body.replaceChildren(
      parts.opening ? h('p', {}, line(parts.opening)) : null,
      parts.points.length ? h('ul', {}, ...parts.points.map((p) => h('li', {}, line(p)))) : null,
      sources.length
        ? h('ol', { class: 'answer-sources' }, ...sources.map((src) => h('li', { value: String(src.n) }, h('a', { href: src.url, target: '_blank', rel: 'noopener noreferrer' }, S.decodeEntities(src.title) || src.url), ' ', h('span', { class: 'domain' }, hostOf(src.url)))))
        : null,
      h(
        'div',
        { class: 'summary-head' },
        h('span', { class: 'summary-byline' }, `${S.summaryByline(reply)} · from the web results’ snippets`),
        iconButton('copy', 'Copy the answer', () => navigator.clipboard.writeText(reply.answer).then(() => toast('Answer copied')).catch(() => {})),
        iconButton('refresh', 'Answer again', () => load(true)),
      ),
    );
  };
  let loading = false;
  async function load(refresh) {
    if (loading) return;
    if (!refresh && answers.has(text)) return draw({ reply: answers.get(text) });
    loading = true;
    draw({ working: true });
    try {
      const reply = await api.answer(text, refresh);
      answers.set(text, reply);
      draw({ reply });
    } catch (error) {
      draw({ error: S.summaryError(error.status, error.code, error.code ? '' : error.message) });
    } finally {
      loading = false;
    }
  }
  return h('section', { class: 'answer-card' }, head, body);
}
const summaries = new Map();
// Never code: the server's AI isn't on the device (code stays on the device).
const canSummarize = (doc, n) => aiOn && !n && !S.isCodeDoc(doc) && S.summarizable(doc.url, doc.label);

function summaryCard(doc, state) {
  const card = h('section', { class: 'summary', 'aria-live': 'polite' });
  const head = h(
    'div',
    { class: 'summary-head' },
    h('span', { class: 'summary-title' }, icon('sparkles'), 'Summary'),
    state.reply ? iconButton('copy', 'Copy the summary', () => navigator.clipboard.writeText(state.reply.summary).then(() => toast('Summary copied')).catch(() => {})) : null,
    state.reply ? iconButton('refresh', 'Summarize again', () => summarize(doc, true)) : null,
    iconButton('close', 'Hide the summary', () => {
      summaries.delete(doc.url);
      card.remove();
    }),
  );
  let body;
  if (state.working) {
    body = h('p', { class: 'summary-working' }, h('span', { class: 'spinner small' }), 'Summarizing…');
  } else if (state.reply) {
    const parts = S.summaryParts(state.reply.summary);
    body = h(
      'div',
      {},
      parts.opening ? h('p', {}, parts.opening) : null,
      parts.points.length ? h('ul', {}, ...parts.points.map((p) => h('li', {}, p))) : null,
      h('p', { class: 'summary-byline' }, S.summaryByline(state.reply)),
    );
  } else {
    body = h('div', {}, h('p', {}, state.error), h('button', { type: 'button', class: 'text-button', onclick: () => summarize(doc, false) }, 'Try Again'));
  }
  card.append(head, body);
  return card;
}

/** Shows the summary above the preview, asking the server unless it's at hand. */
async function summarize(doc, refresh) {
  const place = (state) => {
    if (selected?.url !== doc.url) return;
    const pane = $('preview');
    const card = summaryCard(doc, state);
    const old = pane.querySelector('.summary');
    if (old) old.replaceWith(card);
    else pane.prepend(card);
  };
  if (!refresh && summaries.get(doc.url)?.reply) return place(summaries.get(doc.url));
  summaries.set(doc.url, { working: true });
  place({ working: true });
  try {
    const reply = await api.summarize(doc.url, refresh);
    summaries.set(doc.url, { reply });
    place({ reply });
  } catch (error) {
    summaries.delete(doc.url);
    place({ error: S.summaryError(error.status, error.code, error.code ? '' : error.message) });
  }
}

let previewToken = 0;
async function showPreview(doc, { extractor = '' } = {}) {
  const token = ++previewToken;
  const n = note(doc);
  const bar = $('preview-bar');
  const pane = $('preview');
  // Where it opens, as the apps' toolbar: plain symbols in one group, then ⋯.
  const open = (url) => window.open(url, '_blank', 'noopener');
  const places = n
    ? [
        n.obsidian ? iconButton('note', 'Edit in Obsidian', () => (location.href = n.obsidian)) : null,
        n.niwa ? iconButton('openbook', 'View in Kura', () => open(n.niwa)) : null,
        n.konbini ? iconButton('columns', 'View Card in Konbini', () => open(n.konbini)) : null,
        // Not a work note: Hister never has one.
        n.vault ? null : iconButton('search', 'Open in Hister', () => open(api.histerPageURL(doc.url))),
      ]
    : S.isLocalFile(doc.url)
      ? [
          // Hister's copy: the file:// address is the server's.
          iconButton('open', 'Open', () => open(S.localFileURL(location.origin, doc.url))),
          iconButton('search', 'Open in Hister', () => open(api.histerPageURL(doc.url))),
        ]
      : [
        iconButton('open', 'Open in Browser', () => open(doc.url)),
        iconButton('share', 'Share', () => (navigator.share ? navigator.share({ url: doc.url, title: doc.title }).catch(() => {}) : copy(doc.url))),
        iconButton('search', 'Open in Hister', () => open(api.histerPageURL(doc.url))),
      ];
  // A code document's repo note in Kura (Repos/<name>.git.md), when there is one.
  const code = S.codeInfo(doc);
  const notePath = code && S.codeNotePath(code.repoName);
  if (notePath) {
    api.kuraNote(notePath, '').then((html) => {
      const url = html && S.readerURL('', settings.niwaURL ? settings.niwaURL.replace(/\/?$/, '/') : '', notePath);
      if (url && token === previewToken) bar.querySelector('.icon-group')?.prepend(iconButton('openbook', 'The Repo’s Note in Kura', () => open(url)));
    }).catch(() => {});
  }
  fill(bar, 
    !wide() ? iconButton('back', 'Back', () => history.back()) : null,
    h('span', { class: 'where' }, n || S.isLocalFile(doc.url) ? doc.title || n?.place || doc.url : doc.domain || hostOf(doc.url)),
    h('div', { class: 'icon-group', role: 'group', 'aria-label': 'Open' }, places),
    canSummarize(doc, n) ? iconButton('sparkles', 'Summarize this page', () => summarize(doc, false)) : null,
    pageMenu(doc, n),
  );
  pane.replaceChildren(h('div', { class: 'spinner' }));
  try {
    // A work note's preview is Kura's sanitized HTML (Hister never has it); shown, never cached.
    const p = n && n.vault ? { title: doc.title, content: await api.kuraNote(n.path, n.vault) } : await api.preview(doc.url, extractor);
    if (token !== previewToken) return;
    const frame = h('iframe', { title: 'Preview', sandbox: 'allow-popups allow-popups-to-escape-sandbox', referrerpolicy: 'no-referrer' });
    frame.srcdoc = previewHTML(doc, p, n);
    pane.replaceChildren(frame);
    // A summary asked for this page (Summarize, then Show As) stays above it.
    const kept = summaries.get(doc.url);
    if (kept) pane.prepend(summaryCard(doc, kept));
  } catch (error) {
    if (token !== previewToken) return;
    pane.replaceChildren(status("Preview Not Shown", error.message, () => showPreview(doc, { extractor })));
  }
}

function escapeHTML(t) {
  return String(t ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

function previewHTML(doc, p, n) {
  const css = getComputedStyle(document.documentElement);
  const v = (name) => css.getPropertyValue(name).trim();
  const images = settings.previewImages ? '* data:' : 'data:';
  const d = p.details || {};
  const stored = d.label || doc.label || '';
  // A note's chip names its vault ("Work vault"), as in the lists.
  const label = stored === 'vault' ? S.vaultChip(doc.url, kuraVaults).text : stored;
  // The label's own colour (the page's tokens don't reach the srcdoc).
  const labelColor = label ? v(`--chip${S.labelChipIndex(label)}`) : '';
  const tags = (d.metadata && Array.isArray(d.metadata.tags) ? d.metadata.tags : []).filter((t) => typeof t === 'string');
  const date = (s) => (s ? new Date(s * 1000).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' }) : '');
  // A Kura note's dates are its row's (the preview has none); none, no line.
  const dates = S.previewDates(p, doc, date);
  return `<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src ${images}; style-src 'unsafe-inline'; font-src data:">
<meta name="referrer" content="no-referrer"><base target="_blank">
<style>
:root{color-scheme:${v('color-scheme') || 'dark'}}
body{font-family:-apple-system,system-ui,sans-serif;color:${v('--text')};background:${v('--bg')};margin:0 auto;padding:16px 20px 48px;max-width:56em;line-height:1.55;overflow-wrap:anywhere;font-size:${document.documentElement.style.fontSize || '100%'}}
header{border-bottom:1px solid ${v('--line')};margin-bottom:1.25em;padding-bottom:.75em}
h1{font-size:1.5em;margin:0 0 .3em;line-height:1.25}
.meta{color:${v('--secondary')};font-size:.85em;margin:.2em 0}
a{color:${v('--accent')}} img,video,figure{max-width:100%;height:auto;border-radius:6px}
svg,picture,canvas,iframe,object,embed{max-width:100%;height:auto} figure{margin:1em 0}
pre,code{font-family:ui-monospace,monospace;font-size:.9em;background:${v('--card')};border-radius:6px}pre{padding:12px;overflow-x:auto}
blockquote{margin:1em 0;padding-left:1em;border-left:3px solid ${v('--line')};color:${v('--secondary')}}
table{border-collapse:collapse;display:block;overflow-x:auto}td,th{border:1px solid ${v('--line')};padding:4px 8px}
.chip{display:inline-block;margin-top:.5em;padding:1px 9px;border-radius:999px;border:1px solid currentColor;background:transparent;font-size:.8em;color:${labelColor || v('--kept')}}
</style></head><body><header>
<h1>${escapeHTML(p.title || doc.title || (n && n.path ? n.path.replace(/\.md$/, '').split('/').pop() : '') || doc.url)}</h1>
<p class="meta">${escapeHTML(n && n.place ? n.place : doc.domain || hostOf(doc.url))}</p>
${dates ? `<p class="meta">${escapeHTML(dates)}</p>` : ''}
${p.meta && p.meta.author ? `<p class="meta">${escapeHTML(p.meta.author)}</p>` : ''}
${label ? `<span class="chip">${escapeHTML(label)}</span>` : ''}
${tags.length ? `<p class="meta">${tags.map((t) => { const u = S.kuraTagURL(settings.niwaURL, t); return u ? `<a href="${escapeHTML(u)}">#${escapeHTML(t)}</a>` : '#' + escapeHTML(t); }).join(' ')}</p>` : ''}
</header><article>${p.content || ''}</article></body></html>`;
}

function pageMenu(doc, n) {
  const wrap = h('div', { class: 'menu' });
  const listEl = h('div', { class: 'menu-list', hidden: true, role: 'menu' });
  const close = () => (listEl.hidden = true);
  const item = (text, onclick, cls) => h('button', { type: 'button', role: 'menuitem', class: cls, onclick: () => (close(), onclick()) }, text);
  const populate = async () => {
    // As the apps: the places are in the bar; here the rest.
    const items = [];
    // A file is Hister's to keep as it watches it: no label, no delete.
    // Nor a code document: code-import owns it.
    const file = S.isLocalFile(doc.url) || S.isCodeDoc(doc);
    if (!n && !file) items.push(item('Edit Label…', () => labelPicker(doc)));
    if (canSummarize(doc, n)) items.push(item('Summarize', () => summarize(doc, false)));
    items.push(item('Copy Link', () => copy(S.isLocalFile(doc.url) ? S.localFileURL(location.origin, doc.url) : doc.url)));
    // A web page elsewhere, as the apps' menu has it: Archive.org,
    // Archive.is and the build's front ends (never a note, a file or code:
    // a note is Kura's, and archives can't reach a private forge). Links only.
    if (!isNoteDoc(doc, n) && !file) {
      for (const link of S.elsewhereLinks(doc.url, FRONTENDS)) {
        items.push(item(link.name === 'Original' ? `Open Original on ${link.site}` : link.name.startsWith('Archive.') ? `Open on ${link.name}` : `Open in ${link.name}`,
          () => window.open(link.url, '_blank', 'noopener')));
      }
    }
    // Show As goes here, before Delete, once Hister names the extractors.
    const showAs = h('div', { class: 'show-as', role: 'none' });
    // No Delete for a work note (Hister never has one) or a file.
    fill(listEl, ...items, showAs, ...((n && n.vault) || file ? [] : [h('hr'), item('Delete', () => deleteWithUndo(doc), 'danger')]));
    // Show As is for web pages only: a note's address is never sent to
    // Hister's extractors (a private vault's must never reach Hister at all).
    if (isNoteDoc(doc, n)) return;
    try {
      const names = await api.extractors(doc.url);
      if (names.length > 1) {
        fill(showAs, h('div', { class: 'heading' }, 'Show As'),
          ['Default', ...names].map((name) => item(name, () => showPreview(doc, { extractor: name === 'Default' ? '' : name }))));
      }
    } catch (_) {}
  };
  const button = iconButton('more', 'More actions', (e) => {
    e.stopPropagation();
    listEl.hidden = !listEl.hidden;
    if (!listEl.hidden) populate();
  });
  wrap.append(button, listEl);
  return wrap;
}

// --- Dialogs ---------------------------------------------------------------------

function dialog(title, body) {
  const d = $('dialog');
  d.replaceChildren(h('div', { class: 'dialog-head' }, h('h2', {}, title), iconButton('close', 'Close', () => d.close())), h('div', { class: 'dialog-body' }, body));
  d.showModal();
  return d;
}

function labelPicker(doc) {
  const current = doc.label || '';
  const pick = async (label) => {
    $('dialog').close();
    try {
      await api.setLabel(doc.url, label);
      doc.label = label;
      toast(label ? `Labelled ${label}` : 'Label removed');
      showPreview(doc);
    } catch (error) {
      toast(error.message);
    }
  };
  const row = (label) =>
    h('li', { class: 'row', role: 'button', tabindex: '0', onclick: () => pick(label) }, label ? chip(label) : h('span', {}, 'No Label'), label === current ? h('span', { 'aria-label': 'Current' }, '✓') : h('span'));
  const body = h('ul', { class: 'rows' }, row(''));
  for (const c of collections) {
    body.append(h('li', { class: 'section-head' }, S.collectionTitle(c.name)));
    for (const label of c.labels) body.append(row(label));
  }
  const grouped = new Set(collections.flatMap((c) => c.labels));
  const other = labels.filter((l) => !grouped.has(l));
  if (other.length) {
    body.append(h('li', { class: 'section-head' }, collections.length ? 'Other Labels' : 'Labels'));
    for (const label of other) body.append(row(label));
  }
  dialog('Label', body);
}

/**
 * Add Page, as the apps' (the iPhone's + tab, the iPad's sidebar, the
 * Mac's File menu): an address and an optional title, saved in Hister
 * through the small-web gateway (POST /smallweb/api/save). Checked here
 * first (api.checkPageURL: http, https, gemini and gopher, no user name,
 * never a note). The gateway answers before it fetches, so a good answer
 * is "Saving…", not "Saved". The share target opens it filled in; only
 * Save sends anything.
 */
function addPage(prefill = {}) {
  if (!SMALLWEB) return;
  const field = (attrs) => h('input', { autocapitalize: 'off', autocorrect: 'off', spellcheck: 'false', ...attrs });
  const address = field({ id: 'add-url', type: 'url', inputmode: 'url', placeholder: 'https://example.com/article', autocomplete: 'off', value: prefill.url || '' });
  const title = field({ id: 'add-title', type: 'text', placeholder: 'Optional', autocomplete: 'off', value: prefill.title || '' });
  const message = h('p', { class: 'add-message', role: 'status', 'aria-live': 'polite' });
  const save = h('button', { type: 'submit', class: 'add-save' }, 'Save');
  const say = (text, bad = false) => {
    message.textContent = text;
    message.classList.toggle('bad', bad);
  };
  if ('url' in prefill && !prefill.url) say('No address came with what was shared: paste one here.', true);
  const form = h(
    'form',
    { class: 'add-page', novalidate: true },
    h('div', { class: 'group' },
      h('label', { class: 'item', for: 'add-url' }, h('span', {}, 'Address'), address),
      h('label', { class: 'item', for: 'add-title' }, h('span', {}, 'Title'), title)),
    h('p', { class: 'footnote' }, 'The small-web gateway fetches the page and saves it in your pages: web, Gemini and Gopher alike. Notes stay in Kura.'),
    message,
    h('div', { class: 'add-actions' }, h('button', { type: 'button', class: 'button', onclick: () => $('dialog').close() }, 'Cancel'), save),
  );
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const checked = api.checkPageURL(address.value, { isNote: (url) => isNoteDoc({ url }) });
    if (checked.error) return say(checked.error, true);
    address.value = checked.url;
    save.disabled = true;
    say('Sending…');
    const reply = await api.savePage(checked.url, title.value.trim());
    save.disabled = false;
    if (!reply.ok) return say(reply.message, true);
    $('dialog').close();
    toast(reply.message);
  });
  dialog('Add Page', form);
  (prefill.url ? save : address).focus();
}

/**
 * Delete with undo, for dd and the ⋯ menu alike: the row goes at once and
 * a toast offers Undo for 6 s; only then is the page deleted (the dry run
 * still checks it's exactly one). A second delete while one waits sends
 * the first at once; leaving the page sends it too. If the delete fails,
 * the row comes back.
 */
const UNDO_MS = 6000;
let pendingDelete = null;
function removeRows(url) {
  return [...document.querySelectorAll('.row')]
    .filter((r) => r._doc && r._doc.url === url)
    .map((row) => {
      const place = { row, parent: row.parentNode, next: row.nextSibling };
      row.remove();
      return place;
    });
}
function restoreRows(places) {
  for (const { row, parent, next } of places) {
    if (!parent || !parent.isConnected) continue;
    parent.insertBefore(row, next && next.parentNode === parent ? next : null);
  }
}
function deleteWithUndo(doc) {
  if (pendingDelete) commitDelete();
  const title = doc.title || doc.url;
  const places = removeRows(doc.url);
  if (selected && selected.url === doc.url) {
    selected = null;
    if (wide()) $('preview').replaceChildren(status('No Page Selected', 'Select a page to preview it.'));
  }
  if (!wide() && route().view === 'page') history.back();
  const note = h('div', { class: 'toast', role: 'status' },
    h('span', {}, `Deleted “${title}”`),
    h('button', { type: 'button', class: 'toast-action', onclick: undoDelete }, 'Undo'));
  document.body.append(note);
  pendingDelete = { doc, places, note, timer: setTimeout(commitDelete, UNDO_MS) };
}
function undoDelete() {
  const p = pendingDelete;
  if (!p) return;
  pendingDelete = null;
  clearTimeout(p.timer);
  p.note.remove();
  restoreRows(p.places);
}
async function commitDelete({ keepalive = false } = {}) {
  const p = pendingDelete;
  if (!p) return;
  pendingDelete = null;
  clearTimeout(p.timer);
  p.note.remove();
  try {
    await api.deletePage(p.doc.url, { keepalive });
  } catch (error) {
    restoreRows(p.places);
    toast(error.message);
  }
}
addEventListener('pagehide', () => commitDelete({ keepalive: true }));

// --- Settings ------------------------------------------------------------------

function viewSettings() {
  // A place of its own: the sidebar's gear, or the Settings tab.
  setTitle('Settings');
  listSearch = '';
  fill($('list-top'), );
  const toggle = (key, title) => {
    const input = h('input', { type: 'checkbox', class: 'switch', 'aria-label': title });
    input.checked = !!settings[key];
    input.addEventListener('change', () => changeSetting(key, input.checked));
    return h('label', { class: 'item' }, h('span', {}, title), input);
  };
  const choice = (key, title, options) => {
    const select = h('select', { 'aria-label': title }, options.map(([v, t]) => h('option', { value: String(v), selected: String(settings[key]) === String(v) }, t)));
    select.addEventListener('change', () => changeSetting(key, typeof settings[key] === 'number' ? Number(select.value) : select.value));
    return h('label', { class: 'item' }, h('span', {}, title), select);
  };
  const text = (key, title, placeholder, type = 'url') => {
    const input = h('input', { type, value: settings[key] || '', placeholder, 'aria-label': title, autocapitalize: 'off', autocorrect: 'off', spellcheck: 'false' });
    input.addEventListener('change', () => changeSetting(key, input.value.trim()));
    return h('label', { class: 'item' }, h('span', {}, title), input);
  };
  const group = (title, items, foot) => [h('h2', {}, title), h('div', { class: 'group' }, items), foot ? h('p', { class: 'footnote' }, foot) : null];
  $('list').replaceChildren(
    h(
      'div',
      { class: 'settings' },
      accountGroup(group),
      group('Appearance', [
        choice('palette', 'Theme', Object.entries(S.PALETTES).map(([key, p]) => [key, p.name])),
        choice('theme', 'Appearance', [['system', 'System'], ['day', 'Light'], ['night', 'Dark']]),
        // The rooms' five sizes by their names (Standard is the system's),
        // with Medium and the two largest of the app's.
        choice('textSize', 'Text Size', [['xSmall', 'Extra Small'], ['small', 'Small'], ['medium', 'Medium'], ['system', 'Standard'], ['large', 'Large'], ['xLarge', 'Extra Large'], ['xxLarge', 'Extra Extra Large'], ['xxxLarge', 'Largest']]),
        toggle('previewImages', 'Images in Previews'),
      ]),
      exportGroup(group),
      group('Searching', [toggle('rememberOpened', 'Remember What You Open'), toggle('showOpened', 'Show Opened'),
        choice('resultStyle', 'Result Style', [['tint', 'Tint'], ['solid', 'Solid'], ['bar', 'Left Bar'], ['none', 'None']]),
        toggle('smallWebTab', 'Small Web Tab'),
        choice('smallWebOpen', 'Open Small Web Results', [['gateway', 'Through the Gateway'], ['direct', 'In a Gemini App']]), toggle('searchFilters', 'Search Filters'),
        toggle('foldRepeats', 'Fold Repeated Sites'), toggle('labelSuggestions', 'Labels in Search Page Suggestions'), toggle('webResults', 'Web Results'), toggle('aiAnswer', 'AI Answer'),
      ],
        'Kept in this browser only. Fold Repeated Sites shows the first of several pages in a row from one site, then “N more”.'),
      pillsGroup(group),
      group('Feeds', [text('newsBlurURL', 'NewsBlur', 'https://newsblur.example/')], 'For Subscribe in NewsBlur, which opens NewsBlur with a list’s feed.'),
      group('Search History', [
        toggle('searchHistory', 'Recent Searches'),
        h('div', { class: 'item' }, h('button', { type: 'button', class: 'button', style: 'margin:0;color:var(--danger)', onclick: () => ((recents = []), writeLocal('shioriAppRecents', []), toast('Cleared')) }, 'Clear Recent Searches')),
      ], 'Kept in this browser only.'),
      group('Notes', [text('obsidianVault', 'Obsidian Vault', 'Your vault’s name', 'text'), text('niwaURL', 'Kura', 'https://kura.example/'), text('konbiniURL', 'Konbini', 'https://konbini.example/'), machiyaRow()],
        settings.niwaURL ? 'Signed in, your theme and text size follow you to the Machiya rooms. Signing in and out happen on Kura’s own pages.' : ''),
      group('About', [
        h('div', { class: 'item' }, h('span', {}, 'Saving pages'), h('span', { style: 'color:var(--secondary);text-align:right' },
          SMALLWEB ? 'Add Page, or share a link to Shiori where your browser lists it (installed from Chrome or Edge). Safari’s extension is in the Shiori app.' : 'Safari’s extension, the share sheet and Shortcuts are in the Shiori app.')),
        statusURL ? h('div', { class: 'item' }, h('span', {}, 'Server'), statusLink()) : null,
        // The source (AGPL-3.0 section 13), only when the build names it.
        SOURCE_URL ? h('div', { class: 'item' }, h('span', {}, 'Source'), h('a', { href: SOURCE_URL, target: '_blank', rel: 'noopener noreferrer' }, 'View the source')) : null,
        SOURCE_URL ? h('div', { class: 'item' }, h('span', {}, 'Licence'), h('span', { style: 'color:var(--secondary)' }, S.LICENCE)) : null,
      ],
        'Install this as an app: Share → Add to Home Screen (iPhone, iPad), File → Add to Dock (Safari on the Mac), or Install in the browser’s menu (Chrome, Edge).'),
    ),
  );
}

/**
 * Settings → Account, first: who Hister says is signed in on this browser
 * (S.histerAccount from /api/profile), with Sign Out (the helper's sessions
 * page: its sign-out takes only its own origin's posts), or Sign In when
 * signed out. Nothing while Hister has no users.
 */
function accountGroup(group) {
  const box = h('div', { hidden: true });
  const sessions = S.histerSessionsURL(ROOMS_STAMP, location.origin);
  const signIn = S.histerSignInURL(ROOMS_STAMP, location.origin, location.href);
  void api.profile().then(({ status, json }) => {
    const account = S.histerAccount(status, json);
    if (account.state === 'none') return;
    const row = account.state === 'in'
      ? h('div', { class: 'item' }, h('span', {}, 'Signed in as ', h('strong', {}, account.name)), sessions ? h('a', { class: 'link-button', href: sessions }, 'Sign Out…') : null)
      : h('div', { class: 'item' }, h('span', {}, 'Not signed in'), signIn ? h('a', { class: 'link-button', href: signIn }, 'Sign In') : null);
    // Not null as a child: replaceChildren writes it out as the text "null".
    box.replaceChildren(...group('Account', [row],
      account.state === 'in' ? 'Signed in once, every Machiya room knows you. Sign Out opens Hister’s sessions page: end this browser’s session, or every device’s.' : '').filter(Boolean));
    box.hidden = false;
  });
  return box;
}

/** Settings → Pills: their order, and which show (S.pillEditor), redrawn in place. */
function pillsGroup(group) {
  const items = S.PILLS.filter(([key]) => !['images', 'videos', 'news'].includes(key) && (key !== 'files' || hasLocalFiles));
  const box = h('div', {});
  const draw = (focus) => {
    box.replaceChildren(S.pillEditor(items, settings.pills, (next, control) => {
      changeSetting('pills', next);
      draw(control);
    }, { rowClass: 'item' }));
    if (focus) {
      const again = [...box.querySelectorAll('[aria-label]')].find((n) => n.getAttribute('aria-label') === focus);
      (again && !again.disabled ? again : box.querySelector('.switch'))?.focus();
    }
  };
  draw();
  return group('Pills', [box], 'The pills over every list and search, in this order. All always shows; Opened only with Show Opened, Small Web only with its tab.');
}

/**
 * Settings → Notes → Machiya, as the apps' Sign in to Machiya: whether
 * Kura knows you (its /api/prefs answering 200, 401 or 404), with Sign In
 * (Kura's /signin) or Sign Out (Kura's Settings: its sign-out is a form
 * on Kura's own origin, which this host doesn't pass). Asked afresh each
 * time Settings opens. Only with Kura's address set.
 */
function machiyaRow() {
  if (!settings.niwaURL) return null;
  const state = h('span', { class: 'machiya-state' });
  const action = h('span', {});
  const row = h('div', { class: 'item' }, h('span', {}, 'Machiya'), h('span', { class: 'machiya-account' }, state, action));
  const draw = () => {
    const signIn = S.machiyaSignInURL(settings.niwaURL);
    const link = (href, text) => (href ? h('a', { class: 'link-button', href }, text) : null);
    const [text, a] = {
      200: ['Signed in', link(signIn && signIn.replace(/signin$/, 'settings'), 'Sign Out…')],
      401: ['Not signed in', link(signIn, 'Sign In')],
      404: ['Kura doesn’t ask who you are', null],
      0: ['Kura didn’t answer', null],
    }[kuraAccount.status] || ['Checking…', null];
    state.textContent = text;
    fill(action, a);
  };
  draw();
  loadKuraAccount().then(() => row.isConnected && draw());
  return row;
}

/** Settings → Export & Feed, for the list last on screen (as iOS; File on the Mac). */
function exportGroup(group) {
  const list = shownList;
  if (!list) return null;
  const items = [];
  if (list.query) {
    for (const [format, name] of [['json', 'JSON'], ['csv', 'CSV'], ['rss', 'RSS']]) {
      const button = h('button', { type: 'button', class: 'link-button' }, `Export as ${name}…`);
      button.addEventListener('click', async () => {
        button.disabled = true;
        button.textContent = 'Exporting…';
        try {
          const pages = await allResults(list);
          const data = S.exportData(pages, format, list.title, list.feed || '');
          const type = { json: 'application/json', csv: 'text/csv', rss: 'application/rss+xml' }[format];
          const a = h('a', { href: URL.createObjectURL(new Blob([data], { type })), download: S.exportFileName(list.title, format) });
          document.body.append(a);
          a.click();
          setTimeout(() => (URL.revokeObjectURL(a.href), a.remove()), 1000);
        } catch (error) {
          toast(error.message || "Couldn't export");
        } finally {
          button.disabled = false;
          button.textContent = `Export as ${name}…`;
        }
      });
      items.push(h('div', { class: 'item' }, button));
    }
  }
  if (list.feed) {
    items.push(h('div', { class: 'item' }, h('button', { type: 'button', class: 'link-button', onclick: () => copy(list.feed) }, 'Copy Feed Link')));
    const subscribe = S.newsBlurSubscribeURL(settings.newsBlurURL, list.feed);
    if (subscribe) items.push(h('div', { class: 'item' }, h('a', { class: 'link-button', href: subscribe, target: '_blank', rel: 'noopener' }, 'Subscribe in NewsBlur')));
  }
  return group('Export & Feed', items, `For ${list.title}, the list you were on. An export holds the whole list (up to 1,000), not only what’s loaded.`);
}

/** The whole list, page after page, up to 1,000 (as the app's export). */
async function allResults(list) {
  const out = [];
  const seen = new Set();
  let key = '';
  do {
    // A notes list's from Kura; any other from Hister (pages only, All too).
    const reply = await (list.source === 'notes' ? api.kura : api.search)(list.query, { sort: list.sort || '', pageKey: key, limit: 100 });
    for (const d of reply.documents) {
      // No private vault's note leaves the device in an export.
      if (seen.has(d.url) || S.isPrivateNote(d.url)) continue;
      seen.add(d.url);
      const text = new DOMParser().parseFromString(`<div>${d.text || ''}</div>`, 'text/html').body.textContent || '';
      out.push({ url: d.url, title: d.title || '', domain: d.domain || hostOf(d.url), label: d.label || '', added: d.added, updated: d.updated || d.added, text: text.trim() });
    }
    key = reply.next;
  } while (key && out.length < 1000);
  return out.slice(0, 1000);
}

// Tapping or clicking into a search field selects what's in it, so typing
// replaces it at once. The select waits for the pointer's own mouseup,
// which would otherwise drop the selection back to a caret.
function selectOnFocus(input) {
  let fromPointer = false;
  input.addEventListener('pointerdown', () => {
    fromPointer = document.activeElement !== input;
  });
  input.addEventListener('focus', () => {
    if (!input.value) return;
    input.select();
    // iOS Safari ignores select() in focus; set the range explicitly too.
    setTimeout(() => { if (document.activeElement === input) input.setSelectionRange(0, input.value.length); }, 0);
  });
  input.addEventListener('mouseup', (e) => {
    if (fromPointer) {
      e.preventDefault();
      fromPointer = false;
    }
  });
}

// --- Search field: at the top of the Library, as in the apps ---------------------

// One field, made once, so typing keeps its focus while the list redraws.
const searchInput = h('input', { type: 'search', placeholder: 'Search All', autocapitalize: 'off', autocorrect: 'off', spellcheck: 'false', enterkeyhint: 'search', 'aria-label': 'Search' });
let liveTimer = 0;
function searchTo(text, { record = false } = {}) {
  const q = text.trim();
  const { view, params } = route();
  const s = scopeOf(params);
  if (!q) return view === 'search' && go('library', { s }, { replace: true });
  if (record) recordSearch(q);
  // While typing, one history entry for the whole search. Only a search
  // run on purpose (Return, the magnifier) asks the web (w=1): each web
  // search counts (a paid search API would charge it), so live typing
  // searches your pages and notes alone. Frugal, as AI is.
  go('search', { q, s, ...(record ? { w: '1' } : {}) }, { replace: view === 'search' });
}

// No suggestions under the field (as in the apps): recent searches are in the sidebar. Instead, type-ahead: the rest
// of a recent search, or of the web's autocomplete, grey after the caret;
// Tab or → takes it, and so does a tap on it (no Tab on a phone). Nothing
// after a delete, so it never fights a correction.
const ghostTyped = h('span', { class: 'typed' });
const ghostRest = h('span', { class: 'rest', title: 'Tab to complete' });
const ghost = h('div', { class: 'ghost', 'aria-hidden': 'true', hidden: true }, ghostTyped, ghostRest);
let ghostText = '';
let webCompletions = { q: '', list: [] };
let completeTimer = 0;
let completeToken = 0;
function showGhost(rest) {
  ghostText = rest;
  ghost.hidden = !rest;
  if (!rest) return;
  // The same box and type as the field, so the grey lines up with the text.
  const css = getComputedStyle(searchInput);
  for (const p of ['font', 'letterSpacing', 'paddingLeft', 'paddingRight', 'paddingTop', 'borderLeftWidth', 'borderTopWidth', 'textIndent']) ghost.style[p] = css[p];
  ghost.style.borderStyle = 'solid';
  ghost.style.borderColor = 'transparent';
  // One line box exactly the field's content height: the field centres its
  // text in that box, and so does a line of that height. Centring the
  // overlay with flexbox left the grey a pixel high.
  const content = searchInput.clientHeight - parseFloat(css.paddingTop) - parseFloat(css.paddingBottom);
  ghost.style.lineHeight = `${content}px`;
  ghostTyped.textContent = searchInput.value;
  ghostRest.textContent = rest;
}
function updateGhost(fetch = true) {
  const v = searchInput.value;
  const atEnd = searchInput.selectionStart === v.length && searchInput.selectionEnd === v.length;
  if (document.activeElement !== searchInput || !atEnd || searchInput.scrollLeft > 0) return showGhost('');
  const fits = webCompletions.q && v.toLowerCase().startsWith(webCompletions.q.toLowerCase());
  showGhost(S.typeAhead(v, [...(settings.searchHistory === false ? [] : recents), ...(fits ? webCompletions.list : [])]));
  clearTimeout(completeTimer);
  if (!fetch || !settings.webResults || v.trim().length < 2) return;
  completeTimer = setTimeout(async () => {
    const token = ++completeToken;
    const list = await api.autocomplete(v);
    if (token !== completeToken || searchInput.value !== v) return;
    webCompletions = { q: v, list };
    updateGhost(false);
  }, 150);
}
function acceptGhost() {
  if (!ghostText) return false;
  searchInput.value += ghostText;
  showGhost('');
  searchInput.setSelectionRange(searchInput.value.length, searchInput.value.length);
  searchInput.dispatchEvent(new Event('input'));
  return true;
}
ghostRest.addEventListener('pointerdown', (e) => {
  e.preventDefault();
  acceptGhost();
});
searchInput.addEventListener('keydown', (e) => {
  if (!ghostText) return;
  const atEnd = searchInput.selectionStart === searchInput.value.length;
  if ((e.key === 'Tab' && !e.shiftKey) || (e.key === 'ArrowRight' && atEnd && !e.shiftKey && !e.metaKey && !e.altKey)) {
    e.preventDefault();
    acceptGhost();
  } else if (e.key === 'Escape') {
    showGhost('');
  }
});
searchInput.addEventListener('blur', () => showGhost(''));
searchInput.addEventListener('input', (e) => {
  if (e.inputType && e.inputType.startsWith('delete')) showGhost('');
  else updateGhost();
});
searchInput.addEventListener('input', () => {
  clearTimeout(liveTimer);
  const q = searchInput.value.trim();
  if (!q) return searchTo('');
  // No search while typing (the user's call): Enter or the magnifier runs
  // it, and the field keeps the keyboard meanwhile. Clearing it is at once.
});
searchInput.addEventListener('keydown', (e) => {
  if (e.key !== 'Enter') return;
  e.preventDefault();
  clearTimeout(liveTimer);
  searchTo(searchInput.value, { record: true });
});
selectOnFocus(searchInput);
// The X and, on a phone, the magnifier (submits, as Return does).
const searchButtons = S.fieldButtons(searchInput, () => {
  clearTimeout(liveTimer);
  searchTo(searchInput.value, { record: true });
});
$('search-top').append(h('div', { class: 'searchfield' }, searchInput, ghost, ...searchButtons));

// --- Chrome: sidebar and tabs ----------------------------------------------------

/** Your server's status page, if the build was given one (a meta tag). */
const statusURL = document.querySelector('meta[name="shiori-status"]')?.content || '';
const statusLink = () =>
  statusURL ? h('a', { class: 'status-link', href: statusURL, target: '_blank', rel: 'noopener' }, 'Status') : null;

/** The current search unless it's already recent, then the recent ones: five at most. */
function sidebarSearches(current) {
  const list = settings.searchHistory === false ? [] : [...recents];
  if (current && !list.some((r) => r.toLowerCase() === current.toLowerCase())) list.unshift(current);
  return list.slice(0, 5);
}

function sidebar(current) {
  const nav = $('sidebar');
  const item = (text, view, params, iconName, active, color) =>
    h(
      'button',
      { type: 'button', 'aria-current': active ? 'page' : undefined, onclick: () => go(view, params) },
      h('span', { class: 'nav-icon' }, color ? h('span', { class: 'dot', style: `--chip:${color}` }) : iconName ? icon(iconName) : null),
      text,
    );
  const { view, params } = current;
  const q = params.get('q');
  // Settings is a gear beside Library, as the Mac app's sidebar has it;
  // the list's own bar then holds nothing, and the search field sits at
  // the top of the column.
  const gear = h('button', { type: 'button', class: 'sidebar-gear', 'aria-label': 'Settings', title: 'Settings',
    'aria-current': view === 'settings' ? 'page' : undefined, onclick: () => go('settings') }, icon('gear'));
  // Add Page beside them, as the iPad app's + on its sidebar.
  const add = SMALLWEB ? h('button', { type: 'button', class: 'sidebar-gear sidebar-add', 'aria-label': 'Add Page', title: 'Add Page', onclick: () => addPage() }, icon('plus')) : null;
  fill(nav, 
    // The Machiya rooms' switcher before the gear.
    h('div', { class: 'sidebar-top' }, item('Library', 'library', {}, 'library', view === 'library'), add, S.roomsSwitcher(ROOMS, 'shiori', { settings: ROOMS_SETTINGS }), gear),
    // The search on screen, then the recent ones, five in all, as the Mac's
    // sidebar has them: the history, now there's no list under the field.
    ...sidebarSearches(view === 'search' ? q : null).map((text) =>
      item(text, 'search', { q: text, s: params.get('s') || 'all', w: '1' }, 'search', view === 'search' && q === text)),
    Object.keys(aliases).length ? h('h2', {}, 'Collections') : null,
    ...Object.keys(aliases).sort().map((a) => {
      const row = item(S.collectionTitle(a), 'list', { q: a, t: S.collectionTitle(a) }, S.collectionIcon(a), view === 'list' && q === a);
      // The collection's colour, as a label's dot has its own.
      row.dataset.tint = chipVar(a);
      return row;
    }),
    labels.length ? h('h2', {}, 'Labels') : null,
    ...labels.map((l) => item(l, 'list', { q: `label:${l}`, t: l }, null, view === 'list' && q === `label:${l}`, chipVar(l))),
    // A rule above the status link, not an empty heading.
    statusURL ? h('div', { class: 'sidebar-rule', role: 'separator' }) : null,
    statusLink(),
  );
  // Not the rooms' glyphs: they wear their room's colour (app.css).
  nav.querySelectorAll('svg').forEach((s) => {
    if (s.closest('.rooms')) return;
    const tint = s.closest('button')?.dataset.tint;
    s.setAttribute('style', `width:18px;height:18px;stroke:${tint || 'currentColor'};fill:none;stroke-width:1.7`);
  });
}

function tabs(view) {
  const tab = (name, title, iconName, target) =>
    h('button', { type: 'button', 'aria-current': view === target || (target === 'labels' && view === 'list') ? 'page' : undefined, onclick: () => go(target) }, icon(iconName), h('span', {}, title));
  // As the iPhone app's Library · Labels · + (Add Page, with the
  // small-web gateway) · Settings, then the Machiya rooms, a sheet.
  // Settings is a tab, not a gear in a title row: the tabs' own views have
  // none.
  const add = SMALLWEB ? h('button', { type: 'button', class: 'add-tab', onclick: () => addPage() }, icon('plus'), h('span', {}, 'Add Page')) : null;
  // The rooms' tab-bar menu: it opens above the tab, as theirs does.
  const rooms = S.roomsSwitcher(ROOMS, 'shiori', { tab: true, settings: ROOMS_SETTINGS });
  fill($('tabs'), tab('library', 'Library', 'library', 'library'), tab('labels', 'Labels', 'tag', 'labels'), add,
    tab('settings', 'Settings', 'gear', 'settings'), rooms);
  $('tabs').querySelector('button').setAttribute('aria-current', view === 'library' || view === 'search' ? 'page' : 'false');
}

// --- Render ------------------------------------------------------------------------

function render() {
  const current = route();
  const { view, params } = current;
  if (view === 'page') {
    // A narrow screen: the page in place of the list.
    document.body.classList.add('phone-preview');
    const url = params.get('url') || '';
    // Only the address (a reload, a link): a note's is known by it, so it
    // previews from Kura as from a list, never from Hister.
    const doc = lastPage && lastPage.url === url ? lastPage : { url, title: '', domain: hostOf(url), ...(isNoteDoc({ url }) ? { label: 'vault' } : {}) };
    showPreview(doc);
    return;
  }
  document.body.classList.remove('phone-preview');
  $('search-top').hidden = !(view === 'library' || view === 'search');
  const q = view === 'search' ? params.get('q') || '' : '';
  if (document.activeElement !== searchInput) searchInput.value = q;
  sidebar(current);
  tabs(view);
  if (view === 'labels') viewLabels();
  else if (view === 'list') viewList(params);
  else if (view === 'search') viewSearch(params);
  else if (view === 'settings') viewSettings();
  else viewLibrary(params);
  if (wide() && !selected) $('preview').replaceChildren(status('No Page Selected', 'Select a page to preview it.'));
}

// --- vi keys (the apps and the search page have the same set) -------------------
// j/k move through the list (beside the pane, the page previews as it's
// reached, as the Mac's selection does), h/l through the pills, Enter/o
// opens (a note in Obsidian), p previews, gg/G top and bottom, / the
// search field, Esc backs out, y copies the link, e edits the label, dd
// deletes (with Undo), ? lists them. Never while typing in a field, with a
// dialog open, or with Meta/Ctrl/Alt held (S.vimKey decides).
const keyboard = (() => {
  let state = {};
  let current = null;
  let help = null;
  const inField = (t) => !!t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName));
  const rows = () => [...document.querySelectorAll('#list .row')].filter((r) => r.offsetParent !== null);
  const docOf = (row) => row && row._doc;
  const hrefOf = (row) => {
    const doc = docOf(row);
    if (!doc) return row.querySelector('a[href]')?.href || '';
    return S.isLocalFile(doc.url) ? S.localFileURL(location.origin, doc.url) : doc.url;
  };
  function mark(row) {
    if (current) current.classList.remove('kbd-current');
    current = row || null;
    if (!current) return;
    current.classList.add('kbd-current');
    current.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    const doc = docOf(current);
    // Beside the pane, reaching a page previews it (not an "open").
    if (doc && wide()) {
      selected = doc;
      document.querySelectorAll('.row[aria-selected="true"]').forEach((r) => r.setAttribute('aria-selected', 'false'));
      current.setAttribute('aria-selected', 'true');
      showPreview(doc);
    }
  }
  function move(step) {
    const list = rows();
    if (!list.length) return;
    const at = list.indexOf(current);
    if (at < 0) return mark(step > 0 ? list[0] : list[list.length - 1]);
    mark(list[Math.max(0, Math.min(list.length - 1, at + step))]);
  }
  function pill(step) {
    const pills = [...document.querySelectorAll('#list-top .segments button')];
    const at = pills.findIndex((b) => b.getAttribute('aria-pressed') === 'true');
    const next = pills[at + step];
    if (at >= 0 && next) next.click();
  }
  function open(row) {
    const doc = docOf(row);
    if (!doc) {
      const url = hrefOf(row);
      if (url) window.open(url, '_blank', 'noopener');
      return;
    }
    if (settings.rememberOpened && listSearch) api.recordOpened(doc.url, doc.title || '', listSearch);
    const n = note(doc);
    if (n && n.obsidian) location.href = n.obsidian;
    else window.open(n && n.niwa ? n.niwa : hrefOf(row), '_blank', 'noopener');
  }
  const KEYS = [
    ['j / k', 'Next / previous result'], ['h / l', 'Previous / next pill'], ['Enter, o', 'Open the result'],
    ['p', 'Preview it'], ['gg / G', 'First / last result'], ['/', 'Search'], ['Esc', 'Leave the field, close the preview'],
    ['y', 'Copy the link'], ['e', 'Edit the label'], ['dd', 'Delete (with Undo)'], ['?', 'These keys'],
  ];
  function toggleHelp() {
    if (help) {
      help.remove();
      help = null;
      return;
    }
    help = h(
      'div',
      { class: 'kbd-help', role: 'dialog', 'aria-modal': 'false', 'aria-label': 'Keyboard shortcuts' },
      h('h2', {}, 'Keyboard'),
      h('dl', {}, KEYS.flatMap(([k, what]) => [h('dt', {}, h('kbd', {}, k)), h('dd', {}, what)])),
    );
    document.body.append(help);
  }
  document.addEventListener('keydown', (event) => {
    if (event.defaultPrevented || $('dialog').open) return;
    const typing = inField(event.target);
    const r = S.vimKey(state, {
      key: event.key, shiftKey: event.shiftKey, metaKey: event.metaKey, ctrlKey: event.ctrlKey,
      altKey: event.altKey, inField: typing, now: Date.now(),
    });
    state = r.state;
    if (!r.action) return;
    // Enter on a focused link, button or row is that element's own.
    if (event.key === 'Enter' && event.target.closest && event.target.closest('a[href], button, .row')) return;
    const row = current && current.isConnected ? current : null;
    const doc = docOf(row);
    switch (r.action) {
      case 'next': move(1); break;
      case 'prev': move(-1); break;
      case 'tabPrev': pill(-1); break;
      case 'tabNext': pill(1); break;
      case 'top': { const l = rows(); if (l.length) mark(l[0]); break; }
      case 'bottom': { const l = rows(); if (l.length) mark(l[l.length - 1]); break; }
      case 'open': if (!row) return; open(row); break;
      case 'preview': if (!row) return; if (doc) openDoc(doc, row); else open(row); break;
      case 'copy': if (!row || !hrefOf(row)) return; copy(hrefOf(row)); break;
      case 'label':
        if (!doc) return;
        if (note(doc) || doc.label === 'vault') toast('Notes keep their label');
        else if (S.isLocalFile(doc.url)) toast('Files keep their label');
        else if (S.isCodeDoc(doc)) toast('Code is kept as its forge has it');
        else labelPicker(doc);
        break;
      case 'delete': if (!doc || S.isLocalFile(doc.url) || S.isCodeDoc(doc)) return; mark(null); deleteWithUndo(doc); break;
      case 'focusSearch':
        if ($('search-top').hidden) return;
        searchInput.focus();
        searchInput.select();
        break;
      case 'help': toggleHelp(); break;
      case 'escape':
        if (help) toggleHelp();
        else if (typing) event.target.blur();
        else if (document.body.classList.contains('phone-preview')) history.back();
        else if (wide() && selected) {
          selected = null;
          document.querySelectorAll('.row[aria-selected="true"]').forEach((x) => x.setAttribute('aria-selected', 'false'));
          $('preview').replaceChildren(status('No Page Selected', 'Select a page to preview it.'));
        } else mark(null);
        break;
      default: return;
    }
    event.preventDefault();
  });
  return { mark };
})();

$('back').replaceChildren(icon('back'));
$('back').addEventListener('click', () => history.back());

applyLook();
/**
 * The bars over the list (title, search field, pills, Sort · Group · Filter)
 * are frosted and the list scrolls under them (app.css): its top padding
 * follows their height, here, as they change or hide.
 */
function watchBars() {
  const column = $('list-column');
  const bars = [...column.children].filter((el) => el.id !== 'list');
  const update = () => {
    const top = column.getBoundingClientRect().top;
    const bottom = Math.max(0, ...bars.filter((el) => el.offsetParent).map((el) => el.getBoundingClientRect().bottom - top));
    column.style.setProperty('--bars', `${bottom}px`);
  };
  if (window.ResizeObserver) {
    const observer = new ResizeObserver(update);
    for (const el of bars) observer.observe(el);
  }
  update();
}

// The share target (manifest.webmanifest's share_target): /?url=&title=&text=
// opens Add Page filled in, from a cold start too (sw.js serves / for any
// query). The query goes at once, so a reload or Back never shares again.
const shared = api.sharedPage(new URLSearchParams(location.search));
if (shared) history.replaceState(null, '', '/' + location.hash);

watchBars();
render();
if (shared) addPage(shared);
// Kura's vaults also say which are shared (S.useVaults): read again when
// the app comes back after a while, so a vault made private again counts.
// Until they answer, every vault but the default is private.
let vaultsAt = 0;
const loadVaults = () => {
  vaultsAt = Date.now();
  // api.kuraVaults passes them to S.useVaults.
  return api.kuraVaults().then((v) => {
    kuraVaults = v;
  });
};
document.addEventListener('visibilitychange', () => {
  if (!document.hidden && Date.now() - vaultsAt > 10 * 60_000) void loadVaults();
  // Back from signing in on Kura's page: Settings says so.
  if (!document.hidden && route().view === 'settings') render();
});
Promise.all([loadRules(), api.cards().then((c) => (konbiniCards = c)), loadVaults(), loadKuraAccount(), loadLocalFiles()]).then(render);

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js').then(watchForUpdates).catch(() => {});
}

/**
 * "New Version · Reload" when a new build's worker is waiting (the toast
 * every Machiya room has): sw.js no longer takes over
 * on its own, so a rebuild can't swap files under an open page. Reload
 * tells it to (SKIP_WAITING) and reloads once it has. The app checks for
 * a new build when it comes back to the foreground, at most once a
 * minute, since iOS rarely closes an installed app.
 */
function watchForUpdates(reg) {
  let asked = false;
  const toast = (worker) => {
    if (document.querySelector('.update-toast')) return;
    const reload = h('button', { type: 'button' }, 'Reload');
    reload.addEventListener('click', () => {
      asked = true;
      // The worker waiting now, not the one first seen: another identical
      // update may have superseded it.
      navigator.serviceWorker.getRegistration()
        .then((r) => (r && r.waiting) || worker)
        .catch(() => worker)
        .then((w) => w.postMessage({ type: 'SKIP_WAITING' }));
      // A worker too old to understand the message: reload anyway.
      setTimeout(() => location.reload(), 3000);
    });
    document.body.append(h('div', { class: 'update-toast', role: 'status' }, h('span', {}, 'New Version'), reload));
  };
  navigator.serviceWorker.addEventListener('controllerchange', () => asked && location.reload());
  if (reg.waiting && navigator.serviceWorker.controller) toast(reg.waiting);
  reg.addEventListener('updatefound', () => {
    const w = reg.installing;
    if (w) w.addEventListener('statechange', () => w.state === 'installed' && navigator.serviceWorker.controller && toast(w));
  });
  let last = Date.now();
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && Date.now() - last > 60000) {
      last = Date.now();
      reg.update().catch(() => {});
    }
  });
}
