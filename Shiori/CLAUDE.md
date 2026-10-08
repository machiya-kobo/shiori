# Shiori (the iPhone, iPad and Mac apps): traps and rules

Loaded when you work in `Shiori/`. The project-wide rules, layout and build/test commands are in the root `CLAUDE.md`.

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
