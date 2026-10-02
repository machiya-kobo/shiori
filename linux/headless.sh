#!/bin/sh
# Runs Shiori for Linux on a virtual display and screenshots it, for tests
# over SSH (docs/linux.md). Never a real user's session.
#
#   [SHIORI_TYPE=words] [SHIORI_RUN=command] linux/headless.sh OUT.png [shiori arguments…]
#   (SHIORI_TYPE is typed into the window after it opens, e.g. for --quick;
#   SHIORI_RUN="flatpak run io.github.machiya_kobo.Shiori" runs the Flatpak instead
#   of the checkout)
#
# A GTK app needs a session bus (an SSH login has none) and, without a
# GPU on Xvfb, software rendering; the bus goes inside the display, so the
# desktop portal can open it.
set -eu
out=${1:?usage: headless.sh OUT.png [arguments…]}
shift
cd "$(dirname "$0")/.."
exec xvfb-run -a -s "-screen 0 1280x800x24" sh -c '
  out=$1; shift
  export GSK_RENDERER=cairo LIBGL_ALWAYS_SOFTWARE=1
  dbus-run-session -- sh -c "\${SHIORI_RUN:-gjs -m linux/gjs/main.js} \"\$@\" & p=\$!; sleep 4; [ -n \"\${SHIORI_TYPE:-}\" ] && xdotool type --delay 60 \"\$SHIORI_TYPE\"; sleep \${SHIORI_WAIT:-15}; import -window root \"$out\"; kill \$p" sh "$@"
' sh "$out" "$@"
