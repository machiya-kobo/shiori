# Changelog

Every deploy of Shiori is a release: a version here, the same as
`MARKETING_VERSION` in project.yml, and a `vX.Y.Z` tag (minor for
features, patch for fixes). The
hosted pages serve this file as `/_shiori/CHANGELOG.md`.

## 1.0.0 (2026-10-08)

The first public release. Shiori is a search app for your own
[Hister](https://github.com/asciimoo/hister): the iPhone, iPad and Mac apps
with a Safari extension, a search page and a web app, and apps for Linux,
Haiku and Classic Macintosh. Everything since 0.18.0 is below; docs/features.md
lists what it does.

### Changed

- **"N New Items" has a refresh icon**, not an up arrow: a tap reloads the
  list and goes to the top (apps and web app).
- **"License"**, spelled the American way, in the About screens and the
  docs.
- **The README and CLAUDE.md are written for a first-time reader.**
  CLAUDE.md is short at the root, with each folder's traps beside its code.
  The README says plainly that the Safari extension is Hister's own,
  patched at build time, in the design Nick Burns's hister-safari uses
  (credited in the README, About and docs/extension.md).

### Fixed

- **The release files install on a clean system.** The Flatpak bundle names
  Flathub for its GNOME runtime, and the classic Mac `.hqx` carries
  BinHex's standard header (so decoders read it).

## 0.18.0 (2026-10-07)

### Added

- **Hover that shows what a click will do**, in the apps and on the web:
  a result's title (the link to the original) underlines under the
  pointer, with the link cursor on the Mac; a sidebar row fills with a
  light accent across the whole row; a pill lifts onto a tint of its own
  color, its text shifted to a shade that stays readable (4.5:1 in every
  theme).
- **`SHIORI_KURA_URL`** names Kura's address in builds. The older
  `SHIORI_NIWA_URL` still works.
- **`tools/screenshots --site`** takes Machiya's site images from the
  sample data.

### Changed

- **Sidebar headings are teal**, so Collections and Labels read apart
  from their rows. On the search page, a tab's heading (Your Pages, Your
  Code…) wears its tab's color.
- **A shorter README**, with every feature in docs/features.md. The
  Linux and Haiku pages keep what installing needs; developer notes moved
  to linux/README.md and haiku/README.md. Subscribe and the web's AI now
  point to Machiya's shiori-feed and shiori-ai.

### Fixed

- **The web app sent every search twice**, the web search included (each
  one counts against a paid search API). Now once, and the first result
  arrives sooner (about 1.95 s to 1.5 s with a slow web).
- **The search page asked Hister for its rules** on each of the first
  few keystrokes; now once.

### Security

- **Safari's extension keeps Hister's token in memory only**, never in
  the extension's storage, where content scripts could read it. Shiori's
  own pages ask the background for it.
- **mac-bridge 0.1.1** (Shiori for Classic Macintosh's bridge) checks the
  room token on the Kura port too.

## 0.17.4 (2026-10-07)

### Changed

- **A result's archive links look like buttons**, on the search page:
  Archive.org and Archive.is (and the build's front ends) sit at the end
  of the card's bottom row, apart from its tags, as small grey buttons
  with an icon, tinted on hover. They read as "cached" and "archive.is"
  in plain text beside the tags, and didn't look like something to click.

## 0.17.3 (2026-10-07)

### Fixed

- **The search page no longer goes blank while the web search is slow.**
  On All, with the web taking more than a second and a half, the page
  showed only the AI Answer, in the left column, and nothing else until
  the results came; then the answer jumped to the right. The shimmering
  placeholders now stay until the web is in (or gives up, when your pages
  and notes show on their own), and on a wide window the AI Answer and
  Related Searches sit in the right column from the start.

## 0.17.2 (2026-10-07)

### Fixed

- **Shiori for Linux works on a real desktop.** Tests had only run with
  no window manager, which hid all of this; on Cinnamon:
  - The window has a title bar again (Back, Reload, and the window's
    buttons), so it can be moved, resized and closed, and it starts at a
    size that fits the screen.
  - Previews load: the window sent the preview's frame to the system as
    if it were a link, so clicking a result showed nothing and an "Open
    With… No apps available" dialog popped up. Only real links leave the
    window now.
  - Signing in works inside the window: Hister's and Kura's sign-in pages
    opened in the browser, so the window never got the sign-in and kept
    sending you there.
  - Export saves a file: it asks where, then says it's saved.
  - Quick search opens in the middle of the screen, over a dimmed
    backdrop, instead of in a corner.
  - When Hister or Kura asks you to sign in, quick search and the menu's
    search say so and offer Sign In, instead of "Nothing matches".
  - The panel and window list match the window to Shiori's icon and
    launcher. The desktop file adds Sign In to Hister.
  - Re-run `linux/install-desktop.sh` after updating, for the menu's
    Sign In row.

## 0.17.1 (2026-10-07)

### Changed

- **The search field no longer selects its text** when you tap or click
  into it, in the apps, the web app and the search page: the caret goes
  where you tap. The `/` key, Haiku's Find and the classic Mac's Find
  leave the caret at the end.

## 0.17.0 (2026-10-07)

### Added

- **Notes From: Kura or Hister**, everywhere Shiori runs (the apps, the
  search page and Safari's, the web app, Linux, Haiku and the classic
  Mac). Hister holds your default vault's notes because Kura pushes them
  there, so notes and their previews no longer need Kura: until you
  choose, Shiori uses Kura when one is set up, else Hister. From Hister,
  only the default vault's notes show (never another vault's, shared or
  private), with no vault filter or notes feed.

## 0.16.0 (2026-10-07)

### Added

- **Shiori for Classic Macintosh talks to Hister directly**: Preferences →
  *Directly (HTTP)* reaches a Hister served over plain HTTP on your LAN,
  with or without Hister's access token (or a user's token). Kura is now
  optional. docs/classic.md covers serving Hister to any client without
  TLS, and what plain HTTP exposes. mac-bridge stays for an HTTPS-only
  Hister.

### Fixed

- **Show More against a real Hister** (classic): Hister's paging key holds
  escaped control characters; it now goes back exactly as it came.
- **Long requests** (classic): a long search with Show More no longer
  fails as "a bad address", and no longer overruns a buffer.
- **The classic app's stack** is 32 KB, so a search can't collide with the
  heap on a Mac Plus.

## 0.15.0 (2026-10-07)

### Added

- **Shiori for Classic Macintosh** (docs/classic.md): a native app for 68k
  Macs, from a Mac Plus on System 6 to a color Mac on System 7. Search your
  pages and notes, read a result in its own window with Find, and copy its
  link. On System 7 it has Balloon Help and color.
- **Shiori Search**, its desk accessory: a quick search from the Apple
  menu. On System 7 a result opens in Shiori; on System 6 its link is
  copied.
- **mac-bridge**: the small LAN proxy the classic Mac reaches Hister and
  Kura through, since MacTCP has no TLS. It holds Hister's token; the Mac
  holds only a room token.

## 0.14.4 (2026-10-07)

### Fixed

- **"N New Items" counts only what's new at the top**: it counted older
  results the Library's All hadn't placed yet, and imported ones (NewsBlur's
  stories) dated below the top, so tapping it showed nothing new.

## 0.14.3 (2026-10-06)

### Changed

- **Lists stay put when you change a setting**: rows redraw only for the
  settings they show.
- **Summarize for code** is offered only where Apple Intelligence can run.
- Under the hood: Summarize and delete-with-Undo are their own tested
  pieces, and one tested rule decides what an AI may see.

## 0.14.2 (2026-10-06)

### Fixed

- **Summaries and AI Answer can't be steered by the page**: text in a page
  or a search result that imitates Shiori's prompt markers is neutralized,
  as it already was for automatic labels.

## 0.14.1 (2026-10-06)

### Fixed

- **Smoother previews and deletes**: offline copies and summaries are saved
  in the background, not on the screen's own thread.
- **Summaries are cleaned up** like offline copies: on delete and sign-out,
  and never kept for code, files or private notes.
- **A plain http:// address says why it fails**: Shiori needs https://.
- **Saving a note's links** downloads faster and never takes more than 30
  seconds a page.
- **Clearer states**: the label picker and Save Links offer Try Again when
  something fails, and Filter says when nothing matches.
- **Accessibility**: zoom buttons in the image viewer, a Refresh action for
  VoiceOver, and Reduce Motion respected when pulling to refresh.
- Add Page can go back from Save to the address.

## 0.14.0 (2026-10-06)

### Changed

- **Filter opens a sheet** in the apps: Date, Site, Label, Visits,
  Language and Type in one place, with a search over sites and labels, and
  Hide for a site or label. No more submenus stacked over the menu.
- **Find a label** in the web app's Filter.

## 0.13.0 (2026-10-06)

### Added

- **Filter by label or collection**: Filter → Label in the apps (with Hide
  for a label), and after the dates in the web app's Filter.

### Changed

- **A standard-size search field** on iPhone, with more room between it, the
  pills and Sort · Group · Filter; the web app's too.

## 0.12.2 (2026-10-06)

### Changed

- **Preview is always in a result's menu** (long press, or right-click on
  the Mac), beside Open in Browser, whatever Tap Opens says.

## 0.12.1 (2026-10-06)

### Fixed

- **The hosted search page's start page shows its logo** again: it was
  left pointing at the extension's copy, which the hosted page doesn't
  have. Both web builds now check that every file a page names is in the
  build.

## 0.12.0 (2026-10-05)

### Added

- **Read offline in the apps**: the Library's All, Pages and Notes keep
  their newest page, and the last 50 pages and notes you previewed are
  kept on the device. Without a connection they show with "Offline · as
  of <time>", and they're replaced as soon as your server answers again.
  A private vault's note, a file or code is never kept, and signing out
  clears it all.
- The account settings' copy of the shared schema calls light and dark
  Mode.

## 0.11.1 (2026-10-05)

### Changed

- **Mode** is the light/dark choice (System, Light, Dark) under
  Appearance, as in every Machiya app; it was also called Appearance.

## 0.11.0 (2026-10-05)

### Changed

- **Settings in a clearer order**, the same in every Machiya app:
  Appearance first, then Search, Results, Safari, AI and Feeds & Export,
  then Account (the server, sign-ins, pages waiting to send) with About
  last. Seven pages instead of eight in the apps; the web app and the
  search page follow the same order and names.
- **Settings that depend on another stay hidden until it's on** (Small
  Web's gateway, AI Answer under Web Results…), and Search with Shiori no
  longer greys out settings the app itself uses.
- **Shorter explanations**: footers and tooltips are a sentence or two.
- The search page's gear has Fold Repeated Sites.

## 0.10.0 (2026-10-05)

### Added

- **Click Opens** (Settings → Search → Searching in the apps, Settings →
  Searching in the web app): what a click or tap on a result opens, the
  original (a page in the browser, a note in Obsidian) or Shiori's
  preview. Automatic, the default, keeps what 0.9.0 did: the preview
  beside a preview pane, the original elsewhere. The other one leads the
  result's right-click or long-press menu and its first swipe (in the web
  app, the › at the row's end). Kept on each device.

### Changed

- **A result's title always opens the original**, whatever a click on the
  rest of it does; label, vault and place chips still open their own.

## 0.9.0 (2026-10-05)

### Changed

- **A tap anywhere on a result opens it**, not only on its title: a page
  in the browser, a note in Obsidian (Kura without it), a file from
  Hister's copy. In the apps on iPhone, the web app on a phone and the
  search page. Shiori's own preview is a swipe or the menu in the apps,
  and the › at a row's end in the web app. With a preview pane (Mac, iPad,
  a wide window) a click still previews, and a double-click or Return
  opens. Chips (labels, Obsidian, Kura, Konbini…) open what they always
  did.

## 0.8.2 (2026-10-05)

### Fixed

- **Pull to refresh on iPhone and iPad shows and feels like one**: a mark
  under the bars grows as you pull, a tap of haptics at the point where
  letting go reloads, and a spinner while it does. Before, the reload
  happened but nothing showed it, and the haptic came late.

## 0.8.1 (2026-10-05)

### Changed

- **No pull to refresh on Web and Small Web results** (the apps and the
  installed web app): the same words find the same results, and each web
  search counts. Every other list still refreshes on a pull.

## 0.8.0 (2026-10-05)

### Added

- **New items show up while you look**: an open list (the Library, a
  label or collection, a search's Pages or Notes) checks every minute,
  while the app is in front, for anything added since it loaded, and
  says so with a "↑ N New Items" banner instead of redrawing under you.
  Tap it to load them and go to the top. In the iPhone, iPad and Mac
  apps and the web app; only your Hister and Kura are asked, never the
  web.

## 0.7.8 (2026-10-05)

### Changed

- **Shiori for Haiku shows the newest when the field is empty**: at
  launch and when you clear the search, All lists your recent notes and
  newest pages, and each pill its own newest, as the other Shiori apps
  do.
- **Haiku's Show More** says it's loading, and a page that fails to load
  puts the row back to try again. A first search asks Kura and Hister at
  once, so results show sooner.

## 0.7.7 (2026-10-05)

### Changed

- Settings → Server's **Access Token is now Safari Extension Token**,
  since that's what it's for: the app signs in with your login, and
  Safari's extension, which can't use the login, saves pages with the
  token. Paste it on each device with the extension (and again after a
  new token is made in Hister).

## 0.7.6 (2026-10-05)

### Fixed

- Shiori for Linux: `shiori send` stopped at a 401/403 now says to sign
  in (or set the token), as `shiori save` does, rather than that Hister
  is out of reach.

## 0.7.5 (2026-10-05)

### Fixed

- Settings → Server's connection check failed on a signed-in device
  without a token (or with one Hister no longer takes, after a token
  rotation): it now checks with the sign-in, as the rest of the app does.
- Shiori for Linux kept no page Hister refused with 401/403 (not signed
  in, or a rotated token): it now keeps it until you sign in, as the
  other apps do.

## 0.7.4 (2026-10-05)

### Changed

- **Shiori Search's time range moved** out of the header (beside the
  house and the gear) into a quiet row under the pills, where your
  lists' sort (Best match / Newest) and Notes' vault now sit too. A
  phone shows the full "Anytime" there instead of a clock icon.

## 0.7.3 (2026-10-05)

### Changed

- **30 results a page** for your pages, notes, code and files on Shiori
  Search (it was 20), as the apps and the web app load them; and All
  now mixes up to 30 of your pages and 30 notes among the web results
  everywhere (it was 20). Web, News, Videos, Images and Small Web are
  unchanged.

## 0.7.2 (2026-10-05)

### Fixed

- The counts on the Pages, Notes and Code pills (found by All's search)
  stay when you move to one of those tabs, on Shiori Search and in the
  web app; they used to disappear as soon as you left All.

## 0.7.1 (2026-10-05)

### Changed

- **Shiori Search's page cards are tidier**: a saved page's label is now
  the first chip in the card's bottom row, beside where it opens, and the
  date line holds only the date. The small "preview" link is gone (the
  card itself opens the preview pane, and the hister chip opens Hister's
  page), and so is "summarize" on the cards; the AI Answer stays, as do
  Summarize in the apps and the web app.

## 0.7.0 (2026-10-05)

### Added

- **Shiori for Haiku**: a native app on the Be API, as a `.hpkg` on this
  release (`pkgman install ./shiori-0.7.0-1-x86_64.hpkg`), or built with
  `cd haiku && make && ./package.sh` (docs/haiku.md).
  - Search on Return or a pill: All (Kura's top notes, then your pages),
    Pages, Notes (every vault, or one) and Code, with Show More for the
    next page.
  - A note's preview from Kura, with its links opening in the browser.
  - Save URL to Hister, with an offline outbox by the iOS app's rules.
  - Sign in to Hister (while it has users); Hister's token goes only to
    Hister, and Kura gets the sign-in's id or a room token.
  - The Deskbar item and a quick search (`Shiori --quick`, ⌘K), keys
    (⌘L, ⌘1–⌘4, ↓ and Escape), and Shiori's mark as its icon.
  - Errors that say what to do: a failed secure connection names the
    likely cause, and a server that stops answering is given up on after
    20 seconds without holding up the rest.

## 0.6.4 (2026-10-05)

### Changed

- **Pull to refresh moves the list**, as in the rooms' apps (vaultkit
  0.22.1): in the installed web app, pulling down at the top of the list
  brings the list down after your finger (harder to pull past the point
  where it reloads), with the reload mark growing in the gap under the
  bars. Let go early and it springs back; let go past it and it rests a
  little down, spinning, while the app reloads.

## 0.6.3 (2026-10-05)

### Fixed

- A note's "hister" link went to Hister's copy, which Hister may not have
  (a 404). Notes no longer offer Hister at all (the apps, the web app and
  the search page): they open in Kura and Obsidian, and every note's
  preview comes from Kura, the default vault's too.

## 0.6.2 (2026-10-05)

### Security

- The apps no longer send Hister's token to Kura and Konbini when they
  aren't signed in to Hister: a room that asks who you are now says to
  sign in (Settings → Server). Hister's token goes to Hister alone,
  everywhere in Shiori.

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
