// The window for a `shiori://save-links?…` link (Kura's note view): the
// note's (or folder's) links, what Hister holds of them, and the rest saved
// on request, as the apps' Save Links sheet. The work is savelinks.js's.

import Gtk from 'gi://Gtk?version=4.0';
import Adw from 'gi://Adw?version=1';
import { findLinks, saveLink, labelWhenSaved } from './savelinks.js';
import { fileStore } from './save.js';

const WORDS = { saved: 'Saved', queued: 'Waiting', held: 'In Hister', skipped: 'Skipped', rejected: 'Refused', failed: 'Failed', gateway: 'Sent to the gateway' };

export class SaveLinksWindow {
  constructor(app, config, target) {
    this.config = config;
    this.target = target;
    this.rows = [];
    const name = target.path ? target.path.replace(/^.*\//, '').replace(/\.md$/, '') : target.folder;
    this.window = new Adw.ApplicationWindow({ application: app, title: `Save Links from ${name}`, default_width: 640, default_height: 560 });
    this.save = new Gtk.Button({ label: 'Save Links', sensitive: false, css_classes: ['suggested-action'] });
    this.save.connect('clicked', () => this.saveSelected());
    this.labels = new Gtk.DropDown({ model: Gtk.StringList.new(['No Label']), tooltip_text: "A label from the note's tags" });
    const header = new Adw.HeaderBar();
    header.pack_start(this.labels);
    header.pack_end(this.save);
    this.list = new Gtk.ListBox({ selection_mode: Gtk.SelectionMode.NONE, css_classes: ['boxed-list'], margin_top: 12, margin_bottom: 12, margin_start: 12, margin_end: 12 });
    this.status = new Gtk.Label({ label: 'Finding the links…', wrap: true, margin_top: 24, css_classes: ['dim-label'] });
    const box = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL });
    box.append(this.status);
    box.append(this.list);
    const toolbar = new Adw.ToolbarView();
    toolbar.add_top_bar(header);
    toolbar.set_content(new Gtk.ScrolledWindow({ child: box, vexpand: true }));
    this.window.set_content(toolbar);
  }

  present() {
    this.window.present();
    this.load();
  }

  async load() {
    let found;
    try {
      found = await findLinks(this.config, this.target);
    } catch (e) {
      this.status.set_label(e.message);
      return;
    }
    this.candidates = found.candidates;
    this.labels.set_model(Gtk.StringList.new(['No Label', ...found.candidates]));
    if (!found.rows.length) {
      this.status.set_label('No links to other sites here.');
      return;
    }
    this.status.set_label('Pages are saved one at a time. Ones Hister already holds are never sent again; sites Hister skips wait for Save Anyway.');
    for (const link of found.rows) this.addRow(link);
    this.refresh();
  }

  addRow(link) {
    const open = !link.held && !link.file && !link.needsGateway;
    const check = new Gtk.CheckButton({ active: open, sensitive: open, valign: Gtk.Align.CENTER });
    // A bare link's text is its address: the host, as the apps show it.
    const host = (() => {
      try {
        return new URL(link.url).host;
      } catch (_) {
        return link.url;
      }
    })();
    const title = new Gtk.Label({ label: link.text && link.text !== link.url ? link.text : host, xalign: 0, ellipsize: 3, hexpand: true });
    const url = new Gtk.Label({ label: link.url, xalign: 0, ellipsize: 2, css_classes: ['dim-label', 'caption'] });
    const state = new Gtk.Label({
      label: link.held ? 'In Hister' : link.file ? 'A file, not a page' : link.needsGateway ? 'Needs the small-web gateway' : '',
      css_classes: ['dim-label', 'caption'], valign: Gtk.Align.CENTER,
    });
    const anyway = new Gtk.Button({ label: 'Save Anyway', visible: false, valign: Gtk.Align.CENTER, css_classes: ['flat'] });
    const text = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL, spacing: 2 });
    text.append(title);
    text.append(url);
    const box = new Gtk.Box({ spacing: 10, margin_top: 8, margin_bottom: 8, margin_start: 10, margin_end: 10 });
    box.append(check);
    box.append(text);
    box.append(anyway);
    box.append(state);
    this.list.append(box);
    const row = { link, check, state, anyway, open };
    check.connect('toggled', () => this.refresh());
    anyway.connect('clicked', () => this.saveOne(row, true));
    this.rows.push(row);
  }

  refresh() {
    const n = this.rows.filter((r) => r.open && r.check.get_active()).length;
    this.save.set_label(n === 1 ? 'Save 1 Link' : `Save ${n} Links`);
    this.save.set_sensitive(n > 0 && !this.saving);
  }

  get label() {
    const i = this.labels.get_selected();
    return i > 0 ? this.candidates[i - 1] : null;
  }

  async saveSelected() {
    this.saving = true;
    this.refresh();
    for (const row of this.rows.filter((r) => r.open && r.check.get_active())) await this.saveOne(row, false);
    this.saving = false;
    this.refresh();
  }

  async saveOne(row, anyway) {
    row.state.set_label('Saving…');
    row.anyway.set_visible(false);
    const { outcome, reason, url } = await saveLink(this.config, row.link, { label: this.label, anyway, store: (this.store ??= fileStore()) });
    row.state.set_label(WORDS[outcome] || outcome);
    // The gateway saves without a label: the chosen one goes on once it arrives.
    if (outcome === 'gateway' && this.label) {
      labelWhenSaved(this.config, url, this.label).then((ok) => ok && row.state.set_label('Saved'));
    }
    row.state.set_tooltip_text(reason || null);
    const open = outcome === 'failed' || outcome === 'skipped';
    row.open = outcome === 'failed';
    row.check.set_active(false);
    row.check.set_sensitive(row.open);
    row.anyway.set_visible(outcome === 'skipped');
    if (!open) row.check.set_sensitive(false);
    this.refresh();
  }
}
