#!/usr/bin/env bash
# Stage the extension, regenerate the project, and build.
# Usage: scripts/build.sh [ios|macos]   (default: ios, for the simulator)
#
# The Mac build is signed ad hoc unless DEVELOPMENT_TEAM is set in
# local.yml; an ad-hoc build needs Safari → Develop → Allow Unsigned
# Extensions after every Safari restart.
set -euo pipefail
cd "$(dirname "$0")/.."

PLATFORM="${1:-ios}"

scripts/build-extension.sh
xcodegen generate --quiet

case "$PLATFORM" in
  ios)   SCHEME=Shiori;       DEST='generic/platform=iOS Simulator' ;;
  macos) SCHEME=Shiori-macOS; DEST='platform=macOS' ;;
  *) echo "usage: $0 [ios|macos]" >&2; exit 2 ;;
esac

xcodebuild -project Shiori.xcodeproj -scheme "$SCHEME" \
  -destination "$DEST" -derivedDataPath build build
