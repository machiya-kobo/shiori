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

/**
 * Where notes come from (search-core's notesSource): config.json's
 * `notesSource` ('kura' or 'hister'; absent until chosen), else Kura when
 * the config names one. `S` is search-core.
 */
export function notesFromHister(S, config) {
  return S.notesSource(String((config && config.notesSource) || ''), !!String((config && config.kura) || '').trim()) === 'hister';
}

/**
 * The notes search: { url, hister } for `text` (the default vault only), or
 * null without a server to ask. From Hister: its label:vault search
 * (S.histerNotesText), answered with S.histerNoteDocuments; else Kura's API.
 */
export function notesSearch(S, config, text, limit = 8) {
  const slash = (u) => (u && !u.endsWith('/') ? u + '/' : u || '');
  if (notesFromHister(S, config)) {
    const server = slash(String(config.server || '').trim());
    if (!server) return null;
    const t = String(text || '').trim();
    const query = { text: S.histerNotesText(text), limit, highlight: '' };
    if (!t || t === '*') query.sort = 'date';
    return { url: `${server}search?${new URLSearchParams({ query: JSON.stringify(query) })}`, hister: true };
  }
  const kura = slash(String(config.kura || '').trim());
  return kura ? { url: S.kuraURL(kura, text, { limit }), hister: false } : null;
}

/** A notes search's reply as notes, in Kura's shape (Hister's: the default vault's alone). */
export function notesFromReply(S, json, hister) {
  if (!json) return null;
  return hister ? S.histerNoteDocuments(json) : S.kuraDocuments(json);
}

/** What an activated row opens: a page in the browser, a note in Kura's reader, or Shiori's sign-in. */
export function activation(id) {
  if (String(id) === SIGN_IN) return { kind: 'signin', url: SIGN_IN };
  const m = String(id).match(/^(page|note):(https?:\/\/.+)$/i);
  return m ? { kind: m[1].toLowerCase(), url: m[2] } : null;
}

/** The sign-in row's id and address (`shiori shiori://sign-in` opens the window). */
export const SIGN_IN = 'shiori://sign-in';

/**
 * One reply's state: 'ok', 'signin' (401 or 403: Hister has users, or
 * Kura asks who you are), 'unreachable' (no answer, or an error), or
 * 'none' (nothing to ask). `reply` is { status, json }, null when it
 * failed, undefined when nothing was asked.
 */
export function replyState(reply) {
  if (reply === undefined) return 'none';
  if (!reply) return 'unreachable';
  if (reply.status === 401 || reply.status === 403) return 'signin';
  return reply.status >= 200 && reply.status < 300 && reply.json ? 'ok' : 'unreachable';
}

/**
 * What the quick search and the menu show beside the rows: { message,
 * signIn }. A refused search says so (it found nothing because it wasn't
 * let in), never "Nothing matches".
 */
export function quickStatus(text, pages, notes, count) {
  const signIn = pages === 'signin' || notes === 'signin';
  if (pages === 'signin') return { message: 'Sign in to Hister to search your pages from here.', signIn };
  if (notes === 'signin' && !count) return { message: 'Sign in to see your notes here.', signIn };
  if (count) return { message: '', signIn };
  if (pages === 'unreachable' && notes !== 'ok') return { message: "Hister didn't answer. Check your network or VPN.", signIn };
  if (pages === 'none' && notes === 'none') return { message: 'Add your servers to ~/.config/shiori/config.json.', signIn };
  return { message: `Nothing matches “${text}”.`, signIn };
}

/** The menu's row that opens the sign-in window. */
export function signInRow() {
  return { id: SIGN_IN, kind: 'signin', name: 'Sign in to Hister', description: 'Shiori: to search your pages from the menu', url: SIGN_IN };
}
