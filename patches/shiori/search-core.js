// Shiori's combined search: the pure logic, shared by the results page
// (search.html) and the Node tests (scripts/search-core.test.mjs).
// No DOM and no network here.

(function (root) {
  // Hister-only operators. SearXNG gets the query without them.
  // Hister's syntax, and its @collections (aliases it expands): no use to the web.
  const HISTER_ONLY = /^(-?(label|added|updated|url|domain|type|language|metadata\.[\w.]+):|@\S+$)/i;

  /** A DuckDuckGo !bang anywhere in the query: DuckDuckGo handles those. */
  function hasBang(q) {
    return /(^|\s)!\S/.test(q || '');
  }

  /** The query for the web search, or '' when it was only Hister syntax. */
  function webQuery(q) {
    return (q || '')
      .split(/\s+/)
      .filter((t) => t && !HISTER_ONLY.test(t))
      .join(' ')
      .trim();
  }

  const TRACKING = /^(utm_\w+|fbclid|gclid|mc_cid|mc_eid|ref_src)$/i;

  /** A URL reduced for comparison: no scheme, www., fragment, tracking or trailing slash. */
  function normalizeURL(raw) {
    try {
      const u = new URL(raw);
      const host = u.hostname.toLowerCase().replace(/^www\./, '');
      const params = [...u.searchParams].filter(([k]) => !TRACKING.test(k));
      params.sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
      const query = params.length ? '?' + new URLSearchParams(params).toString() : '';
      let path = u.pathname.replace(/\/+$/, '');
      return host + path + query;
    } catch (_) {
      return String(raw || '');
    }
  }

  /**
   * A Hister query that finds any of these URLs in one search:
   * url:(a|b|...). URLs holding characters the alternation can't carry
   * are left out. Each URL is tried with and without a trailing slash,
   * since Hister stores whichever the page used.
   */
  function urlLookupQuery(urls) {
    const unique = lookupForms(urls);
    return unique.length ? `url:(${unique.join('|')})` : '';
  }

  /** Each URL with and without its trailing slash, once; none holding ( ) | " or a space. */
  function lookupForms(urls) {
    const safe = [];
    for (const u of urls) {
      if (!u || /[()|\s"]/.test(u)) continue;
      safe.push(u);
      safe.push(u.endsWith('/') ? u.slice(0, -1) : u + '/');
    }
    return [...new Set(safe)];
  }

  // A query's longest: the hosted pages' nginx answers 414 past its 8 KB
  // request line, and the query goes out JSON-wrapped and percent-encoded
  // (about half as long again), so 2,000 characters stays near 3.5 KB.
  const LOOKUP_MAX = 2000;

  /**
   * urlLookupQuery in batches, each query at most `max` characters (one
   * URL longer than that alone is left out): the marks for a long list of
   * web results take a few searches, not one too long to send.
   */
  function urlLookupQueries(urls, max = LOOKUP_MAX) {
    const out = [];
    let batch = [];
    const query = (list) => `url:(${list.join('|')})`;
    // A URL and its other form stay in one batch.
    const pairs = [];
    const forms = lookupForms(urls);
    for (let i = 0; i < forms.length; i++) {
      const a = forms[i];
      const b = forms[i + 1];
      if (b !== undefined && (b === a + '/' || a === b + '/')) {
        pairs.push([a, b]);
        i++;
      } else pairs.push([a]);
    }
    for (const pair of pairs) {
      if (query(pair).length > max) continue;
      if (batch.length && query([...batch, ...pair]).length > max) {
        out.push(query(batch));
        batch = [];
      }
      batch.push(...pair);
    }
    if (batch.length) out.push(query(batch));
    return out;
  }

  /**
   * Which web results you already have (Hister's answer to urlLookupQuery):
   * normalised URL → its label ('' for a page with none, "visited").
   * Notes never count: Hister's own copy of one isn't yours to mark.
   */
  function savedLabels(documents) {
    const out = new Map();
    for (const d of Array.isArray(documents) ? documents : []) {
      if (!d || typeof d.url !== 'string' || d.label === 'vault') continue;
      const key = normalizeURL(d.url);
      if (key && !out.has(key)) out.set(key, typeof d.label === 'string' ? d.label : '');
    }
    return out;
  }

  /** Where to go when the web search can't be reached: plain DuckDuckGo. */
  function fallbackURL(q) {
    return 'https://duckduckgo.com/?q=' + encodeURIComponent(q || '') + '&shiori=off';
  }

  /**
   * Whether a duckduckgo.com URL is a search Shiori should take over.
   * `navigationType` is the Navigation Timing type, so going Back to
   * DuckDuckGo shows it instead of bouncing to Shiori again.
   */
  function shouldRedirect(href, navigationType) {
    let u;
    try {
      u = new URL(href);
    } catch (_) {
      return false;
    }
    if (!/^(www\.)?duckduckgo\.com$/.test(u.hostname) || u.pathname !== '/') return false;
    const q = u.searchParams.get('q');
    if (!q || !q.trim()) return false;
    if (u.searchParams.get('shiori') === 'off') return false;
    if (u.searchParams.has('iax') || (u.searchParams.get('ia') || 'web') !== 'web') return false;
    if (hasBang(q)) return false;
    if (navigationType === 'back_forward' || navigationType === 'reload') return false;
    return true;
  }

  /**
   * Web results minus those already shown from Hister, each with what
   * Hister knows about it: `saved` (visited) and its `label` (kept).
   */
  function annotateWeb(webResults, histerDocs, lookupDocs) {
    const shown = new Set(histerDocs.map((d) => normalizeURL(d.url)));
    const known = new Map();
    for (const d of lookupDocs || []) known.set(normalizeURL(d.url), d.label || '');
    const seen = new Set();
    const out = [];
    for (const r of webResults) {
      const key = normalizeURL(r.url);
      if (shown.has(key) || seen.has(key)) continue;
      seen.add(key);
      out.push({ ...r, saved: known.has(key), label: known.get(key) || '' });
    }
    return out;
  }

  /** SearXNG's URL line: the origin, then path segments as › crumbs. */
  function breadcrumb(raw) {
    try {
      const u = new URL(raw);
      const crumbs = u.pathname
        .split('/')
        .filter(Boolean)
        .map((part) => {
          try {
            return decodeURIComponent(part);
          } catch (_) {
            return part;
          }
        });
      return { origin: `${u.protocol}//${u.host}`, crumbs: crumbs.slice(0, 4) };
    } catch (_) {
      return { origin: String(raw || ''), crumbs: [] };
    }
  }

  /** The query's words to bold in snippets: no operators, no bangs, no stopword-short bits. */
  function highlightTerms(q) {
    const words = webQuery(q)
      .split(/\s+/)
      .filter((w) => w && !w.startsWith('-') && !w.startsWith('!') && !/^[a-z]+:/i.test(w))
      .map((w) => w.replace(/^"+|"+$/g, ''))
      .filter((w) => w.length >= 2);
    return [...new Set(words.map((w) => w.toLowerCase()))];
  }

  /** Text split into runs, the query's words marked, for building DOM safely. */
  function splitHighlights(text, terms) {
    if (!text || !terms.length) return [{ text: text || '', hit: false }];
    const escaped = terms.map((t) => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
    const re = new RegExp(`(${escaped.join('|')})`, 'gi');
    const out = [];
    let last = 0;
    for (const m of text.matchAll(re)) {
      if (m.index > last) out.push({ text: text.slice(last, m.index), hit: false });
      out.push({ text: m[0], hit: true });
      last = m.index + m[0].length;
    }
    if (last < text.length) out.push({ text: text.slice(last), hit: false });
    return out;
  }

  /** A SearXNG publishedDate (ISO, maybe "None") as a short date, or ''. */
  function shortDate(value, locale) {
    if (!value || value === 'None') return '';
    const d = new Date(value);
    if (isNaN(d)) return '';
    return d.toLocaleDateString(locale, { year: 'numeric', month: 'short', day: 'numeric' });
  }

  /** A video length, "17:00" or seconds ("206.0"), as m:ss / h:mm:ss. */
  function duration(value) {
    if (value == null || value === 'None' || value === '') return '';
    if (typeof value === 'string' && value.includes(':')) return value;
    const total = Math.round(Number(value));
    if (!isFinite(total) || total <= 0) return '';
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const sec = String(total % 60).padStart(2, '0');
    return h ? `${h}:${String(m).padStart(2, '0')}:${sec}` : `${m}:${sec}`;
  }

  // --- pull to refresh in an installed app (the rooms' ui/machiya.js pullStep) ---
  //   idle --start(ok)--> armed --move past the slop, mostly downward--> pulling
  //   --end with d >= threshold--> reload; armed --sideways or upward--> off
  //   (until the finger lifts); a move that's no longer ok --> off; end or
  //   cancel otherwise --> idle. d is how far the content has come down:
  //   the finger's travel past the slop, times resist up to the threshold,
  //   then harder and harder to pull, never past max (vaultkit 0.22.1). A
  //   release past ready rests the content `hold` down while it reloads.
  const PULL = Object.freeze({ slop: 10, resist: 0.6, threshold: 70, max: 130, hold: 56, settle: 200 });
  const PULL_IDLE = Object.freeze({ phase: 'idle', d: 0 });
  function pullDamp(travel) {
    const d = Math.max(0, travel) * PULL.resist;
    if (d <= PULL.threshold) return d;
    const over = d - PULL.threshold;
    const room = PULL.max - PULL.threshold;
    return PULL.threshold + (room * over) / (over + room);
  }
  function pullStep(s, e) {
    if (s.phase === 'reload') return s;
    if (e.type === 'start') return e.ok ? { phase: 'armed', x: e.x, y: e.y, d: 0 } : PULL_IDLE;
    if (e.type === 'cancel') return PULL_IDLE;
    if (e.type === 'end') return s.phase === 'pulling' && s.d >= PULL.threshold ? { phase: 'reload', d: PULL.hold } : PULL_IDLE;
    if (s.phase !== 'armed' && s.phase !== 'pulling') return s;
    if (!e.ok) return { phase: 'off', d: 0 };
    const dx = e.x - s.x, dy = e.y - s.y;
    if (s.phase === 'armed') {
      if (Math.abs(dx) < PULL.slop && Math.abs(dy) < PULL.slop) return s;
      if (dy < PULL.slop || dy < 1.5 * Math.abs(dx)) return { phase: 'off', d: 0 };
    }
    return { phase: 'pulling', x: s.x, y: s.y, d: Math.min(PULL.max, pullDamp(dy - PULL.slop)) };
  }

  // --- safe links (HisterKit's SafeHref is the twin) --------------------------

  /**
   * A stored or fetched address (Hister's, Kura's, SearXNG's…) as a link
   * or a navigation: http(s) only, parsed as the browser would (it drops
   * tabs, newlines and leading control characters, so "java\tscript:" is
   * javascript:), else ''. `javascript://example.com/%0Aalert(1)` is a
   * valid URL with a host: only the scheme tells. A file:// page goes
   * through localFileURL (Hister's copy), never here.
   */
  function safeHref(url) {
    if (typeof url !== 'string' || !url.trim()) return '';
    let u;
    try {
      u = new URL(url);
    } catch (_) {
      return '';
    }
    return u.protocol === 'http:' || u.protocol === 'https:' ? u.href : '';
  }

  // The schemes Shiori itself builds links in, besides the web's.
  const LINK_SCHEMES = ['http:', 'https:', 'gemini:', 'gopher:', 'obsidian:'];

  /**
   * Any href a page sets (its element builder): the web, the schemes Shiori
   * builds (Obsidian, Gemini, Gopher), or one of the page's own (relative to
   * `base`, the page's address: the extension's search.html?q=…), else ''.
   * Never javascript:, data:, file: or any other.
   */
  function linkHref(value, base) {
    if (typeof value !== 'string' || !value.trim()) return '';
    let u, own;
    try {
      own = new URL(base);
      u = new URL(value, own);
    } catch (_) {
      return '';
    }
    if (LINK_SCHEMES.includes(u.protocol)) return u.href;
    // Same scheme and host (an extension page's origin reads "null").
    return u.protocol === own.protocol && own.host && u.host === own.host ? u.href : '';
  }

  /** SearXNG's "cached" link: the page on the Wayback Machine. */
  function cachedURL(url) {
    return 'https://web.archive.org/web/' + url;
  }

  /** The page's latest snapshot on archive.is (a link only, never fetched). */
  function archiveURL(url) {
    return 'https://archive.is/newest/' + url;
  }

  // --- privacy front ends (HisterKit's Elsewhere is the twin) ----------------

  const REDDIT = ['reddit.com', 'www.reddit.com', 'old.reddit.com', 'new.reddit.com', 'np.reddit.com', 'm.reddit.com', 'redd.it'];
  const YOUTUBE = ['youtube.com', 'www.youtube.com', 'm.youtube.com', 'youtu.be', 'www.youtube-nocookie.com', 'youtube-nocookie.com'];
  const MEDIUM = ['medium.com', 'www.medium.com'];
  const samePage = (u) => ({ path: u.pathname, query: u.search.slice(1) });
  /** youtu.be/<id> and /shorts/<id> become /watch?v=<id> (a start time kept). */
  function youTubePage(u) {
    const parts = u.pathname.split('/').filter(Boolean);
    let id = null;
    if (u.hostname.toLowerCase() === 'youtu.be') id = parts[0] || '';
    else if (parts.length >= 2 && ['shorts', 'embed', 'live'].includes(parts[0])) id = parts[1];
    if (id === null) return samePage(u);
    if (!id) return null;
    const start = u.searchParams.get('t') || u.searchParams.get('start');
    const q = new URLSearchParams({ v: id });
    if (start) q.set('t', start);
    return { path: '/watch', query: q.toString() };
  }
  /** The front ends Shiori knows, keyed as SHIORI_FRONTENDS names them. */
  const FRONTENDS = [
    { key: 'redlib', name: 'Redlib', hosts: REDDIT, page: (u) => {
      if (u.hostname.toLowerCase() !== 'redd.it') return samePage(u);
      const id = u.pathname.split('/').filter(Boolean)[0];
      return id ? { path: '/comments/' + id, query: '' } : null;
    } },
    { key: 'invidious', name: 'Invidious', hosts: YOUTUBE, page: youTubePage },
    { key: 'piped', name: 'Piped', hosts: YOUTUBE, page: youTubePage },
    { key: 'nitter', name: 'Nitter', hosts: ['twitter.com', 'www.twitter.com', 'mobile.twitter.com', 'x.com', 'www.x.com', 'mobile.x.com'], page: samePage },
    { key: 'scribe', name: 'Scribe', hosts: MEDIUM, page: samePage },
    { key: 'libmedium', name: 'LibMedium', hosts: MEDIUM, page: samePage },
    { key: 'rimgo', name: 'rimgo', hosts: ['imgur.com', 'www.imgur.com', 'i.imgur.com', 'm.imgur.com'], page: samePage },
    { key: 'libremdb', name: 'libremdb', hosts: ['imdb.com', 'www.imdb.com', 'm.imdb.com'], page: samePage },
    { key: 'breezewiki', name: 'BreezeWiki', hosts: [], page: (u) => {
      // <wiki>.fandom.com/wiki/Page → /<wiki>/wiki/Page.
      const host = u.hostname.toLowerCase();
      if (!host.endsWith('.fandom.com')) return null;
      const wiki = host.slice(0, -'.fandom.com'.length);
      return wiki && !wiki.includes('.') && wiki !== 'www' ? { path: '/' + wiki + u.pathname, query: u.search.slice(1) } : null;
    } },
  ];

  /** The build's front ends (SHIORI_FRONTENDS, "redlib=https://…,invidious=…"): known names with an http(s) address. */
  function frontendInstances(setting) {
    return String(setting || '').split(',').map((entry) => {
      const at = entry.indexOf('=');
      if (at < 0) return null;
      const frontend = FRONTENDS.find((f) => f.key === entry.slice(0, at).trim().toLowerCase());
      let base = null;
      try { base = new URL(entry.slice(at + 1).trim()); } catch (_) {}
      return frontend && base && /^https?:$/.test(base.protocol) && base.hostname ? { frontend, base } : null;
    }).filter(Boolean);
  }

  /** The page through each front end that stands in for its site: [{name, url}]. */
  function frontendLinks(url, instances) {
    if (!/^https?:\/\//i.test(String(url || ''))) return [];
    let u;
    try { u = new URL(url); } catch (_) { return []; }
    const host = u.hostname.toLowerCase();
    return (instances || []).map(({ frontend, base }) => {
      const serves = frontend.hosts.includes(host) || (frontend.key === 'breezewiki' && host.endsWith('.fandom.com'));
      const page = serves ? frontend.page(u) : null;
      if (!page) return null;
      const out = new URL(base.href);
      out.pathname = out.pathname.replace(/\/$/, '') + (page.path || '/');
      out.search = page.query ? '?' + page.query : '';
      out.hash = u.hash;
      return { name: frontend.name, url: out.href };
    }).filter(Boolean);
  }

  // Where each front end's pages come from (the reverse of frontendLinks).
  const sameOn = (site, origin) => ({ site, page: (path, query) => origin + path + (query ? '?' + query : '') });
  const ORIGINS = {
    redlib: sameOn('Reddit', 'https://www.reddit.com'),
    invidious: sameOn('YouTube', 'https://www.youtube.com'),
    piped: sameOn('YouTube', 'https://www.youtube.com'),
    nitter: sameOn('X', 'https://x.com'),
    scribe: sameOn('Medium', 'https://medium.com'),
    libmedium: sameOn('Medium', 'https://medium.com'),
    rimgo: sameOn('Imgur', 'https://imgur.com'),
    libremdb: sameOn('IMDb', 'https://www.imdb.com'),
    breezewiki: { site: 'Fandom', page: (path, query) => {
      // /<wiki>/wiki/Page → <wiki>.fandom.com/wiki/Page.
      const m = /^\/([^/.]+)\/(.+)$/.exec(path);
      return m ? `https://${m[1]}.fandom.com/${m[2]}` + (query ? '?' + query : '') : null;
    } },
  };

  /** A page on one of the build's front ends, back on its own site: {site, url}, or null. */
  function originalLink(url, instances) {
    if (!/^https?:\/\//i.test(String(url || ''))) return null;
    let u;
    try { u = new URL(url); } catch (_) { return null; }
    for (const { frontend, base } of instances || []) {
      const origin = ORIGINS[frontend.key];
      if (!origin || base.host.toLowerCase() !== u.host.toLowerCase()) continue;
      const prefix = base.pathname.replace(/\/$/, '');
      if (!u.pathname.startsWith(prefix)) continue;
      const page = origin.page(u.pathname.slice(prefix.length) || '/', u.search.slice(1));
      if (page) return { site: origin.site, url: page + u.hash };
    }
    return null;
  }

  /**
   * A web page elsewhere, for a menu: its own site when it's a front end's
   * page (Original), Archive.org and Archive.is (of the original), then the
   * front ends for its site.
   */
  function elsewhereLinks(url, instances) {
    if (!/^https?:\/\//i.test(String(url || ''))) return [];
    const original = originalLink(url, instances);
    const page = original ? original.url : url;
    return [
      ...(original ? [{ name: 'Original', site: original.site, url: original.url }] : []),
      { name: 'Archive.org', url: cachedURL(page) },
      { name: 'Archive.is', url: archiveURL(page) },
      ...frontendLinks(url, instances),
    ];
  }

  // --- vault notes (Hister's label:vault documents) ---------------------------

  /**
   * The vault path ("Projects/Example.md") of a note Hister stored from
   * Niwa (/n/<path>) or Konbini (/p/<slug>, looked up in its cards).
   */
  function notePath(url, cards) {
    let u;
    try {
      u = new URL(url);
    } catch (_) {
      return null;
    }
    // A work vault's note is /v/<vault>/n/<slug> (Kura's vaults).
    const niwa = u.pathname.match(/^(?:\/v\/[^/]+)?\/n\/(.+)$/);
    if (niwa) {
      try {
        return decodeURIComponent(niwa[1]).replace(/\/+$/, '') + '.md';
      } catch (_) {
        return null;
      }
    }
    const konbini = u.pathname.match(/^\/p\/([^/]+)\/?$/);
    if (konbini) {
      const card = (cards || []).find((c) => c.slug === konbini[1]);
      return card && card.path ? card.path : null;
    }
    return null;
  }

  /**
   * The vault a note belongs to ("work"), from its address: Kura keeps
   * the default vault's notes at /n/<slug> for good and every other one's
   * at /v/<vault>/n/<slug>. null for the default vault or a non-note.
   * Which vault, not whether it's private: that's isPrivateNote.
   * HisterKit's Notes.otherVault is the twin.
   *
   * Read as Kura reads it: Kura serves `/v/` however the path reaches it
   * (its server folds a leading `//`, then it decodes `%XX` once), so
   * `//v/…` and `/%76/…` are a work note too. Only ASCII escapes are
   * decoded: a vault's name and the `/v/…/n/` around it are ASCII. The
   * name is then used as it is, never decoded again (`/v/%2577ork/n/` is
   * `%77ork`, which isPrivateNote holds private). Kura refuses a public
   * address with a path, so `/v/` starts the path.
   */
  function noteVault(url) {
    const path = kuraPath(url);
    // Any page under /v/<name>/: a note (/n/…), and a folder or tag page
    // too, which lists the vault's titles (over-inclusive, so safe).
    const m = path && path.match(/^\/v\/([^/]+)\//);
    return m ? m[1] : null;
  }
  /**
   * The path as Kura would serve it: `%XX` escapes of ASCII characters
   * decoded once, leading slashes folded into one, `.` and `..` segments
   * resolved (new URL resolves them; again after the decoding, which is
   * over-inclusive and so safe). null when the address can't be parsed:
   * isPrivateNote then holds it private. HisterKit's Notes.kuraPath is the twin.
   */
  function kuraPath(url) {
    let pathname;
    try {
      pathname = new URL(url).pathname;
    } catch (_) {
      return null;
    }
    const decoded = pathname.replace(/%([0-7][0-9a-f])/gi, (_, hex) => String.fromCharCode(parseInt(hex, 16)));
    const segments = [];
    for (const segment of decoded.replace(/^\/+/, '').split('/')) {
      if (segment === '..') segments.pop();
      else if (segment !== '.') segments.push(segment);
    }
    return '/' + segments.join('/');
  }
  // A vault name as Kura allows it.
  const VAULT_NAME = /^[a-z0-9-]+$/;
  // The vaults Kura marks shared (/api/vaults: not the default, `private:
  // false`), from the last useVaults. Empty until then, so every other
  // vault is private until Kura says otherwise.
  let sharedVaults = new Set();
  const sharedIn = (list) => new Set(
    (Array.isArray(list) ? list : [])
      .filter((v) => v && typeof v.name === 'string' && v.default !== true && v.private === false)
      .map((v) => v.name),
  );
  /** Kura's /api/vaults list, as last read; anything else (a failure: []) shares none. */
  function useVaults(list) {
    sharedVaults = sharedIn(list);
  }
  /**
   * A private vault's note: another vault's, unless Kura marks that vault
   * shared. Everything that must not reach a private note (Hister, AI,
   * caches, exports) asks this. HisterKit's Notes.isPrivateNote is the twin.
   */
  const isPrivateNote = (url) => privateGiven(url, sharedVaults);
  const privateGiven = (url, shared) => {
    // Fails closed: an address that can't be parsed, and a name that isn't
    // one Kura allows, are private.
    if (kuraPath(url) === null) return true;
    const vault = noteVault(url);
    return vault !== null && (!VAULT_NAME.test(vault) || !shared.has(vault));
  };
  // Numbers the fresh reads: only an answer newer than the last one kept
  // replaces it (a slow older one, landing later, doesn't).
  let vaultReadsIssued = 0;
  let vaultReadKept = 0;
  /**
   * isPrivateNote with Kura asked afresh: before another vault's note (its
   * address, title or text) goes to Hister or an AI engine, since a shared
   * vault can be made private again at any time. `read` answers
   * /api/vaults' list; its answer is kept (useVaults), and a failed read
   * shares none. The default vault's notes and other pages ask nothing.
   * The cached isPrivateNote is enough for what's only shown. The answer
   * is this read's own, kept for the cached check when it's the newest.
   * HisterKit's Notes.isPrivateNoteNow is the twin.
   */
  async function isPrivateNoteNow(url, read) {
    if (noteVault(url) === null) return isPrivateNote(url);
    const ticket = ++vaultReadsIssued;
    let list = [];
    try {
      const got = await read();
      list = Array.isArray(got) ? got : [];
    } catch (_) {
      list = [];
    }
    const found = sharedIn(list);
    if (ticket > vaultReadKept) {
      vaultReadKept = ticket;
      sharedVaults = found;
    }
    return privateGiven(url, found);
  }
  /**
   * Kura's vaults through `read` (it answers /api/vaults' list), passed to
   * useVaults and returned; [] when the read fails, which shares none.
   * Every client reads them this way.
   */
  async function loadVaults(read) {
    let list = [];
    try {
      const got = await read();
      list = Array.isArray(got) ? got : [];
    } catch (_) {
      list = [];
    }
    useVaults(list);
    return list;
  }

  /**
   * A note's chip, naming its vault ("Work vault"), since Notes mix
   * vaults: the vault from its address, else Kura's default one (`vaults`: /api/vaults' list).
   * { name, text }; name '' when the default isn't known yet, and the text
   * then is just "vault". HisterKit's Notes.vaultChip is the twin.
   */
  function vaultChip(url, vaults) {
    const list = vaults || [];
    const name = noteVault(url) || (list.find((v) => v && v.default) || {}).name || '';
    const vault = list.find((v) => v && v.name === name);
    return { name, text: name ? `${(vault && vault.title) || name} vault` : 'vault' };
  }

  /** obsidian://open for a vault path (without its .md). */
  function obsidianURL(vault, path) {
    if (!vault || !path) return null;
    return (
      'obsidian://open?vault=' + encodeURIComponent(vault) + '&file=' + encodeURIComponent(path.replace(/\.md$/, ''))
    );
  }

  /** The Niwa page for a vault path. */
  /**
   * A note's reader page (Kura; Niwa before it): the
   * note's own address when that already is a reader page (/n/…), else
   * one built on the reader's address (a Konbini project card's note).
   */
  function readerURL(docURL, base, path) {
    try {
      const u = new URL(docURL);
      if (u.pathname.startsWith('/n/') || noteVault(docURL)) return docURL;
    } catch (_) {}
    return niwaURL(base, path);
  }

  /** A vault tag's page in Kura (/t/topic/docker), which owns tag browsing. */
  function kuraTagURL(base, tag) {
    const t = String(tag || '').replace(/^#/, '');
    if (!base || !t) return null;
    return base.replace(/\/?$/, '/') + 't/' + t.split('/').map(encodeURIComponent).join('/');
  }

  function niwaURL(base, path) {
    if (!base || !path) return null;
    const segments = path.replace(/\.md$/, '').split('/').map(encodeURIComponent);
    return base.replace(/\/?$/, '/') + 'n/' + segments.join('/');
  }

  /** The Konbini card for a vault path, if the note is a project card. */
  function konbiniURL(base, path, cards) {
    if (!base || !path) return null;
    const card = (cards || []).find((c) => c.path === path);
    return card ? base.replace(/\/?$/, '/') + 'p/' + encodeURIComponent(card.slug) : null;
  }

  /** The query restricted to vault notes. */
  /**
   * The same words, allowing for typos: `raspbery~2`, for a search that
   * found nothing in Hister. Only plain words (any operator, quote, `-`,
   * `*` or `~` and it's null); two edits for words of 5 letters or more (a
   * swapped pair of letters is two), one for 4, none below. Null when no
   * word would change.
   */
  /**
   * Which of the eight chip colours a label gets: djb2 over its Unicode
   * scalars, as the app's `Palette.chipHex(for:)` does, so `books` is the
   * same hue in the app, on this page and in the web app.
   */
  function labelChipIndex(label, count = 8) {
    let hash = 5381;
    for (const ch of String(label)) hash = (Math.imul(hash, 33) + ch.codePointAt(0)) >>> 0;
    return hash % count;
  }

  /**
   * The Hister searches behind the suggestions as you type: the words so
   * far with the last one as a title prefix ("raspberry ze" → "raspberry
   * title:ze*"), and the words as typed (which finds "raspberrypi" in
   * "Raspberry Pi"'s text). None for under two characters or anything
   * with query syntax, which the field's completions already cover.
   */
  function suggestionQueries(text) {
    const typed = (text || '').trim().toLowerCase();
    const words = typed.split(/\s+/).filter(Boolean);
    if (typed.length < 2 || !words.length) return [];
    if (words.some((w) => /[:"'*~()|]/.test(w) || w.startsWith('-') || w.startsWith('+'))) return [];
    const last = words[words.length - 1];
    return [[...words.slice(0, -1), `title:${last}*`].join(' '), words.join(' ')];
  }

  /**
   * Whether a title fits what's typed: every word is in the title once its
   * spaces are gone, so "raspberrypi" fits "Raspberry Pi" and "pytho"
   * fits "Learn Python 3".
   */
  function titleMatches(title, text) {
    const flat = String(title || '').toLowerCase().replace(/\s+/g, '');
    const words = String(text || '').trim().toLowerCase().split(/\s+/).filter(Boolean);
    return !!words.length && !!flat && words.every((w) => flat.includes(w));
  }

  /**
   * SearXNG's /autocompleter reply (OpenSearch: [typed, [suggestions…]]):
   * up to five, without the text already typed. Anything else, none.
   */
  function parseAutocomplete(json, typed) {
    const list = Array.isArray(json) && Array.isArray(json[1]) ? json[1] : [];
    const same = String(typed || '').trim().toLowerCase();
    const out = [];
    for (const s of list) {
      if (typeof s !== 'string' || !s.trim()) continue;
      const t = s.trim();
      if (t.toLowerCase() === same || out.some((o) => o.toLowerCase() === t.toLowerCase())) continue;
      out.push(t);
      if (out.length === 5) break;
    }
    return out;
  }

  /**
   * A collection's icon, by a word in its name (the app's CollectionIcon
   * uses the same words, with SF Symbols): one of palette, controller,
   * helm, bookmark, leaf, cpu, book, music, food, travel, work, film,
   * heart, server, shield, else 'stack'.
   */
  const COLLECTION_WORDS = [
    [['retro', 'vintage'], 'clock'],
    [['unix', 'linux', 'bsd', 'terminal', 'shell'], 'terminal'],
    [['smallweb', 'small-web', 'indieweb', 'web'], 'globe'],
    [['gear', 'hardware', 'tools'], 'wrench'],
    [['culture'], 'masks'],
    [['homelab'], 'server'],
    [['art', 'design', 'draw', 'paint'], 'palette'],
    [['game', 'gaming', 'play'], 'controller'],
    [['k8s', 'kube', 'cluster', 'infra', 'ops'], 'helm'],
    [['kept', 'keep', 'saved', 'save', 'star', 'fav'], 'bookmark'],
    [['life', 'home', 'family', 'garden'], 'leaf'],
    [['tech', 'code', 'dev', 'program', 'software', 'computer'], 'cpu'],
    [['book', 'read', 'library'], 'book'],
    [['music', 'audio', 'song'], 'music'],
    [['food', 'recipe', 'cook'], 'food'],
    [['travel', 'trip'], 'travel'],
    [['work', 'job', 'career'], 'work'],
    [['film', 'movie', 'tv', 'video'], 'film'],
    [['health', 'fit', 'sport'], 'heart'],
    [['server', 'selfhost', 'homelab'], 'server'],
    [['security', 'privacy'], 'shield'],
  ];
  /** A collection's name as shown: the alias keyword without its "@". */
  function collectionTitle(name) {
    const s = String(name || '');
    return s.startsWith('@') ? s.slice(1) : s;
  }

  /**
   * The labels named in the aliases' expansions (label:x and label:(a|b)),
   * sorted, and each alias's own set: all the label data Hister offers
   * (it has no list-every-label call).
   */
  /**
   * The aliases that are collections: not one about the notes (Hister's
   * `@notes`, `@pages`), which would read as collections called "notes"
   * and "pages". HisterKit's Rules.namesTheVault, with the same tests.
   */
  function collectionAliases(aliases) {
    // Nor one about the code (metadata.source:code, code-import's): it has its own pill.
    return Object.fromEntries(Object.entries(aliases || {}).filter(([, v]) => !/(label|source):(\([^)]*)?\bvault\b|source:(\([^)]*)?\bcode\b/.test(String(v))));
  }

  /**
   * Whether an alias is a collection: only "@" keywords are (a Machiya
   * convention; HisterKit's `Rules.isCollectionKeyword` is the twin). A
   * plain alias, such as one naming every label, is the user's own query,
   * never listed or edited as a collection.
   */
  function isCollectionKeyword(key) {
    return /^@\S/.test(String(key || ''));
  }

  function labelsFromAliases(aliases) {
    const all = new Set();
    const byAlias = {};
    for (const [alias, expansion] of Object.entries(aliases || {})) {
      const set = new Set();
      for (const m of String(expansion).matchAll(/label:\(([^)]*)\)|label:([A-Za-z0-9_-]+)/g)) {
        for (const name of (m[1] || m[2] || '').split('|').filter(Boolean)) {
          all.add(name);
          set.add(name);
        }
      }
      byAlias[alias] = set;
    }
    return { labels: [...all].sort(), byAlias };
  }

  /**
   * Labels and collections for the last word typed, for the search field's
   * suggestions: {kind: 'collection'|'label', name, query}. Collections
   * first ("@" aliases only, and not one that names every label), then labels; within
   * each, names starting with the word before ones containing it, then
   * alphabetical. The apps' `LabelSuggestions` follows the same rule.
   */
  function labelSuggestions(text, labels, aliases, limit = 6) {
    const words = String(text || '').trim().toLowerCase().split(/\s+/);
    const word = words[words.length - 1] || '';
    if (word.length < 2 || /[:"*~()|]/.test(word)) return [];
    const { byAlias } = labelsFromAliases(aliases);
    const every = new Set(labels || []);
    const rank = (a, b) => {
      const as = a.name.toLowerCase().startsWith(word) ? 0 : 1;
      const bs = b.name.toLowerCase().startsWith(word) ? 0 : 1;
      return as - bs || a.name.localeCompare(b.name);
    };
    const collections = Object.keys(aliases || {})
      .filter(isCollectionKeyword)
      .filter((key) => !(every.size && byAlias[key] && byAlias[key].size >= every.size && [...every].every((l) => byAlias[key].has(l))))
      .map((key) => ({ kind: 'collection', name: collectionTitle(key), query: key }))
      .filter((c) => c.name.toLowerCase().includes(word))
      .sort(rank);
    const labelItems = (labels || [])
      .filter((l) => String(l).toLowerCase().includes(word))
      .map((l) => ({ kind: 'label', name: l, query: `label:${l}` }))
      .sort(rank);
    return [...collections, ...labelItems].slice(0, limit);
  }

  function collectionIcon(name) {
    const lower = String(name || '').toLowerCase();
    const hit = COLLECTION_WORDS.find(([words]) => words.some((w) => lower.includes(w)));
    return hit ? hit[1] : 'stack';
  }

  /**
   * A section's count, always shown (Your Pages' had vanished when the
   * cards on screen outnumbered Hister's total less your notes): "3 of 8
   * results", or "6 results" when that's all of them.
   */
  function countText(shown, total) {
    const all = Math.max(total || 0, shown || 0);
    if (!all) return '';
    const noun = all === 1 ? 'result' : 'results';
    // The full count only: "15 results", not "3 of 15" (the sections
    // start collapsed).
    return `${all} ${noun}`;
  }

  /**
   * A preview's dates line: "Added 3 May 2026 · updated 9 May 2026 · 4
   * visits". Each date from the preview (`p`), else the list's row (`doc`:
   * a note from Kura has its `created` and `changed` there and none in the
   * preview); a note with no created date says only when it changed, and
   * with neither the line is empty. `format` turns unix seconds into text.
   */
  function previewDates(p, doc, format) {
    const added = Number((p && p.added) || (doc && doc.added)) || 0;
    const updated = Number((p && p.updated) || (doc && doc.updated)) || 0;
    const visits = Number(p && p.details && p.details.visits) || 0;
    return [
      added ? `Added ${format(added)}` : '',
      updated && updated !== added ? `${added ? 'updated' : 'Updated'} ${format(updated)}` : '',
      visits > 1 ? `${visits} visits` : '',
    ].filter(Boolean).join(' · ');
  }

  /** Edits between two words: insert, delete, change, or swap two neighbours. */
  function editDistance(a, b) {
    const x = [...a], y = [...b];
    const d = Array.from({ length: x.length + 1 }, (_, i) => [i, ...Array(y.length).fill(0)]);
    for (let j = 1; j <= y.length; j++) d[0][j] = j;
    for (let i = 1; i <= x.length; i++) {
      for (let j = 1; j <= y.length; j++) {
        const cost = x[i - 1] === y[j - 1] ? 0 : 1;
        d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost);
        if (i > 1 && j > 1 && x[i - 1] === y[j - 2] && x[i - 2] === y[j - 1]) {
          d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
        }
      }
    }
    return d[x.length][y.length];
  }

  /**
   * A respelling of `q` taken from the web's related searches, for when
   * Hister (which matches words exactly and has no fuzzy search: `word~2`
   * finds the word "2") found nothing. Every word must be near one of a
   * suggestion's words: two edits for 5+ letters, one for 4, none below.
   * "rasbperry pi" with "raspberry pi 5" → "raspberry pi". Null when no
   * suggestion fits, nothing would change, or `q` holds operators.
   */
  function correctedQuery(q, suggestions) {
    const words = (q || '').trim().toLowerCase().split(/\s+/).filter(Boolean);
    if (!words.length || words.some((w) => /[:"'*~()|]/.test(w) || w.startsWith('-') || w.startsWith('+'))) return null;
    for (const s of suggestions || []) {
      if (typeof s !== 'string') continue;
      const pool = s.toLowerCase().split(/\s+/).filter(Boolean);
      const used = new Set();
      const out = [];
      for (const w of words) {
        const n = [...w].length;
        const room = n >= 5 ? 2 : n === 4 ? 1 : 0;
        let best = -1, bestDistance = Infinity;
        pool.forEach((p, i) => {
          if (used.has(i)) return;
          const distance = editDistance(w, p);
          if (distance < bestDistance) (best = i), (bestDistance = distance);
        });
        if (best < 0 || bestDistance > room) break;
        used.add(best);
        out.push(pool[best]);
      }
      if (out.length === words.length && out.join(' ') !== words.join(' ')) return out.join(' ');
    }
    return null;
  }

  /**
   * Type-ahead: the rest of the first candidate that starts with what's
   * typed, shown grey after the caret (Tab or → takes it). Recent searches
   * come first, then the web's autocomplete. '' when none fits, or for
   * fewer than two characters.
   */
  function typeAhead(typed, candidates) {
    const text = String(typed || '');
    if (text.trim().length < 2) return '';
    const lower = text.toLowerCase();
    for (const c of candidates || []) {
      if (typeof c !== 'string') continue;
      const t = c.trim();
      if (t.length > text.length && t.toLowerCase().startsWith(lower)) return t.slice(text.length);
    }
    return '';
  }

  // --- What a search sends (HisterKit's SearchText, same tests) -------------------

  /**
   * The last word as a prefix ("hist" → "hist*"): Hister and Kura match
   * whole words, so "hist" finds nothing that "history" would. Only a plain word of two or more characters with a
   * letter, not after a trailing space or inside an open quote.
   *
   * `union` (Hister's): the word or its prefix, "(hist|hist*)". Hister's
   * prefix alone misses most body-text matches of a whole word
   * ("concurrency*" found 1 page of 45), and its (a|b) is a union, so this
   * finds everything either does, highlighted. Kura has no (a|b): it
   * keeps "hist*".
   */
  function prefixLastWord(text, { union = false } = {}) {
    const t = String(text || '');
    if (!t || /\s$/.test(t)) return t;
    if ((t.match(/"/g) || []).length % 2) return t;
    const word = t.split(/\s+/).pop();
    if ([...word].length < 2 || !/\p{L}/u.test(word) || !/^[\p{L}\p{N}]+$/u.test(word)) return t;
    return union ? `${t.slice(0, t.length - word.length)}(${word}|${word}*)` : t + '*';
  }

  /**
   * Shiori reads notes only from Kura: every Hister query leaves them out.
   * Hister has no exclude parameter, but a negated field works ("*
   * -label:vault" is exactly the pages, with paging and exact totals).
   */
  // metadata.source too, so a note relabelled in Hister's own UI stays out.
  const NOTES_EXCLUSION = '-label:vault -metadata.source:vault';
  const EXCLUSION_TERMS = NOTES_EXCLUSION.split(' ');
  function excludingNotes(text) {
    const t = String(text || '').trim();
    const words = t.split(/\s+/);
    if (EXCLUSION_TERMS.every((term) => words.includes(term))) return t;
    return t ? `${t} ${NOTES_EXCLUSION}` : NOTES_EXCLUSION;
  }

  // --- Files: the folders Hister watches ---------------------------------------------
  // Documents of type `local` (Hister's indexer.directories), with a file://
  // address, served by Hister (/api/file). Only the Files tab shows them:
  // every other Hister query leaves them out. HisterKit's LocalFiles is the
  // twin, with the same tests.
  const FILES_TERM = 'type:local';
  const FILES_EXCLUSION = '-type:local';
  /** A query that asks for files: `type:local` among its words. */
  function asksForFiles(text) {
    return String(text || '').split(/\s+/).includes(FILES_TERM);
  }
  /** The Files tab's query from what was typed; the term leads, so the last word stays a prefix. */
  function filesQuery(typed) {
    const words = String(typed || '').trim();
    return `${FILES_TERM} ${words || '*'}`;
  }
  /** A watched file, known by its address. */
  function isLocalFile(url) {
    return /^file:\/\//i.test(String(url || ''));
  }
  /** Hister's served copy of a file (/api/file?id=<its address>), or '' for anything else. */
  function localFileURL(base, url) {
    if (!isLocalFile(url)) return '';
    const root = String(base || '').endsWith('/') ? base : `${base}/`;
    return `${root}api/file?id=${encodeURIComponent(url)}`;
  }
  /** Where a file lives: the path without file://. */
  function localFilePath(url) {
    if (!isLocalFile(url)) return String(url || '');
    const rest = String(url).slice('file://'.length);
    try { return decodeURIComponent(rest); } catch (_) { return rest; }
  }

  // --- Code: your repos (code-import, metadata.source:code) ---------------------
  // Repo cards, READMEs and docs, issues, PRs and releases from your
  // forges, each at its real forge URL. Only the Code pill shows them:
  // every other Hister query leaves them out. Their metadata values a
  // query matches are single lowercase tokens (Hister can't match "/" in
  // one): code_repo is owner__repo, code_private the STRING "true".
  // HisterKit's CodeDocs is the twin, with the same tests.
  const CODE_TERM = 'metadata.source:code';
  const CODE_EXCLUSION = '-metadata.source:code';
  /** A query that asks for code: `metadata.source:code` among its words. */
  function asksForCode(text) {
    return String(text || '').split(/\s+/).includes(CODE_TERM);
  }
  /**
   * A repo's key as code-import stores it: owner and repo each lowercase
   * with every other character "_", joined by "__" ("Owner/My-Repo" →
   * "owner__my_repo"); a key already made stays as it is.
   */
  function codeRepoKey(name) {
    const clean = (part) => String(part || '').toLowerCase().replace(/[^a-z0-9]/g, '_');
    const text = String(name || '').trim();
    const slash = text.indexOf('/');
    return slash < 0 ? clean(text) : `${clean(text.slice(0, slash))}__${clean(text.slice(slash + 1))}`;
  }
  // The kinds a filter offers; Docs covers READMEs too.
  const CODE_KINDS = [
    ['repo', 'Repos'], ['docs', 'Docs'], ['issue', 'Issues'], ['pr', 'Pull Requests'], ['release', 'Releases'],
  ];
  /**
   * The Code pill's query: the term and the filters first, so the last
   * typed word stays a prefix. `filters`: { kind (CODE_KINDS' key), host,
   * open (true), repo (a name or key), private (true) }.
   */
  function codeQuery(typed, filters = {}) {
    const terms = [CODE_TERM];
    const f = filters || {};
    if (f.kind === 'docs') terms.push('metadata.code_kind:(readme|doc)');
    else if (CODE_KINDS.some(([k]) => k === f.kind)) terms.push(`metadata.code_kind:${f.kind}`);
    if (/^[a-z]+$/.test(String(f.host || ''))) terms.push(`metadata.code_host:${f.host}`);
    if (f.open === true) terms.push('metadata.code_state:open');
    if (f.repo) terms.push(`metadata.code_repo:${codeRepoKey(f.repo)}`);
    if (f.private === true) terms.push('metadata.code_private:true');
    const words = String(typed || '').trim();
    return `${terms.join(' ')} ${words || '*'}`;
  }
  // The forges code-import reads, for the host filter and each row's badge.
  const CODE_HOSTS = [['forgejo', 'Forgejo'], ['github', 'GitHub']];
  /** A host's name for a row ("forgejo" → "Forgejo"); an unknown one as given. */
  function codeHostName(host) {
    const known = CODE_HOSTS.find(([k]) => k === host);
    return known ? known[1] : String(host || '');
  }

  /** A code document (Hister's metadata.source "code"). */
  function isCodeDoc(doc) {
    return !!(doc && doc.metadata && doc.metadata.source === 'code');
  }
  /** What a code row shows, from its metadata; null for anything else. */
  function codeInfo(doc) {
    if (!isCodeDoc(doc)) return null;
    const m = doc.metadata;
    const str = (v) => (typeof v === 'string' ? v : typeof v === 'number' ? String(v) : '');
    return {
      kind: str(m.code_kind), host: str(m.code_host), repo: str(m.code_repo), repoName: str(m.code_repo_name),
      state: str(m.code_state), private: m.code_private === 'true' || m.code_private === true,
      number: str(m.code_number), tag: str(m.code_tag), path: str(m.code_path),
    };
  }
  /** The repo's note in the default vault, as Kura's path (Repos/<name>.git.md), or ''. */
  function codeNotePath(repoName) {
    const name = String(repoName || '').split('/').pop().trim();
    return /^[A-Za-z0-9._-]+$/.test(name) ? `Repos/${name}.git.md` : '';
  }

  /** A Hister search as sent: the last word a prefix, never the notes, and never the files or code unless it asks. */
  /** A dangling quote closed: open, it swallowed the exclusions after it into one phrase (no results). */
  function closeQuote(text) {
    return (text.match(/"/g) || []).length % 2 ? text + '"' : text;
  }

  function histerText(text) {
    let sent = excludingNotes(prefixLastWord(closeQuote(String(text || '').trim()), { union: true }));
    const words = sent.split(/\s+/);
    if (!asksForFiles(sent) && !words.includes(FILES_EXCLUSION)) sent = `${sent} ${FILES_EXCLUSION}`;
    if (!asksForCode(sent) && !words.includes(CODE_EXCLUSION)) sent = `${sent} ${CODE_EXCLUSION}`;
    return sent;
  }

  /** A query as typed, from one sent (the Opened list shows it). */
  function typedQuery(text) {
    const shown = String(text || '').split(/\s+/).filter((w) => w && !EXCLUSION_TERMS.includes(w) && w !== FILES_EXCLUSION && w !== CODE_EXCLUSION).join(' ');
    // "(word|word*)" as sent now, "word*" before.
    const union = shown.match(/^(.*?)\(([\p{L}\p{N}]+)\|\2\*\)$/u);
    if (union) return union[1] + union[2];
    return shown.endsWith('*') ? shown.slice(0, -1) : shown;
  }

  /**
   * What a newest-first list's "↑ N New Items" counts: results not on
   * screen that are newer than the newest one shown (`newestShown`, unix
   * seconds; 0 for none). Unseen alone isn't enough: All holds back first-
   * page results it can't place yet, and an import can add older ones
   * below the top; neither is new at the top. HisterKit's NewItems
   * (Shiori/Core) is the twin, with the same cases.
   */
  /**
   * The wait before a list next asks what's new: doubled while the count
   * stays the same, up to `most`, back to `first` once it changes.
   * The apps' NewItems.wait is the twin, with the same cases.
   */
  function newItemsWait(wait, changed, { first = 60_000, most = 600_000 } = {}) {
    return changed ? first : Math.min(Math.max(wait, first) * 2, most);
  }
  function newItemsCount(candidates, seen, newestShown) {
    return (candidates || []).filter((d) => !seen.has(d.url) && (!newestShown || (Number(d.updated) || 0) > newestShown)).length;
  }

  /**
   * The pages you opened for a search first, then the rest. Hister takes an
   * opened page out of `documents` and sends it only in `history` (it ranks
   * it first), so a list that dropped `history` lost the page from its
   * search. Each entry becomes a result with what it carries (no snippet or
   * label), `opened: true` so a list may mark it; only web addresses, and
   * `keep` leaves out what the list doesn't show (a note, a file). Duplicates
   * go. HisterKit's OpenedFirst, on scripts/opened-first-cases.json.
   */
  function openedFirst(history, documents, keep = () => true) {
    const opened = (history || [])
      .filter((h) => h && typeof h.url === 'string' && /^https?:\/\//i.test(h.url) && keep(h.url))
      .map((h) => ({ url: h.url, title: h.title || '', domain: h.domain || '', added: h.added, updated: h.updated || h.added, opened: true }));
    const seen = new Set();
    return [...opened, ...(documents || [])].filter((d) => d && !seen.has(d.url) && seen.add(d.url));
  }

  /**
   * Two lists that each come newest first, a page at a time, as one (the
   * web app's Library All: pages from Hister, notes from Kura). A result is
   * placed only once the other list's next one is known, or it has ended.
   * HisterKit's NewestFirstMerge, with the same tests.
   */
  function newestFirstMerge() {
    const m = { pages: [], notes: [], pagesDone: false, notesDone: false, pagesKey: null, notesKey: null };
    m.addPages = (docs, next) => ((m.pages.push(...docs), (m.pagesKey = next || null), (m.pagesDone = !next)));
    m.addNotes = (docs, next) => ((m.notes.push(...docs), (m.notesKey = next || null), (m.notesDone = !next)));
    m.endNotes = () => ((m.notesKey = null), (m.notesDone = true));
    m.needsPages = () => !m.pages.length && !m.pagesDone;
    m.needsNotes = () => !m.notes.length && !m.notesDone;
    m.finished = () => !m.pages.length && !m.notes.length && m.pagesDone && m.notesDone;
    m.take = () => {
      const out = [];
      for (;;) {
        if (m.pages.length && m.notes.length) out.push((m.notes[0].updated || 0) > (m.pages[0].updated || 0) ? m.notes.shift() : m.pages.shift());
        else if (m.pages.length && m.notesDone) out.push(m.pages.shift());
        else if (m.notes.length && m.pagesDone) out.push(m.notes.shift());
        else return out;
      }
    };
    return m;
  }

  // --- The Machiya rooms ----------------------------------------------------------

  /**
   * The switcher's rooms, front to back, then the neighbours: each with
   * its colour token (things wear their room's colour); the icons are
   * `.room-icon`s.
   */
  const ROOMS = [
    { key: 'shiori', name: 'Shiori', tint: 'accent' },
    { key: 'konbini', name: 'Konbini', tint: 'konbini' },
    { key: 'niwa', name: 'Niwa', tint: 'niwa' },
    { key: 'kura', name: 'Kura', tint: 'notes' },
    { key: 'hister', name: 'Hister', tint: 'secondary', neighbour: true },
    { key: 'searxng', name: 'SearXNG', tint: 'secondary', neighbour: true },
    // The house itself: Machiya's landing and status page (SHIORI_ROOMS'
    // machiya=…), last, in a section of its own, as vaultkit's menu has it.
    { key: 'machiya', name: 'Machiya', tint: 'accent', house: true },
  ];

  /** Each room's one-word role in the menu, as the rooms say it (vaultkit's switcher). */
  const ROOM_ROLES = { shiori: 'search', konbini: 'board', niwa: 'garden', kura: 'notes', hister: 'pages', searxng: 'the web', machiya: 'home' };

  /** The switcher's glyphs (24-point strokes, each a path's `d`), shared by both web pages: the house, and the menu's gear. */
  const ROOM_GLYPHS = {
    house: ['M3 11l9-7 9 7', 'M5 10v10h14V10', 'M10 20v-6h4v6'],
    // The search fields' buttons, as the rooms' (vaultkit's form.search.bar).
    clear: ['M6 6l12 12', 'M18 6 6 18'],
    search: ['M18 11a7 7 0 1 1-14 0 7 7 0 0 1 14 0z', 'm20 20-4-4'],
    gear: [
      'M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0z',
      'M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z',
    ],
  };

  /** A glyph as an <svg>, built node by node: no markup to parse. */
  function roomGlyph(name) {
    const ns = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('aria-hidden', 'true');
    for (const d of ROOM_GLYPHS[name] || []) {
      const path = document.createElementNS(ns, 'path');
      path.setAttribute('d', d);
      svg.append(path);
    }
    return svg;
  }

  /**
   * A search field's buttons, as the rooms' (vaultkit's form.search.bar)
   * and Kagi's: an X that clears the field (shown once there's text: CSS,
   * `:placeholder-shown`), and a magnifier that submits, as Return does
   * (CSS shows it on phones). Placed after the input, its siblings.
   */
  function fieldButtons(input, submit) {
    const button = (cls, label, glyph) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = `field-button ${cls}`;
      b.title = label;
      b.setAttribute('aria-label', label);
      b.append(roomGlyph(glyph));
      return b;
    };
    const clear = button('field-clear', 'Clear', 'clear');
    const go = button('field-go', 'Search', 'search');
    clear.addEventListener('click', () => {
      input.value = '';
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.focus();
    });
    go.addEventListener('click', () => submit());
    return [clear, go];
  }

  /**
   * The Rooms menu's rows, as the rooms draw theirs (vaultkit's switcher):
   * each room's icon tile (`.room-icon`, from scripts/room-icons.py), its
   * name and its role, the current one not a link but highlighted, "here";
   * the neighbours (Hister, SearXNG: line glyphs) after a rule; then, with
   * `settings` ({href, open}), a rule and Settings with the gear.
   */
  function roomLinks(list, current = 'shiori', { settings = null } = {}) {
    const out = [];
    const rule = () => document.createElement('hr');
    for (const r of list) {
      if (r.neighbour && out.length && !out.some((n) => n.tagName === 'HR')) out.push(rule());
      // The house: after its own rule.
      if (r.house && out.length) out.push(rule());
      const here = r.key === current;
      const row = document.createElement(here ? 'b' : 'a');
      row.className = 'room' + (r.neighbour ? ' neighbour' : '') + (here ? ' here' : '');
      row.dataset.room = r.key;
      row.setAttribute('role', 'menuitem');
      if (here) row.setAttribute('aria-current', 'page');
      else row.href = r.url;
      const iconEl = document.createElement('span');
      iconEl.className = 'room-icon';
      iconEl.dataset.room = r.key;
      iconEl.setAttribute('aria-hidden', 'true');
      const role = document.createElement('small');
      role.textContent = here ? 'here' : ROOM_ROLES[r.key] || '';
      row.append(iconEl, r.name, role);
      out.push(row);
    }
    if (settings) {
      out.push(rule());
      const a = document.createElement('a');
      a.className = 'room settings';
      a.href = settings.href || '#';
      a.setAttribute('role', 'menuitem');
      const glyph = document.createElement('span');
      glyph.className = 'room-glyph';
      glyph.append(roomGlyph('gear'));
      a.append(glyph, 'Settings');
      if (settings.open) a.addEventListener('click', (e) => (e.preventDefault(), settings.open()));
      out.push(a);
    }
    return out;
  }

  /**
   * The switcher: a button and its menu (`.rooms-menu`), closed by a click
   * elsewhere, Escape, the button again, or a choice in it. `tab`: the
   * phone's tab bar's Rooms tab (the house over "Rooms"), whose menu opens
   * above it (CSS); otherwise a house button. Null when there's nowhere
   * else to go.
   */
  function roomsSwitcher(list, current = 'shiori', { settings = null, tab = false } = {}) {
    if (list.filter((r) => r.key !== current).length === 0) return null;
    const wrap = document.createElement('div');
    wrap.className = 'rooms' + (tab ? ' rooms-tab' : '');
    const button = document.createElement('button');
    button.type = 'button';
    button.className = tab ? 'rooms-open' : 'icon-button rooms-open';
    button.title = 'Rooms';
    button.setAttribute('aria-label', 'Rooms');
    button.setAttribute('aria-haspopup', 'menu');
    button.setAttribute('aria-expanded', 'false');
    button.append(roomGlyph('house'));
    if (tab) {
      const label = document.createElement('span');
      label.textContent = 'Rooms';
      button.append(label);
    }
    const menu = document.createElement('div');
    menu.className = 'rooms-menu';
    menu.setAttribute('role', 'menu');
    menu.setAttribute('aria-label', 'Rooms');
    menu.hidden = true;
    menu.append(...roomLinks(list, current, { settings }));
    const show = (open) => ((menu.hidden = !open), button.setAttribute('aria-expanded', String(open)));
    button.addEventListener('click', (e) => (e.stopPropagation(), show(menu.hidden)));
    menu.addEventListener('click', (e) => e.target.closest('a') && show(false));
    // The page's own listeners go with the switcher: the web app redraws
    // its tabs and sidebar, and each drew a new one.
    const outside = (e) => {
      if (!wrap.isConnected) return document.removeEventListener('click', outside);
      if (!wrap.contains(e.target)) show(false);
    };
    const escape = (e) => {
      if (!wrap.isConnected) return document.removeEventListener('keydown', escape);
      if (e.key === 'Escape' && !menu.hidden) (show(false), button.focus());
    };
    document.addEventListener('click', outside);
    document.addEventListener('keydown', escape);
    // Shut on the way out and on the way back: the back/forward cache (always
    // on in an installed app on iOS) brought the page back with it open.
    const away = () => {
      if (!wrap.isConnected) {
        for (const type of ['pageshow', 'popstate', 'pagehide']) window.removeEventListener(type, away);
        return;
      }
      show(false);
    };
    if (typeof window !== 'undefined' && window.addEventListener) {
      for (const type of ['pageshow', 'popstate', 'pagehide']) window.addEventListener(type, away);
    }
    wrap.append(button, menu);
    return wrap;
  }

  /**
   * The rooms this build knows the addresses of, in the switcher's order:
   * `stamped` is "key=url,key=url" (SHIORI_ROOMS, stamped in by the build;
   * the hostnames stay out of the repo). A room without an http(s)
   * address is left out; `here` (the page's own origin) stands in for
   * Shiori when it isn't given.
   */
  function rooms(stamped, here = '') {
    const urls = {};
    const text = String(stamped || '');
    if (!text.startsWith('__')) {
      for (const pair of text.split(',')) {
        const i = pair.indexOf('=');
        if (i > 0) urls[pair.slice(0, i).trim().toLowerCase()] = pair.slice(i + 1).trim();
      }
    }
    if (!urls.shiori && here) urls.shiori = here.endsWith('/') ? here : here + '/';
    return ROOMS.filter((r) => /^https?:\/\/[^/]/.test(urls[r.key] || '')).map((r) => ({ ...r, url: urls[r.key] }));
  }

  /**
   * Where "Open in Hister" goes: Hister's own pages. On a hosted page the
   * Hister API comes through the page's own host, whose `/` is Shiori's
   * page, not Hister's: there it's the rooms' Hister address, and with none
   * '' (no link, rather than one back to this page).
   */
  function histerUIBase(stamped, histerBase, pageOrigin = '') {
    const room = rooms(stamped).find((r) => r.key === 'hister');
    if (room) return room.url.endsWith('/') ? room.url : room.url + '/';
    const base = String(histerBase || '');
    if (!/^https?:\/\/[^/]/.test(base)) return '';
    try {
      if (pageOrigin && new URL(base).origin === pageOrigin) return '';
    } catch (_) {
      return '';
    }
    return base.endsWith('/') ? base : base + '/';
  }

  // --- Small Web: Gemini and Gopher (docs/smallweb.md) -----------------------
  // Through your server's small-web gateway, searched only on submit. HisterKit's SmallWeb.swift is the twin.

  /** The gateway's search URL; '' without a gateway or words. */
  function smallwebSearchURL(base, q, page = 1) {
    const words = String(q || '').trim().replace(/\s+/g, ' ').slice(0, 300);
    if (!base || !words) return '';
    const b = base.endsWith('/') ? base : base + '/';
    return `${b}api/search?${new URLSearchParams({ q: words, page: String(Math.max(1, Math.min(50, page | 0 || 1))) })}`;
  }

  const ENGINES = { tlgs: 'TLGS', kennedy: 'Kennedy', veronica: 'Veronica-2' };

  /**
   * The gateway's reply, checked: results with a gemini:// or gopher://
   * address and an http(s) proxy_url (the rest left out), whether there's
   * more, and the engines that failed, said as the apps say them.
   */
  function smallwebResults(reply) {
    const results = ((reply && reply.results) || []).filter(
      (r) => r && /^(gemini|gopher):\/\//.test(r.url) && /^https?:\/\//.test(r.proxy_url),
    ).map((r) => ({
      ...r,
      title: r.title || r.url,
      place: r.url.replace(/^(gemini|gopher):\/\//, ''),
      scheme: r.scheme || (r.url.startsWith('gopher://') ? 'gopher' : 'gemini'),
      engines: (r.sources && r.sources.length ? r.sources : [r.source]).filter(Boolean).map((e) => ENGINES[e] || e).join(' · '),
    }));
    const engines = (reply && reply.sources) || {};
    const errors = (reply && reply.errors) || {};
    const say = { timeout: 'timed out', 'rate-limited': 'asked to slow down', 'slow-down': 'asked to slow down', unreachable: "couldn't be reached" };
    const failures = Object.keys(errors).sort().map((k) => `${ENGINES[k] || k} ${say[errors[k]] || "didn't answer"}`);
    const more = Object.values(engines).some((e) => e && e.ok && e.next);
    return { results, failures, more };
  }

  /**
   * The web engines that didn't answer a SearXNG search, from its reply's
   * `unresponsive_engines` ([[name, reason], …], or plain names): each
   * name once, in order, blanks and anything else left out. Twin of
   * HisterKit's EngineHealth.names, on scripts/engine-health-cases.json.
   */
  function unansweredEngines(reply) {
    const raw = reply && Array.isArray(reply.unresponsive_engines) ? reply.unresponsive_engines : [];
    const names = [];
    for (const entry of raw) {
      const name = typeof entry === 'string' ? entry : Array.isArray(entry) && typeof entry[0] === 'string' ? entry[0] : '';
      const trimmed = name.trim();
      if (trimmed && !names.includes(trimmed)) names.push(trimmed);
    }
    return names;
  }

  /** The line above the web's results: "No answer from alpha, beta", or "". */
  function engineHealthLine(names) {
    return names && names.length ? `No answer from ${names.join(', ')}` : '';
  }

  /**
   * The snippet in runs, [{text, marked}]: `marks` are [start, end) in
   * Unicode code points (the gateway is Python). Bad offsets are skipped.
   */
  function markRuns(snippet, marks) {
    const chars = [...String(snippet || '')];
    const runs = [];
    let at = 0;
    for (const m of [...(marks || [])].sort((a, b) => (a[0] || 0) - (b[0] || 0))) {
      if (!Array.isArray(m) || m.length !== 2 || m[0] < at || m[0] >= m[1] || m[1] > chars.length) continue;
      if (m[0] > at) runs.push({ text: chars.slice(at, m[0]).join(''), marked: false });
      runs.push({ text: chars.slice(m[0], m[1]).join(''), marked: true });
      at = m[1];
    }
    if (at < chars.length) runs.push({ text: chars.slice(at).join(''), marked: false });
    return runs;
  }

  /**
   * Where a result opens, by the setting: {href, other, direct}. "direct"
   * is the gemini:// or gopher:// link (for an app such as Lagrange), else
   * the gateway's page; `other` is the one not chosen.
   */
  function smallwebOpen(result, mode) {
    const direct = mode === 'direct';
    return { href: direct ? result.url : result.proxy_url, other: direct ? result.proxy_url : result.url, direct };
  }

  // --- Media: music, films and TV (docs/media.md) -----------------------------
  // Your libraries (Jellyfin, Plex) and what you played (Koito for music,
  // Movary for films), one card per item. Every request is a GET to a read
  // endpoint. Private like a work note: never to Hister, a model, a cache, an
  // export or a feed. HisterKit's Media.swift is the twin, on
  // scripts/media-cases.json.

  const MEDIA_NAMES = { jellyfin: 'Jellyfin', plex: 'Plex', koito: 'Koito', movary: 'Movary' };
  const MEDIA_LIBRARIES = ['jellyfin', 'plex'];
  const MEDIA_KINDS = { film: 'Film', show: 'Show', episode: 'Episode', artist: 'Artist', album: 'Album', track: 'Track', video: 'Music Video', collection: 'Collection', playlist: 'Playlist', other: 'Video' };
  const MEDIA_GROUPS = { film: 'films', show: 'tv', episode: 'tv', artist: 'music', album: 'music', track: 'music', video: 'music', collection: 'other', playlist: 'other', other: 'other' };
  const MEDIA_PERIODS = ['week', 'month', 'year', 'all_time'];
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /** A service's address with its trailing slash, or '' (an http(s) address, or a path on this host). */
  function mediaBase(raw) {
    const s = String(raw || '').trim();
    if (!/^https?:\/\/[^/\s]+/.test(s) && !/^\/(?!\/)/.test(s)) return '';
    return s.endsWith('/') ? s : s + '/';
  }

  const mediaEnc = (v) => encodeURIComponent(String(v));
  const mediaQuery = (pairs) => pairs.filter(([, v]) => v !== undefined && v !== null && v !== '').map(([k, v]) => `${k}=${mediaEnc(v)}`).join('&');
  const mediaWords = (q) => String(q || '').trim().replace(/\s+/g, ' ').slice(0, 200);
  const mediaLimit = (n, d) => Math.max(1, Math.min(100, Number.isInteger(n) ? n : d));

  /**
   * One read request's address: `service` and `what` name it, `args` fill
   * it. '' when the base or a needed argument is missing. Every one is a
   * GET; Shiori never writes to these services.
   */
  function mediaRequestURL(service, what, base, args = {}) {
    const b = mediaBase(base);
    if (!b) return '';
    const a = args || {};
    const q = mediaWords(a.q);
    const id = /^[A-Za-z0-9_-]{1,64}$/.test(String(a.id ?? '')) ? String(a.id) : '';
    const user = String(a.user || '');
    const path = (p, pairs = []) => b + p + (pairs.length && mediaQuery(pairs) ? '?' + mediaQuery(pairs) : '');
    switch (`${service}.${what}`) {
      case 'koito.search': return q ? path('apis/web/v1/search', [['q', q]]) : '';
      case 'koito.listens': return path('apis/web/v1/listens', [['period', 'all_time'], ['limit', mediaLimit(a.limit, 10)]]);
      case 'koito.nowPlaying': return path('apis/web/v1/now-playing');
      case 'koito.top': {
        if (!['artists', 'albums', 'tracks'].includes(a.kind)) return '';
        const period = MEDIA_PERIODS.includes(a.period) ? a.period : 'month';
        return path(`apis/web/v1/top/${a.kind}`, [['period', period], ['limit', mediaLimit(a.limit, 10)]]);
      }
      case 'koito.item': return ['track', 'album', 'artist'].includes(a.kind) && id ? path(`apis/web/v1/${a.kind}/${id}`) : '';
      case 'koito.last': return ['track', 'album', 'artist'].includes(a.kind) && id ? path('apis/web/v1/listens', [['period', 'all_time'], ['limit', 1], [`${a.kind}_id`, id]]) : '';
      case 'movary.me': return path('api/authentication/token');
      case 'movary.played': return user && q ? path(`api/users/${mediaEnc(user)}/played/movies`, [['search', q], ['limit', mediaLimit(a.limit, 30)]]) : '';
      case 'movary.history': return user ? path(`api/users/${mediaEnc(user)}/history/movies`, [['limit', mediaLimit(a.limit, 10)], ['page', 1]]) : '';
      case 'movary.watchlist': return user ? path(`api/users/${mediaEnc(user)}/watchlist/movies`, [['limit', mediaLimit(a.limit, 10)], ['sortBy', 'addedAt'], ['sortOrder', 'desc']]) : '';
      case 'jellyfin.me': return path('Users/Me');
      case 'jellyfin.search': return user && q ? path(`Users/${mediaEnc(user)}/Items`, [['searchTerm', q], ['Recursive', 'true'], ['Limit', mediaLimit(a.limit, 40)],
        ['Fields', 'ProviderIds,ProductionYear,DateCreated'], ['IncludeItemTypes', 'Movie,Series,Episode,MusicArtist,MusicAlbum,Audio,MusicVideo,BoxSet,Playlist,Video,AudioBook'],
        ['EnableTotalRecordCount', 'false']]) : '';
      case 'jellyfin.latest': return user ? path(`Users/${mediaEnc(user)}/Items/Latest`, [['Limit', mediaLimit(a.limit, 10)], ['Fields', 'ProviderIds,ProductionYear,DateCreated']]) : '';
      case 'plex.identity': return path('identity');
      case 'plex.search': return q ? path('hubs/search', [['query', q], ['limit', mediaLimit(a.limit, 10)], ['includeGuids', 1]]) : '';
      case 'plex.recent': return path('library/recentlyAdded', [['X-Plex-Container-Start', 0], ['X-Plex-Container-Size', mediaLimit(a.limit, 10)], ['includeGuids', 1]]);
      default: return '';
    }
  }

  // Values from a reply: never trusted to be the type they should be.
  const mStr = (v) => (typeof v === 'string' ? v.trim() : typeof v === 'number' && Number.isFinite(v) ? String(v) : '');
  const mInt = (v) => (typeof v === 'number' && Number.isFinite(v) ? Math.trunc(v) : typeof v === 'string' && /^-?\d+$/.test(v.trim()) ? parseInt(v, 10) : null);
  const mNum = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : typeof v === 'string' && /^-?\d+(\.\d+)?$/.test(v.trim()) ? parseFloat(v) : null);
  const mArr = (v) => (Array.isArray(v) ? v : []);
  const mObj = (v) => (v && typeof v === 'object' && !Array.isArray(v) ? v : {});
  const mYear = (v) => { const n = mInt(v); return n && n > 1800 && n < 3000 ? n : null; };
  /**
   * Unix seconds from an ISO time (no zone reads as UTC; fractions dropped),
   * or from a plain date (noon UTC, so the day reads the same in every zone).
   */
  function mTime(v) {
    const m = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?$/.exec(mStr(v));
    if (!m) return null;
    const [y, mo, d, h, mi, sec] = [1, 2, 3, 4, 5, 6].map((i) => parseInt(m[i] || '0', 10));
    if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || sec > 60) return null;
    if (m[4] === undefined) return Date.UTC(y, mo - 1, d, 12) / 1000;
    let zone = 0;
    if (m[7] && m[7] !== 'Z') {
      const z = m[7].replace(':', '');
      zone = (z[0] === '-' ? -1 : 1) * (parseInt(z.slice(1, 3), 10) * 60 + parseInt(z.slice(3, 5), 10));
    }
    return Date.UTC(y, mo - 1, d, h, mi, sec) / 1000 - zone * 60;
  }
  const mUnix = (v) => { const n = mInt(v); return n && n > 0 ? n : null; };

  /** An item with its empty fields left out, so both twins write the same object. */
  function mediaItem(fields) {
    const out = {};
    for (const [k, v] of Object.entries(fields)) {
      if (v === undefined || v === null || v === '' || v === false) continue;
      if (Array.isArray(v) && !v.length) continue;
      if (typeof v === 'object' && !Array.isArray(v) && !Object.keys(v).length) continue;
      out[k] = v;
    }
    return out;
  }

  function mediaIds(pairs) {
    const ids = {};
    for (const [k, raw] of pairs) {
      let v = mStr(raw).toLowerCase();
      if (!v || ids[k]) continue;
      if (k === 'imdb' && !/^tt\d+$/.test(v)) continue;
      if ((k === 'tmdb' || k === 'tvdb') && !/^\d+$/.test(v)) continue;
      if (k === 'mbid' && !/^[0-9a-f-]{36}$/.test(v)) continue;
      ids[k] = v;
    }
    return ids;
  }

  /** An image on the service's own address (a relative path joined to `api`), or TMDB's: anything else is dropped. */
  function mediaImageURL(raw, ctx) {
    const s = mStr(raw);
    const api = mediaBase(ctx && ctx.api);
    if (!s || !api) return '';
    if (/^\/[^/]/.test(s)) return api + s.slice(1);
    if (/^https:\/\/image\.tmdb\.org\/t\/p\/[\w/.-]+$/.test(s)) return s;
    const link = mediaBase(ctx && ctx.link);
    if (link && /^https?:/.test(link) && s.startsWith(link) && !/\.\.|[?#]/.test(s.slice(link.length))) return api + s.slice(link.length);
    return '';
  }

  /** A score to one decimal, halves up ("7.3" for 7.25), as the Swift twin writes it. */
  const score1 = (n) => (Math.round(n * 10) / 10).toFixed(1);

  const by = (list) => mArr(list).map((a) => mStr(a && a.name)).filter(Boolean).join(', ');

  function koitoItem(kind, raw, ctx) {
    const r = mObj(raw);
    const id = mInt(r.id);
    const link = mediaBase(ctx && ctx.link);
    const image = mObj(r.image);
    return mediaItem({
      kind,
      title: mStr(kind === 'artist' ? r.name : r.title),
      by: kind === 'artist' ? '' : by(r.artists),
      ids: mediaIds([['mbid', r.musicbrainz_id]]),
      image: mediaImageURL(image.medium || image.small, ctx),
      source: 'koito',
      sourceId: id ? String(id) : '',
      open: link && id ? { koito: `${link}${kind}/${id}` } : {},
    });
  }

  function movaryFilm(raw, ctx) {
    const m = mObj(raw);
    const ids = mObj(m.ids);
    const link = mediaBase(ctx && ctx.link);
    const movaryId = mInt(ids.movary);
    const tmdb = mNum(mObj(mObj(m.externalRatings).tmdb).average);
    const rating = mInt(m.userRating);
    return mediaItem({
      kind: 'film',
      title: mStr(m.title),
      year: mYear(mStr(m.releaseDate).slice(0, 4)),
      ids: mediaIds([['tmdb', ids.tmdb], ['imdb', ids.imdb]]),
      image: mediaImageURL(m.posterPath || (m.tmdbPosterPath ? 'https://image.tmdb.org/t/p/w342' + mStr(m.tmdbPosterPath) : ''), ctx),
      rating: rating && rating > 0 && rating <= 10 ? rating : null,
      ratingFrom: rating && rating > 0 && rating <= 10 ? 'movary' : '',
      outside: tmdb && tmdb > 0 ? [{ name: 'TMDB', score: score1(tmdb) }] : [],
      source: 'movary',
      sourceId: movaryId ? String(movaryId) : '',
      open: link && movaryId && ctx.user ? { movary: `${link}users/${mediaEnc(ctx.user)}/movies/${movaryId}` } : {},
    });
  }

  const JELLYFIN_KINDS = { Movie: 'film', Series: 'show', Episode: 'episode', MusicArtist: 'artist', MusicAlbum: 'album', Audio: 'track', MusicVideo: 'video', BoxSet: 'collection', Playlist: 'playlist', Video: 'other', AudioBook: 'other' };
  const PLEX_KINDS = { movie: 'film', show: 'show', episode: 'episode', artist: 'artist', album: 'album', track: 'track', clip: 'video', collection: 'collection', playlist: 'playlist' };

  const episodeContext = (season, episode) => {
    const s = mInt(season), e = mInt(episode);
    return [s !== null ? `S${s}` : '', e !== null ? `E${e}` : ''].filter(Boolean).join(' · ');
  };

  function jellyfinItem(raw, ctx) {
    const r = mObj(raw);
    const kind = JELLYFIN_KINDS[r.Type];
    const id = mStr(r.Id);
    if (!kind || !/^[0-9a-f]{32}$/i.test(id)) return null;
    const p = mObj(r.ProviderIds);
    const mb = kind === 'album' ? p.MusicBrainzAlbum : kind === 'artist' ? p.MusicBrainzArtist : kind === 'track' ? p.MusicBrainzTrack : '';
    const tags = mObj(r.ImageTags);
    const api = mediaBase(ctx && ctx.api);
    let image = '';
    if (api && mStr(tags.Primary)) image = `${api}Items/${id}/Images/Primary?tag=${mediaEnc(mStr(tags.Primary))}&maxWidth=300`;
    else if (api && kind === 'track' && /^[0-9a-f]{32}$/i.test(mStr(r.AlbumId)) && mStr(r.AlbumPrimaryImageTag)) {
      image = `${api}Items/${mStr(r.AlbumId)}/Images/Primary?tag=${mediaEnc(mStr(r.AlbumPrimaryImageTag))}&maxWidth=300`;
    }
    const link = mediaBase(ctx && ctx.link);
    const server = mStr(ctx && ctx.serverId);
    return mediaItem({
      kind,
      title: mStr(r.Name),
      by: kind === 'episode' ? mStr(r.SeriesName) : ['album', 'track', 'video'].includes(kind) ? (mStr(r.AlbumArtist) || mArr(r.Artists).map(mStr).filter(Boolean).join(', ')) : '',
      context: kind === 'track' ? mStr(r.Album) : kind === 'episode' ? episodeContext(r.ParentIndexNumber, r.IndexNumber) : '',
      year: mYear(r.ProductionYear),
      ids: mediaIds([['tmdb', p.Tmdb], ['imdb', p.Imdb], ['tvdb', p.Tvdb], ['mbid', mb]]),
      image,
      added: mTime(r.DateCreated),
      inLibrary: true,
      source: 'jellyfin',
      sourceId: id,
      open: link && server ? { jellyfin: `${link}web/#/details?id=${id}&serverId=${mediaEnc(server)}` } : {},
    });
  }

  /** Plex's rating images ("rottentomatoes://image.rating.ripe") to the name shown and the score as it reads there. */
  function plexOutside(value, image) {
    const n = mNum(value);
    const img = mStr(image);
    if (!n || n <= 0) return null;
    if (img.startsWith('imdb://')) return { name: 'IMDb', score: score1(n) };
    if (img.startsWith('themoviedb://')) return { name: 'TMDB', score: score1(n) };
    if (/^rottentomatoes:\/\/image\.rating\.(ripe|rotten|certified)/.test(img)) return { name: 'RT', score: `${Math.round(n * 10)}%` };
    if (/^rottentomatoes:\/\/image\.rating\.(upright|spilled)/.test(img)) return { name: 'RT Audience', score: `${Math.round(n * 10)}%` };
    return null;
  }

  function plexItem(raw, ctx) {
    const r = mObj(raw);
    const kind = PLEX_KINDS[r.type];
    const key = mStr(r.ratingKey);
    if (!kind || !/^\d+$/.test(key)) return null;
    const guid = (scheme) => {
      const g = mArr(r.Guid).map((x) => mStr(x && x.id)).find((x) => x.startsWith(scheme + '://'));
      return g ? g.slice(scheme.length + 3) : '';
    };
    const api = mediaBase(ctx && ctx.api);
    const thumb = mStr(r.thumb) || mStr(r.parentThumb) || mStr(r.grandparentThumb);
    const link = mediaBase(ctx && ctx.link);
    const machine = mStr(ctx && ctx.machine);
    const rating = mNum(r.userRating);
    const show = kind === 'show';
    const views = mInt(show ? r.viewedLeafCount : r.viewCount);
    const outside = [plexOutside(r.audienceRating, r.audienceRatingImage), plexOutside(r.rating, r.ratingImage)].filter(Boolean);
    return mediaItem({
      kind,
      title: mStr(r.title),
      by: kind === 'track' || kind === 'episode' ? mStr(r.grandparentTitle) : kind === 'album' ? mStr(r.parentTitle) : '',
      context: kind === 'track' ? mStr(r.parentTitle) : kind === 'episode' ? episodeContext(r.parentIndex, r.index) : '',
      year: mYear(r.year) || (kind === 'album' ? mYear(r.parentYear) : null),
      ids: mediaIds([['tmdb', guid('tmdb')], ['imdb', guid('imdb')], ['tvdb', guid('tvdb')], ['mbid', guid('mbid')]]),
      image: api && /^\/library\/metadata\/\d+\/(thumb|art)\/\d+$/.test(thumb) ? api + thumb.slice(1) : '',
      library: mStr(r.librarySectionTitle),
      added: mUnix(r.addedAt),
      inLibrary: true,
      plays: ['collection', 'playlist'].includes(kind) ? null : views !== null && views > 0 ? views : 0,
      last: views !== null && views > 0 ? mUnix(r.lastViewedAt) : null,
      playedFrom: views !== null && views > 0 ? 'plex' : '',
      episodes: show && mInt(r.leafCount) ? { watched: Math.max(0, mInt(r.viewedLeafCount) || 0), total: mInt(r.leafCount) } : {},
      rating: rating && rating > 0 ? Math.min(10, Math.round(rating)) : null,
      ratingFrom: rating && rating > 0 ? 'plex' : '',
      outside,
      source: 'plex',
      sourceId: key,
      open: link && /^[0-9a-f]{20,64}$/i.test(machine) ? { plex: `${link}web/index.html#!/server/${machine}/details?key=${mediaEnc('/library/metadata/' + key)}` } : {},
    });
  }

  const PLEX_SKIP = new Set(['photo', 'photoalbum', 'actor', 'director', 'genre', 'tag', 'place', 'autotag', 'shared', 'season']);

  /**
   * A reply, read: `service.what` as in `mediaRequestURL`. Lists come back
   * as items; `koito.item` as {plays, first}, `koito.last` as {last};
   * `movary.me` {user}, `jellyfin.me` {user, serverId}, `plex.identity`
   * {machine}. Anything it can't read is left out, never trusted.
   */
  function mediaParse(service, what, reply, ctx = {}) {
    const r = mObj(reply);
    switch (`${service}.${what}`) {
      case 'koito.search':
        return [
          ...mArr(r.tracks).map((x) => koitoItem('track', x, ctx)),
          ...mArr(r.albums).map((x) => koitoItem('album', x, ctx)),
          ...mArr(r.artists).map((x) => koitoItem('artist', x, ctx)),
        ].filter((x) => x.title && x.sourceId);
      case 'koito.listens':
        return mArr(r.items).map((x) => {
          const it = koitoItem('track', mObj(x).track, ctx);
          const when = mTime(mObj(x).time);
          return it.title && when ? { ...it, when } : null;
        }).filter(Boolean);
      case 'koito.nowPlaying': {
        if (r.currently_playing !== true) return [];
        const it = koitoItem('track', r.track, ctx);
        return it.title ? [{ ...it, nowPlaying: true }] : [];
      }
      case 'koito.topArtists': case 'koito.topAlbums': case 'koito.topTracks': {
        const kind = { 'koito.topArtists': 'artist', 'koito.topAlbums': 'album', 'koito.topTracks': 'track' }[`${service}.${what}`];
        return mArr(r.items).map((x) => {
          const it = koitoItem(kind, mObj(x).item, ctx);
          const plays = mInt(mObj(mObj(x).item).listen_count);
          return it.title ? mediaItem({ ...it, rank: mInt(mObj(x).rank), plays: plays && plays > 0 ? plays : null, playedFrom: plays && plays > 0 ? 'koito' : '' }) : null;
        }).filter(Boolean);
      }
      case 'koito.item': {
        const plays = mInt(r.listen_count);
        return mediaItem({ plays: plays !== null && plays >= 0 ? plays : null, first: mUnix(r.first_listen) });
      }
      case 'koito.last': return mediaItem({ last: mTime(mObj(mArr(r.items)[0]).time) });
      case 'movary.me': return mediaItem({ user: mStr(mObj(r.user).name) });
      case 'movary.played':
        return mArr(r.played).map((x) => {
          const it = movaryFilm(mObj(x).movie, ctx);
          const dates = mArr(mObj(x).watchDates);
          const plays = dates.reduce((n, d) => n + Math.max(1, mInt(mObj(d).plays) || 1), 0);
          const last = dates.map((d) => mTime(mObj(d).date)).filter(Boolean).sort((a, b) => b - a)[0];
          return it.title ? mediaItem({ ...it, plays: plays || null, last, playedFrom: plays ? 'movary' : '' }) : null;
        }).filter(Boolean);
      case 'movary.history':
        return mArr(r.history).map((x) => {
          const it = movaryFilm(mObj(x).movie, ctx);
          const when = mTime(mObj(x).watchedAt);
          return it.title ? mediaItem({ ...it, when }) : null;
        }).filter(Boolean);
      case 'movary.watchlist':
        return mArr(r.watchlist).map((x) => {
          const it = movaryFilm(mObj(x).movie || x, ctx);
          return it.title ? mediaItem({ ...it, watchlist: true, added: mTime(mObj(x).addedAt) }) : null;
        }).filter(Boolean);
      case 'jellyfin.me': {
        const user = mStr(r.Id), serverId = mStr(r.ServerId);
        return mediaItem({ user: /^[0-9a-f]{32}$/i.test(user) ? user : '', serverId: /^[0-9a-f]{32}$/i.test(serverId) ? serverId : '' });
      }
      case 'jellyfin.search': case 'jellyfin.latest':
        return (Array.isArray(reply) ? reply : mArr(r.Items)).map((x) => jellyfinItem(x, ctx)).filter((x) => x && x.title);
      case 'plex.identity': {
        const machine = mStr(mObj(r.MediaContainer).machineIdentifier);
        return mediaItem({ machine: /^[0-9a-f]{20,64}$/i.test(machine) ? machine : '' });
      }
      case 'plex.search':
        return mArr(mObj(r.MediaContainer).Hub).filter((h) => !PLEX_SKIP.has(mObj(h).type))
          .flatMap((h) => mArr(mObj(h).Metadata)).map((x) => plexItem(x, ctx)).filter((x) => x && x.title);
      case 'plex.recent':
        return mArr(mObj(r.MediaContainer).Metadata).filter((x) => !PLEX_SKIP.has(mObj(x).type)).map((x) => plexItem(x, ctx)).filter((x) => x && x.title);
      default: return [];
    }
  }

  /** A title or name reduced for matching: no case, accents, punctuation or spaces; "&" reads as "and". */
  function mediaNorm(s) {
    return String(s || '').normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase().replace(/&/g, ' and ').replace(/[^\p{L}\p{N}]+/gu, '');
  }

  const MEDIA_ID_KINDS = ['tmdb', 'imdb', 'tvdb', 'mbid'];

  /** Whether two items are the same thing: one shared id, or the same title and artist (or show) and year when neither id disagrees. */
  function mediaSame(a, b) {
    if (a.kind !== b.kind) return false;
    const ia = a.ids || {}, ib = b.ids || {};
    let conflict = false;
    for (const k of MEDIA_ID_KINDS) {
      if (ia[k] && ib[k]) {
        if (ia[k] === ib[k]) return true;
        conflict = true;
      }
    }
    if (conflict) return false;
    const ta = mediaNorm(a.title);
    if (!ta || ta !== mediaNorm(b.title)) return false;
    const ba = mediaNorm(a.by), bb = mediaNorm(b.by);
    if (ba && bb && ba !== bb) return false;
    if (a.year && b.year && a.year !== b.year) return false;
    return true;
  }

  /** 0 the title is the words, 1 it starts with them, 2 holds them, 3 anything else; episodes after all the rest. */
  function mediaRelevance(item, q) {
    const t = mediaNorm(item.title), w = mediaNorm(q);
    const r = !w ? 0 : t === w ? 0 : t.startsWith(w) ? 1 : t.includes(w) ? 2 : 3;
    return item.kind === 'episode' ? 4 + r : r;
  }

  const MEDIA_HISTORY = { film: 'movary', artist: 'koito', album: 'koito', track: 'koito' };

  /**
   * One card per item. `lists` are the services' parsed items (libraries
   * first); `opts.q` the words, `opts.asked` which history services were
   * asked ({movary, koito}). Played comes from Movary (films) or Koito
   * (music) first, the library's own count where they have nothing; a
   * library item no one has a play for is "Never Played" (plays 0), when
   * someone who would know was asked. Ratings: Movary's for films, else
   * Plex's. Library items first, then what you played that isn't in one.
   */
  function mediaMerge(lists, opts = {}) {
    const asked = opts.asked || {};
    const groups = [];
    for (const list of lists || []) {
      for (const item of list || []) {
        if (!item || !item.kind || !item.title) continue;
        const g = groups.find((members) => !members.some((m) => m.source === item.source) && members.some((m) => mediaSame(m, item)));
        if (g) g.push(item);
        else groups.push([item]);
      }
    }
    const merged = groups.map((members, order) => {
      const first = (f) => members.map((m) => m[f]).find((v) => v !== undefined && v !== null && v !== '');
      const lib = members.find((m) => MEDIA_LIBRARIES.includes(m.source));
      const head = lib || members[0];
      const ids = {};
      for (const m of members) for (const k of MEDIA_ID_KINDS) if (m.ids && m.ids[k] && !ids[k]) ids[k] = m.ids[k];
      const open = {};
      for (const m of members) Object.assign(open, m.open || {});
      const historyService = MEDIA_HISTORY[head.kind];
      const history = members.find((m) => m.source === historyService);
      const plex = members.find((m) => m.source === 'plex');
      let played = {};
      if (history && history.plays > 0) played = { plays: history.plays, last: history.last, playedFrom: history.source };
      else if (plex && plex.plays > 0) played = { plays: plex.plays, last: plex.last, playedFrom: 'plex' };
      else if (lib && !['collection', 'playlist'].includes(head.kind) && ((historyService && asked[historyService]) || plex)) played = { plays: 0 };
      else if (!lib && history && history.plays === 0) played = { plays: 0 };
      const rated = (head.kind === 'film' && members.find((m) => m.source === 'movary' && m.rating)) || members.find((m) => m.source === 'plex' && m.rating);
      const outside = [];
      for (const m of members) for (const o of m.outside || []) if (!outside.some((x) => x.name === o.name) && outside.length < 3) outside.push(o);
      return {
        order,
        item: mediaItem({
          key: `${head.kind}:` + (MEDIA_ID_KINDS.map((k) => ids[k] && `${k}:${ids[k]}`).find(Boolean) || `${mediaNorm(head.title)}:${mediaNorm(first('by'))}:${first('year') || ''}`),
          kind: head.kind,
          title: head.title,
          by: head.by || first('by'),
          context: head.context || first('context'),
          year: first('year'),
          ids,
          image: (lib && lib.image) || first('image'),
          library: first('library'),
          added: first('added'),
          inLibrary: !!lib,
          elsewhere: !lib,
          ...played,
          // When it was last heard or watched in a history list (a browse's Recently Listened).
          when: Math.max(0, ...members.map((m) => m.when || 0)) || null,
          sources: [...new Set(members.map((m) => m.source).filter(Boolean))],
          episodes: plex && plex.episodes,
          rating: rated ? rated.rating : null,
          ratingFrom: rated ? rated.ratingFrom : '',
          outside,
          open,
        }),
      };
    });
    const q = opts.q || '';
    merged.sort((a, b) => (a.item.inLibrary ? 0 : 1) - (b.item.inLibrary ? 0 : 1)
      || (q ? mediaRelevance(a.item, q) - mediaRelevance(b.item, q) : (b.item.added || 0) - (a.item.added || 0))
      || a.order - b.order);
    return merged.map((m) => m.item);
  }

  /** The Kind filter's group: films, tv, music or other. */
  const mediaGroup = (item) => MEDIA_GROUPS[item && item.kind] || 'other';

  const MEDIA_DATES = { week: 7, month: 30, year: 365 };

  /**
   * Items the filters keep: `kind` (films, tv, music, other), `played`
   * (never: in a library and never played; played; elsewhere: not in a
   * library), `rated` (loved 8+, liked 6+, any, unrated), `date` (week,
   * month, year: last played within it, older: before a year ago; `now` in
   * unix seconds) and `service` (on Jellyfin, Plex, Koito or Movary).
   */
  function mediaFilter(items, f = {}, now = 0) {
    return (items || []).filter((it) => {
      if (f.kind && mediaGroup(it) !== f.kind) return false;
      if (f.played === 'never' && !(it.inLibrary && it.plays === 0)) return false;
      if (f.played === 'played' && !(it.plays > 0 || it.when)) return false;
      if (f.played === 'elsewhere' && !it.elsewhere) return false;
      if (f.service && !(it.sources || [it.source]).includes(f.service)) return false;
      if (f.date) {
        const at = mediaLastPlayed(it);
        if (!at) return false;
        if (f.date === 'older' ? now - at <= 365 * 86400 : now - at > (MEDIA_DATES[f.date] || 0) * 86400) return false;
      }
      const r = it.rating || 0;
      if (f.rated === 'loved' && r < 8) return false;
      if (f.rated === 'liked' && r < 6) return false;
      if (f.rated === 'any' && r <= 0) return false;
      if (f.rated === 'unrated' && r > 0) return false;
      return true;
    });
  }

  // Sort and Group, as the other pills' (Newest, Oldest, Day…), for what makes sense here.
  const MEDIA_ORDERS = [['best', 'Best Match'], ['newest', 'Newest'], ['oldest', 'Oldest'], ['plays', 'Most Played'],
    ['rating', 'Top Rated'], ['title', 'Title'], ['year', 'Year'], ['added', 'Recently Added']];
  const MEDIA_GROUPINGS = [['', 'No Groups'], ['day', 'Day'], ['month', 'Month'], ['kind', 'Kind'], ['played', 'Played']];
  /** The Filter sheet's sections, each its choices (search-core and the apps show the same). */
  const MEDIA_FILTERS = [
    ['date', 'Date', [['week', 'Past Week'], ['month', 'Past Month'], ['year', 'Past Year'], ['older', 'Older']]],
    ['kind', 'Kind', [['films', 'Films'], ['tv', 'TV'], ['music', 'Music'], ['other', 'Other']]],
    ['played', 'Played', [['played', 'Played'], ['never', 'Never Played'], ['elsewhere', 'Not in Library']]],
    ['rated', 'Rating', [['loved', '4★+'], ['liked', '3★+'], ['any', 'Any Rating'], ['unrated', 'Unrated']]],
    ['service', 'Service', [['jellyfin', 'Jellyfin'], ['plex', 'Plex'], ['koito', 'Koito'], ['movary', 'Movary']]],
  ];

  /** How many items each Filter choice would keep, by section and choice ({date: {week: 3, …}, …}), the other filters held. */
  function mediaFacets(items, f = {}, now = 0) {
    const out = {};
    for (const [key, , choices] of MEDIA_FILTERS) {
      out[key] = {};
      for (const [value] of choices) out[key][value] = mediaFilter(items, { ...f, [key]: value }, now).length;
    }
    return out;
  }
  const MONTH_NAMES = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  /** When it was last played (or listened to, watched): 0 when no one knows. */
  const mediaLastPlayed = (it) => (it && (it.last || it.when)) || 0;

  /**
   * The items in an order: Best Match keeps the merge's; Newest and Oldest
   * by when you last played (the never or unknown after the rest), Most
   * Played, Top Rated (unrated last), Title (A to Z), Recently Added. Ties
   * keep their order.
   */
  function mediaSort(items, order) {
    const list = (items || []).map((item, i) => ({ item, i }));
    const later = (a, b, f, desc) => {
      const x = f(a.item), y = f(b.item);
      if (!x !== !y) return x ? -1 : 1;
      return x === y ? 0 : (desc ? y - x : x - y);
    };
    const cmp = {
      newest: (a, b) => later(a, b, mediaLastPlayed, true),
      oldest: (a, b) => later(a, b, mediaLastPlayed, false),
      plays: (a, b) => later(a, b, (it) => it.plays || 0, true),
      rating: (a, b) => later(a, b, (it) => it.rating || 0, true),
      added: (a, b) => later(a, b, (it) => it.added || 0, true),
      year: (a, b) => later(a, b, (it) => it.year || 0, true),
      title: (a, b) => {
        const x = mediaNorm(a.item.title), y = mediaNorm(b.item.title);
        return x < y ? -1 : x > y ? 1 : 0;
      },
    }[order];
    if (cmp) list.sort((a, b) => cmp(a, b) || a.i - b.i);
    return list.map((x) => x.item);
  }

  /**
   * The items in groups, each {title, items}, in the order they first
   * appear: by Kind (Films, TV, Music, Other) or by the Month you last
   * played them ("October 2026"; "Never Played", or "No Date" when the
   * plays have no date). No grouping: one group with no title.
   */
  function mediaGroups(items, grouping, offsetMinutes = 0) {
    const titleOf = {
      kind: (it) => ({ films: 'Films', tv: 'TV', music: 'Music', other: 'Other' })[mediaGroup(it)],
      day: (it) => {
        const at = mediaLastPlayed(it);
        return at ? mediaDate(at, offsetMinutes) : it.plays === 0 ? 'Never Played' : 'No Date';
      },
      played: (it) => (it.plays > 0 || it.when ? 'Played' : it.elsewhere ? 'Not in Library' : it.plays === 0 ? 'Never Played' : 'Not Known'),
      month: (it) => {
        const at = mediaLastPlayed(it);
        if (!at) return it.plays === 0 ? 'Never Played' : 'No Date';
        const d = new Date((at + (offsetMinutes || 0) * 60) * 1000);
        return `${MONTH_NAMES[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
      },
    }[grouping];
    if (!titleOf) return [{ title: '', items: [...(items || [])] }];
    const groups = [];
    for (const it of items || []) {
      const title = titleOf(it);
      let g = groups.find((x) => x.title === title);
      if (!g) groups.push((g = { title, items: [] }));
      g.items.push(it);
    }
    const ranks = { kind: ['Films', 'TV', 'Music', 'Other'], played: ['Played', 'Never Played', 'Not in Library', 'Not Known'] };
    if (ranks[grouping]) {
      const rank = ranks[grouping];
      groups.sort((a, b) => rank.indexOf(a.title) - rank.indexOf(b.title));
    }
    return groups;
  }

  /** "Mar 6, 2014", at `offsetMinutes` from UTC. */
  function mediaDate(secs, offsetMinutes = 0) {
    const d = new Date((secs + (offsetMinutes || 0) * 60) * 1000);
    return `${MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}, ${d.getUTCFullYear()}`;
  }

  /**
   * What a card says about playing it: "Played 3× · Last Mar 6, 2014",
   * "Played Mar 6, 2014", "Played 8 of 8 Episodes", "Never Played", with
   * "Not in Library" before it for a search's match that isn't in a library
   * (`elsewhere`).
   */
  function mediaPlayedLine(item, offsetMinutes = 0) {
    const it = item || {};
    const parts = [];
    if (it.nowPlaying) return 'Now Playing';
    if (it.when) return (MEDIA_GROUPS[it.kind] === 'music' ? 'Listened ' : 'Watched ') + mediaDate(it.when, offsetMinutes);
    if (it.elsewhere) parts.push('Not in Library');
    if (it.episodes && it.episodes.total) {
      parts.push(it.episodes.watched ? `Played ${it.episodes.watched} of ${it.episodes.total} Episodes` : 'Never Played');
      if (it.episodes.watched && it.last) parts.push(`Last ${mediaDate(it.last, offsetMinutes)}`);
    } else if (it.plays > 0) {
      if (it.plays === 1 && it.last) parts.push(`Played ${mediaDate(it.last, offsetMinutes)}`);
      else {
        parts.push(`Played ${it.plays}×`);
        if (it.last) parts.push(`Last ${mediaDate(it.last, offsetMinutes)}`);
      }
    } else if (it.plays === 0) parts.push('Never Played');
    return parts.join(' · ');
  }

  /** Your rating as five stars with halves ("★★★★½" for 9); '' when unrated. */
  function mediaStars(rating) {
    const r = Math.round(Number(rating) || 0);
    if (r <= 0) return '';
    const n = Math.min(10, r);
    return '★'.repeat(Math.floor(n / 2)) + (n % 2 ? '½' : '');
  }

  /** The others' ratings, quieter: "RT 93% · IMDb 7.8". */
  const mediaOutsideLine = (item) => ((item && item.outside) || []).map((o) => `${o.name} ${o.score}`).join(' · ');

  /** "Film · 1979", "Track · Artist · Album", "Episode · Show · S1 · E2". */
  function mediaSubtitle(item) {
    const it = item || {};
    return [MEDIA_KINDS[it.kind] || '', it.by || '', it.context || '', it.year ? String(it.year) : ''].filter(Boolean).join(' · ');
  }

  /**
   * Where a card opens and its other places: {href, places: [{key, name, url}]}.
   * Films and TV open in Plex first, then Movary, then Jellyfin; everything
   * else in Koito or Movary first (the history), then Jellyfin, then Plex.
   * The outside sites (IMDb, TMDB, Letterboxd, MusicBrainz) are links only,
   * never fetched.
   */
  function mediaPlaces(item) {
    const it = item || {};
    const open = it.open || {};
    const ids = it.ids || {};
    const places = [];
    const video = ['film', 'collection', 'show', 'episode'].includes(it.kind);
    for (const key of video ? ['plex', 'movary', 'jellyfin', 'koito'] : ['koito', 'movary', 'jellyfin', 'plex']) if (/^https?:\/\//.test(open[key] || '')) places.push({ key, name: MEDIA_NAMES[key], url: open[key] });
    const film = it.kind === 'film' || it.kind === 'collection';
    const tv = it.kind === 'show' || it.kind === 'episode';
    if (ids.imdb && (film || tv)) places.push({ key: 'imdb', name: 'IMDb', url: `https://www.imdb.com/title/${ids.imdb}/` });
    if (ids.tmdb && it.kind === 'film') places.push({ key: 'tmdb', name: 'TMDB', url: `https://www.themoviedb.org/movie/${ids.tmdb}` });
    if (ids.tmdb && it.kind === 'show') places.push({ key: 'tmdb', name: 'TMDB', url: `https://www.themoviedb.org/tv/${ids.tmdb}` });
    if (ids.tmdb && it.kind === 'film') places.push({ key: 'letterboxd', name: 'Letterboxd', url: `https://letterboxd.com/tmdb/${ids.tmdb}/` });
    const mb = { artist: 'artist', album: 'release', track: 'recording' }[it.kind];
    if (ids.mbid && mb) places.push({ key: 'musicbrainz', name: 'MusicBrainz', url: `https://musicbrainz.org/${mb}/${ids.mbid}` });
    const own = places.filter((p) => MEDIA_NAMES[p.key]);
    return { href: own.length ? own[0].url : '', places };
  }

  /**
   * The media services a hosted page has, from the build's
   * "jellyfin=https://…/,plex=…" (each one's address for links); each is
   * reached through this host's own /<name>/ route, which adds its token.
   */
  function mediaServicesFromBuild(stamp, root) {
    const out = {};
    const s = String(stamp || '');
    if (!s || s.startsWith('__')) return out;
    const base = mediaBase(root || '/');
    for (const pair of s.split(',')) {
      const i = pair.indexOf('=');
      const name = pair.slice(0, i).trim().toLowerCase();
      const link = mediaBase(pair.slice(i + 1));
      if (i > 0 && MEDIA_NAMES[name] && /^https?:/.test(link)) out[name] = { api: `${base}${name}/`, link };
    }
    return out;
  }

  const mediaConfigured = (services) => Object.keys(services || {}).some((k) => MEDIA_NAMES[k] && services[k] && mediaBase(services[k].api));

  /** "Plex didn't answer", or "Plex refused Shiori's token" for a 401 or 403. */
  function mediaFailure(service, error) {
    const status = error && error.status;
    return `${MEDIA_NAMES[service] || service} ${status === 401 || status === 403 ? "refused Shiori's token" : "didn't answer"}`;
  }

  /**
   * Each service's own facts a request needs (Movary's user, Jellyfin's
   * user and server, Plex's machine), asked once and kept on `services`.
   */
  async function mediaFacts(services, get) {
    const asks = [];
    const s = services || {};
    const fact = (service, what, have) => {
      if (!s[service] || s[service][have]) return;
      delete s[service].factError;
      asks.push(get(service, mediaRequestURL(service, what, s[service].api))
        .then((r) => Object.assign(s[service], mediaParse(service, what, r)))
        .catch((e) => { s[service].factError = e; }));
    };
    fact('movary', 'me', 'user');
    fact('jellyfin', 'me', 'user');
    fact('plex', 'identity', 'machine');
    await Promise.allSettled(asks);
  }

  /** How many of Koito's matches get their play counts asked (one request each, two when played). */
  const KOITO_COUNTS = 12;

  /**
   * A search across every service set up: `get(service, url)` fetches one
   * reply as JSON (throwing, with `status`, on failure). One failing never
   * fails the search: {items, failures}. Searched on submit only.
   */
  async function mediaSearch(services, q, get, opts = {}) {
    const s = services || {};
    const words = mediaWords(q);
    const failures = [];
    if (!words || !mediaConfigured(s)) return { items: [], failures };
    await mediaFacts(s, get);
    const ask = async (service, what, args) => {
      if (!s[service]) return null;
      const url = mediaRequestURL(service, what, s[service].api, args);
      if (!url) {
        failures.push(mediaFailure(service, s[service].factError));
        return null;
      }
      try {
        return mediaParse(service, what, await get(service, url), s[service]);
      } catch (e) {
        failures.push(mediaFailure(service, e));
        return null;
      }
    };
    const [jf, plex, koito, movary] = await Promise.all([
      ask('jellyfin', 'search', { user: s.jellyfin && s.jellyfin.user, q: words, limit: opts.limit || 40 }),
      ask('plex', 'search', { q: words, limit: 10 }),
      ask('koito', 'search', { q: words }),
      ask('movary', 'played', { user: s.movary && s.movary.user, q: words, limit: 30 }),
    ]);
    if (koito && koito.length) {
      await Promise.allSettled(koito.slice(0, KOITO_COUNTS).map(async (it) => {
        const one = (what) => get('koito', mediaRequestURL('koito', what, s.koito.api, { kind: it.kind, id: it.sourceId }))
          .then((r) => mediaParse('koito', what, r));
        const detail = await one('item');
        if (detail.plays === undefined) return;
        it.plays = detail.plays;
        if (detail.plays > 0) {
          it.playedFrom = 'koito';
          const last = await one('last').catch(() => ({}));
          if (last.last) it.last = last.last;
        }
      }));
    }
    const items = mediaMerge([jf || [], plex || [], koito || [], movary || []], { q: words, asked: { koito: !!koito, movary: !!movary } });
    // What you don't own shows only when you played it (or Koito's count wasn't asked).
    return { items: items.filter((it) => it.inLibrary || it.plays !== 0), failures };
  }

  /**
   * The Media tab before a search: what's playing, what you played and
   * watched lately, your top artists, albums and tracks for `opts.period`,
   * your watchlist and what's new in your libraries. {sections, failures}.
   */
  async function mediaBrowse(services, get, opts = {}) {
    const s = services || {};
    const failures = [];
    if (!mediaConfigured(s)) return { sections: {}, failures };
    await mediaFacts(s, get);
    const period = MEDIA_PERIODS.includes(opts.period) ? opts.period : 'month';
    const seen = new Set();
    const ask = async (service, what, args, as = what) => {
      if (!s[service]) return [];
      const url = mediaRequestURL(service, what, s[service].api, args);
      try {
        if (!url) throw s[service].factError || new Error('no address');
        return mediaParse(service, as, await get(service, url), s[service]);
      } catch (e) {
        if (!seen.has(service)) failures.push(mediaFailure(service, e));
        seen.add(service);
        return [];
      }
    };
    const [nowPlaying, listens, watched, artists, albums, tracks, watchlist, jfAdded, plexAdded] = await Promise.all([
      ask('koito', 'nowPlaying'),
      ask('koito', 'listens', { limit: 10 }),
      ask('movary', 'history', { user: s.movary && s.movary.user, limit: 10 }),
      ask('koito', 'top', { kind: 'artists', period, limit: 10 }, 'topArtists'),
      ask('koito', 'top', { kind: 'albums', period, limit: 10 }, 'topAlbums'),
      ask('koito', 'top', { kind: 'tracks', period, limit: 10 }, 'topTracks'),
      ask('movary', 'watchlist', { user: s.movary && s.movary.user, limit: 10 }),
      ask('jellyfin', 'latest', { user: s.jellyfin && s.jellyfin.user, limit: 12 }),
      ask('plex', 'recent', { limit: 12 }),
    ]);
    const added = mediaMerge([jfAdded, plexAdded]).slice(0, 12);
    return { sections: { nowPlaying, listens, watched, artists, albums, tracks, watchlist, added }, period, failures };
  }

  // --- The house's shared settings ------------------------------------------------
  // The Machiya rooms keep theme, text size and which rooms the switcher
  // shows as `machiya_*` cookies on the network's domain, so one choice
  // covers every room on a device (settings stay per device). Shiori's
  // hosted pages read them as their defaults and write them on a change.

  // The house's five text sizes, and the nearest of Shiori's eight, in two
  // sets of steps. `apple` (the search page, whose sizes are the apps'
  // Dynamic Type: "large" is Apple's default, the same as Standard) and
  // `rooms` (the web app, whose steps are the rooms' own: its Large is the
  // house's large, so each of the five reads back as the one written).
  // "system" is Standard in both.
  const HOUSE_STEPS = {
    apple: {
      toSize: { xsmall: 'xSmall', small: 'small', standard: 'system', large: 'xLarge', xlarge: 'xxLarge' },
      toHouse: { xSmall: 'xsmall', small: 'small', medium: 'small', system: 'standard', large: 'standard', xLarge: 'large', xxLarge: 'xlarge', xxxLarge: 'xlarge' },
    },
    rooms: {
      toSize: { xsmall: 'xSmall', small: 'small', standard: 'system', large: 'large', xlarge: 'xLarge' },
      toHouse: { xSmall: 'xsmall', small: 'small', medium: 'small', system: 'standard', large: 'large', xLarge: 'xlarge', xxLarge: 'xlarge', xxxLarge: 'xlarge' },
    },
  };
  const houseSteps = (steps) => HOUSE_STEPS[steps] || HOUSE_STEPS.apple;

  function readCookies(text) {
    const out = {};
    for (const part of String(text || '').split(';')) {
      const i = part.indexOf('=');
      if (i <= 0) continue;
      try {
        out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
      } catch (_) {}
    }
    return out;
  }

  /**
   * The house's settings from `document.cookie`, in Shiori's terms:
   * { theme, palette, textSize, hidden: [room keys] }, each only when set. `mine`
   * is Shiori's own text size: a cookie that's just its house rounding
   * ("medium" is written as "small") doesn't replace it. `steps`: 'apple'
   * (the search page) or 'rooms' (the web app), HOUSE_STEPS.
   */
  function houseSettings(cookieText, { mine = '', steps = 'apple' } = {}) {
    const { toSize, toHouse } = houseSteps(steps);
    const c = readCookies(cookieText);
    const out = { hidden: [] };
    const theme = c.machiya_theme === 'auto' ? 'system' : c.machiya_theme;
    if (['system', 'night', 'day'].includes(theme)) out.theme = theme;
    if (Object.hasOwn(PALETTES, c.machiya_palette)) out.palette = c.machiya_palette;
    const size = c.machiya_textSize;
    if (toSize[size] && toHouse[mine] !== size) out.textSize = toSize[size];
    for (const [name, value] of Object.entries(c)) {
      if (name.startsWith('machiya_show_') && value === 'false') out.hidden.push(name.slice('machiya_show_'.length));
    }
    return out;
  }

  /**
   * The Machiya rooms' ten themes (vaultkit/palettes.py): the key the house
   * shares (cookie machiya_palette, Kura's prefs `palette`), its name, and the
   * browser bar's colour in each variant (the rooms' --dark). The colours
   * themselves are web/app/palettes.css (scripts/palettes.mjs); a test keeps
   * this list and that table the same.
   */
  const PALETTES = {
    'tokyo-night': { name: 'Tokyo Night', night: '#16161e', day: '#d0d5e3' },
    'solarized': { name: 'Solarized', night: '#00212b', day: '#eee8d5' },
    'nord': { name: 'Nord', night: '#272c36', day: '#e5e9f0' },
    'dracula': { name: 'Dracula', night: '#21222c', day: '#f3efdd' },
    'catppuccin': { name: 'Catppuccin', night: '#181825', day: '#e6e9ef' },
    'gruvbox': { name: 'Gruvbox', night: '#1d2021', day: '#ebdbb2' },
    'rose-pine': { name: 'Rosé Pine', night: '#14121d', day: '#f2e9e1' },
    'kanagawa': { name: 'Kanagawa', night: '#16161d', day: '#e5ddb0' },
    'everforest': { name: 'Everforest', night: '#232a2e', day: '#efebd4' },
    'ayu': { name: 'Ayu', night: '#07090d', day: '#f0f0f0' },
  };

  /**
   * The browser bar's colours for a theme, as the rooms set them
   * (vaultkit's shell): one for Night or Day, else a pair the system's
   * light or dark picks. [{content, media}], media '' for none. `palette`:
   * one of PALETTES (Tokyo Night when unknown).
   */
  function themeColorMetas(theme, palette = 'tokyo-night') {
    const bars = PALETTES[palette] || PALETTES['tokyo-night'];
    const NIGHT = bars.night;
    const DAY = bars.day;
    if (theme === 'night') return [{ content: NIGHT, media: '' }];
    if (theme === 'day') return [{ content: DAY, media: '' }];
    return [
      { content: NIGHT, media: '(prefers-color-scheme: dark)' },
      { content: DAY, media: '(prefers-color-scheme: light)' },
    ];
  }

  /** The domain the rooms share: the host less its first label ("shiori.x.ts.net" → "x.ts.net"); '' for an IP or a bare name. */
  function houseDomain(hostname) {
    const h = String(hostname || '').toLowerCase();
    if (!h || /^[\d.]+$/.test(h) || h.includes(':')) return '';
    const labels = h.split('.');
    return labels.length >= 3 ? labels.slice(1).join('.') : '';
  }

  /**
   * The cookie that shares a Shiori setting with the other rooms (theme, palette or
   * textSize), or null for a setting the house doesn't share. `steps` as
   * for houseSettings.
   */
  function houseCookie(key, value, hostname, { steps = 'apple' } = {}) {
    const house = houseValue(key, value, steps);
    if (!house) return null;
    const domain = houseDomain(hostname);
    return `machiya_${key}=${encodeURIComponent(house)}; path=/; max-age=31536000; samesite=lax${domain ? `; domain=${domain}` : ''}`;
  }

  /** A Shiori theme, palette or text size in the house's words ("night", "large"), or '' for one it doesn't share. */
  function houseValue(key, value, steps = 'apple') {
    let house;
    if (key === 'theme' && ['system', 'night', 'day'].includes(value)) house = value;
    else if (key === 'palette' && Object.hasOwn(PALETTES, value)) house = value;
    else if (key === 'textSize' && houseSteps(steps).toHouse[value]) house = houseSteps(steps).toHouse[value];
    return house || '';
  }

  // --- Preferences that follow the person (machiya docs/contracts/prefs.md) --------
  // HisterKit's PrefsSync is the twin; scripts/prefs-sync-cases.json holds the
  // cases both run.

  /** The account's shared keys, as prefs.schema.json lists them. */
  const PREFS_SHARED = {
    theme: ['system', 'day', 'night'],
    palette: Object.keys(PALETTES),
    text_size: ['xsmall', 'small', 'standard', 'large', 'xlarge'],
  };
  const PREFS_DEFAULTS = { theme: 'system', palette: 'tokyo-night', text_size: 'standard', pills: '' };
  // Shiori's own settings that follow the person, as `shiori.<snake_case>`:
  // the results' options (never an address, an AI setting or a device's own).
  // Read when called: the page settings' lists are declared further down.
  // Not the AI Answer switch (AI stays on the device), nor this device's pane or search mode.
  // Listed, not "every flag but": a new switch stays on the device until it's
  // added here and in PrefsSync.flags (prefs-sync-cases.json's followingFlags).
  const PREFS_SHIORI_FLAGS = [
    'combinedSearch', 'showInfobox', 'showRelated', 'showThumbnails', 'histerInGeneral', 'histerTab',
    'vaultInGeneral', 'vaultTab', 'webResults', 'searchHistory', 'previewImages', 'rememberOpened',
    'searchFilters', 'foldRepeats', 'labelSuggestions', 'showOpened', 'smallWebTab',
  ];
  const shioriFlags = () => PREFS_SHIORI_FLAGS;
  const shioriChoices = () => ({ resultStyle: PAGE_CHOICES.resultStyle, smallWebOpen: PAGE_CHOICES.smallWebOpen });
  const PREFS_SHIORI_COUNTS = ['histerCount', 'vaultCount'];
  const snake = (key) => key.replace(/[A-Z]/g, (c) => '_' + c.toLowerCase());
  const shioriKey = (local) => 'shiori.' + snake(local);

  /**
   * "Use This Device's Size" on the web: the cookie machiya_textSizeDevice
   * (the house's words, shared by the rooms in this browser, never sent), as
   * Shiori's size in `steps`; '' when it isn't set.
   */
  function deviceTextSize(cookieText, steps = 'apple') {
    const size = readCookies(cookieText).machiya_textSizeDevice;
    return (size && houseSteps(steps).toSize[size]) || '';
  }

  /** Shiori's pills setting (['all', '-web', …]) as the account's {"order":[…],"hidden":[…]}, compact; '' for none. */
  function pillsToAccount(pills) {
    const clean = pillSetting(pills);
    if (!clean.length) return '';
    return JSON.stringify({ order: clean.map((p) => p.replace(/^-/, '')), hidden: clean.filter((p) => p.startsWith('-')).map((p) => p.slice(1)) });
  }
  /** The account's pills back as Shiori's, or null when it isn't a shape and ids Shiori knows. */
  function pillsFromAccount(value) {
    if (value === '') return [];
    let v;
    try {
      v = JSON.parse(value);
    } catch (_) {
      return null;
    }
    if (!v || !Array.isArray(v.order) || !Array.isArray(v.hidden)) return null;
    const hidden = new Set(v.hidden);
    const out = pillSetting(v.order.map((id) => (hidden.has(id) ? '-' + id : id)));
    return out.length || !v.order.length ? out : null;
  }

  /**
   * Whether a value is one the account may hold for that key and this
   * client may apply: the schema's lists for the shared keys, Shiori's own
   * for its keys. Anything else is never applied (the contract's rule 5).
   */
  function prefsValid(key, value) {
    if (typeof value !== 'string') return false;
    if (PREFS_SHARED[key]) return PREFS_SHARED[key].includes(value);
    if (key === 'pills') return pillsFromAccount(value) !== null;
    const local = Object.entries(prefsShioriKeys()).find(([, k]) => k === key);
    if (!local) return false;
    const [name] = local;
    if (shioriFlags().includes(name)) return value === 'on' || value === 'off';
    if (PREFS_SHIORI_COUNTS.includes(name)) return PAGE_COUNTS.includes(Number(value)) && String(Number(value)) === value;
    return (shioriChoices()[name] || []).includes(value);
  }

  /** Shiori's local setting → its account key, for every one that follows the person. */
  function prefsShioriKeys() {
    const out = {};
    for (const k of [...shioriFlags(), ...PREFS_SHIORI_COUNTS, ...Object.keys(shioriChoices())]) out[k] = shioriKey(k);
    return out;
  }

  /**
   * This client's settings in the account's words, for every key it keeps
   * there: { theme, palette, text_size, pills, 'shiori.show_infobox': 'on', … }.
   * `steps` as for houseSettings. A setting this client has no value for
   * is left out.
   */
  function accountValues(settings, { steps = 'apple' } = {}) {
    const s = settings || {};
    const out = {};
    if (PREFS_SHARED.theme.includes(s.theme)) out.theme = s.theme;
    if (Object.hasOwn(PALETTES, s.palette)) out.palette = s.palette;
    const size = houseValue('textSize', s.textSize, steps);
    if (size) out.text_size = size;
    if (Array.isArray(s.pills)) out.pills = pillsToAccount(s.pills);
    for (const [local, key] of Object.entries(prefsShioriKeys())) {
      const v = s[local];
      if (shioriFlags().includes(local) && typeof v === 'boolean') out[key] = v ? 'on' : 'off';
      else if (PREFS_SHIORI_COUNTS.includes(local) && PAGE_COUNTS.includes(v)) out[key] = String(v);
      else if (shioriChoices()[local] && shioriChoices()[local].includes(v)) out[key] = v;
    }
    return out;
  }

  /**
   * The account's values as Shiori's settings: { theme: 'night', textSize:
   * 'xLarge', showInfobox: false, … }, valid ones only. null removes (back
   * to Shiori's default: `defaults`, local names). `mine` is this device's
   * text size: an account size that is just its house rounding keeps it.
   */
  function localValues(prefs, { steps = 'apple', mine = '', defaults = {} } = {}) {
    const out = {};
    const keys = prefsShioriKeys();
    for (const [key, value] of Object.entries(prefs || {})) {
      if (value === null) {
        if (key === 'text_size') out.textSize = defaults.textSize ?? 'system';
        else if (key === 'theme' || key === 'palette') out[key] = defaults[key] ?? PREFS_DEFAULTS[key];
        else if (key === 'pills') out.pills = [];
        else {
          const local = Object.keys(keys).find((k) => keys[k] === key);
          if (local) out[local] = defaults[local];
        }
        continue;
      }
      if (!prefsValid(key, value)) continue;
      if (key === 'theme' || key === 'palette') out[key] = value;
      else if (key === 'text_size') {
        if (houseSteps(steps).toHouse[mine] !== value) out.textSize = houseSteps(steps).toSize[value];
      } else if (key === 'pills') out.pills = pillsFromAccount(value);
      else {
        const local = Object.keys(keys).find((k) => keys[k] === key);
        if (shioriFlags().includes(local)) out[local] = value === 'on';
        else if (PREFS_SHIORI_COUNTS.includes(local)) out[local] = Number(value);
        else out[local] = value;
      }
    }
    return out;
  }

  /**
   * One contact with the account (the contract's client rules), after any
   * pending change has been sent: `mine` is this client's values now (the
   * account's words, accountValues), `seen` the answer at its last contact
   * ({prefs, updated}, or null), `answer` the account's now. Returns
   * { apply, send }: values to take here (null: back to the default) and
   * values to write there.
   * - The account's value wins, unless it still says exactly what it said
   *   last time while this client now holds something else: then this
   *   client changed it since, and it's sent (rule 3).
   * - A value the account doesn't have yet is sent, once (rule 4), unless
   *   it's the default; one the account had and no longer has was
   *   removed: back to the default.
   * - Unknown values are never applied (rule 5).
   */
  function prefsSync({ mine = {}, seen = null, answer = {} } = {}) {
    const apply = {};
    const send = {};
    const now = (answer && answer.prefs) || {};
    const nowUpdated = (answer && answer.updated) || {};
    const before = (seen && seen.prefs) || {};
    const beforeUpdated = (seen && seen.updated) || {};
    const keys = new Set([...Object.keys(mine), ...Object.keys(now), ...Object.keys(before)]);
    const known = (k) => Object.hasOwn(PREFS_DEFAULTS, k) || Object.values(prefsShioriKeys()).includes(k);
    for (const key of keys) {
      if (!known(key)) continue;
      const theirs = now[key];
      const ours = mine[key];
      if (theirs !== undefined) {
        if (!prefsValid(key, theirs) || theirs === ours) continue;
        const unchanged = seen && before[key] === theirs && beforeUpdated[key] === nowUpdated[key];
        if (unchanged && ours !== undefined) send[key] = ours;
        else apply[key] = theirs;
      } else if (seen && Object.hasOwn(before, key)) {
        apply[key] = null;
      } else if (ours !== undefined && ours !== (PREFS_DEFAULTS[key] ?? '')) {
        send[key] = ours;
      }
    }
    return { apply, send };
  }

  // --- Notes from Kura -------------------------------------------------------------
  // Notes come from Kura's own search (/api/search, /api/recent), never
  // Hister's label:vault. Its replies are turned into Hister's
  // document shape, so every note card and row draws them unchanged.

  /**
   * A search as Kura reads it: words, "phrases", -word, word*, title:,
   * tag:, folder:. Hister's own operators (label:, domain:, url:, dates…)
   * and @collections mean nothing there, so they're dropped, as for the web.
   * '' when nothing's left, or for "*" (Kura's recent list instead).
   */
  function kuraQuery(q) {
    const words = webQuery(q);
    return words === '*' ? '' : prefixLastWord(words);
  }

  /** Kura's RSS of notes (the 50 newest changed, or matching `q`); no prefix: a feed is a saved search. */
  function kuraFeedURL(base, q) {
    if (!base) return null;
    const b = base.endsWith('/') ? base : base + '/';
    const words = webQuery(q);
    return words && words !== '*' ? `${b}feed.xml?q=${encodeURIComponent(words)}` : `${b}feed.xml`;
  }

  /** The URL for a Kura search (or its recent list when `q` is empty). */
  function kuraURL(base, q, { sort = 'relevance', limit = 20, offset = 0, vault = '' } = {}) {
    const text = kuraQuery(q);
    const params = new URLSearchParams({ limit: String(limit), offset: String(offset) });
    // Which vaults (a Notes list only): one name, a list or "all"; none = the default.
    if (vault) params.set('vault', vault);
    if (!text) return `${base}api/recent?${params}`;
    params.set('q', text);
    params.set('sort', sort === 'date' || sort === 'changed' ? 'changed' : 'relevance');
    return `${base}api/search?${params}`;
  }

  /** Kura's reply as Hister's: {documents, total}, each note a label:vault document. */
  function kuraDocuments(reply) {
    const results = (reply && Array.isArray(reply.results) && reply.results) || [];
    return {
      total: Number(reply && reply.total) || results.length,
      documents: results
        .filter((n) => n && typeof n.url === 'string' && /^https?:\/\//i.test(n.url))
        .map((n) => ({
          url: n.url,
          title: n.title || n.path || n.url,
          // Kura's snippet is escaped HTML whose only markup is <mark>, as Hister's.
          text: n.snippet || n.summary || '',
          label: 'vault',
          added: Number(n.created) || 0,
          updated: Number(n.changed) || Number(n.created) || 0,
          metadata: { tags: Array.isArray(n.tags) ? n.tags : [] },
          path: n.path || '',
          vault: n.vault || '',
          card_url: n.card_url || null,
        })),
    };
  }

  /** Edits between two strings, a swap of neighbours counting as one. */
  function swapDistance(a, b) {
    const x = [...a], y = [...b];
    const d = Array.from({ length: x.length + 1 }, (_, i) => [i, ...Array(y.length).fill(0)]);
    for (let j = 1; j <= y.length; j++) d[0][j] = j;
    for (let i = 1; i <= x.length; i++) {
      for (let j = 1; j <= y.length; j++) {
        const cost = x[i - 1] === y[j - 1] ? 0 : 1;
        d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost);
        if (i > 1 && j > 1 && x[i - 1] === y[j - 2] && x[i - 2] === y[j - 1]) d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
      }
    }
    return d[x.length][y.length];
  }

  /**
   * "Did you mean …?": a respelling of `q` from the web's autocomplete and
   * related searches, even when the search found something ("george
   * orewell" finds pages; the web quietly fixes it). Each suggestion's
   * leading words are candidates, compared without spaces, so
   * "rapsberrypi" meets "raspberry pi". Within one edit (two past ten
   * letters, a swapped pair counting once) of what was typed; the closest
   * wins, then the one most suggestions start with. Null when nothing
   * fits, `q` is already right, or it holds operators.
   */
  function didYouMean(q, suggestions) {
    const typed = (q || '').trim().toLowerCase().replace(/\s+/g, ' ');
    if (typed.length < 4 || /[:"'*~()|@!]/.test(typed) || /(^|\s)[-+]/.test(typed)) return null;
    const bare = typed.replace(/ /g, '');
    const room = bare.length >= 10 ? 2 : bare.length >= 5 ? 1 : 0;
    const counts = new Map();
    for (const s of suggestions || []) {
      if (typeof s !== 'string') continue;
      const words = s.trim().toLowerCase().split(/\s+/).filter(Boolean);
      for (let n = 1; n <= words.length; n++) {
        const candidate = words.slice(0, n).join(' ');
        counts.set(candidate, (counts.get(candidate) || 0) + 1);
      }
    }
    let best = null;
    for (const [candidate, count] of counts) {
      const candidateBare = candidate.replace(/ /g, '');
      // A completion ("raspberry pi" → "raspberry pi 5") or a cut
      // ("raspberry") isn't a respelling.
      if (candidate === typed || (candidateBare !== bare && (candidateBare.startsWith(bare) || bare.startsWith(candidateBare)))) continue;
      const distance = swapDistance(bare, candidateBare);
      // Only spacing differs ("raspberrypi"): worth it when the web agrees.
      if (distance > room || (distance === 0 && count < 2)) continue;
      // Word for word, each changed word stays within its own room: two
      // edits in a long query mustn't both land on one short word
      // ("github machiya" isn't "github machine").
      const typedWords = typed.split(' ');
      const candidateWords = candidate.split(' ');
      if (typedWords.length === candidateWords.length
        && typedWords.some((w, i) => swapDistance(w, candidateWords[i]) > (w.length >= 10 ? 2 : w.length >= 5 ? 1 : 0))) continue;
      if (!best || distance < best.distance || (distance === best.distance && count > best.count)) best = { candidate, distance, count };
    }
    return best ? best.candidate : null;
  }

  function vaultQuery(q) {
    return `${q} label:vault`.trim();
  }

  // --- Notes from Kura or from Hister (scripts/notes-source-cases.json) -------------------
  // Kura pushes the default vault's notes (and a shared vault's) into Hister as
  // label:vault documents, never a private vault's. So notes can be read from
  // Hister when there's no Kura, or when the person prefers it: the setting
  // `notesSource` ('kura' | 'hister', '' until chosen). Twins: HisterKit's
  // NotesSource, haiku/core and classic/core, on the same cases.

  /** Where notes come from: the person's choice, else Kura when one is set up; Hister when Kura can't be. */
  function notesSource(choice, kuraConfigured) {
    if (choice === 'hister') return 'hister';
    return kuraConfigured ? 'kura' : 'hister';
  }

  /** Hister's query for notes: the words (the last a prefix), `*` for the newest, and label:vault. */
  function histerNotesText(text) {
    const t = String(text || '').trim();
    const words = !t || t === '*' ? '*' : prefixLastWord(closeQuote(t), { union: true });
    return `${words} label:vault`;
  }

  /**
   * Whether a client may show one of Hister's notes: the default vault's
   * only (the address decides: /v/<vault>/ is another vault's, shared or
   * private, and without Kura a shared vault can't be told from a private
   * one), and only an http(s) address that Kura's reading of it accepts.
   */
  function histerNoteShown(url) {
    if (typeof url !== 'string' || !/^https?:\/\//i.test(url)) return false;
    return kuraPath(url) !== null && noteVault(url) === null;
  }

  /**
   * Hister's reply to histerNotesText as notes, in kuraDocuments' shape: the
   * default vault's alone (histerNoteShown), their path from Kura's
   * metadata.vault_path (else the address), their tags. `total` is Hister's
   * less what this page dropped: Hister can't leave other vaults out itself.
   */
  function histerNoteDocuments(reply) {
    const all = (reply && Array.isArray(reply.documents) && reply.documents) || [];
    const kept = all.filter((d) => d && histerNoteShown(d.url));
    return {
      total: Math.max(0, (Number(reply && reply.total) || all.length) - (all.length - kept.length)),
      documents: kept.map((d) => {
        const meta = (d.metadata && typeof d.metadata === 'object' && d.metadata) || {};
        const added = Number(d.added) || 0;
        return {
          url: d.url,
          title: d.title || d.url,
          text: d.text || '',
          label: 'vault',
          added,
          updated: Number(d.updated) || added,
          metadata: { tags: Array.isArray(meta.tags) ? meta.tags.filter((t) => typeof t === 'string') : [] },
          path: (typeof meta.vault_path === 'string' && meta.vault_path) || notePath(d.url) || '',
          vault: '',
          card_url: null,
        };
      }),
    };
  }

  /**
   * Whether a URL is a vault note's: a Niwa page (/n/…) or a Konbini card
   * (/p/…), on the configured hosts or any niwa./konbini. host. For lists
   * that carry no label (Hister's `history`), where `label:vault` can't tell.
   */
  function isNoteURL(url, niwaBase = '', konbiniBase = '') {
    let u;
    try {
      u = new URL(url);
    } catch (_) {
      return false;
    }
    const under = (base, prefix) => {
      if (!base) return false;
      try {
        const b = new URL(base);
        return u.host === b.host && u.pathname.startsWith(b.pathname.replace(/\/?$/, '/') + prefix);
      } catch (_) {
        return false;
      }
    };
    if (under(niwaBase, 'n/') || under(konbiniBase, 'p/') || (noteVault(url) && under(niwaBase, 'v/'))) return true;
    if (/^kura\./.test(u.host) && noteVault(url)) return true;
    return (/^(niwa|kura)\./.test(u.host) && u.pathname.startsWith('/n/')) || (/^konbini\./.test(u.host) && u.pathname.startsWith('/p/'));
  }

  /** The site a result counts under for folding: its host, "www." aside. */
  function siteOf(doc) {
    let host = doc.domain || '';
    if (!host) {
      try {
        host = new URL(doc.url).host;
      } catch (_) {
        host = '';
      }
    }
    host = host.toLowerCase();
    return host.startsWith('www.') ? host.slice(4) : host;
  }

  /**
   * A list with runs of one site folded, as the app's SiteRuns: a run of
   * `minimum` or more pages from one site in a row shows its first page,
   * then one item that holds the rest. Notes (label vault), files and code never fold.
   * Items: {page} or {folded: site, pages}.
   */
  function siteRuns(docs, minimum = 3) {
    const items = [];
    const key = (d) => (d.label === 'vault' || isLocalFile(d.url) || isCodeDoc(d) ? null : siteOf(d) || null);
    let i = 0;
    while (i < docs.length) {
      const site = key(docs[i]);
      let end = i + 1;
      if (site) while (end < docs.length && key(docs[end]) === site) end++;
      items.push({ page: docs[i] });
      const rest = docs.slice(i + 1, end);
      if (site && rest.length + 1 >= minimum) items.push({ folded: site, pages: rest });
      else for (const d of rest) items.push({ page: d });
      i = end;
    }
    return items;
  }

  // --- Export and feeds, as the app's Export (HisterKit/Export.swift) -------------

  const xml = (t) =>
    String(t ?? '')
      .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '')
      .replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' })[c]);

  /** A CSV field: ' before a leading = + - @, quoted when it must be (RFC 4180). */
  function csvField(value) {
    let v = String(value ?? '');
    if (/^[=+\-@]/.test(v)) v = "'" + v;
    return /[",\r\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v;
  }

  /** "shiori-<slug>.<ext>": letters, digits and single dashes. */
  function exportFileName(title, format) {
    const slug = String(title || '')
      .toLowerCase()
      .replace(/[^\p{L}\p{N}]+/gu, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 60);
    return `shiori-${slug || 'results'}.${format}`;
  }

  /**
   * Pages as a file, the app's formats: JSON (Hister's import shape: url,
   * title, domain, label, added, updated in unix seconds, keys sorted),
   * CSV, or RSS. `pages` carry {url, title, domain, label, added, updated,
   * text} (text: the snippet, as plain text).
   */
  function exportData(pages, format, title, link = '') {
    const secs = (n) => Math.floor(Number(n) || 0);
    if (format === 'json') {
      const rows = pages.map((p) => ({
        added: secs(p.added), domain: p.domain || '', label: p.label || '', title: p.title || '', updated: secs(p.updated), url: p.url,
      }));
      return JSON.stringify(rows, null, 2);
    }
    const iso = (n) => new Date(secs(n) * 1000).toISOString().replace(/\.\d{3}Z$/, 'Z');
    if (format === 'csv') {
      const lines = ['url,title,domain,label,added,updated'];
      for (const p of pages) lines.push([p.url, p.title, p.domain, p.label, iso(p.added), iso(p.updated)].map(csvField).join(','));
      return lines.join('\r\n') + '\r\n';
    }
    const rfc822 = (n) => new Date(secs(n) * 1000).toUTCString().replace('GMT', '+0000');
    let out = `<?xml version="1.0" encoding="UTF-8"?>\n<rss version="2.0"><channel>\n<title>${xml('Shiori – ' + title)}</title>\n<link>${xml(link)}</link>\n<description>${xml('Hister pages for ' + title)}</description>\n`;
    for (const p of pages) {
      out += `<item><title>${xml(p.title || p.url)}</title><link>${xml(p.url)}</link>`;
      out += `<guid isPermaLink="true">${xml(p.url)}</guid><pubDate>${rfc822(p.added)}</pubDate>`;
      if (p.label) out += `<category>${xml(p.label)}</category>`;
      if (p.text) out += `<description>${xml(String(p.text).slice(0, 500))}</description>`;
      out += '</item>\n';
    }
    return out + '</channel></rss>\n';
  }

  /**
   * A list's feed, as the app's AppState.feedURL: a notes list's
   * is Kura's (`kuraBase`), the Library's All Hister's own (`*`), Opened
   * what you opened, else the feed service (`shiori/feed`)
   * without the notes.
   */
  function feedURL(base, { query, title = '', source = 'pages', opened = false, kuraBase = '', feedService = true }) {
    const b = base.endsWith('/') ? base : base + '/';
    if (opened) return `${b}api/history?opened=true&format=rss`;
    if (source === 'notes') return kuraFeedURL(kuraBase, query);
    if (String(query).trim() === '*' && source === 'all') return `${b}api/history?format=rss`;
    if (!feedService) return '';          // a host with no feed service offers no feed for it
    const params = new URLSearchParams({ q: query });
    params.set('exclude_label', 'vault');
    if (title && title !== query) params.set('title', title);
    return `${b}shiori/feed?${params.toString().replace(/\+/g, '%20')}`;
  }

  /** NewsBlur's "add site" page for a feed; null without a NewsBlur address. */
  function newsBlurSubscribeURL(newsBlur, feed) {
    const base = String(newsBlur || '').trim();
    if (!/^https?:\/\/[^/]/.test(base)) return null;
    return `${base.endsWith('/') ? base : base + '/'}?url=${encodeURIComponent(feed)}`;
  }

  /**
   * vi-style keys for a results list (the search page, the web app; the
   * apps have the same set). Maps a key event ({key, shiftKey, metaKey,
   * ctrlKey, altKey, inField, now}) and a small state ({pendingKey, at})
   * to an action and the next state. ⌘K (Ctrl+K off a Mac) goes to the
   * search field from anywhere, a field included. Otherwise in a field only
   * Escape counts, and with Meta, Ctrl or Alt held nothing does (those are
   * the browser's). `gg` and `dd` are the same key twice within 600 ms.
   */
  const VIM_PAIR_MS = 600;
  const VIM_PAIRS = { g: 'top', d: 'delete' };
  const VIM_KEYS = {
    j: 'next', k: 'prev', h: 'tabPrev', l: 'tabNext', o: 'open', Enter: 'open', p: 'preview',
    G: 'bottom', '/': 'focusSearch', Escape: 'escape', y: 'copy', '?': 'help', e: 'label',
  };
  function vimKey(state, event) {
    const e = event || {};
    const now = e.now == null ? Date.now() : e.now;
    const cleared = { pendingKey: null, at: null };
    if ((e.metaKey || e.ctrlKey) && !e.altKey && !e.shiftKey && String(e.key).toLowerCase() === 'k') return { action: 'focusSearch', state: cleared };
    if (e.metaKey || e.ctrlKey || e.altKey) return { action: null, state: cleared };
    if (e.inField) return { action: e.key === 'Escape' ? 'escape' : null, state: cleared };
    if (Object.prototype.hasOwnProperty.call(VIM_PAIRS, e.key)) {
      const st = state || {};
      if (st.pendingKey === e.key && st.at != null && now - st.at <= VIM_PAIR_MS) {
        return { action: VIM_PAIRS[e.key], state: cleared };
      }
      return { action: null, state: { pendingKey: e.key, at: now } };
    }
    const action = Object.prototype.hasOwnProperty.call(VIM_KEYS, e.key) ? VIM_KEYS[e.key] : null;
    return { action, state: cleared };
  }

  /** "5 minutes ago", "yesterday", "just now", for unix seconds. */
  function relativeTime(seconds, now = Date.now()) {
    if (!seconds) return '';
    const diff = seconds - now / 1000;
    const format = new Intl.RelativeTimeFormat('en', { numeric: 'auto' });
    const units = [['year', 31536000], ['month', 2592000], ['week', 604800], ['day', 86400], ['hour', 3600], ['minute', 60]];
    for (const [unit, size] of units) if (Math.abs(diff) >= size) return format.format(Math.round(diff / size), unit);
    return 'just now';
  }

  // --- Summaries on the web (docs/ai.md) -----------------------
  // The AI endpoint's /shiori/ai/summarize, on the page's own host: the
  // hosted search page and the web app only (the extension page has no
  // same-origin route to it, so it never offers Summarize).

  /** A web page may be summarized; a note never (the server refuses them too). */
  function summarizable(url, label) {
    // Another vault's note never, shared or not (its label aside): whether
    // it's still shared would need Kura asked first.
    if (label === 'vault' || noteVault(url) !== null) return false;
    try {
      const u = new URL(url);
      return /^https?:$/.test(u.protocol) && !/^(kura|konbini|niwa)\./i.test(u.hostname);
    } catch (_) {
      return false;
    }
  }

  const AI_PROVIDERS = { anthropic: 'Anthropic', openai: 'OpenAI', local: 'Local Server', apple: 'Apple Intelligence' };

  /** "By Anthropic · from the first part of a long page", as the apps' card says it. */
  function summaryByline(reply) {
    const engine = (reply && reply.engine) || '';
    let text = `By ${AI_PROVIDERS[engine] || engine || 'your server'}`;
    if (reply && reply.partial) text += ' · from the first part of a long page';
    return text;
  }

  /** The summary's opening sentence and its points ("• " lines). */
  function summaryParts(text) {
    const lines = String(text || '')
      .split(/\n+/)
      .map((l) => l.trim())
      .filter(Boolean);
    const isPoint = (l) => /^[•\-*]\s*/.test(l);
    return {
      opening: lines.filter((l) => !isPoint(l)).join(' '),
      points: lines.filter(isPoint).map((l) => l.replace(/^[•\-*]\s*/, '')),
    };
  }

  /** What a failed summary says, from the endpoint's status and error code. */
  function summaryError(status, code, message) {
    switch (code) {
      case 'note':
        return 'Notes are never summarized on the web.';
      case 'not_indexed':
        return "Hister doesn't have this page any more.";
      case 'empty':
        return 'This page has no text to summarize.';
      case 'cap':
        return "Today's summaries are used up. Try again tomorrow.";
      case 'declined':
        return 'The AI declined to summarize this page.';
      case 'unavailable':
        return "The AI didn't answer. Try again in a moment.";
      case 'forbidden':
        return 'Your server refused the request from this page.';
      case 'no_results':
        return 'The web found nothing to answer from.';
      case 'searx':
        return "The web search didn't answer. Try again in a moment.";
      default:
        if (status === 0) return "The server didn't answer. Check your network or VPN, then try again.";
        return message || `Summarize failed (${status}).`;
    }
  }

  /**
   * An AI answer's text as runs: plain text, and citations ([1], [2]…) as
   * `{cite: n}`, so the page can link each to its source.
   */
  function answerRuns(text) {
    const runs = [];
    let last = 0;
    for (const m of String(text || '').matchAll(/\[(\d{1,2})\]/g)) {
      if (m.index > last) runs.push({ text: text.slice(last, m.index) });
      runs.push({ cite: Number(m[1]) });
      last = m.index + m[0].length;
    }
    if (last < String(text || '').length) runs.push({ text: text.slice(last) });
    return runs;
  }

  /** The sources an answer cites, in number order; http(s) only. */
  function citedSources(answer, sources) {
    const cited = new Set(answerRuns(answer).filter((r) => r.cite).map((r) => r.cite));
    return (sources || [])
      .filter((s) => s && cited.has(Number(s.n)) && /^https?:\/\//i.test(s.url || ''))
      .sort((a, b) => a.n - b.n);
  }

  const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: '\u00a0', '#39': "'" };

  /**
   * Entities left in a web result's text: some engines (wiby) send their
   * snippets escaped twice, and the page showed `&#34;Mezzanine&#34;`. The
   * text goes into the page as text, so decoding can't add markup.
   */
  function decodeEntities(text) {
    if (!text || !text.includes('&')) return text || '';
    return text.replace(/&(#x[0-9a-f]{1,6}|#\d{1,7}|[a-z]{2,6});/gi, (whole, name) => {
      if (name[0] === '#') {
        const code = name[1] === 'x' || name[1] === 'X' ? parseInt(name.slice(2), 16) : parseInt(name.slice(1), 10);
        return code > 0 && code < 0x110000 ? String.fromCodePoint(code) : whole;
      }
      return ENTITIES[name.toLowerCase()] ?? whole;
    });
  }

  /**
   * Which ends of a sideways-scrolling row fade out: '' when it all fits,
   * else 'start', 'end' or 'both', for the side(s) with more to scroll to.
   * A pill cut off at the edge looks like a mistake; a fade says there's
   * more. `slack` absorbs the fraction of
   * a pixel a scrolled-to-the-end row can be short by.
   */
  function edgeFade({ scrollLeft = 0, scrollWidth = 0, clientWidth = 0 } = {}, slack = 2) {
    const left = Math.abs(scrollLeft);
    const start = left > slack;
    const end = left + clientWidth < scrollWidth - slack;
    return start && end ? 'both' : start ? 'start' : end ? 'end' : '';
  }

  // --- "wiki" in a search: Wikipedia first, with its Info card --------------------

  const WIKI_WORD = /^(wiki|wikipedia)$/i;

  /**
   * For a web query with "wiki" or "wikipedia" as one of its words (a way
   * of asking for Wikipedia): the query without that
   * word, to find the article by. null when there's no such word, or
   * nothing else to look up.
   */
  function wikiQuery(q) {
    const words = (q || '').split(/\s+/).filter(Boolean);
    if (!words.some((w) => WIKI_WORD.test(w))) return null;
    const rest = words.filter((w) => !WIKI_WORD.test(w)).join(' ');
    return rest || null;
  }

  // Pages that aren't articles: the main page, and namespace pages, whose
  // names are translated ("Faili:Jauza_Gemini.jpg" on sw), so they're known
  // by shape: one word, a colon, then no space ("Talk:Gemini"), where a
  // title with a colon has a space after it ("Batman:_Year_One").
  const WIKI_NOT_ARTICLE = /^(Main_Page$|[^:_]+:(?!_))/;

  /**
   * The first Wikipedia article among web results: { url, title, lang,
   * index }, or null. Only `<lang>.wikipedia.org/wiki/<Title>` (a mobile
   * `.m.` host too); not the portal, the main page or a namespace page. An
   * article in one of `langs` (the reader's, e.g. ["en"]) comes before one
   * in any other language.
   */
  function wikipediaArticle(results, langs = []) {
    const list = results || [];
    const articles = [];
    for (let i = 0; i < list.length; i++) {
      let u;
      try {
        u = new URL(list[i] && list[i].url);
      } catch (_) {
        continue;
      }
      const host = /^([a-z][a-z-]*)\.(?:m\.)?wikipedia\.org$/i.exec(u.hostname);
      const path = /^\/wiki\/([^/]+)$/.exec(u.pathname);
      if (!host || !path || u.search) continue;
      let raw;
      try {
        raw = decodeURIComponent(path[1]);
      } catch (_) {
        continue;
      }
      if (!raw || WIKI_NOT_ARTICLE.test(raw)) continue;
      const lang = host[1].toLowerCase();
      if (lang === 'www') continue;
      articles.push({ url: `https://${lang}.wikipedia.org/wiki/${path[1]}`, title: raw.replace(/_/g, ' '), lang, index: i });
    }
    const wanted = (langs || []).map((l) => String(l).toLowerCase().split('-')[0]);
    return articles.find((a) => wanted.includes(a.lang)) || articles[0] || null;
  }

  /**
   * The results with the article first: moved up when it's there, else put
   * in front from `found` (the result it came from, in another search).
   */
  function wikiFirst(results, article, found) {
    const list = (results || []).slice();
    if (!article) return list;
    const at = list.findIndex((r) => r && normalizeURL(r.url) === normalizeURL(article.url));
    const first = at >= 0 ? list.splice(at, 1)[0] : found || { url: article.url, title: `${article.title} - Wikipedia`, content: '' };
    return [first, ...list];
  }

  /** A value a build stamps in place of `__NAME__`: '' when it wasn't. */
  function fromBuild(value) {
    return typeof value === 'string' && !value.startsWith('__') ? value : '';
  }

  // --- Save This Note's Links -------------------------------------------------------

  /** At most this many links a run (HisterKit's `SaveLinks.cap`). */
  const SAVE_LINKS_CAP = 200;

  /** Web pages, and Gemini and Gopher through the small-web gateway. */
  const SAVE_LINK_SCHEMES = ['http:', 'https:', 'gemini:', 'gopher:'];

  /** A gemini:// or gopher:// link: saved through the gateway, never fetched (HisterKit's `SaveLinks.isSmallWeb`). */
  const isSmallWebLink = (url) => /^(gemini|gopher):\/\//i.test(String(url || ''));

  /**
   * A small-web link compared conservatively: scheme and host lowercased,
   * the default port (1965, 70) dropped, nothing else (`SaveLinks.smallWebKey`).
   */
  function smallWebKey(raw) {
    const m = /^([a-z]+):\/\/([^/:?#]+)(?::(\d+))?(.*)$/i.exec(String(raw || ''));
    if (!m) return String(raw || '');
    const scheme = m[1].toLowerCase();
    const port = m[3] && !((scheme === 'gemini' && m[3] === '1965') || (scheme === 'gopher' && m[3] === '70')) ? `:${m[3]}` : '';
    return `${scheme}://${m[2].toLowerCase()}${port}${m[4]}`;
  }

  /**
   * The links to offer from Kura notes ({path, title, external_links}), in
   * order: http(s) only, each once across all the notes (compared by
   * `normalizeURL`), at most `cap`: [{url, text, notePath, noteTitle}].
   * HisterKit's `SaveLinks.links` is the twin, with the same tests.
   */
  function saveLinkRows(notes, cap = SAVE_LINKS_CAP) {
    const seen = new Set();
    const out = [];
    for (const note of notes || []) {
      for (const link of (note && note.external_links) || []) {
        if (out.length >= cap) return out;
        let u;
        try {
          u = new URL(link.url);
        } catch (_) {
          continue;
        }
        if (!SAVE_LINK_SCHEMES.includes(u.protocol)) continue;
        // Never another vault's page in Kura: it would go to Hister.
        if (noteVault(link.url) !== null) continue;
        const key = isSmallWebLink(link.url) ? smallWebKey(link.url) : normalizeURL(link.url);
        if (seen.has(key)) continue;
        seen.add(key);
        out.push({ url: link.url, text: link.text || '', notePath: note.path, noteTitle: note.title || '' });
      }
    }
    return out;
  }

  /**
   * The note's tags that name an existing label ("lanterns", or a nested
   * "crafts/lanterns", for the label `lanterns`; case aside). Never an invented
   * label. HisterKit's `SaveLinks.labelCandidates` is the twin.
   */
  function tagLabelCandidates(tags, labels) {
    const known = new Map();
    for (const l of labels || []) if (!known.has(l.toLowerCase())) known.set(l.toLowerCase(), l);
    const out = [];
    for (const tag of tags || []) {
      const bare = String(tag).replace(/^#/, '');
      const last = bare.split('/').filter(Boolean).pop() || bare;
      const label = known.get(last.toLowerCase());
      if (label && !out.includes(label)) out.push(label);
    }
    return out;
  }

  /**
   * The source repository to offer (AGPL-3.0 section 13): the build's
   * SHIORI_SOURCE_URL when it's a plain http(s) address (no credentials,
   * no spaces), else '' (and nothing is shown). HisterKit's
   * `SourceLink.url` is the twin, with the same tests.
   */
  function sourceLink(raw) {
    const text = String(raw || '').trim();
    if (!text || /\s/.test(text)) return '';
    try {
      const u = new URL(text);
      if ((u.protocol !== 'http:' && u.protocol !== 'https:') || !u.hostname || u.username || u.password) return '';
      return text;
    } catch (_) {
      return '';
    }
  }

  /** Shiori's license, as the About sections name it. */
  const LICENSE = 'GNU AGPL-3.0-or-later';

  /** Not web pages: packages, archives, disk images, media, PDFs for now (HisterKit's `SaveLinks.fileExtensions`). */
  const FILE_EXTENSIONS = new Set(
    'deb rpm apk pkg dmg exe msi iso img zip tgz gz xz bz2 7z rar tar jar whl png jpg jpeg gif webp mp3 mp4 mkv mov webm pdf'.split(' '),
  );

  /** Whether a link names a file rather than a page, by its path's extension (`SaveLinks.looksLikeFile`). */
  function linkLooksLikeFile(raw) {
    try {
      const m = /\.([A-Za-z0-9]+)$/.exec(new URL(raw).pathname);
      return !!m && FILE_EXTENSIONS.has(m[1].toLowerCase());
    } catch (_) {
      return false;
    }
  }


  // --- Machiya sign-in (the identity file's tokens) ------------------------
  // Twins: HisterKit's Machiya (Machiya.swift). A token (`mch_…` stored,
  // `mcd_…` a paired device) goes as `Authorization: Bearer …` to exactly
  // the configured Kura, Konbini and Niwa, compared by origin: never to
  // Hister, SearXNG or any other host, and never across a redirect.

  /** A pairing code as typed: uppercase, spaces and dashes gone; '' when it can't be one. */
  function machiyaCode(raw) {
    const code = String(raw == null ? '' : raw).replace(/[\s-]+/g, '').toUpperCase();
    return /^[A-Z0-9]{1,64}$/.test(code) ? code : '';
  }

  /** A pasted token, trimmed; '' unless it looks like one (`mch_…` or `mcd_…`, no spaces or line breaks). */
  function machiyaToken(raw) {
    const token = String(raw == null ? '' : raw).trim();
    // The identity file's (mch_, mcd_), the Hister sign-in helper's app
    // session (mhs_, the app's own) and room tokens (mht_, Linux and scripts).
    return /^mc[hd]_[A-Za-z0-9_.-]{8,4096}$/.test(token) || /^mh[st]_[A-Za-z0-9_-]{43}$/.test(token) ? token : '';
  }

  // --- The pills: their order, and which show (a per-device setting) ----------------
  // `pills` holds the keys in the person's order, a hidden one with a
  // leading "-" (["all", "notes", "pages", "-web", …]); keys it doesn't
  // name keep their default places after it. All is never hidden. Each
  // surface lists the pills it has (the search page has no Opened, the
  // apps no Images); its own conditions (Show Opened, a Files folder, Web
  // Results) still apply. HisterKit-free twin: Shared/Settings PillOrder.

  const PILLS = [
    ['all', 'All'], ['pages', 'Pages'], ['notes', 'Notes'], ['web', 'Web'], ['images', 'Images'],
    ['videos', 'Videos'], ['news', 'News'], ['smallweb', 'Small Web'], ['files', 'Files'], ['code', 'Code'], ['media', 'Media'], ['opened', 'Opened'],
  ];
  const PILL_KEYS = PILLS.map(([key]) => key);

  /** The setting, checked: known keys, each once, All shown; [] for anything else. */
  // --- what a page's own Settings may change (SharedSettings.apply's twin) ----

  const PAGE_FLAG_KEYS = [
    'combinedSearch', 'showInfobox', 'showRelated', 'showThumbnails', 'histerInGeneral',
    'histerTab', 'vaultInGeneral', 'vaultTab', 'webResults', 'searchHistory', 'previewPane',
    'previewImages', 'rememberOpened', 'searchFilters', 'semanticSearch', 'foldRepeats',
    'labelSuggestions', 'aiAnswer', 'showOpened', 'smallWebTab',
  ];
  const PAGE_COUNT_KEYS = ['histerCount', 'vaultCount'];
  const PAGE_COUNTS = [3, 5, 10, 20];
  const PAGE_CHOICES = {
    textSize: ['system', 'xSmall', 'small', 'medium', 'large', 'xLarge', 'xxLarge', 'xxxLarge'],
    theme: ['system', 'day', 'night'],
    palette: ['tokyo-night', 'solarized', 'nord', 'dracula', 'catppuccin', 'gruvbox', 'rose-pine', 'kanagawa', 'everforest', 'ayu'],
    resultStyle: ['tint', 'solid', 'bar', 'none'],
    smallWebOpen: ['gateway', 'direct'],
    // This device's own (never the account's): how the pills sit when they don't fit.
    pillRow: ['auto', 'scroll'],
  };

  /**
   * What a page's own Settings (the results page's gear) may keep where no
   * app judges it: SharedSettings.apply's keys, types and values, and never
   * an address (searxngURL, niwaURL, konbiniURL…): those decide where the
   * sign-ins go, so only the app sets them. Anything else is dropped.
   */
  function pageSettings(values) {
    const out = {};
    if (!values || typeof values !== 'object') return out;
    for (const key of PAGE_FLAG_KEYS) if (typeof values[key] === 'boolean') out[key] = values[key];
    for (const key of PAGE_COUNT_KEYS) if (Number.isInteger(values[key]) && PAGE_COUNTS.includes(values[key])) out[key] = values[key];
    for (const [key, allowed] of Object.entries(PAGE_CHOICES)) {
      if (typeof values[key] === 'string' && allowed.includes(values[key])) out[key] = values[key];
    }
    const vault = values.obsidianVault;
    if (typeof vault === 'string' && vault !== '' && [...vault].length <= 200) out.obsidianVault = vault;
    if (Array.isArray(values.pills) && (!values.pills.length || pillSetting(values.pills).length)) out.pills = pillSetting(values.pills);
    return out;
  }

  function pillSetting(raw) {
    if (!Array.isArray(raw) || raw.length > PILL_KEYS.length) return [];
    const out = [];
    const seen = new Set();
    for (const item of raw) {
      if (typeof item !== 'string') return [];
      const hidden = item.startsWith('-');
      const key = hidden ? item.slice(1) : item;
      if (!PILL_KEYS.includes(key) || seen.has(key)) return [];
      seen.add(key);
      out.push(hidden && key !== 'all' ? '-' + key : key);
    }
    return out;
  }

  /** Every pill, [{key, shown}], in the setting's order, then the rest in theirs. */
  function pillList(raw) {
    const setting = pillSetting(raw);
    const named = setting.map((item) => ({ key: item.replace(/^-/, ''), shown: !item.startsWith('-') }));
    const known = new Set(named.map((p) => p.key));
    return [...named, ...PILL_KEYS.filter((key) => !known.has(key)).map((key) => ({ key, shown: true }))];
  }

  /** Of the pills a surface has (`available`, keys), those to show, in order. */
  function orderPills(available, raw) {
    const have = new Set(available);
    return pillList(raw).filter((p) => p.shown && have.has(p.key)).map((p) => p.key);
  }

  /** The setting after moving `key` one place (`by` −1 or 1) among `among`'s keys, or showing/hiding it. */
  function pillsChanged(raw, among, key, { by = 0, shown } = {}) {
    const list = pillList(raw);
    const at = list.findIndex((p) => p.key === key);
    if (at < 0) return pillSetting(raw);
    if (typeof shown === 'boolean' && key !== 'all') list[at].shown = shown;
    if (by) {
      const visible = list.map((p, i) => [p, i]).filter(([p]) => among.includes(p.key));
      const pos = visible.findIndex(([p]) => p.key === key);
      const other = visible[pos + by];
      if (other) [list[at], list[other[1]]] = [list[other[1]], list[at]];
    }
    return list.map((p) => (p.shown ? p.key : '-' + p.key));
  }

  /**
   * The settings' editor for the pills a surface has (`items`: [[key,
   * label]]): each row its name, Move Up, Move Down and a switch.
   * `onChange(next, control)` gets the new setting and the used control's
   * label (to focus it again after a redraw).
   */
  function pillEditor(items, raw, onChange, { doc = globalThis.document, rowClass = 'setting' } = {}) {
    const among = items.map(([key]) => key);
    const label = Object.fromEntries(items);
    const list = doc.createElement('ul');
    list.className = 'pill-editor';
    const shownList = pillList(raw).filter((p) => among.includes(p.key));
    shownList.forEach((p, i) => {
      const row = doc.createElement('li');
      row.className = `${rowClass} pill-row`;
      const name = doc.createElement('span');
      name.className = 'pill-name';
      name.dataset.pill = p.key;
      name.textContent = label[p.key];
      const button = (text, title, by, disabled) => {
        const b = doc.createElement('button');
        b.type = 'button';
        b.className = 'pill-move';
        b.textContent = text;
        b.title = title;
        b.setAttribute('aria-label', title);
        b.disabled = disabled;
        b.addEventListener('click', () => onChange(pillsChanged(raw, among, p.key, { by }), title));
        return b;
      };
      const toggle = doc.createElement('input');
      toggle.type = 'checkbox';
      toggle.setAttribute('role', 'switch');
      toggle.className = 'switch';
      toggle.checked = p.shown;
      toggle.disabled = p.key === 'all';
      toggle.setAttribute('aria-label', `Show ${label[p.key]}`);
      toggle.addEventListener('change', () => onChange(pillsChanged(raw, among, p.key, { shown: toggle.checked }), `Show ${label[p.key]}`));
      row.append(name, button('↑', `Move ${label[p.key]} Up`, -1, i === 0), button('↓', `Move ${label[p.key]} Down`, 1, i === shownList.length - 1), toggle);
      list.append(row);
    });
    return list;
  }

  // --- All: your pages and notes among the web results ------------------------------
  // HisterKit's MixedResults is the twin, with the same tests.

  /**
   * How many of yours follow each of `web` web results, `mine` in all,
   * spread evenly from the first: [1, 0, 1, 0] for 4 and 2, [3, 3] for 2
   * and 6. With no web results there's no slot: they're the whole list.
   */
  function mixCounts(web, mine) {
    const w = Math.max(0, Math.floor(web)), m = Math.max(0, Math.floor(mine));
    if (!w) return [];
    return Array.from({ length: w }, (_, i) => Math.ceil(((i + 1) * m) / w) - Math.ceil((i * m) / w));
  }

  /** Pages and notes taking turns (a page first), then whichever is left. */
  function alternate(pages, notes) {
    const out = [];
    for (let i = 0; i < Math.max(pages.length, notes.length); i++) {
      if (i < pages.length) out.push(pages[i]);
      if (i < notes.length) out.push(notes[i]);
    }
    return out;
  }

  // --- Signing in on the hosted pages (docs/signing-in.md) ----------------------------
  // Behind the hosted pages' nginx, Hister answers through the sign-in
  // helper (hister-login, on Hister's host under /machiya/): a 401 (nginx's
  // auth_request) or 403 (Hister) means "sign in", which sends the page to
  // the helper's sign-in and back; a 500 there means sign-in is
  // unavailable, said in a line, never an error page. Inert where nothing
  // asks: a Hister without users never answers 401 or 403. The extension's
  // page never goes there (it has the token).

  /**
   * The helper's sign-in for this page, back to `back`: from the rooms' Hister address (SHIORI_ROOMS), else ''.
   * With Hister's own sign-in (the shiori-web image without the helper, `__SHIORI_SIGNIN__` = "hister") it is
   * Hister's `/auth` page on this origin, which the host proxies and which returns to the page.
   */
  function histerSignInURL(stamped, here, back) {
    if (fromBuild('__SHIORI_SIGNIN__') === 'hister') return '/auth';
    const hister = rooms(stamped, here).find((r) => r.key === 'hister');
    if (!hister || !/^https:\/\//i.test(hister.url)) return '';
    const base = hister.url.replace(/\/?$/, '/');
    return `${base}machiya/signin?${new URLSearchParams({ return: String(back || '') })}`;
  }

  /** The helper's sessions page (where a browser signs out), or ''; Hister's own profile page (it has Sign Out) in its own sign-in. */
  function histerSessionsURL(stamped, here) {
    if (fromBuild('__SHIORI_SIGNIN__') === 'hister') return '/profile';
    const url = histerSignInURL(stamped, here, '');
    return url ? url.replace(/signin\?.*$/, 'sessions') : '';
  }

  /** Whether this host keeps settings in an account (the helper's /machiya/api/prefs): not with Hister's own sign-in. */
  function accountSync() {
    return fromBuild('__SHIORI_SIGNIN__') !== 'hister';
  }

  /** Whether the Notes tab shows: Kura is set up, or Notes From Hister was chosen (an unset Kura hides it). */
  function notesTabShown(kuraSetUp, notesSource) {
    return !!kuraSetUp || notesSource === 'hister';
  }

  /** What a Hister answer asks of a hosted page: 'signin' (401, 403), 'unavailable' (500), or ''. */
  function signInAsked(status) {
    if (status === 401 || status === 403) return 'signin';
    if (status === 500) return 'unavailable';
    return '';
  }

  /**
   * Who Hister says is signed in, from its /api/profile (read through the
   * hosted page's own host, which signs it in): { state: 'in', name } for
   * 200 with a username, { state: 'out' } for 401/403, else { state:
   * 'none' } (Hister without users answers an empty 200 to anyone: never
   * "signed in").
   */
  function histerAccount(status, json) {
    if (status === 401 || status === 403) return { state: 'out' };
    const name = status === 200 && json && typeof json.username === 'string' ? json.username.trim().slice(0, 64) : '';
    return name ? { state: 'in', name } : { state: 'none' };
  }

  const SIGN_IN_GUARD_MS = 30_000;
  /**
   * Whether to go to the sign-in now: at most once in 30 s per tab (a
   * sign-in that comes back still refused must not loop). `storage` is
   * sessionStorage (or a stand-in); it records the time when true.
   */
  function signInDue(storage, now = Date.now()) {
    let last = 0;
    try {
      last = Number(storage.getItem('shioriSignInAt')) || 0;
    } catch (_) {}
    if (now - last < SIGN_IN_GUARD_MS) return false;
    try {
      storage.setItem('shioriSignInAt', String(now));
    } catch (_) {}
    return true;
  }

  // --- Hister's token (the Hister login's phase 1: docs/signing-in.md) ------------
  // The user's one Hister token, sent as `X-Access-Token` by every Hister
  // caller that holds one: Safari's extension (from the app's Keychain),
  // the apps, Linux. Unset, nothing is sent,
  // as before. Never in a URL, never logged. HisterKit's HisterToken is the
  // twin, with the same tests.

  /** A token as stored: printable ASCII, no spaces, 8 to 512 characters (Hister's own are 26); '' otherwise. */
  function histerToken(raw) {
    const token = String(raw == null ? '' : raw).trim();
    return /^[\x21-\x7e]{8,512}$/.test(token) ? token : '';
  }

  /** `headers` with `X-Access-Token` added when there's a token, else as they are. */
  function histerHeaders(token, headers = {}) {
    const t = histerToken(token);
    return t ? { ...headers, 'X-Access-Token': t } : { ...headers };
  }

  /**
   * A fetch's options for Hister: the token's header where there is one,
   * and then `redirect: 'error'`, so the token never follows a redirect to
   * another host (fetch keeps custom headers across one). Without a token,
   * `init` as given.
   */
  function histerFetchOptions(token, init = {}) {
    const t = histerToken(token);
    if (!t) return { ...init };
    return { ...init, headers: { ...(init.headers || {}), 'X-Access-Token': t }, redirect: 'error' };
  }

  /** A device's label for pairing: no control characters, at most 64 characters, `fallback` when empty. */
  function machiyaDevice(raw, fallback = 'Shiori') {
    const label = [...String(raw == null ? '' : raw).replace(/[\u0000-\u001f\u007f]/g, '').trim()].slice(0, 64).join('').trim();
    return label || fallback;
  }

  /** The Authorization header's value. */
  function machiyaAuthHeader(token) {
    return 'Bearer ' + token;
  }

  /** An address's origin ("https://host:port", default ports dropped), or '' for anything but plain http(s) (a user or password in it counts as not plain). */
  function machiyaOrigin(raw) {
    try {
      const u = new URL(String(raw || '').trim());
      if ((u.protocol !== 'https:' && u.protocol !== 'http:') || u.username || u.password || !u.hostname) return '';
      return u.origin.toLowerCase();
    } catch (_) {
      return '';
    }
  }

  /**
   * The origins a token may go to: the rooms' bases (Kura, Konbini, Niwa;
   * empty or unreadable ones left out), less any origin in `others`
   * (Hister's, SearXNG's): a room sharing an origin with them gets none.
   */
  function machiyaRooms(bases, others = []) {
    const never = new Set((others || []).map(machiyaOrigin).filter(Boolean));
    return [...new Set((bases || []).map(machiyaOrigin).filter((o) => o && !never.has(o)))];
  }

  /** Whether a request to `url` may carry the token: its origin is one of `rooms` (machiyaRooms). */
  function mayCarryMachiyaToken(url, rooms) {
    const origin = machiyaOrigin(url);
    return !!origin && (rooms || []).includes(origin);
  }

  /**
   * A fetch's options for `url`: with the credential's header when the
   * host rule allows it, and then `redirect: 'error'`, so it never
   * follows a redirect anywhere. Everything else (credentials included) as
   * given. Never Hister's token (`X-Access-Token`): it goes to Hister alone.
   */
  function machiyaFetchOptions(url, token, rooms, init = {}) {
    const clean = machiyaToken(token);
    if (!clean || !mayCarryMachiyaToken(url, rooms)) return init;
    const headers = { ...(init.headers || {}) };
    headers.Authorization = machiyaAuthHeader(clean);
    return { ...init, headers, redirect: 'error' };
  }

  /** What a pairing answer means for a person: [kind, message] by status. */
  function machiyaPairError(status) {
    switch (status) {
      case 0: return ['unreachable', "The room didn't answer. Check your network or VPN, then try again."];
      case 400: return ['invalid', "The room didn't take that as a pairing code."];
      case 401: return ['bad-code', 'That code is wrong or has expired. Make a new one with identity pair.'];
      case 404: return ['no-signin', "This room has no sign-in: it runs without Machiya's identity file."];
      case 415: return ['not-json', 'The room wanted JSON and refused the request.'];
      case 429: return ['throttled', 'Too many tries. Wait ten minutes, then try again.'];
      default: return ['server', `The room answered HTTP ${status}.`];
    }
  }

  /**
   * Pairs this device with a code from `identity pair`: POST
   * <base>api/pair {code, device} → {token, principal}. `fetchFn` is the
   * fetch to use (tests pass a fake). Throws an Error with `kind` and
   * `status` (machiyaPairError) when the room says no.
   */
  async function machiyaPair(base, rawCode, device, fetchFn = globalThis.fetch) {
    const fail = (status, kind, message) => {
      const [k, m] = machiyaPairError(status);
      return Object.assign(new Error(message || m), { kind: kind || k, status });
    };
    const code = machiyaCode(rawCode);
    if (!code) throw fail(400, 'invalid', 'Type the code identity pair showed (eight letters and digits).');
    const origin = machiyaOrigin(base);
    if (!origin) throw fail(0, 'no-room', 'Set Kura’s address first.');
    const url = String(base).trim().replace(/\/?$/, '/') + 'api/pair';
    let response;
    try {
      response = await fetchFn(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({ code, device: machiyaDevice(device) }),
        credentials: 'omit',
        redirect: 'error',
      });
    } catch (_) {
      throw fail(0);
    }
    let reply = null;
    try {
      reply = await response.json();
    } catch (_) {}
    if (response.status !== 200) throw fail(response.status);
    const token = machiyaToken(reply && reply.token);
    const principal = reply && typeof reply.principal === 'string' ? reply.principal.slice(0, 64) : '';
    if (!token || !principal) throw fail(200, 'bad-reply', "The room's answer held no token.");
    return { token, principal };
  }

  /**
   * What was typed in Sign in to Machiya's one field: a pasted token
   * ({token}), a pairing code ({code}, normalised), or null for neither.
   */
  function machiyaEntry(raw) {
    const token = machiyaToken(raw);
    if (token) return { token };
    const code = machiyaCode(raw);
    return code ? { code } : null;
  }

  /** The signed-in line: who, from pairing; a pasted token doesn't say. */
  function machiyaStatusText(signIn) {
    if (!signIn || !signIn.token) return 'Not signed in';
    return signIn.principal ? `Signed in as ${signIn.principal}` : 'Signed in with a token';
  }

  /** A room's sign-in page (`<base>signin`), for a 401; '' without a plain http(s) base. */
  function machiyaSignInURL(base) {
    if (!machiyaOrigin(base)) return '';
    return String(base).trim().replace(/\/?$/, '/') + 'signin';
  }

  /**
   * Where a hosted page sends a room's 401. A room on Hister's sign-in says so
   * (its reply names the helper's `signin`): the helper's sign-in for this
   * page's own host, whose room cookie /kura/ and /konbini/ pass on (the
   * room's own /signin would sign in the room's host only). Else the room's
   * own /signin (the identity file's cookie covers this host). '' for neither.
   */
  function roomSignInURL(helperSignIn, roomBase, stamped, here, back) {
    return (helperSignIn && histerSignInURL(stamped, here, back)) || machiyaSignInURL(roomBase);
  }

  root.ShioriSearch = {
    machiyaCode,
    machiyaToken,
    machiyaDevice,
    machiyaAuthHeader,
    machiyaOrigin,
    machiyaRooms,
    mayCarryMachiyaToken,
    machiyaFetchOptions,
    machiyaPairError,
    machiyaPair,
    machiyaSignInURL,
    roomSignInURL,
    machiyaEntry,
    machiyaStatusText,
    isSmallWebLink,
    smallWebKey,
    vaultChip,
    linkLooksLikeFile,
    sourceLink,
    LICENSE,
    saveLinkRows,
    tagLabelCandidates,
    fromBuild,
    isCollectionKeyword,
    wikiQuery,
    wikipediaArticle,
    wikiFirst,
    edgeFade,
    kuraQuery,
    kuraURL,
    kuraDocuments,
    typeAhead,
    didYouMean,
    answerRuns,
    citedSources,
    decodeEntities,
    summarizable,
    summaryByline,
    summaryParts,
    summaryError,
    notePath,
    obsidianURL,
    readerURL,
    kuraTagURL,
    niwaURL,
    konbiniURL,
    vaultQuery,
    notesSource,
    histerNotesText,
    histerNoteShown,
    histerNoteDocuments,
    isNoteURL,
    siteOf,
    siteRuns,
    relativeTime,
    vimKey,
    csvField,
    exportFileName,
    exportData,
    feedURL,
    kuraFeedURL,
    noteVault,
    kuraPath,
    isPrivateNote,
    isPrivateNoteNow,
    loadVaults,
    useVaults,
    mediaBase,
    mediaRequestURL,
    mediaParse,
    mediaImageURL,
    mediaNorm,
    mediaSame,
    mediaMerge,
    mediaGroup,
    mediaFilter,
    mediaSort,
    mediaGroups,
    mediaFacets,
    MEDIA_FILTERS,
    MEDIA_ORDERS,
    MEDIA_GROUPINGS,
    mediaDate,
    mediaPlayedLine,
    mediaStars,
    mediaOutsideLine,
    mediaSubtitle,
    mediaPlaces,
    mediaServicesFromBuild,
    mediaConfigured,
    mediaFailure,
    mediaFacts,
    mediaSearch,
    mediaBrowse,
    smallwebSearchURL,
    histerUIBase,
    smallwebResults,
    unansweredEngines,
    engineHealthLine,
    markRuns,
    smallwebOpen,
    rooms,
    houseSettings,
    PREFS_SHARED,
    PREFS_DEFAULTS,
    prefsValid,
    prefsShioriKeys,
    accountValues,
    localValues,
    prefsSync,
    pillsToAccount,
    pillsFromAccount,
    deviceTextSize,
    houseCookie,
    houseValue,
    themeColorMetas,
    PALETTES,
    houseDomain,
    roomLinks,
    fieldButtons,
    histerToken,
    histerFetchOptions,
    pageSettings,
    PAGE_FLAG_KEYS,
    PAGE_CHOICES,
    histerHeaders,
    asksForCode,
    codeRepoKey,
    CODE_KINDS,
    CODE_HOSTS,
    codeHostName,
    codeQuery,
    isCodeDoc,
    codeInfo,
    codeNotePath,
    histerSignInURL,
    histerSessionsURL,
    accountSync,
    notesTabShown,
    signInAsked,
    signInDue,
    histerAccount,
    urlLookupQueries,
    LOOKUP_MAX,
    mixCounts,
    alternate,
    PILLS,
    PILL_KEYS,
    pillSetting,
    pillList,
    orderPills,
    pillsChanged,
    pillEditor,
    roomsSwitcher,
    roomGlyph,
    collectionAliases,
    prefixLastWord,
    excludingNotes,
    histerText,
    asksForFiles,
    filesQuery,
    isLocalFile,
    localFileURL,
    localFilePath,
    typedQuery,
    newestFirstMerge,
    openedFirst,
    newItemsCount,
    newItemsWait,
    newsBlurSubscribeURL,
    labelChipIndex,
    countText,
    savedLabels,
    previewDates,
    collectionIcon,
    collectionTitle,
    labelsFromAliases,
    labelSuggestions,
    suggestionQueries,
    titleMatches,
    parseAutocomplete,
    editDistance,
    correctedQuery,
    breadcrumb,
    highlightTerms,
    splitHighlights,
    shortDate,
    duration,
    cachedURL,
    archiveURL,
    safeHref,
    linkHref,
    PULL,
    PULL_IDLE,
    pullStep,
    frontendInstances,
    frontendLinks,
    originalLink,
    elsewhereLinks,
    hasBang,
    webQuery,
    normalizeURL,
    urlLookupQuery,
    fallbackURL,
    shouldRedirect,
    annotateWeb,
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
