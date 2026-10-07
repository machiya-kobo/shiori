#!/bin/bash
# Puts the last build (classic/build/Shiori.bin) where an emulator finds it.
#   classic/scripts/deploy.sh snow [--launch]   # onto shiori-sys608.img's top level
#   classic/scripts/deploy.sh basilisk [--launch [DEPTH]]
#                                                # into Basilisk II's shared folder;
#                                                # DEPTH 1, 2, 4 or 8 bits (8: 256 colors)
# Snow must not be running while its disk changes: this stops it first (by PID,
# never pkill -f, which would match this very command line), then relaunches
# with --launch (SDL_AUDIODRIVER=dummy: with the host's audio stalled, Snow
# never draws a frame). Never run Snow and Basilisk II at once: they share the display.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
EMU=${EMU:-$HOME/emulators}
bin="$here/build/Shiori.bin"
target=${1:?usage: deploy.sh snow|basilisk [--launch]}
[ -f "$bin" ] || { echo "deploy: no build at $bin (classic/scripts/build.sh)" >&2; exit 1; }

stop_snow() {
    local pid
    pid=$(pgrep -x snowemu || true)
    [ -z "$pid" ] && return 0
    kill $pid; for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x snowemu >/dev/null || return 0; sleep 0.5; done
    kill -9 $pid 2>/dev/null || true; sleep 1
    pgrep -x snowemu >/dev/null && { echo "deploy: Snow won't stop" >&2; exit 1; }
    return 0
}

case $target in
snow)
    img="$here/diskimages/shiori-sys608.img"
    [ -f "$img" ] || { echo "deploy: no $img (classic/scripts/setup-emulators.sh)" >&2; exit 1; }
    pgrep -x BasiliskII >/dev/null && { echo "deploy: Basilisk II is running; quit it first" >&2; exit 1; }
    stop_snow
    hmount "$img" >/dev/null
    # at the top level: a folder made by hfsutils has no window position, and
    # the Finder opens it off-screen
    hdel ":Shiori" 2>/dev/null || true
    hcopy -m "$bin" ":Shiori"
    hattrib -t APPL -c SHIO ":Shiori"
    humount >/dev/null
    echo "deploy: Shiori is on $img (:Shiori)"
    if [ "${2:-}" = "--launch" ]; then
        DISPLAY=:0 SDL_AUDIODRIVER=dummy "$EMU/snow/snowemu" "$here/diskimages/shiori.snoww" >/tmp/shiori-snow.log 2>&1 &
        echo "deploy: Snow running (PID $!), log /tmp/shiori-snow.log"
    fi
    ;;
basilisk)
    mkdir -p "$EMU/unix/Shiori"
    python3 "$EMU/basilisk/macbin_to_extfs.py" "$bin" "$EMU/unix/Shiori" Shiori >/dev/null
    echo "deploy: Shiori is in $EMU/unix/Shiori (the Unix disk in Basilisk II)"
    if [ "${2:-}" = "--launch" ]; then
        prefs="$here/diskimages/basilisk_prefs"
        [ -f "$prefs" ] || { echo "deploy: no $prefs (classic/scripts/setup-emulators.sh)" >&2; exit 1; }
        pgrep -x snowemu >/dev/null && { echo "deploy: Snow is running; quit it first" >&2; exit 1; }
        pgrep -x BasiliskII >/dev/null && { echo "deploy: Basilisk II is already running" >&2; exit 0; }
        depth=${3:-8}
        sed -i -e "s/^displaycolordepth .*/displaycolordepth $depth/" "$prefs"
        grep -q '^displaycolordepth' "$prefs" || echo "displaycolordepth $depth" >> "$prefs"
        DISPLAY=:0 BasiliskII --config "$prefs" >/tmp/shiori-basilisk.log 2>&1 </dev/null &
        echo "deploy: Basilisk II running at $depth bits (PID $!), log /tmp/shiori-basilisk.log"
    fi
    ;;
*)
    echo "deploy: unknown target $target (snow or basilisk)" >&2; exit 2 ;;
esac
