# Plan: Shiori for Firefox

Status: phases 0 to 7 done; the release workflow waits for the AMO keys and a first tag, then the hand checks (docs/firefox.md).

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
| Container permission | **Required** `contextualIdentities` (changed from optional: Firefox 153 refuses it in `optional_permissions`, see feature E) |

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
- **Shiori Search** (`search.html`). Safari's DuckDuckGo hand-off
  (`redirect.js`) stays Safari's: Firefox adds search engines, so it never
  takes another engine's searches.
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

### 3. The settings page (done)

Firefox has no app behind it, so it gets a page that sets things:
`patches/ext/settings.{html,css,js}`, shipped as `shiori-settings.html` (the
manifest's `options_ui`). Safari keeps its read-only `shiori-options.html`;
each build ships only its own. Chrome will use the Firefox page.

| Card | What it does |
|---|---|
| Hister Server | The address (http(s), checked on the page), Save, and the status from `api/stats` ("Connected · N pages", "Can't reach it", or "Needs site access" when that's what's missing) |
| Site Access | Allowed or not, for `*://*/*`; when not, a note and **Allow on All Websites** (`permissions.request` from the click) |
| Waiting to Send | The queue's count and since when, and **Retry Now** |
| Search | Web Results, a note on the `sh` keyword and on adding the hosted page as a search engine, and a link to Shiori Search, whose gear holds the rest |
| Neighbours | SearXNG, Kura, Konbini, the small-web gateway, the Obsidian vault (each optional, checked on the page) |

How it's wired:

- **The server** goes through a new message to the core, `set-server`. It
  is accepted only from `shiori-settings.html` itself, only for an http(s)
  address, and only where the host owns the server (`shioriHost.ownsServer`:
  Firefox yes, Safari no, as the app owns it there). Saving:
  - writes `histerURL`;
  - drops the old server's cached rules and fetches the new one's at once,
    so the queue has them before the first offline capture (phase 0,
    finding 3);
  - sends pages already queued to the new server, instead of leaving them
    for 14 days at the old address.
- **Everything else** goes through `set-settings`, the same whitelist the
  gear uses (`host-local.js`). AI settings, the server and unknown keys are
  refused there. The vault, as in the app, can be renamed but not blanked.
- **The queue** answers `queue-status` and `retry-queue`.
- **First install** (`runtime.onInstalled`, reason `install`) opens the
  page. It's done in `host-local.js`, since only an app-less browser needs
  it. Firefox opened it in the empty start tab.

Changed from the earlier draft:

- **The results options aren't repeated here.** Shiori Search's gear
  already sets them through the same whitelist; the page links to it.
- **The hosted search page isn't a setting.** It is a build-time address
  (`SHIORI_SEARCH_PAGE_URL`). It exists for iOS suspending Safari, which
  Firefox doesn't do.
- **No published build starts empty.** Without `SHIORI_SERVER_URL`, the
  address shown is upstream's default, `http://127.0.0.1:4433/` (right for
  a Hister on the same machine). The page opens on install so it can be
  changed.

Found on the way: Firefox counts the content script's `<all_urls>` match
as a host permission of its own. Revoking site access in about:addons
removes both, and the page's check for `*://*/*` sees either.

Proof:

- **Unit tests:** 154 of 154 script tests pass. The new ones cover:
  - `set-server`: rules swapped, queue moved, an unreachable server still
    saved;
  - refused from any other page, a content script, or a non-http(s)
    address;
  - refused on Safari even from that page's address;
  - queue status and retry;
  - opening on install but not on update.
- **Spike on ESR 153:** 26 of 26 pass. A new session drives the page:
  - it opens on install and finds the server and access;
  - a bad address is refused;
  - saving `http://localhost:8775` stores `http://localhost:8775/` and
    fetches its rules before any capture;
  - a switch and a neighbour are kept;
  - with site access revoked, the page says so, offers Allow, and says the
    server needs site access rather than blaming the network.
- **Screenshots:** both themes at desktop width and phone width (16 px
  gutters).
- **Hand check left:** clicking Allow. Firefox's prompt can't be answered
  from WebDriver.

### 4. Search integration (done)

**No DuckDuckGo hand-off on Firefox.** It worked unchanged, but Firefox
lets you add a search engine, so taking another engine's searches over is
Safari's workaround, not a feature. `redirect.js` and its DuckDuckGo
content script are in `manifest.safari.json` only, and
`check-extension.py` refuses either in a Firefox bundle. The ways in are
the `sh` keyword (below) and the hosted search page's OpenSearch
description (`scripts/build-web.sh`), which Firefox offers to add from the
address bar. The spike checks a search on the real duckduckgo.com stays
there.

**The address-bar keyword** (feature A, brought forward):
`patches/ext/omnibox.js`, with `"omnibox": {"keyword": "sh"}` in
`manifest.firefox.json`.

- Typing `sh lantern` searches the configured Hister after a 150 ms pause,
  so it's one search, not one per key. `search-core.js` (now in Firefox's
  background too) shapes the query as every Shiori search does: the last
  word a prefix, never the notes.
- It suggests up to six pages: those opened before for this search
  (Hister's `history`) first, then the results. Each page appears once
  (`normalizeURL`), web pages only, never a note (`isNoteURL` against the
  Kura and Konbini addresses, `isOtherVault`).
- **Enter on a suggestion** opens it. It also tells Hister it was opened for
  that search (`api/history`, as the results page does), unless Remember
  What You Open is off.
- **Enter on the text** opens Shiori Search for it, in the current tab, a
  new one or a background one, as the person chose. A typed address opens
  as it is.
- It talks only to the configured server. With no server, or the server
  out of reach, there are no suggestions, and Enter still opens Shiori
  Search.
- Firefox for Android: the manifest key passes lint; whether Android
  offers the keyword at all is part of the Android hand check.

Background order on Firefox is now `host-local.js`, `core.js`,
`search-core.js`, `omnibox.js` (the build, the tests and
`check-extension.py` agree).

Proof:

- **Unit tests:** 163 of 163 script tests pass. Nine are new for the
  keyword (`scripts/omnibox.test.mjs`): the query, the order and filters,
  the six-suggestion limit, one search for fast typing, failures, each Enter
  and each kind of tab, and Remember What You Open on and off.
- **Spike on ESR 153:** 34 of 34 pass. Typed into Firefox's own address bar:
  - `sh lantern` shows the fake's two pages, the one opened before first;
  - Enter on one opens it and posts `api/history`;
  - Enter on `sh paper lanterns` opens
    `search.html?q=paper%20lanterns`.
- **Lint:** unchanged, 0 errors and upstream's 3 warnings.

### 5. Release on GitHub (built; waiting on the first tag)

`.github/workflows/firefox-release.yml`, on a `v*` tag:

1. checks the tag is `v` + `MARKETING_VERSION` (the apps and the extension
   share the version);
2. runs `node --test scripts/*.test.mjs`;
3. builds with `SHIORI_SOURCE_URL` set to this repository (AGPL section
   13), which lints (0 errors or stop) and packs;
4. packs the source of this repository and the Hister submodule at the
   tag, since the built code is bundled and Mozilla's review wants it
   readable;
5. `web-ext sign --channel unlisted`, the keys from the Actions secrets
   `AMO_JWT_ISSUER` and `AMO_JWT_SECRET` (as environment variables, never
   on a command line or in a file);
6. `scripts/firefox-updates.mjs` writes `updates.json` from the built
   manifest: ID, version, download link, the signed file's SHA-256, the
   floor;
7. attaches the `.xpi` and `updates.json` to the tag's GitHub Release,
   creating it or adding to it.

Run by hand, it stops after the build and keeps the unsigned package as
the run's artifact. CI never commits.

Checked here:

- `actionlint` (with shellcheck) on the workflow;
- `firefox-updates.mjs` and its tests;
- a rehearsal of every step but signing and the release itself: CI-style
  build with no `local.yml`, the Source link stamped, the source archive,
  `updates.json`.

shellcheck also caught a real bug in the spike's `run.sh`: an `export` read
`WORK` before setting it. Fixed.

Not checkable here:

- the signing itself (it needs the keys);
- the first release;
- an update from one signed release to the next.

The first tag will show them. Actions are pinned to major versions, since
their commit hashes couldn't be looked up from here.

Docs:

- `docs/firefox.md`: install, first run, use, what it talks to, building,
  releasing, the hand checks, and when something's wrong;
- a README section, with the extension's description brought up to date
  after the split;
- `CLAUDE.md`: `updates.json` in the network rule, and the release rules.

### 6. Tests (done as each phase went)

- `node --test scripts/*.test.mjs`: 167 tests, among them:
  - the manifests and their checks (`check-extension`, `patch-manifest`);
  - the host and its twin rules (`host-local`);
  - the settings page's messages;
  - the keyword (`omnibox`);
  - the update manifest (`firefox-updates`).

  On Node 22 the folder form, `node --test scripts/`, fails before running
  anything (it treats the folder as a module).
- `tools/firefox-spike/run.sh`: the real Firefox build in headless Firefox
  against a fake Hister, 34 checks on ESR 153.
- The Firefox tab-URL filter planned in phase 1 wasn't needed. Upstream
  already skips `moz-extension://`, and content scripts never run on
  Firefox's `about:` pages. No spike check showed a problem.
- The hand checks before a release are listed in `docs/firefox.md`.

### 7. Features (done)

Each shipped on its own commit, with unit tests and spike checks. The spike
now has 50 checks on ESR 153, and 190 unit tests pass. The Firefox
background, in order:

1. `host-local.js`
2. `containers.js`
3. `core.js`
4. `search-core.js`
5. `pages.js`
6. `omnibox.js`
7. `badge.js`
8. `menus.js`

**A. Address-bar keyword**: done in phase 4.

**B. Toolbar badge** (`ext/badge.js`)

- Every tab's toolbar button shows how many pages are waiting to send
  (amber, dark text, 8.55:1), with a tooltip that says so. It clears when
  the queue drains.
- Upstream clears a tab's badge with `""`, which would hide the count; that
  becomes `null`, "use the count". Upstream's own `!` and `✓` stay.

**F. Settings export and import** (`ext/settings-file.js`, Another Device
on the settings page)

- Save to a File writes the server and this device's settings, never
  recent searches, queued pages or notes.
- Open a File reads one, says what it would change, and applies only on
  Apply. It goes through the page's own doors (`set-server` and the
  whitelist), so a file can't set anything the page couldn't. Whatever was
  refused is named.

**C. Context menu** (`ext/menus.js`, permission `menus`)

- Search Shiori for "…", in a tab beside this one.
- Save Page to Hister, Never Save This Page, Never Save This Site: these
  run upstream's own commands (the menu keeps upstream's command listener
  as upstream adds it), so the server's rules stay the truth. No rule
  editor.
- Save Link to Hister follows Save This Note's Links' rules:
  - never a file, and never a page Hister holds, looked up before and again
    after redirects;
  - downloaded without cookies, with `http://` tried as `https://` first;
  - skip rules hold (no `ignore_skip_rules`);
  - `gemini://` and `gopher://` go through the small-web gateway.
- A saved link goes through the core's fetch, so it carries Shiori's
  metadata (`via: context-menu`) and waits in the queue offline.
- The answer shows on the tab's badge and tooltip for six seconds, rather
  than as notifications, which would need a new permission.

**D. Sidebar** (`ext/sidebar.*`, `sidebar_action`)

- A field searches your pages as you type.
- While it's empty, "From This Site" shows what you've saved from the
  active tab's site, newest first (`domain:<hostname>`, sort `date`), and
  follows the tab.
- Snippets keep Hister's `<mark>`s and nothing else. Script and style text
  is dropped; the results page still shows it, untouched here.
- A plain click opens the page in the current tab, and for a search tells
  Hister it was opened (unless Remember What You Open is off). A modified
  click opens a new tab.
- `_execute_sidebar_action` is a command with no key of its own.
- The page list it shares with the keyword is `ext/pages.js`.

**E. Container rules** (`ext/containers.js`, permission
`contextualIdentities`)

- Choose containers on the settings page. A page in one of them is never
  captured on its own: the automatic capture is answered as a skip rule
  would answer it (406), and a PDF tab there is never fetched. A deliberate
  save ("Index this page now", Save Page) still goes through.
- The list (cookieStoreIds) comes only from the settings page, through
  `set-skip-containers`, guarded like `set-server`.
- **Why the permission is required, not optional.** Firefox 153's schema
  makes `contextualIdentities` a required-only permission
  (`PermissionNoPrompt`). Firefox drops it from `optional_permissions` at
  install with a warning, so an Allow button could never be granted for a
  real user.

  The spike had first granted it from Firefox's privileged side, which
  skips that check; Firefox's parsed manifest (`optionalPermissions: []`)
  showed the truth. The owner chose required. It costs no prompt at
  install.
- **Its side effect.** Installing Shiori switches Firefox's containers on
  where someone had turned them off (spike: `false` → `true` on 153).
  Firefox 153 has them on by default. Granting it later would not have
  switched them on, but Firefox doesn't allow that.
- **Order matters.** `containers.js` runs before `core.js`. The core hides
  `shiori:` messages from every listener added after it, and that had
  hidden this file's own. A test on the real Firefox order now catches
  this.

**Hand checks left** (docs/firefox.md):

- the right-click menu itself (WebDriver can't open it);
- the sidebar from View → Sidebar;
- the file dialogs on Android.

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
  `contextMenus`. `omnibox` is the same API, but Chrome reads a suggestion's
  description as XML: `omnibox.js` must escape `&`, `<` and `>` there
  (Firefox shows it as plain text).
- The BSDs package Chromium, so the platform reach is similar.

## Rules this must keep (from CLAUDE.md)

- `vendor/hister/` stays untouched; only the built `dist/` is patched.
- No `cookies` permission, no analytics. The only new endpoint is the
  approved update manifest.
- Settings per device, never synced (export is a manual file).
- Work-vault notes never go to Hister, a cache, an export or a feed.
- No personal details in the repo; AMO keys live in Actions secrets.
