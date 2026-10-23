#!/bin/sh
set -e

# Runs as the last build phase of the app target (pattern from DailyDose2).
# Version = latest tag vX.Y.Z (without the "v"), build = number of commits on HEAD.
# Never edit the version fields in the project by hand; tag instead.

cd "${SRCROOT}"
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "warning: no git repository – keeping the version from the project"
  exit 0
fi

tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || echo "v0.0.0")
appVersion=${tag#v}
appBuild=$(git rev-list HEAD --count)
commitHash=$(git rev-parse --short HEAD)
branchName=$(git rev-parse --abbrev-ref HEAD)

if [ "$CONFIGURATION" = "Debug" ]; then
  longVersionString="$appVersion ($appBuild) – $branchName @ $commitHash"
else
  longVersionString="$appVersion ($appBuild)"
fi

plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
if [ ! -f "$plist" ]; then
  echo "warning: Info.plist not found at $plist – skipping"
  exit 0
fi

echo "Version $longVersionString → $plist"
set_key() {
  /usr/libexec/PlistBuddy -c "Set :$1 $2" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$plist"
}
set_key CFBundleVersion "$appBuild"
set_key CFBundleShortVersionString "$appVersion"
set_key CFBundleLongVersionString "$longVersionString"
