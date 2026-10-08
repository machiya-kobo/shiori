# Shiori for Linux: developer notes

Using it: [docs/linux.md](../docs/linux.md). These notes are for working on it.

## How it works

**GJS on GTK4 + libadwaita, as a Flatpak on the GNOME 49 runtime** (older
distributions' GTK and libadwaita are too old; the runtime brings them and
WebKitGTK 6).

- **The window** is an `AdwApplicationWindow` with a WebKitGTK view on the
  **live web app**, under a header bar (Back, Reload; Alt+← and F5).
  Same-origin, so Hister's write protection and the service worker work as
  in a browser, and every server rebuild updates the app with no release.
  What stays in the window (`linux/src/window.js`): the web app, the
  frames its pages make (the preview's `about:srcdoc`, `data:`, `blob:`),
  and the sign-in pages, Hister's helper (`/machiya/` on `server`) and
  Kura's `/signin`, whose cookies the window needs; when one of those
  sends you on to its own host, the window goes back to the web app. Other
  web, `gemini:`, `gopher:`, `mailto:` and `obsidian:` links open in the
  default browser or app; nothing else is handed to the system. Its storage
  and cookies are kept in `$XDG_DATA_HOME/shiori/web` (0700). An export
  asks where to save it.
- **The quick-search window** is native: a search entry and a list, fed by
  Hister and Kura directly, reusing `search-core.js` as it is (with
  `linux/src/url.js` for `URL`, which GJS lacks). ↑/↓ or Ctrl+J/K, Return
  opens, Escape or a click outside closes. It's a full-screen, dimmed
  overlay with the search as a card: GTK 4 can't place a window on X11,
  and the window manager put a plain one in a corner. When Hister or Kura
  answers 401 or 403, it says to sign in and offers Sign In (the menu's
  search shows a Sign in to Hister row), never "Nothing matches".
- **The command line** (`linux/src/cli.js`): `shiori`, `--quick`,
  `search <words>`, `save <url> [label]`, `send`, `status`,
  `save-links [--folder] <note or folder> [label] [--dry-run]`,
  `sign-in`, `sign-out`, `pair <code> [device]`,
  `provider-search <words>`, and `shiori://` / `kura://` links. One
  `GApplication`, so a second invocation talks to the running one.
  Commands with no window (`save`, `send`, `status`, `save-links`, `pair`,
  `sign-out`, `provider-search`, `--help`) run before the application
  starts, so they work without a display: over SSH, from cron or a script.
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
  but 401/403/429 drop the page; 401/403 (not signed in, or a token Hister
  no longer takes) keep it, no attempt counted, until a sign-in; 429/5xx
  count an attempt and stop the drain, 5 attempts at most; entries older than 14 days are dropped unsent. It lives
  in `$XDG_DATA_HOME/shiori/outbox/` and drains after a save and on
  `shiori send`.

## Code and tests

- `linux/src/`: pure ES modules (URL shim, save request, outbox, command
  line, provider rows) that GJS runs as they are, tested under Node by
  `scripts/linux.test.mjs` (part of `node --test scripts/*.test.mjs`).
- `linux/gjs/`: the application, windows, libsoup requests, the file store.
  Kept thin.
- `linux/flatpak/`: the manifest, desktop file, launcher and `build.sh`
  (builds, installs for the user, writes a bundle).
- `linux/install-desktop.sh` puts the launcher in `~/.local/bin` and, on
  Cinnamon, the menu provider and the hotkey in your session. Those two
  are your **running desktop session's** settings (gsettings), whatever
  `HOME` says; `--remove` undoes them. Without Cinnamon's settings it
  installs the launcher only.
- Testing on any x86_64 Linux with gjs, Xvfb and Node:
  `gjs -m linux/gjs/selftest.js`, `linux/headless.sh OUT.png [args]` (the
  window on Xvfb in its own D-Bus session; `SHIORI_RUN="flatpak run
  io.github.machiya_kobo.Shiori"` for the Flatpak), and `linux/save-test.sh` for
  save/send/status against `linux/fake-hister.py`. Never test a write
  against a live Hister.
- **Test in a real desktop session too**: `linux/desktop-test.sh [OUT_DIR]`
  starts Cinnamon on its own virtual display and bus and runs the installed
  Flatpak against a local test page and the fake Hister (it swaps
  `~/.config/shiori/config.json` and restores it): the window's class,
  the preview's frame loading with nothing handed to the portal, an
  export's save dialog, quick search covering the screen and asking you to
  sign in, and the menu's sign-in row. `headless.sh` has no window manager
  and forces software rendering, which hid a missing title bar, windows
  placed in a corner and the portal's stray dialogs. On a machine where
  another session is logged in, the save dialog check is skipped (that
  session holds the document portal).

## The app ID

The Flatpak is `io.github.machiya_kobo.Shiori` (the GitHub organization, `machiya-kobo`, with its hyphen as an underscore, as Flatpak IDs need), and the
GApplication takes its ID from `FLATPAK_ID`. The Cinnamon menu provider's
uuid is `shiori@machiya-kobo.github.io` (it was another `shiori@…` before
0.5.5: re-run `linux/install-desktop.sh`, which removes the old provider
and switches the new one on).
