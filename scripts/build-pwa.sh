#!/usr/bin/env bash
# Builds Shiori as a web app (an installable PWA): web/app/, plus the
# search page's theme tokens and search-core.js, which it shares.
#
#   scripts/build-pwa.sh OUT_DIR [STATUS_URL]
#
# STATUS_URL, optional, is your server's status page (linked in the
# sidebar and Settings); the server passes it in, as it does for the
# search page.
#
# OUT_DIR/index.html is the app, OUT_DIR/manifest.webmanifest and sw.js sit
# at the root (a service worker only covers its own directory and below),
# and everything else is under OUT_DIR/_shiori/. The host routes as
# web/README.md says, the same as the search page's host.
set -euo pipefail

cd "$(dirname "$0")/.."
out=${1:?usage: build-pwa.sh OUT_DIR [STATUS_URL]}
status=${2:-}

rm -rf -- "$out"
mkdir -p -- "$out/_shiori"
cp -- web/app/index.html web/app/manifest.webmanifest "$out/"
cp -- web/app/app.js web/app/api.js web/app/app.css web/app/palettes.css patches/shiori/search-core.js "$out/_shiori/"
# The neighbours' icons (Hister, SearXNG): neutral glyphs unless the build
# names a folder holding their own logos (hister.png, searxng.svg) in
# SHIORI_ROOM_LOGOS. The repository carries no other project's logo.
if [ -n "${SHIORI_ROOM_LOGOS:-}" ]; then
  python3 scripts/room-icons.py --logos "$SHIORI_ROOM_LOGOS" "$out/_shiori/app.css" >/dev/null
fi
# The rounded web icons and the maskable one (scripts/generate-shiori-icons.py);
# the apple-touch icon stays square, since iOS rounds it itself.
cp -- assets/icon-256.png assets/web-icon-64.png assets/web-icon-192.png assets/web-icon-512.png assets/web-maskable-512.png "$out/_shiori/"

# The colours: search.css's tokens (its :root blocks, up to the first rule
# that isn't one), so the app and the search page never drift apart.
awk '/^\* \{ box-sizing/ { exit } { print }' patches/shiori/search.css >"$out/_shiori/theme.css"
grep -q -- '--accent' "$out/_shiori/theme.css" || { echo "build-pwa: no theme tokens found in search.css" >&2; exit 1; }

python3 scripts/status-link.py "$out/index.html" "$status"
# The Machiya rooms for the switcher: SHIORI_ROOMS (and the notes' homes
# above) from the environment, as the server passes them.
python3 scripts/rooms-stamp.py "$out/_shiori/app.js"
set -- "$out/_shiori/app.js"
# The notes' homes (Kura, Konbini), the Obsidian vault's name, whether the host has the
# AI companion (SHIORI_AI=1) and whether there's a small-web gateway
# (SHIORI_SMALLWEB_URL: Add Page), from the environment as for the extension
# (the server passes them in); unset leaves them for Settings.
python3 - "$@" <<'PY'
import os, sys
for path in sys.argv[1:]:
    with open(path) as f:
        text = f.read()
    for placeholder, name in (("__SHIORI_NIWA_URL__", "SHIORI_NIWA_URL"), ("__SHIORI_KONBINI_URL__", "SHIORI_KONBINI_URL"),
                              ("__SHIORI_OBSIDIAN_VAULT__", "SHIORI_OBSIDIAN_VAULT"),
                              ("__SHIORI_SOURCE_URL__", "SHIORI_SOURCE_URL"), ("__SHIORI_AI__", "SHIORI_AI"),
                              ("__SHIORI_SMALLWEB_URL__", "SHIORI_SMALLWEB_URL")):
        value = os.environ.get(name, "")
        if value:
            text = text.replace(placeholder, value)
    with open(path, "w") as f:
        f.write(text)
PY

# The share target saves through the small-web gateway: without one, the
# manifest offers none (Add Page is hidden too).
if [ -z "${SHIORI_SMALLWEB_URL:-}" ]; then
  python3 - "$out/manifest.webmanifest" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    manifest = json.load(f)
manifest.pop("share_target", None)
with open(path, "w") as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
fi

# The build's version is a hash of what it built (every file, with the
# settings stamped in, and the service worker), not the commit: a rebuild
# with other settings or room logos gets a new cache name, so an installed
# app picks up the new files, and each file's address carries it (they're
# cached for minutes). The same files give the same version.
version=$(python3 - "$out" web/app/sw.js <<'PY'
import hashlib, os, sys
out, worker = sys.argv[1], sys.argv[2]
h = hashlib.sha256()
for rel in sorted(os.path.relpath(os.path.join(d, f), out) for d, _, fs in os.walk(out) for f in fs):
    with open(os.path.join(out, rel), "rb") as f:
        h.update(rel.encode() + b"\0" + hashlib.sha256(f.read()).digest())
with open(worker, "rb") as f:
    h.update(b"sw.js\0" + hashlib.sha256(f.read()).digest())
print(h.hexdigest()[:12])
PY
)
stamp() { sed -i.bak -E "s#(/_shiori/(app|api|search-core)\.js|/_shiori/(app|theme|palettes)\.css)([\"'])#\1?v=$version\4#g" "$1" && rm -f -- "$1.bak"; }
sed "s/__VERSION__/$version/" web/app/sw.js >"$out/sw.js"
stamp "$out/index.html"
stamp "$out/sw.js"
sed -i.bak "s#from './api.js'#from './api.js?v=$version'#" "$out/_shiori/app.js" && rm -f -- "$out/_shiori/app.js.bak"
# For the house's status page: Shiori's version, the commit, when. After
# the hash above, so the time doesn't make every build a new version.
python3 scripts/status-json.py "$out"

echo "==> Web app in $out ($version)"
