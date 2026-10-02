// Hister, SearXNG, Konbini and the settings document, as the web app sees
// them: all under the page's own host (see web/README.md), so every
// request is same-origin and needs no special headers. The browser's
// Sec-Fetch-Site is what lets Hister accept its writes.

const ROOT = '/';

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

async function request(path, { method = 'GET', body, timeout = 12000, keepalive = false } = {}) {
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

export function preview(url, extractor = '') {
  const params = { url };
  if (extractor) params.extractor = extractor;
  return request(`api/preview?${query(params)}`);
}

export async function extractors(url) {
  const list = (await request(`api/extractors?${query({ url })}`)) || [];
  return list.filter((e) => e && e.enabled !== false && (!e.capabilities || e.capabilities.preview !== false)).map((e) => e.name);
}

export async function rules() {
  const reply = (await request('api/rules')) || {};
  return globalThis.ShioriSearch.collectionAliases(reply.aliases || {});
}

export function setLabel(url, label) {
  return request('api/label', { method: 'POST', body: { url, label } });
}

/**
 * Deletes exactly one page: a dry run first, and nothing unless it matches
 * one. `keepalive` lets both go out while the page is being left.
 */
export async function deletePage(url, { keepalive = false } = {}) {
  // Hister never has a work note, and must never be sent one's address.
  if (globalThis.ShioriSearch.isOtherVault(url)) throw new HisterError("A work vault's note isn't in Hister.");
  const exact = `url:"${url.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
  const dry = await request('api/delete', { method: 'POST', body: { query: exact, dry_run: true }, keepalive });
  const matched = (dry && dry.matched) || 0;
  if (matched !== 1) throw new HisterError(`That would have deleted ${matched} pages, so nothing was deleted.`);
  await request('api/delete', { method: 'POST', body: { query: exact, dry_run: false }, keepalive });
}

/** Tells Hister `url` was opened from a search, so it ranks it first next time. */
export function recordOpened(url, title, q) {
  const text = (q || '').trim();
  // Never a work note's address or title to Hister.
  if (!text || text === '*' || globalThis.ShioriSearch.isOtherVault(url)) return Promise.resolve();
  // As the search was sent: Hister matches the exact text.
  return request('api/history', { method: 'POST', body: { url, title, query: globalThis.ShioriSearch.histerText(text) } }).catch(() => {});
}

export function forgetOpened(url, q) {
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
export async function web(q, page = 1) {
  const response = await fetch(`${ROOT}searx/search?${query({ q, format: 'json', pageno: String(page), categories: 'general' })}`, {
    credentials: 'same-origin',
  }).catch(() => null);
  if (!response || !response.ok) throw new HisterError("The web search didn't answer.");
  return response.json();
}

/** Kura's vaults (the default one and the work vaults), for the Notes filter; [] on failure. */
export async function kuraVaults() {
  const reply = await request('kura/api/vaults').catch(() => null);
  return (reply && Array.isArray(reply.vaults) && reply.vaults) || [];
}

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
export async function autocomplete(q) {
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
