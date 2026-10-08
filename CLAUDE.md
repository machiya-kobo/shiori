# Shiori: guide for contributors and coding agents

Shiori is a search client for a [Hister](https://github.com/asciimoo/hister)
server (your own full-text search of the pages you've read). It's one app of
[Machiya](https://github.com/machiya-kobo/machiya), a set of small
self-hosted apps. Read this before changing code: it holds the rules and
the traps the code can't tell you. README has a short Quickstart; `docs/` has
the rest (quickstart.md is the tested walkthrough; build.md, extension.md,
signing-in.md, ai.md, linux.md, haiku.md, classic.md, smallweb.md,
features.md). `CONTRIBUTING.md` says how to send a change.

## Layout

| Path | What it is |
|---|---|
| `Shiori/`, `Shared/`, `ShioriShare/`, `ShioriExtension/` | The iPhone, iPad and Mac apps, the share extensions and the Safari extension. `project.yml` (XcodeGen) generates `Shiori.xcodeproj`. |
| `Packages/HisterKit`, `Packages/ShioriAI` | The Hister, Kura and SearXNG clients (Swift); the AI engines. |
| `patches/` | The Safari extension: patches applied to upstream Hister's built extension (`vendor/hister`, a submodule), and the search page `patches/shiori/search.*` with `search-core.js`, the logic shared with Swift. |
| `web/`, `scripts/` | The web app (`web/app/`, a PWA), the dev server, the build scripts and the Node tests. |
| `linux/`, `haiku/`, `classic/` | Shiori for Linux (GJS Flatpak), Haiku (C++ on the Be API) and Classic Macintosh (C on Retro68), with `classic/bridge/` (mac-bridge, a LAN proxy). |
| `tools/` | The Quickstart test, the sample data and the screenshot tool. |

## Setup, build, test

From a fresh clone (`git clone --recurse-submodules`; or `git submodule update --init`):

- **Web pages** (any machine with bash and Python 3):
  `scripts/build-web.sh demo-site http://localhost:8765/`,
  `scripts/build-pwa.sh demo-app`, then
  `HISTER_URL=http://127.0.0.1:4433/ web/dev-server.py demo-site` (the web app
  too, with `PORT=8766`). docs/quickstart.md runs a throwaway Hister with
  sample pages (`tools/quickstart/seed-hister.py`); `tools/quickstart-test`
  checks that walkthrough, and README's Quickstart blocks must match it.
- **Apple apps** (Xcode 27, `brew bundle`): `cp local.yml.example local.yml`
  and set `DEVELOPMENT_TEAM` and your own `SHIORI_BUNDLE_PREFIX`, then
  `scripts/build.sh ios|macos`, `scripts/install-mac.sh` or
  `scripts/deploy-device.sh` (docs/build.md). Use an iOS 27 simulator.
- **Linux**: `linux/flatpak/build.sh`, then `linux/install-desktop.sh`
  (docs/linux.md). **Haiku**: `cd haiku && make` on Haiku, `./package.sh` for
  the `.hpkg`. **Classic**: `classic/scripts/build.sh` (Retro68),
  `SHIORI_RELEASE=1 classic/scripts/package.sh` for release files.
- **Tests**, after touching:
  - `patches/`, `scripts/`, `web/`, `linux/`, `haiku/core`, `classic/core`:
    `node --test scripts/*.test.mjs` (Node 22 fails on the folder form). It
    also runs the Haiku core's C++ tests and mac-bridge's Python tests
    (`python3 -m unittest discover -s classic/bridge`) where a compiler or
    Python exists.
  - `Packages/HisterKit`, `Packages/ShioriAI`: `swift test` there.
  - `Shared/`: `xcodebuild test -scheme ShioriTests -destination platform=macOS`.
  - Linux modules in a real GJS: `gjs -m linux/gjs/selftest.js`;
    windows: `linux/desktop-test.sh` (Cinnamon on a virtual display), not
    only `linux/headless.sh`: with no window manager the window had no title
    bar and quick search sat in a corner.
  - Haiku UI: `haiku/tests/ui-run.sh` on a Haiku machine, against
    `haiku/fake-services.py`. Classic: `classic/docs/TESTING.md`.
  - `HISTER_LIVE_URL` and `KURA_LIVE_URL` add read-only checks against
    real servers. `tests/test_private_names.py` scans tracked files for the
    names listed in `~/.config/machiya/private-names` (skipped without it).
- **Never test a write against a live Hister.** Use the stubs in the tests,
  `linux/fake-hister.py`, or a throwaway Hister. Reads against your own are fine.

## Rules

- **Never modify `vendor/hister/`.** Safari behavior lives in `patches/`,
  applied to the built `dist/` by `scripts/build-extension.sh`. Upgrade by
  moving the submodule to an upstream tag; the Hister server runs the
  matching version.
- **Never edit generated files**: `Shiori.xcodeproj/`,
  `ShioriExtension/Resources/`, `build/`, `web/app/palettes.css` and
  `HisterKit/Palettes.swift` (made by `node scripts/palettes.mjs` from
  `web/app/palettes.json`). Change `project.yml`, `patches/` or the table.
- **Never commit personal details, preferences or settings.** The repository
  ships neutral defaults only. Server addresses, hostnames, network names,
  people's names, logins and emails, device names, team IDs, vault and
  folder names, tokens and anyone's own settings (`.env`, `local.*`, the
  identity file `identity.toml`, `prefs.sqlite3`) stay outside it: in the
  gitignored `local.yml` and `local.env`, or the deployment's own repository.
  Code, tests, fixtures, docs, comments, screenshots and commit messages use
  `example.com`, `example.ts.net`, "the user" and the sample vault. Check the
  diff before you push: history can't take them back.
- **No new network endpoints** without discussion. Shiori talks to the
  configured Hister server (and on its host the optional companion services
  `/shiori/feed` and `/shiori/ai/*`, hosted pages only, the latter only in a
  build with `SHIORI_AI=1`), Kura (notes), the small-web gateway, SearXNG, the
  visited site's favicon and PDFs (upstream behavior). With Machiya's identity
  file, Kura's `POST /api/pair` and, from the web app, Kura's `/api/prefs`.
  NewsBlur, status pages, the Wayback Machine and archive.is copies and the
  build's privacy front ends (`SHIORI_FRONTENDS`: `Elsewhere`) are only
  opened as links; `gemini://` and `gopher://` links are handed to the
  system, never fetched. The classic Mac reaches Hister and Kura only
  through mac-bridge. No analytics. AI providers only when the user turns AI
  on, and only from the app.
- **Never re-add the `cookies` permission.** The extension uses Hister's
  token (`X-Access-Token`), never a session or a cookie.
- **Logic shared by Swift and JavaScript has twins** (HisterKit and
  `patches/shiori/search-core.js`) with the same test cases. Change both.
- **No rule editor in the app**: the server's rules are the truth. Shiori
  edits aliases only through Keep Collections Current (docs/ai.md). Only
  `@`-aliases are collections (`Rules.isCollectionKeyword` /
  `S.isCollectionKeyword`); an alias about the vault (`@notes`, `@pages`) is not.
- **Credentials** (docs/signing-in.md). Hister's token (`X-Access-Token`)
  goes to the Hister server and nowhere else; never in a URL, a log, a
  settings file or the offline queue, and no request carrying one follows a
  redirect. The Machiya token (`mch_…` pasted, `mcd_…` from `POST /api/pair`)
  goes in `Authorization: Bearer`, only to the configured Kura and Konbini by
  origin (`S.machiyaRooms` / `Machiya.rooms`, twins), never across a
  redirect; rooms in Hister sign-in mode get the app's `mhs_` id, Linux and
  Haiku a room token (`mht_`). Tokens live in the Keychain
  (`HisterKeychain`, `MachiyaKeychain`) or Linux and Haiku's `config.json`:
  never UserDefaults, never logged. The Safari extension holds Hister's token
  in the background's memory only, never storage, and hands tokens to its own
  pages only, never a content script; its fetches keep `credentials: 'omit'`.
  The hosted pages hold none: the browser's `machiya_session` cookie goes to
  `/kura/` and `/konbini/` only.
- Never put `.searchSuggestions(.hidden, for: .content)` on a sheet's
  `.searchable`: on iOS 27 the sheet went blank.
- **A note from a private vault** (address `/v/<vault>/n/…`; a vault Kura's
  `/api/vaults` doesn't mark `private: false`) never goes to Hister, any AI
  engine (on-device included), a cache, an export or a feed. Clients fail
  closed, and ask Kura afresh before anything about another vault's note goes
  to Hister or a model. The full rule is in `Packages/HisterKit/CLAUDE.md`.
- **The settings that follow the person** are only the shared ones (theme,
  appearance, text size, pills) and `shiori.*` options; never an address, a
  sign-in, a token, an AI setting or a device-only one. Details in
  `Packages/HisterKit/CLAUDE.md`.

## Conventions

- **American English** ("behavior", "color", "license", "labeled"), plain,
  short, verb-first; Title Case for labels and empty states. Machiya's
  [docs/voice.md](https://github.com/machiya-kobo/machiya/blob/main/docs/voice.md)
  has the voice. Keep footers to a sentence or two and tooltips to a few words.
- **Themes are generated.** Ten themes, each dark and light, from
  `web/app/palettes.json` through `node scripts/palettes.mjs` (CSS and
  Swift). Every text color is at least 4.5:1 on its background and surface,
  held by `scripts/theme-contrast.test.mjs`, `scripts/palettes.test.mjs` and
  `SnippetAndSuggestionTests`. New colors go in the tests.
- **Liquid Glass stays on the system chrome**: the theme colors only the
  content layer. Result cards are tinted in their pill's color (pages blue,
  notes orange, opened purple, files green, code red, Small Web teal).
- **Hover shows what a click does** (Machiya's style guide). A result's title
  is a plain `TitleLink` button, underlined with the link cursor (a
  borderless button is AppKit's on the Mac and its label never hears hover).
  A sidebar row fills 14% with the accent across its whole cell
  (`sidebarHover`). An unselected pill lifts onto 24% of its color over
  `raised`, its text moved to the shade that reads there
  (`Palette.pillHover`, the web's `--<pill>-hover-bg` / `--<pill>-hover`:
  twins from `palettes.mjs` `PILLS`, 4.5:1 in every theme, tested).
  Sidebar headings are teal; a tab's heading on the search page wears the
  tab's color. **Every UI change goes into the apps, the web app and the
  search page alike.**
- **Text size: `.textStyle(.headline)`, never `.font(.headline)`**: macOS has
  no Dynamic Type; `macTextScale` scales the Mac, and `@ScaledMetric` sizes
  need it too.
- **Nothing searches while typing**: Return, the field's magnifier, a recent
  search, Did you mean or a pill runs a search (apps, web app and search
  page; the "Search in" fields too). Type-ahead still shows.
- **Web searches are frugal** (each counts against a paid search API): the web
  is asked only for a search run on purpose (`SearchSession.webAllowed`, the
  web app's `w=1`); respellings come from the autocompleter, never a `/search`.
- **A click on a result** opens the original or Shiori's preview as Settings →
  Click Opens says (per device, never sent to the account); the title always
  opens the original; chips and links inside a result keep their own. Every
  delete is Undo, not a confirmation: it goes to Hister only after the toast.
- **Releases**: bump `MARKETING_VERSION` (project.yml) and `VERSION`
  (linux/gjs/save.js) together and add a `## X.Y.Z (date)` section to
  CHANGELOG.md (minor for features, patch for fixes; a test holds all three),
  then tag `vX.Y.Z`. docs/build.md lists the release files and how each is built.

## Where the rest is

Each folder has its own `CLAUDE.md` with its traps and rules, loaded when you
work there:

| Folder | Holds |
|---|---|
| `Shiori/` | the apps: `local.yml` build settings, Xcode and device traps, SwiftUI and macOS rules |
| `Packages/HisterKit/` | the Hister API quirks, notes, files, code, small web, AI, the private-vault and settings-sync rules |
| `patches/` | the Safari extension (and `patches/shiori/` is the search page: see `web/`) |
| `web/` | the search page and the web app |
| `linux/`, `haiku/`, `classic/` | each platform's traps (classic includes mac-bridge) |
