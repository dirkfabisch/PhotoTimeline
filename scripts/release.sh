#!/bin/zsh
# Builds a Developer ID signed, notarized release with a signed Sparkle appcast.
# The version comes from the git tag (scripts/versionupdate.sh), so the tag is set first.
#
# One-time setup:
#   cp scripts/release.env.example scripts/release.env        # then fill in your team ID
#   xcrun notarytool store-credentials <profile> --apple-id <apple-id> --team-id <team-id>
#   <Sparkle bin>/generate_keys                                # EdDSA key in your keychain
#
# Usage: scripts/release.sh <version> [--publish] [--notes <file.md>]
#   without --publish: builds and checks everything, then removes the local tag again
#   with --publish:    pushes the tag and creates the GitHub release with zip + appcast.xml
set -euo pipefail

cd "${0:A:h}/.."
[[ -f scripts/release.env ]] || { echo "scripts/release.env fehlt – siehe scripts/release.env.example" >&2; exit 1; }
source scripts/release.env
: "${TEAM_ID:?TEAM_ID in scripts/release.env setzen}" "${NOTARY_PROFILE:?NOTARY_PROFILE in scripts/release.env setzen}"

VERSION=${1:-}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Aufruf: scripts/release.sh <X.Y.Z> [--publish] [--notes <datei.md>]" >&2; exit 1; }
shift
PUBLISH=false
NOTES_FILE=
while (( $# )); do
  case $1 in
    --publish) PUBLISH=true ;;
    --notes) NOTES_FILE=$2; shift ;;
    *) echo "Unbekannte Option: $1" >&2; exit 1 ;;
  esac
  shift
done

REPO=dirkfabisch/PhotoTimeline
TAG="v$VERSION"
BUILD=$(git rev-list HEAD --count)
ARCHIVE=build/PhotoTimeline.xcarchive
EXPORT=build/export
APP=$EXPORT/PhotoTimeline.app
OUT=build/release-$VERSION
ZIP=$OUT/PhotoTimeline-$VERSION.zip
NOTES=$OUT/PhotoTimeline-$VERSION.md
SPARKLE_BIN=build/SourcePackages/artifacts/sparkle/Sparkle/bin

[[ -z "$(git status --porcelain)" ]] || { echo "Arbeitsbaum nicht sauber – erst committen" >&2; exit 1; }
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "Tag $TAG existiert schon" >&2; exit 1; }
if $PUBLISH; then
  git fetch -q --tags origin
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse @{u})" ]] || { echo "HEAD ist nicht gepusht" >&2; exit 1; }
  ! git ls-remote --exit-code --tags origin "$TAG" >/dev/null || { echo "Tag $TAG existiert schon auf GitHub" >&2; exit 1; }
fi
PREVIOUS_TAG=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)

# The tag must exist before building; remove it again unless it was pushed.
TAG_PUSHED=false
cleanup() { $TAG_PUSHED || git tag -d "$TAG" >/dev/null 2>&1 || true }
trap cleanup EXIT
git tag -a "$TAG" -m "Photo Timeline $VERSION"

echo "→ Archive $VERSION ($BUILD)"
rm -rf "$ARCHIVE" "$EXPORT" "$OUT"
xcodebuild archive -scheme PhotoTimeline -configuration Release -archivePath "$ARCHIVE" -derivedDataPath build -quiet \
  ARCHS=arm64 CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM_ID"

echo "→ Export mit Developer ID"
EXPORT_OPTIONS=build/ExportOptions.plist
cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
  <key>teamID</key><string>$TEAM_ID</string>
</dict></plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" -exportOptionsPlist "$EXPORT_OPTIONS" -quiet

echo "→ Prüfen"
plist=$APP/Contents/Info.plist
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" == "$VERSION" ]] || { echo "Version im Bundle ≠ $VERSION" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" == "$BUILD" ]] || { echo "Build im Bundle ≠ $BUILD" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
# Capture first: grep -q would close the pipe early and pipefail would report codesign as failed.
for item in "$APP" "$APP"/Contents/Frameworks/Sparkle.framework "$APP"/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/*.xpc; do
  info=$(codesign -dvv "$item" 2>&1)
  [[ "$info" == *"Authority=Developer ID Application: "*"($TEAM_ID)"* && "$info" == *"Timestamp="* ]] \
    || { echo "Nicht mit Developer ID + Zeitstempel signiert: $item" >&2; exit 1; }
done
[[ "$(lipo -archs "$APP/Contents/MacOS/PhotoTimeline")" == "arm64" ]] || { echo "Nicht nur arm64" >&2; exit 1; }
entitlements=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)
[[ "$entitlements" != *get-task-allow* ]] || { echo "get-task-allow im Release" >&2; exit 1; }
echo "  $VERSION ($BUILD), arm64, Developer ID, Sparkle-Dienste signiert"

echo "→ Notarisieren (dauert meist 1–5 Minuten)"
mkdir -p "$OUT"
ditto -c -k --keepParent "$APP" build/PhotoTimeline-notarize.zip
xcrun notarytool submit build/PhotoTimeline-notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"

echo "→ ZIP, Release Notes, Appcast"
ditto -c -k --keepParent "$APP" "$ZIP"
if [[ -n "$NOTES_FILE" ]]; then
  cp "$NOTES_FILE" "$NOTES"
else
  { echo "## Photo Timeline $VERSION"; echo
    git log --no-merges --format='- %s' ${PREVIOUS_TAG:+$PREVIOUS_TAG..}HEAD; } > "$NOTES"
fi
"$SPARKLE_BIN/generate_appcast" "$OUT" --embed-release-notes \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
  --link "https://github.com/$REPO" -o "$OUT/appcast.xml"
appcast=$(<"$OUT/appcast.xml")
[[ "$appcast" == *"sparkle:edSignature"* ]] || { echo "Appcast nicht signiert" >&2; exit 1; }
echo "Fertig: $OUT"

if $PUBLISH; then
  echo "→ GitHub-Release $TAG"
  git push -q origin "$TAG"
  TAG_PUSHED=true
  gh release create "$TAG" "$ZIP" "$OUT/appcast.xml" -R "$REPO" \
    --title "Photo Timeline $VERSION" --notes-file "$NOTES" --verify-tag
else
  echo "(Ohne --publish: lokaler Tag $TAG wird wieder entfernt)"
fi
