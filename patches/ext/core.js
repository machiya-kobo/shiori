// Shiori's part of background.js, the same on Safari and Firefox:
// prepended at build time after the browser's own shims and the host
// (ext/host-native.js on Safari, the app; ext/host-local.js on Firefox,
// storage.local), which it reaches only through `shioriHost`.
//
// 1. Offline capture queue. The Hister server is often unreachable (VPN
//    off, no signal), and upstream's only retry lives in the page's content
//    script, which dies with the tab. We wrap fetch for the Hister API: see
//    installCaptureQueue below.

// Only requests to the configured Hister server's api/add and api/rules are
// touched; everything else (favicons, PDFs, other API calls) passes through.
//
// - Every POST api/add gets metadata.client = "shiori" and
//   metadata.client_version = the manifest version.
//
// - POST api/add that fails at the network level is queued in
//   storage.local, stamped with the visit time (`added`, unix seconds), and
//   replayed later unchanged. An automatic capture then answers with a
//   synthetic 201 so upstream shows no error badge and the page does not
//   resubmit; a manual "index this page" still fails, with a message
//   saying it was queued.
// - 5xx and 429 from the server are queued the same way, with a retry
//   budget, but return the real response.
// - GET api/rules that succeeds is remembered (and fetched as soon as the
//   worker starts); while offline the remembered rules answer instead, so
//   skip-listed pages (banks, mail, ...) are recognised and never reach the
//   queue. With no remembered rules at all, nothing is queued.
// - Queued captures never store credentials (the token is re-read when
//   sending), and are dropped after 14 days.
// - The queue drains whenever the server answers anything below 500, and
//   once each time the service worker starts.
//
// Replies of 406 (skip rule), 413 (too large), 422 (sensitive content) and
// any other 4xx drop the queued capture: retrying cannot change them.
(function installCaptureQueue() {
  if (typeof chrome === 'undefined' || !chrome.storage || !chrome.storage.local) return;
  if (typeof globalThis.fetch !== 'function') return;

  const INDEX_KEY = 'shioriQueueIndex';
  const ITEM_PREFIX = 'shioriQueueItem:';
  const RULES_KEY = 'shioriCachedRules';
  const MAX_ITEMS = 100;
  const MAX_BYTES = 24 * 1024 * 1024; // UTF-16 code units, close enough
  const MAX_ATTEMPTS = 5;
  const MAX_AGE_MS = 14 * 24 * 60 * 60 * 1000;

  const originalFetch = globalThis.fetch.bind(globalThis);
  const storage = chrome.storage.local;

  // Serialise every queue mutation: the service worker interleaves awaits.
  let lock = Promise.resolve();
  function withLock(fn) {
    const run = lock.then(fn, fn);
    lock = run.catch(() => {});
    return run;
  }

  async function serverBase() {
    const data = await storage.get(['histerURL']);
    const u = data.histerURL || '';
    if (!u) return '';
    return u.endsWith('/') ? u : u + '/';
  }

  function requestURL(input) {
    if (typeof input === 'string') return input;
    if (input instanceof URL) return input.href;
    return (input && input.url) || '';
  }

  // The endpoint (api/add, api/rules) when url is on the Hister server, else ''.
  async function histerEndpoint(url) {
    const base = await serverBase();
    if (!base || !url.startsWith(base)) return '';
    return url.slice(base.length).split(/[?#]/, 1)[0];
  }

  async function readIndex() {
    const data = await storage.get([INDEX_KEY]);
    return Array.isArray(data[INDEX_KEY]) ? data[INDEX_KEY] : [];
  }

  function stampAdded(body) {
    try {
      const doc = JSON.parse(body);
      if (doc && typeof doc === 'object' && doc.added === undefined) {
        doc.added = Math.floor(Date.now() / 1000);
        return { body: JSON.stringify(doc), pageURL: String(doc.url || '') };
      }
      return { body, pageURL: String((doc && doc.url) || '') };
    } catch (_) {
      return null;
    }
  }

  // Credentials are never written to disk; drain() re-reads them.
  function withoutCredentials(headers) {
    const out = {};
    for (const [k, v] of Object.entries(headers)) {
      if (!/^(x-access-token|cookie|authorization)$/i.test(k)) out[k] = v;
    }
    return out;
  }

  function enqueue(url, headers, rawBody) {
    return withLock(async () => {
      // Fail closed: without a copy of the server's skip rules, a page it
      // would refuse (a bank, mail) could not be recognised and would sit
      // in the queue until the server said no.
      if (typeof (await storage.get([RULES_KEY]))[RULES_KEY] !== 'string') return false;
      const stamped = stampAdded(rawBody);
      if (!stamped) return false;
      let index = await readIndex();

      // One entry per page: a newer snapshot replaces the queued one but
      // keeps the first visit time.
      const existing = index.find((e) => e.pageURL === stamped.pageURL);
      let body = stamped.body;
      if (existing) {
        const old = (await storage.get([existing.key]))[existing.key];
        try {
          const firstAdded = JSON.parse(old.body).added;
          if (firstAdded !== undefined) {
            const doc = JSON.parse(body);
            doc.added = firstAdded;
            body = JSON.stringify(doc);
          }
        } catch (_) {}
        index = index.filter((e) => e !== existing);
        await storage.remove(existing.key);
      }

      if (body.length > MAX_BYTES) return false;
      const key = ITEM_PREFIX + Date.now() + ':' + Math.random().toString(36).slice(2);
      const entry = {
        key,
        pageURL: stamped.pageURL,
        bytes: body.length,
        attempts: 0,
        queuedAt: Date.now(),
      };
      index.push(entry);

      // Over the cap: the oldest captures go first.
      const evicted = [];
      let total = index.reduce((n, e) => n + e.bytes, 0);
      while (index.length > MAX_ITEMS || total > MAX_BYTES) {
        const e = index.shift();
        total -= e.bytes;
        evicted.push(e.key);
      }
      if (evicted.length) await storage.remove(evicted);

      try {
        await storage.set({ [key]: { url, headers: withoutCredentials(headers), body } });
      } catch (_) {
        return false; // storage full; drop this capture rather than the queue
      }
      await storage.set({ [INDEX_KEY]: index });
      return true;
    });
  }

  // Tell the host how many captures are waiting (the app's Settings →
  // Waiting to Send; it can't read the browser's storage). Debounced; best
  // effort.
  let reportTimer = null;
  function reportQueue() {
    if (!shioriHost.canReportQueue()) return;
    clearTimeout(reportTimer);
    reportTimer = setTimeout(async () => {
      try {
        const index = await readIndex();
        const oldest = index.length
          ? Math.min(...index.map((e) => e.queuedAt || Date.now())) / 1000
          : null;
        await shioriHost.reportQueue(index.length, oldest);
      } catch (_) {}
    }, 500);
  }

  function forget(pageURL) {
    if (!pageURL) return Promise.resolve();
    return withLock(async () => {
      const index = await readIndex();
      const stale = index.filter((e) => e.pageURL === pageURL);
      if (!stale.length) return;
      await storage.remove(stale.map((e) => e.key));
      await storage.set({ [INDEX_KEY]: index.filter((e) => e.pageURL !== pageURL) });
    });
  }

  let draining = false;
  async function drain() {
    if (draining) return;
    draining = true;
    try {
      for (;;) {
        const head = (await readIndex())[0];
        if (!head) return;
        const item = (await storage.get([head.key]))[head.key];
        let done = true;
        const expired = Date.now() - (head.queuedAt ?? Date.now()) > MAX_AGE_MS;
        if (item && !expired) {
          // Upstream's optional access token, read fresh at replay and never
          // stored with the queued item. Shiori's server has no login (so
          // it's normally unset), but a token-protected Hister would
          // otherwise refuse every replay and the queue would drop them.
          const { histerToken } = await storage.get(['histerToken']);
          const headers = { ...item.headers };
          if (histerToken) headers['X-Access-Token'] = histerToken;
          let r;
          try {
            r = await originalFetch(item.url, {
              method: 'POST',
              headers,
              body: item.body,
              credentials: 'include',
            });
          } catch (_) {
            return; // still offline; keep everything
          }
          if (r.status >= 500 || r.status === 429) {
            done = head.attempts + 1 >= MAX_ATTEMPTS;
            if (!done) {
              await withLock(async () => {
                const index = await readIndex();
                const e = index.find((x) => x.key === head.key);
                if (e) e.attempts += 1;
                await storage.set({ [INDEX_KEY]: index });
              });
              return; // server unwell; try again on the next trigger
            }
          }
        }
        if (done) {
          await withLock(async () => {
            const index = (await readIndex()).filter((e) => e.key !== head.key);
            await storage.remove(head.key);
            await storage.set({ [INDEX_KEY]: index });
          });
        }
      }
    } catch (_) {
    } finally {
      draining = false;
      reportQueue();
    }
  }

  function plainHeaders(h) {
    if (!h) return {};
    if (typeof Headers !== 'undefined' && h instanceof Headers) {
      const out = {};
      h.forEach((v, k) => (out[k] = v));
      return out;
    }
    return Array.isArray(h) ? Object.fromEntries(h) : { ...h };
  }

  // Provenance: Hister stores arbitrary metadata, so every capture says
  // which client sent it. Two fields, not "shiori/<version>": Hister's
  // query parser cannot match a "/" (metadata.client:shiori
  // metadata.client_version:0.1.0 both work). And `source: "shiori"`,
  // Hister's convention for where a document came from (its importers set
  // `source: "<service>"`), unless one is set.
  const clientVersion = (() => {
    try {
      return chrome.runtime.getManifest().version;
    } catch (_) {
      return '';
    }
  })();

  // Safari's stand-ins for a title it doesn't have: the tab of a PDF (and
  // of a page reached from Shiori's results) can report "Start Page", and
  // upstream sends a PDF with the tab's title (a PDF was indexed as
  // "Start Page").
  const PLACEHOLDER_TITLES = new Set(['Start Page', 'Untitled', 'Favorites']);

  /** A title from the URL's file name: "Sample_Report_2021.pdf" → "Sample Report 2021". */
  function titleFromURL(pageURL) {
    try {
      const u = new URL(pageURL);
      const last = decodeURIComponent(u.pathname.split('/').filter(Boolean).pop() || '');
      const name = last.replace(/\.[a-z0-9]{1,5}$/i, '').replace(/[_+-]+/g, ' ').replace(/\s+/g, ' ').trim();
      return name || u.host;
    } catch (_) {
      return '';
    }
  }

  /** The document with a real title: an empty one, the URL itself, or (for
   *  a PDF) Safari's placeholder is replaced from the file name. */
  function withTitle(doc, isPDF) {
    if (!doc || typeof doc !== 'object' || typeof doc.url !== 'string') return doc;
    const title = typeof doc.title === 'string' ? doc.title.trim() : '';
    const missing = !title || title === doc.url || (isPDF && PLACEHOLDER_TITLES.has(title));
    if (!missing) return doc;
    const better = titleFromURL(doc.url);
    return better ? { ...doc, title: better } : doc;
  }

  /** api/add's body with the client tag and a real title, and the page it's
   *  for. Parsed once: the body is the whole page, megabytes on a big one. */
  function prepAdd(body) {
    try {
      const doc = withTitle(JSON.parse(body), false);
      if (!doc || typeof doc !== 'object') return { body, pageURL: '' };
      doc.metadata = { source: 'shiori', ...(doc.metadata || {}), client: 'shiori' };
      if (clientVersion) doc.metadata.client_version = clientVersion;
      return { body: JSON.stringify(doc), pageURL: String(doc.url || '') };
    } catch (_) {
      return { body, pageURL: '' };
    }
  }

  /** api/add_pdf's body: {document, pdf}. Tag the client and fix the title. */
  function prepPDF(body) {
    try {
      const outer = JSON.parse(body);
      if (!outer || typeof outer !== 'object' || !outer.document) return body;
      const doc = withTitle(outer.document, true);
      doc.metadata = { source: 'shiori', ...(doc.metadata || {}), client: 'shiori' };
      if (clientVersion) doc.metadata.client_version = clientVersion;
      return JSON.stringify({ ...outer, document: doc });
    } catch (_) {
      return body;
    }
  }

  function isManual(body) {
    try {
      const doc = JSON.parse(body);
      return !!(doc && doc.metadata && doc.metadata.ignore_skip_rules);
    } catch (_) {
      return false;
    }
  }

  globalThis.fetch = async function shioriFetch(input, init) {
    const url = requestURL(input);
    const method = ((init && init.method) || (input && input.method) || 'GET').toUpperCase();
    const endpoint = url ? await histerEndpoint(url) : '';

    if (endpoint === 'api/rules' && method === 'GET') {
      try {
        const r = await originalFetch(input, init);
        if (r.ok) {
          const text = await r.clone().text();
          void storage.set({ [RULES_KEY]: text }).catch(() => {});
        }
        if (r.status < 500) void drain();
        return r;
      } catch (err) {
        const cached = (await storage.get([RULES_KEY]))[RULES_KEY];
        if (typeof cached === 'string') {
          return new Response(cached, {
            status: 200,
            headers: { 'Content-Type': 'application/json', 'X-Shiori-Cached': '1' },
          });
        }
        throw err;
      }
    }

    // PDFs aren't queued (they can be large); they get the client tag and a
    // real title, then go as they are.
    if (endpoint === 'api/add_pdf' && method === 'POST' && init && typeof init.body === 'string') {
      return originalFetch(input, { ...init, body: prepPDF(init.body) });
    }

    if (endpoint === 'api/add' && method === 'POST' && init && typeof init.body === 'string') {
      const prepared = prepAdd(init.body);
      init = { ...init, body: prepared.body };
      const headers = plainHeaders(init.headers);
      let r;
      try {
        r = await originalFetch(input, init);
      } catch (err) {
        const queued = await enqueue(url, headers, init.body).catch(() => false);
        if (queued) reportQueue();
        if (!queued) throw err;
        if (isManual(init.body)) {
          throw new TypeError('Hister is unreachable. Queued; it will be sent when the server is back.');
        }
        return new Response('{}', {
          status: 201,
          headers: { 'Content-Type': 'application/json', 'X-Shiori-Queued': '1' },
        });
      }
      if (r.status >= 500 || r.status === 429) {
        await enqueue(url, headers, init.body).catch(() => false);
      } else {
        // The server has answered for this page; a queued copy is stale.
        await forget(prepared.pageURL).catch(() => {});
        void drain();
      }
      return r;
    }

    return originalFetch(input, init);
  };

  // Fetch the skip rules as soon as the worker starts, so the queue has
  // them before the first offline capture (enqueue fails closed without).
  (async () => {
    const base = await serverBase();
    if (!base) return;
    try {
      const r = await originalFetch(base + 'api/rules', { headers: {}, credentials: 'include' });
      if (r.ok) await storage.set({ [RULES_KEY]: await r.text() });
    } catch (_) {}
  })().finally(() => void drain());
})();

// 2. Combined search. The duckduckgo.com content script (shiori/redirect.js)
//    asks here whether to take a search over; if the setting is on, the tab
//    moves to search.html. Settings come from the host (on Safari the app,
//    through native messaging and its App Group) and are cached in
//    storage.local for the results page. Shiori's messages carry `shiori:`
//    and are kept away from upstream's own onMessage handler.
(function installCombinedSearch() {
  if (typeof chrome === 'undefined' || !chrome.runtime || !chrome.runtime.onMessage) return;
  if (!chrome.storage || !chrome.storage.local) return;

  const SETTINGS_KEY = 'shioriSettings';
  // SearXNG default baked in by scripts/build-extension.sh (local.yml).
  const DEFAULTS = {
    combinedSearch: true,
    searxngURL: '__SHIORI_SEARXNG_URL__',
    theme: 'system',
    // The results page's options (the app's Settings → Search from Safari).
    showInfobox: true,
    showRelated: true,
    aiAnswer: true,
    showThumbnails: true,
    histerInGeneral: true,
    histerTab: true,
    histerCount: 5,
    vaultInGeneral: true,
    vaultTab: true,
    vaultCount: 3,
    webResults: true,
    searchHistory: true,
    recentSearches: [],
    textSize: 'system',
    previewImages: true,
    rememberOpened: true,
    showOpened: false,
    resultStyle: 'tint',
    smallWebTab: true,
    smallWebOpen: 'gateway',
    smallwebURL: '',
    // Sent by the app too; without them here the page never heard of a
    // change (refreshSettings keeps only these keys).
    previewPane: true,
    foldRepeats: true,
    searchFilters: true,
    labelSuggestions: true,
    obsidianVault: '__SHIORI_OBSIDIAN_VAULT__',
    niwaURL: '__SHIORI_NIWA_URL__',
    konbiniURL: '__SHIORI_KONBINI_URL__',
  };
  // The results page asks for fresh settings as it opens, just after the
  // search handed it over, which asked the app already.
  const PAGE_FRESH_MS = 5_000;
  let lastRefresh = 0;
  let refreshing = null;

  async function readSettings() {
    const stored = (await chrome.storage.local.get([SETTINGS_KEY]))[SETTINGS_KEY];
    return { ...DEFAULTS, ...(stored || {}) };
  }

  /** Ask the host for its settings. A request already under way is shared,
   *  and with maxAge a copy fetched that recently counts. `after: true` is
   *  for a caller that just changed them: it waits out a request that set
   *  off before the change, then asks again. */
  function refreshSettings({ maxAge = 0, after = false } = {}) {
    if (refreshing) {
      if (!after) return refreshing;
      return refreshing.catch(() => {}).then(() => refreshSettings({ after: true }));
    }
    if (maxAge && Date.now() - lastRefresh < maxAge) return Promise.resolve();
    refreshing = askHost().finally(() => {
      lastRefresh = Date.now();
      refreshing = null;
    });
    return refreshing;
  }

  async function askHost() {
    let reply;
    try {
      reply = await shioriHost.settings();
    } catch (_) {
      reply = null;
    }
    const next = { ...DEFAULTS, fetchedAt: Date.now() };
    const changes = { [SETTINGS_KEY]: next };
    if (reply && typeof reply === 'object') {
      for (const key of Object.keys(DEFAULTS)) if (key in reply) next[key] = reply[key];
      // The app's Hister server is the extension's too (its options page
      // shows and edits the same histerURL).
      if (typeof reply.serverURL === 'string' && /^https?:\/\//i.test(reply.serverURL)) {
        const url = reply.serverURL.endsWith('/') ? reply.serverURL : reply.serverURL + '/';
        const current = (await chrome.storage.local.get(['histerURL'])).histerURL;
        if (current !== url) changes.histerURL = url;
      }
    }
    await chrome.storage.local.set(changes);
  }

  // Going Back from Shiori's page reloads DuckDuckGo as a fresh navigation
  // (not back_forward), and its sessionStorage is gone too (seen on iOS 27).
  // So the background remembers what each tab was handed:
  // the same tab asking again for the same search within a few minutes
  // is the user going Back, and DuckDuckGo stays, once.
  //
  // Back from a RESULT is different: on a device Safari can skip the
  // extension page and land on DuckDuckGo. The results
  // page reports when it's left for a result; if DuckDuckGo then comes back
  // with that search, the tab goes to the results page again, which redraws
  // from its saved copy at the same scroll position.
  const HANDED_KEY = 'shioriHandedOver';
  const LEFT_KEY = 'shioriLeftForResult';
  const BACK_WINDOW_MS = 5 * 60_000;
  const RESULT_WINDOW_MS = 30 * 60_000;

  function prune(map, windowMs, now) {
    for (const [id, entry] of Object.entries(map)) {
      if (!entry || now - entry.at > windowMs) delete map[id];
    }
    return map;
  }

  /** 'new' for a fresh search, 'results' (with the page to return to) or 'back'. */
  async function cameBack(tabId, q) {
    const now = Date.now();
    const stored = await chrome.storage.local.get([HANDED_KEY, LEFT_KEY]);
    const handed = prune(stored[HANDED_KEY] || {}, BACK_WINDOW_MS, now);
    const left = prune(stored[LEFT_KEY] || {}, RESULT_WINDOW_MS, now);
    const previous = handed[tabId];
    const leftFor = left[tabId];
    let outcome;
    if (leftFor && leftFor.q === q) {
      outcome = { kind: 'results', search: leftFor.search };
      delete left[tabId];
      handed[tabId] = { q, at: now };
    } else if (previous && previous.q === q) {
      outcome = { kind: 'back' };
      delete handed[tabId];
    } else {
      outcome = { kind: 'new' };
      handed[tabId] = { q, at: now };
    }
    await chrome.storage.local.set({ [HANDED_KEY]: handed, [LEFT_KEY]: left });
    return outcome;
  }

  async function leftForResult(tabId, q, search) {
    const left = (await chrome.storage.local.get([LEFT_KEY]))[LEFT_KEY] || {};
    left[tabId] = { q, search, at: Date.now() };
    await chrome.storage.local.set({ [LEFT_KEY]: left });
  }

  const onMessage = chrome.runtime.onMessage;
  const addListener = onMessage.addListener.bind(onMessage);
  onMessage.addListener = function withoutShioriMessages(listener) {
    return addListener((request, sender, sendResponse) => {
      if (request && request.shiori) return false;
      return listener(request, sender, sendResponse);
    });
  };

  addListener((request, sender, sendResponse) => {
    if (!request || !request.shiori) return false;
    if (request.shiori === 'left-for-result') {
      const tabId = (sender && sender.tab && sender.tab.id) ?? request.tabId;
      if (tabId != null && request.q && typeof request.search === 'string' && request.search.startsWith('?')) {
        leftForResult(tabId, request.q, request.search).then(() => sendResponse({ ok: true }));
        return true;
      }
      return false;
    }
    if (request.shiori === 'record-search') {
      // Into the app's list (shared with its Search), then back into the
      // settings copy the next page reads.
      if (typeof request.q !== 'string' || !request.q.trim()) return false;
      Promise.resolve()
        .then(() => shioriHost.recordSearch(request.q.trim().slice(0, 500)))
        .catch(() => {})
        .then(() => refreshSettings({ after: true }))
        .then(() => sendResponse({ ok: true }), () => sendResponse({ ok: false }));
      return true;
    }
    if (request.shiori === 'set-settings') {
      // The results page's own Settings: into the host (the app's App
      // Group, the one home for them), then a fresh copy back for the page.
      if (!request.values || typeof request.values !== 'object') return false;
      Promise.resolve()
        .then(() => shioriHost.setSettings(request.values))
        .then(
          () => refreshSettings({ after: true }).then(readSettings),
          async () => {
            // No app to answer: keep the change here, until the app has a say.
            const next = { ...(await readSettings()), ...request.values };
            await chrome.storage.local.set({ [SETTINGS_KEY]: next });
            return next;
          },
        )
        .then((settings) => sendResponse({ ok: true, settings }), () => sendResponse({ ok: false }));
      return true;
    }
    if (request.shiori === 'refresh-settings') {
      refreshSettings({ maxAge: PAGE_FRESH_MS }).then(() => sendResponse({ ok: true }), () => sendResponse({ ok: false }));
      return true;
    }
    if (request.shiori !== 'search') return false;
    (async () => {
      // Ask the host every time, so a switch just flipped in Settings counts
      // for the very next search. Native messaging is quick; if it isn't,
      // the cached settings answer after 400 ms (the page stays hidden
      // meanwhile, so nothing flashes). Whether the hosted page answers is
      // asked at the same time, not after: the two waits used to add up.
      const where = resultsBase();
      await Promise.race([refreshSettings(), new Promise((r) => setTimeout(r, 400))]);
      const settings = await readSettings();
      const tabId = sender && sender.tab && sender.tab.id;
      if (!settings.combinedSearch || tabId == null || !request.q) {
        sendResponse({ redirect: false });
        return;
      }
      // The hosted page: DuckDuckGo's own tab goes there (location.replace
      // in the content script). tabs.update left Safari's address bar
      // focused and selected on the Mac, as if typed, and a
      // replace takes DuckDuckGo out of Back, so there's no Back to
      // detect: the same search again in the tab is a search again (it
      // was taken for Back and left on DuckDuckGo).
      const base = await where;
      if (/^https?:/.test(base)) {
        sendResponse({ redirect: true, url: base + '?q=' + encodeURIComponent(request.q) });
        return;
      }
      // The extension page, which only tabs.update can reach (a page can't
      // load one): Back from it reloads DuckDuckGo, so that's detected.
      const back = await cameBack(tabId, request.q);
      if (back.kind === 'back') {
        sendResponse({ redirect: false });
        return;
      }
      const url = base + (back.kind === 'results' ? back.search : '?q=' + encodeURIComponent(request.q));
      try {
        await chrome.tabs.update(tabId, { url });
        sendResponse({ redirect: true });
      } catch (_) {
        sendResponse({ redirect: false });
      }
    })();
    return true;
  });

  void refreshSettings();
})();

// Where results open: the hosted search page when it answers, else the
// extension's own. A tab showing an extension page is closed when iOS
// restores a Safari it suspended (the results vanished on returning to
// Safari); a web page is restored like any other. The host is
// checked (a second at most, the answer kept a minute) so that with
// the server out of reach a search still gets results, from the extension page.
// One check at a time: a search arriving while one is under way shares it.
const SEARCH_PAGE_URL = '__SHIORI_SEARCH_PAGE_URL__';
let searchPageUp = { at: 0, ok: false };
let searchPageCheck = null;
async function resultsBase() {
  const local = chrome.runtime.getURL('search.html');
  if (!/^https?:\/\//.test(SEARCH_PAGE_URL)) return local;
  if (Date.now() - searchPageUp.at > 60_000) {
    searchPageCheck = searchPageCheck || checkSearchPage().finally(() => (searchPageCheck = null));
    await searchPageCheck;
  }
  return searchPageUp.ok ? SEARCH_PAGE_URL : local;
}

async function checkSearchPage() {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 1000);
  let ok = false;
  try {
    const reply = await fetch(SEARCH_PAGE_URL + '_shiori/opensearch.xml', { method: 'GET', cache: 'no-store', signal: controller.signal });
    ok = reply.ok;
  } catch (_) {}
  clearTimeout(timer);
  searchPageUp = { at: Date.now(), ok };
}

// A DuckDuckGo search starting to load: check the hosted page now, while
// DuckDuckGo answers, so the redirect doesn't wait for it afterwards.
(function prepareForSearches() {
  if (typeof chrome === 'undefined' || !chrome.tabs || !chrome.tabs.onUpdated) return;
  chrome.tabs.onUpdated.addListener((_tabId, changeInfo, tab) => {
    const url = changeInfo.url || (tab && tab.url) || '';
    if (changeInfo.status === 'loading' && /^https:\/\/(www\.)?duckduckgo\.com\/\?(.*&)?q=/.test(url)) void resultsBase();
  });
})();

// Shiori's own command: Open Shiori Search (on Safari its key is set in
// Safari → Settings → Extensions → Shiori). Opens the results page's start
// page in a new tab.
(function installShioriCommands() {
  if (typeof chrome === 'undefined' || !chrome.commands || !chrome.commands.onCommand) return;
  chrome.commands.onCommand.addListener((command) => {
    if (command !== 'open-shiori-search') return;
    resultsBase().then((url) => chrome.tabs.create({ url }));
  });
})();
