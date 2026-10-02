// Shiori in Cinnamon's menu search (docs/linux.md): your pages from
// Hister, then your notes from Kura, for what's typed. The work is done by
// `shiori provider-search` (the app's own code, JSON out); this file only
// runs it and shows the rows. Installed by linux/install-desktop.sh.

const Gio = imports.gi.Gio;
const GLib = imports.gi.GLib;
const St = imports.gi.St;
const Util = imports.misc.util;

const HERE = GLib.build_filenamev([GLib.get_user_data_dir(), 'cinnamon', 'search_providers', 'shiori@machiya-kobo.github.io']);
// The launcher install-desktop.sh writes; `shiori` on the PATH otherwise.
const LAUNCHER = [GLib.build_filenamev([GLib.get_home_dir(), '.local', 'bin', 'shiori']), 'shiori'].find(
    (p) => p.indexOf('/') < 0 || GLib.file_test(p, GLib.FileTest.IS_EXECUTABLE));

let latest = 0;

function icon(kind) {
    const gicon = kind === 'note'
        ? new Gio.ThemedIcon({ name: 'accessories-text-editor-symbolic' })
        : new Gio.FileIcon({ file: Gio.File.new_for_path(GLib.build_filenamev([HERE, 'icon.png'])) });
    return new St.Icon({ gicon: gicon, icon_size: 22, icon_type: St.IconType.FULLCOLOR });
}

function perform_search(pattern) {
    const text = String(pattern || '').trim();
    const mine = ++latest;
    if (text.length < 2) return;
    let proc;
    try {
        proc = Gio.Subprocess.new([LAUNCHER, 'provider-search', text], Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
    } catch (e) {
        global.logError('[shiori] ' + e.message);
        return;
    }
    proc.communicate_utf8_async(null, null, (p, result) => {
        let rows = [];
        try {
            const [, out] = p.communicate_utf8_finish(result);
            rows = JSON.parse(out || '[]');
        } catch (e) {
            return;
        }
        // Only the latest search's answer: typing runs one per keystroke.
        if (mine !== latest) return;
        send_results(rows.map((r) => ({ id: r.url, label: r.name, description: r.description, icon: icon(r.kind) })));
    });
}

function on_result_selected(result) {
    // A page opens in the browser, a note in Kura's reader.
    Util.spawn(['xdg-open', result.id]);
}
