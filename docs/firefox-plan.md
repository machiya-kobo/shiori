# Plan: Shiori for Firefox

Status: phases 0 (the spike), 1 (the split) and 2 (the Firefox build) done; phase 3 is next.

## Decisions

| Topic | Decision |
|---|---|
| Scope | Full Shiori: capture with the offline queue and provenance, Shiori Search (Hister, Kura, SearXNG, small web, Konbini), commands |
| Settings | Edited in the extension's own settings page. Standalone: no native app, no native messaging, the same on every OS |
| Distribution | Signed by Mozilla as an **unlisted** add-on; the `.xpi` is published on this repository's GitHub Releases |
| Add-on ID | `shiori@machiya-kobo.github.io`, fixed in the repository |
| Updates | Automatic, through `update_url` (an update manifest on GitHub Releases) |
| Android | In scope (Firefox for Android) |
| Private windows | Not loaded at all: `"incognito": "not_allowed"` |
| Floor | **Firefox 153** (the current ESR) on desktop and Android; must work on LibreWolf, Zen and Floorp |
| Platforms | Every OS and architecture Firefox runs on, Haiku included |
| Release builds | On Linux in CI. Building natively on the BSDs is a separate task (see "Building on the BSDs") |
| Features | All six suggestions, in the order of phase 7 |
| Chrome | Later, not scoped yet. The build stays target-based so Chrome is a third target, not a fork (see "Chrome, later") |
| Container permission | Optional: `contextualIdentities` is requested only when container rules are turned on |

## Why, given upstream already ships one

Hister's own extension builds for Firefox (`manifest_ff.json`, written by
`vendor/hister/webui/ext/vite.config.ts`), and Hister trusts any
`moz-extension://` origin (`server/extension.go`). So capture alone is
solved upstream. Shiori adds what `patches/` carries:

- **The offline queue** (`installCaptureQueue`): per-URL, fail-closed until
  the skip rules are fetched, 5xx/429 retried, 14-day expiry.
- **Provenance**: `metadata.source = "shiori"`, `client`, `client_version`.
- **The page-size cap and HTML-only capture** (`installPageSizeCap`).
- **No `cookies` permission** (upstream asks for it).
- **Shiori Search** (`search.html`) and the DuckDuckGo hand-off
  (`redirect.js`).
- Shiori's commands and settings page.

It installs beside upstream's Hister extension (its own add-on ID), though
running both would capture every page twice.

## Platforms and architectures

A WebExtension is JavaScript, HTML and CSS: nothing in it is compiled per
OS or CPU. Settings as a page in the extension (no native messaging host)
keep it that way. So the one signed `.xpi` runs on any build of Gecko,
whatever the OS or architecture.

| OS | Firefox there | Notes |
|---|---|---|
| Windows, macOS, Linux | Mozilla's builds (x86-64, arm64); Linux distributions add other CPUs | |
| FreeBSD, OpenBSD, NetBSD | Ports and packages, including ESR | Hand-tested on the owner's BSD VMs |
| Haiku | Official Firefox in HaikuDepot since R1/beta6, plus LibreWolf, Floorp and Waterfox; **x86_64 only** (R1/beta6 release notes) | Its Firefox version must meet the floor; check on install. Haiku is beta: a Haiku-only fault goes to HaikuPorts, not Mozilla, once it's shown not to be Shiori's |
| Android | Firefox for Android | See "Android" |

Where the rule has to be kept:

- **No platform checks in the extension**: no `runtime.getPlatformInfo`
  branches, no OS-specific paths. Every desktop-only API (Android lacks
  several) is feature-checked and degrades to nothing.
- **Shortcuts**: `Ctrl+Shift+…` is Control on Windows, Linux, the BSDs and
  Haiku, and `MacCtrl` on macOS. Check the chosen keys against Firefox's own
  on each.

## Building on the BSDs

Upstream builds with Vite 8, whose bundler (Rolldown) ships native bindings
for some OS and CPU pairs only. `vendor/hister/package-lock.json` has none
for OpenBSD, NetBSD or Haiku, and FreeBSD on x64 only. So:

- Release builds run in CI on Linux; nobody installing the `.xpi` builds
  anything.
- Building natively on the BSDs is a separate task for another agent on the
  owner's BSD VMs. One lead: Rolldown's WebAssembly binding. It must not
  change `vendor/hister/`: no lockfile edit. Anything extra is installed
  into the untracked `node_modules` by `scripts/build-extension.sh`. It
  applies to the Safari build's upstream step too.

## Forks: LibreWolf, Zen, Floorp

All three are Gecko with the WebExtensions API and accept add-ons signed by
Mozilla, so the same `.xpi` installs. LibreWolf and Floorp also run on Haiku
(HaikuDepot); Waterfox is there too, but isn't a target. To check by hand
on each (not verified):

- LibreWolf's hardening (resist-fingerprinting, strict privacy prefs) leaves
  `storage.local`, background fetches to the server and add-on updates
  working.
- Zen's workspaces and vertical tabs don't confuse the tab-event filter or
  the sidebar.
- Each fork's Gecko base is at or above the floor.

## The minimum version

**153**, for both `gecko` and `gecko_android`. It is set in one place,
`patches/manifest.firefox.json` (the bundle check holds desktop and Android
to the same value), and the release checklist checks it against Mozilla's
ESR page.

- ESR 140 reaches end of life on 13 October 2026 (Firefox 158), when its
  users move to ESR 153 (whattrainisitnow.com/release/?version=esr).
  140.17.0 is its last release.
- `data_collection_permissions` begins in Firefox 140 and Firefox for
  Android 142 (`web-ext lint`), so 153 clears it on both.
- When the next ESR replaces 153, the floor moves with it.
- The BSD and distribution `firefox-esr` packages and Haiku's port are
  expected to follow the ESR channel to 153. That is unverified per OS;
  the hand checks confirm it.

## Android

- The same `.xpi`; `browser_specific_settings.gecko_android` carries the
  floor (upstream sets it already).
- As far as I know, Firefox for Android has no `sidebar_action`, no
  `commands` (keyboard shortcuts), no `menus` and no containers, and its
  `omnibox` support is uncertain. Each feature that uses one checks it
  exists.
- Installing an unlisted `.xpi` from a file on Android may need a hidden
  setting. `docs/firefox.md` documents what's true.
- Neither point is verified yet: the spike had no Android device. It needs
  a hand check on a phone or an emulator.
- The settings page works at phone width (16 px gutters, no horizontal
  scroll), as the web app does.

## What the Safari build already gives us

`scripts/build-extension.sh` builds upstream, copies `dist/`, merges
`patches/manifest.safari.json`, prepends shims to `background.js` and
`content.js`, stamps placeholders (`__SHIORI_*__`) and checks the bundle.
Most of that is browser-neutral. The Safari-specific parts:

| Piece | Safari | Firefox |
|---|---|---|
| Settings source | The app, via `sendNativeMessage` (`refreshSettings`, `set-settings`, `recent`) | `storage.local`, edited on the settings page |
| `installIconShim` | Works around Safari's grey icon drawing | Not needed; drop |
| `installTabUrlFilter` | Filters Safari-internal URLs | Same idea, another list: `about:`, `moz-extension:`, `about:reader?url=`, `view-source:` |
| `reportQueue` | Tells the app the queue size | Toolbar badge (feature B) |
| Recent searches (`recent`) | Asked of the app | Kept in `storage.local` |
| Background | `service_worker` | `background.scripts` (event page) |
| Host access | "All Websites" resets to Ask on reinstall | Optional in Firefox MV3: the user must grant `<all_urls>` |
| Shortcut limit | 4 suggested keys, or Safari drops the background | No such limit known; keep that check Safari-only |
| Packaging | Inside the signed app | Signed `.xpi` on GitHub Releases |

The shims hook `globalThis.fetch` and `chrome.runtime.sendMessage` at call
time. Firefox has both, and `chrome.*` is available in Firefox MV3, so the
hooks should carry over; the spike confirms it against the built bundle.
Shiori's pages have no inline scripts and no `eval`, so they pass upstream's
Firefox CSP (`script-src 'self'`).

## Phases

### 0. Spike (done)

`tools/firefox-spike/` (see its README) builds today's Safari bundle, makes
its manifest loadable in Firefox and nothing more, and drives headless
Firefox through geckodriver against a fake Hister.

It passes in full on **Firefox ESR 140.17 and ESR 153.4**, the two ESR
branches current at the time, and on Ubuntu's Firefox 136 with the floor
lowered.

**Works unchanged.** The Safari shims need no Firefox changes:

- capture reaches `api/add`, with `metadata.source = "shiori"`, `client`
  and `client_version`, the HTML, and no text;
- `Origin` is `moz-extension://…`, which Hister trusts;
- the skip rule holds;
- offline, a capture is queued; back online, it drains with `added` as
  integer seconds;
- Firefox unloads the idle event page (`backgroundState: stopped`); a page
  queued while it was unloaded and offline still drains on wake;
- PDFs reach `api/add_pdf`, and `prepPDF` adds Shiori's metadata;
- the settings page, `search.html` (with ` -label:vault
  -metadata.source:vault`) and the popup load;
- `"incognito": "not_allowed"` keeps it out of private browsing entirely
  (nothing sent);
- `<all_urls>` is granted at install. That is for a temporary install; a
  signed install's prompt still needs a hand check (phase 3's Grant card
  covers both).

**Findings that change the plan:**

1. **`data_collection_permissions` needs Firefox 140 and Firefox for
   Android 142.** The floor is now 153 anyway (see "The minimum
   version").
2. **Drop `nativeMessaging` from the Firefox manifest.** With no app it is
   only a failed call (the shim falls back to its defaults), and Firefox
   would show users a native-messaging permission at install for nothing.
3. **Write `histerURL` explicitly** (phase 3). On a fresh install, the
   queue's start-up rule fetch runs before upstream stores its default
   `histerURL`, so the rules arrive with the first capture instead. The
   queue still fails closed, so nothing leaks. On Safari, the app's reply
   writes it.
4. **Containers don't need `cookies`.**
   - `contextualIdentities.query()` gives names, and `tab.cookieStoreId` is
     readable with `tabs`.
   - Only opening a tab in a container needs `cookies`, and Shiori never
     does that.
   - On Firefox 140 (and 136), installing `contextualIdentities` silently
     switches Firefox's containers on (`privacy.userContext.enabled` false
     → true). On 153 they were already on before the install. It is an
     optional permission anyway (the owner's decision), so it can only
     change Firefox for someone who turns container rules on (feature E).
5. **`web-ext lint`** returns 0 errors and 6 warnings:
   - the two floor warnings above;
   - `UNSAFE_VAR_ASSIGNMENT` in upstream's `shared.js` (×3);
   - one in ours: `search-core.js:629` (`svg.innerHTML` from a constant
     glyph table). It's safe, but it will be rebuilt with DOM calls so the
     signed build carries no warning of ours.

**Fixed along the way:** `scripts/build-extension.sh` died without a
`local.yml` (a failing `$( [[ -f local.yml ]] && … )` under `set -e`). Now
`yml()` returns 0 when the file is missing.

**Not covered here** (hand checks):

- the DuckDuckGo hand-off (needs duckduckgo.com);
- Android;
- the forks;
- a signed `.xpi` install, on 140 especially: in this container a
  zipped install's content script fails to load on 136 and 140 but works on
  153 (see the harness traps).

**Harness traps** (in its README):

- In some containers, a zipped temporary add-on's content script never
  loads, upstream's too ("invalid file descriptor"), so it installs
  unpacked. Seen here on 136 and 140, not on 153.
- Firefox 140 and later need geckodriver's `--allow-system-access` for the
  chrome context (and 153 for opening `moz-extension://` pages).
- A fake server that drops sockets makes Firefox retry GETs on its own.

### 1. Split the shims (done; no Safari behaviour change)

`background.js` on Safari is now three files, prepended in this order:

| File | What it holds |
|---|---|
| `patches/safari-shims.js` | Safari's own: the icon shim and the Safari URL filter |
| `patches/ext/host-native.js` | `shioriHost` on Safari: the app, over native messaging (moved as it was) |
| `patches/ext/core.js` | Shiori's part on both browsers: the queue, provenance, combined search, the search-page check, commands |

The core reaches settings only through `shioriHost`:

- `settings()`;
- `recordSearch(q)`;
- `setSettings(values)`;
- `canReportQueue()` / `reportQueue(count, oldest)`.

`patches/ext/host-local.js` is `shioriHost` on Firefox. It stands in for
the app in `storage.local` (`shioriLocalSettings`, never `storage.sync`),
as a twin of `SharedSettings.swift`:

- `apply` / `applyFromPage`: the same keys, types and values;
- `recordSearch`: 5, newest first, once whatever its case;
- `extensionPayload`: only what was set, plus the recent searches.

AI settings, the server and unknown keys are refused. There's no queue
report; the badge will show it (feature B).

Proof:

- **Code:** comments aside, the old and new Safari code differ only at the
  seam. Two edge cases now behave better: before, a missing
  `sendNativeMessage` threw inside the message listener. Now a recorded
  search fails quietly and a settings change is kept on the device. Real
  Safari always has it.
- **Tests:** `node --test scripts/*.test.mjs` passes 140 of 140. That is
  the 125 before, unchanged, plus a check that the build prepends the files
  in the tests' order, plus 14 for the local host. Those read the key lists
  out of `SharedSettings.swift`, so a key added there and not here fails.
- **Spike:** `tools/firefox-spike/run.sh` on ESR 153 passes all 16 checks
  on the rebuilt bundle.

### 2. The Firefox target in the build (done)

`scripts/build-extension.sh --target firefox` builds into a gitignored
`build/firefox/`. The default target, `safari`, still stages
`ShioriExtension/Resources/`. Each target is one entry in the script's
table: where its bundle goes, which of upstream's manifests it starts from,
and its background files.

| Target | Upstream manifest | Background, in order |
|---|---|---|
| `safari` | `manifest.json` | `safari-shims.js`, `ext/host-native.js`, `ext/core.js` |
| `firefox` | `manifest_ff.json` | `ext/host-local.js`, `ext/core.js` |

Manifests are layered by `scripts/patch-manifest.mjs`, which now takes any
number of overlays:

- upstream's manifest;
- then `patches/manifest.shiori.json`, shared by every browser: name,
  icons, action, content scripts, commands, no `key`, no
  `web_accessible_resources`;
- then `patches/manifest.<target>.json`.

The Safari bundle built this way is **byte-identical** to the one before
the change.

`patches/manifest.firefox.json` adds:

- `permissions: tabs, storage`: no `cookies`, no `nativeMessaging`;
- the fixed ID `shiori@machiya-kobo.github.io` and the update URL;
- `strict_min_version: 153.0` for desktop and Android. This file is the
  floor's one home: no `project.yml` setting, so Xcode never sees it;
- `incognito: not_allowed`;
- `options_ui` (opens in a tab) in place of `options_page`;
- shortcuts on **Alt+Shift** S/P/D/F. Control+Shift S, P and D are
  Firefox's own on Windows and Linux (screenshot, private window, bookmark
  all tabs). The Mac keeps MacCtrl+Shift. In the spike Firefox assigned all
  four. Whether they clash with anything on each OS is a hand check.

`data_collection_permissions` comes from upstream unchanged.

**The bundle check** is now `scripts/check-extension.py ROOT TARGET`, with
tests:

- both targets: no `cookies`, every file the manifest names present,
  Shiori's shims in place;
- Safari: at most four suggested shortcuts;
- Firefox: an event page, no `nativeMessaging`, `incognito: not_allowed`,
  the ID, the update URL, the same floor on desktop and Android, and no
  native-messaging code in `background.js`.

**Last steps**, Firefox only:

- `npx web-ext@10.7.0 lint --self-hosted`: 0 errors, or the build fails;
- `web-ext build` → `build/shiori-firefox-<version>.zip` (unsigned).

**Lint** returns 0 errors and 3 warnings, all `innerHTML` in upstream's
`shared.js`. Ours, in `search-core.js`, is gone: the room glyph is built
node by node, and Firefox renders the same markup as before.

**Proof:**

- 148 of 148 script tests pass;
- `tools/firefox-spike/run.sh` now builds and installs the real Firefox
  bundle and passes on ESR 153. New checks: no native messaging; a settings
  change kept by `host-local.js` with AI keys refused; the shortcuts
  Firefox assigned;
- the packed `.zip` installs on ESR 153 and captures a page.

The settings page is still Safari's read-only one ("set it in the Shiori
app"). Phase 3 replaces it.

### 3. The settings page

Firefox has no app behind it, so the read-only Safari page ("set it in the
Shiori app") becomes an editor. One page for every OS.

- **Server**: the Hister address, with the existing connection test
  (`api/stats`).
- **Neighbours**: SearXNG, Kura, Niwa, Konbini, the small-web gateway, the
  hosted search page. Each is optional and validated as `http(s)`.
- **Results**: the settings the results page's gear already writes, through
  the same whitelist (`SharedSettings.applyFromPage`'s keys, types and
  values). **No AI settings**: a page must never turn AI on, and AI is
  app-only.
- **Site access**: a card that checks `permissions.contains(<all_urls>)`,
  with a Grant button (`permissions.request` needs a click). Without it
  nothing is captured.
- **Queue**: how many pages are waiting, and Retry Now.
- First install (`runtime.onInstalled`) opens the page.
- Saving the server writes `histerURL` and fetches the skip rules at once,
  so the queue has them before the first capture (phase 0, finding 3).
- Build defaults (`SHIORI_SERVER_URL` and the rest, from `local.yml`) fill
  the page only in a build that sets them. The published `.xpi` sets none,
  so it starts empty and asks.

### 4. Search integration

- Keep the DuckDuckGo hand-off (`redirect.js` and `search-core.js`'s rules;
  never `tabs.update`).
- The address-bar keyword is feature A (phase 7).

### 5. Release on GitHub

A GitHub Actions workflow on a version tag:

1. Build on Linux.
2. `web-ext lint`.
3. `web-ext sign --channel=unlisted`, with the AMO API keys from the
   repository's Actions secrets. The keys never go in a file.
4. Write `updates.json`: the add-on ID, this version, and the release
   asset's `.xpi` URL as `update_link`.
5. Attach both files to the release.

Firefox then finds updates through
`releases/latest/download/updates.json`. CI never commits to `main`.

The rest of phase 5:

- **`CLAUDE.md`**: the network rule names the new endpoint. Firefox fetches
  `updates.json` from GitHub on its own schedule; the extension's code never
  contacts GitHub. Add a Firefox block of traps.
- **`docs/firefox.md`**:
  - install on desktop, the forks, Android and Haiku;
  - granting site access;
  - building;
  - the BSD build note.
- **README**: a Firefox section.
- **Version**: the manifest takes `MARKETING_VERSION`, as Safari's does.

### 6. Tests

- `node --test scripts/` covers:
  - the Firefox manifest merge and its checks (no `cookies`, incognito,
    floor, ID, update URL);
  - the settings seam and whitelist;
  - the Firefox URL filter;
  - the `updates.json` writer;
  - each feature's pure logic.
- Writes only against stubs; `linux/fake-hister.py` for manual runs.
- In browser: `tools/firefox-spike/run.sh` (headless Firefox, geckodriver,
  a fake Hister). It grows with each phase and becomes the Firefox check.
- On Node 22, `node --test scripts/` fails before running anything (it
  treats the folder as a module). `node --test scripts/*.test.mjs` works.
- Hand-check before the first release:
  - Windows, macOS, Linux;
  - the BSD VMs, and Haiku x86_64 (Firefox, plus LibreWolf or Floorp there);
  - Android;
  - LibreWolf, Zen, Floorp.

### 7. Features

Ordered by value for effort; each ships on its own. Desktop-only features
check their API and stay off on Android.

**A. Address-bar keyword** (`omnibox` manifest key, no permission)
- Type `sh lantern` to get suggestions from the configured Hister: recent
  opens, then results.
- Enter opens Shiori Search.
- It talks only to the server already configured.

**B. Toolbar badge**
- Shows the queued count.
- Marks whether this page was saved, skipped by a rule, or queued.
- Replaces Safari's `reportQueue`.

**F. Settings export and import**
- A JSON file of this device's settings, for setting up another machine
  without syncing.
- Import goes through the same whitelist as the page.
- It holds addresses only, never queue contents or notes.

**C. Context menu** (`menus` permission; desktop)
- Search Shiori for the selection.
- Never save this site.
- Save this link to Hister, following Save This Note's Links' rules:
  - never a URL Hister holds, looked up before the save and again after
    redirects;
  - skip rules hold;
  - links to files are never saved;
  - `gemini://`/`gopher://` go through the small-web gateway.

**D. Sidebar** (`sidebar_action`; desktop)
- Shiori Search beside the page.
- "From this site" for the current tab.
- Reuses `search.html` and `search-core.js`; no second results page.

**E. Container rules** (desktop)
- Skip capture in chosen containers (Banking, Work), picked by name.
- Needs `contextualIdentities`, and no `cookies` (phase 0, finding 4).
- Requested as an optional permission only when the user turns the rules
  on. Installing it switched Firefox's containers on in the spike. Whether
  a later grant does the same is unchecked; phase 7 checks it.
- The skip happens in the background, before upstream's capture is sent,
  keyed by the sender tab's `cookieStoreId`.

## Chrome, later

Not scoped yet. What we already know, so the Firefox work doesn't close
doors:

- **The build is ready for a third target**: a `chrome` row in
  `build-extension.sh`'s table, upstream's `manifest.json` (a service
  worker, which the core already runs as on Safari),
  `patches/manifest.chrome.json`, and `ext/host-local.js` + `ext/core.js`.
  `host-local.js` is browser-neutral, so Chrome gets the Firefox settings
  page from phase 3.
- **Blocker: Hister won't take Shiori's saves from Chrome.** Stock Hister
  skips its CSRF check for an extension's API calls only from
  `moz-extension://…`, `safari-web-extension://…`, or exactly
  `chrome-extension://cciilamhchpmbdnniabclekddabkifhb`, upstream's own
  Chrome ID (`server/extension.go`, `withCSRF` in `server/server.go`). A
  Shiori Chrome extension gets its own ID from the Chrome Web Store, so its
  `api/add` would answer 403 (CSRF mismatch). Search still works:
  `?format=json` skips that check. Options, none chosen:
  1. Upstream: Hister accepts configured extension IDs. That needs a change
     in Hister; Shiori never patches `vendor/hister/`.
  2. Keep upstream's `key`, so the ID matches. That only works for builds
     loaded unpacked, clashes with upstream's own extension, and can't be
     published.
  3. Rewrite the Origin header to `hister://` with
     `declarativeNetRequest`, as the native apps send it. That's a new
     permission, and it sidesteps the protection the server chose.
     Discuss first.
- **Distribution**: Chrome on Windows and macOS installs extensions only
  from the Chrome Web Store (a developer account and review). Edge has its
  own store; Brave and Vivaldi use Chrome's. Chrome for Android has no
  extensions.
- **Feature differences**: no containers (feature E is Firefox-only); the
  sidebar is `side_panel`, not `sidebar_action`; the context menu is
  `contextMenus`; `omnibox` is the same.
- The BSDs package Chromium, so the platform reach is similar.

## Rules this must keep (from CLAUDE.md)

- `vendor/hister/` stays untouched; only the built `dist/` is patched.
- No `cookies` permission, no analytics. The only new endpoint is the
  approved update manifest.
- Settings per device, never synced (export is a manual file).
- Work-vault notes never go to Hister, a cache, an export or a feed.
- No personal details in the repo; AMO keys live in Actions secrets.
