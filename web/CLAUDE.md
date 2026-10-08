# The search page and the web app: traps and rules

Loaded when you work in `web/` (and for the search page in `patches/shiori/`). The project-wide rules, layout and build/test commands are in the root `CLAUDE.md`.

## The search page and the web app

- `patches/shiori/search.*` runs as the extension's page and as a hosted page
  (`scripts/build-web.sh`); `web/shim.js` stands in for the extension APIs.
  The web app is `web/app/` (`scripts/build-pwa.sh`), plain ES modules sharing
  `search-core.js` and the theme tokens.
- **One host serves everything** (web/README.md): the page, `/searx/`,
  `/kura/` (only the API paths Shiori uses), `/konbini/`, `/smallweb/`, and
  Hister. **Never add `Origin: hister://` there**: Hister accepts same-origin
  browser writes and refuses cross-site ones, and that check protects it.
- Asset addresses carry the build (`?v=<commit>`; the service worker's cache
  name is a hash of the built files); unstamped placeholders read as empty
  (`S.fromBuild`). `sw.js` caches only the app's own files and only `ok`
  responses, and waits for "New Version · Reload" (`SKIP_WAITING`).
- **`replaceChildren`/`append` write a `null` child out as the text "null"**:
  filter first.
- The web app's list fills its column with frosted bars laid over its top
  (`--frost`, `--bars`); `#list` stays the scroller (the load-more observer's
  root); sticky headings inside it use `top: 0`. Clicks inside the sandboxed
  preview never reach the page: menus close on the window's `blur` and Escape.
- Collapsible sections are a button and a grid-rows body, not `<details>`
  (which re-decoded images and flashed). Every tab keeps All's width.
- The search page caches each results page for Back (`shioriPageCache`), never
  one holding a private vault's note. Thumbnails load only from the SearXNG
  host's `/image_proxy`: anything else is dropped.
- **Menus close on the way out**: a link or form inside a menu or sheet shuts
  it first, and `pageshow`, `popstate` and `pagehide` shut what's open.
- **Every href goes through `S.linkHref`** and a stored address opened from
  script through `S.safeHref` (`SafeHref` in the apps): never `javascript:`,
  `data:` or `file:`.
- The shared settings (theme, text size, hidden rooms) are `machiya_*` cookies
  on the network's domain (`S.houseSettings`).
