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

// --- Signing in to Hister (docs/linux.md, docs/signing-in.md) ---------------
// `shiori sign-in` (a small window: name and password) signs in with Hister's
// own login and trades the session for the sign-in helper's id (on Hister's
// host under /machiya/). Both are kept in $XDG_DATA_HOME/shiori/sign-in.json
// (0600; config.json is read-only in the Flatpak), tied to the server's
// origin: the session goes only to that server as `Cookie: hister=…`, the id
// only to the rooms as `Authorization: Bearer mhs_…`. `shiori sign-out` ends
// both through the helper.

const SESSION_RE = /^[A-Za-z0-9_-]{43}$/;
const SID_RE = /^mhs_[A-Za-z0-9_-]{43}$/;

/** A Hister session value (43 base64url characters), else ''. */
export const histerSession = (raw) => (typeof raw === 'string' && SESSION_RE.test(raw.trim()) ? raw.trim() : '');
/** The helper's id (mhs_ and 43 base64url characters), else ''. */
export const histerSessionID = (raw) => (typeof raw === 'string' && SID_RE.test(raw.trim()) ? raw.trim() : '');

/** sign-in.json's content for this server, checked: { session, sid, username }, or null. */
export function signInRecord(raw, server) {
  if (!raw || typeof raw !== 'object') return null;
  const session = histerSession(raw.session);
  const sid = histerSessionID(raw.sid);
  if (!session || !sid || !originOf(server) || originOf(raw.server) !== originOf(server)) return null;
  return { session, sid, username: typeof raw.username === 'string' ? raw.username.slice(0, 64) : '' };
}

/** What sign-in.json holds after a sign-in. */
export const signInFileContent = (server, { session, sid, username }) =>
  JSON.stringify({ server: originOf(server), session, sid, username }, null, 2) + '\n';

/** The Cookie a request to `url` gets: the session, to the configured server only, else ''. */
export function histerCookie(config, url) {
  const record = config && config.histerSignIn;
  if (!record || !record.session || !originOf(config.server) || originOf(url) !== originOf(config.server)) return '';
  return `hister=${record.session}`;
}

const base = (server) => (String(server).endsWith('/') ? String(server) : String(server) + '/');

/** Hister's own login: POST /api/login, JSON, with Origin. */
export const loginRequest = (server, username, password) => ({
  method: 'POST',
  url: `${base(server)}api/login`,
  body: JSON.stringify({ username, password }),
});

/** The helper's trade of a session for an id. */
export const appSessionRequest = (server, hister, label) => ({
  method: 'POST',
  url: `${base(server)}machiya/api/app-session`,
  body: JSON.stringify({ hister, label: String(label || '').slice(0, 80) }),
});

/** The helper's sign-out for an id. */
export const signOutRequest = (server, sid) => ({
  method: 'POST',
  url: `${base(server)}machiya/signout`,
  headers: { Authorization: `Bearer ${sid}` },
});

/** The helper's health: sign-in is offered only when it says Hister has users. */
export const availabilityURL = (server) => `${base(server)}machiya/healthz`;
export const signInAvailable = (status, json) => status === 200 && !!json && json.ok === true && json.hister === 'ok';

/** The `hister` session Hister set, from its Set-Cookie values, else ''. */
export function sessionFromSetCookie(values) {
  for (const value of values || []) {
    const [pair, ...attrs] = String(value).split(';');
    const [name, ...rest] = pair.split('=');
    if (name.trim() !== 'hister') continue;
    if (attrs.some((a) => /^\s*max-age\s*=\s*0\s*$/i.test(a))) continue;
    const session = histerSession(rest.join('='));
    if (session) return session;
  }
  return '';
}

/** The login's answer in words, for the window. */
export function loginProblem(status) {
  if (status === 401) return "Hister didn't recognise that name and password.";
  if (status === 403) return 'This Hister signs in only through its sign-in provider: sign in from the web app instead.';
  return "Sign-in is unavailable right now: Hister or its sign-in helper isn't answering.";
}

/** What `shiori status` says about the sign-in. */
export const histerSignInStatus = (record) =>
  record ? `Hister: signed in${record.username ? ` as ${record.username}` : ''} (sign-in.json).` : 'Hister: not signed in.';
