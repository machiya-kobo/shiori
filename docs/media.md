# Media: your libraries and what you played

A **Media** pill beside Code, for "what was that song, that film": your
**Jellyfin** and **Plex** libraries, and what you played from **Koito**
(music, ListenBrainz-compatible) and **Movary** (a film diary). Each
service is optional. With none set up, there's no Media pill.

## What it shows

- **One card per item.** A film, show, episode, album, track, artist, music
  video, collection or playlist shows once, even if both libraries hold it
  (matched by TMDB, IMDb, TVDB or MusicBrainz id, else by title, artist and
  year).
- **When you played it.** "Never Played", "Played Mar 6, 2014" or "Played 3× ·
  Last Mar 6, 2014". Films come from Movary and music from Koito first, since
  they hold every source (streaming included). The library's own count is used
  where they have nothing. TV comes from Plex ("Played 8 of 8 Episodes").
  Things you played that aren't in a library follow, marked "Not in Library".
- **Your rating** as five stars with halves: Movary's for films, Plex's for
  music and TV. The others' ratings (IMDb, TMDB, Rotten Tomatoes) follow,
  quieter.
- **Filters:** Kind (Films, TV, Music, Other), Never Played, and Rating (4★+,
  3★+, Any Rating, Unrated).
- **Before a search:** Now Playing, Recently Listened and Watched, your top
  artists, albums and tracks for a week, month, year or all time (Sort → Top
  Lists), your watchlist and Recently Added. Group → Day or Month instead puts
  date headings over everything, by when you played it.
- **On All:** no section of its own: your top media go among the web results with your pages and notes, taking turns with them, each saying "Your media"; the total is on the Media pill. Media never reaches the AI Answer (the hosted pages send it only the words; the apps, only the web's results).
- **A card opens in its service:** films and TV in Plex first, then Movary,
  then Jellyfin; music in Koito first. Its other places are links: the other
  services, IMDb, TMDB, Letterboxd and MusicBrainz. Those sites are only ever opened as links, never fetched.

Searched on purpose only (Return, the pill), never while typing.

## Private

Media is treated like a work note. Nothing of it goes to Hister (Remember What
You Open never records it), any AI engine (on-device included), a cache on the
device, an export or a feed. The search page never keeps it in its Back copy,
and nothing is previewed. Art is held in memory for the session only.

## Setting it up

Each service needs its address and a token of its own for Shiori. Shiori
only ever sends GETs to the read endpoints below, but none of these services
offers a read-only token, so give it the least you can:

| Service | Token | Sent as |
|---|---|---|
| Jellyfin | the access token of a user of its own, not an admin, that can see the libraries (Jellyfin's API keys are admin keys) | `Authorization: MediaBrowser Token=…` |
| Plex | a device token for Shiori (revocable under Authorized Devices) | `X-Plex-Token` header |
| Koito | an API key | `Authorization: Token …` |
| Movary | a personal API token | `Authorization: Bearer …` |

- **The apps:** Settings → Search → Media. Tokens go in this device's Keychain,
  never synced, never to Safari's extension. Safari's own results page has no
  Media.
- **The hosted pages** (shiori-web): `SHIORI_<NAME>_URL` and
  `SHIORI_<NAME>_TOKEN` (or `_TOKEN_FILE`) for each, and
  `SHIORI_<NAME>_PUBLIC_URL` for links ([web/README.md](../web/README.md)).
  The host adds the token on its own request; the browser never holds one.
  A `_TOKEN_FILE` must be readable by the container's user: with secrets
  that are 0600 and another uid's, run the container as that uid (`user:`).
  It refuses to start, and says so, when it can't read one.
  Movary's public address must be the one Movary writes into its poster links
  (its `APPLICATION_URL`).

## What Shiori asks for

All GETs, nothing else:

- **Jellyfin:** `Users/Me`, `Users/<id>/Items?searchTerm=`, `Users/<id>/Items/Latest`,
  `Items/<id>/Images/Primary`.
- **Plex:** `identity`, `hubs/search?includeGuids=1`, `library/recentlyAdded`,
  `library/metadata/<id>/thumb/<n>`. Shiori asks for JSON; Plex answers XML
  otherwise.
- **Koito:** `apis/web/v1/search`, `listens`, `now-playing`,
  `top/{artists,albums,tracks}`, `{track,album,artist}/<id>`, and `image/…`.
  `listens?period=` is required: without it Koito sends none.
- **Movary:** `api/authentication/token` (whose diary it is),
  `api/users/<user>/{played,history,watchlist}/movies`, `storage/images/…`.
  Never `api/movies/search`, which searches TMDB and would send the words out.

Art loads only from these services and `image.tmdb.org`, and only with
Settings → Results → Images in Previews on. The logic is search-core's media
section and HisterKit's `Media.swift` (twins, on `scripts/media-cases.json`).
`MediaClient` asks the services for the apps.
