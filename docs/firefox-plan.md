# Plan: Shiori for Firefox

Status: decided scope, a few questions left (end of file). Nothing is built
yet.

## Decisions

| Topic | Decision |
|---|---|
| Scope | Full Shiori: capture with the offline queue and provenance, Shiori Search (Hister, Kura, SearXNG, small web, Konbini), commands |
| Settings | Edited in the extension's own settings page. Standalone: no native app, no native messaging, same on every OS |
| Distribution | Signed by Mozilla as an **unlisted** add-on; the `.xpi` is published on this repository's GitHub Releases |
| Android | In scope (Firefox for Android) |
| Private windows | Not loaded at all: `"incognito": "not_allowed"` |
| Floor | The latest Firefox ESR; must work on LibreWolf, Zen and Floorp |
| Platforms | Every OS and architecture Firefox runs on |

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
keep it that way. So the signed `.xpi` runs on any build of Gecko,
whatever the OS or architecture, with no per-platform builds.

| OS | Firefox there | Notes |
|---|---|---|
| Windows, macOS, Linux | Mozilla's builds; x86-64 and arm64 (Linux also others via distributions) | |
| FreeBSD, OpenBSD, NetBSD | Ports/packages, including ESR | Tested by hand; the README's quickstart already covers these OSes for the web pages |
| Android | Firefox for Android | See "Android" below |
| Haiku | No current Firefox port that I know of (its browser is WebKit-based) | Out of reach unless a Gecko port exists |

Where the rule does have to be kept:

- **No platform checks in the extension.** No `runtime.getPlatformInfo`
  branches, no OS-specific paths, no reliance on a desktop-only API without a
  fallback (Android lacks several; see below).
- **Shortcuts**: `Ctrl+Shift+…` maps to Control on Windows/Linux/BSD and
  `MacCtrl` on macOS. Check that the chosen keys don't collide with Firefox's
  own on each.
- **The build is not portable, and doesn't need to be.** Upstream builds
  with Vite 8, whose bundler (Rolldown) ships native bindings only for some
  OS/CPU pairs: no OpenBSD, NetBSD or Haiku, and FreeBSD on x64 only
  (checked in `vendor/hister/package-lock.json`). The release `.xpi` is
  built and signed in CI on Linux; nobody installing it builds anything. A
  contributor on a BSD builds the extension on another machine or in a
  Linux VM, or the README says so.

## Forks: LibreWolf, Zen, Floorp

All three are Gecko with the WebExtensions API, and all accept add-ons
signed by Mozilla, so the same `.xpi` installs. Things to check by hand on
each (not verified):

- LibreWolf's hardening (resist-fingerprinting, strict privacy prefs) does
  not break `storage.local` or background fetches to the server.
- Zen's vertical tabs and workspaces don't confuse the tab-event filter.
- Each fork's ESR-equivalent base is at or above our floor.

## The minimum version

`strict_min_version` is the latest ESR major at release time. I don't know
which major that is today (140 was ESR in 2025; the next ESR may already
have replaced it), so the build reads it from one place (`project.yml` or a
`FIREFOX_MIN_VERSION` line) and the release checklist confirms it against
Mozilla's ESR page. `data_collection_permissions` (upstream already sets it)
needs a recent Firefox too, so the floor can't drop below 140.

## Android

- The same `.xpi`; `browser_specific_settings.gecko_android` carries the
  floor (upstream sets it already).
- Firefox for Android lacks some desktop APIs. As far as I know: no
  `sidebar_action`, no `commands` (no keyboard shortcuts), no `menus`, and
  `omnibox` support is uncertain. Every feature that uses one of them
  checks the API exists and degrades to nothing.
- Installing an unlisted `.xpi` on Android from a file: I believe Firefox for
  Android release needs a hidden setting for that. Unverified; the spike
  checks it, and `docs/firefox.md` documents whatever is true.
- The options page must work at phone width (16 px gutters, no horizontal
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
| `reportQueue` | Tells the app the queue size | Toolbar badge instead |
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

- Build upstream and load `dist/` with `manifest_ff.json` via `web-ext run`
  against `linux/fake-hister.py` (never a live Hister for writes).
- Prepend today's shims unchanged; note what breaks.
- Confirm: captures arrive with `metadata.source = "shiori"`; the queue
  drains; PDFs still index (upstream fetches them from the background);
  `search.html` works as an extension page.
- Check on Firefox for Android: installing an unlisted `.xpi` from a file,
  and which APIs are missing.

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
  the stamping steps. Output in a gitignored `build/firefox/`, never
  `ShioriExtension/Resources/`.
- `patches/manifest.firefox.json` merged over `manifest_ff.json`:
  - drop `cookies` (the existing check covers it) and `key`;
  - our own `browser_specific_settings.gecko.id` (question 1);
  - `strict_min_version` from the single floor setting, for `gecko` and
    `gecko_android`;
  - `data_collection_permissions` kept honest (`browsingActivity`,
    `websiteContent`);
  - `"incognito": "not_allowed"`;
  - `options_ui` → `shiori-options.html`, opened in a tab;
  - `web_accessible_resources: null`, the same reasoning as Safari;
  - `update_url` only if question 2 says yes.
- The bundle check learns `background.scripts` beside `service_worker`, and
  fails if `incognito` isn't `not_allowed`.
- Last steps: `npx web-ext lint`, then `web-ext build`.

### 3. The settings page

Firefox has no app behind it, so the read-only Safari page ("set it in the
Shiori app") becomes an editor. It is one page for every OS.

- **Server**: the Hister address, with the existing connection test
  (`api/stats`).
- **Neighbours**: SearXNG, Kura, Niwa, Konbini, the small-web gateway, the
  hosted search page; each optional and validated as `http(s)`.
- **Results**: the settings the results page's gear already writes, through
  the same whitelist (`SharedSettings.applyFromPage`'s keys, types and
  values). **No AI settings**: a page must never turn AI on, and AI is
  app-only.
- **Site access**: a card that checks `permissions.contains(<all_urls>)`
  and offers a Grant button (`permissions.request` needs a click). Without
  it nothing is captured.
- **Queue**: how many pages are waiting, and a Retry Now button.
- First install (`runtime.onInstalled`) opens the page.
- Build defaults (`SHIORI_SERVER_URL` and the rest from `local.yml`) fill the
  page only in a build that sets them. The published `.xpi` sets none, so
  it starts empty and asks.

### 4. Search integration

- Keep the DuckDuckGo hand-off (`redirect.js` and `search-core.js`'s rules;
  never `tabs.update`).
- An address-bar keyword through the `omnibox` manifest key: `sh lantern`,
  with suggestions from the configured Hister. Desktop only if Android lacks
  it.

### 5. Release on GitHub

- A GitHub Actions workflow on a version tag:
  1. Build on Linux.
  2. `web-ext lint`.
  3. `web-ext sign --channel=unlisted`, using AMO API keys from the
     repository's Actions secrets. The keys never go in a file.
  4. Attach the signed `.xpi` to the release.
- If question 2 is yes, the workflow also publishes the update manifest.
- `docs/firefox.md` covers install (desktop, forks, Android), granting site
  access, building, and the BSD build note. Add a README section and a
  CLAUDE.md block of traps.
- The manifest version comes from `MARKETING_VERSION`, as Safari's does.

### 6. Tests

- `node --test scripts/` covers:
  - the Firefox manifest merge and its checks (no `cookies`, incognito,
    floor);
  - the settings seam;
  - the settings whitelist;
  - the Firefox URL filter.
- Stubs only for writes; `linux/fake-hister.py` for manual runs.
- In-browser automation needs Firefox and geckodriver (this container only
  has Chromium): a later step.
- Hand-check before the first release on:
  - Windows, macOS, Linux
  - one BSD
  - Android
  - LibreWolf, Zen, Floorp

## Suggested features beyond parity (not yet confirmed)

1. **Address-bar keyword** (in phase 4).
2. **Toolbar badge**: the queued count, and whether this page was saved or
   skipped.
3. **Context menu**:
   - Search Shiori for the selection.
   - Never save this site.
   - Save this link. Same rules as Save This Note's Links: check Hister
     doesn't hold the URL, before saving and again after redirects.
4. **Sidebar**: Shiori Search beside the page, and "pages from this site".
   Desktop only.
5. **Container rules**: skip capture in chosen containers. Reading their
   names may need the `cookies` permission, which is ruled out; unverified.
6. **Settings export/import** as a JSON file: a way to set up several
   machines without syncing. AI and secrets aren't in it, as there are none
   here.

## Rules this must keep (from CLAUDE.md)

- `vendor/hister/` stays untouched; only the built `dist/` is patched.
- No `cookies` permission, no analytics, no new network endpoints (the
  update URL is question 2).
- Settings per device, never synced.
- Work-vault notes never go to Hister, a cache, an export or a feed.
- No personal details in the repo. AMO keys live in Actions secrets.

## Open questions

1. **Add-on ID**: one fixed ID for the published `.xpi`, kept in the repo
   (for example `shiori@machiya-kobo.github.io`, matching the Flatpak's
   `io.github.machiya_kobo`)? Unlisted signing ties the ID to the AMO
   account that first signs it.
2. **Automatic updates**: Firefox only updates a self-hosted add-on through
   `update_url`, a JSON file it fetches on a schedule (here, from GitHub).
   That is a new endpoint the browser contacts. Allow it, or ship without it
   and update by hand from Releases?
3. **Features**: which of the six suggestions are in, and in what order?
4. **BSD builds**: is "build the `.xpi` elsewhere" acceptable for the BSDs,
   or must the extension build natively there? That would mean a wasm
   fallback for Rolldown, or bundling upstream ourselves.
