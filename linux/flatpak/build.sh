#!/bin/sh
# Builds Shiori for Linux as a Flatpak (the GNOME 49 runtime), installs it
# for the current user, and writes a single-file bundle to share:
#
#   linux/flatpak/build.sh [OUT_DIR]     (default ~/.cache/shiori-flatpak)
#
# Needs flatpak-builder and org.gnome.Sdk//49 (flatpak install --user flathub org.gnome.Sdk//49).
set -eu
cd "$(dirname "$0")/../.."
# Your cache, not /tmp: a shared /tmp is anyone's to read, and it's often
# a small tmpfs.
out=${1:-${XDG_CACHE_HOME:-$HOME/.cache}/shiori-flatpak}
mkdir -p "$out"
# Its state beside the build: flatpak-builder wants both on one filesystem,
# and /tmp often isn't the checkout's.
flatpak-builder --user --force-clean --state-dir="$out/state" --repo="$out/repo" --install "$out/build" linux/flatpak/io.github.machiya_kobo.Shiori.json
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo "$out/repo" "$out/shiori.flatpak" io.github.machiya_kobo.Shiori
echo "Installed io.github.machiya_kobo.Shiori for $(id -un); bundle: $out/shiori.flatpak"
echo "Then linux/install-desktop.sh for the menu search and the hotkey."
