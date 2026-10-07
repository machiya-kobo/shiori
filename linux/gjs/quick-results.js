// One search of your pages (Hister) and notes (Kura, or Hister's own when
// config.json's notesSource says so, or there's no Kura), as provider rows:
// what the quick-search window and the desktop search show. No GTK here,
// so `shiori provider-search` stays quick. The default vault only (no
// `vault` sent; from Hister, S.histerNoteDocuments): work notes are for
// Shiori's Notes alone.

import { notesFromReply, notesSearch, providerResults } from '../src/provider.js';
import { requestJSON } from './http.js';

const S = () => globalThis.ShioriSearch;
const withSlash = (u) => (u && !u.endsWith('/') ? u + '/' : u || '');

/** One search of your pages and notes, as provider rows. */
export async function quickResults(config, text, limit = { pages: 6, notes: 4 }) {
  const server = withSlash(config.server);
  const hister = server
    ? requestJSON(config, `${server}search?${new URLSearchParams({ query: JSON.stringify({ text: S().histerText(text), limit: 12, highlight: '' }) })}`, { hister: true })
        .then((r) => r.json)
        .catch(() => null)
    : Promise.resolve(null);
  const asked = notesSearch(S(), config, text, 8);
  const notes = asked
    ? requestJSON(config, asked.url, asked.hister ? { hister: true } : {})
        .then((r) => notesFromReply(S(), r.json, asked.hister))
        .catch(() => null)
    : Promise.resolve(null);
  const [pages, found] = await Promise.all([hister, notes]);
  return providerResults(pages, found, limit);
}

