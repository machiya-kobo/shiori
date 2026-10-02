// Your pages from a Hister search reply, as Firefox's keyword (ext/omnibox.js,
// in the background) and sidebar (ext/sidebar.js, a page) list them: the
// pages opened before for this search first, then the rest, each page
// once, web pages only, never a note. Needs search-core.js (ShioriSearch).
(function (root) {
  /** [{ url, title, host, snippet }] from a reply, at most `limit`. */
  function webPages(reply, settings = {}, limit = 20) {
    const S = root.ShioriSearch;
    const seen = new Set();
    const out = [];
    const niwa = settings.niwaURL || '';
    const konbini = settings.konbiniURL || '';
    for (const d of [...((reply && reply.history) || []), ...((reply && reply.documents) || [])]) {
      if (out.length >= limit) break;
      if (!d || !/^https?:\/\//i.test(String(d.url || ''))) continue;
      if (S.isPrivateNote(d.url) || S.isNoteURL(d.url, niwa, konbini)) continue;
      const key = S.normalizeURL(d.url);
      if (seen.has(key)) continue;
      seen.add(key);
      let host = '';
      try {
        host = new URL(d.url).host;
      } catch (_) {}
      // Firefox shows text as it is: no control characters.
      const title = String(d.title || '').replace(/[\u0000-\u001f\u007f]+/g, ' ').trim() || d.url;
      out.push({ url: d.url, title, host, snippet: typeof d.text === 'string' ? d.text : '' });
    }
    return out;
  }

  root.ShioriPages = { webPages };
})(typeof globalThis !== 'undefined' ? globalThis : this);
