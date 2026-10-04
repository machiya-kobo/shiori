// Signing in to Hister on Linux (docs/linux.md): `shiori sign-in` opens a
// small window (name and password), `shiori sign-out` ends the session
// through the sign-in helper. The sign-in lives in
// $XDG_DATA_HOME/shiori/sign-in.json (0600), tied to the server's origin;
// config.json stays read-only. The logic is ../src/hister.js; this file
// stays thin.

import GLib from 'gi://GLib';
import Gtk from 'gi://Gtk?version=4.0';
import Adw from 'gi://Adw?version=1';
import { requestJSON } from './http.js';
import {
  signInRecord, signInFileContent, loginRequest, appSessionRequest, signOutRequest,
  availabilityURL, signInAvailable, sessionFromSetCookie, loginProblem,
} from '../src/hister.js';

/** sign-in.json's path. */
export const signInPath = () => GLib.build_filenamev([GLib.get_user_data_dir(), 'shiori', 'sign-in.json']);

/** The sign-in for the config's server, or null. */
export function readSignIn(config) {
  try {
    const [, bytes] = GLib.file_get_contents(signInPath());
    return signInRecord(JSON.parse(new TextDecoder().decode(bytes)), config.server);
  } catch (_) {
    return null;
  }
}

function writeSignIn(config, record) {
  GLib.mkdir_with_parents(GLib.path_get_dirname(signInPath()), 0o700);
  GLib.file_set_contents_full(signInPath(), signInFileContent(config.server, record), GLib.FileSetContentsFlags.CONSISTENT, 0o600);
}

function removeSignIn() {
  GLib.unlink(signInPath());
}

/** Whether the helper says Hister has users (else no sign-in is offered). */
export async function available(config) {
  if (!config.server) return false;
  try {
    const r = await requestJSON(config, availabilityURL(config.server), { credentials: false, signIn: false, redirects: false });
    return signInAvailable(r.status, r.json);
  } catch (_) {
    return false;
  }
}

/** Signs in: Hister's login, then the helper's id for the session. Resolves to '' or a problem in words. */
export async function signIn(config, username, password) {
  const login = loginRequest(config.server, username, password);
  let r;
  try {
    r = await requestJSON(config, login.url, { method: 'POST', body: login.body, hister: true, credentials: false, redirects: false });
  } catch (_) {
    return "The server didn't answer. Check your network or VPN, then try again.";
  }
  if (r.status !== 200) return loginProblem(r.status);
  const session = sessionFromSetCookie(r.cookies);
  if (!session) return loginProblem(500);
  const trade = appSessionRequest(config.server, session, `Shiori on ${GLib.get_host_name() || 'Linux'}`);
  let t;
  try {
    t = await requestJSON(config, trade.url, { method: 'POST', body: trade.body, signIn: false, credentials: false, redirects: false });
  } catch (_) {
    t = { status: 0 };
  }
  const record = t.status === 200 && t.json ? signInRecord({ server: config.server, session, sid: t.json.sid, username: t.json.username }, config.server) : null;
  if (!record) {
    // The helper didn't take it: log the session out, so none is left behind.
    await requestJSON({ ...config, histerSignIn: { session } }, `${config.server.replace(/\/?$/, '/')}api/logout`, { method: 'POST', hister: true, redirects: false }).catch(() => {});
    return loginProblem(t.status === 401 ? 401 : 500);
  }
  writeSignIn(config, record);
  return '';
}

/** `shiori sign-out`: the helper ends the session everywhere; the file goes either way. */
export async function signOutCommand(config) {
  const record = readSignIn(config);
  if (!record) {
    try {
      removeSignIn();
    } catch (_) {}
    return { code: 0, message: 'Not signed in to Hister.' };
  }
  const out = signOutRequest(config.server, record.sid);
  await requestJSON(config, out.url, { method: 'POST', headers: out.headers, signIn: false, credentials: false, redirects: false }).catch(() => {});
  removeSignIn();
  return { code: 0, message: 'Signed out of Hister.' };
}

/** The sign-in window: name, password, Sign In; it says so when sign-in isn't on. */
export class SignInWindow {
  constructor(app, config) {
    this.config = config;
    this.window = new Adw.Window({ application: app, title: 'Sign in to Hister', default_width: 420, default_height: 300 });
    const box = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL, spacing: 12, margin_top: 12, margin_bottom: 18, margin_start: 18, margin_end: 18 });
    const view = new Adw.ToolbarView();
    view.add_top_bar(new Adw.HeaderBar());
    view.set_content(box);
    this.window.set_content(view);
    this.status = new Gtk.Label({ wrap: true, xalign: 0, label: 'Checking whether your Hister has users…' });
    this.status.add_css_class('dim-label');
    const group = new Adw.PreferencesGroup();
    this.name = new Adw.EntryRow({ title: 'Name' });
    this.password = new Adw.PasswordEntryRow({ title: 'Password' });
    group.add(this.name);
    group.add(this.password);
    this.button = new Gtk.Button({ label: 'Sign In', sensitive: false, halign: Gtk.Align.END });
    this.button.add_css_class('suggested-action');
    this.button.connect('clicked', () => this.submit());
    this.password.connect('entry-activated', () => this.submit());
    box.append(this.status);
    box.append(group);
    box.append(this.button);
    group.set_sensitive(false);
    this.group = group;
    void this.prepare();
  }

  async prepare() {
    const record = readSignIn(this.config);
    if (record) {
      this.status.set_label(`Signed in${record.username ? ` as ${record.username}` : ''}. To sign out: shiori sign-out`);
      return;
    }
    if (!(await available(this.config))) {
      this.status.set_label('Your Hister has no users, or its sign-in is unavailable: nothing to sign in to.');
      return;
    }
    this.status.set_label('Your Hister has users: sign in once on this computer. The session stays in your data folder (0600) and goes only to your Hister.');
    this.group.set_sensitive(true);
    this.button.set_sensitive(true);
  }

  async submit() {
    const name = this.name.get_text().trim();
    const password = this.password.get_text();
    if (!name || !password || !this.button.get_sensitive()) return;
    this.button.set_sensitive(false);
    const problem = await signIn(this.config, name, password);
    this.password.set_text('');
    if (problem) {
      this.status.set_label(problem);
      this.button.set_sensitive(true);
      return;
    }
    this.window.close();
  }

  present() {
    this.window.present();
  }
}
