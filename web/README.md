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
the host name). Both builds also write `_shiori/status.json`,
`{"version", "build", "built", "hister"}` (Shiori's version, the commit,
the time in UTC, the Hister release it's built against; nothing else), for
the house's status page. The optional last address is a status
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
| `/kura/api/search`, `/kura/api/recent`, `/kura/api/note`, `/kura/api/vaults`, `/kura/api/prefs`, `/kura/feed.xml` | Kura, `/kura` removed: your notes, and (signed in) your theme, appearance and text size. **Only these**: anything else under `/kura/` should be a 404, never Kura's reader (below) |
| `/smallweb/*` | the small-web gateway, `/smallweb` removed (`api/search`, `api/save`): Gemini and Gopher, and the web app's Add Page (any http(s), gemini or gopher page; its `SMALLWEB_ORIGINS` must include this host's origin) |
| anything else | the Hister host as it is: Hister's API (`/search`, `/api/*`, `/preview`), and the optional `/shiori/feed` and `/shiori/ai/*` (companion services that aren't published yet, so for now they need your own server: the feed's contract is in [docs/features.md](../docs/features.md), the AI's in [docs/ai.md](../docs/ai.md); the pages ask for `/shiori/ai/*` only when built with `SHIORI_AI=1`) |

Pass requests through **unchanged**. Do not add `Origin: hister://`: Hister
lets a same-origin browser write (`Sec-Fetch-Site: same-origin`) and
refuses a cross-site one (403), and that check is what keeps other sites
from, say, deleting pages through this host. Keep the host private (your
network or VPN), like Hister itself.

**Signing in (Hister's users).** When Hister has users (Hister's
`app.user_handling`, with Machiya's sign-in helper, hister-login, on
Hister's own host), this host signs every Hister call in for the browser:
the browser holds only the helper's opaque `machiya_sso` cookie, and nginx
asks the helper (`auth_request`) for Hister's session on its own hop:

```nginx
location = /_machiya_auth {
    internal;
    proxy_pass http://hister-login:8081/v1/nginx;   # the helper's internal port
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header X-Machiya-Session $cookie_machiya_sso;
}
location / {                                        # Hister's routes, /shiori/ai/ and /shiori/ too
    auth_request /_machiya_auth;
    auth_request_set $hister_cookie $upstream_http_x_hister_cookie;
    proxy_set_header Cookie $hister_cookie;         # replaces the browser's whole Cookie header
    proxy_hide_header Set-Cookie;                   # Hister re-sends its session on every answer
    # … the existing proxy_pass and websocket lines
}
```

- `/v1/nginx` answers 200 with `X-Hister-Cookie: hister=<session>`, or 401.
  The session travels only nginx → Hister, never to the browser: hence the
  `Cookie` replacement **and** `proxy_hide_header Set-Cookie`.
- `/kura/` and `/konbini/` get `Cookie: machiya_sso=$cookie_machiya_sso`
  only; the rooms check it themselves.
- The cookie's name is the helper's default. If you rename it
  (`MACHIYA_SSO_COOKIE`), nginx's variable follows the name:
  `$cookie_<name>` in both places above.
- The pages: a 401 (nginx) or 403 (Hister) from Hister's routes sends the
  page to `<hister>/machiya/signin?return=<the page>` (the `hister` entry
  of `SHIORI_ROOMS` at build time; without it they just fail as before);
  a 500 from the check is "sign-in is unavailable", in a line. Sign-out is
  the helper's sessions page (`<hister>/machiya/sessions`), linked from
  the web app's Settings once a sign-in has been needed: the helper takes
  sign-out posts only from its own origin.
- Without users nothing changes: Hister answers as before and the pages
  never go to the sign-in.

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
  (Hister, SearXNG, the gateway): only the rooms read it. The same for
  the Hister sign-in helper's `machiya_sso` (above): on Hister's routes
  nginx replaces the whole `Cookie` header, and it never goes to SearXNG
  or the gateway. Two cookies, two sign-ins: `machiya_session` is the
  rooms' own (the identity file), `machiya_sso` the helper's (Hister's
  users).

The pages only read the rooms, with one exception: signed in, the web app
keeps your theme (one of the rooms' ten), appearance and text size in step with the rooms through Kura's
`/api/prefs` (read on launch, `PUT` on a change, as the rooms' machiya.js
does; any failure is silent and the device's own choice stays). Kura
accepts that `PUT` only from its own origin (`KURA_PUBLIC_URL`), so through
this host it is refused (403) unless Kura accepts this host's origin too;
reading still works. When Kura answers 401, the Notes list (and All) says
so with a Sign In link to Kura's own sign-in page, and the web app's
Settings → Account → Machiya shows whether you're signed in, with Sign In
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

- Themes: Settings → Theme offers the Machiya rooms' ten (Tokyo Night,
  Solarized, Nord, Dracula, Catppuccin, Gruvbox, Rosé Pine, Kanagawa,
  Everforest, Ayu) and Mode (System, Light, Dark), shared with the
  rooms like the text size (cookie `machiya_palette`, the account's
  `palette`). `web/app/palettes.css` is made by `node scripts/palettes.mjs`
  from `web/app/palettes.json`, the rooms' table from machiya's
  `vaultkit/palettes.py` (the script's header says how to refresh it); the
  search page loads the same file.

- Settings: this browser's localStorage, changed in the page's gear (the
  web app's Settings). Signed in, the Shared ones (theme, appearance, text
  size, pills) and Shiori's own options follow the person through the
  account (`/machiya/api/prefs`, the Hister sign-in helper on this host:
  route `/machiya/` to it; machiya docs/contracts/prefs.md). Addresses,
  AI and this browser's own text size (the `machiya_textSizeDevice`
  cookie) stay here. Some start from the build, from the
  environment of `build-web.sh` and `build-pwa.sh` (all optional):
  - `SHIORI_KURA_URL` (Kura's address; `SHIORI_NIWA_URL`, its older name, still works), `SHIORI_KONBINI_URL`: the notes' homes;
  - `SHIORI_OBSIDIAN_VAULT`: the vault notes open in, in Obsidian;
  - `SHIORI_ROOMS`: the Rooms menu, as `key=url,…` (shiori, konbini, niwa,
    kura, hister, searxng, and machiya for the house's front door:
    "Machiya · home", last before Settings);
  - `SHIORI_SMALLWEB_URL`: the small-web gateway's address; set, the web
    app offers Add Page and its manifest a share target (above). The pages
    still reach the gateway at `/smallweb/` on their own host;
  - `SHIORI_SOURCE_URL`: where your build's source is, linked in About
    (AGPL-3.0 section 13: if you change Shiori and serve it to others, they
    get its source). A plain http(s) address; anything else shows nothing.
  - `SHIORI_AI=1`: the host has the AI companion service (`/shiori/ai/*`,
    docs/ai.md), so the pages ask its status and offer Summarize and AI
    Answer when it says it's on. Unset (or anything but `1`), they never
    request `/shiori/ai/` and show no AI.
- Recent searches and the page's back/forward cache: this browser's
  localStorage.
- No extension means no DuckDuckGo hand-off: it's opened directly
  (`/?q=…`), or as the browser's search engine.
