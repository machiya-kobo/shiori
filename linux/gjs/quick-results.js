// One search of your pages (Hister) and notes (Kura, or Hister's own when
// config.json's notesSource says so, or there's no Kura), as provider rows:
// what the quick-search window and the desktop search show. No GTK here,
// so `shiori provider-search` stays quick. The default vault only (no
// `vault` sent; from Hister, S.histerNoteDocuments): work notes are for
// Shiori's Notes alone.

import { notesFromReply, notesSearch, providerResults, replyState } from '../src/provider.js';
import { requestJSON } from './http.js';

const S = () => globalThis.ShioriSearch;
const withSlash = (u) => (u && !u.endsWith('/') ? u + '/' : u || '');

/**
 * One search of your pages and notes: { rows, pages, notes }, the rows as
 * provider rows and each source's replyState ('ok', 'signin',
 * 'unreachable' or 'none'), so a refused search isn't shown as nothing found.
 */
export async function quickResults(config, text, limit = { pages: 6, notes: 4 }) {
  const server = withSlash(config.server);
  const hister = server
    ? requestJSON(config, `${server}search?${new URLSearchParams({ query: JSON.stringify({ text: S().histerText(text), limit: 12, highlight: '' }) })}`, { hister: true })
        .catch(() => null)
    : Promise.resolve(undefined);
  const asked = notesSearch(S(), config, text, 8);
  const notes = asked
    ? requestJSON(config, asked.url, asked.hister ? { hister: true } : {}).catch(() => null)
    : Promise.resolve(undefined);
  const [pages, found] = await Promise.all([hister, notes]);
  const states = { pages: replyState(pages), notes: replyState(found) };
  const rows = providerResults(
    states.pages === 'ok' ? pages.json : null,
    states.notes === 'ok' ? notesFromReply(S(), found.json, asked.hister) : null,
    limit,
  );
  return { rows, ...states };
}
