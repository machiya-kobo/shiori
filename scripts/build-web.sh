#!/usr/bin/env bash
# Builds Shiori's results page as a plain web page: the same page the Safari
# extension shows, with web/shim.js standing in for the extension APIs.
#
#   scripts/build-web.sh OUT_DIR BASE_URL [STATUS_URL]
#
# BASE_URL is where it's served, e.g. https://shiori.example.ts.net/ (only
# the OpenSearch description needs it, for browsers' "add search engine").
# STATUS_URL, optional, is your server's status page, linked in the
# footer. The hostnames stay out of the repo: the server passes them in.
#
# OUT_DIR/index.html is the page; its files are under OUT_DIR/_shiori/. See
# web/README.md for what the host must route.
set -euo pipefail

cd "$(dirname "$0")/.."
out=${1:?usage: build-web.sh OUT_DIR BASE_URL}
base=${2:?usage: build-web.sh OUT_DIR BASE_URL [STATUS_URL]}
status=${3:-}
[[ $base == */ ]] || base="$base/"
[[ $base =~ ^https?:// ]] || { echo "BASE_URL must start with http:// or https://" >&2; exit 1; }

rm -rf -- "$out"
mkdir -p -- "$out/_shiori"
cp -- patches/shiori/search.js patches/shiori/search-core.js patches/shiori/search.css web/app/palettes.css "$out/_shiori/"
cp -- web/shim.js "$out/_shiori/web-shim.js"
# The neighbours' icons (Hister, SearXNG): neutral glyphs unless the build
# names a folder holding their own logos (hister.png, searxng.svg) in
# SHIORI_ROOM_LOGOS. The repository carries no other project's logo.
if [ -n "${SHIORI_ROOM_LOGOS:-}" ]; then
  python3 scripts/room-icons.py --logos "$SHIORI_ROOM_LOGOS" "$out/_shiori/search.css" >/dev/null
fi
cp -- assets/icon-32.png assets/icon-256.png assets/web-icon-64.png "$out/_shiori/"

# The page, with its files under /_shiori/ (the root's other paths are
# Hister's), the shim first, an icon, and the OpenSearch link.
sed \
  -e 's#href="search.css"#href="/_shiori/search.css"#' \
  -e 's#href="palettes.css"#href="/_shiori/palettes.css"#' \
  -e 's#<script src="search-core.js"></script>#<script src="/_shiori/web-shim.js"></script>\n    <script src="/_shiori/search-core.js"></script>#' \
  -e 's#<script src="search.js"></script>#<script src="/_shiori/search.js"></script>#' \
  -e 's#src="assets/icons/icon-256.png"#src="/_shiori/icon-256.png"#' \
  -e 's#</title>#</title>\n    <link rel="icon" href="/_shiori/web-icon-64.png" />\n    <link rel="apple-touch-icon" href="/_shiori/icon-256.png" />\n    <link rel="search" type="application/opensearchdescription+xml" title="Shiori" href="/_shiori/opensearch.xml" />#' \
  patches/shiori/search.html >"$out/index.html"

python3 scripts/status-link.py "$out/index.html" "$status"
# The Machiya rooms for the switcher: SHIORI_ROOMS (and the notes' homes
# above) from the environment, as the server passes them.
python3 scripts/rooms-stamp.py "$out/_shiori/search.js"
set -- "$out/_shiori/web-shim.js" "$out/_shiori/search.js"
# The notes' homes (Kura, Konbini), the Obsidian vault's name and whether the host has the
# AI companion (SHIORI_AI=1), from the environment as for the
# extension (the server passes them in); unset leaves them for Settings.
python3 - "$@" <<'PY'
import os, sys
for path in sys.argv[1:]:
    with open(path) as f:
        text = f.read()
    for placeholder, name in (("__SHIORI_NIWA_URL__", "SHIORI_NIWA_URL"), ("__SHIORI_KONBINI_URL__", "SHIORI_KONBINI_URL"),
                              ("__SHIORI_OBSIDIAN_VAULT__", "SHIORI_OBSIDIAN_VAULT"),
                              ("__SHIORI_SOURCE_URL__", "SHIORI_SOURCE_URL"), ("__SHIORI_AI__", "SHIORI_AI")):
        value = os.environ.get(name, "")
        if value:
            text = text.replace(placeholder, value)
    with open(path, "w") as f:
        f.write(text)
PY

# Each file's address carries the build, so a browser holding an older copy
# (they're cached for minutes) never runs new HTML with old scripts.
version=$(git rev-parse --short HEAD 2>/dev/null || date +%s)
sed -i.bak -E "s#(/_shiori/(web-shim|search-core|search|palettes)\.(js|css))\"#\1?v=$version\"#g" "$out/index.html" && rm -f -- "$out/index.html.bak"

for needle in '/_shiori/web-shim.js' '/_shiori/search.js' '/_shiori/search.css' '/_shiori/palettes.css' 'opensearch.xml'; do
  grep -q -- "$needle" "$out/index.html" || { echo "build-web: index.html lacks $needle (did search.html change?)" >&2; exit 1; }
done

# Firefox, Chrome and others offer "add search engine" from this.
cat >"$out/_shiori/opensearch.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/" xmlns:moz="http://www.mozilla.org/2006/browser/search/">
  <ShortName>Shiori</ShortName>
  <Description>Your Hister pages and notes, then the web</Description>
  <InputEncoding>UTF-8</InputEncoding>
  <Image width="32" height="32" type="image/png">${base}_shiori/icon-32.png</Image>
  <Url type="text/html" method="get" template="${base}?q={searchTerms}"/>
  <moz:SearchForm>${base}</moz:SearchForm>
</OpenSearchDescription>
XML

# For the house's status page: Shiori's version, the commit, when.
python3 scripts/status-json.py "$out"
# What changed, for the house's status page (Recent Deploys).
cp -- CHANGELOG.md "$out/_shiori/CHANGELOG.md"

echo "==> Web page in $out (for $base)"
