# Shiori for Classic Macintosh: traps and rules

Loaded when you work in `classic/`. The project-wide rules, layout and build/test commands are in the root `CLAUDE.md`.

## Shiori for Classic Macintosh (`classic/`, docs/classic.md)

- C on Retro68 for the 68000, System 6.0.8 to 7.x, MacTCP. `classic/core/` is
  portable C89 (`node --test scripts/classic.test.mjs` runs it, the bridge's
  tests and the vectors' drift check). **Its queries are search-core's twins**:
  regenerate `classic/tests/vectors.h` with `node haiku/tests/gen-vectors.mjs
  --c` after changing search-core.
- **Two ways to Hister** (MacTCP has no TLS; one credential a request):
  **directly**, to a Hister served over plain HTTP (Hister's token to Hister's
  origin only, the room token to Kura's only), or **through mac-bridge**
  (`classic/bridge/bridge.py`, stdlib, GET only, exact paths: the room token
  `mht_` to both bridge origins, checked by hister-login on both ports before
  any upstream; Hister's token never leaves the bridge, and its log never has
  a query, a header or a body). docs/classic.md says what plain HTTP exposes;
  keep that warning wherever direct mode is offered.
- Hister's `page_key` holds escaped control characters and a NUL: keep it raw
  (`ShioriPage.next`) and send it back as it came. A note's vault comes from
  its address; private vaults are never offered, and `SHIO/read` refuses any
  vault but the default.
- The 68000's stack is small (the app sets 32 KB): big buffers live in structs
  or statics, never in a request path's frames. **The desk accessory must stay
  under 32 KB** (`build.sh` fails past it): nothing on its path may use
  `sprintf`, `sscanf`, `strtol` or the library's `strstr`, and it calls
  `RETRO68_RELOCATE()` at every entry.
- Retro68's File Manager glue (`HOpen`, `FSWrite`…) leaves parameter-block
  fields as garbage: zero a block and call `PB…Sync`. Multiversal lacks some
  names (`Scrap.h`, `TEToScrap`…): use the low-memory accessors or local
  constants. Windows are `NewCWindow` where Color QuickDraw is
  (`ThemeNewWindow`).
- **Release files come from `classic/scripts/package.sh`** with
  `SHIORI_RELEASE=1` (neutral defaults): a normal build bakes in
  `classic/local.env`'s test addresses and token.
- Emulator testing (Snow for System 6, Basilisk II for System 7) is in
  `classic/docs/TESTING.md`, against the fake house only. Never hard-kill
  Basilisk, never point its driver off the Mac's screen (it hangs X), and never
  write Snow's disk while Snow runs.
