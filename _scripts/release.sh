#!/usr/bin/env bash
#
# release.sh — build the shippable app and zip it into build/.
#
# The app is signed ad hoc: it runs on the machine that built it and on any other after the user
# clears the quarantine flag. A Developer ID identity, when one is available, goes in Local.xcconfig
# as CODE_SIGN_IDENTITY and is picked up here without changing this script.
#
# Usage:
#   _scripts/release.sh
#   _scripts/release.sh --skip-checks
#
# Copyright (c) 2026 Alex Babaev. MIT licence — see LICENSE.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO/build"
CHECKS=1

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-checks) CHECKS=0 ;;
    -h | --help)
      sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's|^# \{0,1\}||'
      exit 0
      ;;
    *)
      echo "release: unknown option $1" >&2
      exit 2
      ;;
  esac
  shift
done

cd "$REPO"

if [ "$CHECKS" -eq 1 ]; then
  "$REPO/_scripts/check.sh"
  "$REPO/_scripts/test.sh"
fi

command -v xcodegen >/dev/null 2>&1 && xcodegen generate --quiet

rm -rf "$OUT"
mkdir -p "$OUT"

xcodebuild -project GrimDawner.xcodeproj -scheme GrimDawner -configuration Release \
  -derivedDataPath "$OUT/DerivedData" build | grep -E "error:|BUILD" || true

APP="$OUT/DerivedData/Build/Products/Release/GrimDawner.app"
[ -d "$APP" ] || {
  echo "release ❌ no app at $APP" >&2
  exit 1
}

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")"
ARCHIVE="$OUT/GrimDawner-$VERSION($BUILD).zip"

cp -R "$APP" "$OUT/GrimDawner.app"
ditto -c -k --keepParent "$OUT/GrimDawner.app" "$ARCHIVE"
rm -rf "$OUT/DerivedData"

codesign --verify --deep --strict "$OUT/GrimDawner.app" && echo "release ✅ signature verifies"
echo "release ✅ $ARCHIVE"
