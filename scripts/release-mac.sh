#!/usr/bin/env bash
# Builds the Mac app for a GitHub release: a disk image anyone can test.
#
#   scripts/release-mac.sh [TAG] [OUT_DIR]   (default: the latest v* tag, ./release)
#
# The build is made in a fresh worktree of TAG, never this checkout, so
# nothing of yours goes in: its local.yml holds only the public bundle
# prefix (RELEASE_BUNDLE_PREFIX, default io.github.machiya-kobo). No
# server, no Kura, no vault name, no room logos, no team: it's signed ad
# hoc, so no certificate or team ID is embedded either. Without a
# Developer ID it isn't notarized, and Safari runs its extension only with
# Develop → Allow Unsigned Extensions (the release notes say how).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

TAG=${1:-$(git describe --tags --abbrev=0 --match 'v*')}
OUT=$(mkdir -p "${2:-release}" && cd "${2:-release}" && pwd)
PREFIX=${RELEASE_BUNDLE_PREFIX:-io.github.machiya-kobo}
VERSION=${TAG#v}
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "No tag $TAG." >&2; exit 1; }

WT=$(mktemp -d "${TMPDIR:-/tmp}/shiori-release.XXXXXX")
cleanup() {
  # Any Mac build registers its extensions: unregister this one's, or
  # Safari and the share menu list it beside the installed app.
  for appex in "$WT"/build/Build/Products/*/Shiori.app/Contents/PlugIns/*.appex; do
    [[ -d "$appex" ]] && pluginkit -r "$appex" 2>/dev/null || true
  done
  git -C "$ROOT" worktree remove --force "$WT" 2>/dev/null || rm -rf "$WT"
}
trap cleanup EXIT

echo "==> Worktree of $TAG"
git worktree add --detach "$WT" "$TAG" >/dev/null
git -C "$WT" submodule update --init --reference "$ROOT/vendor/hister" vendor/hister >/dev/null 2>&1 \
  || git -C "$WT" submodule update --init vendor/hister >/dev/null

# The example with only the prefix filled in: every other value stays empty.
sed "s|^\( *SHIORI_BUNDLE_PREFIX:\).*|\1 \"$PREFIX\"|" local.yml.example > "$WT/local.yml"
grep -q "SHIORI_BUNDLE_PREFIX: \"$PREFIX\"" "$WT/local.yml" || { echo "Couldn't set the prefix." >&2; exit 1; }

cd "$WT"
# Only what the worktree says: nothing from this shell's environment.
for v in $(env | sed -n 's/^\(SHIORI_[A-Z_]*\)=.*/\1/p; s/^\(DEVELOPMENT_TEAM\)=.*/\1/p'); do unset "$v"; done
echo "==> Extension"
scripts/build-extension.sh >/dev/null
xcodegen generate --quiet
echo "==> Building Shiori $VERSION (Release, ad hoc)"
xcodebuild -project Shiori.xcodeproj -scheme Shiori-macOS -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  build | grep -E "error:|\*\* BUILD" || true
APP=build/Build/Products/Release/Shiori.app
[[ -d "$APP" ]] || { echo "Build failed." >&2; exit 1; }
codesign --verify --deep --strict "$APP"

# Checks that it is the neutral build.
team=$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')
[[ "$team" == "not set" ]] || { echo "Signed with a team ($team): not a release build." >&2; exit 1; }
built=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
[[ "$built" == "$VERSION" ]] || { echo "Built $built, not $VERSION." >&2; exit 1; }
server=$(/usr/libexec/PlistBuddy -c 'Print :ShioriDefaultServerURL' "$APP/Contents/Info.plist" 2>/dev/null || true)
[[ -z "$server" ]] || { echo "A default server is set: not a release build." >&2; exit 1; }

echo "==> Disk image"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/shiori-dmg.XXXXXX")
ditto "$APP" "$STAGE/Shiori.app"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/Shiori-$VERSION-macOS.dmg"
rm -f "$DMG"
hdiutil create -quiet -volname "Shiori $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
rm -rf "$STAGE"
echo "Wrote $DMG"
