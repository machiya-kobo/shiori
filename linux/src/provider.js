// The desktop search provider's results (docs/linux.md): what the
// Cinnamon menu (and GNOME Shell's SearchProvider2) shows for the words
// typed there: your pages from Hister, then your notes from Kura, a few
// of each. Pure: the replies come in, in Hister's and Kura's shapes
// (search-core's kuraDocuments), and the rows go out.

export const PAGES = 4;
export const NOTES = 3;

/** The query for the words typed (the terms the desktop hands over). */
export function providerQuery(terms) {
  return (Array.isArray(terms) ? terms : [terms]).map(String).join(' ').trim();
}

function hostOf(url) {
  const m = String(url).match(/^https?:\/\/([^/?#]+)/i);
  return m ? m[1].replace(/^www\./, '') : '';
}

/**
 * Rows for the desktop: { id, kind, name, description, url }, pages then
 * notes, each deduplicated by address. `id` is what the desktop hands back
 * on activation (`activation(id)` turns it back into what to open).
 */
export function providerResults(histerReply, kuraReply, { pages = PAGES, notes = NOTES } = {}) {
  const seen = new Set();
  const rows = [];
  const take = (docs, kind, max) => {
    let n = 0;
    for (const d of docs || []) {
      if (n >= max || !d || typeof d.url !== 'string' || !/^https?:\/\//i.test(d.url) || seen.has(d.url)) continue;
      // Hister sends no notes (Kura does); one that slips through is Kura's to show.
      if (kind === 'page' && d.label === 'vault') continue;
      seen.add(d.url);
      rows.push({
        id: `${kind}:${d.url}`,
        kind,
        name: d.title || d.url,
        description: kind === 'note' ? String(d.path || '').replace(/\.md$/, '').split('/').join(' › ') || 'Note' : hostOf(d.url),
        url: d.url,
      });
      n++;
    }
  };
  take(histerReply && histerReply.documents, 'page', pages);
  take(kuraReply && kuraReply.documents, 'note', notes);
  return rows;
}

/** What an activated row opens: a page in the browser, a note in Kura's reader. */
export function activation(id) {
  const m = String(id).match(/^(page|note):(https?:\/\/.+)$/i);
  return m ? { kind: m[1].toLowerCase(), url: m[2] } : null;
}
