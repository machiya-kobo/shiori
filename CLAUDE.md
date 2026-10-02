# Shiori: contributor guide

Shiori is a search client for a [Hister](https://github.com/asciimoo/hister)
server: native apps for iPhone, iPad and Mac with a Safari extension (the
upstream Hister extension, patched at build time), a search page and a web
app, and a small Linux app. README covers what it is and how to build it;
docs/ai.md, docs/linux.md and docs/smallweb.md cover those parts. This file
holds the rules and the traps the code can't tell you.

## Rules

- **Never modify `vendor/hister/`.** Safari behaviour lives in `patches/`,
  applied to the built `dist/` by `scripts/build-extension.sh`. Upgrade by
  moving the submodule to an upstream tag; the Hister server runs the
  matching version.
- **Never edit `Shiori.xcodeproj/`, `ShioriExtension/Resources/` or
  `build/`**: all generated. Change `project.yml` or `patches/`.
- **No personal details in the repo**: server addresses, network names,
  device names, team IDs. They go in the gitignored `local.yml`/`local.env`.
- **No new network endpoints** without discussion. Shiori talks to the
  configured Hister server (and on its host the optional companion
  services, not in this repository: the feed service `/shiori/feed` and the
  AI endpoint `/shiori/ai/*`, hosted pages only), Kura (notes), the
  small-web gateway, SearXNG, the visited site's favicon and PDFs (upstream
  behaviour). Firefox itself fetches the add-on's `updates.json` from this
  repository's GitHub Releases (its `update_url`); the extension's code
  never does. NewsBlur, status pages and the Wayback Machine and archive.is
  copies are only ever opened as links.
  `gemini://`/`gopher://` links are handed to the system, never fetched. No
  analytics. AI providers only when the user switches AI on, and only from
  the app.
- **Never re-add the `cookies` permission.** The server has no login; the
  network is the gate.
- **Tests:** `node --test scripts/*.test.mjs` (Node 22 fails on the
  folder form) after touching `patches/`, `scripts/`, `web/` or `linux/`;
  `swift test` in `Packages/HisterKit` and `Packages/ShioriAI`;
  `xcodebuild test -scheme ShioriTests -destination platform=macOS` after
  touching `Shared/`. `HISTER_LIVE_URL` and
  `KURA_LIVE_URL` add read-only checks against real servers.
- **Never test a write against a live Hister.** Use the stubs in the test
  suites or `linux/fake-hister.py`. Reads against your own server are fine.
- **Logic shared by Swift and JavaScript has twins** (HisterKit and
  `patches/shiori/search-core.js`; `SharedSettings`' apply, recordSearch and
  extensionPayload and `patches/ext/host-local.js`) with the same test
  cases. Change both.
- **No rule editor in the app**: the server's rules are the truth. Shiori
  edits aliases only through Keep Collections Current (docs/ai.md).
- **Settings are per device, never synced.** Anything on the network could
  write a shared document.
- **A note from a private vault** (address `/v/<vault>/n/…`, a vault Kura's
  `/api/vaults` doesn't mark `private: false`; `Notes.isPrivateNote` /
  `S.isPrivateNote`) never goes to Hister, to any AI engine (on-device
  included), a cache, an export or a feed. Kura's config is the one switch
  (a shared vault is treated like the default); clients fail closed: until
  Kura answers, or when it can't be read, every vault but the default is
  private. `useVaults` sets the list, which only what's shown may use
  (apps and web app: re-read after ten minutes away). **Before anything
  about another vault's note goes to Hister or a model, Kura is asked
  afresh** (`Notes.isPrivateNoteNow` / `S.isPrivateNoteNow`, 4 s); a
  default-vault note asks nothing. A path that can't wait (the share
  sheet, the sidebar, the address bar, the right-click menu, Summarize on
  the web) refuses every other vault's note. `noteVault` /
  `Notes.otherVault(of:)` only say which vault (on any host: over-inclusive,
  so safe). The address is read as Kura serves it: a leading `//` folded,
  `%XX` decoded once (`//v/…` and `/%76/…` are the same page), dot
  segments resolved; a name that still isn't `[a-z0-9-]+` (`%2577ork`
  reads `%77ork`) and an address that can't be parsed are private.
  `/v/` always starts the path: Kura refuses a public address with a
  path, and the hosted page's `/kura/` passes only Kura's API, never its
  reader.
- Never put `.searchSuggestions(.hidden, for: .content)` on a sheet's
  `.searchable`: on iOS 27 the sheet went blank.

## Build configuration (`local.yml`)

- `SHIORI_BUNDLE_PREFIX` is required and set only in `local.yml` (project.yml
  must not set it: an including file's value wins in XcodeGen). Every bundle
  ID, the App Group (`group.<prefix>.shiori` on iOS,
  `<TeamID>.<prefix>.shiori` on macOS), the entitlements and the URL type
  derive from it. At runtime `ShioriID.app` (and `logSubsystem` in the
  packages) derives the app's ID from the running bundle, dropping an
  extension's last component: the extension's ID, the keychain service
  (`<app>.ai`), the log subsystem. `build-extension.sh` stamps it into the
  shim's `sendNativeMessage` (Safari ignores it). The build stops while it's
  empty.
- `SHIORI_SERVER_URL` is the server's one home (Info.plist and the extension
  build both read it). Others: `SHIORI_SEARXNG_URL`, `SHIORI_NIWA_URL`
  (Kura), `SHIORI_KONBINI_URL`, `SHIORI_SMALLWEB_URL`, `SHIORI_ROOMS`,
  `SHIORI_STATUS_URL`, `SHIORI_SEARCH_PAGE_URL`, `SHIORI_SOURCE_URL`.
- The user's conventions are build defaults, empty in a public build:
  `SHIORI_OBSIDIAN_VAULT`, `SHIORI_AI_NEVER_SUGGEST`, `SHIORI_AI_NOT_TOPICS`,
  `SHIORI_RESERVED_COLLECTIONS` (comma lists). `SHIORI_ROOM_LOGOS` (a folder
  outside the repository holding `hister.png` and `searxng.svg`) swaps the
  neutral Hister/SearXNG glyphs for their logos; the repository carries no
  other project's logo.
- The web builds take the same names from their environment.

## The Safari extension

- **The shims attach by replacing globals upstream looks up at call time:**
  `globalThis.fetch` in `background.js`, `chrome.runtime.sendMessage` in
  `content.js`. If an upstream bump caches either (`const f = fetch`), the
  shim silently stops working. After a bump, grep the built bundle.
- `build-extension.sh` rewrites upstream's default server URL
  (`http://127.0.0.1:4433/`) and fails if the string is gone. It refuses
  more than four suggested shortcuts: a fifth makes Safari drop the
  background silently.
- Every save gets `metadata.source = "shiori"`, `client = "shiori"` and
  `client_version` (two fields: Hister's parser can't match "/" in a value).
- **The offline queue** (`installCaptureQueue`): keyed per URL, keeping the
  first `added` (integer unix seconds: a string is a 400). A queued automatic
  capture answers a synthetic 201 (`X-Shiori-Queued: 1`); a manual one
  rethrows. It **fails closed**: nothing is stored until the skip rules have
  been fetched once. No auth headers are stored. 406/413/422 and other 4xx
  are never retried; 5xx/429 get 5 tries; entries older than 14 days drop.
  It drains on any Hister reply under 500 and on worker start (no timer: iOS
  suspends the worker). It follows a server change from anywhere
  (`storage.onChanged`; `set-server` marks its own write): queued pages
  move to the new address, and its rules are fetched at once.
- A capture with HTML carries no `text` (Hister derives it). Never strip
  `<script>`: Hister's sensitive-content check reads the raw HTML.
- **The native handler class must be `nonisolated`**: Safari calls it off
  the main thread, and a MainActor handler crashes on every message. Same
  for `NSItemProvider` callbacks and `openURL`'s completion on macOS.
- One build, a target per browser: `scripts/build-extension.sh` (Safari,
  into `ShioriExtension/Resources/`) or `--target firefox` (into
  `build/firefox/`, then `web-ext` lint and pack). Manifests are upstream's,
  then `patches/manifest.shiori.json` (every browser), then
  `patches/manifest.<target>.json`; `scripts/check-extension.py` holds each
  target's rules.
- Shiori's background logic is `patches/ext/core.js`, for Safari and
  Firefox alike. It reaches settings only through `shioriHost`:
  `ext/host-native.js` (the app) on Safari, `ext/host-local.js`
  (`storage.local`) on Firefox (docs/firefox-plan.md).
- Firefox's settings page is `patches/ext/settings.*` (Safari's,
  `patches/shiori/options.*`, only shows what the app set). Only it may set
  the server (`set-server`: from its own address, where
  `shioriHost.ownsServer`); everything else goes through `set-settings`, the
  gear's whitelist.
- **Firefox releases** (`.github/workflows/firefox-release.yml`, on a `v*`
  tag matching `MARKETING_VERSION`): Mozilla signs them unlisted; the
  add-on ID `shiori@machiya-kobo.github.io` and the AMO account are fixed
  for good. Every latest release must carry `updates.json`, or Firefox's
  updates break (docs/firefox.md).
- **The background order matters** (`BACKGROUND` in `build-extension.sh`,
  held by tests). Firefox: `host-local`, `containers`, `core`,
  `search-core`, `pages`, `omnibox`, `badge`, `menus`. Safari:
  `safari-shims`, `host-native`, `core`, `search-core`, `badge`, `menus`.
  The core hides `shiori:` messages from every `onMessage` listener added
  after it, so a file with its own `shiori:` messages must come before it;
  `menus` needs `search-core` and `badge` before it.
- **A tab's badge goes back to the toolbar's through `ShioriBadge.clearTab`**
  (`patches/ext/badge.js`): `null` where the browser takes it, else a copy
  kept in step with the count. Safari's answer to `null` hasn't been seen
  on a device.
- `contextualIdentities` (container rules) is a **required** permission:
  Firefox drops it from `optional_permissions`. Installing switches
  containers on where they were off; say so in docs/firefox.md.
- The right-click menu (Firefox, and Safari on the Mac with `contextMenus`)
  runs upstream's own commands for its page items (the menu keeps
  upstream's `onCommand` listener). Never add a rule editor there.
- Firefox's address-bar keyword (`sh`, `patches/ext/omnibox.js`) searches
  through `search-core.js` (`histerText`), drops notes and non-web pages,
  and records an opened suggestion in `api/history` only while Remember What
  You Open is on.
- Settings reach the extension through the App Group: the background asks by
  `sendNativeMessage` on every search (400 ms budget, then its cache in
  `storage.local`). A setting the extension page shows must be in both
  `SharedSettings.extensionPayload` and the core's `DEFAULTS`.
- The results page's gear writes through `SharedSettings.applyFromPage`, a
  whitelist of keys, types and values. AI settings are never in it: a page
  must never turn AI on.
- Search from Safari (Safari only: Firefox adds search engines, so it never
  takes another engine's searches; `check-extension.py` holds that): keep
  DuckDuckGo; `redirect.js` hands address-bar searches to the hosted search
  page when it answers (else the extension's `search.html`). `search-core.js` decides: no `!bang`, image/news search,
  Back/Reload, or `shiori=off`. Never open results with `tabs.update`: Back
  then strands you on DuckDuckGo.

## Xcode and devices

- The appex copy step must not use `rsync --delete`: on iOS the resources
  folder is the appex root.
- Incremental builds can leave the appex with a stale signature: the install
  scripts delete the built products and run `codesign --verify`.
- Don't turn the extension's resources into a Copy Bundle Resources phase:
  Xcode flattens folders and breaks the manifest's paths.
- **A device reinstall resets the extension's All Websites permission to
  Ask, with no prompt.** Remind the user after every install.
- Any Mac build registers its extensions, a throwaway clone's too: Safari and
  the share menu then list duplicates. `install-mac.sh` unregisters build
  copies; for others `pluginkit -r <appex>`.
- App Groups differ by platform (above); never hard-code the name.
- Every bundle has a `PrivacyInfo.xcprivacy`; a new required-reason API
  needs its line.
- Mac export needs `com.apple.security.files.user-selected.read-write`, or
  the sandbox shows no save dialog at all.

## Hister API quirks

- Every request needs `Origin: hister://`. `limit`, `sort` and `highlight`
  only work inside the JSON `query=` parameter. `*` with sort `date` is
  "recent".
- Snippets are HTML with `<mark>`. A malformed regexp returns zero results.
  Replies can hold raw control characters (decoding retries with them
  blanked).
- Delete is by query: dry-run first, refuse unless exactly one page matches.
- `api/add` replaces a page's metadata (last writer wins) but keeps its label
  when the add has none. Provenance in metadata is best effort.
- **Every Hister query ends in ` -label:vault -metadata.source:vault`**
  (`SearchText.forHister` / `S.histerText`, applied inside the clients):
  notes come from Kura. There's no `NOT` and no exclude parameter; a negated
  field works with exact totals.
- The last typed word is searched as a prefix (`prefixLastWord`): Hister and
  Kura match whole words.
- `url:` needs the exact stored URL; marks use one search, `url:(a|a/|b…)`.
  URLs with `( ) |` can't go in the alternation.
- Hister matches remembered opens by the exact query text, so search fields
  have autocapitalisation and autocorrect off, and opens are recorded under
  the text as sent.
- Query strings go through `URLComponents.setQueryItems` (it escapes "+").
- Hister has no fuzzy search (`word~2` finds "2"); respellings come from
  SearXNG's autocomplete (`Respelling.didYouMean` / `S.didYouMean`).

## The apps

- **iOS floor 18.6**: `import WebKit` from Swift needs `libswiftWebKit`.
  Use an iOS 27 simulator.
- The iOS 27 SDK's SwiftUI has `Document` and `Preview`: HisterKit's models
  are `StoredPage` and `PagePreview`.
- **Text size: `.textStyle(.headline)`, never `.font(.headline)`**: macOS has
  no Dynamic Type; `macTextScale` scales the Mac, and `@ScaledMetric` sizes
  need it too.
- **Liquid Glass stays on the system chrome**: the theme colours only the
  content layer. Every text colour is at least 4.5:1 on its background and
  surface (`SnippetAndSuggestionTests`, `theme-contrast.test.mjs`).
- **Bars under the navigation bar go through `topBar`**: a safe-area bar on
  iOS 26 and macOS 26, so the system's frosted edge runs under it (an inset
  made a floating slab, or let content show through). Older systems keep the
  theme's background. `topBarBackground()` must be a view, not a colour fill.
- **A `listRowBackground` view must not read the environment** (crash on the
  Mac): pass the palette in.
- Rows added to a Mac `List` already on screen draw squashed for a moment:
  hide a new list's first pass and don't let rows trickle in.
- **The Mac's search field is an `NSSearchField` in the toolbar**
  (`MacSearchField`), one per window (`MacSearchFieldStore`): SwiftUI rebuilds
  toolbar items, which lost the keyboard mid-typing. Its delegate never gets
  `doCommandBy`, so a key monitor catches Return/Tab/→. Don't put anything
  under it in a popover. `.searchable` can't be placed there on macOS 26.
- On a collection or label (Mac, iPad) the window's field searches within it
  (`SearchSession.within`); the iPhone's pushed list has its own field.
- Mac column widths: macOS restores its own divider over the ideal width and
  without the column's minimum, hence the extra `minWidth` frames.
- The page preview is Hister's readable HTML in a WKWebView with JavaScript
  off, a CSP of images and inline styles, no referrer and a non-persistent
  store. Links open in the browser.
- Transport errors say what to do (`HisterError(transport:)`): TLS failures
  are `.untrusted`, everything else `.unreachable`.
- HisterKit's types are `Sendable` and nonisolated; keep
  `NonisolatedNonsendingByDefault` off (it crashed the network tests).
- Replies that don't decode are logged by field names, never content.
- **Keys** (`AIKeychain`): on the Mac the login keychain (the data-protection
  one needs an entitlement a free team's build lacks; writes fail, reads say
  "not found"). Every query names service and account.
- Every delete is Undo, not a confirmation: the delete goes to Hister only
  after the toast.

## The search page and the web app

- The same `patches/shiori/search.*` runs as the extension's page and as a
  hosted page (`scripts/build-web.sh`); `web/shim.js` stands in for the
  extension APIs. The web app is `web/app/` (`scripts/build-pwa.sh`), plain
  ES modules sharing `search-core.js` and the theme tokens.
- **One host serves everything** (web/README.md): the page, `/searx/`,
  `/kura/` (only the API paths Shiori uses: `scripts/dev-server.test.mjs`),
  `/konbini/`, `/smallweb/`, and Hister (with the optional
  companion `/shiori/feed` and `/shiori/ai/*`, not in this repository; their
  contracts are in README and docs/ai.md). **Never add `Origin:
  hister://` there**: Hister accepts same-origin browser writes and refuses
  cross-site ones, and that check protects it.
- Asset addresses carry the build (`?v=<commit>`); unstamped placeholders
  read as empty (`S.fromBuild`).
- **`replaceChildren`/`append` write a `null` child out as the text "null"**:
  filter first.
- The web app's list fills its column with the frosted bars laid over its top
  (`--frost`, `--frost-filter`); `#list` stays the scroller (the load-more
  observer's root) with `--bars` as its top padding. Sticky section headings
  inside it use `top: 0` (offsets count from inside the padding). Its
  scrollbar track starts at `--bars`.
- Clicks inside the preview (a sandboxed iframe) never reach the page: open
  menus close on the window's `blur` and on Escape.
- Every search-page tab keeps All's width (`two-col`).
- Collapsible sections are a button and a grid-rows body, not `<details>`
  (which re-decoded images and flashed).
- The search page caches each results page for Back (`shioriPageCache`), but
  never one holding a private vault's note.
- Thumbnails load only from the SearXNG host's `/image_proxy`: anything else
  is dropped, so a broken plugin fails closed.
- `sw.js` caches only the app's own files and only `ok` responses, and waits
  for "New Version · Reload" (`SKIP_WAITING`).
- The house's shared settings (theme, text size, hidden rooms) are
  `machiya_*` cookies on the network's domain (`S.houseSettings`).
- AGPL section 13: `SHIORI_SOURCE_URL` puts a Source link in About; only a
  plain http(s) address counts.

## Notes (Kura)

- **Notes come only from Kura** (`/api/search`, `/api/recent`, `/api/note`,
  `/api/vaults`, `feed.xml`); Hister still holds the default vault's notes for
  its own UI, but Shiori never lists them from Hister.
- Other vaults: searchable only in Notes, through the vault filter (Kura's
  `vault`); previewed from Kura's `/api/note` HTML, never cached. A private
  one's are never recorded as opened or deleted in Hister and get no AI
  (`AIContent.workNote` makes `EngineChain.eligible` empty); a shared one's
  are treated as the default vault's.
- A note's chip names its vault (`Notes.vaultChip` / `S.vaultChip`); a tap
  shows Notes from that vault.
- A note opens in Obsidian (the vault name must match exactly), with its Kura
  page and Konbini card linked. Don't build folder, tag or backlink browsing
  into Shiori: link to Kura.
- Only `@`-aliases are collections (`Rules.isCollectionKeyword` /
  `S.isCollectionKeyword`); an alias about the vault (`@notes`, `@pages`) is
  not one. The sidebars list every alias as a saved search.

## Save This Note's Links

- Shiori saves pages into Hister; the other rooms only look up what it
  holds. A note's (or a folder's) outside links come from Kura's
  `external_links`; deduplicated, 200 a run (`SaveLinks` / `S.saveLinkRows`).
- **Never a URL Hister holds**: looked up right before each save and again
  after redirects (`api/add` would replace its metadata).
- http(s): downloaded here, skip rules hold in bulk (no `ignore_skip_rules`),
  Save Anyway per link for a 406. `http://` is tried as `https://` first
  (transport security). Links to files are never saved.
- `gemini://`/`gopher://`: through the small-web gateway's `POST /api/save`
  (202 with the canonical URL; 429 waited out); the batch label goes on once
  the page arrives (the gateway sets none).

## Small Web

- Searched on submit only (the engines are volunteers'); one engine failing
  is a line above the results. Where a result opens is a setting (the
  gateway's page, or the `gemini://` link for an app such as Lagrange). A
  direct open asks the gateway to save it. `marks` are code-point offsets.

## AI (docs/ai.md)

- Off by default; per device; keys in the Keychain. Engine order is fixed:
  Apple Intelligence, a local server, one cloud engine. Another engine tries
  only after "couldn't answer".
- **A note never goes to a cloud engine**, a private vault's note to none.
- Anthropic: never send `temperature` or a prefilled turn; JSON through
  `output_config.format`; a refusal is a 200 with `stop_reason: "refusal"`.
  OpenAI wants `max_completion_tokens`, local servers `max_tokens`.
- Apple Intelligence needs iOS/macOS 26 and an availability check before
  every request; its guardrails decline some ordinary pages (retry from the
  title and address); its context is small (read long pages in parts).

## Shiori for Linux (docs/linux.md)

- GJS on GTK 4 and libadwaita, a Flatpak (`io.github.machiya_kobo.Shiori`) on the
  GNOME 49 runtime. `linux/src/` is pure modules tested under Node; keep
  `linux/gjs/` thin.
- **Use `app.runAsync()`, never `app.run()`**: the main module awaits, and
  inside a blocking `run()` callbacks' promise jobs never run.
- Commands with no window (`save`, `send`, `status`, `save-links`,
  `provider-search`, `--help`) run before the application starts: GTK needs
  a display.
- `GApplicationCommandLine`'s `print`/`printerr` aren't callable from GJS: use
  `print_literal`/`printerr_literal`.
- **Read `message.status_code`, never `get_status()`**: the enum lacks 429
  and throws.
- The Flatpak mounts the host's `~/.config/shiori` over its own config dir,
  so a test config under `~/.var/app/…` is hidden: test saves only with
  `linux/save-test.sh`.
- Over SSH, run with the desktop's session bus, or portals time out; never
  `pkill -f` a pattern that's in the SSH command.
