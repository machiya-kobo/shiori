# Shiori for Classic Macintosh

A native Shiori for 68k Macs, from a Mac Plus on System 6 to a color Mac
on System 7: search your pages in Hister and your notes in Kura, read a
result in its own window, and quick-search from the Apple menu. Written in
C with [Retro68](https://github.com/autc04/Retro68); the code is in
[`classic/`](../classic).

## What it does

- **Search** (Return, or a pill): **All** (Kura's top notes, then your
  pages), **Pages**, **Notes** (Kura's default vault, or a shared one from
  the vault menu) and **Code**. Nothing searches while you type. *Show
  More* ends a list that has another page. Files, Small Web, the web, AI
  and saving aren't in this app.
- **Readers**: a result opens in its own window (up to three): a note from
  Kura (never Hister's copy, never cached), a page from Hister's readable
  copy. Headings, bold, italic, code, quotes, lists and links are styled.
  A link to another note in the same Kura opens it there; any other link
  shows its address, and Copy Link copies it (there's no browser).
  Find (⌘F) and Find Again (⌘G) search the text.
- **Copy Link** (Edit menu): the selected result's or reader's address.
- **Shiori Search**, the desk accessory: a small window in the Apple menu,
  over any application. Return searches (three notes, then your pages);
  Return or a double-click on a result opens it in Shiori's reader on
  System 7 (launching Shiori if needed) and copies its link on System 6.
- **System 7**: Balloon Help for the window and the menus, the required
  Apple events, and color: on a color screen the pills wear Shiori's
  colors and titles the accent; on a gray screen, dark grays. Every color
  is at least 4.5:1 on white, from the screen's own palette.

Keys: Tab moves between the field and the results, ↑ ↓ choose a result,
Return opens it, ⌘1–⌘4 pick the pill, ⌘. stops a search. (A Mac Plus with
the original M0110 keyboard has no arrows: use Tab and the Search menu.)

## What it needs

- A Mac with a 68000 or later and 1 MB free for Shiori (640 KB at least),
  System 6.0.8 or System 7.x, and MacTCP 2.0.6 or later on Ethernet (a
  Mac Plus works with a BlueSCSI or other DaynaPORT-compatible SCSI
  Ethernet).
- **The bridge** (`mac-bridge`, [`classic/bridge/`](../classic/bridge)).
  MacTCP has no TLS and Shiori here resolves no names, so the Mac talks
  plain HTTP/1.0 to a small proxy on your LAN, by IP address: one port
  for Hister and one for Kura, a few read-only paths, passed on over HTTPS.
  Run it next to Hister, published on its LAN address only, and list your
  Mac's address in `BRIDGE_ALLOW`. Its README covers what it refuses and
  what passes.
- **A room token** (`mht_…`) for the Mac, made on the sign-in helper's
  sessions page (Room Tokens) with two scopes: `kura` and the bridge's.
  Kura checks it; on the Hister port the bridge checks it with the helper
  and only then swaps in Hister's own token, which never reaches the LAN.

## Installing

From a release, use the `.dsk` (an 800K floppy image, for a BlueSCSI's SD
card, an emulator or a floppy), the `.sit` (StuffIt) or the `.sit.hqx`.
Each holds three files:

- **Shiori**: the application. Copy it anywhere.
- **Shiori Search**: the desk accessory, as a Font/DA Mover suitcase. On
  System 6, install it into the System file with Font/DA Mover. On
  System 7, double-click it and drag *Shiori Search* to the System Folder
  (or the Apple Menu Items folder). Shiori's own Apple menu carries it
  too, without installing anything.
- **About Shiori**: a short read-me.

## Settings

File → Preferences…: the bridge's two addresses
(`http://<IP address>:<port>/`), the room token, and the reader's text
size. On first launch the dialog opens on its own. They're kept in
*Shiori Preferences* (the Preferences folder on System 7, the System
Folder on System 6), on this Mac only. The token is in that file in
clear, since classic Mac OS has no keychain: keep it off shared disks.
The desk accessory reads the same file.

## What stays private

- The room token goes only to the two bridge addresses (by origin), never
  across a redirect (Shiori follows none).
- A note's vault comes from its address. Notes searches only the default
  vault and vaults Kura marks shared; a private vault is never offered,
  and the bridge refuses any vault not on its list. The desk accessory
  searches the default vault only, and Shiori refuses a request (an Apple
  event) to open a note from any other.
- Replies are capped (256 KB for a search, 192 KB for a reader, 64 KB in
  the desk accessory, and the bridge's own cap), and nothing is written to
  disk but Preferences.

## Building and testing

`classic/scripts/build.sh` builds the app, the desk accessory and the
suitcase with Retro68; `classic/scripts/package.sh` makes the release
files with neutral defaults. The portable core (`classic/core/`, C89) is
tested on any machine by `node --test scripts/classic.test.mjs`, and its
search queries are search-core's twins (`classic/tests/vectors.h`,
generated by `haiku/tests/gen-vectors.mjs --c`). Snow (System 6, Mac
Plus) and Basilisk II (System 7, every depth) runs are described in
[`classic/docs/TESTING.md`](../classic/docs/TESTING.md).
