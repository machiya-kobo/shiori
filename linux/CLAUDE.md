# Shiori for Linux: traps and rules

Loaded when you work in `linux/`. The project-wide rules, layout and build/test commands are in the root `CLAUDE.md`.

## Shiori for Linux (docs/linux.md)

- GJS on GTK 4 and libadwaita, a Flatpak (`io.github.machiya_kobo.Shiori`) on
  the GNOME 49 runtime. `linux/src/` is pure modules tested under Node; keep
  `linux/gjs/` thin.
- **Only real links leave the window** (`linux/src/window.js`): the web app,
  its frames (`about:`, `data:`, `blob:`) and the sign-in pages stay in the
  web view, whose cookies they need.
- **Use `app.runAsync()`, never `app.run()`** (a blocking `run()` never runs
  callbacks' promise jobs). Commands with no window (`save`, `send`, `status`,
  `save-links`, `provider-search`, `--help`) run before the application
  starts: GTK needs a display.
- `GApplicationCommandLine`'s `print`/`printerr` aren't callable from GJS: use
  `print_literal`/`printerr_literal`. **Read `message.status_code`, never
  `get_status()`**: the enum lacks 429 and throws.
- The Flatpak mounts the host's `~/.config/shiori` over its own config dir, so
  a test config under `~/.var/app/…` is hidden: test saves only with
  `linux/save-test.sh`. Over SSH, use the desktop's session bus or portals
  time out; never `pkill -f` a pattern that's in your own command.
