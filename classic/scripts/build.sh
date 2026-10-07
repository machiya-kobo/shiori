#!/bin/bash
# Builds Shiori for Classic Macintosh with Retro68: classic/build/Shiori.{bin,dsk,APPL}.
#   classic/scripts/build.sh            # RETRO68 defaults to the emulator hub's toolchain
# Default settings (until Preferences has them) come from classic/local.env (gitignored), e.g.
#   SHIORI_DEFAULT_HISTER=http://<bridge>:8070/  SHIORI_DEFAULT_KURA=http://<bridge>:8071/  SHIORI_DEFAULT_TOKEN=mht_…
# SHIORI_RELEASE=1 (package.sh) ignores local.env and the environment's defaults, and
# builds in classic/build-release: a release carries the neutral defaults only.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "$here/.." && pwd)"
RETRO68=${RETRO68:-$HOME/emulators/tools/retro68-build/toolchain}
toolchain="$RETRO68/m68k-apple-macos/cmake/retro68.toolchain.cmake"
[ -f "$toolchain" ] || { echo "build.sh: no Retro68 toolchain at $RETRO68 (set RETRO68)" >&2; exit 1; }
if [ "${SHIORI_RELEASE:-0}" = 1 ]; then
    unset SHIORI_DEFAULT_HISTER SHIORI_DEFAULT_KURA SHIORI_DEFAULT_TOKEN
    build="$here/build-release"
else
    [ -f "$here/local.env" ] && set -a && . "$here/local.env" && set +a
    build="$here/build"
fi
version=$(sed -nE 's/^ *MARKETING_VERSION: *"?([0-9.]+)"?.*/\1/p' "$root/project.yml" | head -1)
mkdir -p "$build"
cmake -S "$here" -B "$build" -DCMAKE_TOOLCHAIN_FILE="$toolchain" -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DSHIORI_VERSION="${version:-0.0.0-dev}" \
    -DSHIORI_DEFAULT_HISTER="${SHIORI_DEFAULT_HISTER:-}" -DSHIORI_DEFAULT_KURA="${SHIORI_DEFAULT_KURA:-}" \
    -DSHIORI_DEFAULT_TOKEN="${SHIORI_DEFAULT_TOKEN:-}" >/dev/null
cmake --build "$build" -- -j"$(nproc 2>/dev/null || echo 2)"
ls -l "$build/Shiori.bin" "$build/Shiori.dsk"
# A desk accessory's DRVR must stay under 32 KB (its offsets are 16-bit).
da_size=$(wc -c < "$build/ShioriDA.flt")
echo "build.sh: Shiori Search (the DA) is $da_size bytes of 32768"
[ "$da_size" -lt 32768 ] || { echo "build.sh: the desk accessory is over 32 KB" >&2; exit 1; }
