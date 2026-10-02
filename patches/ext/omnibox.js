// The address bar's keyword (Firefox): "sh lantern" suggests your pages from
// Hister as you type, the pages you opened for that search first; Enter on
// a suggestion opens it, Enter on the text opens Shiori. Prepended to
// background.js after search-core.js (ShioriSearch), ext/pages.js and
// ext/core.js (resultsBase), so it talks only to the configured Hister server, with the
// query as every Shiori search sends it (the last word a prefix, never the
// notes).
(function installOmnibox() {
  if (typeof chrome === 'undefined' || !chrome.omnibox || !chrome.omnibox.onInputChanged) return;
  const S = globalThis.ShioriSearch;
  const LIMIT = 6;
  const WAIT_MS = 150;

  // What the last suggestions were, so Enter on one can say what was opened.
  let offered = { text: '', titles: new Map() };
  let current = null; // { controller, timer } of the search under way

  async function stored() {
    const got = await chrome.storage.local.get(['histerURL', 'shioriSettings']);
    let base = typeof got.histerURL === 'string' ? got.histerURL.trim() : '';
    if (base && !base.endsWith('/')) base += '/';
    return { base, settings: got.shioriSettings || {} };
  }

  const isWeb = (url) => /^https?:\/\//i.test(String(url || ''));

  /** The suggestions for a reply (ext/pages.js: opened before first, once
   *  each, web pages only, never a note). */
  function suggestions(reply, settings) {
    return globalThis.ShioriPages.webPages(reply, settings, LIMIT).map((p) => ({
      content: p.url,
      description: p.host ? `${p.title} — ${p.host}` : p.title,
      title: p.title,
    }));
  }

  chrome.omnibox.setDefaultSuggestion({ description: 'Search your pages for "%s" in Shiori' });

  chrome.omnibox.onInputChanged.addListener((text, suggest) => {
    if (current) {
      clearTimeout(current.timer);
      current.controller.abort();
    }
    const query = String(text || '').trim().slice(0, 500);
    if (!query) {
      current = null;
      suggest([]);
      return;
    }
    const controller = new AbortController();
    const mine = { controller, timer: null };
    current = mine;
    // A short wait, so a fast typist sends one search, not one a key.
    mine.timer = setTimeout(async () => {
      let list = [];
      try {
        const { base, settings } = await stored();
        if (!base) throw new Error('no server');
        const body = JSON.stringify({ text: S.histerText(query), limit: LIMIT });
        const r = await fetch(`${base}search?format=json&query=${encodeURIComponent(body)}`, {
          headers: { Accept: 'application/json' },
          signal: controller.signal,
        });
        if (r.ok) list = suggestions(await r.json(), settings);
      } catch (_) {}
      if (current !== mine) return; // a newer search answers instead
      offered = { text: query, titles: new Map(list.map((s) => [s.content, s.title])) };
      suggest(list.map(({ content, description }) => ({ content, description })));
    }, WAIT_MS);
  });

  /** Tell Hister a suggestion was opened for this search (as the results
   *  page does), unless Remember What You Open is off. Never another
   *  vault's note, shared or not: the keyword drops notes, and whether a
   *  vault is still shared would need Kura asked (fail closed). */
  async function recordOpened(url, title, query) {
    const { base, settings } = await stored();
    if (!base || settings.rememberOpened === false || S.noteVault(url) !== null) return;
    await fetch(`${base}api/history`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url, title, query: S.histerText(query) }),
      credentials: 'omit',
    }).catch(() => {});
  }

  async function open(url, disposition) {
    if (disposition === 'newForegroundTab') return chrome.tabs.create({ url });
    if (disposition === 'newBackgroundTab') return chrome.tabs.create({ url, active: false });
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    return tab ? chrome.tabs.update(tab.id, { url }) : chrome.tabs.create({ url });
  }

  chrome.omnibox.onInputEntered.addListener(async (text, disposition) => {
    const entered = String(text || '').trim();
    if (!entered) return;
    if (offered.titles.has(entered)) {
      void recordOpened(entered, offered.titles.get(entered), offered.text);
      await open(entered, disposition);
      return;
    }
    if (isWeb(entered) && !/\s/.test(entered)) {
      await open(entered, disposition);
      return;
    }
    const base = await resultsBase();
    await open(`${base}?q=${encodeURIComponent(entered.slice(0, 500))}`, disposition);
  });
})();
