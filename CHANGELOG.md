# Changelog

Every deploy of Shiori is a release: a version here, the same as
`MARKETING_VERSION` in project.yml, and a `vX.Y.Z` tag (minor for
features, patch for fixes). The
hosted pages serve this file as `/_shiori/CHANGELOG.md`.

## 1.22.6 (2026-10-22)

- Search page, over a background: AI Answer and Info line up with the first
  result, not the edge of the glass above it, and the placeholders shown
  while results load no longer move when the background starts.

## 1.22.5 (2026-10-22)

- The hosted pages' image builds on the current Python base (1.22.4's pin
  had gone stale). No change to Shiori itself.

## 1.22.4 (2026-10-22)

- Search page, over a background: the placeholder cards shown while results
  load sit on the same glass as the results, level with the Info placeholder
  beside them (they sat a little lower).

## 1.22.3 (2026-10-21)

- Search page, on a wide screen: the footer sits on the bottom edge of the
  page. The room under it was for Home and Settings, which float at the
  right, clear of its centred lines there; a phone keeps it.

## 1.22.2 (2026-10-21)

- The web image's nginx base re-pinned to the current stable-alpine
  digest (1.22.1's image couldn't be built on the old pin). It carries
  1.22.1's changes, which were never deployed.

## 1.22.1 (2026-10-21)

- Search page, on a wide screen: laid out as on a phone. No Shiori name
  row: the search field is the header's top, over the results' column, and
  Home and Settings float in the lower-right corner (Rain and Watch are in
  Settings → Background there).
- Search page: Next page is centred under the results, with no strip of
  glass behind it, as Show More is.
- Search page: the right column (AI Answer, Related Searches, Info)
  scrolls with the page; it had a scrollbar of its own.

## 1.22.0 (2026-10-20)

- iPhone, iPad, Mac and the web app: Images, Videos and News pills after
  Web, as on Shiori Search. Images is a grid of pictures; a tap shows one
  large with its site, size and format, Open Image and Visit Page, and the
  previous and next (buttons, a swipe, the arrow keys). Videos show their
  length on the thumbnail; News its date. Each searches the web only when
  chosen, as Web does.
- Their order and filters (Largest, size, shape and format for Images;
  Newest, Shortest, Longest and length for Videos; Newest and source for
  News) sit beside Sort, in one Filter menu, and narrow or reorder what
  came back in place: never another web search. In the web app the time
  range is there too.
- The choices' logic is shared by the search page, the web app and the
  apps (one set of test cases runs in Swift and JavaScript).

## 1.21.6 (2026-10-20)

- iPhone, iPad and Mac: a list's next page is asked once more after a
  moment when the first try fails, so a dropped request on a phone's
  connection no longer stops the Library with "More didn't load". Why a
  page failed is logged (the error's kind only).
- iPhone, iPad and Mac: the All pill is as wide as Web, as on the web pages.

## 1.21.5 (2026-10-20)

- Search page: over a background, the footer's glass fits its lines, with
  open space under it for Home and Settings (it ran to the bottom of the
  screen).

## 1.21.4 (2026-10-20)

- Search page: Show More is centred under the last result, inside the
  results' panel, rather than at the end of a long strip of glass.

## 1.21.3 (2026-10-20)

- Search page: Pages, Notes, Files and Code show every result: Show More
  adds the next 30 in place until the end. The Next page link never
  showed when a duplicate was dropped from a page (it wanted a full 30),
  so a search of 218 pages stopped at the first 29.
- Search page: Open in Hister sits at the end of the sort row on Pages,
  Files and Code (it was under the last result), level with the results'
  right edge.
- Search page, on a phone: Home and Settings are back where they were,
  keeping their accent look.

## 1.21.2 (2026-10-20)

- Search page and web app: the All pill is as wide as Web, the next
  shortest, so it's easier to tap.
- Search page, on a phone: Home and Settings stand out (an accent ring,
  tinted buttons, bright glyphs, a deeper shadow) and sit lower, into the
  strip Safari keeps under its toolbar.

## 1.21.1 (2026-10-20)

- Search page: a result's description is three lines at most, as other
  search engines show (and the web app already did). An engine's snippet
  can be a whole paragraph: Wikipedia's took half a phone's screen.
- Search page: a search word is bold only where a word starts ("can" no
  longer half-bolds "American").
- Search page: room under the time range before the header's line.
- Search page, on a phone: Home and Settings sit lower, on the bottom of
  the page, with snug padding.
- Search page: no empty strip above the placeholder cards while the Small
  Web, Media, Code or your lists load over a background.

## 1.21.0 (2026-10-20)

- iPhone, iPad and Mac: your pages are in Spotlight. The newest 300 are
  in the device's search (title, site and snippet), refreshed every few
  hours from Hister (no web search), and a tap opens the page.
- Siri and Shortcuts find any of your pages: "Open … in Shiori", or the
  Open Page action, which searches Hister.
- Never notes, files or code. Settings → Search → Spotlight turns it off
  and empties it; signing out of Hister, or another account, empties it
  too, and a deleted page leaves it.

## 1.20.0 (2026-10-20)

- Search page, on a phone and in windows under 1100px: no name row. The
  search field is the top of the page, and Home and Settings sit in the
  floating corner, low in the lower right, where a background's Rain and
  Watch were (the rain is in Settings → Background).
- Search page, on a phone: the search field looks like iOS's own, a
  filled capsule with the magnifier leading (it still searches) and a round
  clear button.
- Search page: AI Answer, Info and Related Searches are the same size, side
  by side in a column (Related Searches had sat inside the web's panel, and
  over a background AI Answer took the panel's padding). Over a background
  the results' glass reaches past the cards, so they're as wide as those
  rows.
- Search page, on a phone: the time range's backing is no longer cut off
  at the left edge.

## 1.19.1 (2026-10-20)

- Web app: Web and All have the time range (Anytime, Past Day…) in the
  row under the pills, as the search page's web tabs do, where 1.19.0 left
  an empty gap. A change searches the web again, on purpose.
- Web app: a web search's reply is kept for 5 minutes. Opening a web
  search could ask SearXNG twice, and every move between All and Web asked
  again; each counts against the search quota.

## 1.19.0 (2026-10-20)

- Search page: Images, Videos and News have their own row of choices
  under the pills, as Kagi's. Images: order (Largest), size, shape and
  format. Videos: order (Newest, Shortest, Longest), length and source.
  News: order (Newest) and source. Each sorts or narrows the results
  already fetched, in place, without another web search, and is kept in
  the address. A choice shows only when the results differ in it.
- Search page: Code's filters (kind, host, Open Only, Private) sit in that
  row beside Best Match, and Media's sort, group and filters too. Media's
  row no longer disappears, so every tab's header is the same height and
  its results start in the same place.
- Search page: the row's menus start at its edge, level with the pills and
  the cards, in every browser (Safari had set their text 10px in), with one
  chevron each, and Best Match and the time ranges are in Title Case.
  Lines of text among the results ("Did you mean", a tab with nothing
  found, More ›) line up with the text in the cards.
- Search page: over a background, the footer sits on the window's bottom
  edge and holds the corner's buttons; on a short tab it floated above them.
- Search page: the image viewer on a phone. The close button sits above
  the picture, so a large one no longer covers it; close, previous and next
  are 44 points; a tap that misses them no longer zooms the page; and
  closing it no longer flashes the picture over the header.
- Search page: the browser's bar above the page (Safari's, behind a
  phone's status bar) takes the page's colour, so it meets the header
  without a lighter band.
- Web app: every list keeps the Sort · Group · Filter row, empty or not,
  so switching between All, Pages, Web and the rest no longer moves the
  results. Code's filters are one menu in that row. The web's results,
  headings and notes line up with the text in the cards.

## 1.18.0 (2026-10-20)

- Search page: tabs switch in place. Pick another tab, the next page or a
  sort, and the results on screen stay until the new ones are ready, then
  swap at once: no blank page, no flash. They dim if the new tab takes a
  moment, and after 3 seconds its placeholder cards show instead. Back and
  Forward switch the same way, from the copy already fetched.
- Search page and web app: the search field has a magnifier that runs the
  search at every width, beside the X, as other search engines' fields do.
  It was on phones only.
- Search page: the loading line shows only on Images. Every other tab has
  its placeholder cards, and the line sat above them.

## 1.17.4 (2026-10-20)

- Search page: every tab lines up. In Safari the header was 1px taller
  on a tab whose pill showed a count, and a plain card's text sat 1px
  higher than a Pages card's; off Apple the sort and time menus had
  different fonts.
- Search page: switching tabs is calmer. A tab that takes a moment shows
  placeholder cards where its results will land (a quick one never
  shows them), and results fade in without sliding.

## 1.17.3 (2026-10-20)

- Search page: while results load, only the placeholder cards show. The
  heading's placeholder above them is gone (tabs have no heading now),
  and so is the loading line while the cards are there; it still shows
  for other loads, such as the next page.

## 1.17.2 (2026-10-20)

- Search page: Frosted Header is clear now, the blurred scene alone, so
  the background and the results scrolling under it show through. Its
  name, pills, time range and buttons each sit on the page's colour, so
  they stay easy to read.
- Search page: a tab's results have no heading ("Your Pages", "Images"…);
  the chosen pill already says which tab you're on. A respelled search
  still says what it found ("Your Pages · for “raspberry pi”").
- Search page: no empty strip of glass under one page of results.

## 1.17.1 (2026-10-20)

- Search page: a tab's heading (Images, News…) is rounded like the rest
  of the page, and Images' results start level with every other tab's
  (they sat 7px lower).

## 1.17.0 (2026-10-20)

- Backgrounds: Frosted Header and Frosted Results (the web app:
  Frosted Sidebar and Frosted List) in Settings → Background. On, that
  part of the page is frosted the way the header is without a
  background, so more of the scene shows through; text is a little less
  crisp over its brightest parts. Off by default.

## 1.16.0 (2026-10-20)

- Search page: step through the images with ‹ › under the picture, the
  ← → keys, or a swipe on a phone. In a wide window the image's pane
  floats over the grid, so the tiles and the search field no longer
  move when it opens.

## 1.15.0 (2026-10-20)

- Search page: a click on an image shows it large, with Open Image and
  Visit Page below it: in the preview pane in a wide window, else over
  the page. ⌘-click still opens the page.

## 1.14.1 (2026-10-19)

- Search page: it waits 5 s for the web, not 10, before going to
  DuckDuckGo (when nothing of yours was found) or saying the web didn't
  answer. SearXNG now gives each engine 2.5 s.

## 1.14.0 (2026-10-19)

- All: your pages come in Hister's own order. Hister ranks a page with
  the whole phrase first, and a site's home page for one word, but not
  in a search with any filter, and Shiori's always leave notes, files
  and code out. All now asks for the words alone too and puts those
  pages first; the count, the paging and the Pages pill are as before.
  The pages you opened from Hister's own page for a search are lifted
  too (the apps, the web app and the search page).
- Search page: opening a preview keeps the results where they were and
  as wide. The preview takes the Info card's place and the window's
  room to its right (it squeezed the results).

## 1.13.1 (2026-10-18)

- shiori-web: the nginx base image is updated to the current
  `nginx-unprivileged:stable-alpine`.

## 1.13.0 (2026-10-18)

- Feeds: Subscribe in RSS Reader opens any reader, not only NewsBlur.
  Put %s in Settings → Data → RSS Reader where the feed's address goes
  (FreshRSS, Miniflux and the like); an address without it gets
  ?url=<feed> as before. The apps, the web app and the docs say RSS
  reader instead of NewsBlur.
- README: it opens with what Shiori searches, links Machiya's other
  apps and services where each first appears, and has screenshots
  retaken on 1.12.1.

## 1.12.1 (2026-10-18)

- One item, one entry: a YouTube video Hister holds under two addresses
  (its mobile site, a start time) shows once in every list, and a site's
  mobile address counts as the site.
- All: a web result that's one of your pages is a single entry, your
  page, where the web ranked it; its title opens the website and its
  hister chip your copy. A "wiki" search's article, when it's yours, was
  listed twice.
- iPhone and iPad Settings: an address sits under its label from the
  leading edge (a shorter one looked indented).
- Apps: Settings → Hister offers Sign In again when Hister has ended this
  device's session (it still read as signed in).

## 1.12.0 (2026-10-16)

- Classic: through mac-bridge 0.2.0, a long page or note opens in parts
  of about 16 KB instead of failing as too large. The status line says
  "Part 2 of 5", and Previous Part and Next Part links sit at the text's
  ends. A page's own relative links now show their full address. Shiori
  Lite on a 512K Mac reads real pages this way.
- Search page: in a window no wider than the page (a 13-inch Mac with
  the preview open), the results' glass keeps a margin from the window's
  edge, as the preview does on the other side.
- Search page: the AI Answer row, first in the column, is level with the
  preview beside it; the loading placeholders' right column is level with
  the left; and the results no longer move up a few pixels when the last
  request comes in.

## 1.11.3 (2026-10-15)

- Search page: with a background the start page shows it behind the
  middle too; the name, the corner's buttons and the footer sit on small
  panes of glass.
- Search page: Did you mean no longer runs into the first result, and the
  right column (AI Answer, Related Searches, Info) lines up with the top
  of the results, Did you mean included.
- All: your media goes among the web results, as your pages and notes do,
  each saying "Your media", with the total on the Media pill; no more
  Your Media section above them. On the search page, in the web app and
  in the apps.

## 1.11.2 (2026-10-15)

- Backgrounds: Safari on a Mac, iPhone and iPad keeps the frosted glass
  over a moving scene, the rain or a video; only other browsers (Firefox
  and Chrome on Linux and Windows) dim it without the blur. There the
  scene also moves at 15 frames a second instead of 30, which halves what
  it costs; the rain stays at 30.

## 1.11.1 (2026-10-15)

- Search page: in a wide window off the Mac (Firefox on Linux, Windows) the
  columns grow to fill it as they do on a Mac, up to the same width; the
  margins beside them were twice the Mac's.
- Backgrounds: a moving scene, the rain or a video no longer makes the
  browser blur them under every panel for every frame. The panels dim
  them with black instead, which looks the same and takes about a quarter
  less of the processor in Firefox on Linux.

## 1.11.0 (2026-10-15)

- Basic Search: with JavaScript off, the search page goes to `/basic`, a
  plain HTML page with your pages, your notes and the web, and takes the
  search with it. The web app says it needs JavaScript and links there.
- The favicon SVG is valid XML again (a comment in it held `--`, so
  browsers drew it as a broken image).

## 1.10.6 (2026-10-15)

- Search page: a preview's text is the system's sans in Chrome and Firefox
  too (it fell back to serif outside Safari).

## 1.10.5 (2026-10-15)

- Search page: a preview's text fits its pane in Safari. With the page's
  Text Size zoom (always on a Mac), the right sixth of the text was cut off.

## 1.10.4 (2026-10-15)

- Search page: the preview pane lines up with the results, stays under
  the header as they scroll and fits the window (on a Mac it ran past the
  bottom). With a background it ends above Rain and Watch, and so does the
  web app's preview.

## 1.10.3 (2026-10-15)

- Backgrounds: the Rain and Watch buttons sit in the lower-right corner,
  where they no longer cover the left edge of the results. On the web app
  the list scrolls clear of them on a wide window too.

## 1.10.2 (2026-10-14)

- shiori-web: the nginx base image is updated to the current
  `nginx-unprivileged:stable-alpine`.

## 1.10.1 (2026-10-14)

- Web app: the installed app's status bar is see-through again, as before
  1.9.0: the header is plain frost up under the clock and starts 12px
  below it on an iPhone. Remove the app from the Home Screen and add it
  again to get it.

## 1.10.0 (2026-10-14)

- Backgrounds, from annai: 16 animated night scenes (Tokyo, Osaka, Seoul,
  Hong Kong, Shanghai, Taipei, Singapore, Bangkok, San Francisco, Los
  Angeles, Chicago, Las Vegas, and three film and game homages), with
  rain and your own picture or video, in the web app and the search page
  (Settings → Appearance). The signs show Shiori's own words. Watch hides
  the page to see the scene; Esc or a tap brings it back. Off by default,
  kept in this browser only, a still frame with Reduce Motion. Text keeps
  its contrast: panels frost over the scene.
- shiori-web: the page's policy allows a video of your own (`media-src
  'self' blob:`). The container test passes under rootless podman.

## 1.9.0 (2026-10-14)

- Media: Sort (Newest, Most Played, Top Rated, Year…), Group (Shelves,
  Day, Month, Kind, Played) and a Filter with counts (Date, Kind, Played,
  Rating, Service), as on the other pills. Sort → Top Lists picks the top
  lists' period. Films and TV open in Plex first. "Recently Listened".
  Settings → Media: a switch, address, token and Test Connection for each
  service.
- Settings: one look for every field; Hister's server at the top of
  Search; the pills' order and switches behind one row; Pill Row
  (Automatic wraps when the pills don't fit, one row on a short screen).
  The web pages' Settings is the house's sheet (Cancel and Save), the web
  app's with the apps' pages inside it.
- Opened pages: a page you opened from a search stays in that search (it
  vanished with Show Opened off). Show Opened is on by default. Beside
  the preview, a page counts as opened after 2 seconds on it.
- ⌘K goes to the search field everywhere (Ctrl+K off a Mac); ⌘R reloads a
  list on the Mac.
- iPad and small Mac windows: two columns below 1,000 points, a page
  opening over the results.
- Saving: a site's error page is never saved as the page; a busy site's
  link waits and is downloaded later. Waiting to Send lists pages that
  couldn't be saved. On the Mac, waiting pages are sent again (the outbox
  never found them). Save Links has Stop.
- Failures say so: Small Web and All when a source didn't answer, a list
  that couldn't load more, Labels when the server didn't answer.
- AI: cut-off summaries and answers are marked and never kept; Label New
  Pages never writes over a label you set, stops when an engine can't
  answer, and starts fresh for another account.
- Privacy and security: Kura's and Konbini's addresses save on Return
  (the sign-in never goes to a half-typed address) and only the app sets
  them; the network cache is memory only; a note from a private vault is
  never offered by Save Links or served from a cached summary; preview
  links open only as web addresses; "Not encrypted" under any http://
  address that gets a sign-in.
- Accessibility: Undo is announced and waits 20 seconds with VoiceOver;
  results and saves are announced; bigger tap targets; theme colors only.
- Web app: no black-translucent status bar (re-add it to the Home
  Screen); the status bar's color fades into the header; one tab lit at a
  time. Search page: Open in Hister goes to Hister.
- shiori-web: says when a token file can't be read; the container test
  covers another uid.
- Faster lists, previews and launch; one bad item no longer fails a page.

## 1.8.0 (2026-10-13)

- Media: a Media pill for your Jellyfin and Plex libraries and what you
  played from Koito and Movary, in the apps, the web app and the hosted
  search page. One card per item says when you played it ("Never Played",
  "Played 3× · Last Mar 6, 2014") with your rating as stars; filter by
  kind, never played and rating. Before a search: what's playing, what
  you played and watched, your top artists, albums and tracks, your
  watchlist and Recently Added. All shows Your Media's top five. Each
  service is optional; Shiori only reads them, and nothing of it goes to
  Hister or any AI (docs/media.md).
- shiori-web: `/jellyfin/`, `/plex/`, `/koito/` and `/movary/` routes that
  add the host's own token (`SHIORI_<NAME>_URL`, `SHIORI_<NAME>_TOKEN`).
- Search page: a beforeunload alone (a link that never leaves, such as a
  note's Obsidian link) counts as leaving for 3 seconds only.

## 1.7.2 (2026-10-13)

- Search page: leaving it while the web is still loading (the sign-in, a
  new search, a link) no longer lands you on DuckDuckGo. A signed-out
  browser now reaches the sign-in.

## 1.7.1 (2026-10-13)

- Hosted pages: Kura's Sign In works. On the search page it was a link
  inside the heading's button, which Safari never followed; with
  Hister's sign-in it now renews this host's sign-in and comes back.
- Search page: a slow web no longer sends you to DuckDuckGo when none of
  your pages or notes match. It says "Web results didn't answer", with
  Try Again and a DuckDuckGo link; only with nothing answering at all
  (Tailscale off) does it go to DuckDuckGo.

## 1.7.0 (2026-10-12)

- Web results say which engines didn't answer ("No answer from …") in the
  web app and the apps too, as the search page did.
- shiori-web: an opt-in timing log (`SHIORI_TIMING_LOG`) for a metrics
  collector: one line per request with a fixed path bucket, status and
  seconds; never a query string, a search word or a client address.

## 1.6.0 (2026-10-12)

- Suggest Labels (the apps' Settings → AI, and Suggested Labels): asks
  about the newest unlabelled pages now, with Label New Pages on or off.
  Every answer waits in Suggested Labels; nothing is applied.
- Previews: a wide table fits the screen in the apps, the web app and the
  search page. Addresses and code may break; words stay whole.

## 1.5.17 (2026-10-11)

- Same as 1.5.16, with the hosted pages' nginx base image pinned to its
  current digest (the old one moved upstream, so 1.5.16's image couldn't
  be built).

## 1.5.16 (2026-10-11)

- iPhone and iPad: result cards line up with the search field, the pills
  and Sort · Group · Filter, 16 points in from the edges; their contents
  move in to match.
- Web app: result cards line up with the search field and the pills too
  (they stuck out 2px each side).

## 1.5.15 (2026-10-11)

- Same as 1.5.14, with the tests green: one check of the stylesheet's
  pattern had gone stale. Nothing changes for the pages.

## 1.5.14 (2026-10-11)

- **The web app's first recent search starts level with the pills.** It sat
  about 12px higher than All / Pages / Notes; its top is now the pills' at
  every width from 760px and at any text size (one shared sum).

## 1.5.13 (2026-10-11)

- **The tab icon is served as an image.** The hosted pages' server had no
  type for `.svg` and `.ico`, so the new favicon went out as a plain
  download and Safari ignored it. The server now lists SVG, ICO and the
  other image, text and font types the pages can ship, and a test checks
  every file in both pages has one (the container test checks what the
  running image sends).

## 1.5.12 (2026-10-11)

- **The tab icon is the rooms' set,** on the search page and in the web
  app: an SVG (a dark rounded tile with the ribbon and lens made bold and
  kept in from the edge, so nothing touches it at 16px), an .ico with 16,
  32 and 48px frames, and the square touch icon. The corners of the old 64px
  PNG were stored as transparent black, which Safari's scaling bled into a
  dark fringe; the new frames store them white and transparent.

## 1.5.11 (2026-10-11)

- **On a Mac the web app's text styles are the Mac app's sizes.** Body and
  titles 15.6px, subheadlines (snippets, Sort · Group · Filter) 13.2px, and
  the smallest three styles (footnotes, captions, the pills) 12px, where the
  iPhone's scale had put the captions at 11 and 10px. Sidebar headings are
  the rows' size, as in the app. Other devices keep the iPhone's sizes, and
  Settings → Text Size scales all of them.

## 1.5.10 (2026-10-11)

- **The web app's text starts larger on a Mac.** Standard followed the
  system's text size, 13 points there, so the menus and results read small
  (a root of 12px against the iPhone's 16). It starts 1.2 times larger, as
  the Mac app and the search page do: 15.6px body text. Other sizes in
  Settings → Text Size are as they were.
- **The pills row sits closer to the search field,** 10px under it at every
  width from 760px (it was 22px at the wide layout).

## 1.5.9 (2026-10-11)

- **The web app's search field is level with the sidebar's Library row.**
  The field sat 7px lower; its center is now the row's at every width from
  760px and at any text size (the row's height is one shared sum), and the
  list under it doesn't move.

## 1.5.8 (2026-10-11)

- **On the Mac, the pills row is level with the sidebar's Library row.**
  All / Pages / Notes sat 4 points lower; their centers now line up, and the
  bar below them is as tall as it was.

## 1.5.7 (2026-10-11)

- **The search field's text is the normal weight** from 1100px, as the
  rooms' field (it was 500), on the search page and in the web app. Its size
  (15px from 1100px, 16px or more below) is as it was.

## 1.5.6 (2026-10-11)

- **The search field is a set 38px tall,** on the search page and in the web
  app, as the rooms'. The height is fixed (no padding above or below the
  text), so a browser's line height or the page's zoom can't change it; it
  was 44px by the sums but drew shorter in Safari. Its text is 15px from
  1100px and 16px or more below, at weight 500 from 1100px. Its place,
  width and single focus ring are as they were.

## 1.5.5 (2026-10-11)

- **The search field's text matches the tabs beside it,** as the rooms'
  now do: the tabs' size at weight 500 from 1100px up (the search page and
  the web app); narrower, 16px or more, so iOS doesn't zoom into it. The
  field is 44.4px tall in both, in the same place and width.
- **One focus ring on the field's edge at every width,** drawn inside over
  the border, where under 1100px it had been a border and a second ring
  outside it.
- **The search page's footer sits at the bottom of the window when the page
  is shorter than it,** and right after the content otherwise.

## 1.5.4 (2026-10-11)

- **The search field's focus ring shows in full.** In the top row the
  field sits just under the window's edge, so its ring lost its top edge
  there. From 1100px up the ring is now drawn inside the field; the field
  and the row keep their size and place.

## 1.5.3 (2026-10-11)

- **The search page's field is sized to the results' column as drawn.** It
  is measured from the column on screen and placed over it, so it is always
  as wide as the results and level with their left edge (from 1100px up),
  whatever the browser's text size or zoom.
- **The web app's search field is a pill,** as the rooms' (Kura, Niwa and
  Konbini). Its width and place are as they were.

## 1.5.2 (2026-10-11)

- **The search field is in the top row, next to the name,** from 1100px up,
  as wide as the results' column and ending where it ends. Its left edge is
  the results' where the name leaves room, else just after the name. Below
  1100px it's the row under the name.

## 1.5.1 (2026-10-11)

- **The search field is back in its own row above the pills** on the
  search page, at the results' width as before; only the name and the icons
  span the window.
- **The start page's field is in the middle of the window:** the Text Size
  zoom had made the page 20% taller than the window on the Mac, so the field
  sat low.

## 1.5.0 (2026-10-11)

- **The search page's header spans the window, as the rooms':** the mark
  20px in from the left edge, the house and gear 20px in from the right,
  the search pill just left of them from 1100px up (240 to 560px wide, as
  theirs). Below that the field is the row under the name. The pills and
  time range keep the results' column.
- **The header keeps the rooms' pixel sizes at any Text Size:** the Mac's
  larger Standard no longer scales the name, field and icons.
- **The start page's field is in the middle of the window**, the mark above
  it and the recent searches below.
- **The web app applies a waiting new version on a refresh** (plain or hard);
  the New Version · Reload toast stays for a page left open.

## 1.4.3 (2026-10-11)

- **The search page's header is the rooms' size at any text size:** the name
  is 18px and the field 16px, not scaled by Text Size (the Mac's larger
  Standard made them bigger than the rooms'), and the icon buttons have the
  rooms' 8px corners.

## 1.4.2 (2026-10-11)

- **The web app's search field shows its whole focus ring** in a wide
  window: it sat 12px down in a 62px row, and the bar under it cut off the
  ring's bottom. The field is centered in the row, above that bar.

## 1.4.1 (2026-10-11)

- **A table in a preview keeps its columns readable:** a wide note table
  (a change log's Date, Category, Status) squeezed its narrow columns to a
  letter wide ("Categor y"). Cells now wrap at word edges, in the apps, the
  web app and the search page's preview.

## 1.4.0 (2026-10-11)

- **Settings → AI is reordered** in the iPhone, iPad and Mac apps: AI
  Features, Used For, Engines (Tried in This Order), Cloud Engine, Privacy,
  Automatic Labels. Both cloud providers show their key, model and test at
  once, and a Use row picks which one answers. The AI Answer switch moved
  here from Search; Requests Today shows the day's cloud requests against the
  cap, and one Privacy note replaces three footers.

## 1.3.0 (2026-10-11)

- **Test Anthropic and Test OpenAI** in Settings → AI: each tries that
  provider's saved key and model, whichever one is in use, with one small
  request. It shows the model that answered and how long it took, or what's
  wrong in plain words: a refused key, no access to the model, a rate limit,
  a provider fault, no network. Off with no key set.

## 1.2.1 (2026-10-11)

- **The apps' AI Answer follows your language, not the results':** it
  answers in the query's language when that's plain (three words or more),
  else in the device's. "dak galbi" came back in Indonesian.

## 1.2.0 (2026-10-10)

- **The search page's header matches the Machiya rooms':** the name in the
  accent color, 18px, a 48px top row, 32px icon buttons. From 1100px up the
  search field sits in that row between the name and the icons, centered;
  below that, and on phones, it stays under the name. The pills stay in their
  own row, and the start page is as it was.
- **The Info card sticks under the header** instead of behind it.

## 1.1.7 (2026-10-10)

- **The search page's start box is smaller:** narrower, with a slightly
  smaller field, and the recent searches under it match its width.

## 1.1.6 (2026-10-10)

- **All waits for the web before it shows your notes** in the iPhone, iPad
  and Mac apps (1.5 s at most), as the search page does. Your pages and notes
  showed first, then moved when the web's results landed among them.

## 1.1.5 (2026-10-10)

- **Switching pills in the web app no longer shows the last pill's
  results.** Notes (or All's pages and notes) that finished loading after a
  switch to Web sat under the Web pill until the web answered.

## 1.1.4 (2026-10-10)

- **The loading line sits above the result placeholders** on the search
  page; the placeholders covered it.

## 1.1.3 (2026-10-08)

- **`shiori save` on Linux no longer hangs** on a page whose title holds a
  numeric entity past U+10FFFF; the entity stays as written.
- **Safari's Save Link decodes a title once:** "Tom &amp;lt;3" is saved as
  "Tom &lt;3", not "Tom <3".
- **AI summaries and answers leave out scripts, styles and comments** that
  span several lines; before, their text could reach the model.

## 1.1.2 (2026-10-08)

- **The container's start-up check reads SearXNG's whole answer.** It read
  only the first 64 KiB, so a real JSON answer warned "wasn't JSON".
- **status.json names the Hister release again** in the image (`v0.20.0`,
  not empty or a commit). `SHIORI_HISTER_VERSION` sets it when Hister runs
  another release.

## 1.1.1 (2026-10-08)

- **The container hides what isn't set up.** Without Kura the Notes tab
  stays out (unless Notes From Hister is chosen), without a small-web
  gateway the Small Web tab does, and with Hister's own sign-in the pages
  no longer ask for `/machiya/api/prefs`, so there is no 404 on every
  load. Settings then say they stay in this browser.
- README and web/README: Kura's allowed host names, the compose start,
  and Hister's https cookie.

## 1.1.0 (2026-10-08)

- **Shiori in a container.** `ghcr.io/machiya-kobo/shiori-web` serves the
  search page and the web app behind nginx, for amd64 and arm64, signed with
  cosign on each release. Two settings run it (`SHIORI_HISTER_URL` and
  `SHIORI_SEARXNG_URL`); Kura, Konbini, the small web, the feed, AI and
  hister-login are optional, and an unset one is hidden with its routes
  answering 404. Without hister-login it signs in with Hister's own
  account. The start-up log says if Hister is unreachable or SearXNG refuses
  JSON results. web/README.md ("In a container") has every setting.
- The pages take their sign-in and feed settings from the host, so a host
  with no feed service offers no Subscribe links.

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
