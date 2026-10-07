# Build the Apple apps

Build Shiori for iPhone, iPad and Mac, with its Safari extension and share extensions. You need a Mac with Xcode 27 or later, [Homebrew](https://brew.sh) and an Apple ID. A free Personal Team works for your own devices; its builds need re-signing every 7 days.

**1. Get the code and the tools**

```bash
git clone --recurse-submodules https://github.com/machiya-kobo/shiori
cd shiori
brew bundle                      # Node.js and XcodeGen, from the Brewfile
cp local.yml.example local.yml   # your team, bundle prefix and servers
cp local.env.example local.env   # your device name, for deploys
```

The submodule matters: the Safari extension is built from Hister's own. In a clone made without it, run `git submodule update --init`.

**2. Fill in `local.yml`**

| Setting | Value |
|---|---|
| `DEVELOPMENT_TEAM` | Your team ID, from Xcode → Settings → Accounts. |
| `SHIORI_BUNDLE_PREFIX` | A reverse-DNS prefix of your own, such as `io.github.you`. Bundle IDs are unique across Apple. The build stops until it's set. |
| `SHIORI_SERVER_URL` | Your Hister, with the trailing slash. For the [Quickstart](quickstart.md)'s Hister: `http://<this machine's address>:4433/`. |
| `SHIORI_SEARXNG_URL`, `SHIORI_NIWA_URL`, `SHIORI_KONBINI_URL`, `SHIORI_SMALLWEB_URL` | Optional: your SearXNG, Kura (the name is older than Kura), Konbini and small-web gateway. |

- The prefix names everything. The app is `<prefix>.shiori` and its extensions `.Extension` and `.Share`. The App Group is `group.<prefix>.shiori` on iOS and `<TeamID>.<prefix>.shiori` on macOS.
- The server address becomes the default for the app and the extension; both can change it. Unset, the extension gets upstream's `http://127.0.0.1:4433/` and the app asks.
- `local.yml.example` lists the rest. Anything unset is left for Settings.

**3. Test and build**

```bash
node --test scripts/*.test.mjs   # the extension's manifest and shims, and the shared search logic
(cd Packages/HisterKit && swift test)
scripts/build.sh ios             # or: scripts/build.sh macos
```

**4. Install** on an iPhone or iPad, or on this Mac:

```bash
scripts/deploy-device.sh         # the device named DEVICE_NAME in local.env
scripts/install-mac.sh           # a signed Release in /Applications, replacing any earlier copy
```

## Turn on the extension

**iPhone and iPad:** Settings → Apps → Safari → Extensions → Shiori. Turn it on, set **All Websites** to **Allow**, and leave **Allow in Private Browsing** off. To check the server address, tap the Page Menu button left of Safari's address bar, then Shiori.

A reinstall sets All Websites back to Ask, with no prompt. Set it to Allow again after every install.

**Mac:** open Shiori, click **Open Safari Extensions Settings…**, turn on Shiori, and allow it on every website. A build signed with your team stays on. An ad-hoc build needs Develop → Allow Unsigned Extensions after every Safari restart.

Use one Hister extension in Safari. If hister-safari is on, turn one of them off, or Safari sends every page twice. [extension.md](extension.md) covers what the extension does.

## Release files

Each tag's GitHub release carries builds anyone can test. Make each one from the tag, never from a working checkout, so nothing of yours goes in: no `local.yml` or `local.env` values, no room logos, no token, no team.

| File | Built on | How |
|---|---|---|
| `Shiori-X.Y.Z-macOS.dmg` | a Mac | `scripts/release-mac.sh vX.Y.Z` (a fresh worktree, the public bundle prefix only, signed ad hoc) |
| `Shiori-X.Y.Z-linux-x86_64.flatpak` | Linux with flatpak-builder | from `git archive vX.Y.Z`: `flatpak-builder --repo=repo build linux/flatpak/io.github.machiya_kobo.Shiori.json`, then `flatpak build-bundle repo … io.github.machiya_kobo.Shiori` |
| `shiori-X.Y.Z-1-x86_64.hpkg` | Haiku | from the archive: `cd haiku && make && ./package.sh` |
| `Shiori-Classic-X.Y.Z.{dsk,sit,hqx}` | the Retro68 host | from the archive: `SHIORI_RELEASE=1 classic/scripts/package.sh` |

Before uploading, unpack each file and search it for your own addresses, hostnames, names and team ID. Then attach the files and a `SHA256SUMS` with `gh release create vX.Y.Z …`. iOS has no release file: sideloading needs a paid Apple Developer Program team.

## Generated files

Never edit `Shiori.xcodeproj/` or `ShioriExtension/Resources/`: both are generated. Change `project.yml` or `patches/` instead. Shiori's icons (the app, its Light alternate and the extension's) come from `scripts/generate-shiori-icons.py`.
