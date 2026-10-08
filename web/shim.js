// Shiori's results page as a plain web page (no Safari extension): the few
// extension APIs the page uses, over localStorage. Settings are this
// browser's own (nothing is shared between devices).
//
// The page is served from one host with everything it talks to under it
// (see web/README.md): Hister's API at the root, SearXNG under /searx/,
// Konbini's card list under /konbini/, Kura under /kura/. So every fetch is
// same-origin, and the browser's cross-site rules never apply.
//
// Loaded before search-core.js and search.js; it only defines `chrome`.
(function () {
  const ROOT = location.origin + '/';
  const KEY = 'shioriWeb';

  // What the page's gear may set (SharedSettings.apply's keys, less the
  // addresses this page sets for itself).
  const SETTABLE = [
    'combinedSearch', 'showInfobox', 'showRelated', 'showThumbnails', 'histerInGeneral', 'histerTab',
    'vaultInGeneral', 'vaultTab', 'webResults', 'searchHistory', 'previewPane', 'previewImages',
    'rememberOpened', 'showOpened', 'resultStyle', 'pills', 'smallWebTab', 'smallWebOpen', 'searchFilters', 'semanticSearch', 'aiAnswer', 'histerCount', 'vaultCount', 'niwaURL',
    'labelSuggestions', 'foldRepeats',
    'konbiniURL', 'newsBlurURL', 'theme', 'palette', 'textSize', 'obsidianVault', 'notesSource',
  ];
  // The notes' homes, from the build (the server passes them in); a
  // browser's own choice wins.
  const NOTE_HOMES = { niwaURL: '__SHIORI_KURA_URL__', konbiniURL: '__SHIORI_KONBINI_URL__' };
  const RECENT_LIMIT = 5;
  // The companion AI service (/shiori/ai/*), only when the build says it's
  // there (SHIORI_AI=1): without it the page never asks, so a host without
  // one logs no 404s.
  const AI_BUILD = '__SHIORI_AI__';

  function load() {
    try {
      const all = JSON.parse(localStorage.getItem(KEY) || '{}') || {};
      // Result Style back to Tint, once, whatever was saved before (the
      // user's call, 0.5.0); a style chosen after that is kept.
      if (!localStorage.getItem('shioriResultStyleReset')) {
        localStorage.setItem('shioriResultStyleReset', '1');
        if (all.shioriSettings && all.shioriSettings.resultStyle) {
          all.shioriSettings.resultStyle = 'tint';
          localStorage.setItem(KEY, JSON.stringify(all));
        }
      }
      return all;
    } catch (_) {
      return {};
    }
  }
  function save(all) {
    try {
      localStorage.setItem(KEY, JSON.stringify(all));
    } catch (_) {
      // Private browsing or full: the page still works, it just forgets.
    }
  }

  /** The page's settings, with the addresses fixed to this host. */
  function withAddresses(settings) {
    const homes = {};
    for (const [key, value] of Object.entries(NOTE_HOMES)) if (!value.startsWith('__')) homes[key] = value;
    const merged = { ...homes, ...(settings || {}) };
    // Kura is set up when this host has a Kura home (the build's, or this
    // browser's): /kura/ is always routed, so its address alone can't say.
    // Notes From follows it until the person picks (S.notesSource).
    return { ...merged, searxngURL: ROOT + 'searx/', konbiniAPIURL: ROOT + 'konbini/', aiURL: AI_BUILD === '1' ? ROOT + 'shiori/ai/' : '', kuraAPIURL: ROOT + 'kura/', kuraConfigured: !!merged.niwaURL, smallwebAPIURL: ROOT + 'smallweb/' };
  }

  const storage = {
    get(keys) {
      const all = load();
      all.histerURL = ROOT;
      all.shioriSettings = withAddresses(all.shioriSettings);
      // The house's shared appearance, theme and text size: a choice
      // made in any Machiya room on this device counts here too.
      const S = window.ShioriSearch;
      if (S) {
        const house = S.houseSettings(document.cookie, { mine: all.shioriSettings.textSize });
        if (house.theme) all.shioriSettings.theme = house.theme;
        if (house.palette) all.shioriSettings.palette = house.palette;
        if (house.textSize) all.shioriSettings.textSize = house.textSize;
      }
      const out = {};
      for (const key of [].concat(keys)) if (key in all) out[key] = all[key];
      return Promise.resolve(out);
    },
    set(values) {
      save({ ...load(), ...values });
      return Promise.resolve();
    },
  };

  function settingsNow() {
    return withAddresses(load().shioriSettings);
  }
  function setSettings(settings) {
    const all = load();
    all.shioriSettings = settings;
    save(all);
  }

  /** A change made in the page's gear, kept in this browser. */
  function change(values) {
    const next = settingsNow();
    if (values.clearRecentSearches) next.recentSearches = [];
    for (const key of SETTABLE) if (key in values) next[key] = values[key];
    if (values.searchHistory === false) next.recentSearches = [];
    setSettings(next);
    // Appearance, theme and text size are the house's too (the other rooms read them).
    const S = window.ShioriSearch;
    for (const key of ['theme', 'palette', 'textSize']) {
      const shared = S && key in values ? S.houseCookie(key, values[key], location.hostname) : null;
      if (shared) document.cookie = shared;
    }
  }

  function record(q) {
    const settings = settingsNow();
    const query = String(q || '').trim();
    if (settings.searchHistory === false || !query || query.length > 500) return;
    const list = (settings.recentSearches || []).filter((r) => r.toLowerCase() !== query.toLowerCase());
    settings.recentSearches = [query, ...list].slice(0, RECENT_LIMIT);
    setSettings(settings);
  }

  function sendMessage(message, reply) {
    const done = () => {
      if (typeof reply === 'function') reply();
    };
    const kind = message && message.shiori;
    if (kind === 'set-settings') {
      change(message.values || {});
      done();
    } else if (kind === 'record-search') {
      record(message.q);
      done();
    } else done(); // refresh-settings, left-for-result: nothing to do here.
  }

  window.chrome = {
    storage: { local: storage },
    runtime: { sendMessage, lastError: undefined },
    tabs: { getCurrent: (callback) => callback(undefined) },
  };
})();
