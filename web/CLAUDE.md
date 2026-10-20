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
  one holding a private vault's note.
- **Tabs switch in place** on the search page (`switchTo` in search.js): the same
  search's other tab, page, sort or time range is drawn by `show(run)` into a
  fresh copy of the page's `<main>`, unseen, while the old one is held over it
  (`main.tab-snapshot`), then they swap; the address follows by `pushState`, and
  `popstate` switches back. So: anything per tab goes inside `show(run)` and reads
  the run's values; `$` there is the run's own main, and a run left behind must
  touch nothing outside it (guard with `live()`). `<main>` is replaced on each
  switch: a listener on something inside it is delegated from the document.
  Rules on `body > main` reach the held copy too (exclude `.tab-snapshot`). Thumbnails load only from the SearXNG
  host's `/image_proxy`: anything else is dropped.
- **Menus close on the way out**: a link or form inside a menu or sheet shuts
  it first, and `pageshow`, `popstate` and `pagehide` shut what's open.
- **Every href goes through `S.linkHref`** and a stored address opened from
  script through `S.safeHref` (`SafeHref` in the apps): never `javascript:`,
  `data:` or `file:`.
- **Settings is the house's sheet** (vaultkit v0.32) on both pages: ✕ Cancel,
  the title, ✓ Save. Changes preview; only Save keeps them (localStorage,
  cookies, the account, Safari's set-settings), and any other close puts them
  back. Account contact reads the kept settings, never the preview.
- The shared settings (theme, text size, hidden rooms) are `machiya_*` cookies
  on the network's domain (`S.houseSettings`).
- **Basic Search** (`/basic`, web/basic.mjs; web/README.md) is the no-JavaScript
  fallback. It runs in the image's njs on QuickJS: no URL, URLSearchParams or
  Intl there, in it or in what it uses of search-core (`basic.test.mjs` runs
  that in a bare context). Its searches go through this host's routes on
  loopback, never subrequests, so sign-in still applies. Everything from a
  server is escaped; snippets keep only `<mark>`; links are http(s) only.
- **Backgrounds** (docs/backgrounds.md, `patches/shiori/backgrounds.*`, `bg.js`
  from annai) are this browser's own: never the account, the cookies or
  Safari's set-settings. Over one, a surface with text is glass only through
  `--glass-mix`, `--glass-filter` and `--glass-under` (backgrounds.css; Frosted, the reader's opt-in, points them at
  the `--glass-*-frosted` ones and has a lower floor in the test; the search page's Frosted Header points at the
  clear `--glass-*-bar`, so every piece of text on it carries `--glass-backing-bar`), never
  a translucency of its own (off Apple, a moving background, `html.bg-lite.bg-moving`, swaps the
  filter for black under the panel: a backdrop filter re-blurs every frame): the themes sit at 4.5:1, so what shows through may only darken
  a dark panel (`theme-contrast.test.mjs` holds it). Off loads nothing.
