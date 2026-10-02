#!/bin/zsh
# Build Shiori and install it on an iPhone/iPad.
# Usage: scripts/deploy-device.sh   (device unlocked; USB or the network tunnel)
#
# DEVICE_NAME comes from local.env (gitignored):
#   cp local.env.example local.env
# Signing needs DEVELOPMENT_TEAM in local.yml. With a free personal team
# the provisioning expires after 7 days: rerun weekly.
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

# Caller env beats the file.
DEVICE_NAME_ENV=${DEVICE_NAME-}
[[ -f local.env ]] && source local.env
[[ -n "$DEVICE_NAME_ENV" ]] && DEVICE_NAME=$DEVICE_NAME_ENV
if [[ -z "${DEVICE_NAME:-}" ]]; then
  echo "No device configured. Set DEVICE_NAME in local.env (cp local.env.example local.env)."
  exit 1
fi

scripts/build-extension.sh

echo "→ Regenerating Xcode project"
xcodegen generate --quiet

# A clean product, so the appex is re-signed after its web resources are
# copied in (see install-mac.sh).
rm -rf build/Build/Products/Debug-iphoneos/Shiori.app build/Build/Products/Debug-iphoneos/*.appex(N)

echo "→ Building for ${DEVICE_NAME}"
xcodebuild -project Shiori.xcodeproj -scheme Shiori \
  -destination "platform=iOS,name=${DEVICE_NAME}" \
  -derivedDataPath build \
  -allowProvisioningUpdates \
  build

APP=build/Build/Products/Debug-iphoneos/Shiori.app
codesign --verify --deep --strict "$APP" || { echo "error: the built app's signature is invalid; not installing" >&2; exit 1; }
echo "→ Installing on ${DEVICE_NAME}"
# Any install failure other than "unavailable": `pkill -f CoreDeviceService`
# and rerun.
xcrun devicectl device install app --device "${DEVICE_NAME}" "${APP}"

echo
echo "Reinstalling resets Shiori's website permission, with no prompt. On the device:"
echo "  Settings → Apps → Safari → Extensions → Shiori → All Websites → Allow"
