#!/bin/bash
# The release files for Shiori for Classic Macintosh, in classic/build-release/:
#   Shiori-Classic-<version>.dsk      an 800K HFS floppy image
#   Shiori-Classic-<version>.sit      StuffIt 1.5
#   Shiori-Classic-<version>.hqx      that archive in BinHex
# Each holds Shiori, Shiori Search (the desk accessory's suitcase) and About Shiori.
# Built with neutral defaults only (SHIORI_RELEASE=1): never this machine's local.env.
# Needs hfsutils, macutils' binhex and the emulator hub's sit (scripts/setup-sit.sh).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "$here/.." && pwd)"
EMU=${EMULATORS_DIR:-$HOME/emulators}
SIT="$EMU/tools/sit/sit"
SPLIT="$EMU/scripts/macbinary_split.py"
for tool in hformat hcopy hattrib binhex "$SIT"; do
    command -v "$tool" >/dev/null || { echo "package.sh: $tool is missing" >&2; exit 1; }
done
[ -f "$SPLIT" ] || { echo "package.sh: no $SPLIT" >&2; exit 1; }

SHIORI_RELEASE=1 "$here/scripts/build.sh" >/dev/null
out="$here/build-release"
version=$(sed -nE 's/^ *MARKETING_VERSION: *"?([0-9.]+)"?.*/\1/p' "$root/project.yml" | head -1)
name="Shiori-Classic-$version"

# Nothing private goes out: the neutral defaults are in, and no token or LAN
# address is (192.168.1.5 is Preferences' own example).
# (strings to a file first: grep -q ends early, and under pipefail a SIGPIPE'd strings fails the test)
strings -a "$out/Shiori.bin" "$out/Shiori Search.bin" > "$out/strings.txt"
if ! grep -qF 'http://192.0.2.1:8070/' "$out/strings.txt"; then
    echo "package.sh: the build doesn't carry the neutral defaults" >&2
    exit 1
fi
if grep -vF '192.168.1.5:8070' "$out/strings.txt" \
        | grep -E 'mht_[A-Za-z0-9]|(^|[^0-9])(10|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]+\.[0-9]+' >&2; then
    echo "package.sh: a private address or token is in the build" >&2
    exit 1
fi
rm -f "$out/strings.txt"

sed "s/@VERSION@/$version/" "$here/docs/About Shiori" | tr '\n' '\r' > "$out/About Shiori"

# The floppy image
dsk="$out/$name.dsk"
rm -f "$dsk"
dd if=/dev/zero of="$dsk" bs=1024 count=800 status=none
hformat -l "Shiori $version" "$dsk" >/dev/null
hmount "$dsk" >/dev/null
hcopy -m "$out/Shiori.bin" ":Shiori"
hcopy -m "$out/Shiori Search.bin" ":Shiori Search"
hcopy -r "$out/About Shiori" ":About Shiori"
hattrib -t ttro -c ttxt ":About Shiori"
humount >/dev/null

# The archive, and the archive in BinHex: plain text that survives any
# download and keeps the archive's type, so Expander opens it on the old Mac
stage="$out/.sit-staging"
rm -rf "$stage" && mkdir -p "$stage"
python3 "$SPLIT" split "$out/Shiori.bin" "$stage/Shiori"
python3 "$SPLIT" split "$out/Shiori Search.bin" "$stage/Shiori Search"
cp "$out/About Shiori" "$stage/About Shiori"
python3 "$SPLIT" make-info "$stage/About Shiori" ttro ttxt
rm -f "$out/$name.sit" "$out/$name.hqx" "$out/$name.sit.hqx"
(cd "$stage" && "$SIT" -o "$out/$name.sit" Shiori "Shiori Search" "About Shiori" >/dev/null)
rm -rf "$stage"
(cd "$out" && binhex -d -t 'SIT!' -c 'SIT!' "$name.sit" > "$name.hqx")

ls -l "$dsk" "$out/$name.sit" "$out/$name.hqx"
