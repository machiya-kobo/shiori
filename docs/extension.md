# The Safari extension

Hister's [official extensions](https://hister.org/docs/browser-extension) cover Firefox and Chrome, and [hister-safari](https://github.com/nburns/hister-safari) brings Hister to Safari on the Mac. Safari on iPhone and iPad loads only extensions that ship inside a signed app, so Shiori carries Hister's own extension, built for Safari.

**Where it comes from.** Shiori's Safari extension is Hister's own extension, built from Hister's source (a pinned submodule, never modified) and patched at build time. That design, the build pipeline, the manifest merge and the Safari shims (`patches/safari-shims.js`) come from [hister-safari](https://github.com/nburns/hister-safari) by Nick Burns, which Shiori started from; it's AGPL-3.0, like Shiori. What Shiori adds is the offline queue, settings shared with the app, the search page, and carrying the extension in an iPhone and iPad app.

It runs on the Mac too. Use Shiori's or hister-safari there, not both: with both on, Safari sends every page twice.

To install it, [build the apps](build.md), then [turn on the extension](build.md#turn-on-the-extension).

## Search from Safari's address bar

Settings → Safari → Search with Shiori, on by default.

- Keep DuckDuckGo as Safari's search engine. Address-bar searches open Shiori instead: your pages and notes first, then the web from your SearXNG.
- `!bangs` still go to DuckDuckGo.
- If SearXNG doesn't answer, your own pages stay. With none, you land on DuckDuckGo.
- Thumbnails come only through your SearXNG's `/image_proxy`, so the device never contacts the engines' image hosts. Stock SearXNG proxies images only in its HTML, so its JSON needs a plugin (not in this repository). Without one, there are no thumbnails.

## Safari-only behavior

- **Offline queue.** With the server out of reach, a captured page waits on the device, stamped with your visit's time, and goes when the server answers.
  - It keeps the newest 100 pages (24 M characters at most), one per URL, for up to 14 days, and stores no credentials.
  - Pages the server refuses (a skip rule, too large, sensitive content) are dropped.
  - Nothing is queued until the skip rules have been fetched once, and they still apply offline.
  - A new server address takes the queue with it.
- **Waiting count** on the Mac's toolbar button. Settings → Account → Waiting to Send shows it on every device.
- **Right-click menu** (the Mac):
  - Search Shiori for the selection.
  - Upstream's Save Page to Hister, Never Save This Page and Never Save This Site.
  - Save Link to Hister. It never saves a file or a page Hister already has, and saves `gemini://` and `gopher://` links through the small-web gateway.
- **Sites never saved.** Safari has no containers. Turn Shiori off in a Safari profile (Safari Settings → Profiles → Extensions) and browse those sites there.
- **Size cap.** Mobile Safari kills extensions that use too much memory, so page HTML over 2 M characters is cut at a tag boundary, never dropped. Hister reads the text from the HTML; text alone is capped at 1 M.
- **Tagged captures.** Every page carries `metadata.client: "shiori"` and `metadata.client_version`. Search `metadata.client:shiori` to find them.
- **No cookies permission.** The popup's "Authenticate with Browser Session" won't work. Use an access token ([signing-in.md](signing-in.md)), or a server gated by your network.
- **Touch-sized popup.** It's full width on iPhone and iPad.
- **Keyboard shortcuts.** Control-Shift-S saves the page, Control-Shift-P never saves this page, Control-Shift-D never saves this site, and Control-Shift-F opens Shiori. Change them in Safari Settings on the Mac.

The popup, skip rules, "index this page", "skip this page/domain" and PDF indexing are upstream's own.

## How it's built

- `vendor/hister/` pins the **official upstream extension** as a git submodule (currently **v0.20.0**, extension 0.31.0). Shiori never modifies or forks it.
- `scripts/build-extension.sh` builds it with npm, then patches the built bundle:
  - `patches/manifest.shiori.json` and `patches/manifest.safari.json`: icons, name, Shiori's shortcuts, no `cookies` permission.
  - Prepended to `background.js`: `patches/safari-shims.js`, `patches/ext/host-native.js`, `patches/ext/core.js` (the offline queue, tagged captures, combined search), `patches/shiori/search-core.js`, `patches/ext/badge.js` and `patches/ext/menus.js`.
  - Prepended to `content.js`: `patches/safari-content-shim.js` (the size cap).
  - `patches/safari-popup.css` for touch screens.
- `project.yml` ([XcodeGen](https://github.com/yonaskolb/XcodeGen)) generates one Xcode project: an iOS/iPadOS app, a macOS app, and a Safari Web Extension for each. `Packages/HisterKit` is the Hister API client, query suggestions and the themes, tested with `swift test`.

## Updating upstream

Move the submodule to an upstream tag, rebuild and test:

```bash
git -C vendor/hister fetch --tags
git -C vendor/hister checkout vX.Y.Z
scripts/build-extension.sh && node --test scripts/*.test.mjs
git add vendor/hister
```

The build fails if upstream asks for a new permission or moves its default server URL, so a bump can't change either unnoticed. Your Hister server should run the same version.
