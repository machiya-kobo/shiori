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

Each device has its own token. Hister and SearXNG have no login (the
network is their gate) and never get it.

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
| Hosted search page and web app | Kura's own `/signin` | No token: the browser's `machiya_session` cookie (with `MACHIYA_COOKIE_DOMAIN` covering Shiori's host), passed on only to `/kura/` and `/konbini/` (web/README.md). A 401 shows a Sign In link. |
| Linux | `"machiyaToken"` in `~/.config/shiori/config.json`; `shiori pair <code>` prints it | That file, `chmod 600` (docs/linux.md). |

The extension's fetches keep `credentials: 'omit'`; the token is a header.
The offline capture queue (Hister's `api/add`) strips `authorization`,
`cookie` and `x-access-token` before anything is stored, and its replays
carry none of them.

## Signing out and revoking

**Sign Out** deletes the token from the device (Linux: delete the line).
That doesn't make it invalid: revoke it on the server with the identity
CLI, `identity device revoke <device id>` for a paired device (all of a
person's devices: `identity epoch bump`), or `identity token revoke <id>`
for a stored token. A revoked token gets 401, and Shiori says to sign in
again.
