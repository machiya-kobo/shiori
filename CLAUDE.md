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
- **Never commit personal details, preferences or settings.** This
  repository ships neutral defaults only. Server addresses, hostnames,
  tailnet and network names, people's names, logins and emails, device names
  and team IDs, vault and folder names, tokens, and anyone's own choices or
  settings (themes and text size, rooms, `.env` and `local.*` files, the
  identity file `identity.toml`, `prefs.sqlite3` and other data) stay
  outside the repository: in the gitignored `local.yml`/`local.env`,
  settings or the deployment's own repository. Code, tests, fixtures, docs,
  comments, screenshots and commit messages use `example.com`,
  `example.ts.net`, "the user" and the sample vault. Check the diff for them
  before you push: once the repository is public, its history can't take
  them back.
- **No new network endpoints** without discussion. Shiori talks to the
  configured Hister server (and on its host the optional companion
  services, not in this repository: the feed service `/shiori/feed` and the
  AI endpoint `/shiori/ai/*`, hosted pages only, and only in a build with
  `SHIORI_AI=1`), Kura (notes), the
  small-web gateway, SearXNG, the visited site's favicon and PDFs (upstream
  behaviour). With Machiya's identity file, Kura's `POST /api/pair`
  (pairing a device) and, from the web app, Kura's `/api/prefs` (theme and
  text size, as the rooms keep them). NewsBlur, status pages, the Wayback Machine and archive.is
  copies and the build's privacy front ends (`SHIORI_FRONTENDS`, Redlib,
  Invidious…: `Elsewhere`) are only ever opened as links.
  `gemini://`/`gopher://` links are handed to the system, never fetched. No
  analytics. AI providers only when the user switches AI on, and only from
  the app.
- **Never re-add the `cookies` permission.** The extensions use Hister's
  token (`X-Access-Token`), never a session or a cookie.
- **The Machiya sign-in** (docs/signing-in.md): a token (`mch_…` pasted,
  `mcd_…` from `POST /api/pair` with a code) in `Authorization: Bearer`,
  only where the host rule allows (`S.machiyaRooms` /
  `S.mayCarryMachiyaToken`, `Machiya.rooms` / `mayCarryToken`, twins):
  the configured Kura and Konbini by origin, less Hister's and SearXNG's;
  never across a redirect. Rooms in Hister sign-in mode get the app's
  `mhs_` id (the Safari extension asks the app for it), Linux a room token
  (`mht_`, config `roomToken`); no Shiori sends Hister's token to a room. It lives in the Keychain (`MachiyaKeychain`,
  service "Machiya"; Safari's extension asks the app, `machiya`),
  Linux's config.json; never UserDefaults, never logged.
  The extension hands it to its own pages only, never a content script;
  extension fetches keep `credentials: 'omit'`. The hosted pages carry
  none: the browser's `machiya_session` cookie goes to `/kura/` and
  `/konbini/` only, and the host strips it everywhere else.
- **Tests:** `node --test scripts/*.test.mjs` (Node 22 fails on the
  folder form) after touching `patches/`, `scripts/`, `web/` or `linux/`;
  `swift test` in `Packages/HisterKit` and `Packages/ShioriAI`;
  `xcodebuild test -scheme ShioriTests -destination platform=macOS` after
  touching `Shared/`. `HISTER_LIVE_URL` and
  `KURA_LIVE_URL` add read-only checks against real servers.
- **Never test a write against a live Hister.** Use the stubs in the test
  suites or `linux/fake-hister.py`. Reads against your own server are fine.
- **Logic shared by Swift and JavaScript has twins** (HisterKit and
  `patches/shiori/search-core.js`) with the same test cases. Change both.
- **No rule editor in the app**: the server's rules are the truth. Shiori
  edits aliases only through Keep Collections Current (docs/ai.md).
- **The settings that follow the person** (machiya docs/contracts/prefs.md,
  the owner's call): signed in, the Shared ones (theme, appearance, text
  size, pills) and Shiori's own options (`shiori.*`) go to the account at
  the Hister sign-in helper (`/machiya/api/prefs`). Never an address, a
  sign-in or token, an AI setting or this device's own (the preview pane,
  Use This Device's Size). The client rules are twins: `S.prefsSync` /
  `PrefsSync` on `scripts/prefs-sync-cases.json`; `scripts/prefs.schema.json`
  is a copy of the contract's schema, which the tests hold Shiori's keys to.
- **A note from a private vault** (address `/v/<vault>/n/…`, and any other
  page under `/v/<vault>/`, its folder and tag pages included; a vault Kura's
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
  `SHIORI_STATUS_URL`, `SHIORI_SEARCH_PAGE_URL`, `SHIORI_SOURCE_URL`,
  `SHIORI_FRONTENDS` (`redlib=https://…,invidious=https://…,libmedium=…`:
  a web page's menu, and the search page's cards, offer the page there
  beside Archive.org and Archive.is, and a page on one of them its
  original (Open Original on Reddit…, its archives of the original);
  `Elsewhere` / `S.elsewhereLinks`, twins; the web builds take it from
  their environment).
- The user's conventions are build defaults, empty in a public build:
  `SHIORI_OBSIDIAN_VAULT`, `SHIORI_AI_NEVER_SUGGEST`, `SHIORI_AI_NOT_TOPICS`,
  `SHIORI_RESERVED_COLLECTIONS` (comma lists). `SHIORI_ROOM_LOGOS` (a folder
  outside the repository holding `hister.png` and `searxng.svg`) swaps the
  neutral Hister/SearXNG glyphs for their logos; the repository carries no
  other project's logo.
- The web builds take the same names from their environment, plus
  `SHIORI_AI=1` (the host has the AI companion; else no `/shiori/ai/`
  request at all).

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
  are never retried, but a 401/403 (Hister's users on, no token yet) keeps
  the capture, no try counted; 5xx/429 get 5 tries; entries older than 14
  days drop.
  It drains on any Hister reply under 500 and on worker start (no timer: iOS
  suspends the worker). It follows a server change from anywhere
  (`storage.onChanged`; `set-server` marks its own write): queued pages
  move to the new address, and its rules are fetched at once.
- A capture with HTML carries no `text` (Hister derives it). Never strip
  `<script>`: Hister's sensitive-content check reads the raw HTML.
- **The native handler class must be `nonisolated`**: Safari calls it off
  the main thread, and a MainActor handler crashes on every message. Same
  for `NSItemProvider` callbacks and `openURL`'s completion on macOS.
- **Safari is the one extension.** Shiori for Firefox was removed in
  0.4.0: on Firefox and Chrome, upstream Hister's own extension does the
  capturing. Don't bring a second browser target back.
  `scripts/build-extension.sh` builds into `ShioriExtension/Resources/`;
  manifests are upstream's, then `patches/manifest.shiori.json`, then
  `patches/manifest.safari.json`; `scripts/check-extension.py` holds the
  rules.
- Shiori's background logic is `patches/ext/core.js`. It reaches the app
  only through `shioriHost` (`ext/host-native.js`, native messaging). The
  extension never sets the server, the token or the sign-in: the app does,
  and its page (`patches/shiori/options.*`) only shows them. The results
  page's gear goes through `set-settings`, the whitelist.
- **Every deploy is a release**: bump `MARKETING_VERSION` (project.yml)
  and `VERSION` (linux/gjs/save.js) together, add a `## X.Y.Z (date)`
  section to CHANGELOG.md (minor for features, patch for fixes; a test
  holds all three), commit, then tag `vX.Y.Z` on main and push the tag to
  both forges. The hosted builds are made from the tag, and serve
  `/_shiori/status.json` and `/_shiori/CHANGELOG.md`. 1.0.0 marks the
  public release.
- **The background order matters** (`BACKGROUND` in `build-extension.sh`,
  held by tests): `safari-shims`, `host-native`, `core`, `search-core`,
  `badge`, `menus`.
  The core hides `shiori:` messages from every `onMessage` listener added
  after it, so a file with its own `shiori:` messages must come before it;
  `menus` needs `search-core` and `badge` before it.
- **A tab's badge goes back to the toolbar's through `ShioriBadge.clearTab`**
  (`patches/ext/badge.js`): `null` where the browser takes it, else a copy
  kept in step with the count. Safari's answer to `null` hasn't been seen
  on a device.
- The right-click menu (Safari on the Mac, `contextMenus`)
  runs upstream's own commands for its page items (the menu keeps
  upstream's `onCommand` listener). Never add a rule editor there.
- Settings reach the extension through the App Group: the background asks by
  `sendNativeMessage` on every search (400 ms budget, then its cache in
  `storage.local`). A setting the extension page shows must be in both
  `SharedSettings.extensionPayload` and the core's `DEFAULTS`.
- The results page's gear writes through `SharedSettings.applyFromPage`, a
  whitelist of keys, types and values. AI settings are never in it: a page
  must never turn AI on.
- Search from Safari: keep DuckDuckGo; `redirect.js` hands address-bar searches to the hosted search
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

- **Hister's token** (`X-Access-Token`, for a server with users): the
  user's one token, entered once per device (Settings → Server,
  `HisterKeychain`; Safari's extension asks the app by the `hister` native
  message; Linux `histerToken`). It goes to the Hister server and, under
  Machiya's host rule, to the configured Kura and Konbini (rooms in Hister
  sign-in mode read it to know who's asking; a signed-in app sends them
  its `mhs_` id instead); never to the gateway (which also gets `Origin:
  hister://`), SearXNG or anything else, never in a URL, a log, a settings file or the offline queue
  (drain re-reads it), and follows no redirect elsewhere. Unset, nothing
  is sent. `HisterToken` / `S.histerToken` are twins. The hosted pages
  never hold it.
- **Signing in to Hister** (the apps, `HisterAccount`, docs/signing-in.md):
  the app holds a Hister session of its own (`Cookie: hister=…`, HisterKit
  keeps cookies off and sets it) and the sign-in helper's id (`Bearer
  mhs_…` to the rooms, never to Hister), both in the Keychain. The helper
  is on Hister's host under `/machiya/`. Inert: offered only while the
  helper says Hister has users. A 401/403 from Hister is `signedOut`,
  never retried; the outbox keeps its pages until sign-in. Test a sign-in
  only against a throwaway Hister with users (`HISTER_USERS_URL`).
- Every request needs `Origin: hister://`. `limit`, `sort` and `highlight`
  only work inside the JSON `query=` parameter. `*` with sort `date` is
  "recent".
- Snippets are HTML with `<mark>`. A malformed regexp returns zero results.
  Replies can hold raw control characters (decoding retries with them
  blanked).
- Delete is by query: dry-run first, refuse unless exactly one page matches.
- `api/add` replaces a page's metadata (last writer wins) but keeps its label
  when the add has none. Provenance in metadata is best effort.
- **Every Hister query ends in ` -label:vault -metadata.source:vault
  -type:local -metadata.source:code`** (`SearchText.forHister` /
  `S.histerText`, applied inside the clients): notes come from Kura, files
  only on the Files pill (a query with `type:local` keeps them), code only
  on the Code pill (one with `metadata.source:code` keeps it). There's no `NOT` and no exclude parameter;
  a negated field works with exact totals.
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
- **Result cards are tinted in their pill's colour** (Result Style, Tint
  by default): pages blue, notes orange, opened purple, files green, code
  red, Small Web teal; the web's own results stay plain. Every card tint
  is in the contrast tests (`palettes.mjs` `TINTS`, `CARD_TINTS`,
  `SnippetAndSuggestionTests`).
- **Liquid Glass stays on the system chrome**: the theme colours only the
  content layer. Every text colour is at least 4.5:1 on its background and
  surface (`SnippetAndSuggestionTests`, `theme-contrast.test.mjs`).
- **Bars under the navigation bar go through `topBar`**: a safe-area bar on
  iOS 26 and macOS 26, so the system's frosted edge runs under it (an inset
  made a floating slab, or let content show through). Older systems keep the
  theme's background. `topBarBackground()` must be a view, not a colour fill.
- **SwiftUI never runs `.task` on a view whose body is empty**: a check
  that decides whether a view shows must live outside it (AppState, the
  parent), or the view never shows (it hid Sign in to Hister).
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
- **A click (tap) anywhere on a result opens the original or Shiori's
  preview**, as Settings → Click Opens says (`clickOpens`, per device,
  never sent to the account: `clickOpensOriginal`, the web app's twin).
  Automatic previews beside a preview pane and opens the original
  elsewhere. The original is `openPage` / the web app's `openInApp`: a
  note in Obsidian (else Kura), a file from Hister's copy, a page in the
  browser. The other one leads the menu and is the first swipe (the web
  app's ›). The title always opens the original; chips and links inside
  a result keep their own. The search page: a card opens as its title.
- Every delete is Undo, not a confirmation: the delete goes to Hister only
  after the toast.
- **Pull to refresh is Shiori's own (`.pullToRefresh`), not `.refreshable`**:
  with the `topBar` bars under the navigation bar, iOS drew the system's
  spinner where it couldn't be seen and its haptic came late. Ours (iOS)
  arms at 70 pt with a haptic, reloads on letting go, and shows its mark
  under the bars. Web and Small Web have none (the same words find the same).
- **Lists watch for new items, never redraw under you**: every 60 s while
  the app is in front (the web app: the tab visible), an open list asks
  Hister and Kura (never the web) what arrived (`ResultsModel.checkForNew`,
  the web app's `watchForNew`): newest-first lists count unseen first-page
  results, other orders the total's growth. A "↑ N New Items" banner
  reloads and goes to the top on a tap.

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
- Asset addresses carry the build (`?v=<commit>`; the web app's, and its
  service worker's cache name, a hash of the built files); unstamped placeholders
  read as empty (`S.fromBuild`).
- **Nothing searches while typing** (the user's call): Return, the
  field's magnifier, a recent search, Did you mean or a pill runs a
  search, in the apps, the web app and the search page alike, the "Search
  in" fields of collections and labels too; clearing a field resets at
  once. The field keeps the keyboard while you type. Type-ahead
  (autocompleter) still shows.
- **Web searches are frugal** (each counts: a paid search API would
  charge it, as AI is kept frugal): the web is asked only for a search run
  on purpose (Return, a recent search, Did you mean, the Web pill;
  `SearchSession.webAllowed`, the web app's `w=1`). Respellings come from the autocompleter,
  never a `/search`; the "wiki" second search runs only when needed.
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
- **Menus close on the way out** (as the rooms' ui/machiya.js): a link or
  form inside a menu or sheet shuts it before the page goes, and
  `pageshow`, `popstate` and `pagehide` shut what's open (iOS's installed
  apps restore the back/forward cache as left). **Pull to refresh** only in
  the installed app (`S.pullStep`, the rooms' gesture); the web app's
  `#list` counts as the page.
- **Every href goes through `S.linkHref`** (the pages' element builders),
  and a stored address opened from script through `S.safeHref`
  (`SafeHref` in the apps): never `javascript:`, `data:` or `file:`.
- The house's shared settings (theme, text size, hidden rooms) are
  `machiya_*` cookies on the network's domain (`S.houseSettings`).
- AGPL section 13: `SHIORI_SOURCE_URL` puts a Source link in About; only a
  plain http(s) address counts.

## Notes (Kura)

- **Notes come only from Kura** (`/api/search`, `/api/recent`, `/api/note`,
  `/api/vaults`, `feed.xml`), their previews too (`/api/note`, every vault);
  Hister may hold the default vault's notes for its own UI, but Shiori never
  lists, previews or links a note there (no "Open in Hister" on a note).
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

## Files

- The folders Hister watches (its `indexer.directories`): documents of
  `type:local` (domain `local`, a `file://` address). Only the Files pill
  (or tab) shows them, after Small Web, and only while Hister has some
  (`LocalFiles` / `S.filesQuery`, twins); never in All or any other list.
- A file opens from Hister's copy (`/api/file?id=<address>`), is never
  recorded as opened, labelled or deleted, and never folds by site. No AI:
  `AIContent.localFile` makes `EngineChain.eligible` empty, on-device
  engines included. Files queries go into Recent like any other.

## Code

- Your repos (code-import, `metadata.source:code`: repo cards,
  READMEs and docs, issues, PRs, releases, each at its forge URL). Only
  the Code pill shows them, after Files, while Hister has some
  (`CodeDocs` / `S.codeQuery`, twins), with a count from All; never in
  All or any other list.
- Filters are metadata terms, each one lowercase token (Hister can't match
  `/` in a metadata value): `metadata.code_kind:`, `code_state:open`,
  `code_repo:<owner>__<repo>` (`codeRepoKey`), `code_private:true` (a
  string). Rows read `metadata` from the search reply (`CodeInfo`).
- Never labelled, deleted or folded by site (code-import owns them). AI:
  on the device only (`AIContent.code`: Apple Intelligence, not a local
  server, never a cloud engine); the hosted pages never summarize code.
  "code" is a reserved collection name, and an alias naming
  `metadata.source:code` is no collection.

## Small Web

- Searched on submit only (the engines are volunteers'); one engine failing
  is a line above the results.
- The web app's Add Page and share target (`SHIORI_SMALLWEB_URL` builds
  only) save through `POST /smallweb/api/save`, after `api.checkPageURL`
  refuses any note (`/v/<vault>/` by `S.kuraPath`, and `isNoteDoc`). The
  202 means queued: say "Saving…", never "Saved". A share never saves
  without a tap on Save. Where a result opens is a setting (the
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

## Shiori for Haiku (`haiku/`)

- Native C++17 on the Be API, HTTP through the Network Kit's netservices2
  (private, linked statically). `haiku/core/` is portable (no Be headers):
  JSON, the search query, results, settings and the credential rules, tested
  anywhere by `make -f Makefile.test test` (Node's `scripts/haiku.test.mjs`
  runs it where a C++ compiler exists; CI on Linux). `haiku/app/` is the Be
  UI, built only on Haiku (`cd haiku && make`).
- **The core's queries are search-core's twins**: `haiku/tests/vectors.inc`
  is generated from search-core.js (`node haiku/tests/gen-vectors.mjs
  patches/shiori/search-core.js > haiku/tests/vectors.inc`); a test fails
  when they drift, so regenerate after changing search-core.
- Settings: `~/config/settings/Shiori/config.json`, 0600, Linux's keys.
  Hister's token only to Hister; the rooms get the sign-in's `mhs_` or a
  room token (`mht_`), never Hister's token.
- The Be UI can't be run from the Mac: UI checks run on the Haiku test VM
  (`haiku/tests/ui-run.sh`, driven by `hey`, against `haiku/fake-services.py`)
  by machiya's subagent. Never a write against a live Hister there either.
- The version is project.yml's: the Makefile passes `SHIORI_VERSION` and
  writes the gitignored `Version.rdef`; `Icon.rdef` is `haiku/tools/icon.py`'s
  (HVIF), held by a test. `haiku/package.sh` makes the `.hpkg` on Haiku.
- **The Deskbar item runs inside Deskbar**, loaded from the app's binary
  (`instantiate_deskbar_item`; the link exports dynamic symbols, or Deskbar
  can't find it): no networking there, every action a message to the app,
  and never a synchronous `BDeskbar` call from Deskbar's own thread.
- Searches run on Return or a pill, never while typing, as everywhere.
- **One stalled TLS handshake jams a netservices2 session** (one control
  thread connects for all; `BSecureSocket::Connect` ignores the timeout), and
  its destructor then hangs quit and can crash: `Http.cpp` keeps the session
  on the heap, never deletes it, and retires it when a request passes its
  20 s deadline. TLS failures are `ErrorCode() == B_NOT_ALLOWED`, no detail.

