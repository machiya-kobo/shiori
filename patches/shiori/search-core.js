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
    const safe = [];
    for (const u of urls) {
      if (!u || /[()|\s"]/.test(u)) continue;
      safe.push(u);
      safe.push(u.endsWith('/') ? u.slice(0, -1) : u + '/');
    }
    const unique = [...new Set(safe)];
    return unique.length ? `url:(${unique.join('|')})` : '';
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

  /** SearXNG's "cached" link: the page on the Wayback Machine. */
  function cachedURL(url) {
    return 'https://web.archive.org/web/' + url;
  }

  /** The page's latest snapshot on archive.is (a link only, never fetched). */
  function archiveURL(url) {
    return 'https://archive.is/newest/' + url;
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
    const m = path && path.match(/^\/v\/([^/]+)\/n\/./);
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
  /** Kura's /api/vaults list, as last read; anything else (a failure: []) shares none. */
  function useVaults(list) {
    sharedVaults = new Set(
      (Array.isArray(list) ? list : [])
        .filter((v) => v && typeof v.name === 'string' && v.default !== true && v.private === false)
        .map((v) => v.name),
    );
  }
  /**
   * A private vault's note: another vault's, unless Kura marks that vault
   * shared. Everything that must not reach a private note (Hister, AI,
   * caches, exports) asks this. HisterKit's Notes.isPrivateNote is the twin.
   */
  const isPrivateNote = (url) => {
    // Fails closed: an address that can't be parsed, and a name that isn't
    // one Kura allows, are private.
    if (kuraPath(url) === null) return true;
    const vault = noteVault(url);
    return vault !== null && (!VAULT_NAME.test(vault) || !sharedVaults.has(vault));
  };
  /**
   * isPrivateNote with Kura asked afresh: before another vault's note (its
   * address, title or text) goes to Hister or an AI engine, since a shared
   * vault can be made private again at any time. `read` answers
   * /api/vaults' list; its answer is kept (useVaults), and a failed read
   * shares none. The default vault's notes and other pages ask nothing.
   * The cached isPrivateNote is enough for what's only shown.
   * HisterKit's Notes.isPrivateNoteNow is the twin.
   */
  async function isPrivateNoteNow(url, read) {
    if (noteVault(url) === null) return isPrivateNote(url);
    await loadVaults(read);
    return isPrivateNote(url);
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
    return Object.fromEntries(Object.entries(aliases || {}).filter(([, v]) => !/(label|source):(\([^)]*)?\bvault\b/.test(String(v))));
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
   */
  function prefixLastWord(text) {
    const t = String(text || '');
    if (!t || /\s$/.test(t)) return t;
    if ((t.match(/"/g) || []).length % 2) return t;
    const word = t.split(/\s+/).pop();
    if ([...word].length < 2 || !/\p{L}/u.test(word) || !/^[\p{L}\p{N}]+$/u.test(word)) return t;
    return t + '*';
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

  /** A Hister search as sent: the last word a prefix, never the notes, and never the files unless it asks. */
  function histerText(text) {
    const sent = excludingNotes(prefixLastWord(String(text || '').trim()));
    if (asksForFiles(sent) || sent.split(/\s+/).includes(FILES_EXCLUSION)) return sent;
    return `${sent} ${FILES_EXCLUSION}`;
  }

  /** A query as typed, from one sent (the Opened list shows it). */
  function typedQuery(text) {
    const shown = String(text || '').split(/\s+/).filter((w) => w && !EXCLUSION_TERMS.includes(w) && w !== FILES_EXCLUSION).join(' ');
    return shown.endsWith('*') ? shown.slice(0, -1) : shown;
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
  ];

  /** The switcher's button glyph (24-point strokes, each a path's `d`), shared by both web pages. */
  const ROOM_GLYPHS = {
    house: ['M3 11l9-7 9 7', 'M5 10v10h14V10', 'M10 20v-6h4v6'],
  };

  /** A glyph as an <svg>, built node by node: no markup, so Mozilla's
   *  linter has no innerHTML to flag in the signed Firefox build. */
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
   * The rooms as links, the neighbours after a rule: each with its own
   * icon (`.room-icon`, from scripts/room-icons.py: a room's home-screen
   * icon, a neighbour's logo or a neutral glyph), in its room's colour (`--room`,
   * set through setProperty for the extension page's CSP), `current`
   * marked. For the header menu and the phones' sheet.
   */
  function roomLinks(list, current = 'shiori') {
    const out = [];
    for (const r of list) {
      if (r.neighbour && out.length && !out.some((n) => n.tagName === 'HR')) out.push(document.createElement('hr'));
      const a = document.createElement('a');
      a.className = 'room' + (r.neighbour ? ' neighbour' : '');
      a.href = r.url;
      a.setAttribute('role', 'menuitem');
      if (r.key === current) a.setAttribute('aria-current', 'page');
      a.style.setProperty('--room', `var(--${r.tint})`);
      const name = document.createElement('span');
      name.textContent = r.name;
      // Every entry its own icon: a room's home-screen icon, a
      // neighbour's logo (smaller, with no tile).
      const iconEl = document.createElement('span');
      iconEl.className = 'room-icon';
      iconEl.dataset.room = r.key;
      iconEl.setAttribute('aria-hidden', 'true');
      a.append(iconEl, name);
      out.push(a);
    }
    return out;
  }

  /**
   * The header's switcher: a house button and its menu, closed by a click
   * elsewhere or Escape. Null when there's nowhere else to go.
   */
  function roomsSwitcher(list, current = 'shiori') {
    if (list.filter((r) => r.key !== current).length === 0) return null;
    const wrap = document.createElement('div');
    wrap.className = 'rooms';
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'icon-button rooms-open';
    button.title = 'Rooms';
    button.setAttribute('aria-label', 'Rooms');
    button.setAttribute('aria-haspopup', 'menu');
    button.setAttribute('aria-expanded', 'false');
    button.append(roomGlyph('house'));
    const menu = document.createElement('div');
    menu.className = 'rooms-menu';
    menu.setAttribute('role', 'menu');
    menu.hidden = true;
    menu.append(...roomLinks(list, current));
    const show = (open) => ((menu.hidden = !open), button.setAttribute('aria-expanded', String(open)));
    button.addEventListener('click', (e) => (e.stopPropagation(), show(menu.hidden)));
    document.addEventListener('click', (e) => !wrap.contains(e.target) && show(false));
    document.addEventListener('keydown', (e) => e.key === 'Escape' && !menu.hidden && (show(false), button.focus()));
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
   * then one item that holds the rest. Notes (label vault) and files never fold.
   * Items: {page} or {folded: site, pages}.
   */
  function siteRuns(docs, minimum = 3) {
    const items = [];
    const key = (d) => (d.label === 'vault' || isLocalFile(d.url) ? null : siteOf(d) || null);
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
  function feedURL(base, { query, title = '', source = 'pages', opened = false, kuraBase = '' }) {
    const b = base.endsWith('/') ? base : base + '/';
    if (opened) return `${b}api/history?opened=true&format=rss`;
    if (source === 'notes') return kuraFeedURL(kuraBase, query);
    if (String(query).trim() === '*' && source === 'all') return `${b}api/history?format=rss`;
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
   * to an action and the next state. In a field only Escape counts; with
   * Meta, Ctrl or Alt held nothing does (those are the browser's). `gg`
   * and `dd` are the same key twice within 600 ms.
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
        const key = isSmallWebLink(link.url) ? smallWebKey(link.url) : normalizeURL(link.url);
        if (seen.has(key)) continue;
        seen.add(key);
        out.push({ url: link.url, text: link.text || '', notePath: note.path, noteTitle: note.title || '' });
      }
    }
    return out;
  }

  /**
   * The note's tags that name an existing label ("retro", or a nested
   * "topic/retro", for the label `retro`; case aside). Never an invented
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

  /** Shiori's licence, as the About sections name it. */
  const LICENCE = 'GNU AGPL-3.0-or-later';

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
    return /^mc[hd]_[A-Za-z0-9_.-]{8,4096}$/.test(token) ? token : '';
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
   * A fetch's options for `url`: with the token's header when the host rule
   * allows it, and then `redirect: 'error'`, so it never follows a
   * redirect anywhere. Everything else (credentials included) as given.
   */
  function machiyaFetchOptions(url, token, rooms, init = {}) {
    const clean = machiyaToken(token);
    if (!clean || !mayCarryMachiyaToken(url, rooms)) return init;
    return { ...init, headers: { ...(init.headers || {}), Authorization: machiyaAuthHeader(clean) }, redirect: 'error' };
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
    machiyaEntry,
    machiyaStatusText,
    isSmallWebLink,
    smallWebKey,
    vaultChip,
    linkLooksLikeFile,
    sourceLink,
    LICENCE,
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
    smallwebSearchURL,
    smallwebResults,
    markRuns,
    smallwebOpen,
    rooms,
    houseSettings,
    houseCookie,
    houseValue,
    themeColorMetas,
    PALETTES,
    houseDomain,
    roomLinks,
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
    hasBang,
    webQuery,
    normalizeURL,
    urlLookupQuery,
    fallbackURL,
    shouldRedirect,
    annotateWeb,
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
