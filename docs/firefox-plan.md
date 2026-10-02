# Plan: Shiori for Firefox

Status: scope settled, ready to start with the spike (phase 0). Nothing is
built yet.

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
| Floor | The latest Firefox ESR; must work on LibreWolf, Zen and Floorp |
| Platforms | Every OS and architecture Firefox runs on, Haiku included |
| Release builds | On Linux in CI. Building natively on the BSDs is a separate task (see "Building on the BSDs") |
| Features | All six suggestions, in the order of phase 7 |

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

`strict_min_version` is the latest ESR major at release time. I don't know
which major that is today: 140 was ESR in 2025, and a newer one may have
replaced it. So the build reads it from one place (a
`FIREFOX_MIN_VERSION` line in `project.yml`), and the release checklist
confirms it against Mozilla's ESR page. `data_collection_permissions`
(upstream sets it) needs a recent Firefox too, so the floor can't drop below
140.

## Android

- The same `.xpi`; `browser_specific_settings.gecko_android` carries the
  floor (upstream sets it already).
- As far as I know, Firefox for Android has no `sidebar_action`, no
  `commands` (keyboard shortcuts), no `menus` and no containers, and its
  `omnibox` support is uncertain. The spike confirms which. Each feature
  that uses one checks it exists.
- Installing an unlisted `.xpi` from a file on Android may need a hidden
  setting. Unverified; the spike checks it, and `docs/firefox.md` documents
  what's true.
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

### 0. Spike

- Build upstream; load `dist/` with `manifest_ff.json` through `web-ext run`
  against `linux/fake-hister.py` (never a live Hister for writes).
- Prepend today's shims unchanged; note what breaks.
- Confirm:
  - captures arrive with `metadata.source = "shiori"`;
  - the queue drains;
  - PDFs still index (upstream fetches them from the background);
  - `search.html` works as an extension page.
- Check the open facts:
  - on Android: which APIs exist, and how an unlisted `.xpi` installs;
  - for containers (feature E): whether reading names needs `cookies`.

### 1. Split the shims (no Safari behaviour change)

- `patches/ext/core.js`: queue, provenance, combined search, commands,
  search-page check. It reads settings only through a
  `getSettings()`/`setSettings()`/`recent()` seam.
- `patches/ext/settings-native.js` (Safari): today's `sendNativeMessage`
  path, moved.
- `patches/ext/settings-local.js` (Firefox): `storage.local` only, never
  `storage.sync` (settings are per device).
- `patches/safari-shims.js` keeps only what is Safari's (icon shim, Safari
  URL filter).
- Proof: Safari's staged `ShioriExtension/Resources/` behaves the same before
  and after; `node --test scripts/` stays green, with new tests for the
  seam.

### 2. The Firefox target in the build

- `scripts/build-extension.sh --target firefox` (default `safari`), sharing
  the stamping steps. Output goes to a gitignored `build/firefox/`, never to
  `ShioriExtension/Resources/`.
- `patches/manifest.firefox.json` merged over `manifest_ff.json`:
  - drop `cookies` (the existing check covers it) and `key`;
  - `browser_specific_settings.gecko.id`: `shiori@machiya-kobo.github.io`;
  - `gecko.update_url`:
    `https://github.com/machiya-kobo/shiori/releases/latest/download/updates.json`;
  - `strict_min_version` from `FIREFOX_MIN_VERSION`, for `gecko` and
    `gecko_android`;
  - `data_collection_permissions` kept honest (`browsingActivity`,
    `websiteContent`);
  - `"incognito": "not_allowed"`;
  - `options_ui` → `shiori-options.html`, opened in a tab;
  - `web_accessible_resources: null`, the same reasoning as Safari.
- The bundle check also:
  - accepts `background.scripts` beside `service_worker`;
  - fails unless `incognito` is `not_allowed`;
  - fails unless the ID and the update URL are as above.
- Last steps: `npx web-ext lint`, then `web-ext build`.

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
- In-browser automation needs Firefox and geckodriver (this container only
  has Chromium): a later step.
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
- Skip capture in chosen containers (Banking, Work).
- **Blocked on the spike**: if reading container names needs the `cookies`
  permission, it doesn't get it. That's a rule. Fallback: "never save
  pages from this tab's container", keyed by the tab's `cookieStoreId`
  with no names. If even that needs `cookies`, the feature is dropped and
  the owner is told.

## Rules this must keep (from CLAUDE.md)

- `vendor/hister/` stays untouched; only the built `dist/` is patched.
- No `cookies` permission, no analytics. The only new endpoint is the
  approved update manifest.
- Settings per device, never synced (export is a manual file).
- Work-vault notes never go to Hister, a cache, an export or a feed.
- No personal details in the repo; AMO keys live in Actions secrets.
