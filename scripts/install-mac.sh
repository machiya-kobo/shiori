#!/bin/zsh
# Build Shiori for the Mac (Release, signed with the team in local.yml)
# and install it in /Applications, replacing any earlier copy.
# Usage: scripts/install-mac.sh
#
# Afterwards, in Safari → Settings → Extensions: turn on Shiori and allow
# it on every website. If another Hister extension is on (e.g. the
# hister-safari port), turn it off, or every page is sent twice.
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
DEST=/Applications/Shiori.app

scripts/build-extension.sh

echo "→ Regenerating Xcode project"
xcodegen generate --quiet

# The icon for Finder and Launchpad (the Mac can't switch those at runtime,
# so it's built in): SHIORI_ICON if given (e.g. SHIORI_ICON=AppIcon-Light),
# else the one chosen in Shiori's Settings. macOS usually won't let a
# terminal read the app's container, so that read often finds nothing and
# the default is built in; the Dock still shows the chosen one while
# Shiori runs.
# The app's bundle ID, from the prefix in local.yml.
APP_ID="$(sed -n 's/^ *SHIORI_BUNDLE_PREFIX: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' local.yml 2>/dev/null | head -1).shiori"
[[ "$APP_ID" != ".shiori" ]] || { echo "Set SHIORI_BUNDLE_PREFIX in local.yml (see local.yml.example)." >&2; exit 1; }
ICON=${SHIORI_ICON:-$(defaults read "$HOME/Library/Containers/$APP_ID/Data/Library/Preferences/$APP_ID" macAppIcon 2>/dev/null || true)}
case "$ICON" in
  AppIcon-Light) ;;
  *) ICON=AppIcon ;;
esac
echo "→ App icon: $ICON"

# Start from a clean product: the appex's web resources are copied by a
# script phase that runs every build, but Xcode re-signs only when it sees
# other inputs change, so an incremental build can leave a stale seal
# ("a sealed resource is missing or invalid") and codesign below fails.
rm -rf build/Build/Products/Release/Shiori.app build/Build/Products/Release/*.appex(N)

echo "→ Building (Release, icon $ICON)"
xcodebuild -project Shiori.xcodeproj -scheme Shiori-macOS -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build -allowProvisioningUpdates \
  ASSETCATALOG_COMPILER_APPICON_NAME="$ICON" \
  build | grep -E "error:|warning:|\*\* BUILD" || true

APP=build/Build/Products/Release/Shiori.app
[[ -d "$APP" ]] || { echo "build failed"; exit 1; }
codesign --verify --deep --strict "$APP" || { echo "error: the built app's signature is invalid; not installing" >&2; exit 1; }

# Safari lists every registered copy of the extension, including the ones
# left in build folders by development builds; unregister those.
for stale in build/Build/Products/*/Shiori.app; do
  [[ -d "$stale/Contents/PlugIns" ]] || continue
  for appex in "$stale"/Contents/PlugIns/*.appex; do
    pluginkit -r "$appex" 2>/dev/null || true
  done
done

echo "→ Installing $DEST"
if [[ -d "$DEST" ]]; then
  osascript -e "tell application id \"$APP_ID\" to quit" 2>/dev/null || true
  # Wait for it to exit, or reopening below fails (LaunchServices -609).
  for _ in {1..20}; do
    pgrep -qf "$DEST/Contents/MacOS/Shiori" || break
    sleep 0.25
  done
  rm -rf "$DEST"
fi
ditto "$APP" "$DEST"

# Opening the app registers its extensions with Safari and the share menu.
open "$DEST" || { sleep 2; open "$DEST"; }
echo
echo "Installed. In Safari → Settings → Extensions: turn on Shiori, allow it on"
echo "every website, and turn off any other Hister extension."
