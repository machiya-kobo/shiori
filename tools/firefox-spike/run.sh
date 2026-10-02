#!/usr/bin/env bash
# The Firefox build (scripts/build-extension.sh --target firefox) against a
# fake Hister, in headless Firefox: run.mjs. Started in phase 0 of
# docs/firefox-plan.md with the Safari bundle; now the real Firefox one.
#
#   FIREFOX=/path/to/firefox tools/firefox-spike/run.sh
#
# Needs node, python3, rsync (for the build), Firefox and geckodriver (on
# PATH or GECKODRIVER=). Rebuilds build/firefox with the fake server's
# address.

set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$HERE/../.." && pwd)"
: "${FIREFOX:?set FIREFOX to a Firefox binary}"
export FIREFOX GECKODRIVER="${GECKODRIVER:-geckodriver}"
export HISTER_PORT="${HISTER_PORT:-8775}" PAGES_PORT="${PAGES_PORT:-8776}"
export WORK="${WORK:-$(mktemp -d)}" EXT="$WORK/ext" PROBE="$HERE/container-probe"
echo "==> Work dir: $WORK"

version="$("$FIREFOX" --version | sed -n 's/.* \([0-9][0-9]*\)\..*/\1/p')"
export FIREFOX_MAJOR="$version"
floor=153.0
if [[ -n "$version" && "$version" -lt 153 ]]; then
    floor="$version.0"
    echo "warning: Firefox $version is below the floor (153); the bundle's floor is lowered to run here" >&2
fi

[[ -d "$HERE/node_modules" ]] || (cd -- "$HERE" && npm ci --no-audit --no-fund --loglevel=error)
SHIORI_SERVER_URL="http://127.0.0.1:$HISTER_PORT/" "$REPO_ROOT/scripts/build-extension.sh" --target firefox \
    > "$WORK/build.log" 2>&1 || { tail -20 "$WORK/build.log" >&2; exit 1; }
rm -rf -- "$EXT"
cp -R -- "$REPO_ROOT/build/firefox" "$EXT"
# Only to run on a Firefox older than the floor; never in a real build.
python3 -c 'import json, sys
p, floor = sys.argv[1:]
m = json.load(open(p))
for k in ("gecko", "gecko_android"): m["browser_specific_settings"][k]["strict_min_version"] = floor
json.dump(m, open(p, "w"), indent=2)' "$EXT/manifest.json" "$floor"

python3 -m http.server "$PAGES_PORT" --bind 127.0.0.1 --directory "$HERE/pages" > /dev/null 2>&1 &
pages=$!
trap 'kill $pages 2>/dev/null' EXIT
sleep 0.5
node "$HERE/run.mjs"
