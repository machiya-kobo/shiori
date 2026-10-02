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
import Adw from 'gi://Adw?version=1';
import WebKit from 'gi://WebKit?version=6.0';
import System from 'system';
import { installURL } from '../src/url.js';
import { parseArgs, saveLinksTarget } from '../src/cli.js';
import { QuickSearch } from './quick.js';
import { save, sendWaiting, waitingStatus } from './save.js';
import { pairedMessage, signInStatus } from '../src/machiya.js';

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
    let rows = [];
    if (early.query.length >= 2) rows = await quickResults(loadConfig(), early.query).catch(() => []);
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
    if (early.command === 'status') r.message += '\n' + signInStatus(config, configMode(), globalThis.ShioriSearch);
    (r.code !== 0 ? printerr : print)(r.message);
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

/** The configuration, or {} when there's none (the window then says so). */
function loadConfig() {
  for (const path of configPaths()) {
    try {
      const [, bytes] = GLib.file_get_contents(path);
      return JSON.parse(new TextDecoder().decode(bytes)) || {};
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

/** Off the web app's host, a link opens in the default browser (a gemini:// link in its app). */
function sameOrigin(a, b) {
  try {
    return new URL(a).origin === new URL(b).origin;
  } catch (_) {
    return false;
  }
}

class ShioriWindow {
  constructor(app, config) {
    this.config = config;
    this.window = new Adw.ApplicationWindow({ application: app, title: 'Shiori', default_width: 1200, default_height: 800 });
    this.view = new WebKit.WebView();
    const settings = this.view.get_settings();
    settings.set_enable_developer_extras(GLib.getenv('SHIORI_DEVTOOLS') === '1');
    this.view.connect('decide-policy', (_view, decision, type) => this.decide(decision, type));
    this.view.connect('notify::title', () => {
      const title = this.view.get_title();
      this.window.set_title(title && title !== 'Shiori' ? `${title} – Shiori` : 'Shiori');
    });
    this.window.set_content(this.view);
  }

  decide(decision, type) {
    if (type !== WebKit.PolicyDecisionType.NAVIGATION_ACTION && type !== WebKit.PolicyDecisionType.NEW_WINDOW_ACTION) return false;
    const uri = decision.get_navigation_action().get_request().get_uri();
    if (sameOrigin(uri, this.config.webApp) && type === WebKit.PolicyDecisionType.NAVIGATION_ACTION) return false;
    // Everything else (another site, a note in Kura, a gemini:// link) goes
    // to the system: the browser, or the app that handles the scheme.
    decision.ignore();
    Gio.AppInfo.launch_default_for_uri_async(uri, null, null, null);
    return true;
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

const app = new Adw.Application({ application_id: APP_ID, flags: Gio.ApplicationFlags.HANDLES_COMMAND_LINE });
let main = null;

app.connect('command-line', (_app, commandLine) => {
  const command = parseArgs(commandLine.get_arguments().slice(1));
  if (command.command === 'help' || command.command === 'error') {
    say(commandLine, `${command.message ? command.message + '\n' : ''}${command.usage}`, command.command === 'error');
    return command.command === 'error' ? 2 : 0;
  }
  if (command.command === 'quick') {
    new QuickSearch(app, loadConfig()).present();
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
    main ??= new ShioriWindow(app, loadConfig());
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
