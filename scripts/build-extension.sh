#!/usr/bin/env bash
# Build the upstream Hister extension and patch it for one browser:
#
#   scripts/build-extension.sh                   Safari, staged in
#       ShioriExtension/Resources/ (gitignored); every Xcode build copies it
#       into both the iOS and macOS appex.
#   scripts/build-extension.sh --target firefox  Firefox (desktop and
#       Android) in build/firefox/, then linted and packed by web-ext into
#       build/shiori-firefox-<version>.zip (unsigned; docs/firefox-plan.md).
#
# Stages:
#   1. npm ci + build of the upstream extension inside vendor/hister.
#   2. Copy dist/; merge patches/manifest.shiori.json, then the browser's
#      patches/manifest.<target>.json, over its upstream manifest.
#   3. Prepend the browser's background files (its shims, the host and
#      Shiori's core) to background.js and the content shim to content.js,
#      and link the popup stylesheet override into popup.html.
#   4. Point the default server URL at SHIORI_SERVER_URL (from local.yml).
#   5. Copy the prebuilt icons, then check the bundle.
#
# Upstream source is never modified; only the built dist/ is patched.

set -euo pipefail

TARGET=safari
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="${2:-}"; shift 2 ;;
        --target=*) TARGET="${1#*=}"; shift ;;
        *) echo "usage: $0 [--target safari|firefox]" >&2; exit 2 ;;
    esac
done

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$REPO_ROOT"

[[ -f local.env ]] && source local.env
# A key's value from local.yml, or nothing. Returns 0 without the file:
# under set -e, a failing $(...) in an assignment would end the build.
yml() {
    [[ -f local.yml ]] || return 0
    sed -n "s/^ *$1: *\"\{0,1\}\([^\"]*\)\"\{0,1\} *\$/\1/p" local.yml | head -1
}
# The server URL normally lives in local.yml, which the app build reads too;
# the environment or local.env can override it.
if [[ -z "${SHIORI_SERVER_URL:-}" && -f local.yml ]]; then
    SHIORI_SERVER_URL="$(sed -n 's/^ *SHIORI_SERVER_URL: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' local.yml | head -1)"
fi
SHIORI_SERVER_URL="${SHIORI_SERVER_URL:-}"

UPSTREAM_ROOT="vendor/hister"
UPSTREAM_EXT="$UPSTREAM_ROOT/webui/ext"
DIST="$UPSTREAM_EXT/dist"
UPSTREAM_DEFAULT_URL="http://127.0.0.1:4433/"

# Per browser: where the bundle goes, which of upstream's manifests it
# starts from, and what is prepended to background.js, in order (the host
# defines shioriHost, which the core uses; scripts/shims.test.mjs and
# scripts/host-local.test.mjs load the same files in the same order).
case "$TARGET" in
    safari)
        RESOURCES="ShioriExtension/Resources"
        UPSTREAM_MANIFEST="manifest.json"
        BACKGROUND=(patches/safari-shims.js patches/ext/host-native.js patches/ext/core.js)
        ;;
    firefox)
        RESOURCES="build/firefox"
        UPSTREAM_MANIFEST="manifest_ff.json"
        BACKGROUND=(patches/ext/host-local.js patches/ext/core.js)
        ;;
    *)
        echo "error: unknown target '$TARGET' (safari or firefox)" >&2
        exit 2
        ;;
esac

if [[ ! -d "$UPSTREAM_EXT" ]]; then
    echo "error: $UPSTREAM_EXT missing; run 'git submodule update --init'" >&2
    exit 1
fi

echo "==> Building upstream extension ($(git -C "$UPSTREAM_ROOT" describe --tags --always)) for $TARGET"
# The extension is an npm workspace; install from the workspace root so
# @hister/components resolves, then build only the extension.
(
    cd -- "$UPSTREAM_ROOT"
    npm ci --no-audit --no-fund --loglevel=error
    npm --workspace @hister/ext run build
)

echo "==> Staging into $RESOURCES"
mkdir -p -- "$RESOURCES"
# Source maps stay out: they only add weight to the appex.
rsync -a --delete \
    --exclude 'manifest.json' \
    --exclude 'manifest_ff.json' \
    --exclude '*.map' \
    "$DIST/" "$RESOURCES/"

# Upstream permissions this build accounts for. A new one fails the build
# so a submodule bump cannot slip a permission past review.
python3 - "$DIST/$UPSTREAM_MANIFEST" "$TARGET" <<'PY'
import json, sys
known = {"tabs", "storage", "cookies"}
m = json.load(open(sys.argv[1]))
if m.get("content_scripts") != [{"js": ["content.js"], "matches": ["<all_urls>"]}]:
    sys.exit("upstream content_scripts changed; update the copy in patches/manifest.shiori.json")
perms = set(m.get("permissions", []))
new = sorted(perms - known)
if new:
    sys.exit("upstream manifest asks for new permissions %s; review them and update "
             "patches/manifest.%s.json and this check" % (new, sys.argv[2]))
PY

node scripts/patch-manifest.mjs \
    "$DIST/$UPSTREAM_MANIFEST" \
    patches/manifest.shiori.json \
    "patches/manifest.$TARGET.json" \
    "$RESOURCES/manifest.json"

# The manifest carries Shiori's version (project.yml MARKETING_VERSION),
# which Safari shows and the background shim reports as metadata.client.
SHIORI_VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9.]*\)"\{0,1\}.*/\1/p' project.yml | head -1)"
[[ -n "$SHIORI_VERSION" ]] || { echo "error: MARKETING_VERSION not found in project.yml" >&2; exit 1; }
python3 - "$RESOURCES/manifest.json" "$SHIORI_VERSION" <<'PY'
import json, sys
p, version = sys.argv[1:]
m = json.load(open(p))
m["version"] = version
json.dump(m, open(p, "w"), indent=2)
open(p, "a").write("\n")
PY
echo "==> Shiori version $SHIORI_VERSION"

prepend() { # <bundle file> <shim>...
    local target="$1"; shift
    { for shim in "$@"; do cat -- "$shim"; printf '\n'; done; cat -- "$DIST/$target"; } > "$RESOURCES/$target.tmp"
    mv -- "$RESOURCES/$target.tmp" "$RESOURCES/$target"
}
prepend background.js "${BACKGROUND[@]}"
prepend content.js patches/safari-content-shim.js

# Shiori's own pages and scripts: the combined-search results page and the
# duckduckgo.com redirect.
cp -- patches/shiori/search.html patches/shiori/search.css patches/shiori/search.js \
    patches/shiori/search-core.js "$RESOURCES/"
cp -- patches/shiori/redirect.js "$RESOURCES/shiori-redirect.js"
# Shiori's settings page. Safari's shows what the app set (Safari →
# Extensions → Shiori → Settings); Firefox has no app, so its page sets them.
if [[ "$TARGET" == safari ]]; then
    cp -- patches/shiori/options.html "$RESOURCES/shiori-options.html"
    cp -- patches/shiori/options.css "$RESOURCES/shiori-options.css"
    cp -- patches/shiori/options.js "$RESOURCES/shiori-options.js"
else
    cp -- patches/ext/settings.html "$RESOURCES/shiori-settings.html"
    cp -- patches/ext/settings.css "$RESOURCES/shiori-settings.css"
    cp -- patches/ext/settings.js "$RESOURCES/shiori-settings.js"
fi
# Your server's status page, linked in the results page's footer.
SHIORI_STATUS_URL="${SHIORI_STATUS_URL:-$(yml SHIORI_STATUS_URL)}"
python3 scripts/status-link.py "$RESOURCES/search.html" "$SHIORI_STATUS_URL"
echo "==> Status page: ${SHIORI_STATUS_URL:-(none)}"

# Popup stylesheet overrides, linked after upstream's style.css.
cp -- patches/safari-popup.css "$RESOURCES/safari-popup.css"
cp -- patches/shiori-popup.js "$RESOURCES/shiori-popup.js"
python3 - "$RESOURCES/popup.html" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = '<link rel="stylesheet" href="style.css" />'
if anchor not in s:
    sys.exit("popup.html no longer links style.css as expected; update the popup patch")
s = s.replace(anchor, anchor + '\n    <link rel="stylesheet" href="safari-popup.css" />\n    <script src="shiori-popup.js"></script>', 1)
open(p, "w", encoding="utf-8").write(s)
PY

if [[ -z "${SHIORI_SEARXNG_URL:-}" && -f local.yml ]]; then
    SHIORI_SEARXNG_URL="$(sed -n 's/^ *SHIORI_SEARXNG_URL: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' local.yml | head -1)"
fi
SHIORI_SEARXNG_URL="${SHIORI_SEARXNG_URL:-}"
if [[ -n "$SHIORI_SEARXNG_URL" && "$SHIORI_SEARXNG_URL" != */ ]]; then SHIORI_SEARXNG_URL="$SHIORI_SEARXNG_URL/"; fi
python3 - "$RESOURCES/background.js" "$SHIORI_SEARXNG_URL" <<'PY'
import sys
p, url = sys.argv[1:]
s = open(p, encoding="utf-8").read()
if "__SHIORI_SEARXNG_URL__" not in s:
    sys.exit("background.js lost the SearXNG placeholder")
open(p, "w", encoding="utf-8").write(s.replace("__SHIORI_SEARXNG_URL__", url))
PY
echo "==> Default SearXNG URL: ${SHIORI_SEARXNG_URL:-(none)}"

# Niwa and Konbini, where vault notes live on the web (optional).
SHIORI_NIWA_URL="${SHIORI_NIWA_URL:-$(yml SHIORI_NIWA_URL)}"
SHIORI_KONBINI_URL="${SHIORI_KONBINI_URL:-$(yml SHIORI_KONBINI_URL)}"
python3 - "$RESOURCES/background.js" "$SHIORI_NIWA_URL" "$SHIORI_KONBINI_URL" <<'PY'
import sys
p, niwa, konbini = sys.argv[1:]
s = open(p, encoding="utf-8").read()
for placeholder, value in (("__SHIORI_NIWA_URL__", niwa), ("__SHIORI_KONBINI_URL__", konbini)):
    if placeholder not in s:
        sys.exit("background.js lost the %s placeholder" % placeholder)
    s = s.replace(placeholder, value)
open(p, "w", encoding="utf-8").write(s)
PY
echo "==> Niwa: ${SHIORI_NIWA_URL:-(none)}   Konbini: ${SHIORI_KONBINI_URL:-(none)}"

# The Obsidian vault's name (if the build sets one), the extension's
# default before the app answers, and its results page's; none unset.
SHIORI_OBSIDIAN_VAULT="${SHIORI_OBSIDIAN_VAULT:-$(yml SHIORI_OBSIDIAN_VAULT)}"
python3 - "$RESOURCES" "$SHIORI_OBSIDIAN_VAULT" <<'PY'
import os, sys
root, vault = sys.argv[1:]
for name in ("background.js", "search.js"):
    p = os.path.join(root, name)
    s = open(p, encoding="utf-8").read()
    if "__SHIORI_OBSIDIAN_VAULT__" not in s:
        sys.exit("%s lost the Obsidian vault placeholder" % name)
    open(p, "w", encoding="utf-8").write(s.replace("__SHIORI_OBSIDIAN_VAULT__", vault))
PY
echo "==> Obsidian vault: ${SHIORI_OBSIDIAN_VAULT:-(none)}"

# Where the source is (AGPL-3.0 section 13), shown in the results page's
# gear when set; none when unset.
SHIORI_SOURCE_URL="${SHIORI_SOURCE_URL:-$(yml SHIORI_SOURCE_URL)}"
python3 - "$RESOURCES/search.js" "$SHIORI_SOURCE_URL" <<'PY'
import sys
p, url = sys.argv[1:]
s = open(p, encoding="utf-8").read()
if "__SHIORI_SOURCE_URL__" not in s:
    sys.exit("search.js lost the source placeholder")
open(p, "w", encoding="utf-8").write(s.replace("__SHIORI_SOURCE_URL__", url))
PY

# The neighbours' icons in the results page: neutral glyphs unless local.yml
# (or the environment) names a folder holding their own logos (hister.png,
# searxng.svg) in SHIORI_ROOM_LOGOS. The repository carries no other
# project's logo.
SHIORI_ROOM_LOGOS="${SHIORI_ROOM_LOGOS:-$(yml SHIORI_ROOM_LOGOS)}"
if [[ -n "$SHIORI_ROOM_LOGOS" ]]; then
  python3 scripts/room-icons.py --logos "$SHIORI_ROOM_LOGOS" "$RESOURCES/search.css" >/dev/null
  echo "==> Room icons: the neighbours' logos"
else
  echo "==> Room icons: neutral glyphs"
fi

if [[ "$TARGET" == safari ]]; then
    # The app's ID for sendNativeMessage, from the bundle prefix (local.yml).
    # Safari ignores it and answers from the containing app, so a build
    # without one names the placeholder Apple's samples use.
    SHIORI_BUNDLE_PREFIX="${SHIORI_BUNDLE_PREFIX:-$(yml SHIORI_BUNDLE_PREFIX)}"
    APP_ID="${SHIORI_BUNDLE_PREFIX:+$SHIORI_BUNDLE_PREFIX.shiori}"
    python3 - "$RESOURCES/background.js" "${APP_ID:-application.id}" <<'PY'
import sys
p, app = sys.argv[1:]
s = open(p, encoding="utf-8").read()
if "__SHIORI_APP_ID__" not in s:
    sys.exit("background.js lost the app ID placeholder")
open(p, "w", encoding="utf-8").write(s.replace("__SHIORI_APP_ID__", app))
PY
    echo "==> App ID: ${APP_ID:-(none: application.id)}"
fi

# The Machiya rooms for the results page's switcher (optional).
SHIORI_ROOMS="${SHIORI_ROOMS:-$(yml SHIORI_ROOMS)}"
SHIORI_ROOMS="$SHIORI_ROOMS" SHIORI_NIWA_URL="$SHIORI_NIWA_URL" SHIORI_KONBINI_URL="$SHIORI_KONBINI_URL" \
  SHIORI_SERVER_URL="$SHIORI_SERVER_URL" SHIORI_SEARXNG_URL="$SHIORI_SEARXNG_URL" \
  python3 scripts/rooms-stamp.py "$RESOURCES/search.js"

# The hosted search page (web/), where Safari's searches open when it
# answers: a web page survives iOS suspending and restoring Safari, an
# extension page doesn't (optional; without it the extension's own page).
SHIORI_SEARCH_PAGE_URL="${SHIORI_SEARCH_PAGE_URL:-$(yml SHIORI_SEARCH_PAGE_URL)}"
if [[ -n "$SHIORI_SEARCH_PAGE_URL" && "$SHIORI_SEARCH_PAGE_URL" != */ ]]; then SHIORI_SEARCH_PAGE_URL="$SHIORI_SEARCH_PAGE_URL/"; fi
[[ -z "$SHIORI_SEARCH_PAGE_URL" || "$SHIORI_SEARCH_PAGE_URL" =~ ^https?:// ]] || { echo "SHIORI_SEARCH_PAGE_URL must start with http:// or https://" >&2; exit 1; }
python3 - "$RESOURCES" "$SHIORI_SEARCH_PAGE_URL" "$TARGET" <<'PY'
import os, sys
root, url, target = sys.argv[1:]
for name in ("background.js", "shiori-options.js") if target == "safari" else ("background.js",):
    p = os.path.join(root, name)
    s = open(p, encoding="utf-8").read()
    if "__SHIORI_SEARCH_PAGE_URL__" not in s:
        sys.exit(name + " lost the search page placeholder")
    open(p, "w", encoding="utf-8").write(s.replace("__SHIORI_SEARCH_PAGE_URL__", url))
PY
echo "==> Search page: ${SHIORI_SEARCH_PAGE_URL:-(extension page)}"

if [[ -n "$SHIORI_SERVER_URL" ]]; then
    [[ "$SHIORI_SERVER_URL" == */ ]] || SHIORI_SERVER_URL="$SHIORI_SERVER_URL/"
    echo "==> Default server URL: $SHIORI_SERVER_URL"
    python3 - "$RESOURCES" "$UPSTREAM_DEFAULT_URL" "$SHIORI_SERVER_URL" <<'PY'
import os, sys
root, old, new = sys.argv[1:]
hits = []
for name in os.listdir(root):
    if not name.endswith(".js"):
        continue
    p = os.path.join(root, name)
    s = open(p, encoding="utf-8").read()
    if old in s:
        open(p, "w", encoding="utf-8").write(s.replace(old, new))
        hits.append(name)
if "background.js" not in hits:
    sys.exit("upstream default URL %s not found in background.js; "
             "has modules/settings.ts changed?" % old)
print("    replaced in " + ", ".join(sorted(hits)))
PY
else
    echo "==> SHIORI_SERVER_URL unset; keeping upstream default $UPSTREAM_DEFAULT_URL"
fi

mkdir -p -- "$RESOURCES/assets/icons"
for f in assets/icon-*.png; do
    cp -- "$f" "$RESOURCES/assets/icons/"
done
# Upstream's own Hister images, replaced with Shiori's: icon128.png is
# what upstream draws its toolbar icons from (the shim then swaps in the
# files above, telling colour from grey by the drawn pixels), logo.png
# is its logo.
cp -- assets/icon-128.png "$RESOURCES/assets/icons/icon128.png"
[[ -f "$RESOURCES/assets/logo.png" ]] && cp -- assets/icon-256.png "$RESOURCES/assets/logo.png"

python3 scripts/check-extension.py "$RESOURCES" "$TARGET"

# Firefox: Mozilla's linter (0 errors or the build fails; warnings are
# printed), then the unsigned package. Signing happens in the release
# workflow (docs/firefox-plan.md, phase 5).
if [[ "$TARGET" == firefox ]]; then
    WEB_EXT="web-ext@10.7.0"
    echo "==> $WEB_EXT lint"
    npx --yes "$WEB_EXT" lint --source-dir "$RESOURCES" --self-hosted --output text
    npx --yes "$WEB_EXT" build --source-dir "$RESOURCES" --artifacts-dir build \
        --filename "shiori-firefox-$SHIORI_VERSION.zip" --overwrite-dest
fi
