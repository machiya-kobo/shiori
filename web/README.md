# Shiori's results page on the web

The page Safari's extension shows for an address-bar search, served as an
ordinary web page, so any browser on your network can use it, and Firefox
(or anything that reads OpenSearch) can add it as a search engine without
an extension. It's the same `patches/shiori/search.*`; `web/shim.js`
stands in for the few extension APIs it uses.

## Build

    scripts/build-web.sh OUT_DIR https://<the page's host>/ [https://<status page>]
    scripts/build-pwa.sh OUT_DIR [https://<status page>]

`OUT_DIR/index.html` is the page, and its files are under
`OUT_DIR/_shiori/` (with `opensearch.xml`, which is the only file that needs
the host name). The optional last address is a status
page: the search page links it in its footer, the web app in its sidebar
and Settings. Without it there is no link. Rebuild after pulling a new
Shiori.

## What the host must route

One host serves everything, so the page's requests are all same-origin
(SearXNG sends no CORS headers, and Hister's writes only accept its own
origin):

| Path | Goes to |
|---|---|
| `/` (with any `?q=…`), `/_shiori/*`, and for the web app `/sw.js` and `/manifest.webmanifest` | the built files (`/` is `index.html`) |
| `/searx/*` | SearXNG, `/searx` removed (the page asks for `search?format=json` and `image_proxy`) |
| `/konbini/*` | Konbini, `/konbini` removed (only `api/cards`) |
| `/kura/api/search`, `/kura/api/recent`, `/kura/api/note`, `/kura/api/vaults`, `/kura/api/prefs`, `/kura/feed.xml` | Kura, `/kura` removed: your notes, and (signed in) your theme and text size. **Only these**: anything else under `/kura/` should be a 404, never Kura's reader (below) |
| `/smallweb/*` | the small-web gateway, `/smallweb` removed (`api/search`, `api/save`): Gemini and Gopher, and the web app's Add Page (any http(s), gemini or gopher page; its `SMALLWEB_ORIGINS` must include this host's origin) |
| anything else | the Hister host as it is: Hister's API (`/search`, `/api/*`, `/preview`), and the optional `/shiori/feed` and `/shiori/ai/*` (companion services, not part of this repository: README) |

Pass requests through **unchanged**. Do not add `Origin: hister://`: Hister
lets a same-origin browser write (`Sec-Fetch-Site: same-origin`) and
refuses a cross-site one (403), and that check is what keeps other sites
from, say, deleting pages through this host. Keep the host private (your
network or VPN), like Hister itself, which has no login.

**Kura's reader pages stay at Kura's own address.** Kura gives a work
vault's note an address starting `/v/<vault>/n/`, and Shiori (the
extension's capture included) keeps such a page out of Hister, AI and
caches by that `/v/` at the start of the path. Under `/kura/` the same
page would read as any other, so pass only the API paths above.

**Signing in (Machiya's identity file).** When Kura and Konbini run with
Machiya's identity file they ask who is calling, and these pages carry no
token: they use the browser's `machiya_session` cookie, from the room's
own sign-in page (`<kura>/signin`) with `MACHIYA_COOKIE_DOMAIN` covering
this host too. So the host must:

- pass `Cookie` through to `/kura/` and `/konbini/` unchanged, and their
  `Set-Cookie` back (a session is renewed on use);
- take `machiya_session` out of the `Cookie` header on every other route
  (Hister, SearXNG, the gateway): only the rooms read it.

The pages only read the rooms, with one exception: signed in, the web app
keeps your theme and text size in step with the rooms through Kura's
`/api/prefs` (read on launch, `PUT` on a change, as the rooms' machiya.js
does; any failure is silent and the device's own choice stays). Kura
accepts that `PUT` only from its own origin (`KURA_PUBLIC_URL`), so through
this host it is refused (403) unless Kura accepts this host's origin too;
reading still works. When Kura answers 401, the Notes list (and All) says
so with a Sign In link to Kura's own sign-in page, and the web app's
Settings → Notes → Machiya shows whether you're signed in, with Sign In
(Kura's `/signin`) or Sign Out (Kura's Settings: its sign-out is a form
on Kura's own origin).

`web/dev-server.py` does exactly this routing locally, for testing.

## Add Page and the share target (the web app)

With `SHIORI_SMALLWEB_URL` set at build time, the web app saves pages
through the small-web gateway: **Add Page** (the + beside Library in the
sidebar, the Add Page tab on a phone) takes an address and an optional
title and sends `POST /smallweb/api/save {url, title}`. Before sending,
it refuses anything but http, https, gemini and gopher, an address with a
user name or password, and any note: a Kura note's address, and any
address whose path (with a leading `//` folded and `%XX` decoded, so
`/%76/` too) starts with `/v/<vault>/`. The gateway answers 202 at once
and fetches in the background, so the app says "Saving… it'll be in your
pages shortly"; 400 (an address it won't take), 403 (not allowed: this
origin isn't in its `SMALLWEB_ORIGINS`), 429 (20 saves waiting) and no
answer each get a line of their own in the sheet.

The manifest's `share_target` (`GET /?url=&title=&text=`) puts the
installed app in the system's share menu where the browser supports it
(Chrome and Edge, Android and desktop; not Safari). A share opens Add Page
filled in: the shared `url`, else the first http(s) address in `text`,
and the `title`. Nothing is saved until Save is tapped. It works from a
cold start (the service worker serves `/` for any query), and the query
is dropped at once, so a reload never shares again. Without
`SHIORI_SMALLWEB_URL` the build has neither, and the manifest no
`share_target`.

## What it keeps where

- Settings: this browser's localStorage, changed in the page's gear.
  Nothing is shared between devices. Some start from the build, from the
  environment of `build-web.sh` and `build-pwa.sh` (all optional):
  - `SHIORI_NIWA_URL` (Kura's address; the name is older than Kura), `SHIORI_KONBINI_URL`: the notes' homes;
  - `SHIORI_OBSIDIAN_VAULT`: the vault notes open in, in Obsidian;
  - `SHIORI_ROOMS`: the Rooms menu, as `key=url,…`;
  - `SHIORI_SMALLWEB_URL`: the small-web gateway's address; set, the web
    app offers Add Page and its manifest a share target (above). The pages
    still reach the gateway at `/smallweb/` on their own host;
  - `SHIORI_SOURCE_URL`: where your build's source is, linked in About
    (AGPL-3.0 section 13: if you change Shiori and serve it to others, they
    get its source). A plain http(s) address; anything else shows nothing.
- Recent searches and the page's back/forward cache: this browser's
  localStorage.
- No extension means no DuckDuckGo hand-off: it's opened directly
  (`/?q=…`), or as the browser's search engine.
