// The host behind the extension where there is no app (Firefox): a stand-in
// for it in storage.local, prepended to background.js before ext/core.js in
// place of ext/host-native.js (same interface; see there).
//
// It keeps what the app's App Group would, under its own key: only the
// values someone set, so the extension's defaults hold for the rest. The
// rules are the app's, twins of Shared/Settings/SharedSettings.swift
// (apply, applyFromPage, recordSearch, extensionPayload); a test holds the
// key lists to the Swift ones. Change both.
//
// Settings are per device: storage.local, never storage.sync.
//
// The Machiya sign-in ({token, principal}) has a key of its own, never in
// the settings (which a settings file can export) and never synced or
// logged.
const shioriHost = (() => {
  const STORE_KEY = 'shioriLocalSettings';
  const MACHIYA_KEY = 'machiyaSignIn';

  const RECENT_LIMIT = 5;
  const TEXT_SIZES = ['system', 'xSmall', 'small', 'medium', 'large', 'xLarge', 'xxLarge', 'xxxLarge'];
  const PAGE_COUNTS = [3, 5, 10, 20];
  const FLAG_KEYS = [
    'combinedSearch', 'showInfobox', 'showRelated', 'showThumbnails', 'histerInGeneral',
    'histerTab', 'vaultInGeneral', 'vaultTab', 'webResults', 'searchHistory', 'previewPane',
    'previewImages', 'rememberOpened', 'searchFilters', 'semanticSearch', 'foldRepeats',
    'labelSuggestions', 'aiAnswer', 'showOpened', 'smallWebTab',
  ];
  const COUNT_KEYS = ['histerCount', 'vaultCount'];
  const URL_KEYS = ['searxngURL', 'niwaURL', 'konbiniURL', 'newsBlurURL', 'smallwebURL'];
  const THEMES = ['system', 'day', 'night'];
  const RESULT_STYLES = ['tint', 'solid', 'bar', 'none'];
  const SMALL_WEB_OPENS = ['gateway', 'direct'];
  // What extensionPayload passes on as it is stored.
  const STRING_KEYS = [
    'searxngURL', 'theme', 'obsidianVault', 'niwaURL', 'konbiniURL', 'textSize', 'serverURL',
    'resultStyle', 'smallwebURL', 'smallWebOpen',
  ];

  const storage = () => chrome.storage.local;
  async function load() {
    const stored = (await storage().get([STORE_KEY]))[STORE_KEY];
    return stored && typeof stored === 'object' ? stored : {};
  }
  const save = (store) => storage().set({ [STORE_KEY]: store });
  const historyOn = (store) => store.searchHistory !== false;

  /** SharedSettings.apply: known keys, the right type, an allowed value. */
  function apply(values, store) {
    const isInt = (v) => typeof v === 'number' && Number.isInteger(v);
    for (const key of FLAG_KEYS) if (typeof values[key] === 'boolean') store[key] = values[key];
    for (const key of COUNT_KEYS) if (isInt(values[key]) && PAGE_COUNTS.includes(values[key])) store[key] = values[key];
    for (const key of URL_KEYS) {
      const v = values[key];
      if (typeof v === 'string' && (v === '' || v.startsWith('https://') || v.startsWith('http://'))) store[key] = v;
    }
    const vault = values.obsidianVault;
    if (typeof vault === 'string' && vault !== '' && [...vault].length <= 200) store.obsidianVault = vault;
    const oneOf = (key, allowed) => {
      if (typeof values[key] === 'string' && allowed.includes(values[key])) store[key] = values[key];
    };
    oneOf('textSize', TEXT_SIZES);
    oneOf('theme', THEMES);
    oneOf('resultStyle', RESULT_STYLES);
    oneOf('smallWebOpen', SMALL_WEB_OPENS);
    if (values.searchHistory === false) delete store.recentSearches;
    return store;
  }

  return {
    /** SharedSettings.extensionPayload: what someone set, and the recent searches. */
    async settings() {
      const store = await load();
      const out = {};
      for (const key of [...FLAG_KEYS.filter((k) => k !== 'semanticSearch'), ...COUNT_KEYS, ...STRING_KEYS]) {
        if (key in store) out[key] = store[key];
      }
      out.recentSearches = historyOn(store) ? (store.recentSearches || []).slice(0, RECENT_LIMIT) : [];
      return out;
    },

    /** SharedSettings.recordSearch: to the top, once whatever its case. */
    async recordSearch(q) {
      const query = typeof q === 'string' ? q.trim() : '';
      const store = await load();
      if (!historyOn(store) || !query || [...query].length > 500) return;
      const list = (store.recentSearches || []).filter((r) => r.toLowerCase() !== query.toLowerCase());
      store.recentSearches = [query, ...list].slice(0, RECENT_LIMIT);
      await save(store);
    },

    /** SharedSettings.applyFromPage. */
    async setSettings(values) {
      if (!values || typeof values !== 'object') return;
      const store = apply(values, await load());
      if (values.clearRecentSearches === true) delete store.recentSearches;
      await save(store);
    },

    /** What setSettings would keep of these values, for a file's preview. */
    judge: (values) => apply(values && typeof values === 'object' ? values : {}, {}),

    // Nothing outside the extension to tell; the toolbar badge shows the
    // queue (docs/firefox-plan.md, feature B).
    canReportQueue: () => false,
    reportQueue: async () => {},

    // No app to set the server: the settings page does (ext/settings.js).
    ownsServer: true,

    /** The Machiya sign-in, {token, principal}, or {} when signed out. */
    async machiya() {
      const stored = (await storage().get([MACHIYA_KEY]))[MACHIYA_KEY];
      return stored && typeof stored === 'object' && typeof stored.token === 'string' ? { token: stored.token, principal: String(stored.principal || '') } : {};
    },
    /** Keeps a sign-in (the core checked the token's shape). */
    setMachiya: (token, principal) => storage().set({ [MACHIYA_KEY]: { token, principal: String(principal || '') } }),
    /** Signs out: the token is deleted from this browser. */
    clearMachiya: () => storage().remove(MACHIYA_KEY),
    // No app: the settings page signs in and out.
    ownsMachiya: true,
  };
})();

// No app to welcome you either: the settings page opens on first install,
// where the server is set and site access granted.
(function openSettingsOnInstall() {
  if (typeof chrome === 'undefined' || !chrome.runtime || !chrome.runtime.onInstalled) return;
  chrome.runtime.onInstalled.addListener((details) => {
    if (details && details.reason === 'install') void chrome.runtime.openOptionsPage();
  });
})();
