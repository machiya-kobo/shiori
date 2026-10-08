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
- **The settings that follow the person**: signed in, the shared ones (theme,
  appearance, text size, pills) and Shiori's own options (`shiori.*`) go to
  the account at the Hister sign-in helper (`/machiya/api/prefs`). Never an
  address, a sign-in, a token, an AI setting or this device's own (the preview
  pane, Use This Device's Size). Twins: `S.prefsSync` / `PrefsSync` on
  `scripts/prefs-sync-cases.json`; `scripts/prefs.schema.json` is a copy of
  [Machiya's contract](https://github.com/machiya-kobo/machiya/blob/main/docs/contracts/prefs.md)'s schema.
- **A note from a private vault** (address `/v/<vault>/n/…` and any page under
  `/v/<vault>/`; a vault Kura's `/api/vaults` doesn't mark `private: false`;
  `Notes.isPrivateNote` / `S.isPrivateNote`) never goes to Hister, any AI
  engine (on-device included), a cache, an export or a feed. Kura's config is
  the one switch (a shared vault is treated like the default); clients fail
  closed: until Kura answers, every vault but the default is private.
  **Before anything about another vault's note goes to Hister or a model,
  ask Kura afresh** (`isPrivateNoteNow`, 4 s); a path that can't wait (the
  share sheet, the sidebar, the address bar, the right-click menu, Summarize on
  the web) refuses every other vault's note. Read the address as Kura serves
  it: a leading `//` folded, `%XX` decoded once, dot segments resolved; a
  name that still isn't `[a-z0-9-]+`, or an address that can't be parsed, is
  private. The hosted page's `/kura/` passes only Kura's API, never its reader.
- Never put `.searchSuggestions(.hidden, for: .content)` on a sheet's
  `.searchable`: on iOS 27 the sheet went blank.

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

## Build configuration (`local.yml`)

- `SHIORI_BUNDLE_PREFIX` is required and set only in `local.yml` (project.yml
  must not set it: an including file's value wins in XcodeGen). Every bundle
  ID, the App Group (`group.<prefix>.shiori` on iOS, `<TeamID>.<prefix>.shiori`
  on macOS), the entitlements and the URL type derive from it; at runtime
  `ShioriID.app` derives the app's ID from the running bundle. Never
  hard-code a name. The build stops while it's empty.
- `SHIORI_SERVER_URL` is the server's one home (Info.plist and the extension
  build both read it). Others: `SHIORI_SEARXNG_URL`, `SHIORI_KURA_URL` (its old
  name `SHIORI_NIWA_URL` still counts), `SHIORI_KONBINI_URL`,
  `SHIORI_SMALLWEB_URL`, `SHIORI_ROOMS`, `SHIORI_STATUS_URL`,
  `SHIORI_SEARCH_PAGE_URL`, `SHIORI_SOURCE_URL` (AGPL section 13: a plain
  http(s) address puts a Source link in About), `SHIORI_FRONTENDS`
  (`redlib=https://…,invidious=https://…`; `Elsewhere` / `S.elsewhereLinks`,
  twins). The web builds take the same names from their environment, plus
  `SHIORI_AI=1` (the host has the AI companion; else no `/shiori/ai/` request).
- Personal conventions are build defaults, empty in a public build:
  `SHIORI_OBSIDIAN_VAULT`, `SHIORI_AI_NEVER_SUGGEST`, `SHIORI_AI_NOT_TOPICS`,
  `SHIORI_RESERVED_COLLECTIONS`. `SHIORI_ROOM_LOGOS` (a folder outside the
  repository) swaps the neutral glyphs for other projects' logos; the
  repository carries none.

## The Safari extension

- **The shims attach by replacing globals upstream looks up at call time**:
  `globalThis.fetch` in `background.js`, `chrome.runtime.sendMessage` in
  `content.js`. If an upstream bump caches either (`const f = fetch`), the
  shim silently stops working. After a bump, grep the built bundle.
- `build-extension.sh` rewrites upstream's default server URL
  (`http://127.0.0.1:4433/`) and fails if it's gone. It refuses more than four
  suggested shortcuts: a fifth makes Safari drop the background silently.
- **Safari is the one extension.** On Firefox and Chrome upstream Hister's
  own extension captures; don't add a second browser target.
  `scripts/build-extension.sh` builds into `ShioriExtension/Resources/`
  (manifests: upstream's, then `patches/manifest.shiori.json`, then
  `patches/manifest.safari.json`); `scripts/check-extension.py` holds the rules.
- Shiori's background logic is `patches/ext/core.js`; it reaches the app only
  through `shioriHost` (native messaging). The extension never sets the
  server, token or sign-in: the app does, and the extension's page only shows
  them. The page's gear writes through `SharedSettings.applyFromPage`, a
  whitelist of keys, types and values; AI settings are never in it. A setting
  the extension page shows must be in both `SharedSettings.extensionPayload`
  and the core's `DEFAULTS`.
- **The background order matters** (`BACKGROUND` in `build-extension.sh`, held
  by tests): `safari-shims`, `host-native`, `core`, `search-core`, `badge`,
  `menus`. The core hides `shiori:` messages from every `onMessage` listener
  added after it; `menus` needs `search-core` and `badge` before it.
- Every save gets `metadata.source = "shiori"`, `client = "shiori"` and
  `client_version` (two fields: Hister's parser can't match "/" in a value). A
  capture with HTML carries no `text` (Hister derives it); never strip
  `<script>` (Hister's sensitive-content check reads the raw HTML).
- **The offline queue** (`installCaptureQueue`): keyed per URL, keeping the
  first `added` (integer unix seconds: a string is a 400). A queued automatic
  capture answers a synthetic 201 (`X-Shiori-Queued: 1`); a manual one
  rethrows. It **fails closed**: nothing is stored until the skip rules have
  been fetched once. No auth headers are stored. 406/413/422 and other 4xx
  are never retried, but a 401/403 keeps the capture with no try counted;
  5xx/429 get 5 tries; entries older than 14 days drop. It drains on any
  Hister reply under 500 and on worker start (no timer: iOS suspends the
  worker), and follows a server change from anywhere (`storage.onChanged`).
- **The native handler class must be `nonisolated`**: Safari calls it off the
  main thread, and a MainActor handler crashes on every message. Same for
  `NSItemProvider` callbacks and `openURL`'s completion on macOS.
- A tab's badge goes back to the toolbar's through `ShioriBadge.clearTab`
  (`patches/ext/badge.js`). The right-click menu runs upstream's own commands.
- Search from Safari keeps DuckDuckGo: `redirect.js` hands address-bar
  searches to the hosted search page when it answers (else the extension's
  `search.html`); `search-core.js` decides (no `!bang`, image/news search,
  Back/Reload, or `shiori=off`). Never open results with `tabs.update`: Back
  then strands you on DuckDuckGo.

## Xcode and devices

- The appex copy step must not use `rsync --delete`: on iOS the resources
  folder is the appex root. Don't turn the extension's resources into a Copy
  Bundle Resources phase: Xcode flattens folders and breaks the manifest.
- Incremental builds can leave the appex with a stale signature: the install
  scripts delete the built products and run `codesign --verify`.
- **A device reinstall resets the extension's All Websites permission to Ask,
  with no prompt.** Tell whoever installs.
- Any Mac build registers its extensions, a throwaway clone's too: Safari and
  the share menu then list duplicates. `install-mac.sh` unregisters build
  copies; for others `pluginkit -r <appex>`.
- Every bundle has a `PrivacyInfo.xcprivacy`; a new required-reason API needs
  its line. Mac export needs `com.apple.security.files.user-selected.read-write`
  or the sandbox shows no save dialog.
- **iOS floor 18.6** (`import WebKit` from Swift needs `libswiftWebKit`). The
  iOS 27 SDK's SwiftUI has `Document` and `Preview`: HisterKit's models are
  `StoredPage` and `PagePreview`.

## Hister API quirks

- Every request needs `Origin: hister://`. `limit`, `sort` and `highlight`
  only work inside the JSON `query=` parameter. `*` with sort `date` is
  "recent". Snippets are HTML with `<mark>`. A malformed regexp returns zero
  results. Replies can hold raw control characters (decoding retries with
  them blanked). Query strings go through `URLComponents.setQueryItems` (it
  escapes "+").
- **Every Hister query ends in ` -label:vault -metadata.source:vault
  -type:local -metadata.source:code`** (`SearchText.forHister` /
  `S.histerText`, applied inside the clients): notes come from Kura, files
  only on the Files pill (a query with `type:local` keeps them), code only on
  the Code pill. There's no `NOT` and no exclude parameter; a negated field
  works with exact totals.
- The last typed word is searched as a prefix (`prefixLastWord`): Hister and
  Kura match whole words. Hister has no fuzzy search (`word~2` finds "2");
  respellings come from SearXNG's autocomplete (`Respelling.didYouMean` /
  `S.didYouMean`).
- Delete is by query: dry-run first, refuse unless exactly one page matches.
  `api/add` replaces a page's metadata (last writer wins) but keeps its label
  when the add has none.
- `url:` needs the exact stored URL; marks use one search, `url:(a|a/|b…)`;
  URLs with `( ) |` can't go in the alternation.
- Hister matches remembered opens by the exact query text, so search fields
  have autocapitalization and autocorrect off, and opens are recorded under
  the text as sent.
- Signing in (the apps, `HisterAccount`): the app holds a Hister session
  (`Cookie: hister=…`; HisterKit keeps cookies off and sets it) and the
  helper's `mhs_` id for the rooms; offered only while the helper says
  Hister has users. A 401/403 is `signedOut`, never retried; the outbox keeps
  its pages until sign-in. Test a sign-in only against a throwaway Hister
  with users (`HISTER_USERS_URL`).

## The apps

- **The app targets run on the main actor unless code says otherwise**
  (`SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`): a `nonisolated async`
  function there runs on its caller's actor, usually main. Work that must
  leave the main thread says so: `@concurrent`, a background queue (as
  `OfflineStore`), or the packages. HisterKit's types are `Sendable` and
  nonisolated; keep `NonisolatedNonsendingByDefault` off (it crashed the
  network tests).
- **Bars under the navigation bar go through `topBar`** (a safe-area bar on
  iOS 26 and macOS 26, so the system's frosted edge runs under it);
  `topBarBackground()` must be a view, not a color fill.
- **SwiftUI never runs `.task` on a view whose body is empty**: a check that
  decides whether a view shows must live outside it, or the view never shows.
- **A `listRowBackground` view must not read the environment** (crash on the
  Mac): pass the palette in. Rows added to a Mac `List` already on screen draw
  squashed for a moment: hide a new list's first pass.
- **The Mac's search field is an `NSSearchField` in the toolbar**
  (`MacSearchField`), one per window (`MacSearchFieldStore`): SwiftUI rebuilds
  toolbar items, which lost the keyboard mid-typing. Its delegate never gets
  `doCommandBy`, so a key monitor catches Return/Tab/→. Don't put anything
  under it in a popover.
- Mac column widths: macOS restores its own divider over the ideal width and
  without the column's minimum, hence the extra `minWidth` frames. On a
  collection or label the window's field searches within it
  (`SearchSession.within`).
- The page preview is Hister's readable HTML in a WKWebView with JavaScript
  off, a CSP of images and inline styles, no referrer and a non-persistent
  store; links open in the browser.
- Transport errors say what to do (`HisterError(transport:)`): TLS failures
  are `.untrusted`, a plain http:// address `.plainHTTP`, else `.unreachable`.
  Replies that don't decode are logged by field names, never content.
- **Keys** (`AIKeychain`): on the Mac the login keychain (the data-protection
  one needs an entitlement a free team's build lacks; writes fail, reads say
  "not found"). Every query names service and account.
- **Pull to refresh is Shiori's own (`.pullToRefresh`), not `.refreshable`**
  (with the `topBar` bars the system's spinner was out of sight and its
  haptic late). Web and Small Web have none.
- **Offline reading** (`OfflineStore`, apps only): the Library's first pages
  and the last 50 previews, in Caches per server and Kura, shown only when
  Hister or Kura is unreachable ("Offline · as of <time>"). Never a private
  vault's note, a file or code; signing out empties it.
- **Lists watch for new items, never redraw under you**: every 60 s while
  visible, an open list asks Hister and Kura (never the web) what arrived
  (`ResultsModel.checkForNew`, the web's `watchForNew`); an "N New Items"
  banner with a refresh icon (never an up arrow) reloads on a tap.

## The search page and the web app

- `patches/shiori/search.*` runs as the extension's page and as a hosted page
  (`scripts/build-web.sh`); `web/shim.js` stands in for the extension APIs.
  The web app is `web/app/` (`scripts/build-pwa.sh`), plain ES modules sharing
  `search-core.js` and the theme tokens.
- **One host serves everything** (web/README.md): the page, `/searx/`,
  `/kura/` (only the API paths Shiori uses), `/konbini/`, `/smallweb/`, and
  Hister. **Never add `Origin: hister://` there**: Hister accepts same-origin
  browser writes and refuses cross-site ones, and that check protects it.
- Asset addresses carry the build (`?v=<commit>`; the service worker's cache
  name is a hash of the built files); unstamped placeholders read as empty
  (`S.fromBuild`). `sw.js` caches only the app's own files and only `ok`
  responses, and waits for "New Version · Reload" (`SKIP_WAITING`).
- **`replaceChildren`/`append` write a `null` child out as the text "null"**:
  filter first.
- The web app's list fills its column with frosted bars laid over its top
  (`--frost`, `--bars`); `#list` stays the scroller (the load-more observer's
  root); sticky headings inside it use `top: 0`. Clicks inside the sandboxed
  preview never reach the page: menus close on the window's `blur` and Escape.
- Collapsible sections are a button and a grid-rows body, not `<details>`
  (which re-decoded images and flashed). Every tab keeps All's width.
- The search page caches each results page for Back (`shioriPageCache`), never
  one holding a private vault's note. Thumbnails load only from the SearXNG
  host's `/image_proxy`: anything else is dropped.
- **Menus close on the way out**: a link or form inside a menu or sheet shuts
  it first, and `pageshow`, `popstate` and `pagehide` shut what's open.
- **Every href goes through `S.linkHref`** and a stored address opened from
  script through `S.safeHref` (`SafeHref` in the apps): never `javascript:`,
  `data:` or `file:`.
- The shared settings (theme, text size, hidden rooms) are `machiya_*` cookies
  on the network's domain (`S.houseSettings`).

## Notes, files, code, small web, AI

- **Notes come from Kura or from Hister**: Settings → Notes From,
  `notesSource` (`""` until chosen, `kura`, `hister`), per device, never sent
  to the account. Until chosen, Kura when one is set up, else Hister;
  `S.notesSource` / `NotesSource` and the Haiku and classic cores are twins on
  `scripts/notes-source-cases.json`.
  - From Kura (`/api/search`, `/api/recent`, `/api/note`, `/api/vaults`,
    `feed.xml`): every vault the filter picks, previews from `/api/note`
    (never cached for another vault).
  - From Hister: its `label:vault` documents, **the default vault's alone**
    (`S.histerNoteShown` / `Notes.histerNoteShown`: by address as Kura reads
    it, `/v/<vault>/` never), previews from Hister's `/api/preview`; no vault
    filter, no notes feed. Every other Hister query leaves notes out.
  - A note's chip names its vault (`Notes.vaultChip`); it opens in Obsidian
    (the vault name must match exactly) with its Kura page and Konbini card
    linked. Don't build folder, tag or backlink browsing into Shiori: link to Kura.
- **Save This Note's Links**: a note's outside links come from Kura's
  `external_links`, deduplicated, 200 a run (`SaveLinks` / `S.saveLinkRows`).
  Never a URL Hister holds (looked up before each save and again after
  redirects). http(s): downloaded here, skip rules hold in bulk, Save Anyway
  per link for a 406, `http://` tried as `https://` first, files never saved.
  `gemini://` and `gopher://` go through the small-web gateway's
  `POST /api/save` (202; 429 waited out).
- **Files** (the folders Hister watches, `type:local`): only the Files pill,
  only while Hister has some (`LocalFiles` / `S.filesQuery`, twins), opened
  from Hister's copy (`/api/file?id=<address>`); never recorded as opened,
  labeled or deleted; no AI (`AIContent.localFile`).
- **Code** (code-import's `metadata.source:code`): only the Code pill, while
  Hister has some (`CodeDocs` / `S.codeQuery`, twins). Filters are metadata
  terms, each one lowercase token (Hister can't match `/` in a value):
  `metadata.code_kind:`, `code_state:open`, `code_repo:<owner>__<repo>`,
  `code_private:true` (a string). Never labeled, deleted or folded by site; AI
  on the device only (`AIContent.code`). "code" is a reserved collection name.
- **Small Web** (Gemini and Gopher through the gateway) is searched on submit
  only. The web app's Add Page and share target save through
  `POST /smallweb/api/save` after `api.checkPageURL` refuses any note; the 202
  means queued: say "Saving…", never "Saved". `marks` are code-point offsets.
- **AI** (docs/ai.md): off by default, per device, keys in the Keychain.
  Engine order is fixed: Apple Intelligence, a local server, one cloud engine;
  another engine tries only after "couldn't answer". **A note never goes to a
  cloud engine**, a private vault's note to none (`AIContent.workNote`).
  Anthropic: never send `temperature` or a prefilled turn; JSON through
  `output_config.format`; a refusal is a 200 with `stop_reason: "refusal"`.
  OpenAI wants `max_completion_tokens`, local servers `max_tokens`. Apple
  Intelligence needs iOS/macOS 26 and an availability check before every
  request; its guardrails decline some ordinary pages (retry from the title
  and address); its context is small (read long pages in parts).

## Shiori for Linux (docs/linux.md)

- GJS on GTK 4 and libadwaita, a Flatpak (`io.github.machiya_kobo.Shiori`) on
  the GNOME 49 runtime. `linux/src/` is pure modules tested under Node; keep
  `linux/gjs/` thin.
- **Only real links leave the window** (`linux/src/window.js`): the web app,
  its frames (`about:`, `data:`, `blob:`) and the sign-in pages stay in the
  web view, whose cookies they need.
- **Use `app.runAsync()`, never `app.run()`** (a blocking `run()` never runs
  callbacks' promise jobs). Commands with no window (`save`, `send`, `status`,
  `save-links`, `provider-search`, `--help`) run before the application
  starts: GTK needs a display.
- `GApplicationCommandLine`'s `print`/`printerr` aren't callable from GJS: use
  `print_literal`/`printerr_literal`. **Read `message.status_code`, never
  `get_status()`**: the enum lacks 429 and throws.
- The Flatpak mounts the host's `~/.config/shiori` over its own config dir, so
  a test config under `~/.var/app/…` is hidden: test saves only with
  `linux/save-test.sh`. Over SSH, use the desktop's session bus or portals
  time out; never `pkill -f` a pattern that's in your own command.

## Shiori for Haiku (`haiku/`, docs/haiku.md)

- C++17 on the Be API, HTTP through the Network Kit's netservices2 (private,
  linked statically). `haiku/core/` is portable (no Be headers) and tested
  anywhere by `make -f Makefile.test test`; `haiku/app/` is the Be UI, built
  only on Haiku.
- **The core's queries are search-core's twins**: regenerate
  `haiku/tests/vectors.inc` with `node haiku/tests/gen-vectors.mjs
  patches/shiori/search-core.js > haiku/tests/vectors.inc` after changing
  search-core (a test fails on drift). The version is project.yml's.
- Settings: `~/config/settings/Shiori/config.json`, 0600, Linux's keys.
  Hister's token only to Hister; the rooms get the sign-in's `mhs_` or a room token.
- **The Deskbar item runs inside Deskbar**, loaded from the app's binary: no
  networking there, every action a message to the app, and never a synchronous
  `BDeskbar` call from Deskbar's own thread.
- **One stalled TLS handshake jams a netservices2 session**: `Http.cpp` keeps
  the session on the heap, never deletes it, and retires it when a request
  passes its 20 s deadline. TLS failures are `ErrorCode() == B_NOT_ALLOWED`.

## Shiori for Classic Macintosh (`classic/`, docs/classic.md)

- C on Retro68 for the 68000, System 6.0.8 to 7.x, MacTCP. `classic/core/` is
  portable C89 (`node --test scripts/classic.test.mjs` runs it, the bridge's
  tests and the vectors' drift check). **Its queries are search-core's twins**:
  regenerate `classic/tests/vectors.h` with `node haiku/tests/gen-vectors.mjs
  --c` after changing search-core.
- **Two ways to Hister** (MacTCP has no TLS; one credential a request):
  **directly**, to a Hister served over plain HTTP (Hister's token to Hister's
  origin only, the room token to Kura's only), or **through mac-bridge**
  (`classic/bridge/bridge.py`, stdlib, GET only, exact paths: the room token
  `mht_` to both bridge origins, checked by hister-login on both ports before
  any upstream; Hister's token never leaves the bridge, and its log never has
  a query, a header or a body). docs/classic.md says what plain HTTP exposes;
  keep that warning wherever direct mode is offered.
- Hister's `page_key` holds escaped control characters and a NUL: keep it raw
  (`ShioriPage.next`) and send it back as it came. A note's vault comes from
  its address; private vaults are never offered, and `SHIO/read` refuses any
  vault but the default.
- The 68000's stack is small (the app sets 32 KB): big buffers live in structs
  or statics, never in a request path's frames. **The desk accessory must stay
  under 32 KB** (`build.sh` fails past it): nothing on its path may use
  `sprintf`, `sscanf`, `strtol` or the library's `strstr`, and it calls
  `RETRO68_RELOCATE()` at every entry.
- Retro68's File Manager glue (`HOpen`, `FSWrite`…) leaves parameter-block
  fields as garbage: zero a block and call `PB…Sync`. Multiversal lacks some
  names (`Scrap.h`, `TEToScrap`…): use the low-memory accessors or local
  constants. Windows are `NewCWindow` where Color QuickDraw is
  (`ThemeNewWindow`).
- **Release files come from `classic/scripts/package.sh`** with
  `SHIORI_RELEASE=1` (neutral defaults): a normal build bakes in
  `classic/local.env`'s test addresses and token.
- Emulator testing (Snow for System 6, Basilisk II for System 7) is in
  `classic/docs/TESTING.md`, against the fake house only. Never hard-kill
  Basilisk, never point its driver off the Mac's screen (it hangs X), and never
  write Snow's disk while Snow runs.
