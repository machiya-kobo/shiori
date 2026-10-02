#!/bin/sh
# Installs Shiori's desktop pieces for the user running it, in their own
# Cinnamon session (docs/linux.md):
#   - ~/.local/bin/shiori, the launcher (the Flatpak when it's installed,
#     else this checkout under GJS);
#   - the menu's search provider (~/.local/share/cinnamon/search_providers/
#     shiori@machiya-kobo.github.io), switched on;
#   - one custom keyboard shortcut for the quick-search window
#     (Ctrl+Alt+Space unless SHIORI_HOTKEY says otherwise).
# Nothing else in the Cinnamon settings is changed.
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
if [ ! -d "linux/cinnamon/shiori@machiya-kobo.github.io" ]; then
  echo "install-desktop.sh: run it from a Shiori checkout (linux/install-desktop.sh), not a copy" >&2
  exit 1
fi
uuid=shiori@machiya-kobo.github.io
bin="$HOME/.local/bin/shiori"
provider="${XDG_DATA_HOME:-$HOME/.local/share}/cinnamon/search_providers/$uuid"
hotkey=${SHIORI_HOTKEY:-<Primary><Alt>space}
keypath=/org/cinnamon/desktop/keybindings/custom-keybindings/shiori-quick/

# A string list from gsettings, as one item per line.
list() { gsettings get "$1" "$2" | sed "s/^@as //; s/^\[//; s/\]$//; s/, /\n/g; s/'//g" | sed '/^$/d'; }
# One per line back to gsettings' "['a', 'b']".
join() { printf "["; sed "s/.*/'&'/" | paste -sd, - | sed 's/,/, /g' | tr -d '\n'; printf "]"; }

if [ "${1:-}" = "--remove" ]; then
  list org.cinnamon enabled-search-providers | grep -vx "$uuid" | join | xargs -0 gsettings set org.cinnamon enabled-search-providers
  list org.cinnamon.desktop.keybindings custom-list | grep -vx shiori-quick | join | xargs -0 gsettings set org.cinnamon.desktop.keybindings custom-list
  gsettings reset-recursively "org.cinnamon.desktop.keybindings.custom-keybinding:$keypath" 2>/dev/null || true
  rm -rf "$provider" "$bin"
  echo "Removed Shiori's search provider, shortcut and launcher."
  exit 0
fi

mkdir -p "$HOME/.local/bin" "$(dirname "$provider")"
# The Flatpak (io.github.machiya_kobo.Shiori), else this checkout under GJS.
app=
if flatpak info io.github.machiya_kobo.Shiori >/dev/null 2>&1; then app=io.github.machiya_kobo.Shiori; fi
if [ -n "$app" ]; then
  printf '#!/bin/sh\nexec flatpak run %s "$@"\n' "$app" > "$bin"
else
  printf '#!/bin/sh\nexec gjs -m "%s/linux/gjs/main.js" "$@"\n' "$here" > "$bin"
fi
chmod +x "$bin"

rm -rf "$provider"
cp -R "linux/cinnamon/$uuid" "$provider"
current=$(list org.cinnamon enabled-search-providers)
printf '%s\n%s\n' "$current" "$uuid" | sed '/^$/d' | awk '!seen[$0]++' | join | xargs -0 gsettings set org.cinnamon enabled-search-providers

gsettings set "org.cinnamon.desktop.keybindings.custom-keybinding:$keypath" name "Shiori Quick Search"
gsettings set "org.cinnamon.desktop.keybindings.custom-keybinding:$keypath" command "$bin --quick"
gsettings set "org.cinnamon.desktop.keybindings.custom-keybinding:$keypath" binding "['$hotkey']"
current=$(list org.cinnamon.desktop.keybindings custom-list)
printf '%s\n%s\n' "$current" shiori-quick | sed '/^$/d' | awk '!seen[$0]++' | join | xargs -0 gsettings set org.cinnamon.desktop.keybindings custom-list

echo "Installed: $bin, the menu's Shiori search, and $hotkey for Quick Search."
echo "Config: ~/.config/shiori/config.json with webApp, server and kura."
