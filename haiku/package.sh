#!/bin/sh
# Builds Shiori's Haiku package (.hpkg) from a `make` build, on Haiku:
#
#   make && ./package.sh            (writes shiori-<version>-1-<arch>.hpkg here)
#
# The version is Shiori's one version (project.yml). The package holds the
# app, a Deskbar menu entry, the licence and the third-party notices; the
# netservices2 HTTP code is linked in, so it needs nothing beyond Haiku.
# Releases attach it to the tag's GitHub release.
set -eu
cd "$(dirname "$0")"
APP=$(ls objects.*/Shiori 2>/dev/null | head -1)
[ -n "$APP" ] || { echo "No build: run make first." >&2; exit 1; }
VERSION=$(sed -n 's/.*MARKETING_VERSION: *"\{0,1\}\([0-9][0-9.]*\).*/\1/p' ../project.yml | head -1)
ARCH=$(getarch 2>/dev/null || uname -m)
OUT="shiori-$VERSION-1-$ARCH.hpkg"
STAGE=$(mktemp -d /tmp/shiori-package.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/apps" "$STAGE/data/deskbar/menu/Applications" "$STAGE/documentation/packages/shiori"
cp "$APP" "$STAGE/apps/Shiori"
# The binary's resources (the icon, the version) travel with it.
ln -s ../../../../apps/Shiori "$STAGE/data/deskbar/menu/Applications/Shiori"
cp ../LICENSE "$STAGE/documentation/packages/shiori/LICENSE"
# A package's licence must be in it when Haiku doesn't carry the text (no AGPL there).
mkdir -p "$STAGE/data/licenses"
cp ../LICENSE "$STAGE/data/licenses/GNU AGPL v3"
[ -f ../THIRD_PARTY_NOTICES ] && cp ../THIRD_PARTY_NOTICES "$STAGE/documentation/packages/shiori/"

cat > "$STAGE/.PackageInfo" <<EOI
name			shiori
version			$VERSION-1
architecture	$ARCH
summary			"Search Hister and Kura (Machiya)"
description		"Shiori for Haiku: a native client for a Hister server and Kura's notes. Search your saved pages and notes, preview a note, save a web page to Hister, and quick-search from the Deskbar."
packager		"machiya-kobo <https://github.com/machiya-kobo>"
vendor			"machiya-kobo"
copyrights		{
	"The Shiori authors"
}
licenses		{
	"GNU AGPL v3"
}
urls			{
	"https://github.com/machiya-kobo/shiori"
}
provides		{
	shiori = $VERSION
	app:Shiori = $VERSION
}
requires		{
	haiku
}
EOI

rm -f "$OUT"
# A failed create leaves a truncated file: never keep it.
package create -C "$STAGE" "$OUT" || { rm -f "$OUT"; exit 1; }
package list "$OUT" >/dev/null
echo "$OUT"
