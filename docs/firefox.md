# Shiori for Firefox

The same extension as Safari's (upstream Hister's, patched at build time),
built for Firefox on desktop and Android. It sends the pages you visit to
your own Hister server, queues them while the server is out of reach, and
searches your pages beside the web. Firefox has no Shiori app behind it,
so the extension's own settings page sets everything. How it was built,
and why, is in [firefox-plan.md](firefox-plan.md).

It needs **Firefox 153** or later, the current ESR, and works in
LibreWolf, Zen and Floorp. One file serves every OS and CPU Firefox runs
on: Windows, macOS, Linux, the BSDs, Haiku (x86_64) and Android.

## Install

Every release on this repository's
[Releases](https://github.com/machiya-kobo/shiori/releases) page carries
`shiori-firefox-<version>.xpi`, signed by Mozilla (unlisted: it isn't on
addons.mozilla.org).

- **Firefox, LibreWolf, Zen, Floorp** (any OS): open the `.xpi` link in the
  browser, or drag the downloaded file onto a window, then confirm. Haiku's
  Firefox and its forks come from HaikuDepot.
- **Firefox for Android**: download the `.xpi`, then install it from the
  file. Recent versions hide that behind a setting. Not yet checked by
  hand, so the steps here will follow the first Android check.

Firefox then keeps it up to date from this repository (below).

## First run

The settings page opens by itself on install. It's also under Add-ons and
themes → Shiori → Preferences, and behind the gear in the toolbar menu.

1. **Hister Server**: your server's address, then Save. The status should
   read "Connected · N pages". Saving fetches the server's skip rules
   straight away, so pages visited offline can wait in the queue.
2. **Site Access**: it should read "Allowed". If not, Allow on All
   Websites. Without it, nothing is sent.
   Firefox lets you take it away under Add-ons and themes → Shiori →
   Permissions; this page shows it.
3. **Neighbours** (optional): SearXNG for web results, Kura for notes,
   Konbini, the small-web gateway, and your Obsidian vault's name.

Settings stay on this device; nothing syncs them.

## Using it

- **Saving pages** is automatic; Hister's rules decide what it keeps.
  Pages visited while it's out of reach wait (Waiting to Send on the
  settings page) and go out once it answers; after 14 days they drop.
- **The address bar**: type `sh`, a space and your words. Your pages are
  suggested as you type, the ones you opened before for that search first.
  Enter on one opens it; Enter on the words opens Shiori Search, with your
  pages and notes, then the web.
- **Shiori as a search engine**: Shiori never takes over another engine's
  searches (Safari's version takes DuckDuckGo's, having no other way in).
  If you host the search page (web/README.md), open it, then the address
  bar's search button offers "Add Shiori Search" (the page advertises
  itself through OpenSearch). Then Settings → Search makes it the default
  or gives it a keyword. Without a hosted page, `sh` is the way in.
- **Shortcuts** (Firefox's Add-ons and themes → ⚙ → Manage Extension
  Shortcuts changes them):

  | | Windows, Linux, BSD, Haiku | macOS |
  |---|---|---|
  | Save this page | Alt+Shift+S | Control+Shift+S |
  | Never save this page | Alt+Shift+P | Control+Shift+P |
  | Never save this site | Alt+Shift+D | Control+Shift+D |
  | Open Shiori Search | Alt+Shift+F | Control+Shift+F |

- **The toolbar button** shows how many pages are waiting to send.
- **The right-click menu**:
  - Search Shiori for the selected words;
  - Save Page to Hister, Never Save This Page, Never Save This Site;
  - Save Link to Hister.

  A link is saved as Save This Note's Links saves one: never a file or a
  page Hister has, skip rules holding, `gemini://` and `gopher://` through
  the small-web gateway. The toolbar button shows the answer on that tab
  for a few seconds.
- **The sidebar** (View → Sidebar → Shiori, or a key you set for "Show or
  hide Shiori in the sidebar"):
  - search your pages as you type;
  - with the field empty, it shows what you've saved from the site in the
    tab beside it.
- **Containers**: choose containers on the settings page (Banking, Work).
  Pages in them are never saved on their own; saving one by hand still
  works. Installing Shiori turns Firefox's containers on if they were off
  (it needs them to read their names; Firefox has them on by default).
- **Another device**: the settings page's Save to a File and Open a File
  carry the server and settings over (never your searches or pages). A
  file is applied only after you've seen what it changes.
- **Private windows**: Shiori isn't loaded in them at all.

## What it talks to

- **Your Hister server**, and the neighbours you set, to save and search.
- **Visited sites**: their favicons and PDFs (upstream's behaviour).
- **A link you save** with Save Link to Hister: that page is downloaded
  (without cookies), or, for `gemini://` and `gopher://`, handed to your
  small-web gateway.
- **GitHub**: Firefox itself checks this repository's
  `releases/latest/download/updates.json` (the add-on's `update_url`)
  for a newer version, on its own schedule. The extension's code never
  contacts GitHub.

Nothing else: no analytics, no AI (that is the Apple apps', and only when
switched on).

## Building

```bash
git submodule update --init
scripts/build-extension.sh --target firefox
```

It needs Node, npm, Python 3 and rsync. It builds upstream's extension,
patches it into `build/firefox/`, checks it (`scripts/check-extension.py`),
runs Mozilla's linter (`web-ext`; 0 errors or it stops) and packs
`build/shiori-firefox-<version>.zip`. That package is unsigned.

- **Trying a build**: Firefox → `about:debugging` → This Firefox → Load
  Temporary Add-on → `build/firefox/manifest.json`. It's gone on restart.
- **`local.yml`** values (`SHIORI_SERVER_URL` and the rest) become the
  build's defaults, just as for Safari. A published build sets none but
  `SHIORI_SOURCE_URL`. Without a server address, the page starts at
  upstream's default, `http://127.0.0.1:4433/`.
- **The BSDs and Haiku** run the extension but can't build it yet:
  upstream's bundler (Vite 8's Rolldown) ships native parts only for some
  systems. Build on Linux, macOS or Windows.

**Tests:**

- `node --test scripts/*.test.mjs`.
- In a real Firefox: `FIREFOX=/path/to/firefox tools/firefox-spike/run.sh`
  ([its README](../tools/firefox-spike/README.md)). It builds, installs and
  drives the add-on against a fake Hister: never a real one for writes.

## Releasing

Releases come from `.github/workflows/firefox-release.yml`.

**Once:** on addons.mozilla.org, sign in with the account that will own
the add-on. Then Developer Hub → Manage API Keys. Add the two values as
this repository's Actions secrets: `AMO_JWT_ISSUER` and `AMO_JWT_SECRET`.
The first signing registers `shiori@machiya-kobo.github.io` to that
account; every later one must use the same account.

**Each release:**

1. Set `MARKETING_VERSION` in `project.yml` (the apps and the extension
   share it), commit, and go through the hand checks below.
2. Tag it `v<version>` (`v0.2.0`) and push the tag.
3. The workflow:
   1. checks the tag matches;
   2. runs the tests;
   3. builds with the Source link (AGPL section 13);
   4. packs the source of this repository and the Hister submodule for
      Mozilla's review (the built code is bundled);
   5. signs as unlisted;
   6. writes `updates.json` (version, download link, the signed file's
      SHA-256, the floor);
   7. attaches both files to the tag's GitHub Release, creating it if
      needed.

Run by hand (Actions → Firefox release → Run workflow), it only tests and
builds, and keeps the unsigned package as the run's artifact.

**Keep `updates.json` on the latest release.** Firefox asks
`releases/latest/download/updates.json`. A newer release without it, such
as an app-only one, would break updates: give it the file too, or mark it
a pre-release.

The workflow's actions are pinned to major versions (`actions/checkout@v4`
and so on). Pin them to commit hashes if you'd rather not follow them.

## Hand checks before a release

Automation covers the rest (above). These need a person:

- [ ] Install the signed `.xpi` on Firefox ESR 153 and on the current
      release: the settings page opens, a visited page is saved.
- [ ] Allow on All Websites, after taking site access away in Firefox's
      add-on Permissions: Firefox asks, and the page then reads Allowed.
- [ ] Each OS you ship for: Windows, macOS, Linux, one BSD, Haiku x86_64.
      The shortcuts work and clash with nothing.
- [ ] LibreWolf, Zen and Floorp: install, save a page, `sh` in the address
      bar.
- [ ] The right-click menu: each item, on a page, a link and a selection.
- [ ] The sidebar from View → Sidebar; a search; a click.
- [ ] Firefox for Android: how the file installs; capture; the settings
      page at phone width; whether `sh` is offered; Save to a File and
      Open a File.
- [ ] An update: with the previous release installed, Firefox picks up the
      new one (about:addons → Check for Updates).

## When something's wrong

| You see | Try |
|---|---|
| Nothing reaches Hister | Settings page: Site Access must read Allowed and the status Connected. Hister's own rules may skip the site. |
| "Needs site access" | Allow on All Websites, on the same page. |
| "Can't reach it" | The address (with its port), your network or VPN. Pages wait in the queue meanwhile. |
| Firefox says the add-on is corrupt or unverified | Install the signed `.xpi` from Releases. The `.zip` from a build is unsigned and loads only as a temporary add-on. |
| The keyword shows nothing | The server must answer, and Hister must have pages for those words. Enter still opens Shiori Search. |
