#!/usr/bin/env bash
#
# build.sh — build the app.
#
# Usage:
#   _scripts/build.sh              # Debug
#   _scripts/build.sh --release
#   _scripts/build.sh --clean
#
# Copyright (c) 2026 Alex Babaev. MIT licence — see LICENSE.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG=Debug
CLEAN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --release) CONFIG=Release ;;
    --debug) CONFIG=Debug ;;
    --clean) CLEAN=1 ;;
    -h | --help)
      sed -n '3,9p' "${BASH_SOURCE[0]}" | sed 's|^# \{0,1\}||'
      exit 0
      ;;
    *)
      echo "build: unknown option $1" >&2
      exit 2
      ;;
  esac
  shift
done

cd "$REPO"

# The project file is generated, so a source file added or removed only reaches Xcode through xcodegen.
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate --quiet
else
  echo "build ⚠️  xcodegen not installed — building the project file as it stands" >&2
fi

ACTIONS=(build)
[ "$CLEAN" -eq 1 ] && ACTIONS=(clean build)

xcodebuild -project GrimDawner.xcodeproj -scheme GrimDawner -configuration "$CONFIG" "${ACTIONS[@]}" |
  grep -E "error:|warning:|BUILD" || true

echo "build ✅ $CONFIG"
