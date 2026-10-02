# Contributing to Shiori

Thanks for helping. Shiori is a client for [Hister](https://github.com/asciimoo/hister):
native apps for iPhone, iPad and Mac with a Safari extension, a search page
and web app, and a small Linux app. It's one of the
[Machiya](https://github.com/machiya-kobo/machiya) services ("rooms"; README
says what they are). [CLAUDE.md](CLAUDE.md) is the detailed
guide to how it works and the traps already found; read the section for the
part you're changing.

## Building

- **Apple apps:** see README → Build. You need `local.yml` (from
  `local.yml.example`) with your own `SHIORI_BUNDLE_PREFIX` and team.
- **Web pages:** `scripts/build-web.sh` and `scripts/build-pwa.sh`;
  `web/dev-server.py` serves them locally with the same routing as a real
  host (web/README.md).
- **Linux:** see docs/linux.md; `linux/flatpak/build.sh` builds the Flatpak.

## Tests

Run what covers your change before sending it:

- `node --test scripts/`: the shared search logic, the extension's shims,
  the web pages' helpers and the Linux modules.
- `swift test` in `Packages/HisterKit` (the client) and `Packages/ShioriAI`
  (the AI engines).
- `xcodebuild test -scheme ShioriTests -destination platform=macOS` after
  changing `Shared/`.
- On Linux: `gjs -m linux/gjs/selftest.js`, `linux/headless.sh`, and
  `linux/save-test.sh` for anything that saves.

Logic shared by the apps and the web pages has twins (Swift in HisterKit,
JavaScript in `patches/shiori/search-core.js`) with the same test cases;
change both.

**Never test a write against a real Hister.** Use the stubs in the test
suites or `linux/fake-hister.py`. Read-only checks against your own server
are fine: `HISTER_LIVE_URL` and `KURA_LIVE_URL` turn them on.

## Rules

- Never modify `vendor/hister/`: Safari behaviour lives in `patches/`,
  applied to the built extension. To upgrade, move the submodule to an
  upstream tag.
- Never edit the generated `Shiori.xcodeproj/` or
  `ShioriExtension/Resources/`: change `project.yml` or `patches/`.
- Keep personal details out of the repo: server addresses, network names,
  device names, team IDs. They belong in the gitignored `local.yml` and
  `local.env`.
- No new network endpoints without discussion: Shiori talks to the
  servers the user configures (and AI providers only when the user turns AI
  on). No analytics.
- A note from a private vault (any but the default, unless Kura marks it
  shared) never goes to Hister, to an AI engine, a cache, an export or a
  feed. When Kura can't say, every other vault is private.
- Match the surrounding code: its naming, comment density and idiom.

## Sending a change

Open a pull request with what changed and why, and which tests you ran. Keep
one change per pull request. By contributing, you agree that your work is
licensed under the GNU AGPL-3.0-or-later, as the rest of Shiori.
