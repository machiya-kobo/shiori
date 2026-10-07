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

## Install

Build the Flatpak on the GNOME 49 runtime, then add the desktop pieces. You need `flatpak` and `flatpak-builder`.

```bash
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub org.gnome.Platform//49 org.gnome.Sdk//49
linux/flatpak/build.sh                 # builds, installs for you, and writes a single-file bundle
linux/install-desktop.sh               # the `shiori` launcher, Cinnamon's menu search, Ctrl+Alt+Space
```

Then point it at your servers in `~/.config/shiori/config.json`:

```json
{"webApp": "https://<your Shiori web app>/", "server": "https://<your Hister>/", "kura": "https://<your Kura>/"}
```

- `linux/install-desktop.sh --remove` undoes the desktop pieces.
- A bundle someone built for you installs with `flatpak install --user shiori.flatpak`.
- [The Quickstart](quickstart.md#a-standalone-with-sample-pages) builds and checks it against a Hister with sample pages.

## Shape

**GJS on GTK4 + libadwaita, as a Flatpak on the GNOME 49 runtime** (older
distributions' GTK and libadwaita are too old; the runtime brings them and
WebKitGTK 6).

Without the Flatpak (`linux/install-desktop.sh`'s launcher then runs the
checkout under GJS), the system needs gjs and the typelibs for GTK 4,
libadwaita 1.5 or later, WebKitGTK 6 and libsoup 3. On Debian 13:
`sudo apt-get install gjs gir1.2-gtk-4.0 gir1.2-adw-1 gir1.2-webkit-6.0
gir1.2-soup-3.0`. Even the commands with no window load WebKit, so all of
them are needed.

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
- **Where notes come from** in the quick search and the menu's search:
  `"notesSource": "kura"` or `"hister"`. Without it, Kura when `kura` is
  set, else Hister, which shows your default vault's notes only. The
  window's web app has its own choice (Settings → Notes → Notes From).
- **Signing in to Machiya** (when Kura runs with Machiya's identity file,
  docs/signing-in.md): put a token in the same file, `"machiyaToken":
  "mch_…"`, and `chmod 600 ~/.config/shiori/config.json`. There's no
  settings window to type it into, and the Flatpak reads the file
  read-only, so Shiori never writes it. Get one either way:
  `identity token mint <you> --label "Linux"` on the server, or a pairing
  code from `identity pair <you> --label "Linux"`, then
  `shiori pair ABCD-EFGH`, which pairs with the config's Kura and prints
  the line to add. `shiori status` says whether you're signed in and
  warns when others can read the file. The token goes only to the
  config's Kura (and `konbini` or `niwa`, if you name them), by origin:
  never to Hister, the gateway or the web app, and a request carrying it
  follows no redirect. To sign out, delete the line; revoke it on the
  server with `identity device revoke` or `identity token revoke`.
- **Hister's token** (when the server has users): `"histerToken": "…"` in
  the same file, 0600, your Hister user's one token (Hister keeps one per
  user). Sent as `X-Access-Token` to the config's `server` only, by origin
  (`linux/src/hister.js`); never the rooms, the gateway or the web app, and
  a request carrying it follows no redirect.
- **A room token** (rooms in Hister sign-in mode, when you're not signed
  in): `"roomToken": "mht_…"` in the same file, made on the helper's
  sessions page (Room Tokens) for the rooms it names. Sent as
  `Authorization: Bearer mht_…` to the config's Kura and Konbini only
  (`linux/src/machiya.js`), in place of `machiyaToken`; never to Hister. Unset, nothing is sent.
  `shiori status` says whether it's set and warns when others can read the
  file.
- **Signing in to Hister** (when it has users, docs/signing-in.md):
  `shiori sign-in` opens a small window (name and password; offered only
  while the sign-in helper on Hister's host says Hister has users). It signs
  in with Hister's own login, trades the session for the helper's id, and
  keeps both in `$XDG_DATA_HOME/shiori/sign-in.json` (0600, tied to the
  server's origin; config.json stays read-only). The session goes only to
  the config's `server` as `Cookie: hister=…`; the id only to the rooms as
  `Authorization: Bearer mhs_…` (in place of `machiyaToken`); neither
  follows a redirect. `shiori sign-out` ends it everywhere through the
  helper and deletes the file; `shiori status` says who is signed in. The
  window on the web app signs in through the hosted pages' own flow.
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

## The app ID

The Flatpak is `io.github.machiya_kobo.Shiori` (the GitHub organization, `machiya-kobo`, with its hyphen as an underscore, as Flatpak IDs need), and the
GApplication takes its ID from `FLATPAK_ID`. The Cinnamon menu provider's
uuid is `shiori@machiya-kobo.github.io` (it was another `shiori@…` before
0.5.5: re-run `linux/install-desktop.sh`, which removes the old provider
and switches the new one on).
