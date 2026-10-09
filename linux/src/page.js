// A page to save, and the request that saves it: HisterKit's NewPage,
// PageFetcher's title and cap, and HisterClient.add, for `shiori save`
// (docs/linux.md). The one native write on Linux: everything else
// goes through the live web app in the window, same-origin.

/** A bare link's page is downloaded up to this, as the share extension does. */
export const MAX_BYTES = 3 * 1024 * 1024;
export const MAX_HTML_CHARACTERS = 2 * 1024 * 1024;

/**
 * A deliberate save: Hister's skip rules are for automatic capture, so it
 * says to ignore them (the sensitive-content check still applies), and it
 * carries where it came from (`source: "shiori"`, Hister's convention).
 */
export function newPage({
  url, title = '', html = null, label = null, added = null, via = 'linux', clientVersion = '0',
  ignoreSkipRules = true, extra = {},
}) {
  if (!/^https?:\/\/[^/\s]/i.test(String(url || ''))) throw new Error(`Not a web address: ${url}`);
  const page = { url: String(url), title: String(title || '') };
  if (html) page.html = html;
  if (label) page.label = String(label);
  if (added != null) page.added = Math.trunc(Number(added));
  page.metadata = { source: 'shiori', client: 'shiori', client_version: String(clientVersion), via };
  // A deliberate save overrides the skip rules; a note's links in bulk
  // don't (only Save Anyway, one link at a time). `extra`: provenance
  // (a note-links save's `from_note`).
  if (ignoreSkipRules) page.metadata.ignore_skip_rules = true;
  for (const [key, value] of Object.entries(extra || {})) page.metadata[key] = String(value);
  return page;
}

/** The request that adds `page`: `Origin: hister://` passes Hister's check, as HisterKit sends. */
export function addRequest(server, page) {
  const base = String(server).endsWith('/') ? String(server) : String(server) + '/';
  return {
    method: 'POST',
    url: `${base}api/add`,
    headers: { 'Content-Type': 'application/json', Origin: 'hister://' },
    body: JSON.stringify(page),
  };
}

const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };

/** The document's <title>, entities decoded, spaces folded. */
export function titleIn(html) {
  const m = String(html || '').match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  if (!m) return '';
  return m[1]
    .replace(/<[^>]*>/g, '')
    .replace(/&(#x[0-9a-f]+|#\d+|\w+);/gi, (whole, name) => {
      if (name[0] === '#') {
        const code = name[1].toLowerCase() === 'x' ? parseInt(name.slice(2), 16) : parseInt(name.slice(1), 10);
        // Past U+10FFFF fromCodePoint throws: such an entity stays as written.
        return Number.isInteger(code) && code >= 0 && code <= 0x10ffff ? String.fromCodePoint(code) : whole;
      }
      return ENTITIES[name.toLowerCase()] ?? whole;
    })
    .replace(/\s+/g, ' ')
    .trim();
}

/** Cut at the last '>' before the cap, as the Safari extension and iOS do. */
export function capped(html) {
  const s = String(html || '');
  if (s.length <= MAX_HTML_CHARACTERS) return s;
  const prefix = s.slice(0, MAX_HTML_CHARACTERS);
  const close = prefix.lastIndexOf('>');
  return close >= 0 ? prefix.slice(0, close + 1) : prefix;
}

/** Why Hister refused a page for good (HisterKit's Rejection). */
export function rejectionReason(status, message = '') {
  return { 406: 'Hister skips this site.', 413: 'The page is too large for Hister.', 422: 'Hister refused it as sensitive (it looks like it holds a secret).' }[status] || message;
}
