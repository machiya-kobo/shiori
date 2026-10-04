// `shiori` on the command line (docs/linux.md):
//   shiori                      open the window
//   shiori --quick              the quick-search window (bound to a hotkey)
//   shiori search <words…>      open the window on a search
//   shiori save <url> [label]   save a page (queued when Hister is away)
//   shiori save-links <note path> [label] [--dry-run]
//   shiori save-links --folder <folder> [label] [--dry-run]
//                               a note's (or a folder's notes') links, those
//                               Hister doesn't hold yet (docs/linux.md)
//   shiori send                 send what's waiting
//   shiori status               how many wait, and the sign-ins
//   shiori sign-in              sign in to Hister (a small window; when it has users)
//   shiori sign-out             sign out of Hister, everywhere
//   shiori pair <code> [device] pair with a code from `identity pair` (against
//                               the config's Kura); prints the token for config.json
//   shiori provider-search <words…>  the desktop search's rows, as JSON (for Cinnamon's menu)
//   shiori shiori://… | kura://… an app link

const USAGE =
  'usage: shiori [--quick | search <words…> | save <url> [label] | save-links [--folder] <note path or folder> [label] [--dry-run] | send | status | sign-in | sign-out | pair <code> [device] | <shiori:// link>]';

export function parseArgs(argv) {
  const [first, ...rest] = argv;
  if (first === undefined) return { command: 'open' };
  if (first === '--quick' || first === 'quick') return { command: 'quick' };
  if (first === '--help' || first === '-h' || first === 'help') return { command: 'help', usage: USAGE };
  if (first === 'search') {
    const query = rest.join(' ').trim();
    return query ? { command: 'search', query } : { command: 'error', message: 'search needs words', usage: USAGE };
  }
  if (first === 'save') {
    const [url, label] = rest;
    if (!url || !/^https?:\/\/[^/\s]/i.test(url)) return { command: 'error', message: 'save needs a web address', usage: USAGE };
    if (rest.length > 2) return { command: 'error', message: 'save takes one address and at most one label', usage: USAGE };
    return label ? { command: 'save', url, label } : { command: 'save', url };
  }
  if (first === 'save-links') {
    const dryRun = rest.includes('--dry-run');
    const folder = rest.includes('--folder');
    const words = rest.filter((w) => w !== '--dry-run' && w !== '--folder');
    const [where, label] = words;
    if (!where) return { command: 'error', message: `save-links needs ${folder ? 'a folder' : "a note's path"}`, usage: USAGE };
    if (words.length > 2) return { command: 'error', message: 'save-links takes one note or folder and at most one label', usage: USAGE };
    const target = folder ? { folder: where.replace(/\/+$/, '') } : { path: where };
    return { command: 'save-links', ...target, ...(label ? { label } : {}), dryRun };
  }
  if (first === 'pair') {
    // A code may be typed in its two groups ("ABCD EFGH"); the device is the rest after a code-shaped first word.
    const [code, ...device] = rest;
    if (!code) return { command: 'error', message: 'pair needs the code from identity pair', usage: USAGE };
    const joined = /^[A-Za-z0-9]{4}$/.test(code) && /^[A-Za-z0-9]{4}$/.test(device[0] || '') ? [code + device.shift()] : [code];
    return { command: 'pair', code: joined[0], device: device.join(' ').trim() || 'Linux' };
  }
  if (first === 'provider-search') return { command: 'provider-search', query: rest.join(' ').trim() };
  if (first === 'sign-in' || first === 'sign-out') return rest.length ? { command: 'error', message: `${first} takes nothing`, usage: USAGE } : { command: first };
  if (first === 'send' || first === 'status') return rest.length ? { command: 'error', message: `${first} takes nothing`, usage: USAGE } : { command: first };
  if (/^(shiori|kura):\/\//i.test(first)) return { command: 'link', url: first };
  return { command: 'error', message: `unknown: ${first}`, usage: USAGE };
}

/**
 * A `shiori://save-links?path=<vault path>` link (Kura's note view's "Save
 * links in Shiori") or `?folder=<folder>`: { path } or { folder }; null for
 * any other link.
 */
export function saveLinksTarget(url) {
  const m = /^shiori:\/\/save-links\/?\?(.*)$/i.exec(String(url || ''));
  if (!m) return null;
  const params = {};
  for (const part of m[1].split('&')) {
    const [key, value = ''] = part.split('=');
    try {
      params[key] = decodeURIComponent(value.replace(/\+/g, ' '));
    } catch (_) {
      return null;
    }
  }
  if (params.path) return { path: params.path };
  if (params.folder && params.folder !== '/') return { folder: params.folder.replace(/\/+$/, '') };
  return null;
}
