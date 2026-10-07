#!/bin/sh
# Shiori for Linux in a real Cinnamon session on a virtual display
# (docs/linux.md): what the window manager makes of its windows, which
# headless.sh (no window manager, software rendering) can't show. The
# installed Flatpak against a local test page and linux/fake-hister.py
# (its searches refused, as a Hister with users answers one not signed
# in), never the real servers. Run it on a test account: it swaps
# ~/.config/shiori/config.json, as save-test.sh does, and restores it.
#
#   linux/desktop-test.sh [OUT_DIR]     (screenshots there; exit 1 on a failed check)
#
# Needs Xvfb, cinnamon, dbus-run-session, xdotool, xprop, xwininfo,
# ImageMagick's import, python3 and the Flatpak (linux/flatpak/build.sh).
set -u
# Its own session bus, so the app, the portals and Cinnamon are this test's alone.
if [ -z "${SHIORI_IN_TEST_SESSION:-}" ]; then
  SHIORI_IN_TEST_SESSION=1 exec dbus-run-session -- "$0" "$@"
fi
cd "$(dirname "$0")/.."
app=io.github.machiya_kobo.Shiori
out=${1:-${XDG_CACHE_HOME:-$HOME/.cache}/shiori-desktop-test}
mkdir -p "$out"
export DISPLAY=:${SHIORI_TEST_DISPLAY:-77} XDG_CURRENT_DESKTOP=X-Cinnamon XDG_SESSION_TYPE=x11
width=1600
height=1000
# Free ports, asked of the system: a fixed one may be another test's.
free_port() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
site_port=$(free_port)
hister_port=$(free_port)
cfg=$HOME/.config/shiori/config.json
saved=$(mktemp)
site=$(mktemp -d)
pids=
[ -f "$cfg" ] && cp "$cfg" "$saved"
cleanup() {
  for p in $pids; do kill "$p" 2>/dev/null; done
  if [ -s "$saved" ]; then cp "$saved" "$cfg"; else rm -f "$cfg"; fi
  rm -rf "$saved" "$site"
}
trap cleanup EXIT INT TERM
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
# Waits up to $1 tenths of a second for a command to succeed.
until_ok() {
  n=$1
  shift
  while [ "$n" -gt 0 ]; do
    "$@" >/dev/null 2>&1 && return 0
    sleep 0.1
    n=$((n - 1))
  done
  return 1
}
window() { xdotool search --name "$1" 2>/dev/null | head -1; }
shoot() { import -window root "$out/$1.png"; }
shiori() { flatpak run "$app" "$@" >>"$out/app.log" 2>&1 </dev/null & pids="$pids $!"; }

# The web app's stand-in: a preview-like srcdoc frame that says it loaded,
# and on a search address an export (a blob download, as the web app's).
cat > "$site/index.html" <<'EOF'
<!doctype html><meta charset="utf-8"><title>Window test</title>
<body style="font:18px sans-serif;padding:20px">
<h1>Shiori window test</h1>
<iframe sandbox="allow-scripts" srcdoc="<p>The preview frame</p><script>parent.postMessage('frame', '*')</script>"></iframe>
<script>
addEventListener('message', (e) => { if (e.data === 'frame') document.title = 'Frame loaded'; });
// A search to an open window only changes the hash.
const exportOnSearch = () => location.hash.startsWith('#/search') && setTimeout(() => {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob(['{}'], { type: 'application/json' }));
  a.download = 'shiori-test.json';
  document.body.append(a);
  a.click();
}, 800);
addEventListener('hashchange', exportOnSearch);
exportOnSearch();
</script>
EOF
python3 -m http.server "$site_port" --bind 127.0.0.1 --directory "$site" >/dev/null 2>&1 & pids="$pids $!"
FAKE_SEARCH_STATUS=403 python3 -u linux/fake-hister.py "$hister_port" > "$out/fake-hister.log" 2>&1 & pids="$pids $!"
mkdir -p "$(dirname "$cfg")"
printf '{"webApp": "http://127.0.0.1:%s/", "server": "http://127.0.0.1:%s/"}\n' "$site_port" "$hister_port" > "$cfg"
# The Flatpak reads the host's file through its mount: stop unless it sees this one.
flatpak run --command=cat "$app" "$HOME/.var/app/$app/config/shiori/config.json" 2>/dev/null | grep -q "127.0.0.1:$hister_port" \
  || { echo "desktop-test: the app doesn't see the test config; stopping" >&2; exit 1; }

Xvfb "$DISPLAY" -screen 0 "${width}x${height}x24" >/dev/null 2>&1 & pids="$pids $!"
until_ok 50 xdpyinfo || until_ok 50 xprop -root _NET_SUPPORTED || true
cinnamon --replace > "$out/cinnamon.log" 2>&1 & pids="$pids $!"
until_ok 300 sh -c 'xprop -root _NET_SUPPORTING_WM_CHECK | grep -q "window id"' || { echo "desktop-test: Cinnamon didn't start" >&2; exit 1; }
sleep 3
: > "$out/app.log"

# 1. The window: the app's class, a frame that loads, nothing handed to the portal.
shiori
if until_ok 300 sh -c "xdotool search --name 'Frame loaded – Shiori'"; then ok "the preview-like frame loads in the window"; else bad "the srcdoc frame didn't load"; fi
w=$(window ' – Shiori$')
[ -z "$w" ] && w=$(window '^Shiori$')
class=$(xprop -id "${w:-0}" WM_CLASS 2>/dev/null)
case "$class" in *"\"$app\""*) ok "WM_CLASS is $app" ;; *) bad "WM_CLASS: $class" ;; esac
geometry=$(xwininfo -id "${w:-0}" 2>/dev/null | awk '/Width:/{w=$2} /Height:/{h=$2} END{print w"x"h}')
echo "     window $geometry on ${width}x${height}"
sleep 1
[ -z "$(window '^Open With')" ] && ok "nothing went to the portal's Open With" || bad "an Open With dialog appeared"
shoot 1-window

# 2. An export: the save dialog asks where.
shiori search export
if until_ok 150 sh -c "xdotool search --name '^Save'"; then
  ok "an export asks where to save"
elif grep -q "Can't mount path" "$out/app.log"; then
  # The file chooser hands its file over through the document portal, whose
  # mount another session on this machine (a logged-in desktop) holds.
  echo "skip an export's save dialog: the document portal belongs to another session here"
else
  bad "no save dialog for an export"
fi
shoot 2-export
d=$(window '^Save')
[ -n "$d" ] && xdotool windowactivate --sync "$d" key Escape 2>/dev/null
sleep 1

# 3. Quick search, over the window: a full-screen overlay, the card in the middle; Hister refuses, so it says to sign in.
shiori --quick
if until_ok 150 sh -c "xdotool search --name 'Shiori Quick Search'"; then
  q=$(window 'Shiori Quick Search')
  sleep 1
  read -r qx qy qw qh <<EOF
$(xwininfo -id "$q" | awk '/Absolute upper-left X/{x=$4} /Absolute upper-left Y/{y=$4} /Width:/{w=$2} /Height:/{h=$2} END{print x, y, w, h}')
EOF
  [ "$qx" -le 0 ] && [ "$qy" -le 0 ] && [ "$qw" -ge "$width" ] && [ "$qh" -ge "$height" ] \
    && ok "quick search covers the screen (${qw}x${qh} at $qx,$qy)" || bad "quick search at $qx,$qy, ${qw}x${qh}"
  xdotool type --delay 60 lantern
  sleep 3
  shoot 3-quick-refused
  # Its Sign In button (Tab from the field) opens the sign-in window in its place.
  xdotool key Tab Return
  if until_ok 100 sh -c "xdotool search --name '^Sign in to Hister$'"; then ok "quick search's Sign In opens the sign-in window"; else bad "no sign-in window from quick search"; fi
  [ -z "$(window 'Shiori Quick Search')" ] && ok "quick search closed for it" || bad "quick search still open"
  sleep 1.5
  shoot 4-sign-in
  s=$(window '^Sign in to Hister$')
  [ -n "$s" ] && xdotool windowactivate --sync "$s" key alt+F4 2>/dev/null
  sleep 1
else
  bad "no quick-search window"
fi
grep -q "GET /search" "$out/fake-hister.log" && ok "quick search asked the fake Hister" || bad "quick search never asked Hister"

[ -n "$w" ] && xdotool windowactivate --sync "$w" key alt+F4 2>/dev/null
sleep 1

# 4. The menu's rows: a refused search offers the sign-in.
rows=$(flatpak run "$app" provider-search lantern 2>/dev/null)
case "$rows" in *'"shiori://sign-in"'*) ok "the menu offers Sign in to Hister" ;; *) bad "menu rows: $rows" ;; esac
# Picking that row runs `shiori shiori://sign-in`.
shiori shiori://sign-in
if until_ok 150 sh -c "xdotool search --name '^Sign in to Hister$'"; then ok "shiori://sign-in opens the sign-in window"; else bad "shiori://sign-in opened nothing"; fi

echo "Screenshots: $out"
exit $fail
