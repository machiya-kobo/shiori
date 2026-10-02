# Small Web: Gemini and Gopher

A **Small Web** source next to Web, for Gemini and Gopher, through a
small-web gateway (TLGS, Kennedy and Veronica-2).

## The gateway, in short

- `GET <gateway>/api/search?q=&source=tlgs,kennedy,veronica&page=` returns
  results with a canonical `url` (`gemini://…` or `gopher://…`), a
  `proxy_url` (the gateway's own HTML rendering, no scripts), a plain
  `snippet` with `marks` (code-point offsets), `source(s)`, `scheme`,
  `kind`, `size` and `archive_url`, plus a status per engine. One engine
  failing never fails the search.
- **Searched on submit only**: no autocomplete, no live search, no
  prefetch (the engines are volunteers'). A first, uncached search can
  take 10 s or more.
- `POST <gateway>/api/save {url}` saves a page to Hister without showing
  it.

## In Shiori

- A **Small Web** scope/tab (teal) beside Web, in the apps, the web app and
  Shiori Search. `SmallWebClient` in HisterKit, `S.smallweb*` and
  `S.markRuns` in search-core, `api.smallweb` in the web app.
- **Where a result opens is a setting** (`smallWebOpen`): through the
  gateway (`proxy_url`, the default; the gateway saves what it shows to
  Hister) or directly (the canonical link, for an app such as Lagrange).
  The other way is always one tap away on the result.
  - Apps: `openURL` on the canonical link; if no app takes it, the gateway
    page opens instead.
  - Web pages: a plain link; the browser hands it to the registered app.
- **A direct open asks the gateway to save the page** (`POST /api/save`:
  `Origin: hister://` from the apps, same-origin `/smallweb/api/save` from
  the hosted pages). Safari's extension page can't (its origin isn't
  accepted) and says so above its results when set to direct.
- Remember What You Open records the canonical `gemini://` address.
- `gemini://` and `gopher://` links are only handed to the system, never
  fetched by Shiori.
- Settings: `smallwebURL` (the build's `SHIORI_SMALLWEB_URL` by default),
  `smallWebTab`, `smallWebOpen`; the hosted pages use `/smallweb/` on their
  own host.
