#!/bin/zsh
# Builds a Developer ID signed, notarized and stapled release and zips it.
#
# One-time setup (stores notary credentials in the login keychain):
#   xcrun notarytool store-credentials PhotoTimeline --apple-id <apple-id> --team-id YV6CG57Z4A
#
# Usage: scripts/release.sh [output.zip]   (default: ~/Desktop/PhotoTimeline.zip)
set -euo pipefail

cd "${0:A:h}/.."
PROFILE=PhotoTimeline
OUT=${1:-$HOME/Desktop/PhotoTimeline.zip}
APP=build/Build/Products/Release/PhotoTimeline.app
SUBMIT=build/PhotoTimeline-notarize.zip

echo "→ Build (Release, arm64)"
xcodebuild -scheme PhotoTimeline -configuration Release -derivedDataPath build build -quiet

echo "→ Signatur prüfen"
codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E "^Authority=Developer ID Application|^Runtime Version|^Timestamp"

echo "→ Notarisieren (dauert meist 1–5 Minuten)"
rm -f "$SUBMIT"
ditto -c -k --keepParent "$APP" "$SUBMIT"
xcrun notarytool submit "$SUBMIT" --keychain-profile "$PROFILE" --wait

echo "→ Ticket anheften"
xcrun stapler staple "$APP"

echo "→ Gatekeeper-Prüfung"
spctl --assess --type execute --verbose=2 "$APP"

echo "→ ZIP"
rm -f "$OUT"
ditto -c -k --keepParent "$APP" "$OUT"
echo "Fertig: $OUT"
