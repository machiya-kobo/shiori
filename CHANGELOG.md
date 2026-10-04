# Changelog

Every deploy of Shiori is a release: a version here, the same as
`MARKETING_VERSION` in project.yml, and a `vX.Y.Z` tag (minor for
features, patch for fixes). The tag also releases Shiori for Firefox. The
hosted pages serve this file as `/_shiori/CHANGELOG.md`.

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
  Hister offers its tailnet sign-in (`oauthProviders` has "oidc"): the
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
  data through the tailnet, ordinary searches ran past 4 and showed "Web
  results didn't answer". That line now has Try Again beside Search
  DuckDuckGo.

## 0.3.0 (2026-10-04)

### Added

- **Code**: a pill for the owner's repos in Hister (code-import's repo
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
