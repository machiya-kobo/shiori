// The Machiya sign-in on Linux (docs/linux.md, docs/signing-in.md): a token
// in ~/.config/shiori/config.json (`"machiyaToken": "mch_…"`, the file
// 0600), sent as `Authorization: Bearer …` only where search-core's host
// rule allows: the configured Kura (and Konbini or Niwa, if named), by
// origin, never Hister, the gateway, the web app or any other host. Pure:
// search-core (`S`) is passed in.

/** The origins the token may go to: the rooms the config names, less the other services'. */
export function roomOrigins(config, S) {
  const c = config || {};
  return S.machiyaRooms([c.kura, c.konbini, c.niwa], [c.server, c.smallweb, c.webApp, c.searxng]);
}

/** The token from the config, checked; '' when there's none or it isn't one. */
export function configToken(config, S) {
  return S.machiyaToken((config && config.machiyaToken) || '');
}

/** The headers a request to `url` gets: Authorization where the rule allows, else none. */
export function roomHeaders(config, url, S) {
  // Signed in through Hister (sign-in.json): the helper's id, which rooms in
  // Hister sign-in mode take (they refuse the identity file's tokens).
  const sid = config && config.histerSignIn && config.histerSignIn.sid;
  if (sid && /^mhs_[A-Za-z0-9_-]{43}$/.test(sid)) {
    return S.mayCarryMachiyaToken(url, roomOrigins(config, S)) ? { Authorization: S.machiyaAuthHeader(sid) } : {};
  }
  const token = configToken(config, S);
  if (!token || !S.mayCarryMachiyaToken(url, roomOrigins(config, S))) return {};
  return { Authorization: S.machiyaAuthHeader(token) };
}

/**
 * What `shiori status` says about the sign-in: who can read the token too.
 * `mode` is config.json's permission bits (null when unknown).
 */
export function signInStatus(config, mode, S) {
  if (!configToken(config, S)) return (config && config.machiyaToken) ? 'Machiya: machiyaToken in config.json isn’t a token (mch_… or mcd_…).' : 'Machiya: not signed in.';
  const line = 'Machiya: signed in (a token in config.json).';
  if (typeof mode === 'number' && (mode & 0o077) !== 0) {
    return `${line} Others can read the file (mode ${(mode & 0o777).toString(8)}): chmod 600 ~/.config/shiori/config.json`;
  }
  return line;
}

/** What `shiori pair` prints: who, and the line to put in config.json. */
export function pairedMessage({ token, principal }) {
  return [
    `Paired as ${principal}. Add this to ~/.config/shiori/config.json, then chmod 600 it:`,
    `  "machiyaToken": ${JSON.stringify(token)}`,
  ].join('\n');
}
