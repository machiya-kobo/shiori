#!/bin/sh
# `shiori save`, `send` and `status` in the Flatpak against a fake Hister
# (linux/fake-hister.py), never the real one. Run on a test account.
#
#   dbus-run-session -- linux/save-test.sh
#
# The Flatpak mounts the host's ~/.config/shiori over its own config dir
# (--filesystem=xdg-config/shiori:ro), so a config written under
# ~/.var/app/… is hidden and the real one is used: a test would then save
# to the real Hister. So this swaps ~/.config/shiori/config.json for the test, restores it after,
# and before every command stops unless the app itself sees the fake.
set -u
cd "$(dirname "$0")/.."
app=io.github.machiya_kobo.Shiori
port=18081
cfg=$HOME/.config/shiori/config.json
saved=$(mktemp)
fake=
[ -f "$cfg" ] && cp "$cfg" "$saved"
restore() {
  [ -n "$fake" ] && kill "$fake" 2>/dev/null
  if [ -s "$saved" ]; then cp "$saved" "$cfg"; else rm -f "$cfg"; fi
  rm -f "$saved"
}
trap restore EXIT INT TERM
mkdir -p "$(dirname "$cfg")"
# Kura stays the real one (only read, for save-links); Hister is the fake.
kura=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("kura", ""))' "$saved" 2>/dev/null)
printf '{"server": "http://127.0.0.1:%s/", "kura": "%s"}\n' "$port" "$kura" > "$cfg"
log=$(mktemp)

sees_fake() {
  flatpak run --command=cat "$app" "$HOME/.var/app/$app/config/shiori/config.json" 2>/dev/null | grep -q "127.0.0.1:$port" \
    || { echo "save-test: the app doesn't see the fake Hister's config; stopping" >&2; exit 1; }
}
quiet() { grep -Ev 'dbus-daemon|fusermount|fuse init|portal|Gtk-WARNING|No skeleton|^$'; }
run() { sees_fake; echo "\$ shiori $*"; flatpak run "$app" "$@" 2>&1 | quiet; }
serve() {
  [ -n "$fake" ] && kill "$fake" 2>/dev/null && sleep 0.5
  python3 -u linux/fake-hister.py "$port" "$1" >> "$log" 2>&1 &
  fake=$!
  sleep 1
  echo "(Hister answers $1)"
}

page=https://example.net/shiori-save-test
serve 201; run save "$page-1" testlabel
serve 503; run save "$page-2"
run status
serve 422; run save "$page-3"
serve 201; run send
run status
# Save This Note's Links: a real note's links from Kura, saved to the fake.
if [ -n "$kura" ]; then
  serve 201; run save-links "${SAVE_LINKS_NOTE:-Projects/Example.md}"
  serve 406; run save-links --folder "${SAVE_LINKS_FOLDER:-Reading}" --dry-run
fi
echo "--- the fake Hister saw:"
cat "$log"
rm -f "$log"
