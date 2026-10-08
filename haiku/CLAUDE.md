# Shiori for Haiku: traps and rules

Loaded when you work in `haiku/`. The project-wide rules, layout and build/test commands are in the root `CLAUDE.md`.

## Shiori for Haiku (`haiku/`, docs/haiku.md)

- C++17 on the Be API, HTTP through the Network Kit's netservices2 (private,
  linked statically). `haiku/core/` is portable (no Be headers) and tested
  anywhere by `make -f Makefile.test test`; `haiku/app/` is the Be UI, built
  only on Haiku.
- **The core's queries are search-core's twins**: regenerate
  `haiku/tests/vectors.inc` with `node haiku/tests/gen-vectors.mjs
  patches/shiori/search-core.js > haiku/tests/vectors.inc` after changing
  search-core (a test fails on drift). The version is project.yml's.
- Settings: `~/config/settings/Shiori/config.json`, 0600, Linux's keys.
  Hister's token only to Hister; the rooms get the sign-in's `mhs_` or a room token.
- **The Deskbar item runs inside Deskbar**, loaded from the app's binary: no
  networking there, every action a message to the app, and never a synchronous
  `BDeskbar` call from Deskbar's own thread.
- **One stalled TLS handshake jams a netservices2 session**: `Http.cpp` keeps
  the session on the heap, never deletes it, and retires it when a request
  passes its 20 s deadline. TLS failures are `ErrorCode() == B_NOT_ALLOWED`.
