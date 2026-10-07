#!/bin/bash
# Starts, stops or shows the fake house (classic/tests/fake_house.py: the real
# bridge in front of fake services), by PID file: never pkill -f or pgrep -f
# a pattern, which matches your own shell's command line (over SSH it kills
# the session).
#   classic/scripts/fake-house.sh start [--allow NETWORK]   # default: this machine's /24
#   classic/scripts/fake-house.sh stop | status | log
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
pidfile=/tmp/shiori-fakehouse.pid
log=/tmp/shiori-fakehouse.log
running() { [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; }
case ${1:-status} in
start)
    if running; then echo "fake-house: already running (PID $(cat "$pidfile"))"; exit 0; fi
    allow=${3:-}
    [ "${2:-}" = "--allow" ] || allow=""
    if [ -z "$allow" ]; then
        addr=$(ip -4 -o route get 1.1.1.1 2>/dev/null | sed -nE 's/.* src ([0-9.]+).*/\1/p')
        [ -n "$addr" ] || { echo "fake-house: can't find this machine's LAN address; pass --allow" >&2; exit 1; }
        allow="${addr%.*}.0/24"
    fi
    setsid python3 "$here/tests/fake_house.py" --allow "$allow" >"$log" 2>&1 </dev/null &
    echo $! >"$pidfile"
    sleep 1
    running || { echo "fake-house: didn't start:" >&2; cat "$log" >&2; exit 1; }
    echo "fake-house: running (PID $(cat "$pidfile")), admitting $allow; log $log"
    ;;
stop)
    if running; then
        pid=$(cat "$pidfile")
        kill -- -"$pid" 2>/dev/null || kill "$pid"   # its process group: the fake services too
        rm -f "$pidfile"
        echo "fake-house: stopped"
    else
        echo "fake-house: not running"
    fi
    ;;
status)
    if running; then echo "fake-house: running (PID $(cat "$pidfile"))"; else echo "fake-house: not running"; fi
    ;;
log)
    tail -20 "$log"
    ;;
*)
    echo "usage: fake-house.sh start [--allow NETWORK] | stop | status | log" >&2; exit 2 ;;
esac
