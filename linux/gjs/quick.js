// The quick-search window (docs/linux.md): opened by a hotkey
// (`shiori --quick`), keyboard only. What's typed searches your pages
// (Hister) and notes (Kura) after a pause; ↑/↓ (or Ctrl+J/K) move, Return
// opens the selection, Escape closes. A page opens in the browser, a note
// in Kura's reader. The rows are provider.js's, the same as the desktop's.

import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk?version=4.0';
import Adw from 'gi://Adw?version=1';
import { activation } from '../src/provider.js';

import { quickResults } from './quick-results.js';

export class QuickSearch {
  constructor(app, config) {
    this.config = config;
    this.generation = 0;
    this.window = new Adw.Window({ application: app, title: 'Shiori Quick Search', default_width: 640, default_height: 460, modal: false });
    this.entry = new Gtk.SearchEntry({ placeholder_text: 'Search Your Pages and Notes', hexpand: true, margin_top: 12, margin_bottom: 8, margin_start: 12, margin_end: 12 });
    this.list = new Gtk.ListBox({ selection_mode: Gtk.SelectionMode.BROWSE, css_classes: ['navigation-sidebar'] });
    this.status = new Gtk.Label({ css_classes: ['dim-label'], margin_top: 24, label: 'Type to search.' });
    const scroller = new Gtk.ScrolledWindow({ vexpand: true, child: this.list });
    const box = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL });
    box.append(this.entry);
    box.append(this.status);
    box.append(scroller);
    this.window.set_content(box);

    this.entry.connect('search-changed', () => this.search());
    this.entry.connect('activate', () => this.open(this.list.get_selected_row() ?? this.list.get_row_at_index(0)));
    this.entry.connect('stop-search', () => this.window.close());
    this.list.connect('row-activated', (_list, row) => this.open(row));
    const keys = new Gtk.EventControllerKey();
    keys.connect('key-pressed', (_c, keyval, _code, state) => this.key(keyval, state));
    this.window.add_controller(keys);
    this.window.connect('notify::is-active', () => {
      // Gone once it loses focus, as a launcher is (only after it had it:
      // without a window manager it may never be given focus at all).
      if (this.window.is_active) this.hadFocus = true;
      else if (this.hadFocus) this.window.close();
    });
  }

  present() {
    this.window.present();
    this.entry.grab_focus();
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
    if (text.length < 2) return this.show([], 'Type to search.');
    this.timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 250, () => {
      this.timer = 0;
      quickResults(this.config, text)
        .then((rows) => mine === this.generation && this.show(rows, rows.length ? '' : `Nothing matches “${text}”.`))
        .catch(() => mine === this.generation && this.show([], 'Hister didn’t answer.'));
      return GLib.SOURCE_REMOVE;
    });
  }

  show(rows, message) {
    let child;
    while ((child = this.list.get_first_child())) this.list.remove(child);
    this.status.set_label(message);
    this.status.set_visible(!!message);
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
