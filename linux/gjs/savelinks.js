// Save This Note's Links (docs/linux.md): Shiori saves pages into Hister;
// the other rooms only look up what it holds. A note's (or a
// folder's notes') outside links, from Kura; those Hister doesn't hold yet,
// saved one at a time by the same rules as `shiori save`, except that skip
// rules hold: a 406 waits for `shiori save <url>` (Save Anyway). No GTK here,
// so the command works without a display; the window is savelinks-window.js.

import { newPage, rejectionReason } from '../src/page.js';
import * as outbox from '../src/outbox.js';
import { requestJSON } from './http.js';
import { fetchPage, fileStore, send, VERSION } from './save.js';

const S = () => globalThis.ShioriSearch;
const withSlash = (u) => (u && !u.endsWith('/') ? u + '/' : u || '');
const pause = (seconds) => new Promise((resolve) => setTimeout(resolve, seconds * 1000));
// A gemini:// or gopher:// link, under the forms Hister may hold it: as
// written, and conservatively normalised (host lowercased, default port gone).
const forms = (url) => (S().isSmallWebLink(url) ? [...new Set([url, S().smallWebKey(url)])] : [url]);

/** Kura's notes for a target: { path } one note, { folder } every note under it with links. */
export async function notesFor(config, { path = null, folder = null }) {
  const kura = withSlash(config.kura);
  if (!kura) throw new Error('No Kura address in ~/.config/shiori/config.json');
  if (path) {
    const r = await requestJSON(config, `${kura}api/note?${new URLSearchParams({ path })}`);
    if (r.status !== 200 || !r.json) throw new Error(r.status === 404 ? "Kura doesn't have that note." : `Kura answered ${r.status}.`);
    return [r.json];
  }
  const notes = [];
  let offset = 0;
  let links = 0;
  while (links < 200) {
    const r = await requestJSON(config, `${kura}api/links?${new URLSearchParams({ folder, limit: '100', offset: String(offset) })}`);
    if (r.status !== 200 || !r.json) throw new Error(r.status === 400 ? `Kura has no folder “${folder}”.` : `Kura answered ${r.status}.`);
    const page = r.json.notes || [];
    notes.push(...page);
    links += page.reduce((n, note) => n + ((note.external_links || []).length), 0);
    offset += page.length;
    if (!page.length || offset >= (r.json.total || 0)) break;
  }
  return notes;
}

/** Which of these URLs Hister holds (with and without a trailing slash), a few searches. */
export async function heldURLs(config, urls) {
  const server = withSlash(config.server);
  const held = new Set();
  if (!server) return held;
  for (let i = 0; i < urls.length; i += 30) {
    const q = S().urlLookupQuery(urls.slice(i, i + 30));
    if (!q) continue;
    const r = await requestJSON(config, `${server}search?${new URLSearchParams({ query: JSON.stringify({ text: q, limit: 100 }) })}`, { hister: true });
    if (r.status !== 200) throw new Error(`Hister answered ${r.status}.`);
    for (const d of (r.json && r.json.documents) || []) {
      held.add(d.url);
      held.add(d.url.endsWith('/') ? d.url.slice(0, -1) : d.url + '/');
    }
  }
  return held;
}

/**
 * Whether Hister holds this exact address, or it with or without a trailing
 * slash (HEAD api/document: 200 or 404). Throws when Hister can't say: a
 * failed lookup never reads as "not held" (HisterClient.holds is the twin).
 */
export async function holds(config, url) {
  const server = withSlash(config.server);
  if (!server) throw new Error('No Hister server is set.');
  const twin = url.endsWith('/') ? url.slice(0, -1) : url + '/';
  for (const candidate of [url, twin]) {
    const r = await requestJSON(config, `${server}api/document?${new URLSearchParams({ url: candidate })}`, { method: 'HEAD', hister: true });
    if (r.status === 200) return true;
    if (r.status !== 404) throw new Error(`Hister answered ${r.status}.`);
  }
  return false;
}

/** The labels Hister's aliases name, for the tag candidates. */
async function labels(config) {
  const server = withSlash(config.server);
  if (!server) return [];
  const r = await requestJSON(config, `${server}api/rules`, { hister: true }).catch(() => null);
  return r && r.json ? S().labelsFromAliases(S().collectionAliases(r.json.aliases || {})).labels : [];
}

/** The links of a target, each with `held`, and the notes' tags that name a label. */
export async function findLinks(config, target) {
  const notes = await notesFor(config, target);
  const rows = S().saveLinkRows(notes);
  const held = await heldURLs(config, rows.flatMap((r) => forms(r.url)));
  const candidates = S().tagLabelCandidates(notes.flatMap((n) => n.tags || []), await labels(config));
  // A link to a file (a package, an image, a PDF) isn't a page: never saved.
  // A gemini:// or gopher:// one goes through the small-web gateway, if set.
  return {
    rows: rows.map((r) => ({
      ...r,
      held: forms(r.url).some((u) => held.has(u)),
      file: S().linkLooksLikeFile(r.url),
      smallweb: S().isSmallWebLink(r.url),
      needsGateway: S().isSmallWebLink(r.url) && !config.smallweb,
    })),
    candidates,
  };
}

/**
 * Saves one link: never one Hister holds (looked up again right before,
 * and under its address after redirects: `api/add` would replace its
 * metadata). → { outcome: 'saved'|'queued'|'held'|'skipped'|'rejected'|'failed', reason }
 */
export async function saveLink(config, row, { label = null, anyway = false, store = fileStore() } = {}) {
  if (S().isSmallWebLink(row.url)) return saveThroughGateway(config, row);
  if (S().linkLooksLikeFile(row.url)) return { outcome: 'failed', reason: 'A file, not a web page: not saved.' };
  // Hister's exact answer, or nothing is saved: api/add would replace a
  // held page's metadata.
  const held = async (url) => {
    try {
      return (await holds(config, url)) ? { outcome: 'held' } : null;
    } catch (error) {
      return { outcome: 'failed', reason: `Couldn't check whether Hister has it: ${error.message}` };
    }
  };
  const before = await held(row.url);
  if (before) return before;
  const fetched = await fetchPage(row.url);
  if (!fetched.html) return { outcome: 'failed', reason: "Couldn't download this page, or it isn't a web page." };
  const after = fetched.url !== row.url ? await held(fetched.url) : null;
  if (after) return after;
  const host = (() => {
    try {
      return new URL(row.url).host;
    } catch (_) {
      return row.url;
    }
  })();
  const page = newPage({
    url: fetched.url, title: fetched.title || (row.text && row.text !== row.url ? row.text : host), html: fetched.html,
    label, via: 'note-links', clientVersion: VERSION, ignoreSkipRules: anyway, extra: { from_note: row.notePath },
  });
  let status;
  try {
    status = await send(config, page);
  } catch (_) {
    await outbox.enqueue(store, page);
    return { outcome: 'queued' };
  }
  const result = outbox.outcome(status);
  if (result === 'sent') return { outcome: 'saved' };
  if (result === 'retry') {
    await outbox.enqueue(store, page);
    return { outcome: 'queued' };
  }
  return { outcome: status === 406 ? 'skipped' : 'rejected', reason: rejectionReason(status, `Hister refused it (${status}).`) };
}

/**
 * A gemini:// or gopher:// link: never fetched here; the small-web gateway
 * fetches and saves it (POST /api/save → 202 with the canonical
 * URL). Never one Hister holds; a 429 (20 waiting) is waited out.
 * → { outcome: 'gateway', url } or as saveLink.
 */
export async function saveThroughGateway(config, row, { wait = pause } = {}) {
  const gateway = withSlash(config.smallweb);
  if (!gateway) return { outcome: 'failed', reason: 'Needs the small-web gateway ("smallweb" in ~/.config/shiori/config.json).' };
  const held = await heldURLs(config, forms(row.url)).catch(() => new Set());
  if (forms(row.url).some((u) => held.has(u))) return { outcome: 'held' };
  for (let attempt = 0; attempt < 4; attempt++) {
    let r;
    try {
      r = await requestJSON(config, `${gateway}api/save`, { method: 'POST', body: { url: row.url }, hister: true });
    } catch (_) {
      return { outcome: 'failed', reason: 'The small-web gateway is out of reach.' };
    }
    if (r.status === 202 || r.status === 200) return { outcome: 'gateway', url: (r.json && r.json.url) || row.url };
    if (r.status === 400) return { outcome: 'rejected', reason: 'The gateway saves only gemini:// and gopher:// pages.' };
    if (r.status !== 429) return { outcome: 'failed', reason: `The gateway answered ${r.status}.` };
    if (attempt < 3) await wait(5 * (attempt + 1));
  }
  return { outcome: 'failed', reason: 'The gateway has too many saves waiting; try again in a minute.' };
}

/** The batch's label for a page the gateway saves in the background (it sets none), once Hister holds it. */
export async function labelWhenSaved(config, url, label, { tries = 6, wait = pause } = {}) {
  const server = withSlash(config.server);
  for (let attempt = 0; attempt < tries; attempt++) {
    if ((await heldURLs(config, [url]).catch(() => new Set())).has(url)) {
      const r = await requestJSON(config, `${server}api/label`, { method: 'POST', body: { url, label }, hister: true }).catch(() => null);
      return !!r && r.status >= 200 && r.status < 300;
    }
    if (attempt < tries - 1) await wait(3);
  }
  return false;
}

/** `shiori save-links`: resolves to { code, message } for the command line, printing as it goes. */
export async function saveLinksCommand(config, { path = null, folder = null, label = null, dryRun = false }, say = print) {
  if (!config.server) return { code: 2, message: 'No Hister server in ~/.config/shiori/config.json' };
  let found;
  try {
    found = await findLinks(config, path ? { path } : { folder });
  } catch (e) {
    return { code: 1, message: `shiori: ${e.message}` };
  }
  const { rows, candidates } = found;
  if (!rows.length) return { code: 0, message: `No links to other sites in ${path || folder}.` };
  const open = rows.filter((r) => !r.held && !r.file && !r.needsGateway);
  for (const r of rows.filter((r) => r.held)) say(`in Hister  ${r.url}`);
  for (const r of rows.filter((r) => r.file && !r.held)) say(`a file     ${r.url}`);
  for (const r of rows.filter((r) => r.needsGateway && !r.held)) say(`needs the small-web gateway  ${r.url}`);
  if (dryRun) {
    for (const r of open) say(`not yet    ${r.url}`);
    const hint = candidates.length ? ` Labels from the note's tags: ${candidates.join(', ')}.` : '';
    return { code: 0, message: `${open.length} of ${rows.length} links not in Hister yet.${hint}` };
  }
  const store = fileStore();
  const counts = { saved: 0, queued: 0, held: 0, skipped: 0, rejected: 0, failed: 0, gateway: 0 };
  const viaGateway = [];
  for (const r of open) {
    const { outcome, reason, url } = await saveLink(config, r, { label, store });
    counts[outcome] += 1;
    if (outcome === 'gateway') viaGateway.push(url);
    const word = { saved: 'saved', queued: 'queued', held: 'in Hister', skipped: 'skipped', rejected: 'refused', failed: 'failed', gateway: 'gateway' }[outcome];
    say(`${word.padEnd(10)} ${r.url}${reason ? `  (${reason}${outcome === 'skipped' ? ` To save it anyway: shiori save ${r.url}` : ''})` : ''}`);
  }
  // The gateway saves without a label: the batch's goes on once each page arrives.
  if (label) {
    for (const url of viaGateway) {
      if (!(await labelWhenSaved(config, url, label))) say(`no label yet ${url}  (the gateway hadn't saved it; label it later)`);
    }
  }
  const parts = [`${counts.saved} saved`];
  if (counts.gateway) parts.push(`${counts.gateway} sent to the small-web gateway`);
  if (counts.queued) parts.push(`${counts.queued} queued`);
  if (counts.skipped) parts.push(`${counts.skipped} skipped by a skip rule`);
  if (counts.rejected + counts.failed) parts.push(`${counts.rejected + counts.failed} not saved`);
  return { code: counts.failed + counts.rejected ? 1 : 0, message: `${parts.join(', ')}; ${rows.length - open.length + counts.held} already in Hister.` };
}
