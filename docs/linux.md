# Shiori for Linux

A small native Shiori for a Linux desktop, made for Cinnamon (Linux Mint) on
X11. The web app already browses and searches anywhere, and Hister's own
browser extension captures what's visited; the Linux app adds what a web
page can't do:

1. **Search from the desktop**: Cinnamon's menu shows your pages and notes
   for what's typed.
2. **A quick-search window on a hotkey** (Ctrl+Alt+Space), keyboard only.
3. **Saving outside the browser**: `shiori save <url> [label]`, with an
   offline outbox, as the iOS share extension has.

4. **Saving a note's links**: `shiori save-links <note path> [label]` (or
   `--folder <folder>`, `--dry-run`) saves the outside links of a note in
   Kura that Hister doesn't hold yet, and a `shiori://save-links?path=…`
   link (Kura's note view) opens a small window to pick them. Skip rules
   hold; a skipped site is saved with `shiori save <url>`.

No AI, no rule editor, nothing the web view already does.

## Shape

**GJS on GTK4 + libadwaita, as a Flatpak on the GNOME 49 runtime** (older
distributions' GTK and libadwaita are too old; the runtime brings them and
WebKitGTK 6).

- **The window** is an `AdwApplicationWindow` with a WebKitGTK view on the
  **live web app**. Same-origin, so Hister's write protection and the
  service worker work as in a browser, and every server rebuild updates the
  app with no release. Links to other hosts open in the default browser.
- **The quick-search window** is native: a search entry and a list, fed by
  Hister and Kura directly, reusing `search-core.js` as it is (with
  `linux/src/url.js` for `URL`, which GJS lacks). ↑/↓ or Ctrl+J/K, Return
  opens, Escape closes.
- **The command line** (`linux/src/cli.js`): `shiori`, `--quick`,
  `search <words>`, `save <url> [label]`, `send`, `status`,
  `provider-search <words>`, and `shiori://` / `kura://` links. One
  `GApplication`, so a second invocation talks to the running one.
  Commands with no window (`save`, `send`, `status`, `provider-search`,
  `--help`) run before the application starts, so they work without a
  display: over SSH, from cron or a script.
- **The desktop search provider**: Cinnamon's menu providers are JS files
  outside any Flatpak, so a thin one (`linux/cinnamon/`) runs
  `shiori provider-search <words>` (JSON, ~0.15 s) and shows the latest
  keystroke's rows: your pages, then your notes, a few each.
- **The hotkey**: Cinnamon has no GlobalShortcuts portal, so it's a custom
  keyboard shortcut running `shiori --quick`.

## Writes

**`shiori save` is the only native write.** Everything else writes from the
web view, same-origin.

- It downloads the page (3 MB cap, HTML or text only, `linux/src/page.js`)
  and POSTs `api/add` with `Origin: hister://`, as a deliberate save:
  `metadata.ignore_skip_rules`, `source: "shiori"`, `client: "shiori"`,
  `client_version`, `via: "linux"`.
- **The outbox** (`linux/src/outbox.js`) follows the iOS rules: one entry
  per URL keeping its first time; oldest first; 406/413/422 and other 4xx
  but 429 drop the page; 429/5xx count an attempt and stop the drain, 5
  attempts at most; entries older than 14 days are dropped unsent. It lives
  in `$XDG_DATA_HOME/shiori/outbox/` and drains after a save and on
  `shiori send`.

## Notes

Notes come only from Kura. The quick search's Notes may include other
vaults; the desktop provider asks for the default vault only. A note from
a private vault is never cached, exported or sent to Hister.

## Configuration and privacy

- `~/.config/shiori/config.json`: `webApp`, `server` (Hister), `kura`, and
  optionally `smallweb` (the small-web gateway, for saving a note's
  `gemini://` and `gopher://` links). The
  Flatpak reads it read-only (`--filesystem=xdg-config/shiori:ro`); that
  mount also covers the app's own config dir, so the host's file is the one
  it reads.
- The HTTP client (`linux/gjs/http.js`, libsoup 3) refuses hosts the config
  doesn't name, except the page `shiori save` was asked to download. The
  network itself (your tailnet's or LAN's access rules) is the real
  boundary: Flatpak's network permission is all or nothing.

## Code and tests

- `linux/src/`: pure ES modules (URL shim, save request, outbox, command
  line, provider rows) that GJS runs as they are, tested under Node by
  `scripts/linux.test.mjs` (part of `node --test scripts/*.test.mjs`).
- `linux/gjs/`: the application, windows, libsoup requests, the file store.
  Kept thin.
- `linux/flatpak/`: the manifest, desktop file, launcher and `build.sh`
  (builds, installs for the user, writes a bundle).
- `linux/install-desktop.sh` puts the launcher, the menu provider and the
  hotkey in your session; `--remove` undoes it.
- Testing on any x86_64 Linux with gjs, Xvfb and Node:
  `gjs -m linux/gjs/selftest.js`, `linux/headless.sh OUT.png [args]` (the
  window on Xvfb in its own D-Bus session; `SHIORI_RUN="flatpak run
  io.github.machiya_kobo.Shiori"` for the Flatpak), and `linux/save-test.sh` for
  save/send/status against `linux/fake-hister.py`. Never test a write
  against a live Hister.

## The app ID

The Flatpak is `io.github.machiya_kobo.Shiori` (the GitHub organisation, `machiya-kobo`, with its hyphen as an underscore, as Flatpak IDs need), and the
GApplication takes its ID from `FLATPAK_ID`. The Cinnamon menu provider's
uuid is `shiori@machiya-kobo.github.io`.
