# Firefox spike

The Firefox build (`scripts/build-extension.sh --target firefox`) in
headless Firefox against a fake Hister. It began as phase 0 of
[docs/firefox-plan.md](../../docs/firefox-plan.md), on the Safari bundle,
and stays as the in-browser check, growing with each phase.

```bash
FIREFOX=/path/to/firefox tools/firefox-spike/run.sh
```

Needs node, python3, rsync, a Firefox and geckodriver (on `PATH`, or
`GECKODRIVER=`). It rebuilds `build/firefox` with the fake server's
address. Ports 8775
(fake Hister) and 8776 (test pages), or `HISTER_PORT`/`PAGES_PORT`. Logs and
`results.json` go to `WORK` (a temporary folder by default).

| File | What it is |
|---|---|
| `run.sh` | Builds the Firefox target, serves `pages/`, runs `run.mjs` |
| `fake-hister.py` | Skip rules (`skipme`), stats, profile, search; logs requests as JSON lines. Never a real Hister |
| `run.mjs` | Nine sessions: the settings page, capture, the address bar, DuckDuckGo, the sidebar, container rules, private browsing, the container probe |
| `container-probe/` | A tiny add-on: what `contextualIdentities` gives without `cookies` |

## What it checks

- The settings page opens on first install; a bad address is refused;
  saving the server fetches its rules at once; a switch and a neighbour
  are kept; without site access it says so and offers Allow.
- No native messaging; a settings change is kept on the device (AI keys
  refused); the shortcuts Firefox assigned.
- `sh lantern` in Firefox's address bar suggests the fake's pages (the one
  opened before first); Enter on one opens it and tells Hister; Enter on
  the text opens Shiori Search.
- A DuckDuckGo search opens Shiori Search; Back stays; a `!bang` and a
  switched-off take-over leave DuckDuckGo alone (on the real
  duckduckgo.com; a note instead when it's out of reach).
- Settings to a file and back: the file holds no searches; opening one
  shows what it changes; Apply keeps only what the page takes.
- The toolbar badge counts the queue and clears.
- The right-click menu's five items are registered; Save Link to Hister
  saves a page (marked `via: context-menu`) and refuses a file.
- The sidebar searches as you type (marks only in snippets, one column);
  the real sidebar follows the tab's site.
- Container rules: what installing does to Firefox's containers (a note);
  the page with containers off and on; a Banking page not captured while a
  normal tab is.
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
  geckodriver's `path`. Seen on Firefox 136 and ESR 140, not on ESR 153.
- **Firefox 140 and later** refuse the chrome context (and 153 refuses
  opening `moz-extension://` pages) unless geckodriver runs with
  `--allow-system-access`; `run.mjs` adds it from 140.
- **Revoking site access takes two origins**: `*://*/*` and the content
  script's `<all_urls>`, which Firefox counts as a host permission too.
- **The settings page opens in the empty start tab** on install, so WebDriver
  sees no new window; `run.mjs` reads the tabs from Firefox.
- `SHOTS=<folder>` saves screenshots of the settings page (both themes,
  desktop and phone width).
- **A proxy that re-signs TLS** (some sandboxes) makes Firefox refuse
  duckduckgo.com's certificate; the DuckDuckGo session alone accepts it.
- **The address bar is driven from Firefox's chrome context**
  (`gURLBar.search`, then a row and `handleCommand`); WebDriver can't type
  there.
- **Firefox's own prompts** (optional permissions, Allow on All Websites)
  can't be answered from WebDriver. And a grant made from the chrome side
  (`ExtensionPermissions.add`) skips the manifest's checks, so it can pass
  where a real user would be refused. Read `ext.optionalPermissions`.
- **A hidden tab isn't captured** (upstream skips `document.hidden`): select
  the tab before navigating it.
- **The right-click menu** can't be opened from WebDriver: its items are
  checked with `menus.update`, and Save Link through
  `getBackgroundPage().ShioriMenus`.
- **Offline means stopped.** A fake that drops the socket mid-request makes
  Firefox retry idempotent GETs dozens of times on its own.
- An older Firefox than the floor (153) still runs: `run.sh` lowers the
  bundle's floor to match, with a warning.
