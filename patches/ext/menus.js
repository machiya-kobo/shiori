// The right-click menu (Safari's `contextMenus` on the Mac; iOS has none):
// search Shiori for the selection; save this page, or never save it or its
// site (upstream's own commands, the same ones its shortcuts run: the
// server's rules stay the truth); save a link to Hister. Prepended to
// background.js after search-core.js, ext/core.js (resultsBase) and
// ext/badge.js (ShioriBadge), and before upstream, whose command listeners
// it keeps so the menu can run them.
//
// A link is saved by Save This Note's Links' rules (Packages/HisterKit/CLAUDE.md): never one
// Hister holds (looked up before, and again after redirects: api/add would
// replace its metadata); never a file; downloaded here without cookies,
// http:// tried as https:// first; skip rules hold (no ignore_skip_rules);
// gemini:// and gopher:// through the small-web gateway. It goes through
// the core's fetch, so it carries Shiori's metadata and waits in the queue
// while Hister is out of reach. The answer shows on the tab's badge and
// tooltip for a few seconds.
(function installMenus() {
  if (typeof chrome === 'undefined') return;
  const S = globalThis.ShioriSearch;

  // Upstream's command listeners, kept as it adds them (it looks up
  // addListener at call time), so a menu item can run the same command.
  const commandListeners = [];
  if (chrome.commands && chrome.commands.onCommand && chrome.commands.onCommand.addListener) {
    const onCommand = chrome.commands.onCommand;
    const add = onCommand.addListener.bind(onCommand);
    onCommand.addListener = function keepingTheListener(listener) {
      commandListeners.push(listener);
      return add(listener);
    };
  }

  const MAX_HTML = 2 * 1024 * 1024; // characters, as the content shim caps a page
  const SHOW_MS = 6000;
  const withSlash = (u) => (u && !u.endsWith('/') ? u + '/' : u || '');

  // Hister's token where this device has one (sent as X-Access-Token),
  // read with the server each time (the core keeps it in memory).
  let token = '';
  async function stored() {
    const got = await chrome.storage.local.get(['histerURL', 'shioriSettings']);
    token = typeof shioriHisterToken !== 'undefined' ? await shioriHisterToken.get() : '';
    return { base: withSlash(String(got.histerURL || '').trim()), settings: got.shioriSettings || {} };
  }

  // A gemini:// or gopher:// link under the forms Hister may hold it.
  const forms = (url) => (S.isSmallWebLink(url) ? [...new Set([url, S.smallWebKey(url)])] : [url]);

  /** Whether Hister holds any of these URLs (with or without a trailing slash). */
  async function holds(base, urls) {
    const q = S.urlLookupQuery(urls);
    if (!q) return false;
    const r = await fetch(`${base}search?format=json&query=${encodeURIComponent(JSON.stringify({ text: q, limit: 20 }))}`,
      S.histerFetchOptions(token, { headers: { Accept: 'application/json' } }));
    if (!r.ok) throw new Error(`Hister answered ${r.status}`);
    const docs = (await r.json()).documents || [];
    const wanted = new Set(urls.flatMap((u) => [u, u.endsWith('/') ? u.slice(0, -1) : u + '/']));
    return docs.some((d) => wanted.has(d.url));
  }

  // Entities decoded in one pass, so "&amp;lt;" stays "&lt;" (one decode, as a browser would show it).
  const TITLE_ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', '#39': "'" };
  const titleIn = (html) => {
    const m = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(html);
    return m ? m[1].replace(/\s+/g, ' ').trim().replace(/&(amp|lt|gt|quot|#39);/g, (_, name) => TITLE_ENTITIES[name]) : '';
  };
  const capped = (html) => {
    if (html.length <= MAX_HTML) return html;
    const end = html.lastIndexOf('>', MAX_HTML - 1);
    return end > 0 ? html.slice(0, end + 1) : html.slice(0, MAX_HTML);
  };

  /** A web page's HTML, without cookies; http:// tried as https:// first. Null when it isn't a page. */
  async function download(url) {
    const tries = url.startsWith('http://') ? ['https://' + url.slice(7), url] : [url];
    for (const tryURL of tries) {
      let r;
      try {
        r = await fetch(tryURL, { credentials: 'omit', redirect: 'follow', headers: { Accept: 'text/html,application/xhtml+xml' } });
      } catch (_) {
        continue;
      }
      if (!r.ok) continue;
      if (!/^(text\/html|application\/xhtml\+xml)\b/i.test(r.headers.get('Content-Type') || '')) return null;
      return { url: r.url || tryURL, html: capped(await r.text()) };
    }
    return null;
  }

  /** A gemini:// or gopher:// link: the gateway fetches and saves it; a 429 is waited out. */
  async function saveThroughGateway(url, settings, base, wait) {
    const gateway = withSlash(settings.smallwebURL || '');
    if (!gateway) return { outcome: 'failed', reason: 'Needs the small-web gateway (Shiori settings, Neighbours)' };
    if (base && (await holds(base, forms(url)).catch(() => false))) return { outcome: 'held' };
    for (let attempt = 0; attempt < 4; attempt++) {
      let r;
      try {
        r = await fetch(`${gateway}api/save`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ url }),
        });
      } catch (_) {
        return { outcome: 'failed', reason: 'The small-web gateway is out of reach' };
      }
      if (r.status === 202 || r.status === 200) return { outcome: 'saved' };
      if (r.status === 400) return { outcome: 'failed', reason: 'The gateway saves only gemini:// and gopher:// pages' };
      if (r.status !== 429) return { outcome: 'failed', reason: `The gateway answered ${r.status}` };
      if (attempt < 3) await wait(5000 * (attempt + 1));
    }
    return { outcome: 'failed', reason: 'The gateway has too many saves waiting; try again in a minute' };
  }

  /**
   * Saves one link. → { outcome: 'saved'|'queued'|'held'|'skipped'|'failed', reason? }
   */
  async function saveLink(url, { wait = (ms) => new Promise((r) => setTimeout(r, ms)) } = {}) {
    url = String(url || '').trim();
    const { base, settings } = await stored();
    if (S.isSmallWebLink(url)) return saveThroughGateway(url, settings, base, wait);
    if (!/^https?:\/\//i.test(url)) return { outcome: 'failed', reason: 'Not a web page' };
    if (S.linkLooksLikeFile(url)) return { outcome: 'failed', reason: 'A file, not a web page' };
    if (!base) return { outcome: 'failed', reason: 'No Hister server set (Shiori settings)' };
    // Notes come only from Kura: none is saved from here, another vault's
    // (shared or not) known by its address wherever Kura is.
    const isNote = (u) => S.noteVault(u) !== null || S.isNoteURL(u, settings.niwaURL || '', settings.konbiniURL || '');
    const NOTE = { outcome: 'failed', reason: 'A note, which stays in Kura' };
    if (isNote(url)) return NOTE;
    // Hister out of reach: not known to hold it; the save is then queued.
    if (await holds(base, [url]).catch(() => false)) return { outcome: 'held' };
    const page = await download(url);
    if (!page) return { outcome: 'failed', reason: "Couldn't download it, or it isn't a web page" };
    if (page.url !== url && isNote(page.url)) return NOTE;
    if (page.url !== url && (await holds(base, [page.url]).catch(() => false))) return { outcome: 'held' };
    const body = { url: page.url, title: titleIn(page.html), html: page.html, metadata: { via: 'context-menu' } };
    let r;
    try {
      r = await fetch(`${base}api/add`, S.histerFetchOptions(token, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }));
    } catch (_) {
      return { outcome: 'failed', reason: 'Hister is out of reach, and its skip rules are unknown here yet' };
    }
    if (r.headers.get('X-Shiori-Queued') === '1' || r.status >= 500 || r.status === 429) return { outcome: 'queued' };
    if (r.ok) return { outcome: 'saved' };
    if (r.status === 406) return { outcome: 'skipped' };
    if (r.status === 413) return { outcome: 'failed', reason: 'Too large for Hister' };
    if (r.status === 422) return { outcome: 'failed', reason: 'Hister found sensitive content in it' };
    return { outcome: 'failed', reason: `Hister answered ${r.status}` };
  }

  // The answer, on the tab's badge and tooltip for a moment (null: back to
  // the toolbar's own, the queue's count).
  const LOOK = {
    saved: { text: '✓', colour: '#9ece6a', title: 'Saved to Hister' },
    queued: { text: '…', colour: '#e0af68', title: 'Waiting to send to Hister' },
    held: { text: '=', colour: '#7aa2f7', title: 'Hister already has this page' },
    skipped: { text: '–', colour: '#a9b1d6', title: "Hister's rules skip this page" },
    failed: { text: '!', colour: '#f7768e', title: "Couldn't save it" },
  };
  function tell(tabId, result) {
    if (tabId == null || !chrome.action) return;
    const look = LOOK[result.outcome] || LOOK.failed;
    const quiet = (p) => (p && p.catch ? p.catch(() => {}) : p);
    quiet(chrome.action.setBadgeText({ tabId, text: look.text }));
    quiet(chrome.action.setBadgeBackgroundColor({ tabId, color: look.colour }));
    if (chrome.action.setBadgeTextColor) quiet(chrome.action.setBadgeTextColor({ tabId, color: '#1a1b26' }));
    quiet(chrome.action.setTitle({ tabId, title: `Shiori · ${look.title}${result.reason ? `: ${result.reason}` : ''}` }));
    setTimeout(() => {
      if (globalThis.ShioriBadge) return void globalThis.ShioriBadge.clearTab(tabId);
      quiet(chrome.action.setBadgeText({ tabId, text: null }));
      quiet(chrome.action.setTitle({ tabId, title: null }));
    }, SHOW_MS);
  }

  function runCommand(command, tab) {
    for (const listener of commandListeners) {
      try {
        listener(command, tab);
      } catch (_) {}
    }
  }

  async function searchFor(text, tab) {
    const q = String(text || '').replace(/\s+/g, ' ').trim().slice(0, 500);
    if (!q) return;
    const url = `${await resultsBase()}?q=${encodeURIComponent(q)}`;
    await chrome.tabs.create({ url, ...(tab && tab.index != null ? { index: tab.index + 1, openerTabId: tab.id } : {}) });
  }

  const ITEMS = [
    { id: 'shiori-search', title: 'Search Shiori for “%s”', contexts: ['selection'] },
    { id: 'shiori-save-link', title: 'Save Link to Hister', contexts: ['link'] },
    { id: 'shiori-save-page', title: 'Save Page to Hister', contexts: ['page'] },
    { id: 'shiori-never-page', title: 'Never Save This Page', contexts: ['page'] },
    { id: 'shiori-never-site', title: 'Never Save This Site', contexts: ['page'] },
  ];

  async function onClicked(info, tab) {
    switch (info.menuItemId) {
      case 'shiori-search':
        return searchFor(info.selectionText, tab);
      case 'shiori-save-link':
        return tell(tab && tab.id, await saveLink(info.linkUrl).catch(() => ({ outcome: 'failed' })));
      case 'shiori-save-page':
        return runCommand('index-current-page', tab);
      case 'shiori-never-page':
        return runCommand('disable-indexing-current-page', tab);
      case 'shiori-never-site':
        return runCommand('disable-indexing-current-domain', tab);
    }
  }

  globalThis.ShioriMenus = { saveLink, ITEMS };

  const menus = chrome.menus || chrome.contextMenus;
  if (!menus || !menus.create) return; // iOS has none
  // Made afresh each time the background starts, so a changed list never
  // leaves an old item behind. removeAll answers by promise or by callback.
  new Promise((done) => {
    try {
      const p = menus.removeAll(() => done());
      if (p && typeof p.then === 'function') p.then(done, done);
    } catch (_) {
      done();
    }
  })
    .then(() => {
      for (const item of ITEMS) menus.create(item, () => void (chrome.runtime && chrome.runtime.lastError));
    });
  menus.onClicked.addListener((info, tab) => void onClicked(info, tab));
})();
