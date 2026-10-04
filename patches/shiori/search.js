// Shiori's combined results page, laid out like SearXNG's: pages from
// Hister (in General, or on a tab of their own), then the web from
// SearXNG. The two engines' scores aren't comparable, so they stay in
// separate blocks. If SearXNG can't be reached on a first search, the page
// hands the search to plain DuckDuckGo, so searching never breaks.
//
// Everything from the network is added as text or attributes; no response
// HTML is ever inserted, except Hister's snippet <mark>s, rebuilt from text.
//
// Coming Back to a results page redraws it from what was fetched (kept in
// storage.local for 30 minutes) and returns to the same scroll position,
// with the same sections open. Reload fetches afresh.
(async function () {
  const S = globalThis.ShioriSearch;
  const $ = (id) => document.getElementById(id);
  const WEB_TIMEOUT_MS = 4000;
  const PAGE_CACHE_KEY = 'shioriPageCache';
  const PAGE_CACHE_MS = 30 * 60_000;
  const PAGE_CACHE_MAX = 12;

  const params = new URLSearchParams(location.search);
  const q = (params.get('q') || '').trim();
  const time = ['day', 'week', 'month', 'year'].includes(params.get('time')) ? params.get('time') : '';
  const page = Math.max(1, parseInt(params.get('page') || '1', 10) || 1);
  const histerKey = params.get('hk') || '';
  const histerSort = params.get('hs') === 'new' ? 'new' : '';
  // The Notes tab's vaults (Kura's work vaults included: they're
  // searchable in Notes wherever Shiori runs): 'all', or one's name.
  const vaultParam = params.get('vault') || 'all';
  const terms = S.highlightTerms(q);
  // Your pages, notes or files: the full search of one, sorted rather than filtered by time.
  const isNoteTab = (cat) => cat === 'hister' || cat === 'vault' || cat === 'files';
  // The app's Text Size, one setting for the app and this page. Scales
  // as Dynamic Type steps body text (17 points at Large).
  const TEXT_SCALES = { xSmall: 14, small: 15, medium: 16, large: 17, xLarge: 19, xxLarge: 21, xxxLarge: 23 };
  // A Mac (not an iPad, which also says "Mac"): its system text is 13
  // points, so the page starts larger there, as the app does (TextSize.macBase).
  const IS_MAC = /Mac/.test(navigator.platform) && navigator.maxTouchPoints < 2;
  const MAC_BASE = 1.2;

  // The header as it was last drawn (theme and tabs), kept in localStorage
  // because that can be read before the first paint: switching tabs loads
  // a new page, and it should arrive with its header already in place
  // rather than blank for the half second the settings can take.
  const HEADER_KEY = 'shioriHeader';
  // Whether Hister had files (the folders it watches) last time: the Files
  // tab is drawn from it at once, and asked again once the page is up.
  const FILES_KEY = 'shioriHasFiles';
  let hasFiles = false;
  try {
    hasFiles = localStorage.getItem(FILES_KEY) === '1';
  } catch (_) {}
  let header = null;
  // Counts on the Pages and Notes pills (All's searches find them), kept so
  // the header's redraws (a settings change) keep them.
  const pillCounts = {};
  try {
    header = JSON.parse(localStorage.getItem(HEADER_KEY) || 'null');
  } catch (_) {}
  // Two arrangements: the cards with their tags up
  // on the date line, and a dense list (?layout=dense). Kept in this
  // browser, so switching tabs keeps it; ?layout=cards goes back.
  try {
    const asked = params.get('layout');
    if (asked === 'dense' || asked === 'cards') localStorage.setItem('shioriCardLayout', asked);
    document.body.classList.toggle('dense', localStorage.getItem('shioriCardLayout') === 'dense');
  } catch (_) {}
  // As the field's default too: Safari resets an autocomplete="off" field
  // to its default when the page comes back from its Back-Forward cache,
  // which left the web page's field empty after leaving for a result.
  $('q').defaultValue = q;
  $('q').value = q;
  window.addEventListener('pageshow', (event) => {
    if (event.persisted && document.activeElement !== $('q')) $('q').value = q;
  });
  document.title = q ? `${q} – Shiori` : 'Shiori';
  if (header) drawHeader(header);
  // All's first page has the two columns (results, and the Info card
  // beside them) from the first paint: they came only when the card did,
  // so on a reload the search bar and tabs drew narrow, then snapped wide
  // a second later. The last header says whether the card is
  // on; the settings confirm it below.
  // Pages and Notes keep All's width, their right column empty, so moving
  // between them doesn't narrow the page.
  const twoColumns = (s) => !!q && s.infobox !== false && s.webResults !== false;
  // Every tab keeps All's width (Small Web, News and the rest shrank):
  // results in the first column, the second empty but for All's Info;
  // Images' tiles take both (search.css).
  const wideCat = (cat) => ['general', 'web', 'hister', 'vault', 'images', 'videos', 'news', 'smallweb', 'files'].includes(cat || 'general');
  document.body.classList.toggle('two-col', wideCat(params.get('cat')) && twoColumns(header || {}));
  document.body.dataset.cat = params.get('cat') || 'general';

  // Fresh settings from the app first (a switch just flipped should count
  // on this page), but never wait more than half a second for them.
  await Promise.race([
    new Promise((resolve) => {
      try {
        chrome.runtime.sendMessage({ shiori: 'refresh-settings' }, () => {
          void chrome.runtime.lastError;
          resolve();
        });
      } catch (_) {
        resolve();
      }
    }),
    new Promise((resolve) => setTimeout(resolve, 500)),
  ]);
  const FOLDS_KEY = 'shioriFolds';
  // Your pages and notes in All: a page of each (as the Pages tab's), all
  // of them among the web results (mixIn).
  const ALL_COUNT = 20;
  const stored = await chrome.storage.local.get(['histerURL', 'histerToken', PAGE_CACHE_KEY, FOLDS_KEY, 'shioriSettings']);
  // Hister's token where this device has one (the extension; the hosted
  // page has none: its host signs it in), sent as X-Access-Token.
  const histerAuth = (headers = {}) => S.histerHeaders(stored.histerToken, headers);
  const settings = {
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
    previewPane: true,
    previewImages: true,
    rememberOpened: true,
    // Pages you opened, shown (lifted into Your Pages): off by default,
    // they mostly cluttered things.
    showOpened: false,
    resultStyle: 'tint',
    foldRepeats: true,
    labelSuggestions: true,
    // The build's SHIORI_OBSIDIAN_VAULT; none in a
    // public build, where notes link to Kura until the gear names one.
    obsidianVault: S.fromBuild('__SHIORI_OBSIDIAN_VAULT__'),
    niwaURL: '',
    konbiniURL: '',
    // Gemini and Gopher through the small-web gateway, and where a
    // result opens: its page, or the gemini:// link (docs/smallweb.md).
    smallwebURL: '',
    smallWebTab: true,
    smallWebOpen: 'gateway',
    ...(stored.shioriSettings || {}),
  };
  // An older build's "Hister Tab Only" choice.
  if (stored.shioriSettings && stored.shioriSettings.histerPlacement === 'tab' && !('histerInGeneral' in stored.shioriSettings)) {
    settings.histerInGeneral = false;
  }
  // How your pages, notes and opened pages stand apart: search.css keys
  // the cards' tint, bar or nothing off this.
  document.body.dataset.resultStyle = ['tint', 'solid', 'bar', 'none'].includes(settings.resultStyle) ? settings.resultStyle : 'tint';
  const histerBase = withSlash(stored.histerURL || '');
  // The gateway: on the page's own host for the hosted page (/smallweb/),
  // else its own address (the app's setting).
  const smallwebBase = withSlash(settings.smallwebAPIURL || '') || withSlash(settings.smallwebURL || '');
  const searxBase = withSlash(settings.searxngURL || '');
  const niwaBase = withSlash(settings.niwaURL || '');
  const konbiniBase = withSlash(settings.konbiniURL || '');
  // Where the card list is fetched: Konbini itself, or (the web page,
  // which can't read another site's replies) a path on its own host.
  const konbiniAPIBase = withSlash(settings.konbiniAPIURL || '') || konbiniBase;
  // The AI endpoint: set only on the hosted page (web/shim.js), and only
  // when its build has one (SHIORI_AI=1).
  const aiBase = withSlash(settings.aiURL || '');
  // Notes come only from Kura:
  // its API on the page's own host for the hosted page (/kura/), else on
  // the Kura reader's. Hister's queries leave the notes out (S.histerText).
  const kuraBase = withSlash(settings.kuraAPIURL || '') || niwaBase;
  // Machiya sign-in (docs/signing-in.md). In the extension: its token,
  // which the background hands to its own pages only, sent to Kura and
  // Konbini through search-core's host rule (never Hister or SearXNG,
  // never across a redirect; credentials stay 'omit'). The hosted page has
  // no token: its /kura/ and /konbini/ are on its own host, and the
  // browser's machiya_session cookie goes with them.
  const machiyaRooms = S.machiyaRooms([niwaBase, konbiniBase, kuraBase, konbiniAPIBase], [histerBase, searxBase]);
  const machiyaTokenReady = Promise.race([
    new Promise((resolve) => {
      try {
        chrome.runtime.sendMessage({ shiori: 'machiya' }, (reply) => {
          void chrome.runtime.lastError;
          resolve((reply && reply.ok && reply.token) || '');
        });
      } catch (_) {
        resolve('');
      }
    }),
    new Promise((resolve) => setTimeout(() => resolve(''), 500)),
  ]);
  /** Whether url is on this page's own host (the hosted page's /kura/, /konbini/). */
  function sameOrigin(url) {
    try {
      return /^https?:$/.test(location.protocol) && new URL(url, location.href).origin === location.origin;
    } catch (_) {
      return false;
    }
  }
  /** A room's fetch options: the hosted page's cookie, or the extension's token where the rule allows. */
  async function roomInit(url, init) {
    if (sameOrigin(url)) return { ...init, credentials: 'same-origin' };
    return S.machiyaFetchOptions(url, await machiyaTokenReady, machiyaRooms, init);
  }
  /** What to say when a room answers 401: sign in (the room's own page here, Settings in the extension). */
  function signInNote(room) {
    const where = sameOrigin(kuraBase) ? S.machiyaSignInURL(niwaBase) : '';
    return where
      ? [`${room} asks you to sign in. `, el('a', { href: where }, 'Sign In')]
      : [`${room} asks you to sign in: Settings → Sign in to Machiya.`];
  }
  /** Notes from Kura, in Hister's shape ({documents, total}). */
  async function kuraNotes(text, options) {
    return S.kuraDocuments(await fetchJSON(S.kuraURL(kuraBase, text, options), { timeout: 8000, room: true }));
  }
  // Kura's vaults (/api/vaults), for a work note's title and Obsidian vault,
  // the Notes tab's filter, and which vaults are shared (S.useVaults; until
  // it answers, every other vault is private). Asked once, only for the
  // Notes tab, where another vault's notes show.
  let kuraVaults = [];
  // Read afresh each time (no copy kept here); also before another vault's
  // note goes to Hister (S.isPrivateNoteNow). A failure throws: none shared.
  const readVaultsNow = () =>
    kuraBase ? fetchJSON(`${kuraBase}api/vaults`, { timeout: 4000, room: true }).then((r) => r && r.vaults) : Promise.resolve([]);
  const vaultsReady = () => S.loadVaults(readVaultsNow).then((list) => (list.length ? (kuraVaults = list) : list));

  // Every source can be switched off on its own (the app's Settings): Hister
  // and the vault each in General and as a tab, and the web results.
  // The pills in the order the person set, less the ones they hid
  // (settings.pills, S.orderPills); the conditions below still apply.
  const PILL_OF = { general: 'all', hister: 'pages', vault: 'notes' };
  const pillKey = (cat) => PILL_OF[cat] || cat;
  const inPillOrder = (cats) => {
    const order = S.orderPills(cats.map(([c]) => pillKey(c)), settings.pills);
    return order.map((key) => cats.find(([c]) => pillKey(c) === key));
  };
  const CATEGORIES = inPillOrder([
    // Shown as "All" (as in the app); still SearXNG's general category.
    ['general', 'All'],
    // Your pages are "Pages", as in the app; "Hister" is the server.
    ...(settings.histerTab ? [['hister', 'Pages']] : []),
    ...(settings.vaultTab ? [['vault', 'Notes']] : []),
    ...(settings.webResults
      ? [
          // The web alone: All without your pages and notes (no count).
          ['web', 'Web'],
          ['images', 'Images'],
          ['videos', 'Videos'],
          ['news', 'News'],
        ]
      : []),
    ...(settings.smallWebTab !== false && smallwebBase ? [['smallweb', 'Small Web']] : []),
    // The folders Hister watches (type:local), once it has some files.
    ...(hasFiles && histerBase ? [['files', 'Files']] : []),
  ]);
  const category = CATEGORIES.some(([c]) => c === params.get('cat')) ? params.get('cat') : 'general';
  // All and Web are SearXNG's general results; Web without yours mixed in.
  const webLike = category === 'general' || category === 'web';
  const nextHeader = {
    theme: settings.theme || '',
    palette: settings.palette || '',
    categories: CATEGORIES,
    webResults: !!settings.webResults,
    textSize: settings.textSize,
    infobox: settings.showInfobox !== false,
  };
  document.body.classList.toggle('two-col', wideCat(category) && !!searxBase && twoColumns(nextHeader));
  if (JSON.stringify(nextHeader) !== JSON.stringify(header)) {
    drawHeader(nextHeader);
    try {
      localStorage.setItem(HEADER_KEY, JSON.stringify(nextHeader));
    } catch (_) {}
  }
  // Whether Hister has files, asked afresh: the Files tab comes or goes
  // with the answer, which the next page starts from.
  if (histerBase) {
    histerSearch(S.filesQuery(''), 1)
      .then((r) => {
        const found = !!(r && r.total);
        if (found === hasFiles) return;
        try {
          localStorage.setItem(FILES_KEY, found ? '1' : '0');
        } catch (_) {}
        nextHeader.categories = found ? inPillOrder([...CATEGORIES, ['files', 'Files']]) : CATEGORIES.filter(([c]) => c !== 'files');
        drawHeader(nextHeader);
        try {
          localStorage.setItem(HEADER_KEY, JSON.stringify(nextHeader));
        } catch (_) {}
      })
      .catch(() => {});
  }

  function link({ q: nq = q, cat = category, t = time, p = 1, hk = '', hs = histerSort, v = vaultParam } = {}) {
    const next = new URLSearchParams({ q: nq });
    if (cat !== 'general') next.set('cat', cat);
    if (cat === 'vault' && v && v !== 'all') next.set('vault', v);
    if (t && !isNoteTab(cat)) next.set('time', t);
    if (hs && isNoteTab(cat)) next.set('hs', hs);
    if (p > 1) next.set('page', String(p));
    if (hk) next.set('hk', hk);
    return '?' + next.toString();
  }

  // --- what this page fetched, and where it was left ------------------------------

  const nav = performance.getEntriesByType('navigation')[0];
  const cacheId = location.search;
  const allCached = stored[PAGE_CACHE_KEY] || {};
  const cached =
    nav && nav.type === 'reload' ? null : fresh(allCached[cacheId]) ? allCached[cacheId] : null;
  const pageState = {
    hister: cached && cached.hister,
    vault: cached && cached.vault,
    web: cached && cached.web,
    answer: cached && cached.answer,
    y: 0,
    folds: {},
  };
  // Your pages were fetched with a count; a copy made under another count
  // (the setting changed since) is fetched again. Everything else in the
  // settings only affects how the page is drawn, so the copy still serves.
  if (cached && category === 'general' && cached.histerCount !== ALL_COUNT) pageState.hister = null;
  if (cached && category === 'general' && cached.vaultCount !== ALL_COUNT) pageState.vault = null;
  if (cached) Object.assign(pageState.folds, cached.folds || {});

  function fresh(entry) {
    return entry && Date.now() - entry.at < PAGE_CACHE_MS;
  }

  let saveTimer = null;
  function saveState() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(persist, 250);
  }
  async function persist() {
    const all = (await chrome.storage.local.get([PAGE_CACHE_KEY]))[PAGE_CACHE_KEY] || {};
    // Never a work vault's note on the device: its results
    // leave the Back copy.
    const vault = pageState.vault && (pageState.vault.documents || []).some((d) => S.isPrivateNote(d.url)) ? undefined : pageState.vault;
    all[cacheId] = {
      at: (all[cacheId] && all[cacheId].at) || Date.now(),
      hister: pageState.hister,
      histerCount: ALL_COUNT,
      vault,
      vaultCount: ALL_COUNT,
      web: pageState.web,
      answer: pageState.answer,
      y: Math.round(window.scrollY),
      folds: pageState.folds,
    };
    const entries = Object.entries(all).filter(([, e]) => fresh(e));
    entries.sort(([, a], [, b]) => b.at - a.at);
    await chrome.storage.local.set({ [PAGE_CACHE_KEY]: Object.fromEntries(entries.slice(0, PAGE_CACHE_MAX)) });
  }
  window.addEventListener('scroll', saveState, { passive: true });
  window.addEventListener('pagehide', persist);
  document.addEventListener('visibilitychange', () => document.hidden && persist());
  // Leaving through a link: record the position first. Leaving for a
  // result (not a tab, page or filter link on this page) is also told to
  // the background, so coming Back via DuckDuckGo returns here.
  let tabId = null;
  try {
    chrome.tabs.getCurrent((tab) => (tabId = tab ? tab.id : null));
  } catch (_) {}
  document.addEventListener(
    'click',
    (event) => {
      const a = event.target.closest('a[href]');
      if (!a) return;
      // A preview into the pane isn't leaving the page.
      if (a.classList.contains('preview-link') && document.body.classList.contains('with-preview')) return;
      persist();
      const href = a.getAttribute('href') || '';
      if (/^https?:/i.test(href) && !href.includes('shiori=off')) {
        chrome.runtime.sendMessage(
          { shiori: 'left-for-result', q, search: location.search, tabId },
          () => void chrome.runtime.lastError,
        );
      }
    },
    true,
  );

  // --- header ------------------------------------------------------------------

  $('ddg').href = S.fallbackURL(q);
  $('search').addEventListener('submit', (event) => {
    event.preventDefault();
    hideSuggest();
    const next = $('q').value.trim();
    if (!next) return;
    if (S.hasBang(next)) location.href = S.fallbackURL(next);
    else location.href = link({ q: next, p: 1 });
  });
  $('clear').addEventListener('click', () => {
    $('q').value = '';
    $('q').focus();
    hideSuggest();
    drawRecent();
  });

  // Recent searches (the app's Settings → Search History): one list with
  // the app's, kept in the App Group. Tapping the field shows them; typing
  // narrows them. This search joins the list, unless it's a page coming
  // Back from its saved copy.
  const sameText = (a, b) => a.toLowerCase() === b.toLowerCase();
  let recent = settings.searchHistory
    ? (Array.isArray(settings.recentSearches) ? settings.recentSearches : [])
        .filter((s) => typeof s === 'string' && s.trim())
        .slice(0, 5)
    : [];
  if (q && settings.searchHistory && !cached && !(recent[0] && sameText(recent[0], q))) {
    recent = [q, ...recent.filter((s) => !sameText(s, q))].slice(0, 5);
    chrome.runtime.sendMessage({ shiori: 'record-search', q }, () => void chrome.runtime.lastError);
  }
  // Only while the field is empty, as in the apps: typing brings the
  // suggestions instead.
  function drawRecent() {
    const typed = $('q').value.trim();
    const shown = typed ? [] : recent.filter((s) => !sameText(s, q));
    $('recent-list').replaceChildren(
      ...shown.map((s, i) =>
        el('li', {}, el('a', { href: link({ q: s, cat: 'general', p: 1 }), role: 'option', id: `rc-${i}` }, s)),
      ),
    );
    $('recent').hidden = !shown.length || document.activeElement !== $('q') || document.body.classList.contains('home');
    if (!$('recent').hidden) $('suggest').hidden = true;
  }

  // --- Suggestions as you type (the apps and the web app have the same) --------
  // Your pages and notes whose titles fit what's typed, then searches from
  // SearXNG's autocompleter. A page or note opens; a search runs.
  let suggestToken = 0;
  let suggestTimer = 0;
  let suggestItems = [];
  let suggestActive = -1;

  function hideSuggest() {
    suggestToken++;
    $('suggest').hidden = true;
    suggestItems = [];
    suggestActive = -1;
    $('q').removeAttribute('aria-activedescendant');
  }

  // The server's aliases, for Labels in the suggestions: the labels they
  // name and the collections themselves (Hister has no call listing every
  // label). Kept an hour in this browser.
  const RULES_KEY = 'shioriRules';
  let rules = null;
  function cachedRules() {
    try {
      const stored = JSON.parse(localStorage.getItem(RULES_KEY) || 'null');
      if (stored && stored.base === histerBase && Date.now() - stored.at < 60 * 60_000) return stored.aliases;
    } catch (_) {}
    return null;
  }
  async function loadRules() {
    if (rules || !histerBase) return rules;
    const cached = cachedRules();
    if (cached) {
      const aliases = S.collectionAliases(cached);
      return (rules = { aliases, labels: S.labelsFromAliases(aliases).labels });
    }
    try {
      const reply = await fetchJSON(`${histerBase}api/rules`, { headers: histerAuth({ Accept: 'application/json' }) });
      const aliases = S.collectionAliases((reply && reply.aliases) || {});
      rules = { aliases, labels: S.labelsFromAliases(aliases).labels };
      try {
        localStorage.setItem(RULES_KEY, JSON.stringify({ base: histerBase, at: Date.now(), aliases }));
      } catch (_) {}
    } catch (_) {}
    return rules;
  }
  /** Labels and collections for what's typed, straight from the rules. */
  function labelItems(typed) {
    return rules && settings.labelSuggestions !== false ? S.labelSuggestions(typed, rules.labels, rules.aliases) : [];
  }

  function scheduleSuggest() {
    clearTimeout(suggestTimer);
    const typed = $('q').value.trim();
    if (!typed) return hideSuggest();
    // Labels are local: at once, before the Hister and web lookups.
    const now = () => {
      if ($('q').value.trim() !== typed) return;
      const labels = labelItems(typed);
      if (labels.length) drawSuggest({ labels, pages: [], notes: [], searches: [], cards: [] });
    };
    if (rules) now();
    else loadRules().then(now);
    suggestTimer = setTimeout(() => fetchSuggestions(typed), 200);
  }

  async function fetchSuggestions(typed) {
    const token = ++suggestToken;
    const queries = histerBase ? S.suggestionQueries(typed) : [];
    const webOn = settings.webResults !== false && !!searxBase && !S.hasBang(typed);
    const web = webOn
      ? fetchJSON(`${searxBase}autocompleter?q=${encodeURIComponent(typed)}`, { timeout: 3000 })
          .then((json) => S.parseAutocomplete(json, typed))
          .catch(() => [])
      : Promise.resolve([]);
    const replies = await Promise.all(queries.map((text) => histerSearch(text, 20).catch(() => null)));
    if (token !== suggestToken) return;
    const seen = new Set();
    const docs = [];
    for (const r of replies) {
      for (const d of [...((r && r.history) || []), ...((r && r.documents) || [])]) {
        if (!d || !d.url || seen.has(d.url) || !S.titleMatches(d.title, typed)) continue;
        seen.add(d.url);
        docs.push(d);
      }
    }
    const isNote = (d) => d.label === 'vault' || S.isNoteURL(d.url, niwaBase, konbiniBase);
    const notes = docs.filter(isNote).slice(0, 3);
    const pages = docs.filter((d) => !isNote(d)).slice(0, 4);
    let cards = [];
    if (notes.length) {
      try {
        cards = await konbiniCards();
      } catch (_) {}
    }
    const searches = await web;
    if (token !== suggestToken || $('q').value.trim() !== typed) return;
    await loadRules();
    drawSuggest({ labels: labelItems(typed), pages, notes, searches, cards });
  }

  function drawSuggest({ labels = [], pages, notes, searches, cards }) {
    const box = $('suggest');
    suggestItems = [];
    suggestActive = -1;
    $('q').removeAttribute('aria-activedescendant');
    const option = (content, pick, cls) => {
      const id = `sg-${suggestItems.length}`;
      const node = el('div', { class: `suggest-item ${cls}`, role: 'option', id, 'aria-selected': 'false' }, ...content);
      // mousedown, before the field's blur hides the list.
      node.addEventListener('mousedown', (e) => {
        e.preventDefault();
        pick();
      });
      suggestItems.push({ node, pick });
      return node;
    };
    const host = (url) => {
      try {
        return new URL(url).host;
      } catch (_) {
        return '';
      }
    };
    const sections = [];
    // Labels and collections first: with hundreds of labels, the quickest
    // way to one. Picking searches it (label:x, or the collection's @name).
    if (labels.length) {
      sections.push(el('p', { class: 'recent-head' }, 'Labels'));
      for (const item of labels) {
        const dot = el('span', { class: `suggest-icon dot ${item.kind}`, 'aria-hidden': 'true' });
        dot.style.setProperty('--chip', `var(--chip${S.labelChipIndex(item.query === `label:${item.name}` ? item.name : item.query)})`);
        sections.push(
          option(
            [dot, el('span', { class: 'suggest-title' }, item.name), el('span', { class: 'suggest-hint' }, item.kind)],
            () => {
              hideSuggest();
              $('q').value = item.query;
              $('search').requestSubmit();
            },
            'label',
          ),
        );
      }
    }
    if (pages.length) {
      sections.push(el('p', { class: 'recent-head' }, 'Your Pages'));
      for (const d of pages) {
        const icon = d.favicon_key
          ? el('img', { class: 'suggest-icon', src: `${histerBase}api/favicon?key=${encodeURIComponent(d.favicon_key)}`, alt: '' })
          : el('span', { class: 'suggest-icon globe', 'aria-hidden': 'true' });
        if (icon.tagName === 'IMG') icon.addEventListener('error', () => icon.replaceWith(el('span', { class: 'suggest-icon globe', 'aria-hidden': 'true' })));
        sections.push(
          option(
            [icon, el('span', { class: 'suggest-text' }, el('span', { class: 'suggest-title' }, d.title || d.url), el('span', { class: 'suggest-where' }, d.domain || host(d.url)))],
            () => (hideSuggest(), (location.href = d.url)),
            'page',
          ),
        );
      }
    }
    if (notes.length) {
      sections.push(el('p', { class: 'recent-head' }, 'Your Notes'));
      for (const d of notes) {
        const path = S.notePath(d.url, cards);
        const obsidian = S.obsidianURL(settings.obsidianVault, path);
        const niwa = S.niwaURL(niwaBase, path) || (/^niwa\./.test(host(d.url)) ? d.url : null);
        const place = [settings.obsidianVault || 'vault', ...(path ? path.replace(/\.md$/, '').split('/') : [])].join(' › ');
        sections.push(
          option(
            [el('span', { class: 'suggest-icon note', 'aria-hidden': 'true' }), el('span', { class: 'suggest-text' }, el('span', { class: 'suggest-title' }, d.title || path || d.url), el('span', { class: 'suggest-where' }, place))],
            () => (hideSuggest(), (location.href = obsidian || niwa || d.url)),
            'note',
          ),
        );
      }
    }
    if (searches.length) {
      sections.push(el('p', { class: 'recent-head' }, 'Suggestions'));
      for (const s of searches) {
        sections.push(
          option([el('span', { class: 'suggest-icon search', 'aria-hidden': 'true' }), el('span', { class: 'suggest-title' }, s)], () => {
            hideSuggest();
            $('q').value = s;
            $('search').requestSubmit();
          }, 'search'),
        );
      }
    }
    box.replaceChildren(...sections);
    box.hidden = !suggestItems.length || document.activeElement !== $('q');
    if (!box.hidden) $('recent').hidden = true;
  }

  function moveSuggest(step) {
    if (!suggestItems.length || $('suggest').hidden) return false;
    if (suggestActive >= 0) suggestItems[suggestActive].node.setAttribute('aria-selected', 'false');
    // Wraps through "none" (-1, the field itself) at either end.
    const n = suggestItems.length + 1;
    suggestActive = ((suggestActive + 1 + step + n) % n) - 1;
    if (suggestActive >= 0) {
      const { node } = suggestItems[suggestActive];
      node.setAttribute('aria-selected', 'true');
      node.scrollIntoView({ block: 'nearest' });
      $('q').setAttribute('aria-activedescendant', node.id);
    } else {
      $('q').removeAttribute('aria-activedescendant');
    }
    return true;
  }
  // --- The preview pane --------------------------------------------------------
  // In a wide window (and Settings → Preview Pane on), one of your pages or
  // notes previews beside the results, as on Hister's own page: a click on
  // its card (not its title) or its "preview" link. Hister's readable HTML
  // goes in a sandboxed frame: no scripts, no same-origin, links open in a
  // new tab. The pane is there only while it shows something: otherwise the
  // results have the whole width, as on any search page (it sat empty
  // beside them), and × closes it.
  const previewPane = (() => {
    const wide = matchMedia('(min-width: 1100px)');
    let current = null;
    const on = () => settings.previewPane !== false && wide.matches;
    function update() {
      const shown = on() && current !== null;
      document.body.classList.toggle('with-preview', shown);
      $('preview-pane').hidden = !shown;
      placeSide(); // the right column goes while the pane shows
    }
    wide.addEventListener('change', update);
    function escapeHTML(t) {
      return String(t).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
    }
    function pageCSS() {
      const css = getComputedStyle(document.documentElement);
      const v = (name) => css.getPropertyValue(name).trim();
      return `:root{color-scheme:light dark}
        body{margin:0;padding:18px 22px 40px;font:-apple-system-body;line-height:1.55;color:${v('--text')};background:${v('--bg')};overflow-wrap:anywhere}
        h1{font:-apple-system-title2;font-weight:700;margin:0 0 .3em}
        .meta{color:${v('--secondary')};font:-apple-system-footnote;margin:0 0 1.2em;padding-bottom:.8em;border-bottom:1px solid ${v('--line')}}
        a{color:${v('--accent')}} img{max-width:100%;height:auto;border-radius:6px}
        svg,video,picture,figure,canvas,iframe,object,embed{max-width:100%;height:auto} figure{margin:1em 0}
        pre,code{white-space:pre-wrap} table{border-collapse:collapse;max-width:100%}`;
    }
    async function show(url, card) {
      if (current === url) return;
      current = url;
      summaries.leavePane(url);
      update();
      // Previewing a page is opening it.
      if (card) recordOpened(url, card.querySelector('.title')?.textContent || '');
      document.querySelectorAll('.card.previewing').forEach((c) => c.classList.remove('previewing'));
      if (card) card.classList.add('previewing');
      $('preview-open').href = url;
      $('preview-open').hidden = false;
      $('preview-empty').hidden = true;
      const frame = $('preview-frame');
      frame.hidden = false;
      frame.srcdoc = `<!doctype html><meta charset="utf-8"><body style="background:transparent"></body>`;
      try {
        // A work vault's note: Kura's sanitized HTML (Hister never has it).
        const other = S.noteVault(url);
        const p = other
          ? { title: card?.querySelector('.title')?.textContent || url, content: ((await fetchJSON(`${kuraBase}api/note?${new URLSearchParams({ path: S.notePath(url, []) || '', vault: other })}`, { timeout: 10000, room: true })) || {}).html }
          : await fetchJSON(`${histerBase}api/preview?url=${encodeURIComponent(url)}`, { timeout: 10000, headers: histerAuth() });
        if (current !== url) return;
        let host = url;
        try {
          host = new URL(url).host;
        } catch (_) {}
        const added = Number(p.added) ? S.shortDate(new Date(Number(p.added) * 1000).toISOString()) : '';
        frame.srcdoc =
          `<!doctype html><html><head><meta charset="utf-8">` +
          // No referrer: a page's images never learn which page is previewed;
          // Images in Previews off: they don't load at all.
          `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src ${settings.previewImages === false ? 'data:' : '* data:'}; style-src 'unsafe-inline'">` +
          `<meta name="referrer" content="no-referrer">` +
          `<base target="_blank"><style>${pageCSS()}</style></head><body>` +
          `<h1>${escapeHTML(p.title || url)}</h1><p class="meta">${escapeHTML(host)}${added ? ' · Added ' + escapeHTML(added) : ''}</p>` +
          `${p.content || ''}</body></html>`;
      } catch (_) {
        if (current !== url) return;
        frame.srcdoc = `<!doctype html><meta charset="utf-8"><style>${pageCSS()}</style><p class="meta">Hister couldn't show a preview of this page.</p>`;
      }
    }
    function clear() {
      current = null;
      summaries.leavePane(null);
      document.querySelectorAll('.card.previewing').forEach((c) => c.classList.remove('previewing'));
      $('preview-frame').hidden = true;
      $('preview-open').hidden = true;
      $('preview-empty').hidden = false;
      update();
    }
    // Escape closes it too: the keyboard block below (vi keys) handles it.
    document.addEventListener(
      'click',
      (event) => {
        if (!on() || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) return;
        const card = event.target.closest('.card[data-preview]');
        if (!card || event.target.closest('.summarize-link')) return;
        const a = event.target.closest('a[href]');
        if (a && !a.classList.contains('preview-link')) return; // titles and other links go where they go
        event.preventDefault();
        event.stopPropagation();
        show(card.dataset.preview, card);
      },
      true,
    );
    $('preview-close').addEventListener('click', clear);
    update();
    return { update, clear, show, on, isOpen: () => current !== null };
  })();

  // --- Summarize (docs/ai.md) ------------------------------------
  // The AI endpoint, on this page's own host: only the hosted
  // page has one (web/shim.js sets aiURL, when built with SHIORI_AI=1), so
  // the extension page never offers it, nor a build without it. Web pages only, never notes (the server refuses them too).
  // The summary goes above the preview in the pane, or under its card
  // without one, as the apps' card sits above theirs: Copy, Regenerate, ×.
  /** The AI endpoint's status, once per page: null when there's none (or it's down). */
  const aiStatus = aiBase ? fetchJSON(`${aiBase}status`, { timeout: 4000 }).catch(() => null) : Promise.resolve(null);

  /** POST to the AI endpoint; the reply, or throws `{message}` in the page's words. */
  async function aiPost(path, body, isReply) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 90_000);
    let r;
    try {
      r = await fetch(`${aiBase}${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify(body),
        credentials: 'same-origin',
        signal: controller.signal,
      });
    } catch (_) {
      throw { message: S.summaryError(0, '', '') };
    } finally {
      clearTimeout(timer);
    }
    let reply = null;
    try {
      reply = await r.json();
    } catch (_) {}
    if (!r.ok || !reply || !isReply(reply)) throw { message: S.summaryError(r.status, reply && reply.error, reply && reply.message) };
    return reply;
  }

  const summaries = (() => {
    const done = new Map();
    aiStatus.then((s) => document.body.classList.toggle('ai-on', !!(s && s.enabled)));
    const request = (url, refresh) => aiPost('summarize', { url, refresh: !!refresh }, (b) => typeof b.summary === 'string');
    function render(box, url, state) {
      const button = (text, label, onclick) => {
        const b = el('button', { type: 'button', class: 'summary-button', 'aria-label': label, title: label }, text);
        b.addEventListener('click', onclick);
        return b;
      };
      const head = el(
        'div',
        { class: 'summary-head' },
        el('span', { class: 'summary-title' }, '✦ Summary'),
        state.reply ? button('Copy', 'Copy the summary', () => navigator.clipboard.writeText(state.reply.summary).catch(() => {})) : null,
        state.reply ? button('Regenerate', 'Summarize again', () => run(box, url, true)) : null,
        button('×', 'Hide the summary', () => close(box)),
      );
      let body;
      if (state.working) {
        body = el('p', { class: 'summary-working' }, el('span', { class: 'summary-spinner', 'aria-hidden': 'true' }), 'Summarizing…');
      } else if (state.reply) {
        const parts = S.summaryParts(state.reply.summary);
        body = el(
          'div',
          {},
          parts.opening ? el('p', {}, parts.opening) : null,
          parts.points.length ? el('ul', {}, ...parts.points.map((p) => el('li', {}, p))) : null,
          el('p', { class: 'summary-byline' }, S.summaryByline(state.reply)),
        );
      } else {
        body = el('div', {}, el('p', {}, state.error), button('Try Again', 'Summarize again', () => run(box, url, false)));
      }
      box.replaceChildren(head, body);
    }
    async function run(box, url, refresh) {
      if (!refresh && done.has(url)) return render(box, url, { reply: done.get(url) });
      render(box, url, { working: true });
      try {
        const reply = await request(url, refresh);
        done.set(url, reply);
        if (box.dataset.url === url) render(box, url, { reply });
      } catch (error) {
        if (box.dataset.url === url) render(box, url, { error: error.message });
      }
    }
    function close(box) {
      if (box.id === 'preview-summary') {
        box.hidden = true;
        box.replaceChildren();
        delete box.dataset.url;
      } else {
        box.closest('.summary-item')?.remove();
      }
    }
    function summarize(card) {
      const url = card.dataset.preview;
      let box;
      if (previewPane.on()) {
        previewPane.show(url, card);
        box = $('preview-summary');
        box.hidden = false;
      } else {
        // Under its card; a second tap closes it.
        const next = card.nextElementSibling;
        if (next && next.classList.contains('summary-item')) return next.remove();
        box = el('section', { class: 'summary', 'aria-live': 'polite' });
        card.after(el('li', { class: 'summary-item' }, box));
      }
      box.dataset.url = url;
      run(box, url, false);
    }
    document.addEventListener('click', (event) => {
      const link = event.target.closest('.summarize-link');
      if (!link) return;
      event.preventDefault();
      const card = link.closest('.card[data-preview]');
      if (card) summarize(card);
    });
    return {
      /** The pane moved to another page (or closed): its summary goes. */
      leavePane(url) {
        const box = $('preview-summary');
        if (box && box.dataset.url !== url) close(box);
      },
    };
  })();

  // --- vi keys (the apps and the web app have the same set) ----------------------
  // j/k move through the results, h/l through the tabs, Enter/o opens, p
  // previews, gg/G top and bottom, / the search field, Esc backs out, y
  // copies the link, ? lists them. Never while typing in a field, a dialog
  // is open, or Meta/Ctrl/Alt is held (S.vimKey decides).
  const keyboard = (() => {
    let state = {};
    let current = null;
    let help = null;
    const inField = (t) => !!t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName));
    const cards = () =>
      [...document.querySelectorAll('main .card')].filter((c) => c.offsetParent !== null && !c.closest('#skeleton'));
    function mark(card) {
      if (current) current.classList.remove('kbd-current');
      current = card || null;
      if (!current) return;
      current.classList.add('kbd-current');
      current.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }
    function move(step) {
      const list = cards();
      if (!list.length) return;
      const at = list.indexOf(current);
      if (at < 0) return mark(step > 0 ? list[0] : list[list.length - 1]);
      mark(list[Math.max(0, Math.min(list.length - 1, at + step))]);
    }
    function tab(step) {
      const tabs = [...document.querySelectorAll('#categories a')];
      const at = tabs.findIndex((a) => a.getAttribute('aria-current') === 'page');
      const next = tabs[at + step];
      if (at >= 0 && next) location.href = next.href;
    }
    const urlOf = (card) => card.dataset.preview || card.querySelector('a.title')?.href || '';
    function open(card) {
      const title = card && card.querySelector('a.title');
      if (title) title.click();
    }
    function preview(card) {
      if (card.dataset.preview && previewPane.on()) previewPane.show(card.dataset.preview, card);
      else open(card);
    }
    function toast(text) {
      const t = el('div', { class: 'kbd-toast', role: 'status' }, text);
      document.body.append(t);
      setTimeout(() => t.remove(), 2000);
    }
    async function copy(card) {
      const url = urlOf(card);
      if (!url) return;
      try {
        await navigator.clipboard.writeText(url);
        toast('Link copied');
      } catch (_) {
        toast("Couldn't copy the link");
      }
    }
    const KEYS = [
      ['j / k', 'Next / previous result'], ['h / l', 'Previous / next tab'], ['Enter, o', 'Open the result'],
      ['p', 'Preview it'], ['gg / G', 'First / last result'], ['/', 'Search'], ['Esc', 'Leave the field, close the preview'],
      ['y', 'Copy the link'], ['?', 'These keys'],
    ];
    function toggleHelp() {
      if (help) {
        help.remove();
        help = null;
        return;
      }
      help = el(
        'div',
        { class: 'kbd-help', role: 'dialog', 'aria-modal': 'false', 'aria-label': 'Keyboard shortcuts' },
        el('h2', {}, 'Keyboard'),
        el('dl', {}, ...KEYS.flatMap(([k, what]) => [el('dt', {}, el('kbd', {}, k)), el('dd', {}, what)])),
      );
      document.body.append(help);
    }
    document.addEventListener('keydown', (event) => {
      if (event.defaultPrevented) return;
      if (document.querySelector('dialog[open]')) return;
      const typing = inField(event.target);
      const r = S.vimKey(state, {
        key: event.key, shiftKey: event.shiftKey, metaKey: event.metaKey, ctrlKey: event.ctrlKey,
        altKey: event.altKey, inField: typing, now: Date.now(),
      });
      state = r.state;
      if (!r.action) return;
      // Enter on a focused link or button is that link's or button's.
      if (event.key === 'Enter' && event.target.closest && event.target.closest('a[href], button, summary')) return;
      const card = current && current.isConnected ? current : null;
      switch (r.action) {
        case 'next': move(1); break;
        case 'prev': move(-1); break;
        case 'tabPrev': tab(-1); break;
        case 'tabNext': tab(1); break;
        case 'top': { const l = cards(); if (l.length) mark(l[0]); break; }
        case 'bottom': { const l = cards(); if (l.length) mark(l[l.length - 1]); break; }
        case 'open': if (!card) return; open(card); break;
        case 'preview': if (!card) return; preview(card); break;
        case 'copy': if (!card) return; copy(card); break;
        case 'focusSearch': $('q').focus(); $('q').select(); break;
        case 'help': toggleHelp(); break;
        case 'escape':
          if (help) toggleHelp();
          else if (typing) event.target.blur();
          else if (previewPane.isOpen()) previewPane.clear();
          else mark(null);
          break;
        default: return; // 'label', 'delete': not on this page
      }
      event.preventDefault();
    });
    return { mark };
  })();

  // The comparison's leftover choice (the wide layout won).
  try {
    localStorage.removeItem('shioriLayout');
  } catch (_) {}

  // Keeps the side Info card level with the first result (alignInfo, below).
  // Its sections too: a late change inside them (the web font arriving)
  // moves the first result without changing main's size.
  const aligner = new ResizeObserver(() => alignInfo());
  for (const el of [document.querySelector('main'), $('hister'), $('vault'), $('web'), $('infobox-slot')]) aligner.observe(el);
  document.fonts?.ready.then(() => alignInfo());
  addEventListener('resize', () => alignInfo());

  // --- Settings (the gear): the app's options for this page ---------------------
  // Changes go to the app's App Group through the background, so the app
  // and this page share one set. Theme and text size apply at once; the
  // rest redraw the page when the sheet closes.
  const choices = (values, label = String) => values.map((v) => [v, label(v)]);
  // The same choices as the app's (on a Mac, Standard stands for Large).
  const TEXT_SIZE_CHOICES = [
    ['system', IS_MAC ? 'Standard' : 'System'],
    ['xSmall', 'Extra Small'],
    ['small', 'Small'],
    ['medium', 'Medium'],
    ...(IS_MAC ? [] : [['large', 'Large']]),
    ['xLarge', 'Extra Large'],
    ['xxLarge', 'Extra Extra Large'],
    ['xxxLarge', 'Largest'],
  ];
  const SETTINGS_ROWS = [
    ['Appearance', [
      { key: 'palette', label: 'Theme', options: Object.entries(S.PALETTES).map(([key, p]) => [key, p.name]) },
      { key: 'theme', label: 'Appearance', options: [['system', 'System'], ['day', 'Light'], ['night', 'Dark']] },
      { key: 'textSize', label: 'Text Size', options: TEXT_SIZE_CHOICES },
      { key: 'previewPane', label: 'Preview Pane' },
      { key: 'previewImages', label: 'Images in Previews' },
    ]],
    ['Results', [
      { key: 'rememberOpened', label: 'Remember What You Open' },
      { key: 'showOpened', label: 'Show Opened' },
      { key: 'resultStyle', label: 'Result Style', options: [['tint', 'Tint'], ['solid', 'Solid'], ['bar', 'Left Bar'], ['none', 'None']] },
      { key: 'webResults', label: 'Web Results' },
      { key: 'showInfobox', label: 'Info Box', needs: 'webResults' },
      { key: 'showRelated', label: 'Related Searches', needs: 'webResults' },
      { key: 'aiAnswer', label: 'AI Answer', needs: 'webResults' },
      { key: 'showThumbnails', label: 'Thumbnails', needs: 'webResults' },
    ]],
    // Their order, and which show (S.pillEditor).
    ['Pills', [{ action: 'pills' }]],
    ['Small Web', [
      { key: 'smallWebTab', label: 'Small Web Tab' },
      { key: 'smallWebOpen', label: 'Open Results', options: [['gateway', 'Through the Gateway'], ['direct', 'In a Gemini App']], needs: 'smallWebTab' },
    ]],
    ['Your Pages', [
      { key: 'histerInGeneral', label: 'In All' },
      { key: 'histerTab', label: 'Pages Tab' },
    ]],
    ['Your Notes', [
      { key: 'vaultInGeneral', label: 'In All' },
      { key: 'vaultTab', label: 'Notes Tab' },
    ]],
    ['Search History', [
      { key: 'searchHistory', label: 'Recent Searches' },
      { key: 'labelSuggestions', label: 'Labels in Suggestions' },
      { action: 'clear-recent', label: 'Clear Recent Searches' },
    ]],
  ];
  const LOOK_KEYS = ['theme', 'palette', 'textSize', 'previewPane'];
  // What a choice shows while it was never set.
  const CHOICE_DEFAULTS = { theme: 'system', palette: 'tokyo-night' };
  const saving = [];
  let redraw = false;

  function drawSettings() {
    const body = [];
    for (const [title, rows] of SETTINGS_ROWS) {
      body.push(el('h3', { class: 'group-title' }, title));
      const group = el('div', { class: 'group' });
      for (const row of rows) {
        const off = row.needs && !settings[row.needs];
        const id = `setting-${row.key || row.action}`;
        let control;
        if (row.action === 'pills') {
          const items = S.PILLS.filter(([key]) => key !== 'opened' && (key !== 'files' || hasFiles));
          group.append(
            S.pillEditor(items, settings.pills, (next, control) => {
              change({ pills: next });
              // The sheet was redrawn: the keyboard stays on what was used.
              const again = [...$('settings-body').querySelectorAll('.pill-editor [aria-label]')].find((n) => n.getAttribute('aria-label') === control);
              (again && !again.disabled ? again : $('settings-body').querySelector('.pill-editor .switch'))?.focus();
            }),
          );
          continue;
        }
        if (row.action === 'clear-recent') {
          control = el('button', { type: 'button', class: 'link', id, disabled: !recent.length || !settings.searchHistory }, row.label);
          control.addEventListener('click', () => {
            recent = [];
            change({ clearRecentSearches: true });
          });
          group.append(el('div', { class: 'setting' }, control));
          continue;
        }
        if (row.options) {
          control = el('select', { id, disabled: off });
          for (const [value, text] of row.options) {
            const option = el('option', { value: String(value) }, text);
            if (String(settings[row.key] ?? CHOICE_DEFAULTS[row.key] ?? '') === String(value)) option.selected = true;
            control.append(option);
          }
          control.addEventListener('change', () => {
            const raw = control.value;
            change({ [row.key]: typeof row.options[0][0] === 'number' ? Number(raw) : raw });
          });
        } else {
          control = el('input', { id, type: 'checkbox', role: 'switch', class: 'switch', disabled: off });
          control.checked = !!settings[row.key];
          control.addEventListener('change', () => change({ [row.key]: control.checked }));
        }
        group.append(el('div', { class: 'setting' + (off ? ' disabled' : '') }, el('label', { for: id }, row.label), control));
      }
      body.push(group);
    }
    // The source, as AGPL-3.0 section 13 asks of a page served over the
    // network: only when the build names it (SHIORI_SOURCE_URL).
    const source = S.sourceLink(S.fromBuild('__SHIORI_SOURCE_URL__'));
    if (source) {
      body.push(el('h3', { class: 'group-title' }, 'About'));
      body.push(
        el('div', { class: 'group' },
          el('div', { class: 'setting' }, el('span', {}, 'Source'), el('a', { href: source, target: '_blank', rel: 'noopener noreferrer' }, 'View the source')),
          el('div', { class: 'setting' }, el('span', {}, 'Licence'), el('span', {}, S.LICENCE))),
      );
    }
    $('settings-body').replaceChildren(...body);
  }

  function change(values) {
    Object.assign(settings, values);
    if (values.searchHistory === false) recent = [];
    if (Object.keys(values).some((k) => !LOOK_KEYS.includes(k) && k !== 'clearRecentSearches')) redraw = true;
    if (Object.keys(values).some((k) => LOOK_KEYS.includes(k))) {
      applyLook(settings.theme, settings.textSize, settings.palette);
      previewPane.update();
      try {
        const copy = JSON.parse(localStorage.getItem(HEADER_KEY) || 'null');
        if (copy) localStorage.setItem(HEADER_KEY, JSON.stringify({ ...copy, theme: settings.theme || '', palette: settings.palette || '', textSize: settings.textSize }));
      } catch (_) {}
    }
    saving.push(
      new Promise((resolve) =>
        chrome.runtime.sendMessage({ shiori: 'set-settings', values }, () => {
          void chrome.runtime.lastError;
          resolve();
        }),
      ),
    );
    drawSettings();
  }

  // The Machiya rooms: a switcher beside the gear, with
  // the addresses the build stamped in (scripts/rooms-stamp.py).
  // Rooms switched off in the house's settings (machiya_show_*) stay out.
  const hiddenRooms = S.houseSettings(document.cookie).hidden;
  // Its last row is the page's own Settings, as the rooms end theirs.
  // Shiori is this page ("here") where it's served over http(s): the
  // hosted page; Safari's own page has no such address and leaves it out.
  const switcher = S.roomsSwitcher(S.rooms('__SHIORI_ROOMS__', /^https?:$/.test(location.protocol) ? location.origin : '').filter((r) => r.key === 'shiori' || !hiddenRooms.includes(r.key)), 'shiori', {
    settings: { href: '#settings', open: () => $('settings-open').click() },
  });
  if (switcher) $('settings-open').before(switcher);

  $('settings-open').addEventListener('click', () => {
    drawSettings();
    $('recent').hidden = true;
    $('settings').showModal();
  });
  $('settings').addEventListener('close', async () => {
    await Promise.all(saving);
    if (redraw) location.replace(location.href);
  });
  // A tap on the dimmed backdrop closes the sheet too.
  $('settings').addEventListener('click', (event) => {
    if (event.target === $('settings')) $('settings').close();
  });

  selectOnFocus($('q'));
  $('q').addEventListener('focus', () => {
    drawRecent();
    if ($('q').value.trim() && $('q').value.trim() !== q) scheduleSuggest();
  });
  $('q').addEventListener('input', () => {
    drawRecent();
    scheduleSuggest();
  });
  // Leaving the field hides the lists, but not before a tap on them lands.
  $('q').addEventListener('blur', () =>
    setTimeout(() => {
      $('recent').hidden = true;
      hideSuggest();
    }, 150),
  );
  $('q').addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      // A list open: Escape closes it (and only that; the next one leaves the field).
      if (!$('recent').hidden || !$('suggest').hidden) event.preventDefault();
      $('recent').hidden = true;
      hideSuggest();
    } else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      if (moveSuggest(event.key === 'ArrowDown' ? 1 : -1)) event.preventDefault();
    } else if (event.key === 'Enter' && suggestActive >= 0 && suggestItems[suggestActive]) {
      event.preventDefault();
      suggestItems[suggestActive].pick();
    }
  });
  $('time').addEventListener('change', () => (location.href = link({ t: $('time').value, p: 1 })));
  $('sort').addEventListener('change', () => (location.href = link({ hs: $('sort').value, p: 1 })));
  if (!q) {
    // The start page: centred, the recent searches as chips (not the list
    // under the field, which would say the same twice).
    document.body.classList.add('home');
    $('home-brand').hidden = false;
    const chips = settings.searchHistory === false ? [] : recent.slice(0, 5);
    $('home-recent').replaceChildren(
      ...chips.map((s) => el('a', { href: link({ q: s, cat: 'general', p: 1 }), class: 'home-chip' }, s)),
    );
    $('home-recent').hidden = !chips.length;
    reveal();
    $('q').focus();
    return;
  }

  /** Theme, tabs and filters: from the copy before the first paint, then from settings. */
  // The header's height, for the section headings that stick under it
  // (search.css, --header-h).
  {
    const header = document.querySelector('header');
    const keep = () => document.documentElement.style.setProperty('--header-h', `${header ? header.offsetHeight : 0}px`);
    if (header && window.ResizeObserver) new ResizeObserver(keep).observe(header);
    keep();
  }

  function drawHeader({ theme, palette, categories, webResults, textSize }) {
    applyLook(theme, textSize, palette);
    const current = categories.some(([c]) => c === params.get('cat')) ? params.get('cat') : 'general';
    $('categories').replaceChildren(
      ...categories.map(([cat, name]) => {
        const a = el('a', { href: link({ cat, p: 1 }), 'data-cat': cat }, name);
        if (cat === current) a.setAttribute('aria-current', 'page');
        if (pillCounts[cat]) a.append(el('span', { class: 'pill-count' }, pillCounts[cat]));
        return a;
      }),
    );
    fadeEdges($('categories'), true);
    $('time').value = time;
    // The Hister and Vault tabs sort instead of filtering by time.
    $('time-label').hidden = isNoteTab(current) || !webResults;
    $('sort-label').hidden = !isNoteTab(current);
    $('sort').value = histerSort;
  }

  /**
   * A sideways-scrolling row fades out at an end with more to scroll to
   * (`data-fade`, drawn by search.css), kept current as it scrolls or
   * resizes. `reveal` brings the chosen pill into view first, so a tab past
   * the edge (Small Web on a phone) isn't hidden when it's the one showing.
   */
  function fadeEdges(row, reveal = false) {
    if (reveal) {
      const chosen = row.querySelector('[aria-current="page"]');
      if (chosen) {
        const box = row.getBoundingClientRect();
        const pill = chosen.getBoundingClientRect();
        if (pill.right > box.right || pill.left < box.left) row.scrollLeft += pill.left - box.left - 24;
      }
    }
    if (!row.shioriFade) {
      row.shioriFade = () => {
        const fade = S.edgeFade(row);
        if (fade) row.dataset.fade = fade;
        else delete row.dataset.fade;
      };
      row.addEventListener('scroll', row.shioriFade, { passive: true });
      if (window.ResizeObserver) new ResizeObserver(row.shioriFade).observe(row);
    }
    row.shioriFade();
  }

  /** Appearance, theme and text size: the page's look, applied at once. */
  function applyLook(theme, textSize, palette) {
    if (theme === 'day' || theme === 'night') document.documentElement.dataset.theme = theme;
    else delete document.documentElement.dataset.theme;
    // The rooms' themes (palettes.css); Tokyo Night is search.css's own.
    if (Object.hasOwn(S.PALETTES, palette) && palette !== 'tokyo-night') document.documentElement.dataset.palette = palette;
    else delete document.documentElement.dataset.palette;
    const zoom = pageZoom(textSize);
    document.body.style.zoom = Math.abs(zoom - 1) < 0.01 ? '' : String(zoom);
  }

  function pageZoom(textSize) {
    const chosen = TEXT_SCALES[textSize];
    if (IS_MAC) return MAC_BASE * (chosen ? chosen / 17 : 1);
    if (!chosen) return 1; // System: the page's fonts already follow Dynamic Type
    // Relative to the system's size, which the page's fonts already use.
    const body = parseFloat(getComputedStyle(document.body).fontSize) || 17;
    return chosen / body;
  }

  /** The results are drawn: the footer (held back so it doesn't sit under the header meanwhile) can show. */
  function reveal() {
    document.body.classList.remove('pending');
  }

  // --- helpers -------------------------------------------------------------------

  function withSlash(u) {
    u = (u || '').trim();
    return u && !u.endsWith('/') ? u + '/' : u;
  }

  function el(tag, attrs = {}, ...children) {
    const node = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
      if (v == null || v === false) continue;
      if (k === 'class') node.className = v;
      else node.setAttribute(k, v === true ? '' : v);
    }
    for (const child of children) if (child != null && child !== '') node.append(child);
    return node;
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

  // `room`: Kura or Konbini, which may want the Machiya sign-in (roomInit).
  async function fetchJSON(url, { timeout = 8000, headers = {}, room = false } = {}) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout);
    try {
      // The hosted page's own host carries its sign-in (the cookie its
      // nginx asks the helper about); anywhere else, no cookies.
      const init = { headers, signal: controller.signal, credentials: sameOrigin(url) ? 'same-origin' : 'omit' };
      const r = await fetch(url, room ? await roomInit(url, init) : init);
      if (!r.ok) {
        refused(r.status, url);
        throw Object.assign(new Error(`HTTP ${r.status}`), { status: r.status });
      }
      // Hister can leave raw control characters in text; blank them.
      return JSON.parse((await r.text()).replace(/[\u0000-\u001f]/g, ' '));
    } finally {
      clearTimeout(timer);
    }
  }

  // Signing in (docs/signing-in.md), on the hosted page only: its nginx
  // asks the sign-in helper about every Hister call, so a 401 or 403 from
  // Hister's routes (not the rooms', which say so themselves) goes to the
  // helper's sign-in and back here, at most once in 30 s; a 500 says
  // sign-in is unavailable, in the status line. Inert while Hister has no
  // users. The extension's page has the token instead.
  // (A declaration, hoisted, with no outer state: fetchJSON may call it
  // before this line runs.)
  function refused(status, url) {
    if (!sameOrigin(url) || !histerBase || !sameOrigin(histerBase)) return;
    let path = '';
    try {
      path = new URL(url, location.href).pathname;
    } catch (_) {}
    if (/^\/(kura|konbini|searx|smallweb)\//.test(path)) return;
    const asked = S.signInAsked(status);
    if (asked === 'signin') {
      const where = S.histerSignInURL('__SHIORI_ROOMS__', location.origin, location.href);
      if (!where) return;
      try {
        localStorage.setItem('shioriSignInSeen', '1');
      } catch (_) {}
      let storage = { getItem: () => null, setItem() {} };
      try {
        storage = sessionStorage;
      } catch (_) {}
      if (S.signInDue(storage)) location.assign(where);
    } else if (asked === 'unavailable' && !refused.said) {
      let seen = false;
      try {
        seen = localStorage.getItem('shioriSignInSeen') === '1';
      } catch (_) {}
      if (!seen) return;
      refused.said = true;
      showStatus("Sign-in is unavailable right now: Hister or its sign-in helper isn't answering.");
    }
  }

  function histerSearch(text, limit, extra = {}) {
    // The last word a prefix, never the notes (those are Kura's).
    const query = JSON.stringify({ text: S.histerText(text), limit, ...extra });
    return fetchJSON(`${histerBase}search?format=json&query=${encodeURIComponent(query)}`, {
      headers: histerAuth({ Accept: 'application/json' }),
    });
  }

  /**
   * Hister's results for `text` (wrapped, e.g. for the vault), or, when a
   * first page found nothing at all, for a respelling taken from the web's
   * related searches (`suggest`, a promise of SearXNG's suggestions):
   * Hister matches words exactly, so "rasbperry pi" found nothing while
   * the web did. Hister has no fuzzy search (`word~2` finds the word "2").
   * "Nothing" counts `history` too: with a small limit, the pages you
   * opened before can fill it, leaving `documents` empty ("hister", limit
   * 3: 13 found, no documents). `closeMatches` is the spelling used.
   */
  async function histerOrClose(text, limit, extra = {}, wrap = (t) => t, suggest = null) {
    const result = await histerSearch(wrap(text), limit, extra);
    const found = (r) => r.total || (r.documents || []).length || (r.history || []).length;
    if (found(result) || extra.page_key || !suggest) return result;
    const close = S.correctedQuery(text, await suggest().catch(() => []));
    if (!close) return result;
    const again = await histerSearch(wrap(close), limit, extra);
    return found(again) ? { ...again, closeMatches: close } : result;
  }

  /** SearXNG's related searches for `text`, for a respelling; [] without it. */
  async function webSuggestions(text) {
    if (!searxBase || !settings.webResults) return [];
    const url = new URL(`${searxBase}search`);
    url.search = new URLSearchParams({ q: text, format: 'json' }).toString();
    const data = await fetchJSON(url.href, { timeout: WEB_TIMEOUT_MS });
    return data.suggestions || [];
  }

  function isHTTP(u) {
    return typeof u === 'string' && /^https?:\/\//i.test(u);
  }

  function chip(text, kind) {
    return el('span', { class: `chip ${kind}` }, text);
  }

  /**
   * Where a label's tag goes: its pages, in this tab unless the tab is
   * Images, Videos or News (a label has none of those), then All.
   */
  function labelHref(label) {
    const cat = ['web', 'images', 'videos', 'news'].includes(category) ? 'general' : category;
    return link({ q: `label:${label}`, cat, p: 1, hk: '' });
  }

  /** A label in its own colour (the app's), linking to its pages. */
  function labelChip(label, href = labelHref(label)) {
    const node = href
      ? el('a', { class: 'chip label link-chip', href, title: `Pages labelled ${label}` }, label)
      : el('span', { class: 'chip label' }, label);
    // Through the CSSOM: the extension's CSP may refuse a style attribute.
    node.style.setProperty('--chip', `var(--chip${S.labelChipIndex(label)})`);
    return node;
  }

  // --- Remember What You Open ----------------------------------------------------
  // Hister ranks a result first for a query once you've opened it from that
  // query (its search replies carry them as `history`). Opening a Hister or
  // vault result tells it; the app does the same.

  function recordOpened(url, title) {
    // Gemini and Gopher too: Hister keeps a small-web page's canonical address.
    // Never a private vault's note to Hister, nor a file (it stays here).
    if (settings.rememberOpened === false || !histerBase || !q || !/^(https?|gemini|gopher):\/\//i.test(url) || S.isPrivateNote(url) || S.isLocalFile(url)) return;
    const query = S.histerText(q);
    const send = () =>
      fetch(`${histerBase}api/history`, {
        method: 'POST',
        headers: histerAuth({ 'Content-Type': 'application/json' }),
        // As the search was sent: Hister matches the exact text.
        body: JSON.stringify({ url, title, query }),
        credentials: sameOrigin(histerBase) ? 'same-origin' : 'omit',
        // The page is being left: let the request finish anyway.
        keepalive: true,
      }).catch(() => {});
    // A shared vault's note: Kura is asked again first (it may be private
    // by now). If the page is gone before it answers, nothing is sent.
    if (S.noteVault(url) === null) return void send();
    void S.isPrivateNoteNow(url, readVaultsNow).then((isPrivate) => (isPrivate ? undefined : send()));
  }

  document.addEventListener('click', (event) => {
    const link = event.target.closest('.hister-card a.title, .vault-card a.title, .vault-card .meta a:not(.preview-link)');
    if (!link) return;
    const card = link.closest('.card');
    recordOpened(card?.dataset.preview || link.href, card?.querySelector('.title')?.textContent || '');
  });

  /**
   * Results you opened before, first; the rest without them. `skipNotes`:
   * Your Pages on All, which leaves notes to Your Notes (`history` has no
   * label, so a note is known by its Niwa or Konbini address).
   */
  function withOpened(result, docs, { skipNotes = false } = {}) {
    const opened = settings.rememberOpened === false || settings.showOpened !== true
      ? []
      : (result.history || []).filter((h) => isHTTP(h.url) && !(skipNotes && S.isNoteURL(h.url, niwaBase, konbiniBase)));
    const urls = new Set(opened.map((h) => h.url));
    const cards = opened.map((h) => {
      const card = histerCard({ url: h.url, title: h.title, updated: h.updated, added: h.added });
      card.classList.add('opened-card');
      card.querySelector('.meta')?.prepend(chip('you opened', 'hister'));
      return card;
    });
    return { cards, docs: docs.filter((d) => !urls.has(d.url)) };
  }

  /** A collapsible section: the head toggles the body; the state is remembered. */
  // Sections start collapsed, and each one
  // stays as it was last left, on this device, for every later search: an
  // Info left open opens again. Not the AI answer: it always starts shut,
  // since open would ask the AI on every search (only on request). A page
  // reopened by Back keeps its own folds first.
  const remembered = stored[FOLDS_KEY] || {};
  function fold(section, openByDefault = false) {
    const head = section.querySelector('.fold-head');
    const name = section.dataset.fold;
    const keeps = name !== 'answer';
    const open = name in pageState.folds ? pageState.folds[name] : keeps && name in remembered ? remembered[name] : openByDefault;
    head.setAttribute('aria-expanded', String(open));
    head.addEventListener('click', () => {
      const next = head.getAttribute('aria-expanded') !== 'true';
      head.setAttribute('aria-expanded', String(next));
      pageState.folds[name] = next;
      saveState();
      if (keeps) {
        remembered[name] = next;
        chrome.storage.local.set({ [FOLDS_KEY]: remembered });
      }
    });
  }

  /** SearXNG's URL line: origin › crumb › crumb, with an optional favicon. */
  function urlLine(url, favicon) {
    const { origin, crumbs } = S.breadcrumb(url);
    return el(
      'div',
      { class: 'url' },
      favicon ? el('img', { src: favicon, alt: '', loading: 'lazy' }) : null,
      el('span', { class: 'origin' }, origin),
      crumbs.length ? el('span', { class: 'crumbs' }, ' › ' + crumbs.join(' › ')) : null,
    );
  }

  /** Plain text with the query's words in bold. */
  function boldSnippet(text) {
    if (!text) return null;
    const p = el('p', { class: 'snippet' });
    for (const run of S.splitHighlights(text, terms)) p.append(run.hit ? el('b', {}, run.text) : run.text);
    return p;
  }

  /** Hister's snippet HTML as text and <mark>s only; nothing else survives. */
  function markedSnippet(html) {
    const doc = new DOMParser().parseFromString(`<body>${html || ''}</body>`, 'text/html');
    const p = el('p', { class: 'snippet' });
    (function walk(node) {
      for (const child of node.childNodes) {
        if (child.nodeType === Node.TEXT_NODE) p.append(child.textContent);
        else if (child.nodeName === 'MARK') p.append(el('mark', {}, child.textContent));
        else walk(child);
      }
    })(doc.body);
    return p.textContent.trim() ? p : null;
  }

  /**
   * An image URL the page may load: only ones served by our SearXNG (its
   * /image_proxy) or inline data:image. Raw
   * URLs from Google, Brave and the like are dropped, so if SearXNG ever
   * stops proxying its JSON, the phone still never contacts them.
   */
  function imageURL(raw) {
    if (typeof raw !== 'string' || !raw) return null;
    if (raw.startsWith('data:image/')) return raw;
    if (!searxBase) return null;
    try {
      const u = new URL(raw, searxBase);
      if (u.origin === new URL(searxBase).origin) return u.href;
      // The web page reaches SearXNG through a path on its own host, while
      // SearXNG writes its image_proxy links for its own address: send
      // those the same way. Still only ever SearXNG's image proxy.
      if (/\/image_proxy$/.test(u.pathname)) return new URL('image_proxy' + u.search, searxBase).href;
      return null;
    } catch (_) {
      return null;
    }
  }

  function firstImage(...candidates) {
    for (const c of candidates) {
      const u = imageURL(c);
      if (u) return u;
    }
    return null;
  }

  // Images that fail to load (a refused host, an expired link) are removed, not left as broken boxes.
  document.addEventListener(
    'error',
    (event) => {
      const img = event.target;
      if (!(img instanceof HTMLImageElement)) return;
      const tile = img.closest('.image-grid > a');
      (tile || img.closest('.video') || img).remove();
    },
    true,
  );

  // Images load when they come near the screen, at most six at a time, in
  // the order they're reached. Letting Safari start every one at once (an
  // Images page has ~280) queued the visible ones behind the rest over the
  // phone's link: fine on a fast network, slow on a phone.
  const IMAGE_SLOTS = 6;
  let imagesLoading = 0;
  const imageQueue = [];
  function pumpImages() {
    while (imagesLoading < IMAGE_SLOTS && imageQueue.length) {
      const img = imageQueue.shift();
      if (!img.isConnected) continue;
      imagesLoading++;
      const done = () => {
        imagesLoading--;
        pumpImages();
      };
      img.addEventListener('load', done, { once: true });
      img.addEventListener('error', done, { once: true });
      img.src = img.dataset.src;
    }
  }
  const nearScreen = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        nearScreen.unobserve(entry.target);
        imageQueue.push(entry.target);
      }
      pumpImages();
    },
    { rootMargin: '400px 0px' },
  );

  /** An <img> that loads through the queue above. */
  function lazyImage(attrs) {
    const { src, ...rest } = attrs;
    const img = el('img', { ...rest, 'data-src': src, decoding: 'async', referrerpolicy: 'no-referrer' });
    nearScreen.observe(img);
    return img;
  }

  function thumbnail(r) {
    if (!settings.showThumbnails) return null;
    const src = firstImage(r.thumbnail, r.thumbnail_src, r.img_src);
    return src ? lazyImage({ class: 'thumb', src, alt: '' }) : null;
  }

  // --- cards ---------------------------------------------------------------------

  /** A tag that opens something: Hister's page, Obsidian, Niwa, Konbini, a label's search. */
  function chipLink(text, kind, href, title) {
    return el('a', { class: `chip ${kind} link-chip`, href, title }, text);
  }

  /** "2 days ago", as the apps say it; the full date on hover. */
  function relativeDate(seconds) {
    const full = new Date(seconds * 1000).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
    return el('div', { class: 'date', title: full }, S.relativeTime(seconds));
  }

  /**
   * Cards for `docs`, with runs of one site folded (Fold Repeated Sites, as
   * in the app): a run's first card, then "N more from site", which opens
   * the rest in place.
   */
  function appendFolded(list, docs, card) {
    if (settings.foldRepeats === false) {
      for (const d of docs) list.append(card(d));
      return;
    }
    for (const item of S.siteRuns(docs)) {
      if (item.page) {
        list.append(card(item.page));
        continue;
      }
      const hidden = item.pages.map((d) => {
        const c = card(d);
        c.hidden = true;
        return c;
      });
      const count = item.pages.length;
      const button = el('button', { type: 'button', class: 'fold-more', 'aria-expanded': 'false' }, `${count} more from ${item.folded}`);
      button.addEventListener('click', () => {
        const open = button.getAttribute('aria-expanded') !== 'true';
        button.setAttribute('aria-expanded', String(open));
        button.textContent = open ? `Hide ${count} more from ${item.folded}` : `${count} more from ${item.folded}`;
        for (const c of hidden) c.hidden = !open;
      });
      list.append(el('li', { class: 'fold-row' }, button), ...hidden);
    }
  }

  /** Hister's own page for a stored document. */
  const histerPage = (url) => `${histerBase}preview?id=${encodeURIComponent(url)}`;

  // Cards read as on other search engines: the title, then where it is, then when, then the text.
  function histerCard(d) {
    const favicon = d.favicon_key ? `${histerBase}api/favicon?key=${encodeURIComponent(d.favicon_key)}` : null;
    const saved = d.updated || d.added;
    const meta = el(
      'div',
      { class: 'meta' },
      d.label ? labelChip(d.label) : null,
      el('a', { href: histerPage(d.url), class: 'preview-link' }, 'preview'),
      // Shown only once the AI endpoint answers (body.ai-on).
      aiBase && S.summarizable(d.url, d.label) ? el('button', { type: 'button', class: 'summarize-link' }, 'summarize') : null,
    );
    return el(
      'li',
      { class: 'card hister-card', 'data-preview': d.url },
      el('a', { class: 'title', href: d.url }, d.title || d.url),
      urlLine(d.url, favicon),
      saved ? relativeDate(saved) : null,
      markedSnippet(d.text),
      meta,
      places(chipLink('hister', 'hister', histerPage(d.url), 'Open in Hister')),
    );
  }

  /**
   * A file from the folders Hister watches: it opens from Hister's copy
   * (/api/file), shows where it lives, and has no summarize (no model ever
   * reads a file) and no label to edit.
   */
  function fileCard(d) {
    const saved = d.updated || d.added;
    return el(
      'li',
      { class: 'card hister-card file-card', 'data-preview': d.url },
      el('a', { class: 'title', href: S.localFileURL(histerBase, d.url) }, d.title || S.localFilePath(d.url)),
      el('div', { class: 'url' }, el('span', { class: 'crumbs' }, S.localFilePath(d.url))),
      saved ? relativeDate(saved) : null,
      markedSnippet(d.text),
      el('div', { class: 'meta' }, el('a', { href: histerPage(d.url), class: 'preview-link' }, 'preview')),
      places(chipLink('hister', 'hister', histerPage(d.url), 'Open in Hister')),
    );
  }

  /**
   * Where a result opens (Obsidian, Kura, Konbini, Hister): a row of its
   * own under the snippet, left-aligned; the
   * label, preview and summarize stay on the date line.
   */
  function places(...chips) {
    return el('div', { class: 'places' }, ...chips);
  }

  // Konbini's cards (slug ↔ vault path), so notes can link their card and a
  // card's note its Niwa page. Kept for an hour.
  const CARDS_KEY = 'shioriKonbiniCards';
  let cardsPromise = null;
  function konbiniCards() {
    if (!konbiniBase) return Promise.resolve([]);
    cardsPromise ||= (async () => {
      const cachedCards = (await chrome.storage.local.get([CARDS_KEY]))[CARDS_KEY];
      if (cachedCards && Date.now() - cachedCards.at < 60 * 60_000) return cachedCards.cards;
      try {
        const data = await fetchJSON(`${konbiniAPIBase}api/cards`, { timeout: 5000, room: true });
        const cards = (Array.isArray(data) ? data : data.cards || [])
          .filter((c) => c && c.slug && c.path)
          .map((c) => ({ slug: c.slug, path: c.path }));
        await chrome.storage.local.set({ [CARDS_KEY]: { at: Date.now(), cards } });
        return cards;
      } catch (_) {
        return (cachedCards && cachedCards.cards) || [];
      }
    })();
    return cardsPromise;
  }

  /** A vault note: opens in Obsidian, with its Niwa page and Konbini card. */
  function vaultCard(d, cards) {
    const path = S.notePath(d.url, cards);
    // A work vault's note: its own vault's name and Obsidian vault, read in
    // Kura, never a Konbini card or Hister.
    const other = S.noteVault(d.url);
    const vault = other && kuraVaults.find((v) => v.name === other);
    const obsidian = S.obsidianURL(other ? (vault && vault.obsidian) || other : settings.obsidianVault, path);
    let host = '';
    try {
      host = new URL(d.url).host;
    } catch (_) {}
    const niwa = S.readerURL(d.url, niwaBase, path);
    const konbini = other ? null : S.konbiniURL(konbiniBase, path, cards) || (/^konbini\./.test(host) ? d.url : null);
    const saved = d.updated || d.added;
    const crumbs = path ? path.replace(/\.md$/, '').split('/') : [];
    const where = el(
      'div',
      { class: 'url' },
      el('span', { class: 'origin' }, other ? (vault && vault.title) || other : settings.obsidianVault || 'vault'),
      crumbs.length ? el('span', { class: 'crumbs' }, ' › ' + crumbs.join(' › ')) : null,
    );
    const meta = el(
      'div',
      { class: 'meta' },
      el('a', { href: other ? niwa || d.url : histerPage(d.url), class: 'preview-link' }, 'preview'),
    );
    return el(
      'li',
      { class: 'card vault-card', 'data-preview': d.url },
      el('a', { class: 'title', href: obsidian || niwa || d.url }, d.title || path || d.url),
      where,
      saved ? relativeDate(saved) : null,
      markedSnippet(d.text),
      meta,
      places(
        obsidian ? chipLink('obsidian', 'obsidian', obsidian, 'Edit in Obsidian') : null,
        niwa ? chipLink('kura', 'niwa', niwa, 'View in Kura') : null,
        konbini ? chipLink('konbini', 'konbini', konbini, 'View Card in Konbini') : null,
        other ? null : chipLink('hister', 'hister', histerPage(d.url), 'Open in Hister'),
      ),
    );
  }

  function webCard(r) {
    // Not which engines found it (Google CSE, Bing…): where it is and when
    // is what a result needs.
    const meta = el(
      'div',
      { class: 'meta' },
      el('a', { href: S.cachedURL(r.url) }, 'cached'),
      el('a', { href: S.archiveURL(r.url) }, 'archive.is'),
    );
    const li = el(
      'li',
      { class: 'card' },
      el('a', { class: 'title', href: r.url }, S.decodeEntities(r.title) || r.url),
      urlLine(r.url),
      S.shortDate(r.publishedDate) ? el('div', { class: 'date' }, S.shortDate(r.publishedDate)) : null,
    );
    if (r.template === 'videos.html' || category === 'videos') {
      const src = settings.showThumbnails ? firstImage(r.thumbnail, r.thumbnail_src, r.img_src) : null;
      const length = S.duration(r.length);
      if (src) {
        li.append(
          el(
            'a',
            { class: 'video', href: r.url, 'aria-label': r.title ? `Play video: ${r.title}` : 'Play video' },
            lazyImage({ src, alt: '' }),
            length ? el('span', { class: 'length' }, length) : null,
          ),
        );
      } else if (length) {
        li.append(el('div', { class: 'date' }, length));
      }
    } else {
      const thumb = thumbnail(r);
      if (thumb) li.append(thumb);
    }
    const snippet = boldSnippet(S.decodeEntities(r.content));
    if (snippet) li.append(snippet);
    li.append(meta);
    return li;
  }

  function imageTile(r) {
    const src = firstImage(r.thumbnail_src, r.thumbnail, r.img_src);
    if (!src) return null;
    return el(
      'a',
      { href: isHTTP(r.url) ? r.url : r.img_src, title: r.title || '' },
      // The picture is the result: never an empty alt (the site, at least).
      lazyImage({ src, alt: r.title || S.breadcrumb(r.url).origin }),
      el('span', {}, r.title || S.breadcrumb(r.url).origin),
    );
  }

  function infobox(ib) {
    const img =
      settings.showThumbnails && imageURL(ib.img_src)
        ? lazyImage({ class: 'figure', src: imageURL(ib.img_src), alt: '' })
        : null;
    const dl = el('dl');
    for (const a of (ib.attributes || []).slice(0, 8)) {
      if (a && a.label && a.value) dl.append(el('dt', {}, a.label), el('dd', {}, String(a.value)));
    }
    const links = el('ul');
    for (const u of (ib.urls || []).slice(0, 10)) {
      if (u && isHTTP(u.url)) links.append(el('li', {}, el('a', { href: u.url }, u.title || u.url)));
    }
    const section = el(
      'section',
      { class: 'fold panel infobox', 'data-fold': 'info' },
      el(
        'button',
        { class: 'fold-head', type: 'button', 'aria-expanded': 'true' },
        el('span', { class: 'chevron', 'aria-hidden': 'true' }),
        el('span', {}, 'Info'),
      ),
      el(
        'div',
        { class: 'fold-body' },
        el(
          'div',
          {},
          el('h3', {}, ib.infobox || ib.title || ''),
          img,
          ib.content ? el('p', {}, ib.content) : null,
          dl.childNodes.length ? dl : null,
          links.childNodes.length ? links : null,
        ),
      ),
    );
    // Open where it has its own column beside the results (the wide
    // two-column layout, search.css's 1100px): it takes nothing from them
    // there. Shut on a phone, where it pushed the results down. A choice
    // made in this browser still wins.
    fold(section, document.body.classList.contains('two-col') && matchMedia('(min-width: 1100px)').matches);
    return section;
  }

  function showStatus(...parts) {
    reveal();
    $('web').hidden = false;
    $('web-status').replaceChildren(...parts.filter((p) => p != null));
  }

  // --- Did you mean …? ---------------------------------------------------------------
  // A respelling from the web's autocomplete (and, on All, its related
  // searches), shown even when the search found something: "george
  // orewell" finds pages, and the web engines quietly fix it. SearXNG's
  // own `corrections`, when it sends one, comes first.
  // SearXNG's autocomplete for the search, fetched once: "Did you mean"
  // reads it, and Related Searches falls back on it.
  function webAutocomplete() {
    const wq = S.webQuery(q);
    if (!webAutocomplete.reply) {
      webAutocomplete.reply = !searxBase || !wq || S.hasBang(q)
        ? Promise.resolve([])
        : fetchJSON(`${searxBase}autocompleter?q=${encodeURIComponent(wq)}`, { timeout: 3000 })
          .then((json) => (Array.isArray(json) && Array.isArray(json[1]) ? json[1].filter((s) => typeof s === 'string') : []))
          .catch(() => []);
    }
    return webAutocomplete.reply;
  }

  async function didYouMeanLine(related) {
    const wq = S.webQuery(q);
    if (page !== 1 || !searxBase || !settings.webResults || !wq || S.hasBang(q)) return;
    const auto = await webAutocomplete();
    const fix = S.didYouMean(wq, [...auto, ...(await related)]);
    const line = $('correction');
    if (!fix || !line.hidden) return;
    line.replaceChildren('Did you mean ', el('a', { href: link({ q: fix, p: 1 }) }, fix), '?');
    line.hidden = false;
  }

  // --- the Small Web tab: Gemini and Gopher (docs/smallweb.md) --------------
  // Through the small-web gateway, only for a submitted search (this
  // page runs one per load). A result opens where Settings says: the
  // gateway's page, or the gemini:// / gopher:// link for an app such as
  // Lagrange (then the gateway is asked to save it to Hister, since it
  // never passes through); the other is the chip beside it.

  if (category === 'smallweb') {
    $('web').hidden = false;
    $('web-title').textContent = 'Small Web';
    const direct = settings.smallWebOpen === 'direct';
    let reply;
    try {
      const url = S.smallwebSearchURL(smallwebBase, q, page);
      reply = S.smallwebResults(await fetchJSON(url, { timeout: 25000 }));
    } catch (_) {
      return showStatus("The Small Web didn't answer.");
    }
    if (!reply.results.length) return showStatus(['Nothing on the Small Web matches.', ...reply.failures].join(' '));
    // Safari's own page (not the hosted one) can't ask the gateway to save a
    // direct open: its origin isn't one the gateway accepts.
    const unsaved = direct && !settings.smallwebAPIURL ? ["Pages opened in a Gemini app from here aren't saved to Hister."] : [];
    if (reply.failures.length || unsaved.length) $('timing').textContent = [...reply.failures, ...unsaved].join(' · ');
    const opened = (r, isDirect) => {
      recordOpened(r.url, r.title);
      if (!isDirect) return;
      fetch(`${smallwebBase}api/save`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ url: r.url }), keepalive: true,
      }).catch(() => {});
    };
    const anchor = (r, isDirect, attrs, ...children) => {
      const a = el('a', { href: isDirect ? r.url : r.proxy_url, ...attrs }, ...children);
      a.addEventListener('click', () => opened(r, isDirect));
      return a;
    };
    for (const r of reply.results) {
      const snippet = el('p', { class: 'snippet' });
      for (const run of S.markRuns(r.snippet, r.marks)) snippet.append(run.marked ? el('mark', {}, run.text) : run.text);
      $('web-results').append(
        el(
          'li',
          { class: 'card smallweb-card' },
          anchor(r, direct, { class: 'title' }, r.title),
          el('div', { class: 'url' }, el('span', { class: 'origin' }, r.scheme === 'gopher' ? 'Gopher' : 'Gemini'), el('span', { class: 'crumbs' }, ' ' + r.place)),
          r.snippet ? snippet : null,
          // The other way to open it, then the engines that found it.
          places(
            anchor(r, !direct, { class: `chip link-chip ${direct ? 'gateway' : 'gemini'}`, title: direct ? 'Open Through the Gateway' : 'Open in a Gemini App' }, direct ? 'gateway' : r.scheme),
            el('span', { class: 'engines' }, r.engines),
          ),
        ),
      );
    }
    $('pages').hidden = false;
    if (reply.more) $('next').href = link({ p: page + 1 });
    else $('next').hidden = true;
    if (page > 1) {
      $('prev').hidden = false;
      $('prev').addEventListener('click', (e) => (e.preventDefault(), history.back()));
    }
    return restoreScroll();
  }

  // --- the Hister and Vault tabs: the full search of your pages or notes --------

  if (isNoteTab(category)) {
    didYouMeanLine([]);
    const vault = category === 'vault';
    // Files: Hister's watched folders, the same search asking for them alone.
    const files = category === 'files';
    $('web').hidden = false;
    $('web-title').textContent = vault ? 'Your Notes' : files ? 'Your Files' : 'Your Pages';
    if (vault && !kuraBase) return showStatus('No Kura address is set up (Settings → Notes).');
    if (!vault && !histerBase) return showStatus('No Hister server is set up.');
    let result = pageState[category];
    if (vault) {
      await vaultsReady();
      // Which vaults: All, or one (work vaults are searchable in Notes).
      if (kuraVaults.length > 1) {
        const select = el(
          'select',
          { id: 'vault-select', 'aria-label': 'Vault' },
          el('option', { value: 'all' }, 'All Vaults'),
          ...kuraVaults.map((v) => el('option', { value: v.name }, v.title || v.name)),
        );
        select.value = kuraVaults.some((v) => v.name === vaultParam) ? vaultParam : 'all';
        select.addEventListener('change', () => (location.href = link({ v: select.value, p: 1 })));
        $('settings-open').parentElement.insertBefore(select, $('settings-open').parentElement.firstChild);
      }
    }
    if (!result && vault) {
      // Kura pages by offset; a marker page key keeps the Next link below.
      try {
        const offset = (page - 1) * 20;
        result = await kuraNotes(q, { limit: 20, offset, sort: histerSort === 'new' ? 'date' : 'relevance', vault: vaultParam });
        result.page_key = offset + result.documents.length < result.total ? 'kura' : '';
        pageState[category] = result;
        saveState();
      } catch (error) {
        if (error && error.status === 401) return showStatus(...signInNote('Kura'));
        return showStatus('Kura could not be reached.');
      }
    }
    if (!result) {
      try {
        const extra = { highlight: 'HTML' };
        if (histerKey) extra.page_key = histerKey;
        if (histerSort === 'new') extra.sort = 'date';
        result = files
          ? await histerSearch(S.filesQuery(q), 20, extra)
          : await histerOrClose(q, 20, extra, undefined, () => webSuggestions(q));
        pageState[category] = result;
        saveState();
      } catch (_) {
        return showStatus('Hister could not be reached.');
      }
    }
    // Pages is your web pages: Hister sends no notes, but an opened one
    // (Hister's `history` carries no label) is known by its address.
    const pageOf = (d) => d.label !== 'vault' && !S.isNoteURL(d.url, niwaBase, konbiniBase);
    let docs = (result.documents || []).filter((d) => vault || pageOf(d));
    if (!docs.length && !(!vault && (result.history || []).some((h) => pageOf(h)))) {
      return showStatus(vault ? 'No notes in the vault match.' : files ? 'None of your files match.' : 'None of your pages match.');
    }
    if (result.closeMatches) $('web-title').textContent += ` · for “${result.closeMatches}”`;
    const cards = vault ? await konbiniCards() : [];
    let lifted = 0;
    if (!vault && !files && page === 1) {
      const first = withOpened(result, docs, { skipNotes: true });
      for (const card of first.cards) $('web-results').append(card);
      lifted = first.cards.length;
      docs = first.docs;
    }
    appendFolded($('web-results'), docs, (d) => (vault ? vaultCard(d, cards) : files ? fileCard(d) : histerCard(d)));
    const from = (page - 1) * 20 + 1;
    const noun = vault ? 'notes' : files ? 'files' : 'pages';
    // Hister's total is your pages alone (notes are Kura's), so both can say "of".
    $('timing').textContent = `${from}–${from + lifted + docs.length - 1} of ${(result.total || docs.length).toLocaleString()} ${noun}`;
    $('hister-more-tab').href = `${histerBase}?q=${encodeURIComponent(files ? S.filesQuery(q) : q)}`;
    // "Open in Hister" is for Hister's own results, not Kura's.
    $('hister-more-tab').hidden = vault;
    $('pages').hidden = false;
    // A close-match page key belongs to the other spelling: no next page.
    if (result.page_key && docs.length >= 20 && !result.closeMatches) $('next').href = link({ p: page + 1, hk: result.page_key });
    else $('next').hidden = true;
    if (page > 1) {
      $('prev').hidden = false;
      $('prev').addEventListener('click', (e) => (e.preventDefault(), history.back()));
    }
    return restoreScroll();
  }

  // --- The AI answer (All, first page) ------------------------------------------------
  // The AI endpoint answers the search from the web results' snippets
  // (/shiori/ai/answer; it runs the search on SearXNG itself and fetches
  // no pages). Only when opened: a collapsed section costs nothing, and a
  // page reopened on Back redraws its answer from the page's own copy.
  (async () => {
    const section = $('answer');
    const text = S.webQuery(q);
    if (!aiBase || !webLike || page !== 1 || !settings.webResults || settings.aiAnswer === false || !text || S.hasBang(q)) return;
    const status = await aiStatus;
    if (!status || !status.enabled || !status.answer) return;
    const body = $('answer-body');
    const head = section.querySelector('.fold-head');
    const button = (label, title, onclick) => {
      const b = el('button', { type: 'button', class: 'summary-button', title, 'aria-label': title }, label);
      b.addEventListener('click', onclick);
      return b;
    };
    function draw(state) {
      if (state.working) {
        return body.replaceChildren(el('p', { class: 'summary-working' }, el('span', { class: 'summary-spinner', 'aria-hidden': 'true' }), 'Answering…'));
      }
      if (state.error) {
        return body.replaceChildren(el('p', {}, state.error), button('Try Again', 'Answer again', () => load(false)));
      }
      const reply = state.reply;
      const sources = S.citedSources(reply.answer, reply.sources);
      const byNumber = new Map(sources.map((src) => [Number(src.n), src]));
      const paragraph = (line) => {
        const node = el('span');
        for (const run of S.answerRuns(line)) {
          const src = run.cite && byNumber.get(run.cite);
          if (run.text) node.append(run.text);
          else if (src) node.append(el('sup', { class: 'cite' }, el('a', { href: src.url, title: src.title || src.url }, String(run.cite))));
        }
        return node;
      };
      const parts = S.summaryParts(reply.answer);
      body.replaceChildren(
        parts.opening ? el('p', {}, paragraph(parts.opening)) : null,
        parts.points.length ? el('ul', {}, ...parts.points.map((p) => el('li', {}, paragraph(p)))) : null,
        sources.length
          ? el('ol', { class: 'answer-sources' }, ...sources.map((src) => el('li', { value: String(src.n) }, el('a', { href: src.url }, S.decodeEntities(src.title) || src.url), ' ', el('span', { class: 'origin' }, S.breadcrumb(src.url).origin))))
          : null,
        el(
          'p',
          { class: 'summary-byline' },
          S.summaryByline(reply) + ' · from the web results\u2019 snippets ',
          button('Copy', 'Copy the answer', () => navigator.clipboard.writeText(reply.answer).catch(() => {})),
          ' ',
          button('Regenerate', 'Answer again', () => load(true)),
        ),
      );
    }
    let loading = false;
    async function load(refresh) {
      if (loading) return;
      if (!refresh && pageState.answer) return draw({ reply: pageState.answer });
      loading = true;
      draw({ working: true });
      try {
        pageState.answer = await aiPost('answer', { q: text, refresh: !!refresh }, (b) => typeof b.answer === 'string');
        saveState();
        draw({ reply: pageState.answer });
      } catch (error) {
        draw({ error: error.message });
      } finally {
        loading = false;
      }
    }
    fold(section, false);
    head.addEventListener('click', () => {
      if (head.getAttribute('aria-expanded') === 'true') load(false);
    });
    section.hidden = false;
    if (head.getAttribute('aria-expanded') === 'true') load(false);
  })();

  // --- Hold the page until the web is in (All, first page) -------------------------
  // The Info card comes with the web results, a second after your pages:
  // drawing those first made the page jump when it arrived. So the results
  // wait, unseen, for the web (at most 1.5 s), then show at once.
  const holding = webLike && page === 1 && settings.webResults && settings.showInfobox !== false && !!searxBase;
  // var: restoreScroll() calls settle() on paths that return before here.
  var settled = false;
  function settle() {
    if (settled) return;
    settled = true;
    document.body.classList.remove('settling');
  }
  if (holding) {
    document.body.classList.add('settling');
    setTimeout(settle, 1500);
  }

  // --- Hister in General (first page) -----------------------------------------------

  // The web's reply, once it's in (null without one): a search of yours
  // that found nothing borrows a respelling from its related searches.
  let webArrived;
  const webReply = new Promise((resolve) => (webArrived = resolve));
  const suggest = () => webReply.then((d) => (d && d.suggestions) || []);
  if (webLike) didYouMeanLine(suggest());

  let histerDocs = [];
  // On All your pages and notes have no sections: a page of each goes
  // among the web results (mixIn, below), each card saying whose it is,
  // and their totals go on the Pages and Notes pills.
  let myPages = [];
  let myNotes = [];
  const showHister = category === 'general' && settings.histerInGeneral && page === 1 && !!histerBase;
  const showVault = category === 'general' && settings.vaultInGeneral && page === 1 && !!kuraBase;
  // Your notes, from Kura (Hister's queries leave them out).
  const vaultResult = !showVault
    ? Promise.resolve(null)
    : pageState.vault
      ? Promise.resolve(pageState.vault)
      : kuraNotes(q, { limit: ALL_COUNT }).then((r) => {
          pageState.vault = r;
          saveState();
          return r;
        });
  /** A count on a pill (Pages, Notes), kept for the header's redraws. */
  function setPillCount(cat, n) {
    if (!n) return;
    pillCounts[cat] = n.toLocaleString();
    const pill = document.querySelector(`#categories a[data-cat="${cat}"]`);
    if (!pill) return;
    pill.querySelector('.pill-count')?.remove();
    pill.append(el('span', { class: 'pill-count' }, pillCounts[cat]));
  }

  /**
   * Your pages and notes among the web results: pages and notes taking
   * turns, spread evenly from the first web result to the last
   * (S.mixCounts), each card saying whose it is. With no web results,
   * the list is theirs.
   */
  function mixIn() {
    const mine = S.alternate(myPages, myNotes).filter(Boolean);
    if (!mine.length) return;
    const list = $('web-results');
    const web = [...list.children];
    for (const card of mine) {
      card.classList.add('mixed');
      const title = card.querySelector('.title');
      if (title) title.dataset.label = card.classList.contains('vault-card') ? 'Your note' : 'Your page';
    }
    const counts = S.mixCounts(web.length, mine.length);
    let next = 0;
    if (!web.length) list.append(...mine);
    web.forEach((card, i) => {
      card.after(...mine.slice(next, next + counts[i]));
      next += counts[i];
    });
    $('web').hidden = false;
  }

  /** A section with nothing to show: its heading, faded, and why. */
  function emptySection(section, count, why) {
    section.classList.add('empty');
    count.textContent = why;
    section.querySelector('.fold-head')?.setAttribute('aria-expanded', 'false');
    section.hidden = false;
  }

  const histerDone = (async () => {
    if (!showHister) return;
    try {
      let result = pageState.hister;
      if (!result) {
        // Hister sends no notes (S.histerText), so five is five.
        result = await histerOrClose(q, ALL_COUNT, { highlight: 'HTML' }, undefined, suggest);
        pageState.hister = result;
        saveState();
      }
      histerDocs = (result.documents || []).slice(0, ALL_COUNT);
      if (result.closeMatches) $('hister-title').textContent = `Your Pages · for “${result.closeMatches}”`;
      if (!histerDocs.length && !(result.history || []).length) return;
      const first = withOpened(result, histerDocs, { skipNotes: true });
      // At most "How Many": the pages you opened (lifted to the top) count
      // toward it (it showed 6 with 5 chosen).
      first.cards = first.cards.slice(0, ALL_COUNT);
      first.docs = first.docs.slice(0, Math.max(0, ALL_COUNT - first.cards.length));
      if (!first.cards.length && !first.docs.length) return;
      // The pages you opened (lifted to the top) first, then the rest.
      myPages = [...first.cards, ...first.docs.map(histerCard)];
      const shown = first.cards.length + first.docs.length;
      // Hister counts the pages you opened in its total: hidden (Show
      // Opened off), they leave the count too.
      const hiddenOpened = settings.showOpened === true ? 0 : (result.history || []).filter((h) => isHTTP(h.url) && !S.isNoteURL(h.url, niwaBase, konbiniBase)).length;
      setPillCount('hister', Math.max((result.total || 0) - hiddenOpened, shown));
    } catch (_) {
      // Hister unreachable: the web block (or the fallback) carries on.
    }
  })();

  // --- the vault in General (first page) ----------------------------------------------

  let vaultDocs = [];
  const vaultDone = (async () => {
    if (!showVault) return;
    try {
      const result = await vaultResult;
      if (!result) return;
      vaultDocs = result.documents || [];
      if (result.closeMatches) $('vault-title').textContent = `Your Notes · for “${result.closeMatches}”`;
      if (!vaultDocs.length) return;
      const cards = await konbiniCards();
      myNotes = vaultDocs.slice(0, ALL_COUNT).map((d) => vaultCard(d, cards));
      setPillCount('vault', Math.max(result.total || 0, vaultDocs.length));
    } catch (error) {
      // Kura wants the sign-in: said where the notes would be.
      if (error && error.status === 401) {
        emptySection($('vault'), $('vault-count'), '');
        $('vault-count').replaceChildren(...signInNote('Kura'));
      }
    }
  })();

  // --- web block -------------------------------------------------------------------

  const wq = S.webQuery(q);
  if (!wq || !settings.webResults || !searxBase) webArrived(null);
  if (!wq || !settings.webResults) {
    await histerDone;
    await vaultDone;
    mixIn();
    if (!histerDocs.length && !vaultDocs.length) {
      showStatus(settings.webResults ? 'No pages in Hister match.' : 'Nothing in your pages or notes matches.');
    }
    return restoreScroll();
  }
  if (!searxBase) {
    await histerDone;
    $('web').hidden = false;
    $('web-status').replaceChildren('No web search is set up. ', el('a', { href: S.fallbackURL(q) }, 'Search DuckDuckGo'));
    return restoreScroll();
  }

  const started = performance.now();
  let data = pageState.web;
  // "wiki" as a word: Wikipedia's article first, with its Info card. The
  // search without the word starts now, beside the main one, in case the
  // typed search finds no article.
  const wikiWords = page === 1 && webLike ? S.wikiQuery(wq) : null;
  const wikiAlt = wikiWords && !(data && data.shioriWiki) ? searx(wikiWords).catch(() => null) : null;
  if (!data) {
    const url = new URL(`${searxBase}search`);
    url.search = new URLSearchParams({ q: wq, format: 'json', pageno: String(page), categories: webLike ? 'general' : category }).toString();
    if (time) url.searchParams.set('time_range', time);
    try {
      data = await fetchJSON(url.href, { timeout: page === 1 && webLike ? WEB_TIMEOUT_MS : 10000 });
      pageState.web = data;
      saveState();
    } catch (_) {
      webArrived(null);
      if (page === 1 && webLike) {
        await histerDone;
        await vaultDone;
        // Unreachable (VPN off) or broken, and nothing of yours to show:
        // plain DuckDuckGo, without a trace here. With your pages or notes
        // already on screen, keep them (the jump away was jarring).
        if (!histerDocs.length && !vaultDocs.length) {
          location.replace(S.fallbackURL(q));
          return;
        }
        reveal();
        $('web').hidden = false;
        $('web-status').replaceChildren(
          "Web results didn't answer. ",
          el('a', { href: S.fallbackURL(q) }, 'Search DuckDuckGo'),
        );
        mixIn();
        return restoreScroll();
      }
      await histerDone;
      showStatus('SearXNG could not be reached.');
      return;
    }
  }
  if (wikiWords && !data.shioriWiki) {
    data.shioriWiki = (await Promise.race([findWikipedia(data, wikiAlt), new Promise((r) => setTimeout(r, 3000))])) || {};
    pageState.web = data;
    saveState();
  }
  const wiki = data.shioriWiki || {};
  webArrived(data);
  const seconds = ((performance.now() - started) / 1000).toFixed(1);
  await histerDone;
  await vaultDone;

  const corrections = (data.corrections || []).filter((c) => typeof c === 'string' && c !== wq);
  if (corrections.length) {
    $('correction').replaceChildren(
      'Did you mean ',
      el('a', { href: link({ q: corrections[0], p: 1 }) }, corrections[0]),
      '?',
    );
    $('correction').hidden = false;
  }
  const box = wiki.infobox || (data.infoboxes && data.infoboxes[0]);
  if (settings.showInfobox && webLike && page === 1 && box) {
    $('infobox-slot').querySelector('.infobox')?.remove();
    $('infobox-slot').append(infobox(box)); // last, under the AI answer and Related Searches
  }
  const suggestions = (data.suggestions || []).filter((s) => typeof s === 'string' && s !== wq).slice(0, 8);
  function drawRelated(list) {
    for (const s of list) {
      $('suggestion-list').append(el('li', {}, el('a', { href: link({ q: s, p: 1 }) }, s)));
    }
    // A compact row, shut until opened (then remembered, as fold() does).
    fold($('suggestions'));
    $('suggestions').hidden = false;
  }
  if (settings.showRelated && page === 1 && webLike) {
    if (suggestions.length) drawRelated(suggestions);
    // The engines that send related searches drop out now and then (a
    // CAPTCHA, a rate limit): the autocomplete's completions stand in.
    else {
      webAutocomplete().then((auto) => {
        const typed = wq.toLowerCase();
        const list = auto.filter((s) => s.toLowerCase() !== typed).slice(0, 8);
        if (list.length && $('suggestions').hidden) drawRelated(list);
      });
    }
  }

  const results = S.wikiFirst(data.results, wiki.article, wiki.found).filter((r) => r && isHTTP(r.url));
  $('web').hidden = false;
  placeSide.ready = true;
  placeSide();
  $('web-title').textContent = webLike ? 'Web' : CATEGORIES.find(([c]) => c === category)[1];
  const count = data.number_of_results > 0 ? `${data.number_of_results.toLocaleString()} results · ` : '';
  // On All and Web the web's results need no heading: they're the list
  // (on All, your pages and notes among them).
  if (webLike) $('web-title').hidden = true;
  $('timing').textContent = cached ? count.replace(/ · $/, '') : `${count}${seconds} s`;
  const slow = (data.unresponsive_engines || []).map((e) => (Array.isArray(e) ? e[0] : e));
  $('engines').textContent = slow.length ? `No answer from ${slow.join(', ')}` : '';

  if (!results.length) {
    showStatus('No web results.');
  } else if (category === 'images') {
    // 60 tiles at a time; the rest on request.
    $('images').hidden = false;
    const tiles = results.map(imageTile).filter(Boolean);
    let shown = 0;
    const more = el('button', { type: 'button', class: 'page-button show-more' }, 'Show more images');
    const showMore = () => {
      for (const tile of tiles.slice(shown, shown + 60)) $('images').append(tile);
      shown += 60;
      more.hidden = shown >= tiles.length;
    };
    more.addEventListener('click', showMore);
    showMore();
    $('images').after(el('p', { class: 'more' }, more));
  } else {
    // Web leaves out what Your Pages shows, but not a "wiki" search's
    // article: it's the one asked for, and Your Pages may be folded.
    const mine = wiki.article ? histerDocs.filter((d) => S.normalizeURL(d.url) !== S.normalizeURL(wiki.article.url)) : histerDocs;
    const shown = category === 'general' ? S.annotateWeb(results, mine, []) : results;
    const cards = shown.map((r) => {
      const card = webCard(r);
      $('web-results').append(card);
      return [r, card];
    });
    markSaved(cards);
  }
  if (category === 'general' && page === 1) mixIn();

  // Paging, as SearXNG does it.
  if (results.length) {
    $('pages').hidden = false;
    $('next').href = link({ p: page + 1 });
    if (page > 1) {
      $('prev').hidden = false;
      $('prev').href = link({ p: page - 1 });
    }
  }
  restoreScroll();

  /** SearXNG's first page of general results for `text`. */
  function searx(text, params = {}) {
    const url = new URL(`${searxBase}search`);
    url.search = new URLSearchParams({ q: text, format: 'json', pageno: '1', categories: 'general', ...params }).toString();
    return fetchJSON(url.href, { timeout: WEB_TIMEOUT_MS });
  }

  /**
   * For a "wiki" search: the Wikipedia article to put first ({ article,
   * found, infobox }, or {}). The article is the first in the typed
   * search's results, else in the search without "wiki" (`alt`, already
   * under way). Its Info card is SearXNG's wikipedia engine's, which only
   * answers an exact title (`!wp Gemini (astrology)`; `!wp gemini zodiac`
   * finds nothing), so it's asked for by the article's title. All through
   * SearXNG: Shiori never calls Wikipedia itself.
   */
  async function findWikipedia(main, alt) {
    const langs = navigator.languages || [];
    const readers = (a) => langs.some((l) => l.toLowerCase().split('-')[0] === a.lang);
    let article = S.wikipediaArticle(main.results, langs);
    let found = null;
    // None, or only one in another language: try the search without "wiki".
    if (!article || !readers(article)) {
      const other = await alt;
      const better = other && S.wikipediaArticle(other.results, langs);
      if (better && (!article || readers(better))) {
        article = better;
        found = other.results[better.index];
      }
    }
    if (!article) return {};
    let box = (main.infoboxes || []).find((ib) => ib && ib.engine === 'wikipedia') || null;
    if (!box && settings.showInfobox) {
      const wp = await searx(`!wp ${article.title}`, { language: article.lang }).catch(() => null);
      box = ((wp && wp.infoboxes) || []).find((ib) => ib && ib.engine === 'wikipedia') || null;
    }
    return { article, found, infobox: box };
  }

  /** Back to where this page was left, once now and again when images settle. */
  // The Info card beside the results (wide windows, see search.css): its
  // top level with the first result's box, whatever heading is above it.
  // A wide window's right column holds the AI answer, Related Searches and
  // Info, as a sidebar (it often had no Info card and sat empty). They
  // go back to their places on a narrow window or beside the preview pane,
  // which hide the column.
  function sideColumn() {
    return document.body.classList.contains('two-col')
      && !document.body.classList.contains('with-preview') && matchMedia('(min-width: 1100px)').matches;
  }
  function placeSide() {
    // Only once the web results are drawn: they decide it (the preview
    // pane calls this from the start).
    if (!placeSide.ready) return;
    const slot = $('infobox-slot');
    const side = sideColumn();
    // The AI answer first (folded: it asks the AI only when opened), Related
    // Searches under it, then Info.
    if (side && $('answer').parentElement !== slot) slot.prepend($('answer'), $('suggestions'));
    if (!side && $('answer').parentElement === slot) {
      slot.parentElement.insertBefore($('answer'), slot);
      $('web').insertBefore($('suggestions'), $('web-status'));
    }
    slot.classList.toggle('side', side);
    alignInfo();
    // And again once the move and the results around it have been laid out:
    // measured in the same turn, the column landed a few pixels low.
    requestAnimationFrame(() => alignInfo());
    setTimeout(() => alignInfo(), 600);
  }
  matchMedia('(min-width: 1100px)').addEventListener('change', () => placeSide());

  function alignInfo() {
    const slot = $('infobox-slot');
    const main = slot.parentElement;
    slot.style.marginTop = '';
    // Its first box that's drawn (a hidden AI answer has none).
    const top = [...slot.children].find((c) => !c.hidden && c.offsetHeight);
    if (!top || getComputedStyle(main).display !== 'grid') return;
    // The first box drawn in the results' column: a panel (AI Answer), a
    // section's heading row, or the first web card. Not the first .card:
    // inside a collapsed section cards are clipped, not hidden, and Info
    // lined up with an unseen one, well below the top.
    const first = (() => {
      for (const el of main.children) {
        if (el === slot || el.hidden || el.id === 'skeleton' || el.classList.contains('correction') || !el.offsetHeight) continue;
        if (el.id === 'web') return el.querySelector('.panel:not([hidden]), .card') || el;
        return el.matches('.fold:not(.panel)') ? el.querySelector('.fold-head') : el;
      }
      return null;
    })();
    if (!first) return;
    // The card's own box against the first result's, as drawn; then once
    // more for what's left (the pinned column's layout shifts it a little).
    // Measured unpinned: scrolled down (a section opened there), the
    // sticky column and an open section's sticky heading sit where they're
    // stuck, and the card kept that offset once scrolled back up.
    const pinned = [slot, first];
    for (const el of pinned) Object.assign(el.style, { position: 'relative', top: '0' });
    let margin = 0;
    for (let i = 0; i < 3; i++) {
      const gap = first.getBoundingClientRect().top - top.getBoundingClientRect().top;
      if (Math.abs(gap) < 1) break;
      margin = Math.max(0, margin + gap);
      slot.style.marginTop = `${Math.round(margin)}px`;
    }
    for (const el of pinned) Object.assign(el.style, { position: '', top: '' });
  }

  function restoreScroll() {
    settle(); // everything's drawn: show it
    reveal();
    alignInfo(); // once more, as finally drawn
    if (!cached || !cached.y) return;
    const y = cached.y;
    window.scrollTo(0, y);
    window.addEventListener('load', () => window.scrollTo(0, y), { once: true });
  }

  /** A few Hister searches (S.urlLookupQueries) mark the web results already saved (visited) or kept. */
  async function markSaved(cards) {
    const lookups = S.urlLookupQueries(cards.map(([r]) => r.url));
    if (!lookups.length || !histerBase) return;
    try {
      const replies = await Promise.all(lookups.map((q) => histerSearch(q, 100).catch(() => null)));
      const labels = S.savedLabels(replies.flatMap((r) => (r && r.documents) || []));
      for (const [r, card] of cards) {
        const key = S.normalizeURL(r.url);
        if (!labels.has(key)) continue;
        const meta = card.querySelector('.meta');
        const label = labels.get(key);
        meta.prepend(label ? labelChip(label) : chip('visited', 'visited'));
      }
    } catch (_) {}
  }
})();
