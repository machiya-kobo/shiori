// Hister's token on Linux (docs/linux.md): `"histerToken": "…"` in
// ~/.config/shiori/config.json (the file 0600), sent as `X-Access-Token`
// only to the configured Hister server, by origin: never the small-web
// gateway (which also gets `Origin: hister://`), the web app or Kura.
// Unset, nothing is sent. Pure: search-core (`S`) is passed in.

const originOf = (url) => {
  try {
    const u = new URL(String(url));
    return u.username || u.password ? '' : u.origin.toLowerCase();
  } catch (_) {
    return '';
  }
};

/** The token from the config, checked; '' when there's none or it isn't one. */
export function configHisterToken(config, S) {
  return S.histerToken((config && config.histerToken) || '');
}

/** The headers a request to `url` gets: X-Access-Token when it's the configured server's, else none. */
export function histerHeaders(config, url, S) {
  const server = originOf(config && config.server);
  if (!server || originOf(url) !== server) return {};
  return S.histerHeaders(configHisterToken(config, S));
}

/** What `shiori status` says about the token: whether it's set, and who can read it too. */
export function histerTokenStatus(config, mode, S) {
  if (!configHisterToken(config, S)) {
    return config && config.histerToken ? 'Hister: histerToken in config.json isn’t a token (8 to 512 characters, no spaces).' : 'Hister: no token (none needed while the server has no users).';
  }
  const line = 'Hister: a token in config.json.';
  if (typeof mode === 'number' && (mode & 0o077) !== 0) {
    return `${line} Others can read the file (mode ${(mode & 0o777).toString(8)}): chmod 600 ~/.config/shiori/config.json`;
  }
  return line;
}
