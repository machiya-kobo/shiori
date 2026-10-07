# Quickstart

The full walkthrough, with every step checked. The README's [Quickstart](../README.md#quickstart) is the short path.

Two ways in:

- **[A. Standalone](#a-standalone-with-sample-pages):** a Hister with invented sample pages.
- **[B. With Machiya](#b-as-one-of-the-machiya-services):** next to Kura, Konbini, Niwa and SearXNG.

`tools/quickstart-test` runs every block marked `quickstart:` on this page exactly as written, on clean machines: Debian for all of it, and OpenBSD, FreeBSD and NetBSD for the web pages. It can't test the Mac, iPhone and iPad apps (they need Xcode, a signing team and a device) or Cinnamon's menu search and hotkey (they need a desktop session). Those steps, in [build.md](build.md) and [linux.md](linux.md), are checked by hand.

## Get the tools

You need `git`, `bash`, `python3`, `curl`, and `podman` or `docker` for Hister. The Linux app needs Debian or any Linux with Flatpak. Ports 4433, 8765 and 8766 must be free.

*Debian or Ubuntu* (everything, the Linux app included):

<!-- quickstart: packages-debian -->
```bash
sudo apt-get update
sudo apt-get install -y git curl python3 podman flatpak flatpak-builder dbus-bin
```

Run the BSD blocks as root: a fresh FreeBSD or NetBSD has no `sudo`, and OpenBSD's `doas` needs an `/etc/doas.conf` first.

*OpenBSD* (the web pages):

<!-- quickstart: packages-openbsd -->
```bash
pkg_add python%3 git curl bash
```

*FreeBSD* (the web pages):

<!-- quickstart: packages-freebsd -->
```bash
pkg install -y python3 git curl bash
```

*NetBSD* (the web pages; its packages name Python by version, so give it a `python3`):

<!-- quickstart: packages-netbsd -->
```bash
export PKG_PATH="https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/$(uname -p)/$(uname -r | cut -d_ -f1)/All"
pkg_add python313 git-base curl bash
ln -sf /usr/pkg/bin/python3.13 /usr/pkg/bin/python3
```

The BSDs have no podman or docker. Run Hister on another machine, or natively with [Machiya's BSD guide](https://github.com/machiya-kobo/machiya/blob/main/docs/install/bsd.md), and point step 2's `HISTER_URL` at it. Without a Hister, the results check has nothing to show.

## Get the code

```bash
git clone https://github.com/machiya-kobo/shiori && cd shiori
```

The Mac and iOS builds also need `git submodule update --init`: the Safari extension is built from Hister's own.

## A. Standalone, with sample pages

**1. Start a Hister.** It listens on this machine only.

*With podman:*

<!-- quickstart: hister-podman -->
```bash
podman run -d --name shiori-hister -p 127.0.0.1:4433:4433 \
  -e HISTER__SERVER__ADDRESS=0.0.0.0:4433 -e HISTER__SERVER__BASE_URL=http://localhost:4433 \
  ghcr.io/asciimoo/hister:v0.20.0
```

*With docker:*

<!-- quickstart: hister-docker -->
```bash
docker run -d --name shiori-hister -p 127.0.0.1:4433:4433 \
  -e HISTER__SERVER__ADDRESS=0.0.0.0:4433 -e HISTER__SERVER__BASE_URL=http://localhost:4433 \
  ghcr.io/asciimoo/hister:v0.20.0
```

Fill it with a dozen invented pages from a paper-lantern workshop and a Kyoto trip. The script writes only to a Hister on this machine.

<!-- quickstart: seed -->
```bash
tools/quickstart/seed-hister.py http://127.0.0.1:4433/
```

<!-- quickstart-expect: seed -->
```text
Added 12 sample pages to http://127.0.0.1:4433/
```

**2. Build the search page and the web app.** They need only bash and Python 3.

<!-- quickstart: pages-build -->
```bash
scripts/build-web.sh demo-site http://localhost:8765/
scripts/build-pwa.sh demo-app
```

Serve each in its own terminal (or end the line with `&`). `web/dev-server.py` routes them the way a real host does.

<!-- quickstart: serve-search background -->
```bash
HISTER_URL=http://127.0.0.1:4433/ web/dev-server.py demo-site
```

<!-- quickstart: serve-app background -->
```bash
HISTER_URL=http://127.0.0.1:4433/ PORT=8766 web/dev-server.py demo-app
```

Check that both answer and reach Hister:

<!-- quickstart: pages-check -->
```bash
curl -s http://localhost:8765/_shiori/opensearch.xml | grep -o '<ShortName>[^<]*</ShortName>'
curl -s http://localhost:8766/manifest.webmanifest | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])'
```

<!-- quickstart-expect: pages-check -->
```text
<ShortName>Shiori</ShortName>
Shiori
```

<!-- quickstart: results-check -->
```bash
curl -s 'http://localhost:8765/search?format=json&query=%7B%22text%22%3A%22lantern%22%7D' \
  | python3 -c 'import json,sys; print(*sorted(d["title"] for d in json.load(sys.stdin)["documents"]), sep="\n")'
```

<!-- quickstart-expect: results-check -->
```text
Bending bamboo frames with steam
Candle or LED inside a paper lantern?
Folding a chōchin lantern
Kyoto's summer lantern festival
Restoring an old paper lantern
```

Open <http://localhost:8765/?q=lantern> to see those pages. The web results need SearXNG (part B). <http://localhost:8766/> is the web app, with all twelve pages in its Library and their labels in the sidebar. To host the pages for real, see [web/README.md](../web/README.md).

**3. Build Shiori for Linux.** This installs the GNOME runtime, then the app, for your user. Tested on Debian 13; any distribution with Flatpak works the same.

<!-- quickstart: linux-build -->
```bash
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user -y flathub org.gnome.Platform//49 org.gnome.Sdk//49
linux/flatpak/build.sh
```

The build also writes `~/.cache/shiori-flatpak/shiori.flatpak`, a bundle to install elsewhere.

Point it at Hister and the web app, and search the way the desktop search does. This overwrites `~/.config/shiori/config.json`, so back up your own first (`cp ~/.config/shiori/config.json ~/.config/shiori/config.json.bak`). Over SSH with no desktop, put `dbus-run-session --` in front of `flatpak run`.

<!-- quickstart: linux-check -->
```bash
mkdir -p ~/.config/shiori
echo '{"webApp": "http://localhost:8766/", "server": "http://127.0.0.1:4433/"}' > ~/.config/shiori/config.json
flatpak run io.github.machiya_kobo.Shiori provider-search lantern \
  | python3 -c 'import json,sys; print(*sorted(r["name"] for r in json.load(sys.stdin)), sep="\n")'
```

<!-- quickstart-expect: linux-check -->
```text
Bending bamboo frames with steam
Candle or LED inside a paper lantern?
Folding a chōchin lantern
Kyoto's summer lantern festival
Restoring an old paper lantern
```

`flatpak run io.github.machiya_kobo.Shiori` opens the window. `linux/install-desktop.sh` adds the `shiori` command and, on Cinnamon, the menu search and Ctrl+Alt+Space. It changes your running desktop session's settings; `--remove` undoes it ([linux.md](linux.md)).

**4. Build the Mac, iPhone and iPad apps** (not machine-tested). Follow [build.md](build.md) on a Mac with Xcode 27, and set `SHIORI_SERVER_URL` to `http://<this machine's address>:4433/`. Then [turn on the extension](build.md#turn-on-the-extension).

**Stop.** End the two servers (Ctrl+C), then remove Hister:

<!-- quickstart: stop-podman -->
```bash
podman rm -f shiori-hister
```

<!-- quickstart: stop-docker -->
```bash
docker rm -f shiori-hister
```

## B. As one of the Machiya services

Clone `machiya`, `kura`, `niwa`, `konbini` and `shiori` side by side. Start the stack with the [Machiya Quickstart](https://github.com/machiya-kobo/machiya#quickstart): Hister, SearXNG, Kura with the sample vault, Konbini and Niwa on this machine's ports, with no sign-in.

**1. Build the pages** in `shiori`, with the stack's default addresses. `SHIORI_NIWA_URL` is your Kura (the name is older than Kura):

<!-- quickstart: stack-pages-build -->
```bash
export SHIORI_NIWA_URL=http://localhost:8083/ SHIORI_KONBINI_URL=http://localhost:8081/
export SHIORI_ROOMS="kura=http://localhost:8083/,konbini=http://localhost:8081/,niwa=http://localhost:8082/,hister=http://localhost:4433/,searxng=http://localhost:8888/"
scripts/build-web.sh demo-site http://localhost:8765/
scripts/build-pwa.sh demo-app
```

**2. Serve them**, routed to every app:

<!-- quickstart: stack-serve-search background -->
```bash
HISTER_URL=http://127.0.0.1:4433/ SEARXNG_URL=http://127.0.0.1:8888/ KURA_URL=http://127.0.0.1:8083/ \
  KONBINI_URL=http://127.0.0.1:8081/ web/dev-server.py demo-site
```

<!-- quickstart: stack-serve-app background -->
```bash
HISTER_URL=http://127.0.0.1:4433/ SEARXNG_URL=http://127.0.0.1:8888/ KURA_URL=http://127.0.0.1:8083/ \
  KONBINI_URL=http://127.0.0.1:8081/ PORT=8766 web/dev-server.py demo-app
```

**3. Check the notes.** They come from Kura, through the same host:

<!-- quickstart: stack-check -->
```bash
curl -s 'http://localhost:8765/kura/api/search?q=lantern&limit=50' \
  | python3 -c 'import json,sys; print(*sorted(r["title"] for r in json.load(sys.stdin)["results"]), sep="\n")' | grep -x 'Lantern festival kit'
```

<!-- quickstart-expect: stack-check -->
```text
Lantern festival kit
```

<http://localhost:8765/?q=lantern> now has the sample vault's notes, each with its Kura page and Konbini card, and web results from SearXNG. The web app's Notes view lists the vault, and the Rooms menu moves between the apps.

- **Pages too:** the stack's Hister holds only the notes. Run part A's `tools/quickstart/seed-hister.py http://127.0.0.1:4433/`.
- **Gemini and Gopher:** add `SHIORI_SMALLWEB_URL` to the build and a `SMALLWEB_URL` route to the server.
- **A Source link in About:** add `SHIORI_SOURCE_URL`, your fork's address.

**4. The Linux app** takes Kura the same way. This overwrites `~/.config/shiori/config.json` again, so back up your own first:

<!-- quickstart: stack-linux-check -->
```bash
mkdir -p ~/.config/shiori
echo '{"webApp": "http://localhost:8766/", "server": "http://127.0.0.1:4433/", "kura": "http://127.0.0.1:8083/"}' > ~/.config/shiori/config.json
flatpak run io.github.machiya_kobo.Shiori provider-search lantern \
  | python3 -c 'import json,sys; print(*sorted(r["name"] for r in json.load(sys.stdin) if r["kind"] == "note"), sep="\n")' | grep -x 'Lantern festival kit'
```

<!-- quickstart-expect: stack-linux-check -->
```text
Lantern festival kit
```

The Mac and iOS apps take the same addresses in `local.yml` (`SHIORI_SEARXNG_URL`, `SHIORI_NIWA_URL`, `SHIORI_KONBINI_URL`, `SHIORI_SMALLWEB_URL`) or in Settings.

