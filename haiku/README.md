# Shiori for Haiku: developer notes

Using it: [docs/haiku.md](../docs/haiku.md). These notes are for working on it.

## How the code is laid out

- `haiku/core/` is portable C++17 with no Be headers: JSON, the search
  queries (search-core.js's twins, checked against vectors generated from
  it: `haiku/tests/gen-vectors.mjs`), reply parsing, the credential rules,
  the sign-in, the outbox and the note's text. Its tests run on Linux and
  macOS too (`node --test scripts/haiku.test.mjs`, and CI).
- `haiku/app/` is the Be UI. HTTP goes through the Network Kit's
  netservices2 (private API, linked statically) in one file, `Http.cpp`.
  Every request runs on its own thread and answers the window with a
  message; a generation counter drops stale answers.
- The Deskbar item runs inside Deskbar, loaded from the app's binary, so it
  does no networking: each action is a message to the app.
- The version is the one in `project.yml`; the icon is Shiori's mark as an
  HVIF vector (`haiku/tools/icon.py` writes `Icon.rdef`).

## Testing

`haiku/tests/ui-run.sh`, on a Haiku test machine, drives the app with
`hey` against `haiku/fake-services.py` (a fake Hister, sign-in helper and
Kura that log every credential they get and shout when one goes where it
mustn't), and takes screenshots. It replaces the settings: never run it
where Shiori is in use, and never test a save against a real Hister.

Launching by signature (the Deskbar item does, with `be_roster->Launch`)
picks the build tree's binary over the installed package's when both
exist: test the installed copy with no build tree beside it, or with
`objects.*` removed.
