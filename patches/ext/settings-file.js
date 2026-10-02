// Settings as a file, to set up another device without syncing anything
// (docs/firefox-plan.md, feature F): the settings page exports this
// device's Hister server and settings, and imports such a file after
// showing what it would change. Applying it goes through the same doors
// as the page's own fields (`set-server`, and `set-settings`'s whitelist),
// so a file can't set anything the page couldn't. Never in it: recent
// searches (history, not settings), queued pages, notes. Pure: the page
// (ext/settings.js) and scripts/settings-file.test.mjs use it.
(function (root) {
  const KIND = 'shiori-settings';
  const VERSION = 1;
  const NOT_EXPORTED = new Set(['recentSearches']);

  /** The file's content: { kind, version, exported, server, settings }. */
  function exportSettings({ server, settings, now = new Date() }) {
    const out = {};
    for (const [key, value] of Object.entries(settings || {})) if (!NOT_EXPORTED.has(key)) out[key] = value;
    return { kind: KIND, version: VERSION, exported: now.toISOString(), server: server || '', settings: out };
  }

  /** The file's name for a date: shiori-settings-2026-10-02.json. */
  function fileName(now = new Date()) {
    return `shiori-settings-${now.toISOString().slice(0, 10)}.json`;
  }

  const httpAddress = (value) => {
    try {
      const u = new URL(String(value || '').trim());
      return u.protocol === 'http:' || u.protocol === 'https:' ? (u.href.endsWith('/') ? u.href : u.href + '/') : null;
    } catch (_) {
      return null;
    }
  };

  /**
   * A file's text, read: { server, settings } to apply, or { error } in
   * words. The server only when it's an http(s) address; settings as
   * written (the whitelist judges them when applied), less what's never
   * imported.
   */
  function readImport(text) {
    let doc;
    try {
      doc = JSON.parse(String(text || ''));
    } catch (_) {
      return { error: "That file isn't Shiori's settings (it isn't JSON)." };
    }
    if (!doc || typeof doc !== 'object' || doc.kind !== KIND) return { error: "That file isn't Shiori's settings." };
    if (doc.version !== VERSION) return { error: `That file is from another version of Shiori (format ${doc.version}).` };
    const settings = {};
    if (doc.settings && typeof doc.settings === 'object' && !Array.isArray(doc.settings)) {
      for (const [key, value] of Object.entries(doc.settings)) if (!NOT_EXPORTED.has(key)) settings[key] = value;
    }
    return { server: httpAddress(doc.server), settings };
  }

  /** What applying it would change, in words, for the page to show first. */
  function describeImport({ server, settings }, currentServer = '') {
    const count = Object.keys(settings || {}).length;
    const others = `${count} ${count === 1 ? 'setting' : 'settings'}`;
    if (server && server !== currentServer) {
      return count ? `This file sets the Hister server to ${server}, plus ${others}.` : `This file sets the Hister server to ${server}.`;
    }
    return count ? `This file sets ${others}.` : 'This file changes nothing here.';
  }

  root.ShioriSettingsFile = { exportSettings, fileName, readImport, describeImport };
})(typeof globalThis !== 'undefined' ? globalThis : this);
