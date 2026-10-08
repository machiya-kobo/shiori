# Shiori for Haiku

A native Shiori for [Haiku](https://www.haiku-os.org/), written in C++ on
the Be API: search your pages in Hister and your notes in Kura, preview a
note, save a web page to Hister, and quick-search from the Deskbar.

## Install

From a release: download `shiori-<version>-1-x86_64.hpkg` from the tag's
GitHub release and install it with `pkgman install ./shiori-*.hpkg` (or
copy it to `~/config/packages`). Shiori is then in the Deskbar's
Applications menu.

## Build

On Haiku (R1/beta5 or later; the stock `haiku_devel` and gcc are enough):

```sh
cd haiku
make                        # objects.*/Shiori
make -f Makefile.test test  # the portable core's tests
./package.sh                # shiori-<version>-1-<arch>.hpkg
```

## What it does

- **Search** (Return, or a pill): **All** (Kura's top notes, then your
  pages), **Pages**, **Notes** (every vault, or one, from the vault menu)
  and **Code**. Nothing searches while you type. *Show More…* ends a list
  that has another page. Files, Small Web, the web and AI aren't in this
  app.
- **Notes From** (Settings): Kura, or Hister (the default vault only).
  Until you choose, Kura when one is set up.
- **A note's preview**: invoking a note shows it from Kura (never cached),
  or Hister's readable copy when notes come from Hister, with its links
  opening in the browser and *Open in Kura*. A page opens in the browser (WebPositive, or your preferred one).
- **Save URL** (File → Save URL…, a link dropped on the window, or
  `Shiori --save <url> [label]`): a deliberate save to Hister. When Hister
  can't take it, it waits
  in an outbox and goes on its own once Hister answers, by the iOS app's
  rules: a refusal (a skip rule, too large, sensitive) is said, not kept,
  and a page waiting 14 days is dropped.
- **The Deskbar item** (Settings → Show in Deskbar, or `Shiori --deskbar`):
  a click opens the quick search; the secondary button has Quick Search,
  Open Shiori, Save URL, Settings and Remove from Deskbar.
- **Quick search** (`Shiori --quick`, ⌘K, or the Deskbar item): a small
  floating window. Return searches, ↓ moves into the results, Return opens
  one, Command-Return hands the search to Shiori's window, Escape closes.
  To open it from anywhere, give `Shiori --quick` a key in the Shortcuts
  preferences.

Keys in the window: ⌘L the field, ⌘1–⌘4 the pills, ↓ from the field into
the results, Escape back, ⌘O open in the browser, ⇧⌘C copy the link.

## Settings and signing in

Settings live in `~/config/settings/Shiori/config.json` (mode 0600):

```json
{"server": "https://<your Hister>/", "histerToken": "", "kura": "https://<your Kura>/", "roomToken": ""}
```

- **Hister's token** (`X-Access-Token`) goes only to Hister.
- **Signing in to Hister** (Settings → Sign In…, offered while Hister has
  users and Machiya's sign-in helper is on its host): a name and password.
  Hister's session and the helper's id are kept in
  `~/config/settings/Shiori/sign-in.json` (0600), tied to that server;
  the session goes only to Hister, the id (`mhs_…`) only to Kura. Sign
  Out ends both. [signing-in.md](signing-in.md) has the protocol.
- **A room token** (`mht_…`) is Kura's credential when you're not signed
  in. Hister's token never goes to Kura.
- No request follows a redirect while it carries a credential, and the
  app talks to no host but the two you set.

Developer notes, tests and how the code is laid out: [haiku/README.md](../haiku/README.md).
