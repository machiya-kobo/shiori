# Firefox spike

Phase 0 of [docs/firefox-plan.md](../../docs/firefox-plan.md): today's
Safari bundle, shims unchanged, in headless Firefox against a fake Hister.
It answers "what breaks before we change anything" and stays as a
regression check until phase 6 replaces it.

```bash
FIREFOX=/path/to/firefox tools/firefox-spike/run.sh
```

Needs node, python3, rsync, a Firefox and geckodriver (on `PATH`, or
`GECKODRIVER=`). It restages `ShioriExtension/Resources` with the fake
server's address (the build and install scripts restage it). Ports 8775
(fake Hister) and 8776 (test pages), or `HISTER_PORT`/`PAGES_PORT`. Logs and
`results.json` go to `WORK` (a temporary folder by default).

| File | What it is |
|---|---|
| `run.sh` | Builds, converts, serves `pages/`, runs `run.mjs` |
| `make-firefox.py` | The Safari bundle's manifest made loadable in Firefox, nothing more |
| `fake-hister.py` | Skip rules (`skipme`), stats, profile, search; logs requests as JSON lines. Never a real Hister |
| `run.mjs` | Three sessions: capture, private browsing, containers |
| `container-probe/` | A tiny add-on: what `contextualIdentities` gives without `cookies` |

## What it checks

- A visited page reaches `api/add` with Shiori's metadata, HTML and no text.
- A skip rule holds.
- Offline (the fake stopped), a capture is queued and drains when Hister is
  back.
- The idle event page is unloaded, and the queue survives it.
- PDFs go to `api/add_pdf` with Shiori's metadata.
- The settings page, `search.html` and the popup load.
- Nothing runs in private browsing.
- Container names and a tab's container are readable without `cookies`.

## Traps

- **Install unpacked.** In some containers, a zipped temporary add-on's
  content script never loads: "IPDL protocol Error: Received an invalid file
  descriptor", then "Unable to load script: …/content.js". Plain upstream
  fails the same way there. `run.mjs` installs the folder through
  geckodriver's `path`.
- **Offline means stopped.** A fake that drops the socket mid-request makes
  Firefox retry idempotent GETs dozens of times on its own.
- An older Firefox than the floor (140) still runs: `run.sh` lowers the
  bundle's floor to match, with a warning.
