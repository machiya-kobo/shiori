// Hister, SearXNG, Konbini and the settings document, as the web app sees
// them: all under the page's own host (see web/README.md), so every
// request is same-origin and needs no special headers. The browser's
// Sec-Fetch-Site is what lets Hister accept its writes.

const ROOT = '/';

/**
 * Told of every refused answer (status, path) before it throws: the app
 * sends a Hister refusal to the sign-in (docs/signing-in.md).
 */
let onRefused = () => {};
export function setRefusedHandler(handler) {
  onRefused = typeof handler === 'function' ? handler : () => {};
}

export class HisterError extends Error {
  constructor(message, status = 0, code = '') {
    super(message);
    this.status = status;
    /** The server's own error code, when it sent one (the AI endpoint does). */
    this.code = code;
  }
  get unreachable() {
    return this.status === 0;
  }
}

// An identical read already on its way is shared, never sent twice: the
// first draw and the one after the rules and vaults arrive ask the same
// searches, the web's included (each counts). Only while it's in flight,
// so nothing is ever older than a fresh request; each caller gets its own
// copy of the reply.
const inFlight = new Map();
function shared(key, make) {
  let pending = inFlight.get(key);
  if (!pending) {
    pending = make();
    inFlight.set(key, pending);
    const done = () => inFlight.delete(key);
    pending.then(done, done);
  }
  return pending.then((value) => (value && typeof value === 'object' ? structuredClone(value) : value));
}

function request(path, options = {}) {
  const read = (options.method || 'GET') === 'GET' && options.body === undefined && !options.keepalive;
  return read ? shared('GET ' + path, () => send(path, options)) : send(path, options);
}

async function send(path, { method = 'GET', body, timeout = 12000, keepalive = false } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout);
  let response;
  try {
    response = await fetch(ROOT + path, {
      method,
      body: body === undefined ? undefined : JSON.stringify(body),
      headers: body === undefined ? { Accept: 'application/json' } : { 'Content-Type': 'application/json', Accept: 'application/json' },
      credentials: 'same-origin',
      signal: controller.signal,
      keepalive,
    });
  } catch (_) {
    throw new HisterError("The server didn't answer. Check your network or VPN, then try again.");
  } finally {
    clearTimeout(timer);
  }
  const text = await response.text();
  if (!response.ok) {
    try {
      onRefused(response.status, path);
    } catch (_) {}
    let message = '';
    let code = '';
    try {
      const reply = JSON.parse(text);
      code = reply.error || '';
      message = reply.message || reply.error || '';
    } catch (_) {}
    throw new HisterError(message || `The server answered ${response.status}.`, response.status, code);
  }
  if (!text) return null;
  try {
    // Stored text can hold raw control characters Hister doesn't escape.
    return JSON.parse(text.replace(/[\u0000-\u001f]/g, ' '));
  } catch (_) {
    throw new HisterError("The server's reply didn't make sense.", response.status);
  }
}

const query = (params) => new URLSearchParams(params).toString();

/**
 * Who Hister says is signed in on this browser: its /api/profile through
 * this host (whose nginx signs Hister's calls in), as { status, json }. Not
 * through request(): a 403 here is an answer, never a trip to the sign-in.
 */
export async function profile() {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 6000);
  try {
    const response = await fetch(`${ROOT}api/profile`, { headers: { Accept: 'application/json' }, credentials: 'same-origin', signal: controller.signal });
    const text = await response.text();
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch (_) {}
    return { status: response.status, json };
  } catch (_) {
    return { status: 0, json: null };
  } finally {
    clearTimeout(timer);
  }
}

/** One page of results: documents, the next page's key, opened ones, a suggestion. */
export async function search(text, { sort = '', pageKey = '', limit = 30 } = {}) {
  // The last word a prefix, never the notes (those are Kura's).
  const q = { text: globalThis.ShioriSearch.histerText(text), highlight: 'HTML', limit };
  if (sort) q.sort = sort;
  if (pageKey) q.page_key = pageKey;
  const reply = await request(`search?${query({ format: 'json', query: JSON.stringify(q) })}`);
  const documents = (reply && reply.documents) || [];
  return {
    total: (reply && reply.total) || 0,
    documents,
    next: documents.length >= limit ? reply.page_key || '' : '',
    opened: pageKey ? [] : (reply && reply.history) || [],
    suggestion: (reply && reply.query_suggestion) || '',
  };
}

/**
 * Hister's readable copy of a page. Never another vault's note (Kura
 * previews those, and Hister must never be sent one's address): refused
 * without a request, as is an address that can't be parsed.
 */
export async function preview(url, extractor = '') {
  if (globalThis.ShioriSearch.noteVault(url) !== null || globalThis.ShioriSearch.isPrivateNote(url)) throw new HisterError(PRIVATE);
  const params = { url };
  if (extractor) params.extractor = extractor;
  return request(`api/preview?${query(params)}`);
}

/**
 * Hister's extractors for a page (Show As). Never asked about a note: the
 * apps' Show As is for web pages, and another vault's note's address must
 * never reach Hister (any `/v/<vault>/n/` address, on any host: over-
 * inclusive, so safe).
 */
export async function extractors(url) {
  if (globalThis.ShioriSearch.noteVault(url) !== null || globalThis.ShioriSearch.isPrivateNote(url)) return [];
  const list = await request(`api/extractors?${query({ url })}`);
  return (Array.isArray(list) ? list : []).filter((e) => e && e.enabled !== false && (!e.capabilities || e.capabilities.preview !== false)).map((e) => e.name);
}

export async function rules() {
  const reply = (await request('api/rules')) || {};
  return globalThis.ShioriSearch.collectionAliases(reply.aliases || {});
}

/**
 * Whether a note is private, Kura asked afresh: before another vault's note
 * goes to Hister (a shared vault can be made private again at any time). A
 * failed read is private; the default vault's notes and pages ask nothing.
 */
export function isPrivateNow(url) {
  return globalThis.ShioriSearch.isPrivateNoteNow(url, readVaults);
}

const PRIVATE = "A private vault's note isn't in Hister.";
// The folders Hister watches are its own to keep: their files are never
// labelled or deleted from here.
const FILE = 'Files stay as Hister watches them.';

export async function setLabel(url, label) {
  if (globalThis.ShioriSearch.isLocalFile(url)) throw new HisterError(FILE);
  if (await isPrivateNow(url)) throw new HisterError(PRIVATE);
  return request('api/label', { method: 'POST', body: { url, label } });
}

/**
 * Deletes exactly one page: a dry run first, and nothing unless it matches
 * one. `keepalive` lets both go out while the page is being left.
 */
export async function deletePage(url, { keepalive = false } = {}) {
  // Hister never has a private vault's note, and must never be sent one's address.
  if (globalThis.ShioriSearch.isLocalFile(url)) throw new HisterError(FILE);
  if (await isPrivateNow(url)) throw new HisterError(PRIVATE);
  const exact = `url:"${url.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
  const dry = await request('api/delete', { method: 'POST', body: { query: exact, dry_run: true }, keepalive });
  const matched = (dry && dry.matched) || 0;
  if (matched !== 1) throw new HisterError(`That would have deleted ${matched} pages, so nothing was deleted.`);
  await request('api/delete', { method: 'POST', body: { query: exact, dry_run: false }, keepalive });
}

/** Tells Hister `url` was opened from a search, so it ranks it first next time. */
export async function recordOpened(url, title, q) {
  const text = (q || '').trim();
  // Never a private vault's note's address or title to Hister.
  // Nor a file's: what you open there stays here.
  if (!text || text === '*' || globalThis.ShioriSearch.isLocalFile(url) || globalThis.ShioriSearch.isPrivateNote(url) || (await isPrivateNow(url))) return;
  // As the search was sent: Hister matches the exact text.
  return request('api/history', { method: 'POST', body: { url, title, query: globalThis.ShioriSearch.histerText(text) } }).catch(() => {});
}

export async function forgetOpened(url, q) {
  if (await isPrivateNow(url)) throw new HisterError(PRIVATE);
  return request('api/history', { method: 'POST', body: { url, query: q, delete: true } });
}

export async function opened(cursor = null, filter = '') {
  const params = { opened: 'true' };
  if (filter) params.filter = filter;
  if (cursor) Object.assign(params, { last_id: String(cursor.lastID), last_updated_at: cursor.lastUpdatedAt });
  const reply = (await request(`api/history?${query(params)}`)) || {};
  const entries = reply.documents || [];
  return {
    entries,
    next: entries.length >= 100 && reply.last_id ? { lastID: reply.last_id, lastUpdatedAt: reply.last_updated_at } : null,
  };
}

export const faviconURL = (key) => (key ? `${ROOT}api/favicon?${query({ key })}` : '');
export const histerPageURL = (url) => `${ROOT}preview?${query({ id: url })}`;

/** Web results from SearXNG (through /searx/). */
export function web(q, page = 1) {
  const url = `${ROOT}searx/search?${query({ q, format: 'json', pageno: String(page), categories: 'general' })}`;
  return shared('web ' + url, async () => {
    const response = await fetch(url, { credentials: 'same-origin' }).catch(() => null);
    // A stock SearXNG answers 403 to format=json.
    if (response && response.status === 403) throw new HisterError("SearXNG doesn't allow JSON results: turn on formats: json under search: in its settings.yml.");
    if (!response || !response.ok) throw new HisterError("The web search didn't answer.");
    return response.json();
  });
}

const readVaults = () => request('kura/api/vaults', { timeout: 4000 }).then((r) => r && r.vaults);

/**
 * Kura's vaults (the default one and the others, private or shared), for
 * the Notes filter, and which are shared (passed to S.useVaults); [] on
 * failure, sharing none.
 */
export function kuraVaults() {
  return globalThis.ShioriSearch.loadVaults(readVaults);
}

/**
 * Kura's preferences for whoever is signed in (/api/prefs, with Machiya's
 * identity file): `{status, prefs}`. The status also says where you stand:
 * 200 signed in, 401 not, 404 no sign-in there (or the host doesn't pass
 * the path), 0 Kura out of reach. Never throws.
 */
export async function kuraPrefs() {
  try {
    const reply = await request('kura/api/prefs', { timeout: 6000 });
    const prefs = reply && reply.prefs && typeof reply.prefs === 'object' ? reply.prefs : {};
    return { status: 200, prefs };
  } catch (error) {
    return { status: error.status || 0, prefs: {} };
  }
}

/**
 * The person's settings in their account (/machiya/api/prefs: the Hister
 * sign-in helper on this host, machiya docs/contracts/prefs.md), with this
 * browser's own sign-in. `{status, snapshot}`: 200 with {rev, prefs,
 * updated}, 304 (unchanged since `rev`), 401 signed out, 0 out of reach.
 * Never throws, and never sets off the sign-in redirect: failures are silent.
 */
async function prefsCall(method, { rev, values } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  try {
    const headers = { Accept: 'application/json' };
    if (rev != null) headers['If-None-Match'] = `"${rev}"`;
    if (values) headers['Content-Type'] = 'application/json';
    const r = await fetch(ROOT + 'machiya/api/prefs', {
      method, headers, credentials: 'same-origin', cache: 'no-store', signal: controller.signal,
      body: values ? JSON.stringify({ prefs: values }) : undefined,
    });
    if (r.status !== 200) return { status: r.status };
    const reply = await r.json();
    const snapshot = { rev: reply.rev, prefs: reply.prefs || {}, updated: reply.updated || {} };
    return { status: 200, snapshot };
  } catch (_) {
    return { status: 0 };
  } finally {
    clearTimeout(timer);
  }
}
export const accountPrefs = (rev) => prefsCall('GET', { rev });
export const putAccountPrefs = (values) => prefsCall('PUT', { values });

/** A note's sanitized HTML from Kura (a work note's preview: Hister never has one). Not cached. */
export async function kuraNote(path, vault) {
  const reply = await request(`kura/api/note?${query({ path, vault })}`);
  return (reply && reply.html) || '';
}

/** Gemini and Gopher results through the small-web gateway (/smallweb/, same-origin). Searched only on submit. */
export async function smallweb(q, page = 1) {
  const url = globalThis.ShioriSearch.smallwebSearchURL(ROOT + 'smallweb/', q, page);
  if (!url) return globalThis.ShioriSearch.smallwebResults(null);
  // The engines are slow at times (volunteers'; one timing out never fails it).
  const reply = await request(url.slice(ROOT.length), { timeout: 25000 });
  return globalThis.ShioriSearch.smallwebResults(reply);
}

/** Asks the gateway to save a page opened directly in a Gemini app. Best effort. */
export function smallwebSave(url) {
  return request('smallweb/api/save', { method: 'POST', body: { url }, keepalive: true }).catch(() => {});
}

// --- Add Page: a page saved through the small-web gateway -----------------------

const ADDABLE = new Set(['http:', 'https:', 'gemini:', 'gopher:']);

/**
 * Add Page's address check, before anything is sent: `{url}` (an address
 * without a scheme gets https://), or `{error}` in the app's words. Only
 * http, https, gemini and gopher; no user name or password; never a note:
 * an address whose path, read as Kura reads it (S.kuraPath: `//` folded,
 * `%XX` decoded, so `/%76/` too), starts with `/v/<name>/` is a private
 * vault's, on any host, and `isNote` (the app's isNoteDoc) catches the
 * rest. Notes live in Kura, not Hister.
 */
export function checkPageURL(text, { isNote = () => false } = {}) {
  let raw = String(text || '').trim();
  if (!raw) return { error: 'Type or paste an address.' };
  if (/\s/.test(raw)) return { error: 'That isn’t an address.' };
  if (!/^[a-z][a-z0-9+.-]*:/i.test(raw)) raw = `https://${raw.replace(/^\/+/, '')}`;
  let u;
  try {
    u = new URL(raw);
  } catch (_) {
    return { error: 'That isn’t an address.' };
  }
  if (!ADDABLE.has(u.protocol)) return { error: 'Only http, https, gemini and gopher pages can be saved.' };
  if (!u.hostname) return { error: 'That isn’t an address.' };
  if (u.username || u.password) return { error: 'Leave the user name and password out of the address.' };
  const path = globalThis.ShioriSearch.kuraPath(u.href);
  if (path === null || /^\/v\/[^/]+(\/|$)/.test(path) || isNote(u.href)) return { error: 'That’s a note: notes stay in Kura, not in your pages.' };
  return { url: u.href };
}

/**
 * What the share target was handed (`?url=&title=&text=`, from the
 * manifest's share_target): `{url, title}`, or null when it wasn't a
 * share. An empty `url` takes the first http(s) address in `text`
 * (Android often puts the link there), less trailing punctuation and
 * unbalanced closing brackets. Nothing is checked or saved here: the
 * sheet opens with it, and only Save sends it.
 */
export function sharedPage(params) {
  const get = (k) => (params.get(k) || '').trim();
  const [url, title, text] = ['url', 'title', 'text'].map(get);
  if (!params.has('url') && !params.has('title') && !params.has('text')) return null;
  return { url: url || firstLink(text), title: title.slice(0, 300) };
}

function firstLink(text) {
  const m = String(text || '').match(/https?:\/\/[^\s<>"]+/i);
  if (!m) return '';
  let link = m[0];
  for (;;) {
    const last = link.slice(-1);
    const open = { ')': '(', ']': '[', '}': '{' }[last];
    const count = (c) => link.split(c).length - 1;
    if ('.,;:!?\'"’”»'.includes(last)) link = link.slice(0, -1);
    else if (open && count(last) > count(open)) link = link.slice(0, -1);
    else return link;
  }
}

/**
 * Asks the gateway to save a page (`POST /smallweb/api/save`): it answers
 * 202 at once and fetches in the background, where a refusal (a private
 * address, a note) can still happen, so success says "Saving…", never
 * "Saved". `{ok, message}` in the app's words.
 */
export async function savePage(url, title = '') {
  const body = { url };
  if (title) body.title = title;
  try {
    await request('smallweb/api/save', { method: 'POST', body, timeout: 15000 });
    return { ok: true, message: 'Saving… it’ll be in your pages shortly.' };
  } catch (error) {
    return { ok: false, message: SAVE_ERRORS[error.status] || (error.status ? `The gateway answered ${error.status}.` : 'The gateway didn’t answer. Check your network or VPN, then try again.') };
  }
}

const SAVE_ERRORS = {
  400: 'The gateway can’t save that address.',
  403: 'The gateway doesn’t take saves from here.',
  429: 'The gateway has 20 pages waiting. Try again in a minute.',
};

/** SearXNG's image-proxy links, moved under /searx/; anything else, nothing. */
export function proxiedImage(raw) {
  if (typeof raw !== 'string' || !raw) return '';
  try {
    const u = new URL(raw, location.origin + ROOT + 'searx/');
    return /\/image_proxy$/.test(u.pathname) ? `${ROOT}searx/image_proxy${u.search}` : '';
  } catch (_) {
    return '';
  }
}

let cardsPromise = null;
/** Konbini's cards (slug ↔ vault path), for linking notes. */
export function cards() {
  cardsPromise ||= request('konbini/api/cards', { timeout: 6000 })
    .then((data) => (Array.isArray(data) ? data : (data && data.cards) || []).filter((c) => c && c.slug && c.path))
    .catch(() => []);
  return cardsPromise;
}

/** SearXNG's autocomplete for `q` (its list of searches), for "Did you mean"; [] on failure. */
export function autocomplete(q) {
  return shared('autocomplete ' + q, () => fetchAutocomplete(q));
}

async function fetchAutocomplete(q) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 3000);
  try {
    const response = await fetch(`${ROOT}searx/autocompleter?${query({ q })}`, { credentials: 'same-origin', signal: controller.signal });
    const json = response.ok ? await response.json() : null;
    return Array.isArray(json) && Array.isArray(json[1]) ? json[1] : [];
  } catch (_) {
    return [];
  } finally {
    clearTimeout(timer);
  }
}

// --- AI (docs/ai.md) ---------------------------------------------

/** Your server's AI: `{enabled, answer, engine, …}`, or null when it isn't there. */
export async function aiStatus() {
  try {
    return await request('shiori/ai/status', { timeout: 4000 });
  } catch (_) {
    return null;
  }
}

/** An answer to a web search from its results' snippets: {answer, sources, engine, …}. */
export function answer(q, refresh = false) {
  return request('shiori/ai/answer', { method: 'POST', body: { q, refresh }, timeout: 90000 });
}

/** A web page's summary: {summary, engine, model, partial, cached}. Never a note. */
export function summarize(url, refresh = false) {
  return request('shiori/ai/summarize', { method: 'POST', body: { url, refresh }, timeout: 90000 });
}

// --- Notes from Kura -------------------------------------------------------------

/**
 * One page of notes from Kura's own search (same-origin /kura/), in the
 * shape `search` returns: the offset is the page key.
 */
export async function kura(text, { sort = '', pageKey = '', limit = 30, vault = '' } = {}) {
  const S = globalThis.ShioriSearch;
  const offset = Number(pageKey) || 0;
  const url = S.kuraURL(ROOT + 'kura/', text, { sort: sort === 'date' ? 'date' : 'relevance', limit, offset, vault });
  const reply = await request(url.slice(ROOT.length));
  const { documents, total } = S.kuraDocuments(reply);
  return { total, documents, next: offset + documents.length < total ? String(offset + documents.length) : '', opened: [], suggestion: '' };
}

/**
 * One page of notes from Hister (Notes From: Hister): its label:vault
 * documents, the default vault's alone (S.histerNoteDocuments), in the
 * shape `kura` returns. "" or "*": the newest first.
 */
export async function histerNotes(text, { sort = '', pageKey = '', limit = 30 } = {}) {
  const S = globalThis.ShioriSearch;
  const t = String(text || '').trim();
  const q = { text: S.histerNotesText(text), highlight: 'HTML', limit };
  if (sort === 'date' || !t || t === '*') q.sort = 'date';
  if (pageKey) q.page_key = pageKey;
  const reply = await request(`search?${query({ format: 'json', query: JSON.stringify(q) })}`);
  const { documents, total } = S.histerNoteDocuments(reply);
  // Hister's own page count: its key goes on while it sent a full page.
  const sent = (reply && Array.isArray(reply.documents) && reply.documents.length) || 0;
  return { total, documents, next: sent >= limit ? (reply && reply.page_key) || '' : '', opened: [], suggestion: '' };
}
