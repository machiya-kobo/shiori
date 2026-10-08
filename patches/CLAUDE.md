# The Safari extension and the search page: traps and rules

Loaded when you work in `patches/`. The search page (`patches/shiori/search.*`) is also the hosted page: its rules are in `web/CLAUDE.md`. The project-wide rules, layout and build/test commands are in the root `CLAUDE.md`.

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
