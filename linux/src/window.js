// The window's rules (docs/linux.md), pure so Node tests them: where a
// navigation in the web view goes, and how big the window starts.

// Handed to the system (the browser, or the app for the scheme). Nothing
// else ever leaves the window: about:, data: or blob: are the page's own
// (the preview's srcdoc frame, an export), file: and javascript: go nowhere.
const SYSTEM_SCHEMES = ['http', 'https', 'gemini', 'gopher', 'mailto', 'obsidian'];
const PAGE_SCHEMES = ['about', 'data', 'blob'];

const schemeOf = (uri) => {
  const m = /^([a-z][a-z0-9+.-]*):/i.exec(String(uri || ''));
  return m ? m[1].toLowerCase() : '';
};

function parse(uri) {
  if (!['http', 'https'].includes(schemeOf(uri))) return null;
  try {
    return new URL(uri);
  } catch (_) {
    return null;
  }
}

const withSlash = (u) => (u && !u.endsWith('/') ? u + '/' : u || '');

/** The sign-in helper's pages on Hister's host, or Kura's own sign-in: they stay in the window, where their cookies are needed. */
export function signInPage(uri, config) {
  const u = parse(uri);
  if (!u) return false;
  const hister = parse(withSlash(String(config.server || '').trim()));
  if (hister && u.origin === hister.origin && u.pathname.startsWith(`${hister.pathname}machiya/`)) return true;
  const kura = parse(withSlash(String(config.kura || '').trim()));
  return !!kura && u.origin === kura.origin && u.pathname.startsWith(kura.pathname) && /^signin(\/|$)/.test(u.pathname.slice(kura.pathname.length));
}

/**
 * Where a navigation goes: 'view' (load it here), 'system' (the browser or
 * the scheme's app), 'home' (back to the web app: a sign-in finished on a
 * room's own page) or 'drop'. `from` is the page showing now; `newWindow`
 * a link that asked for one (target=_blank, window.open).
 */
export function navigation(uri, { config, from = '', newWindow = false }) {
  const scheme = schemeOf(uri);
  if (PAGE_SCHEMES.includes(scheme)) return newWindow ? 'drop' : 'view';
  if (!SYSTEM_SCHEMES.includes(scheme)) return 'drop';
  const u = parse(uri);
  if (!newWindow && u) {
    const app = parse(withSlash(String(config.webApp || '').trim()));
    if (app && u.origin === app.origin) return 'view';
    if (signInPage(uri, config)) return 'view';
    const rooms = [config.server, config.kura].map((r) => parse(withSlash(String(r || '').trim()))?.origin).filter(Boolean);
    if (signInPage(from, config) && rooms.includes(u.origin)) return 'home';
  }
  return 'system';
}

/** The window's first size on a monitor of this size: 1200×800, or less where that wouldn't fit. */
export function fitSize(width, height) {
  if (!(width > 0) || !(height > 0)) return [1200, 800];
  return [Math.max(480, Math.min(1200, Math.floor(width * 0.9))), Math.max(400, Math.min(800, Math.floor(height * 0.85)))];
}
