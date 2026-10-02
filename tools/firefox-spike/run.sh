#!/usr/bin/env bash
# Phase 0 of docs/firefox-plan.md: build the Safari bundle against a fake
# Hister, turn it into a Firefox one, and run run.mjs in headless Firefox.
#
#   FIREFOX=/path/to/firefox tools/firefox-spike/run.sh
#
# Needs node, python3, rsync (for the build), Firefox and geckodriver (on
# PATH or GECKODRIVER=). Restages ShioriExtension/Resources with the fake
# server's address; scripts/build.sh and the install scripts restage it.

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
floor=140.0
if [[ -n "$version" && "$version" -lt 140 ]]; then
    floor="$version.0"
    echo "warning: Firefox $version is below the floor (140); the bundle's floor is lowered to run here" >&2
fi

[[ -d "$HERE/node_modules" ]] || (cd -- "$HERE" && npm ci --no-audit --no-fund --loglevel=error)
SHIORI_SERVER_URL="http://127.0.0.1:$HISTER_PORT/" "$REPO_ROOT/scripts/build-extension.sh" > "$WORK/build.log" 2>&1 \
    || { tail -20 "$WORK/build.log" >&2; exit 1; }
python3 "$HERE/make-firefox.py" "$REPO_ROOT/ShioriExtension/Resources" "$EXT" "$floor"

python3 -m http.server "$PAGES_PORT" --bind 127.0.0.1 --directory "$HERE/pages" > /dev/null 2>&1 &
pages=$!
trap 'kill $pages 2>/dev/null' EXIT
sleep 0.5
node "$HERE/run.mjs"
