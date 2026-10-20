# Every feature

What Shiori does on iPhone, iPad, Mac and the web app. The Linux app is the web app in its own window ([linux.md](linux.md)); [Haiku](haiku.md) and the [Classic Macintosh](classic.md) have their own, smaller lists.

## Searching and reading

- **Search your pages** with Hister's query syntax, completions included. Filter by date, site, visits, language and type.
- **Search your notes**: your Obsidian vault, through [Kura](https://github.com/machiya-kobo/kura). A note opens in Obsidian, its Kura page and [Konbini](https://github.com/machiya-kobo/konbini) card a tap away.
- **Search the World Wide Web** through your [SearXNG](https://github.com/searxng/searxng), your own pages mixed in (one the web also found is a single entry) and the ones you've visited marked.
- **Search Gemini and Gopher** through a [small-web gateway](https://github.com/machiya-kobo/machiya/tree/main/stack/smallweb).
- **Search your code** in the Code view: repos, READMEs, docs, issues, pull requests and releases imported into Hister by Machiya's [code-import](https://github.com/machiya-kobo/machiya/blob/main/docs/services/code-import.md). Filter by kind, forge, open or private; each opens at its forge.
- **Search your media** on the Media pill: your Jellyfin and Plex libraries and what you played from Koito and Movary, one card per item, saying when you played it ("Never Played", "Played 3× · Last Mar 6, 2014") with your rating. Filter by kind, never played and rating; before a search, what's playing, your top artists and albums, your watchlist and what's new ([media.md](media.md)).
- **Search your files** in the Files view: the folders Hister watches ([local directory indexing](https://hister.org/docs/configuration#local-directory-indexing)), opened from Hister's copy.
- **Browse** everything Hister holds, newest first, by label and collection (Hister's `@` aliases, like `@reading`), or by day and month.
- **Read a page** as Hister's readable copy, scripts off, no referrer. Earlier versions, Show As, full screen, and images large on tap.
- **Search without JavaScript**: the hosted search page sends a browser with JavaScript off to Basic Search, plain HTML with your pages, your notes and the web, the search carried over. The web app links it.
- **Remember what you open**: Hister puts it first the next time you search the same words. Your last 5 searches stay on the device (Settings → Results → History).

## Keeping and sharing

- **Label, share or delete** a page. A delete checks that exactly one page matches, and waits for Undo.
- **Save pages** from the share sheet on iPhone, iPad and Mac, by address (Add Page, ⇧⌘A on the Mac), or with Shortcuts and Siri ("Search Hister", "Save URL to Hister"), with an optional label. A page Hister can't take yet waits on the device; Settings → Account → Waiting to Send lists what waits, and any page given up on, with why.
- **Spotlight, Siri and Shortcuts find your pages**: your newest 300 pages are in the device's search (title, site, snippet), and "Open … in Shiori" or the Open Page action finds any of them in Hister. A tap opens the page. Never notes, files or code; Settings → Search → Spotlight turns it off and empties it.
- **Offline support.** Saves wait on the device, out of your backups, and go when Hister answers. After 14 days they're dropped.
- **Export** any list as JSON, CSV or RSS.
- **Subscribe** to any search, collection or label as RSS (all collections at once as OPML, for your RSS reader), or open a list's feed in your reader with Subscribe in RSS Reader. It needs Machiya's [shiori-feed](https://github.com/machiya-kobo/machiya/blob/main/docs/services/shiori-feed.md) on the Hister host (the reference compose's `shiori` profile): `GET /shiori/feed?q=<query>[&title=…][&exclude_label=…]`, answering RSS 2.0 with the 50 newest matches.

## Your settings

- **Pick a theme**: Tokyo Night, Solarized, Nord, Dracula, Catppuccin, Gruvbox, Rosé Pine, Kanagawa, Everforest or Ayu, light and dark, and a text size of your own, on the Mac too.
- **Set a background** on the web app and Shiori Search: a neon city in the rain (Tokyo, Seoul, Hong Kong, San Francisco and more), the rain on its own, or a picture or video of yours. It stays in that browser ([backgrounds.md](backgrounds.md)).
- **Take your settings along.** Signed in to Hister, your theme, text size, views and results options follow you to every device and Machiya app. Addresses, sign-ins, AI and Use This Device's Size stay put.

## AI

Off by default, on-device first: Summarize, label suggestions, Label New Pages and an AI Answer for web searches, in the apps ([ai.md](ai.md)). The hosted web app's Summarize and AI Answer need Machiya's [shiori-ai](https://github.com/machiya-kobo/machiya/blob/main/docs/services/shiori-ai.md) on the Hister host (the reference compose's `shiori` profile; [ai.md](ai.md) has its contract).

## What it talks to

Shiori talks only to the servers you configure: Hister and, if you set them, SearXNG, Kura, Konbini, a small-web gateway, the feed service and the media services (Jellyfin, Plex, Koito, Movary, with art from TMDB), plus the AI providers you switch on (Settings → AI, off by default). Safari's extension also fetches the favicons and PDFs of the sites you visit, as upstream's does. A file never goes to an AI, and code only to an on-device model. Switch off Settings → Results → Images in Previews and a preview loads nothing from elsewhere. No analytics.

Shiori needs only a Hister. Kura (Machiya's notes app), Konbini (its project board), [Niwa](https://github.com/machiya-kobo/niwa) (its digital garden) and SearXNG are optional.
