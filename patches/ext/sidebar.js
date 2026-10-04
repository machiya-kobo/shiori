// Shiori in Firefox's sidebar: a field that searches your pages as you
// type, and, while it's empty, what you've saved from the site in the tab
// beside it, newest first (Hister's `domain:` field). It talks only to the
// configured Hister server, with queries as every Shiori search sends them
// (search-core.js: the last word a prefix, never the notes), and lists pages
// as the address-bar keyword does (ext/pages.js). A plain click opens the
// page in the current tab (and, for a search, tells Hister it was opened,
// unless Remember What You Open is off); a modified click, a new tab.
(async () => {
  const $ = (id) => document.getElementById(id);
  const S = globalThis.ShioriSearch;
  const P = globalThis.ShioriPages;
  const LIMIT = 20;
  const SITE_LIMIT = 10;
  const WAIT_MS = 200;

  let base = '';
  let settings = {};
  async function load() {
    const got = await chrome.storage.local.get(['histerURL', 'shioriSettings']);
    base = String(got.histerURL || '').trim();
    if (base && !base.endsWith('/')) base += '/';
    settings = got.shioriSettings || {};
    if (settings.theme === 'night' || settings.theme === 'day') document.documentElement.dataset.theme = settings.theme;
    else delete document.documentElement.dataset.theme;
    // The rooms' themes (palettes.css); Tokyo Night is search.css's own.
    if (Object.hasOwn(S.PALETTES, settings.palette) && settings.palette !== 'tokyo-night') document.documentElement.dataset.palette = settings.palette;
    else delete document.documentElement.dataset.palette;
  }

  const status = (text) => ($('status').textContent = text || '');

  async function search(text, limit, extra = {}, signal) {
    if (!base) throw new Error('no server');
    const query = JSON.stringify({ text: S.histerText(text), limit, highlight: 'HTML', ...extra });
    const r = await fetch(`${base}search?format=json&query=${encodeURIComponent(query)}`, { headers: { Accept: 'application/json' }, signal });
    if (!r.ok) throw new Error(String(r.status));
    return r.json();
  }

  /** Hister's snippet HTML as text and <mark>s only (as the results page
   *  builds it, less any script or style text). */
  function snippet(html) {
    const p = document.createElement('p');
    p.className = 'snippet';
    const doc = new DOMParser().parseFromString(`<body>${html || ''}</body>`, 'text/html');
    (function walk(node) {
      for (const child of node.childNodes) {
        if (child.nodeType === Node.TEXT_NODE) p.append(child.textContent);
        else if (/^(SCRIPT|STYLE|TEMPLATE)$/.test(child.nodeName)) continue; // code, not words
        else if (child.nodeName === 'MARK') {
          const mark = document.createElement('mark');
          mark.textContent = child.textContent;
          p.append(mark);
        } else walk(child);
      }
    })(doc.body);
    return p.textContent.trim() ? p : null;
  }

  async function openHere(url) {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    return tab ? chrome.tabs.update(tab.id, { url }) : chrome.tabs.create({ url });
  }

  // Never another vault's note, shared or not: Hister's results hold none
  // to open here, and whether a vault is still shared would need Kura
  // asked first (fail closed).
  function recordOpened(url, title, query) {
    if (!base || !query || settings.rememberOpened === false || S.noteVault(url) !== null) return;
    fetch(`${base}api/history`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url, title, query: S.histerText(query) }),
      credentials: 'omit',
    }).catch(() => {});
  }

  function item(page, query) {
    const li = document.createElement('li');
    const a = document.createElement('a');
    a.className = 'title';
    a.href = page.url;
    a.textContent = page.title;
    a.addEventListener('click', (event) => {
      recordOpened(page.url, page.title, query);
      // Modified and middle clicks keep the browser's own (a new tab).
      if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      void openHere(page.url);
    });
    const host = document.createElement('span');
    host.className = 'host';
    host.textContent = page.host;
    li.append(a, host);
    const text = snippet(page.snippet);
    if (text) li.append(text);
    return li;
  }

  // --- searching ---

  let current = null; // { timer, controller }
  async function find(text) {
    const q = text.trim().slice(0, 500);
    $('found').hidden = !q;
    $('site').hidden = !!q;
    if (!q) {
      status('');
      return;
    }
    const controller = new AbortController();
    const mine = { controller };
    current = mine;
    try {
      const pages = P.webPages(await search(q, LIMIT, {}, controller.signal), settings, LIMIT);
      if (current !== mine) return;
      $('found-list').replaceChildren(...pages.map((p) => item(p, q)));
      $('found-all').href = `search.html?q=${encodeURIComponent(q)}`;
      $('found-more').hidden = false;
      status(pages.length ? '' : `Nothing of yours for “${q}” yet.`);
    } catch (e) {
      if (current !== mine || e.name === 'AbortError') return;
      $('found-list').replaceChildren();
      status(base ? "Can't reach Hister." : "Set your Hister server in Shiori's settings.");
    }
  }
  $('q').addEventListener('input', () => {
    if (current) {
      clearTimeout(current.timer);
      if (current.controller) current.controller.abort();
    }
    const value = $('q').value;
    current = { timer: setTimeout(() => void find(value), WAIT_MS) };
  });
  $('find').addEventListener('submit', (event) => {
    event.preventDefault();
    const q = $('q').value.trim();
    if (q) void chrome.tabs.create({ url: chrome.runtime.getURL(`search.html?q=${encodeURIComponent(q)}`) });
  });

  // --- from this site ---

  let shownHost = null;
  async function showSite(force = false) {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true }).catch(() => []);
    let host = '';
    try {
      const u = new URL(tab && tab.url);
      if (u.protocol === 'http:' || u.protocol === 'https:') host = u.hostname;
    } catch (_) {}
    if (host === shownHost && !force) return;
    shownHost = host;
    const list = $('site-list');
    const head = $('site-head');
    if (!host) {
      head.textContent = 'From This Site';
      list.replaceChildren();
      if (!$('q').value.trim()) status('Open a web page to see what you’ve saved from its site.');
      return;
    }
    head.textContent = `From ${host}`;
    try {
      const reply = await search(`domain:${host}`, SITE_LIMIT, { sort: 'date' });
      if (host !== shownHost) return;
      const pages = P.webPages(reply, settings, SITE_LIMIT);
      list.replaceChildren(...pages.map((p) => item(p, '')));
      if (!$('q').value.trim()) status(pages.length ? '' : `Nothing saved from ${host} yet.`);
    } catch (_) {
      if (host !== shownHost) return;
      list.replaceChildren();
      if (!$('q').value.trim()) status(base ? "Can't reach Hister." : "Set your Hister server in Shiori's settings.");
    }
  }
  chrome.tabs.onActivated.addListener(() => void showSite());
  chrome.tabs.onUpdated.addListener((_id, change, tab) => {
    if (tab && tab.active && (change.url || change.status === 'complete')) void showSite();
  });
  chrome.storage.onChanged.addListener(async (changes, area) => {
    if (area !== 'local' || !('histerURL' in changes || 'shioriSettings' in changes)) return;
    await load();
    void showSite(true);
  });

  await load();
  await showSite(true);
})();
