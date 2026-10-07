# Shiori

[Machiya](https://github.com/machiya-kobo/machiya) is a set of small self-hosted apps for finding what you've read: your pages ([Hister](https://github.com/asciimoo/hister)), the web ([SearXNG](https://github.com/searxng/searxng)), your notes ([Obsidian](https://obsidian.md)) and your code ([Forgejo](https://forgejo.org) or [GitHub](https://github.com)).

Shiori (栞, "bookmark") is the search app for Machiya and searches Hister and SearXNG from an iPhone, iPad, Mac, Linux, Haiku, a classic 68k Mac or the web. It's also a Hister extension for Safari on macOS and iOS, or you can use Hister's [official](https://hister.org/docs/browser-extension) or [community](https://github.com/nburns/hister-safari) extensions.

<p align="center">
<a href="https://machiya-kobo.github.io/">Machiya</a> · <a href="#what-it-does">Features</a> · <a href="#quickstart">Quickstart</a> · <a href="docs/signing-in.md">Sign In</a> · <a href="docs/extension.md">Safari</a> · <a href="docs/build.md">Build</a> · <a href="docs/linux.md">Linux</a> · <a href="docs/haiku.md">Haiku</a> · <a href="docs/classic.md">Classic Mac</a> · <a href="web/README.md">Hosting</a> · <a href="#credits-and-license">License</a>
</p>

<p align="center"><a href="docs/screenshots/shiori-search-dark.png"><img src="docs/screenshots/shiori-search-dark.png" alt="Shiori searching for lantern in the dark theme: invented web results with a sample page marked Your page and a sample note marked Your note among them, the Pages 5 and Notes 4 tabs above, and an Info card about paper lanterns on the right" width="100%"></a><br>Everything everywhere all at once</p>

<table>
  <tr>
    <td align="center" width="33%"><a href="docs/screenshots/shiori-library-light.png"><img src="docs/screenshots/shiori-library-light.png" alt="The web app's Library in the light theme: sample collections and labels in the sidebar, sample pages newest first, and Folding a chōchin lantern open in the preview" width="100%"></a><br>Browse your library</td>
    <td align="center" width="33%"><a href="docs/screenshots/shiori-notes-light.png"><img src="docs/screenshots/shiori-notes-light.png" alt="The web app's Notes in the light theme: sample notes from Kura with their folders, and the Lantern festival kit note open in the preview with its checklist" width="100%"></a><br>Read your notes</td>
    <td align="center" width="33%"><a href="docs/screenshots/shiori-settings-dark.png"><img src="docs/screenshots/shiori-settings-dark.png" alt="The web app's Settings in the dark theme: theme, mode and text size, then which views show over every list, in what order" width="100%"></a><br>Pick a theme and your views</td>
  </tr>
</table>

<p align="center"><a href="docs/screenshots/shiori-library-phone-light.png"><img src="docs/screenshots/shiori-library-phone-light.png" alt="The web app's Library at phone width in the light theme: sample pages as cards, and the Library, Labels, Settings and Rooms tabs at the bottom" width="24%"></a><br>Search from your phone</p>

## What it does

[Hister](https://github.com/asciimoo/hister) is a self-hosted personal search engine: its browser extension sends the full text of every page you visit (except the ones you skip) to your own Hister server. Shiori searches it. Native apps for iPhone, iPad, Mac, Linux, Haiku and classic 68k Macs, and web apps for everything else. No Electron.

> **Unofficial.** Shiori is not affiliated with or endorsed by the Hister project.

- **Search your pages** with Hister's query syntax, completions included. Filter by date, site, visits, language and type.
- **Search your notes**: your Obsidian vault, through Kura. A note opens in Obsidian, its Kura page and Konbini card a tap away.
- **Search the World Wide Web** through your [SearXNG](https://github.com/searxng/searxng), your own pages mixed in and the ones you've visited marked.
- **Search Gemini and Gopher** through a small-web gateway.
- **Search your code** in the Code view: repos, READMEs, docs, issues, pull requests and releases imported into Hister. Filter by kind, forge, open or private; each opens at its forge.
- **Search your files** in the Files view: the folders Hister watches ([local directory indexing](https://hister.org/docs/configuration#local-directory-indexing)), opened from Hister's copy.
- **Browse** everything Hister holds, newest first, by label and collection (Hister's `@` aliases, like `@reading`), or by day and month.
- **Read a page** as Hister's readable copy, scripts off, no referrer. Earlier versions, Show As, full screen, and images large on tap.
- **Label, share or delete** a page. A delete checks that exactly one page matches, and waits for Undo.
- **Save pages** from the share sheet on iPhone, iPad and Mac, by address (Add Page, ⇧⌘A on the Mac), or with Shortcuts and Siri ("Search Hister", "Save URL to Hister"), with an optional label.
- **Offline support.** Saves wait on the device, out of your backups, and go when Hister answers. After 14 days they're dropped.
- **Remember what you open**: Hister puts it first the next time you search the same words. Your last 5 searches stay on the device (Settings → Results → History).
- **Subscribe** to any search, collection or label as RSS (all collections at once as OPML, for NewsBlur), through a companion feed service on the Hister host, not in this repository: `GET /shiori/feed?q=<query>[&title=…][&exclude_label=…]`, answering RSS 2.0 with the 50 newest matches.
- **Export** any list as JSON, CSV or RSS.
- **Pick a theme**: Tokyo Night, Solarized, Nord, Dracula, Catppuccin, Gruvbox, Rosé Pine, Kanagawa, Everforest or Ayu, light and dark, and a text size of your own, on the Mac too.
- **Take your settings along.** Signed in to Hister, your theme, text size, views and results options follow you to every device and Machiya app. Addresses, sign-ins, AI and Use This Device's Size stay put.

Shiori talks only to the servers you configure: Hister and, if you set them, SearXNG, Kura, Konbini, a small-web gateway and the feed service, plus the AI providers you switch on (Settings → AI, off by default). Safari's extension also fetches the favicons and PDFs of the sites you visit, as upstream's does. A file never goes to an AI, and code only to an on-device model. Switch off Settings → Results → Images in Previews and a preview loads nothing from elsewhere. No analytics.

**Part of Machiya.** Each [Machiya](https://github.com/machiya-kobo/machiya) app is a *room*: Kura (a notes search and reader), Konbini (a project board), Niwa (a published notes garden) and Shiori. Shiori needs only a Hister; the other rooms are optional.

## Quickstart

Run a Hister with a dozen invented pages, then Shiori's search page and web app, on this machine. You need `git`, `python3`, `curl`, and `podman` or `docker`. Ports 4433, 8765 and 8766 must be free.

**1. Get the code**

```bash
git clone https://github.com/machiya-kobo/shiori && cd shiori
```

**2. Start Hister and add the sample pages.** Hister listens on this machine only. With docker, type `docker` for `podman`.

<!-- quickstart: hister-podman -->
```bash
podman run -d --name shiori-hister -p 127.0.0.1:4433:4433 \
  -e HISTER__SERVER__ADDRESS=0.0.0.0:4433 -e HISTER__SERVER__BASE_URL=http://localhost:4433 \
  ghcr.io/asciimoo/hister:v0.20.0
```

<!-- quickstart: seed -->
```bash
tools/quickstart/seed-hister.py http://127.0.0.1:4433/
```

**3. Build the search page and the web app**

<!-- quickstart: pages-build -->
```bash
scripts/build-web.sh demo-site http://localhost:8765/
scripts/build-pwa.sh demo-app
```

**4. Serve them**, each in its own terminal:

<!-- quickstart: serve-search background -->
```bash
HISTER_URL=http://127.0.0.1:4433/ web/dev-server.py demo-site
```

<!-- quickstart: serve-app background -->
```bash
HISTER_URL=http://127.0.0.1:4433/ PORT=8766 web/dev-server.py demo-app
```

| Open | Address |
|---|---|
| The search page | http://localhost:8765/?q=lantern |
| The web app | http://localhost:8766/ |
| Hister | http://localhost:4433/ |

The search page finds five lantern pages, and the web app's Library holds all twelve. To stop, press Ctrl+C in both terminals, then run `podman rm -f shiori-hister`.

### Next

- **Check every step as you go,** with packages for Debian and the BSDs: [the full, tested walkthrough](docs/quickstart.md).
- **Add your notes and the web:** [run it with Machiya](docs/quickstart.md#b-as-one-of-the-machiya-services), next to Kura, Konbini and SearXNG.
- **Use it from your phone and laptop:** [host the pages](web/README.md) behind your own network.
- **Get the apps:** [iPhone, iPad and Mac](docs/build.md), [Linux](docs/linux.md#install) or [Haiku](docs/haiku.md#install).
- **Save pages as you browse:** [Shiori's Safari extension](docs/extension.md), or Hister's [official extensions](https://hister.org/docs/browser-extension) for Firefox and Chrome.

## Sign in

Shiori signs in to Hister when it has users, and to Kura and Konbini when Machiya's identity file is on. Both are off by default: [docs/signing-in.md](docs/signing-in.md).

## The Safari extension

Hister's own extension, built for Safari on iPhone, iPad and Mac, with an offline queue and search from the address bar: [docs/extension.md](docs/extension.md).

## Build

Build the iPhone, iPad and Mac apps with Xcode 27 and a free Apple ID, then turn on the extension: [docs/build.md](docs/build.md).

## Linux

A Flatpak around the web app, with Cinnamon's menu search, a quick-search hotkey and `shiori save`: [docs/linux.md](docs/linux.md).

## Haiku

A native app on the Be API, installed with `pkgman` or built with `make`: [docs/haiku.md](docs/haiku.md).

<p align="center"><a href="docs/screenshots/shiori-haiku-search.png"><img src="docs/screenshots/shiori-haiku-search.png" alt="Shiori on Haiku in the default theme: a search for lantern lists sample notes from Kura (Lantern festival kit, Chōchin build log, Washi offcuts) above sample pages from Hister, with the All, Pages, Notes and Code buttons above them" width="73%"></a><br>Native on Haiku</p>

## Classic Macintosh

A native Hister client for 68k Macs, from a Mac Plus on System 6 to color on System 7, with a quick-search desk accessory. It talks to Hister directly over plain HTTP on your LAN, or through a small read-only bridge when Hister is HTTPS-only: [docs/classic.md](docs/classic.md), which also covers serving Hister to any client without TLS, and what that exposes.

<table>
  <tr>
    <td align="center" width="50%"><a href="docs/screenshots/shiori-classic-system6-search.png"><img src="docs/screenshots/shiori-classic-system6-search.png" alt="Shiori on a Mac Plus in System 6, in black and white: a search for lantern lists sample notes from Kura (Lantern festival kit, Chochin build log, Washi offcuts, Kyoto trip plan) above sample pages from Hister, with the All, Pages, Notes and Code pills above them" width="100%"></a><br>A Mac Plus on System 6</td>
    <td align="center" width="50%"><a href="docs/screenshots/shiori-classic-system7-color.png"><img src="docs/screenshots/shiori-classic-system7-color.png" alt="Shiori in color on System 7: the same search for lantern with blue titles and colored pills, and the Lantern festival kit note open in a reader window beside it, showing its checklist" width="100%"></a><br>Color on System 7</td>
  </tr>
</table>

## Hosting the web pages

Serve the search page and the web app from one host that routes to Hister, SearXNG and Kura, reachable only by you: [web/README.md](web/README.md).

## Updating upstream

Move `vendor/hister` to an upstream tag and rebuild the extension: [docs/extension.md](docs/extension.md#updating-upstream).

## Credits and license

- [Hister](https://github.com/asciimoo/hister) by Adam Tauber (asciimoo) and contributors: the search engine Shiori searches, and the extension it builds for Safari. Hister's [official extensions](https://hister.org/docs/browser-extension) are the ones to use in Firefox and Chrome.
- [hister-safari](https://github.com/nburns/hister-safari) by Nick Burns: the macOS Safari port whose build pipeline, manifest merge and background shim Shiori started from.

Copyright (C) 2026 Micheal Waltz and Machiya contributors.

Contributions are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md), and [SECURITY.md](SECURITY.md) to report a vulnerability privately.

Shiori is free software under the GNU Affero General Public License, version 3 or (at your option) any later version ([AGPL-3.0-or-later](LICENSE)), matching both. Under section 13, if you modify Shiori and let others use it over a network, offer them its source: build with `SHIORI_SOURCE_URL` (a plain http(s) address) and About links it. The third-party software it ships or uses (the Hister extension's bundled libraries and fonts, the logos, the platform libraries) is listed with its licenses in [`THIRD_PARTY_NOTICES`](THIRD_PARTY_NOTICES).
