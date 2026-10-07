// Shiori for Linux: the application (docs/linux.md). GJS on GTK4 +
// libadwaita, a WebKitGTK 6 window on the live web app (same-origin, so
// Hister's write protection and the service worker work as in a
// browser). The logic lives in ../src/, tested under Node and GJS; this
// file stays thin.
//
//   gjs -m linux/gjs/main.js [search <words…> | --quick | save <url> [label] | …]
//
// Configuration: ~/.config/shiori/config.json (0600 once it holds a token)
//   { "webApp": "https://shiori.example/", "server": "https://hister.example/",
//     "kura": "https://kura.example/", "smallweb": "https://smallweb.example/",
//     "machiyaToken": "mch_…" }
// No hostnames in the repo, as for the other clients.

import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk?version=4.0';
import Gdk from 'gi://Gdk?version=4.0';
import Adw from 'gi://Adw?version=1';
import WebKit from 'gi://WebKit?version=6.0';
import System from 'system';
import { installURL } from '../src/url.js';
import { parseArgs, saveLinksTarget } from '../src/cli.js';
import { QuickSearch } from './quick.js';
import { save, sendWaiting, waitingStatus } from './save.js';
import { pairedMessage, signInStatus } from '../src/machiya.js';
import { histerTokenStatus, histerSignInStatus } from '../src/hister.js';
import { readSignIn, signOutCommand, SignInWindow } from './signin.js';
import { navigation, fitSize } from '../src/window.js';

installURL(globalThis);
// search-core.js sets globalThis.ShioriSearch, once URL exists.
await import('../../patches/shiori/search-core.js');

// The Flatpak's own ID when it runs as one (io.github.machiya_kobo.Shiori), so
// the window and its desktop file match.
const APP_ID = GLib.getenv('FLATPAK_ID') || 'io.github.machiya_kobo.Shiori';

// Commands with no window run here, before the application starts: GTK
// needs a display to start, and these must work without one (over SSH,
// from cron or a script; without this `shiori status` failed with "Failed
// to open display").
{
  const early = parseArgs([...ARGV]);
  // The desktop search's rows (Cinnamon's menu runs this for what's
  // typed): JSON on stdout, so it's quick. The default vault only: the
  // menu isn't Shiori's Notes (docs/linux.md).
  if (early.command === 'provider-search') {
    const { quickResults } = await import('./quick-results.js');
    const { quickStatus, signInRow } = await import('../src/provider.js');
    let rows = [];
    if (early.query.length >= 2) {
      const found = await quickResults(loadConfig(), early.query).catch(() => null);
      // Refused (Hister has users, or Kura asks who you are): a row that opens the sign-in.
      if (found) rows = quickStatus(early.query, found.pages, found.notes, found.rows.length).signIn ? [...found.rows, signInRow()] : found.rows;
    }
    print(JSON.stringify(rows));
    System.exit(0);
  }
  if (early.command === 'help' || early.command === 'error') {
    const text = `${early.message ? early.message + '\n' : ''}${early.usage}`.trimEnd();
    (early.command === 'error' ? printerr : print)(text);
    System.exit(early.command === 'error' ? 2 : 0);
  }
  if (early.command === 'save-links') {
    const { saveLinksCommand } = await import('./savelinks.js');
    const r = await saveLinksCommand(loadConfig(), early).catch((e) => ({ code: 1, message: `shiori: ${e.message}` }));
    (r.code !== 0 ? printerr : print)(r.message);
    System.exit(r.code);
  }
  if (early.command === 'save' || early.command === 'send' || early.command === 'status') {
    const config = loadConfig();
    let r;
    try {
      r = await (early.command === 'save' ? save(config, early) : early.command === 'send' ? sendWaiting(config) : waitingStatus());
    } catch (e) {
      r = { code: 1, message: `shiori: ${e.message}` };
    }
    if (early.command === 'status') {
      r.message += '\n' + histerSignInStatus(config.histerSignIn);
      r.message += '\n' + histerTokenStatus(config, configMode(), globalThis.ShioriSearch);
      r.message += '\n' + signInStatus(config, configMode(), globalThis.ShioriSearch);
    }
    (r.code !== 0 ? printerr : print)(r.message);
    System.exit(r.code);
  }
  if (early.command === 'sign-out') {
    const r = await signOutCommand(loadConfig());
    print(r.message);
    System.exit(r.code);
  }
  // Pairing with a code from `identity pair`, against the config's Kura. The
  // config is read-only here (the Flatpak mounts it so), so the token is
  // printed for you to add; nothing else keeps it.
  if (early.command === 'pair') {
    const config = loadConfig();
    const { requestJSON } = await import('./http.js');
    const viaSoup = async (url, init) => {
      const r = await requestJSON(config, url, { method: 'POST', body: init.body, signIn: false, redirects: false });
      return { status: r.status, json: async () => r.json };
    };
    let code = 0;
    let message;
    try {
      message = pairedMessage(await globalThis.ShioriSearch.machiyaPair(config.kura || '', early.code, early.device, viaSoup));
    } catch (e) {
      code = 1;
      message = `shiori: ${e.message}`;
    }
    (code !== 0 ? printerr : print)(message);
    System.exit(code);
  }
}

// The app's config dir, then the host's ~/.config (inside the Flatpak the
// first is ~/.var/app/…; the manifest shares ~/.config/shiori read-only).
// A declaration, hoisted: the commands above run before this line.
function configPaths() {
  return [GLib.get_user_config_dir(), GLib.build_filenamev([GLib.get_home_dir(), '.config'])].map((dir) =>
    GLib.build_filenamev([dir, 'shiori', 'config.json']));
}

/** The configuration, or {} when there's none (the window then says so), with this device's Hister sign-in. */
function loadConfig() {
  for (const path of configPaths()) {
    try {
      const [, bytes] = GLib.file_get_contents(path);
      const config = JSON.parse(new TextDecoder().decode(bytes)) || {};
      const signIn = readSignIn(config);
      return signIn ? { ...config, histerSignIn: signIn } : config;
    } catch (_) {}
  }
  return {};
}

/** config.json's permission bits (the one loadConfig read), or null. */
function configMode() {
  for (const path of configPaths()) {
    try {
      return Gio.File.new_for_path(path).query_info('unix::mode', Gio.FileQueryInfoFlags.NONE, null).get_attribute_uint32('unix::mode');
    } catch (_) {}
  }
  return null;
}

const withSlash = (u) => (u && !u.endsWith('/') ? u + '/' : u || '');

/** The web app's address for a command: the Library, or a search. */
export function startURL(webApp, command) {
  const base = withSlash(webApp);
  if (!base) return '';
  if (command.command === 'search') return `${base}#/search?${new URLSearchParams({ q: command.query, s: 'all' })}`;
  return base;
}

/** The web view's storage, once per run: the web app's settings, its service worker and the sign-ins' cookies, kept between runs. */
let webSession = null;
function networkSession() {
  if (webSession) return webSession;
  const data = GLib.build_filenamev([GLib.get_user_data_dir(), 'shiori', 'web']);
  const cache = GLib.build_filenamev([GLib.get_user_cache_dir(), 'shiori', 'web']);
  // Before 0.17.2 WebKit kept it under the program's name ("gjs"); in
  // the Flatpak that folder is Shiori's alone, so it moves over once.
  const old = GLib.build_filenamev([GLib.get_user_data_dir(), 'gjs']);
  if (GLib.getenv('FLATPAK_ID') && GLib.file_test(old, GLib.FileTest.IS_DIR) && !GLib.file_test(data, GLib.FileTest.EXISTS)) {
    GLib.mkdir_with_parents(GLib.path_get_dirname(data), 0o700);
    GLib.rename(old, data);
  }
  GLib.mkdir_with_parents(data, 0o700);
  // Its cookies are the sign-ins': yours alone, as sign-in.json is.
  GLib.chmod(data, 0o700);
  webSession = WebKit.NetworkSession.new(data, cache);
  webSession.get_cookie_manager().set_persistent_storage(GLib.build_filenamev([data, 'cookies.sqlite']), WebKit.CookiePersistentStorage.SQLITE);
  return webSession;
}

/** The first monitor's size, for the window's first size. */
function monitorSize() {
  const monitor = Gdk.Display.get_default()?.get_monitors().get_item(0);
  const g = monitor?.get_geometry();
  return g ? [g.width, g.height] : [0, 0];
}

class ShioriWindow {
  constructor(app, config, onClosed) {
    this.config = config;
    const [width, height] = fitSize(...monitorSize());
    this.window = new Adw.ApplicationWindow({ application: app, title: 'Shiori', default_width: width, default_height: height });
    const session = networkSession();
    this.view = new WebKit.WebView({ network_session: session });
    const settings = this.view.get_settings();
    settings.set_enable_developer_extras(GLib.getenv('SHIORI_DEVTOOLS') === '1');
    this.view.connect('decide-policy', (_view, decision, type) => this.decide(decision, type));
    this.view.connect('notify::title', () => {
      const title = this.view.get_title();
      this.window.set_title(title && title !== 'Shiori' ? `${title} – Shiori` : 'Shiori');
    });
    // One handler per run, for this window's downloads (the web app's exports).
    this.downloads = session.connect('download-started', (_session, download) => this.download(download));

    // The title bar: libadwaita draws the window's own, so the window
    // manager adds none; without it there was nothing to move or close it by.
    const back = new Gio.SimpleAction({ name: 'back', enabled: false });
    back.connect('activate', () => this.view.go_back());
    const reload = new Gio.SimpleAction({ name: 'reload' });
    reload.connect('activate', () => this.view.reload());
    this.window.add_action(back);
    this.window.add_action(reload);
    this.view.connect('load-changed', () => back.set_enabled(this.view.can_go_back()));
    this.view.connect('notify::uri', () => back.set_enabled(this.view.can_go_back()));
    const header = new Adw.HeaderBar();
    header.pack_start(new Gtk.Button({ icon_name: 'go-previous-symbolic', tooltip_text: 'Back', action_name: 'win.back' }));
    header.pack_start(new Gtk.Button({ icon_name: 'view-refresh-symbolic', tooltip_text: 'Reload', action_name: 'win.reload' }));
    this.toasts = new Adw.ToastOverlay({ child: this.view });
    const toolbar = new Adw.ToolbarView({ content: this.toasts });
    toolbar.add_top_bar(header);
    this.window.set_content(toolbar);
    this.window.connect('close-request', () => {
      session.disconnect(this.downloads);
      onClosed();
      return false;
    });
  }

  decide(decision, type) {
    const newWindow = type === WebKit.PolicyDecisionType.NEW_WINDOW_ACTION;
    if (type !== WebKit.PolicyDecisionType.NAVIGATION_ACTION && !newWindow) return false;
    const uri = decision.get_navigation_action().get_request().get_uri();
    const where = navigation(uri, { config: this.config, from: this.view.get_uri() || '', newWindow });
    if (where === 'view') return false;
    decision.ignore();
    // Another site, a note in Kura, a gemini:// link: the browser, or the app for the scheme.
    if (where === 'system') Gio.AppInfo.launch_default_for_uri_async(uri, null, null, null);
    // A sign-in done on the room's own page: back to the web app, now signed in.
    if (where === 'home') this.show({ command: 'open' });
    return true;
  }

  /** A download (an export): saved where the save dialog says, or not at all. */
  download(download) {
    let failed = false;
    download.connect('decide-destination', (_download, suggested) => {
      const dialog = new Gtk.FileDialog({ title: 'Save', initial_name: suggested || 'download', modal: true });
      dialog.save(this.window, null, (_dialog, result) => {
        let file = null;
        try {
          file = dialog.save_finish(result);
        } catch (_) {}
        const path = file?.get_path();
        if (!path) return download.cancel();
        download.set_allow_overwrite(true);
        download.set_destination(path);
      });
      return true;
    });
    download.connect('failed', () => {
      failed = true;
    });
    download.connect('finished', () => {
      const path = download.get_destination();
      if (!failed && path) this.toasts.add_toast(new Adw.Toast({ title: `Saved ${GLib.path_get_basename(path)}`, timeout: 3 }));
    });
  }

  show(command) {
    const url = startURL(this.config.webApp, command);
    if (url) this.view.load_uri(url);
    else this.view.load_html(
      '<body style="font:15px system-ui;padding:2em;color:#c0caf5;background:#1a1b26"><h2>Shiori isn’t set up</h2>' +
        '<p>Add the web app’s address to <code>~/.config/shiori/config.json</code>: <code>{"webApp": "https://shiori.…/"}</code></p></body>',
      null,
    );
    this.window.present();
  }
}

/** Writes to the invoking terminal: GLib 2.80's print_literal (print/printerr are C varargs, not callable from GJS). */
function say(commandLine, text, error = false) {
  const line = text.endsWith('\n') ? text : text + '\n';
  const fn = error ? commandLine.printerr_literal : commandLine.print_literal;
  if (fn) fn.call(commandLine, line);
  else (error ? printerr : print)(line.trimEnd());
}

// The windows' class is the app's ID (it was "gjs"), so the panel and
// window list match them to the desktop file and its icon.
GLib.set_prgname(APP_ID);
GLib.set_application_name('Shiori');
const app = new Adw.Application({ application_id: APP_ID, flags: Gio.ApplicationFlags.HANDLES_COMMAND_LINE });
app.connect('startup', () => {
  Gtk.Window.set_default_icon_name(APP_ID);
  app.set_accels_for_action('win.back', ['<Alt>Left']);
  app.set_accels_for_action('win.reload', ['F5', '<Control>r']);
});
let main = null;

app.connect('command-line', (_app, commandLine) => {
  const command = parseArgs(commandLine.get_arguments().slice(1));
  if (command.command === 'help' || command.command === 'error') {
    say(commandLine, `${command.message ? command.message + '\n' : ''}${command.usage}`, command.command === 'error');
    return command.command === 'error' ? 2 : 0;
  }
  if (command.command === 'quick') {
    const config = loadConfig();
    new QuickSearch(app, config, () => new SignInWindow(app, config).present()).present();
    return 0;
  }
  if (command.command === 'sign-in') {
    new SignInWindow(app, loadConfig()).present();
    return 0;
  }
  // Kura's "Save links in Shiori": its own window, not the web app.
  if (command.command === 'link' && saveLinksTarget(command.url)) {
    // Held until the window is up: the handler returns before the import does.
    app.hold();
    import('./savelinks-window.js')
      .then(({ SaveLinksWindow }) => new SaveLinksWindow(app, loadConfig(), saveLinksTarget(command.url)).present())
      .finally(() => app.release());
    return 0;
  }
  if (command.command === 'open' || command.command === 'search' || command.command === 'link') {
    // A closed window is gone: another window (quick search, sign-in) may keep the app running.
    main ??= new ShioriWindow(app, loadConfig(), () => (main = null));
    main.show(command);
    return 0;
  }
  say(commandLine, `shiori: “${command.command}” isn’t built yet`, true);
  return 1;
});

// runAsync, not run: this module awaits (search-core's import), and inside
// a blocking run() the promise jobs queued by callbacks never ran, so a
// search's reply never arrived.
const status = await app.runAsync([System.programInvocationName, ...ARGV]);
System.exit(status);
