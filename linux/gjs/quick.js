// The quick-search window (docs/linux.md): opened by a hotkey
// (`shiori --quick`), keyboard only. What's typed searches your pages
// (Hister) and notes (Kura) after a pause; ↑/↓ (or Ctrl+J/K) move, Return
// opens the selection, Escape closes. A page opens in the browser, a note
// in Kura's reader. The rows are provider.js's, the same as the desktop's.
//
// It's a full-screen, dimmed overlay with the search as a card in its
// upper middle: GTK 4 can't place a window on X11, and the window manager
// put a plain one wherever it liked (a corner, under the panel). A click
// outside the card closes it, as losing focus does.

import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk?version=4.0';
import Gdk from 'gi://Gdk?version=4.0';
import Adw from 'gi://Adw?version=1';
import { activation, quickStatus } from '../src/provider.js';
import { quickResults } from './quick-results.js';

const CSS = `
window.shiori-quick { background-color: rgba(0, 0, 0, 0.32); }
.shiori-quick-card { background-color: var(--window-bg-color); color: var(--window-fg-color); border-radius: 14px; box-shadow: 0 10px 40px rgba(0, 0, 0, 0.4); }
`;
let styled = false;

export class QuickSearch {
  constructor(app, config, signIn) {
    this.config = config;
    this.signIn = signIn;
    this.generation = 0;
    if (!styled) {
      const provider = new Gtk.CssProvider();
      provider.load_from_string(CSS);
      Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
      styled = true;
    }
    this.window = new Adw.Window({ application: app, title: 'Shiori Quick Search', decorated: false });
    // Added, not set: the window's own classes (background) carry its text colours.
    this.window.add_css_class('shiori-quick');
    this.entry = new Gtk.SearchEntry({ placeholder_text: 'Search Your Pages and Notes', hexpand: true, margin_top: 12, margin_bottom: 8, margin_start: 12, margin_end: 12 });
    this.list = new Gtk.ListBox({ selection_mode: Gtk.SelectionMode.BROWSE, css_classes: ['navigation-sidebar'] });
    this.status = new Gtk.Label({ css_classes: ['dim-label'], margin_top: 24, wrap: true, justify: Gtk.Justification.CENTER, label: 'Type to search.' });
    this.signInButton = new Gtk.Button({ label: 'Sign In…', halign: Gtk.Align.CENTER, margin_top: 12, visible: false, css_classes: ['pill', 'suggested-action'] });
    this.signInButton.connect('clicked', () => this.openSignIn());
    const scroller = new Gtk.ScrolledWindow({ vexpand: true, child: this.list });
    this.card = new Gtk.Box({
      orientation: Gtk.Orientation.VERTICAL, css_classes: ['shiori-quick-card'],
      width_request: 640, height_request: 460, halign: Gtk.Align.CENTER,
    });
    this.card.append(this.entry);
    this.card.append(this.status);
    this.card.append(this.signInButton);
    this.card.append(scroller);
    // The card a quarter of the way down the free space, as launchers sit:
    // one share of it above, three below.
    const top = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL });
    top.append(new Gtk.Box({ vexpand: true }));
    top.append(this.card);
    for (let i = 0; i < 3; i++) top.append(new Gtk.Box({ vexpand: true }));
    this.window.set_content(top);

    this.entry.connect('search-changed', () => this.search());
    this.entry.connect('activate', () => this.open(this.list.get_selected_row() ?? this.list.get_row_at_index(0)));
    this.entry.connect('stop-search', () => this.window.close());
    this.list.connect('row-activated', (_list, row) => this.open(row));
    const keys = new Gtk.EventControllerKey();
    keys.connect('key-pressed', (_c, keyval, _code, state) => this.key(keyval, state));
    this.window.add_controller(keys);
    // A click on the dimmed backdrop, outside the card, closes it.
    const click = new Gtk.GestureClick();
    click.connect('pressed', (_g, _n, x, y) => {
      const picked = this.window.pick(x, y, Gtk.PickFlags.DEFAULT);
      if (!picked || !(picked === this.card || picked.is_ancestor(this.card))) this.window.close();
    });
    this.window.add_controller(click);
    this.window.connect('notify::is-active', () => {
      // Gone once it loses focus, as a launcher is (only after it had it:
      // without a window manager it may never be given focus at all).
      if (this.window.is_active) this.hadFocus = true;
      else if (this.hadFocus && !this.leaving) this.window.close();
    });
  }

  present() {
    this.window.fullscreen();
    this.window.present();
    this.entry.grab_focus();
  }

  openSignIn() {
    // The sign-in window first, so the app always has a window and keeps running.
    this.leaving = true;
    this.signIn();
    this.window.close();
  }

  key(keyval, state) {
    const ctrl = (state & 0x4) !== 0; // Gdk.ModifierType.CONTROL_MASK
    const move = (by) => {
      const at = this.list.get_selected_row()?.get_index() ?? -1;
      const next = this.list.get_row_at_index(Math.max(0, at + by));
      if (next) this.list.select_row(next);
      return true;
    };
    if (keyval === 0xff54 || (ctrl && keyval === 0x06a)) return move(1); // Down, Ctrl+J
    if (keyval === 0xff52 || (ctrl && keyval === 0x06b)) return move(-1); // Up, Ctrl+K
    if (keyval === 0xff1b) {
      this.window.close(); // Escape
      return true;
    }
    return false;
  }

  search() {
    const text = this.entry.get_text().trim();
    const mine = ++this.generation;
    if (this.timer) GLib.source_remove(this.timer);
    this.timer = 0;
    if (text.length < 2) return this.show([], { message: 'Type to search.', signIn: false });
    this.timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 250, () => {
      this.timer = 0;
      quickResults(this.config, text)
        .then((found) => mine === this.generation && this.show(found.rows, quickStatus(text, found.pages, found.notes, found.rows.length)))
        .catch(() => mine === this.generation && this.show([], quickStatus(text, 'unreachable', 'unreachable', 0)));
      return GLib.SOURCE_REMOVE;
    });
  }

  show(rows, { message, signIn }) {
    let child;
    while ((child = this.list.get_first_child())) this.list.remove(child);
    this.status.set_label(message);
    this.status.set_visible(!!message);
    this.signInButton.set_visible(signIn);
    for (const row of rows) {
      const item = new Adw.ActionRow({ title: GLib.markup_escape_text(row.name, -1), subtitle: GLib.markup_escape_text(row.description, -1), activatable: true });
      item.add_prefix(new Gtk.Image({ icon_name: row.kind === 'note' ? 'accessories-text-editor-symbolic' : 'web-browser-symbolic' }));
      item.shioriId = row.id;
      this.list.append(item);
    }
    const first = this.list.get_row_at_index(0);
    if (first) this.list.select_row(first);
  }

  open(row) {
    const target = row && activation(row.shioriId);
    if (!target) return;
    Gio.AppInfo.launch_default_for_uri_async(target.url, null, null, null);
    this.window.close();
  }
}
