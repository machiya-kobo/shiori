#!/bin/bash
# Creates Shiori's own emulator environment on a test machine with the classic
# Mac emulator hub (~/emulators: Snow, Basilisk II, ROMs, the System 6.0.8 and
# 7.6.1 disks; see classic/docs/TESTING.md). Run once; it never touches the
# hub's shared disks, only copies one.
#   classic/scripts/setup-emulators.sh [--force]
#
# Snow (System 6.0.8, a Mac Plus with 4 MB):
#   classic/diskimages/shiori-sys608.img  a copy of the hub's System 6 disk
#                                         (MacTCP and the DaynaPORT driver set
#                                         up), with other projects' folders
#                                         removed, so the Finder's disk window
#                                         lists Shiori without scrolling
#   classic/diskimages/shiori.snoww       its workspace: Mac Plus ROM, that
#                                         disk on SCSI 0, Ethernet on SCSI 3
# Basilisk II (System 7.6.1): the hub's ROM, a copy of its disk, Shiori's own prefs:
#   classic/diskimages/shiori-sys761.hda  a copy of the hub's System 7 disk, so its
#                                         TCP/IP can be set for slirp (DHCP)
#                                         without touching the disk Flynn and
#                                         Geomys share
#   classic/diskimages/basilisk_prefs     the hub's, with user-mode networking
#                                         (ether slirp: no sheep_net kernel
#                                         module, which must match the running
#                                         kernel); deploy.sh sets the depth
#   Shiori is deployed into the hub's shared folder (~/emulators/unix/Shiori),
#   which System 7 shows as the "Unix" disk.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
EMU=${EMU:-$HOME/emulators}
src=${SHIORI_SYS6_IMAGE:-$EMU/disks/system6.img}
rom=${SHIORI_PLUS_ROM:-$EMU/roms/128KB ROMs/1986-03 - 4D1F8172 - MacPlus v3.ROM}
out="$here/diskimages"
img="$out/shiori-sys608.img"
force=0; [ "${1:-}" = "--force" ] && force=1

[ -f "$src" ] || { echo "setup-emulators: no System 6 disk at $src (set SHIORI_SYS6_IMAGE)" >&2; exit 1; }
[ -f "$rom" ] || { echo "setup-emulators: no Mac Plus ROM at $rom (set SHIORI_PLUS_ROM)" >&2; exit 1; }
if pgrep -x snowemu >/dev/null; then
    echo "setup-emulators: Snow is running; quit it first (its disk is memory-mapped)" >&2; exit 1
fi
mkdir -p "$out"
if [ -f "$img" ] && [ $force = 0 ]; then
    echo "setup-emulators: $img exists (--force replaces it)"
else
    cp "$src" "$img"
    hmount "$img" >/dev/null
    # keep only the system's own items at the top level
    rmtree() {
        local d=$1 n
        hls -a1 "$d" | while IFS= read -r n; do
            [ -n "$n" ] || continue
            if [ "$(hls -ld "$d:$n" | cut -c1)" = d ]; then rmtree "$d:$n"; else hdel "$d:$n"; fi
        done
        hrmdir "$d"
    }
    hls -a1 ":" | while IFS= read -r n; do
        case $n in "System Folder"|"Desktop Folder"|"Trash"|"TeachText"|"") ;;
        *) if [ "$(hls -ld ":$n" | cut -c1)" = d ]; then rmtree ":$n"; else hdel ":$n"; fi ;;
        esac
    done
    humount >/dev/null
    echo "setup-emulators: made $img"
fi
cat > "$out/shiori.snoww" <<JSON
{
  "viewport_scale": 1.5,
  "rom_path": "$rom",
  "scsi_targets": [
    {"Disk": "shiori-sys608.img"},
    "None",
    "None",
    "Ethernet",
    "None",
    "None",
    "None"
  ],
  "model": "Plus",
  "map_cmd_ralt": true,
  "scaling_algorithm": "NearestNeighbor",
  "framebuffer_mode": "Centered",
  "shader_configs": []
}
JSON
echo "setup-emulators: wrote $out/shiori.snoww"
hubprefs="$EMU/basilisk/basilisk_ii_prefs"
[ -f "$hubprefs" ] || { echo "setup-emulators: no Basilisk II prefs at $hubprefs" >&2; exit 1; }
src7=${SHIORI_SYS7_IMAGE:-$EMU/disks/system7.hda}
img7="$out/shiori-sys761.hda"
if pgrep -x BasiliskII >/dev/null; then
    echo "setup-emulators: Basilisk II is running; quit it first" >&2; exit 1
fi
if [ ! -f "$img7" ] || [ $force = 1 ]; then
    [ -f "$src7" ] || { echo "setup-emulators: no System 7 disk at $src7 (set SHIORI_SYS7_IMAGE)" >&2; exit 1; }
    cp "$src7" "$img7"
    echo "setup-emulators: made $img7 (set its TCP/IP to DHCP once: docs/TESTING.md)"
fi
sed -e 's/^ether .*/ether slirp/' -e "s#^disk .*#disk $img7#" "$hubprefs" > "$out/basilisk_prefs"
grep -q '^ether slirp' "$out/basilisk_prefs" || echo "ether slirp" >> "$out/basilisk_prefs"
echo "setup-emulators: wrote $out/basilisk_prefs (ether slirp)"
mkdir -p "$EMU/unix/Shiori"
echo "setup-emulators: Basilisk II gets Shiori in $EMU/unix/Shiori"
