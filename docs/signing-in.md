# Signing in

Two sign-ins can apply, each only when the server side has it on:

- **Hister's users** (Hister v0.20.0+ with `app.user_handling: true`, and
  Machiya's sign-in helper, hister-login): one sign-in for Hister and every
  room. Below.
- **Machiya's identity file**, for rooms that run with it: [Signing in to
  Machiya](#signing-in-to-machiya), further down.

With neither, Shiori sends nothing more than before, and none of this shows.

## Hister's users

Hister keeps **one access token per user** (making a new one breaks every
holder at once), and sessions for browsers and apps. The sign-in helper
sits on Hister's own host under `/machiya/` (its sign-in page, sessions
page and app flow) and turns a Hister session into an opaque id,
`mhs_…`, that the rooms accept. Shiori uses each where it fits:

| Shiori | How it signs in | What it sends |
|---|---|---|
| iPhone, iPad, Mac | Settings → Server → **Sign in to Hister**: a name and password (Hister's `POST /api/login`, then the helper's `POST /machiya/api/app-session` trades the session for an id), or **Sign In with the Browser** (the helper's `/machiya/signin?app=1&return=shiori://signed-in` in a private web session, back with `#sid=…&hister=…`). Shown only while the helper's `/machiya/healthz` says Hister has users, or while signed in. | `Cookie: hister=<session>` to Hister (HisterKit keeps cookies off and sets it itself), `Authorization: Bearer mhs_…` to the rooms. Kept in the Keychain, service `Hister` (`HisterKeychain`): this device only, shared with the share extension. |
| Safari extension | Settings → Server → **Access Token** in the app (paste your Hister user's token, once per device) | `X-Access-Token`, handed over by native messaging (`hister`); a browser extension can't set `Cookie`. |
| Firefox | Shiori's settings page → **Access Token** | `X-Access-Token`, from `storage.local` (`histerToken`): never synced, never in a settings file; the page only learns whether one is set. |
| Hosted search page and web app | The helper's sign-in page: a 401 or 403 from Hister's routes sends the page to `<hister>/machiya/signin?return=<the page>` (at most once in 30 s), and back | Nothing of their own: the browser's `machiya_sso` cookie goes to this host, whose nginx asks the helper and adds Hister's session on its own hop (web/README.md). Signing out: Settings → Signing In → Hister's sessions page. |
| Linux | `shiori sign-in` (a small window, name and password) | The session and id in `$XDG_DATA_HOME/shiori/sign-in.json` (0600, tied to the server's origin); `histerToken` in config.json for the token. `shiori sign-out`, `shiori status`. |

The apps also take the token (Settings → Server → Access Token), and send
it beside a sign-in; either is enough for Hister.

**Where they go.** The session and the token only to the configured Hister
server, by origin; the `mhs_` id only to the rooms, under the same host
rule as Machiya's token (below; rooms in Hister mode refuse the identity
file's tokens, so a signed-in app sends the id in their place). Nothing
follows a redirect to another origin with any of them, none is ever in a
URL or a log, and the offline capture queue stores none (its replays read
the token afresh).

**Signed out.** Hister answers 403 (and nginx 401) without a valid
credential. The apps say "Hister wants you to sign in" and never retry it;
pages waiting in the outbox stay until the device signs in again. The
hosted pages go to the sign-in. A 500 from the hosted pages' sign-in check
means sign-in is unavailable, said in a line, never an error page.

**Signing out.** In the apps Sign Out posts the id to the helper's
`/machiya/signout`, which ends the Hister session and every id on it, then
forgets both. A browser signs out on the helper's `/machiya/sessions` page
(it lists every browser and app, with Sign Out for one or all). The token
is separate: make a new one in Hister (`hister update-user <you>
--regen-token`) and every holder needs the new one.

**Testing.** Never against a live Hister: a sign-in writes a session.
HisterKit's `HisterUsersLiveTests` run against a throwaway Hister with
users (`HISTER_USERS_URL`, `HISTER_USERS_NAME`, `HISTER_USERS_PASSWORD`,
and optionally `HISTER_USERS_TOKEN`); the stubs cover the helper.

# Signing in to Machiya

When the Machiya rooms run with Machiya's identity file
(`MACHIYA_IDENTITY_FILE`, Machiya's `docs/plans/identity.md`), Kura,
Konbini and Niwa ask who is calling: a request without a proof gets **401**,
one whose principal has no grant **403**. Without the file they behave as
before, and none of this is needed.

Shiori proves who you are with a **token**, sent as
`Authorization: Bearer <token>`:

- `mch_…`, a stored token, made on the server with
  `identity token mint <you> --label "iPhone"` and pasted into Shiori;
- `mcd_…`, a device token, from **pairing**: `identity pair <you> --label
  "iPhone"` shows a one-time code (eight letters and digits, ten minutes),
  and Shiori posts it to Kura's `POST /api/pair`. Type it as shown;
  spaces, dashes and case don't matter. Five wrong tries per address in
  ten minutes and the room says to wait.

Each device has its own token. Hister and SearXNG never get it (Hister
has its own sign-in, above).

## Where it goes

Only to **exactly the configured Kura and Konbini** (and Niwa, where one is
configured; Shiori fetches nothing from Niwa today), compared by origin:
scheme, host and port. An address with a user or password in it, a
lookalike host, another port or `http://` where `https://` is configured
gets nothing. A room on Hister's or SearXNG's origin gets nothing either:
give it its own. A request carrying the token never follows a redirect to
another origin (the browsers' fetch refuses any redirect; the apps drop the
header; Linux follows none). The rule is one function with twins:
search-core's `machiyaRooms` / `mayCarryMachiyaToken` and HisterKit's
`Machiya.rooms` / `mayCarryToken`, with the same cases in
`scripts/machiya.test.mjs` and `MachiyaTests`.

## Where it lives

| Shiori | Signing in | The token |
|---|---|---|
| iPhone, iPad, Mac | Settings → Notes → Sign in to Machiya: a code or a token | The Keychain, service `Machiya` (`MachiyaKeychain`); on iOS this device only, never in a backup, shared with the Safari extension through the App Group; on the Mac the login keychain. Never UserDefaults. |
| Safari extension | In the app | Asked from the app over native messaging (`machiya`), kept in the background's memory a minute, never stored. |
| Firefox | Shiori's settings page → Sign in to Machiya | `storage.local` under its own key (`machiyaSignIn`): never synced, never in a settings file, never logged. |
| Hosted search page and web app | Kura's own `/signin` (the web app: Settings → Notes → Machiya) | No token: the browser's `machiya_session` cookie (with `MACHIYA_COOKIE_DOMAIN` covering Shiori's host), passed on only to `/kura/` and `/konbini/` (web/README.md). A 401 shows a Sign In link. |
| Linux | `"machiyaToken"` in `~/.config/shiori/config.json`; `shiori pair <code>` prints it | That file, `chmod 600` (docs/linux.md). |

The extension's fetches keep `credentials: 'omit'`; the token is a header.
The offline capture queue (Hister's `api/add`) strips `authorization`,
`cookie` and `x-access-token` before anything is stored, and its replays
carry none of them.

## Signing out and revoking

**Sign Out** deletes the token from the device (Linux: delete the line).
That doesn't make it invalid: revoke it on the server with the identity
CLI, `identity device revoke <name> <device id>` for a paired device (all of a
person's devices: `identity epoch bump <name>`), or `identity token revoke <id>`
for a stored token. A revoked token gets 401, and Shiori says to sign in
again.
