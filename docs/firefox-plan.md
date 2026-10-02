# Plan: Shiori for Firefox

Status: draft, open questions at the end. Nothing here is built yet.

## Why, given upstream already ships one

Hister's own extension builds for Firefox (`manifest_ff.json`, written by
`vendor/hister/webui/ext/vite.config.ts`), and Hister trusts any
`moz-extension://` origin (`server/extension.go`). So capture alone is
solved upstream. A Shiori build earns its place only through what
`patches/` adds on top:

- **The offline queue** (`installCaptureQueue`): per-URL, fail-closed until
  the skip rules are fetched, 5xx/429 retried, 14-day expiry.
- **Provenance**: `metadata.source = "shiori"`, `client`, `client_version`.
- **The page-size cap and HTML-only capture** (`installPageSizeCap`).
- **No `cookies` permission.** Upstream asks for it.
- **Shiori Search**: combined Hister, Kura, SearXNG and small-web results
  (`search.html`), with the DuckDuckGo hand-off (`redirect.js`).
- **Shiori's commands** (Open Shiori Search) and the options page.

## What the Safari build already gives us

`scripts/build-extension.sh` builds upstream, copies `dist/`, merges
`patches/manifest.safari.json`, prepends shims to `background.js` and
`content.js`, stamps placeholders (`__SHIORI_*__`) and checks the bundle.
Most of that is browser-neutral. The Safari-specific parts:

| Piece | Safari | Firefox |
|---|---|---|
| Settings source | The app, via `sendNativeMessage` (`refreshSettings`, `set-settings`, `recent`) | No host app. `storage.local`, edited on the options page |
| `installIconShim` | Works around Safari's grey icon drawing | Not needed; drop |
| `installTabUrlFilter` | Filters Safari-internal URLs | Same idea, different list: `about:`, `moz-extension:`, `about:reader?url=`, `view-source:` |
| `reportQueue` | Tells the app the queue size | Toolbar badge instead |
| Background | `service_worker` | `background.scripts` (event page, non-persistent) |
| Host access | "All Websites" resets to Ask on reinstall | MV3 host permissions are optional in Firefox: the user must grant `<all_urls>` |
| Shortcut limit | 4 suggested keys or the background dies | No such limit known; keep the check Safari-only |
| Packaging | Inside the signed app | `.xpi`, signed by AMO (see questions) |

The shims hook `globalThis.fetch` and `chrome.runtime.sendMessage` at call
time. Firefox exposes both, and `chrome.*` aliases `browser.*` in MV3, so
the hooks should carry over. Verify against the built bundle (the existing
grep rule in CLAUDE.md).

## Phases

### 0. Spike (half a day)

- Build upstream (`npm --workspace @hister/ext run build`) and load
  `dist/` with `manifest_ff.json` in Firefox via `web-ext run`.
- Prepend today's `safari-shims.js` unchanged and see what breaks.
- Confirm: captures land with `metadata.source = "shiori"`; the queue
  drains; PDFs (upstream fetches them from the background with
  `credentials: 'include'`) still index; `Origin` is `moz-extension://…`.

### 1. Split the shims (no Safari behaviour change)

- `patches/ext/core.js`: queue, provenance, combined search, commands,
  search-page check. Gets settings through one `getSettings()`/`setSettings()`
  seam.
- `patches/ext/settings-native.js` (Safari): today's `sendNativeMessage`
  path.
- `patches/ext/settings-local.js` (Firefox): `storage.local` only. Never
  `storage.sync`: settings are per device.
- `patches/safari-shims.js` becomes Safari-only (icon shim, Safari URL
  filter), prepended before core.
- Proof: the Safari bundle built before and after the split behaves the
  same; `node --test scripts/` stays green, plus new tests for the seam.

### 2. A Firefox target in the build

- `scripts/build-extension.sh --target firefox` (default `safari`), or a
  thin `scripts/build-firefox.sh` sourcing shared stamp functions. Output
  in a gitignored `build/firefox/`, never `ShioriExtension/Resources/`.
- `patches/manifest.firefox.json` merged over `manifest_ff.json`:
  - drop `cookies` (the existing check covers it) and `key`;
  - `browser_specific_settings.gecko.id` of our own, derived from
    `SHIORI_BUNDLE_PREFIX` (stays in `local.yml`), so it installs beside
    upstream's Hister extension;
  - keep `data_collection_permissions` honest: `browsingActivity`,
    `websiteContent`;
  - `options_ui` → `shiori-options.html`;
  - `web_accessible_resources: null`, same reasoning as Safari.
- The bundle check learns `background.scripts` as well as
  `service_worker`.
- `npx web-ext lint` and `web-ext build` as the last step.

### 3. Settings and onboarding

The Safari options page is read-only ("set it in the Shiori app").
Firefox needs an editor:

- Server address, SearXNG, Kura/Niwa/Konbini, search-page URL, and the
  results settings the page's gear already writes.
- Validation through the same whitelist as `SharedSettings.applyFromPage`.
  **AI settings stay out**: a page must never turn AI on, and AI is
  app-only.
- A host-permission card: checks `permissions.contains(<all_urls>)`, with a
  Grant button (`permissions.request` needs a user click). Without it
  nothing is captured, the same trap as Safari's reset.
- Connection test (`api/stats`): already there.
- `runtime.onInstalled` opens the options page on first install.

### 4. Search integration

- Keep the DuckDuckGo hand-off (`redirect.js`, `search-core.js` rules,
  never `tabs.update`).
- New: an **omnibox keyword** (`omnibox.keyword`, a manifest key, not a
  permission): type `sh lantern` in the address bar and get suggestions
  from Hister's recent opens and results. It goes to the configured server
  only. No new endpoint.
- Optional: `chrome_settings_overrides.search_provider` pointing at the
  hosted search page, so Shiori appears as a choosable engine. I believe
  this needs an `https` URL, so it fits hosted setups only. Unverified.

### 5. Packaging and docs

- Signing: see question 3.
- `docs/firefox.md` covers build, install, granting site access, and
  signing. Add a README section and a CLAUDE.md block of traps.
- Version: the manifest takes `MARKETING_VERSION`, as Safari's does.

### 6. Tests

- `node --test scripts/` covers manifest merge, the settings seam, the
  whitelist and the URL filter, using the stubbed Hister in the existing
  suites.
- Never write to a live Hister. `linux/fake-hister.py` serves manual
  runs with `web-ext run`.
- An automated in-browser test needs Firefox plus geckodriver or
  Playwright's Firefox build. This container has only Chromium, so it is a
  later step, if wanted.

## Suggested features, beyond parity

Roughly in order of value for effort.

1. **Omnibox keyword with suggestions** (above). It is the Firefox-native
   replacement for the DuckDuckGo trick.
2. **Toolbar badge**: queued count, and a mark when the current page was
   saved or skipped.
3. **Context menu** (`menus` permission):
   - Search Shiori for the selection.
   - Never save this site.
   - Save this link to Hister. Same rules as Save This Note's Links: check
     that Hister doesn't hold the URL, before saving and again after
     redirects.
4. **Sidebar** (`sidebar_action`, Firefox-only): Shiori Search in the
   sidebar, plus "pages from this site" for the current tab.
5. **Private windows**: never capture. `incognito: "not_allowed"` is the
   blunt version; `"spanning"` with a skip check keeps search usable there.
6. **Container rules**: skip capture in chosen Firefox containers (Banking,
   Work). This may need the `cookies` permission to read container names,
   which CLAUDE.md forbids. Unverified; if so, it falls back to matching
   `tab.cookieStoreId` without names, or is dropped.
7. **Firefox for Android**: upstream already sets `gecko_android`. The same
   `.xpi` could give Shiori capture on Android.
8. **Linux app bridge** (native messaging to the GJS app, sharing
   `~/.config/shiori`). Flatpak Firefox and a Flatpak host make native
   messaging painful, so this is the most expensive item.

## Rules this must keep (from CLAUDE.md)

- `vendor/hister/` stays untouched; only the built `dist/` is patched.
- No `cookies` permission, no analytics, no new network endpoints.
- Settings per device, never synced.
- Work-vault notes never go to Hister, a cache, an export or a feed. The
  search page already enforces this; the Firefox settings path must not
  bypass it.
- No personal details in the repo: the gecko ID prefix and AMO keys go in
  `local.yml`/`local.env`.

## Open questions

1. **Scope**: full Shiori (combined search, Kura, options editor) or a thin
   capture build (queue + provenance + no cookies) on top of upstream?
2. **Settings**: an options-page editor in the extension, or native
   messaging to the Linux app?
3. **Distribution**: AMO unlisted (signed, self-hosted `.xpi`), AMO listed
   (public review, needs source upload), or unsigned for Developer
   Edition/Nightly/ESR only? Firefox release refuses unsigned add-ons.
4. **Android**: in scope?
5. **Private windows**: no capture, or not loaded at all?
6. **Minimum version and forks**: Firefox ESR floor? LibreWolf, Zen,
   Floorp?
7. **Features**: which of the suggestions above, and in what order?
