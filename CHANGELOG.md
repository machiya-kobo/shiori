# Changelog

Every deploy of Shiori is a release: a version here, the same as
`MARKETING_VERSION` in project.yml, and a `vX.Y.Z` tag (minor for
features, patch for fixes). The
hosted pages serve this file as `/_shiori/CHANGELOG.md`.

## 0.6.1 (2026-10-05)

### Security

- **Hister's token stays with Hister.** Safari's extension now presents
  the app's own sign-in to Kura and Konbini (passed over from the app),
  and Shiori for Linux a room token (`"roomToken": "mht_…"`, made on the
  sign-in helper's sessions page); neither sends Hister's token to a room
  any more.

### Changed

- The hosted pages' **Sign Out** (Settings → Account) signs out here and
  in every room at once (it posts to the sign-in helper on the page's own
  host); **Sessions…** ends another device's.

## 0.6.0 (2026-10-05)

### Added

- **Settings that follow you.** Signed in to Hister, the Shared settings
  (Theme, Appearance, Text Size, Pills) and the results' options follow
  you to every device and every Machiya app: in the apps, the web app and
  the hosted search page, through your account (the Hister sign-in
  helper's `/machiya/api/prefs`). A change goes at once; another device's
  arrives when you come back to the app or page. Addresses, sign-ins, AI
  and a device's own text size stay on the device. Settings → General
  (the web app's Settings, the search page's gear) starts with **Shared**,
  saying where you stand.
- **Use This Device's Size** (This Device): this device's own text size
  over the shared one, which your other devices keep.

### Changed

- The web app no longer keeps its theme and text size in Kura; the
  account holds them for every room.

## 0.5.8 (2026-10-05)

### Added

- **Pull to refresh** in the installed web app, as in the rooms' apps: at
  the top of the list, pull down and let go once the mark turns blue.

### Fixed

- Menus close on the way out and on the way back: the installed web app
  on iOS came back from another page with the Rooms menu still open.
- A search with an unclosed quote (`raspberry "pi`) found nothing: the
  quote is closed before Shiori's own terms go on.
- A private vault's folder and tag pages (any `/v/<vault>/…` address, not
  only its notes) are kept from Hister and AI like its notes.
- The dev server keeps the Hister sign-in helper's cookie (`machiya_sso`)
  from Hister and SearXNG, as it did the rooms' (`machiya_session`).

## 0.5.7 (2026-10-05)

### Security

- **A stored address is a link only when it's the web.** A page in Hister
  whose address was `javascript:…` became a link that ran script on the
  search page (and could on the web app). Every link the pages draw now
  goes through one check (`S.linkHref`/`S.safeHref`, HisterKit's
  `SafeHref` in the apps): http(s), and only the schemes Shiori builds
  itself (Obsidian, Gemini, Gopher).
- **Hister's token never follows a redirect.** Safari's extension sent
  `X-Access-Token` along a redirect to another host; every request
  carrying it now refuses redirects.
- **Only Shiori's own pages change its settings in Safari.** A web page's
  content script could ask the extension to change them, and with the app
  out of reach any value was kept (addresses decide where the sign-ins
  go). Now only the extension's pages may, and without the app only what
  the app's own whitelist allows is kept, never an address.

### Fixed

- On the search page, Images has its own colour (green): it was the same
  yellow as Web, side by side, in every theme.
- On the search page's Pages, Notes, Files and Code, the vault and the
  sort sit in a row above the list instead of the header, which crowded a
  phone's.
- Linux's GJS self-test expected an old query; the Node tests run it
  where gjs is installed.

## 0.5.6 (2026-10-05)

### Fixed

- On the search page, a tap on a note opens its preview, as a page's does:
  in the preview pane on a wide screen, and on a phone Kura's reader page
  (it opened Obsidian). The small "preview" link, which went to Hister's
  copy, is gone; Obsidian is a chip below.

## 0.5.5 (2026-10-05)

### Fixed

- On the search page, a web result's cached and archive.is links (and its
  front ends) sit in the card's bottom row, left-aligned, as your pages'
  do: on a phone they stood alone between the address and the text.
- `linux/install-desktop.sh` installs only the launcher where there's no
  Cinnamon (it failed there), and says that the menu search and hotkey
  change your running desktop session (`--remove` undoes them).
- The search page's build no longer writes a stray `n` into its HTML on
  the BSDs and the Mac (their `sed`).
- `tools/screenshots` waits for a visible result; the README's screenshots
  are new.

### Changed

- **Linux: the Cinnamon menu provider is `shiori@machiya-kobo.github.io`.**
  Re-run `linux/install-desktop.sh`: it removes the old provider and
  switches the new one on.
- The Flatpak builds into `~/.cache/shiori-flatpak` (it was `/tmp`).
- Docs: the Quickstart's BSD steps run as root and point at a Hister
  elsewhere; back up `~/.config/shiori/config.json` before the Linux steps;
  what Linux needs without the Flatpak; the whole command list; the Code
  pill and Sign In with Tailscale in the feature list; the AI skill's page
  queries leave code out (`@pages`), and it never queries code.

## 0.5.4 (2026-10-05)

### Fixed

- **Save This Note's Links asks Hister exactly whether it has a page**
  (`HEAD /api/document`, the address and its trailing-slash twin) before
  saving, in the apps and on Linux. The search it used couldn't take an
  address with `( ) |`, and a lookup that failed read as "not held", so a
  page Hister had could be saved again and its metadata replaced. Now a
  lookup that fails stops the save and says why.

### Changed

- The docs say where Hister's token goes: to Hister, and to the
  configured Kura and Konbini, which read it when they use Hister's
  sign-in (a signed-in app sends them its id instead).

## 0.5.3 (2026-10-05)

### Added

- **Open Original** for a page on one of your privacy front ends (a
  Reddit thread saved from Redlib, a video from Invidious…): the menu
  (apps, web app) and the search page's cards offer it on its own site,
  and their Archive.org and Archive.is links are of the original, which
  the archives can reach.

## 0.5.2 (2026-10-05)

### Fixed

- The Code pill's filters (kind, host, Open Only, Private) sit on one
  line in the apps, styled as Sort · Group · Filter and scrolling sideways
  when they don't fit: on a phone every label wrapped onto two lines.

## 0.5.1 (2026-10-05)

### Added

- The web app's page menu (⋯) and the search page's cards (web results
  and your pages) offer the same as the apps: Archive.org, Archive.is and
  the build's privacy front ends. The web builds read `SHIORI_FRONTENDS`
  from their environment, and Safari's results page from local.yml.
- **LibMedium** for Medium articles, beside Scribe.

## 0.5.0 (2026-10-05)

### Added

- **Open on Archive.org and Open on Archive.is** in a web page's long-press
  and right-click menu (the apps; not for notes, files or code), and
  **Open in Redlib, Invidious…** for a Reddit or YouTube page when the
  build names your front ends (`SHIORI_FRONTENDS` in local.yml; also
  Piped, Nitter, Scribe, rimgo, libremdb and BreezeWiki). Links only.
- **Small Web results are tinted teal**, as their pill, in every Result
  Style (the web's own results stay plain).

### Changed

- **Result Style is back to Tint** on every device, once: a style chosen
  earlier is replaced, and one chosen from now on is kept.
- The rooms' light themes darken a few text colours a shade, so every
  text colour reads at 4.5:1 on the files, code and Small Web cards too.

## 0.4.0 (2026-10-05)

### Removed

- **Shiori for Firefox.** On Firefox (and Chrome), upstream Hister's own
  extension does the automatic capturing, which was the Firefox
  extension's purpose. Gone: its build target, settings page, sidebar,
  `sh` keyword, container rules, settings files and the signed release
  workflow. Copies already installed stay at 0.3.5 and get no more
  updates: remove Shiori from Firefox's add-ons and install
  [Hister's extension](https://addons.mozilla.org/firefox/addon/hister/).
  Safari's extension is unchanged.

## 0.3.5 (2026-10-04)

### Changed

- **Code rows say which forge they're on** (Forgejo or GitHub, from the
  document's `code_host`), and the Code pill's filters gain **All Hosts /
  Forgejo / GitHub**. Most rows are Forgejo's, and without the badge they
  read as GitHub's.

## 0.3.4 (2026-10-04)

### Changed

- **Nothing searches while you type**: a search runs on Return, the
  field's magnifier, a recent search, Did you mean or a pill, in the apps
  and the web app, the "Search in" fields of collections and labels too.
  The field keeps the keyboard while you type (a search that ran at a
  pause took it away); clearing the field still resets at once.

## 0.3.3 (2026-10-04)

### Added

- **Apply Apple Intelligence's Labels** (Settings → AI → Automatic
  Labels, off by default): when Anthropic doesn't settle a page, or isn't
  used, Apple Intelligence's first choice is applied instead of waiting in
  Suggested Labels, and the waiting suggestions are applied the same way.
  Each can be undone; a label undone twice is only suggested again.

### Fixed

- On the Mac, clearing the search field now goes back to the Library's
  newest (0.3.2's fix reached only the iPad).
- On the Mac, a search that finds nothing fills the column: the pills, Did
  you mean and "No Results" stayed at the top instead of floating
  mid-column. The same for the web's and Small Web's empty answers and a
  failed list.

## 0.3.2 (2026-10-04)

### Added

- The apps' Sign in to Hister starts with **Sign In with Tailscale** when
  Hister offers an OIDC sign-in (`oauthProviders` has "oidc"): the
  sign-in sheet goes straight to it, one tap with no form, once the
  sign-in helper takes the provider; until then it opens the sign-in page
  a tap from it.

### Fixed

- On the Mac and iPad, clearing the search field (its X, deleting the
  text, Escape) goes back to the Library's newest, as on the iPhone and
  the web app; the cleared search's results, Did you mean and AI Answer
  stayed until another search.

## 0.3.1 (2026-10-04)

### Fixed

- The search page gives the web 10 seconds, not 4: on a phone's mobile
  data through the VPN, ordinary searches ran past 4 and showed "Web
  results didn't answer". That line now has Try Again beside Search
  DuckDuckGo.

## 0.3.0 (2026-10-04)

### Added

- **Code**: a pill for your repos in Hister (code-import's repo
  cards, READMEs and docs, issues, pull requests and releases), after
  Files, on every Shiori. Searched as you type, with a count on the pill;
  filters for the kind, Open Only and Private; each row shows what it is,
  the repo, its state and a lock when private, and opens at the forge. A
  repo's note in Kura is linked when there is one.

### Changed

- Every other Hister search leaves code out (` -metadata.source:code`),
  as it does notes and files: code is never in All, Pages or any list but
  its own.
- Code is summarized on the device only (Apple Intelligence), never by a
  local server or a cloud engine; the hosted pages never summarize it.
  Code is never labelled, deleted or folded by site, "code" is a reserved
  collection name, and an alias for code isn't listed as a collection.

## 0.2.1 (2026-10-04)

### Changed

- The apps' Sign in to Hister starts with **Sign In with Saved Password**:
  Hister's own sign-in page in a Safari sheet, where Passwords or
  Bitwarden offer the saved login for the site (the app's own fields can't
  be matched to the site without Associated Domains, which needs a paid
  developer team). The name and password fields follow it.

## 0.2.0 (2026-10-04)

Everything since 0.1.0.

### Added

- **Shiori for Firefox**: a second extension target sharing Safari's core,
  with a settings page, the toolbar badge counting the waiting queue, the
  right-click menu, the sidebar, the `sh` address-bar keyword, container
  rules, and settings to a file and back. Signed releases come from a
  version tag.
- **Signing in to Hister**, for a Hister with users: the apps sign in
  (password, or the browser), Linux with `shiori sign-in`, and the hosted
  pages hand off to the sign-in and show who's signed in. Every Hister
  caller can send Hister's access token (Settings → Server → Access Token;
  Firefox's settings page; Linux's config). Nothing changes while Hister
  has no users.
- Kura and Konbini in Hister sign-in mode get the signed-in device's id,
  or Hister's access token when it isn't signed in.
- **Signing in to Machiya**: pairing with a code or a pasted token, sent
  only to the configured Kura and Konbini.
- **Files**: the folders Hister watches, on their own pill.
- **Pills**: their order and which show, a setting on every Shiori.
- **The Machiya rooms' ten themes**, shared with the rooms.
- The web app's **Add Page** and share target, through the small-web
  gateway.
- Counts on the Pages and Notes pills; a Web pill for the web alone.
- The hosted builds publish `/_shiori/status.json` (version, build, the
  Hister release) and this changelog.

### Changed

- **All mixes in a page of your pages and notes**, spread evenly through
  the web results, instead of sections above them.
- **Web searches are frugal**: the web is asked only for a search run on
  purpose (Return, a recent search, Did you mean, the Web pill), never
  while typing; respellings come from the autocompleter.
- Hister searches send the last word as `(word|word*)`, which finds every
  page the whole word does.
- Private vaults follow Kura's own switch; their notes never reach Hister,
  an AI engine, a cache or an export.
- The Rooms menu reads as the rooms' own (Machiya · home); search fields
  have the rooms' clear and submit buttons.
- iPhone and the web app on a phone: no title row, Settings is a tab.

### Fixed

- The saved-page marks no longer fail (414) for a long list of web results.
- A capture Hister refuses for want of a credential is kept until the
  token works, instead of lost.
- The apps' Sign in to Hister appears when Hister has users.
