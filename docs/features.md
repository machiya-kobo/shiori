# Every feature

What Shiori does on iPhone, iPad, Mac and the web app. The Linux app is the web app in its own window ([linux.md](linux.md)); [Haiku](haiku.md) and the [Classic Macintosh](classic.md) have their own, smaller lists.

## Searching and reading

- **Search your pages** with Hister's query syntax, completions included. Filter by date, site, visits, language and type.
- **Search your notes**: your Obsidian vault, through Kura. A note opens in Obsidian, its Kura page and Konbini card a tap away.
- **Search the World Wide Web** through your [SearXNG](https://github.com/searxng/searxng), your own pages mixed in and the ones you've visited marked.
- **Search Gemini and Gopher** through a small-web gateway.
- **Search your code** in the Code view: repos, READMEs, docs, issues, pull requests and releases imported into Hister. Filter by kind, forge, open or private; each opens at its forge.
- **Search your files** in the Files view: the folders Hister watches ([local directory indexing](https://hister.org/docs/configuration#local-directory-indexing)), opened from Hister's copy.
- **Browse** everything Hister holds, newest first, by label and collection (Hister's `@` aliases, like `@reading`), or by day and month.
- **Read a page** as Hister's readable copy, scripts off, no referrer. Earlier versions, Show As, full screen, and images large on tap.
- **Remember what you open**: Hister puts it first the next time you search the same words. Your last 5 searches stay on the device (Settings → Results → History).

## Keeping and sharing

- **Label, share or delete** a page. A delete checks that exactly one page matches, and waits for Undo.
- **Save pages** from the share sheet on iPhone, iPad and Mac, by address (Add Page, ⇧⌘A on the Mac), or with Shortcuts and Siri ("Search Hister", "Save URL to Hister"), with an optional label.
- **Offline support.** Saves wait on the device, out of your backups, and go when Hister answers. After 14 days they're dropped.
- **Export** any list as JSON, CSV or RSS.
- **Subscribe** to any search, collection or label as RSS (all collections at once as OPML, for NewsBlur). It needs Machiya's [shiori-feed](https://github.com/machiya-kobo/machiya/blob/main/docs/services/shiori-feed.md) on the Hister host (the reference compose's `shiori` profile): `GET /shiori/feed?q=<query>[&title=…][&exclude_label=…]`, answering RSS 2.0 with the 50 newest matches.

## Your settings

- **Pick a theme**: Tokyo Night, Solarized, Nord, Dracula, Catppuccin, Gruvbox, Rosé Pine, Kanagawa, Everforest or Ayu, light and dark, and a text size of your own, on the Mac too.
- **Take your settings along.** Signed in to Hister, your theme, text size, views and results options follow you to every device and Machiya app. Addresses, sign-ins, AI and Use This Device's Size stay put.

## AI

Off by default, on-device first: Summarize, label suggestions, Label New Pages and an AI Answer for web searches, in the apps ([ai.md](ai.md)). The hosted web app's Summarize and AI Answer need Machiya's [shiori-ai](https://github.com/machiya-kobo/machiya/blob/main/docs/services/shiori-ai.md) on the Hister host (the reference compose's `shiori` profile; [ai.md](ai.md) has its contract).

## What it talks to

Shiori talks only to the servers you configure: Hister and, if you set them, SearXNG, Kura, Konbini, a small-web gateway and the feed service, plus the AI providers you switch on (Settings → AI, off by default). Safari's extension also fetches the favicons and PDFs of the sites you visit, as upstream's does. A file never goes to an AI, and code only to an on-device model. Switch off Settings → Results → Images in Previews and a preview loads nothing from elsewhere. No analytics.

Shiori needs only a Hister. Kura (Machiya's notes app), Konbini (its project board), Niwa (its digital garden) and SearXNG are optional.
