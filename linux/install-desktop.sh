#!/bin/sh
# Installs Shiori's desktop pieces for the user running it (docs/linux.md):
#   - ~/.local/bin/shiori, the launcher (the Flatpak when it's installed,
#     else this checkout under GJS);
# and, on Cinnamon only:
#   - the menu's search provider (~/.local/share/cinnamon/search_providers/
#     shiori@machiya-kobo.github.io), switched on;
#   - one custom keyboard shortcut for the quick-search window
#     (Ctrl+Alt+Space unless SHIORI_HOTKEY says otherwise).
# Those two change the RUNNING desktop session's settings (gsettings talks
# to the session's own dconf, whatever HOME says); nothing else in them is
# changed, and --remove undoes it. Without Cinnamon's settings schemas
# only the launcher is installed.
#
#   linux/install-desktop.sh            install
#   linux/install-desktop.sh --remove   take it all out again
set -eu
case "${1:-}" in
  ""|--remove) ;;
  *) echo "usage: install-desktop.sh [--remove]" >&2; exit 2 ;;
esac
# Works from any directory: the repository is this script's parent's parent.
cd "$(dirname "$0")/.."
here=$(pwd)
uuid=shiori@machiya-kobo.github.io
if [ ! -d "linux/cinnamon/$uuid" ]; then
  echo "install-desktop.sh: run it from a Shiori checkout (linux/install-desktop.sh), not a copy" >&2
  exit 1
fi
bin="$HOME/.local/bin/shiori"
providers="${XDG_DATA_HOME:-$HOME/.local/share}/cinnamon/search_providers"
provider="$providers/$uuid"
hotkey=${SHIORI_HOTKEY:-<Primary><Alt>space}
keypath=/org/cinnamon/desktop/keybindings/custom-keybindings/shiori-quick/

# Cinnamon's settings, or none: then the launcher alone.
cinnamon=
if command -v gsettings >/dev/null 2>&1 && gsettings list-schemas 2>/dev/null | grep -qx org.cinnamon \
  && gsettings list-schemas 2>/dev/null | grep -qx org.cinnamon.desktop.keybindings; then
  cinnamon=1
fi

# A string list from gsettings, as one item per line.
list() { gsettings get "$1" "$2" | sed "s/^@as //; s/^\[//; s/\]$//; s/, /\n/g; s/'//g" | sed '/^$/d'; }
# One per line back to gsettings' "['a', 'b']".
join() { printf "["; sed "s/.*/'&'/" | paste -sd, - | sed 's/,/, /g' | tr -d '\n'; printf "]"; }
# The enabled providers without any of Shiori's (the uuid was another
# shiori@… before 0.5.5); grep -v exits 1 on an empty result.
providers_without_shiori() { list org.cinnamon enabled-search-providers | { grep -v '^shiori@' || true; }; }
# Shiori's provider folders under any uuid, the current one included.
remove_providers() { for dir in "$providers"/shiori@*; do [ -e "$dir" ] && rm -rf "$dir"; done; return 0; }

if [ "${1:-}" = "--remove" ]; then
  if [ -n "$cinnamon" ]; then
    providers_without_shiori | join | xargs -0 gsettings set org.cinnamon enabled-search-providers
    list org.cinnamon.desktop.keybindings custom-list | { grep -vx shiori-quick || true; } | join | xargs -0 gsettings set org.cinnamon.desktop.keybindings custom-list
    gsettings reset-recursively "org.cinnamon.desktop.keybindings.custom-keybinding:$keypath" 2>/dev/null || true
  fi
  remove_providers
  rm -f "$bin"
  echo "Removed Shiori's launcher${cinnamon:+, search provider and shortcut}."
  exit 0
fi

mkdir -p "$HOME/.local/bin"
# The Flatpak (io.github.machiya_kobo.Shiori), else this checkout under GJS.
app=
if command -v flatpak >/dev/null 2>&1 && flatpak info io.github.machiya_kobo.Shiori >/dev/null 2>&1; then app=io.github.machiya_kobo.Shiori; fi
if [ -n "$app" ]; then
  printf '#!/bin/sh\nexec flatpak run %s "$@"\n' "$app" > "$bin"
else
  printf '#!/bin/sh\nexec gjs -m "%s/linux/gjs/main.js" "$@"\n' "$here" > "$bin"
fi
chmod +x "$bin"

if [ -z "$cinnamon" ]; then
  echo "Installed: $bin. No Cinnamon settings here, so no menu search or hotkey."
  echo "Config: ~/.config/shiori/config.json with webApp, server and kura."
  exit 0
fi

# The provider, under its current uuid; one under an older uuid goes.
mkdir -p "$providers"
remove_providers
cp -R "linux/cinnamon/$uuid" "$provider"
current=$(providers_without_shiori)
printf '%s\n%s\n' "$current" "$uuid" | sed '/^$/d' | awk '!seen[$0]++' | join | xargs -0 gsettings set org.cinnamon enabled-search-providers

gsettings set "org.cinnamon.desktop.keybindings.custom-keybinding:$keypath" name "Shiori Quick Search"
gsettings set "org.cinnamon.desktop.keybindings.custom-keybinding:$keypath" command "$bin --quick"
gsettings set "org.cinnamon.desktop.keybindings.custom-keybinding:$keypath" binding "['$hotkey']"
current=$(list org.cinnamon.desktop.keybindings custom-list)
printf '%s\n%s\n' "$current" shiori-quick | sed '/^$/d' | awk '!seen[$0]++' | join | xargs -0 gsettings set org.cinnamon.desktop.keybindings custom-list

echo "Installed: $bin, the menu's Shiori search, and $hotkey for Quick Search (in this desktop session; --remove undoes it)."
echo "Config: ~/.config/shiori/config.json with webApp, server and kura."
