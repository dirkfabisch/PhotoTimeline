#!/bin/zsh
# Builds a Developer ID signed, notarized and stapled release and zips it.
# With --publish it also tags the version and uploads the zip as a GitHub release.
#
# One-time setup:
#   cp scripts/release.env.example scripts/release.env   # then fill in your team ID
#   xcrun notarytool store-credentials <profile> --apple-id <apple-id> --team-id <team-id>
#
# Usage: scripts/release.sh [--publish]
set -euo pipefail

cd "${0:A:h}/.."
[[ -f scripts/release.env ]] || { echo "scripts/release.env fehlt – siehe scripts/release.env.example" >&2; exit 1; }
source scripts/release.env
: "${TEAM_ID:?TEAM_ID in scripts/release.env setzen}" "${NOTARY_PROFILE:?NOTARY_PROFILE in scripts/release.env setzen}"

PUBLISH=false
[[ "${1:-}" == "--publish" ]] && PUBLISH=true

VERSION=$(xcodebuild -scheme PhotoTimeline -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ MARKETING_VERSION = / { print $2; exit }')
TAG="v$VERSION"
APP=build/Build/Products/Release/PhotoTimeline.app
SUBMIT=build/PhotoTimeline-notarize.zip
OUT=build/PhotoTimeline-$VERSION.zip

if $PUBLISH; then
  [[ -z "$(git status --porcelain)" ]] || { echo "Arbeitsbaum nicht sauber – erst committen" >&2; exit 1; }
  git fetch -q origin
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse @{u})" ]] || { echo "HEAD ist nicht gepusht" >&2; exit 1; }
  ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "Tag $TAG existiert schon – Version erhöhen" >&2; exit 1; }
fi

echo "→ Build $VERSION (Release, arm64, Developer ID)"
xcodebuild -scheme PhotoTimeline -configuration Release -derivedDataPath build build -quiet \
  CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS=--timestamp

echo "→ Signatur prüfen"
codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E "^TeamIdentifier|^Runtime Version|^Timestamp"

echo "→ Notarisieren (dauert meist 1–5 Minuten)"
rm -f "$SUBMIT"
ditto -c -k --keepParent "$APP" "$SUBMIT"
xcrun notarytool submit "$SUBMIT" --keychain-profile "$NOTARY_PROFILE" --wait

echo "→ Ticket anheften"
xcrun stapler staple "$APP"

echo "→ Gatekeeper-Prüfung"
spctl --assess --type execute --verbose=2 "$APP"

echo "→ ZIP"
rm -f "$OUT"
ditto -c -k --keepParent "$APP" "$OUT"
echo "Fertig: $OUT"

if $PUBLISH; then
  echo "→ GitHub-Release $TAG"
  git tag -a "$TAG" -m "Photo Timeline $VERSION"
  git push -q origin "$TAG"
  gh release create "$TAG" "$OUT" --title "Photo Timeline $VERSION" --generate-notes --verify-tag
fi
