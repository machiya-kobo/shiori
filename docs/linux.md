# Shiori for Linux

Shiori for the Linux desktop: the web app in its own window, made for Cinnamon (Linux Mint) on X11, plus what a web page can't do:

1. **Search from the desktop**: Cinnamon's menu shows your pages and notes for what's typed.
2. **A quick-search window on a hotkey** (Ctrl+Alt+Space), keyboard only.
3. **Save outside the browser**: `shiori save <url> [label]`, with an offline outbox, as the iOS share extension has.
4. **Save a note's links**: `shiori save-links <note>` saves the links in a Kura note that Hister doesn't hold yet. Kura's note view opens a window to pick them.

No AI, no rule editor, nothing the web view already does. Hister's own browser extension captures what you visit.

## Install

Build the Flatpak on the GNOME 49 runtime, then add the desktop pieces. You need `flatpak` and `flatpak-builder`.

```bash
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user -y flathub org.gnome.Platform//49 org.gnome.Sdk//49
linux/flatpak/build.sh                 # builds, installs for you, and writes a single-file bundle
linux/install-desktop.sh               # the `shiori` launcher, Cinnamon's menu search, Ctrl+Alt+Space
```

Then point it at your servers in `~/.config/shiori/config.json`:

```json
{"webApp": "https://<your Shiori web app>/", "server": "https://<your Hister>/", "kura": "https://<your Kura>/"}
```

- `linux/install-desktop.sh` changes your running desktop session's settings (the menu search and the hotkey); `--remove` undoes them. Without Cinnamon it installs the launcher only.
- A bundle someone built for you (a release's `Shiori-X.Y.Z-linux-x86_64.flatpak`) installs with `flatpak install --user shiori.flatpak`, which fetches GNOME 49 from Flathub.
- [The Quickstart](quickstart.md#a-standalone-with-sample-pages) builds and checks it against a Hister with sample pages.

**Without the Flatpak**, the launcher runs the checkout under GJS. The system then needs gjs and the typelibs for GTK 4, libadwaita 1.5 or later, WebKitGTK 6 and libsoup 3 (every command needs them, even those with no window). On Debian 13:

```bash
sudo apt-get install gjs gir1.2-gtk-4.0 gir1.2-adw-1 gir1.2-webkit-6.0 gir1.2-soup-3.0
```

## Use it

- **The window** is the web app, with Back and Reload (Alt+← and F5). Other links open in your browser, or in the app for `gemini:`, `gopher:`, `mailto:` and `obsidian:` links.
- **Quick search** (Ctrl+Alt+Space, or `shiori --quick`): ↑/↓ or Ctrl+J/K, Return opens, Escape closes. It asks you to sign in when Hister or Kura says 401 or 403.
- **The menu's search** (Cinnamon): your pages, then your notes, a few each.

| Command | What it does |
|---|---|
| `shiori` | Opens the window |
| `shiori --quick` | Opens quick search |
| `shiori search <words>` | Opens the window on a search |
| `shiori save <url> [label]` | Saves a page to Hister |
| `shiori send` | Sends what's waiting in the outbox |
| `shiori status` | Says what's waiting, and who's signed in |
| `shiori save-links [--folder] <note or folder> [label] [--dry-run]` | Saves a note's (or a folder's) links. Skip rules hold: save a skipped site with `shiori save <url>` |
| `shiori sign-in`, `shiori sign-out` | Signs in to Hister, or out |
| `shiori pair <code> [device]` | Pairs with Kura and prints the line to add |

The commands with no window (`save`, `send`, `status`, `save-links`, `pair`, `sign-out`) work without a display: over SSH, from cron or a script. Over SSH with no desktop, put `dbus-run-session --` in front of `flatpak run`.

**Saves** wait in an outbox when Hister can't take them and go on their own, by the iOS app's rules: a refusal (a skip rule, too large, sensitive) is said, not kept, and after 14 days a waiting page is dropped.

## Notes

Notes come from Kura, or from Hister (`"notesSource": "hister"` in config.json, or no `kura` set), which shows the default vault's notes only. From Kura, quick search may include other vaults; the menu's search asks for the default vault only. A note from a private vault is never cached, exported or sent to Hister. The window's web app has its own choice (Settings → Notes → Notes From).

## Configuration and signing in

Everything is in `~/.config/shiori/config.json`. The Flatpak reads it and never writes it. When it holds a token, `chmod 600` it; `shiori status` warns when others can read it.

- **`webApp`, `server` (Hister), `kura`**, and optionally **`smallweb`** (the small-web gateway, for saving a note's `gemini://` and `gopher://` links).
- **`notesSource`**: `"kura"` or `"hister"`. Without it, Kura when `kura` is set, else Hister.
- **Hister's token** (when Hister has users): `"histerToken": "…"`. It goes only to `server`, never across a redirect.
- **Signing in to Hister** (when it has users and Machiya's sign-in helper is on its host): `shiori sign-in` opens a small window for your name and password. The session goes only to `server`, the helper's id only to Kura (and `konbini` or `niwa`, if you name them). Both are kept in `$XDG_DATA_HOME/shiori/sign-in.json` (0600); `shiori sign-out` ends them. The window signs in through the web app's own flow.
- **Signing in to Machiya** (when Kura runs with Machiya's identity file): `"machiyaToken": "mch_…"`. Make one on the server with `python3 -m vaultkit.identity token mint <you> --label Linux`, or make a pairing code with `python3 -m vaultkit.identity pair <you> --label Linux` and run `shiori pair ABCD-EFGH` ([machiya identity.md](https://github.com/machiya-kobo/machiya/blob/main/docs/identity.md)). It goes only to Kura (and `konbini` or `niwa`, if you name them), never across a redirect. To sign out, delete the line and revoke it on the server.
- **A room token** (when Kura uses Hister's sign-in and you're not signed in): `"roomToken": "mht_…"`, made on the sign-in helper's sessions page. It goes where `machiyaToken` would, in its place; never to Hister.

Shiori talks to no host the config doesn't name, except the page `shiori save` was asked to download. Your network (your tailnet's or LAN's rules) is the real boundary: Flatpak's network permission is all or nothing. [signing-in.md](signing-in.md) has the protocols.

## The app ID

The Flatpak is `io.github.machiya_kobo.Shiori`. Before 0.5.5 the Cinnamon menu search had another ID: re-run `linux/install-desktop.sh` to switch.

Developer notes, tests and how the code is laid out: [linux/README.md](../linux/README.md).
