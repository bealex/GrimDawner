#!/usr/bin/env bash
#
# test.sh — run the test suite.
#
# Usage:
#   _scripts/test.sh
#   _scripts/test.sh --release
#
# Copyright (c) 2026 Alex Babaev. MIT licence — see LICENSE.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG=Debug

while [ $# -gt 0 ]; do
  case "$1" in
    --release) CONFIG=Release ;;
    -h | --help)
      sed -n '3,8p' "${BASH_SOURCE[0]}" | sed 's|^# \{0,1\}||'
      exit 0
      ;;
    *)
      echo "test: unknown option $1" >&2
      exit 2
      ;;
  esac
  shift
done

cd "$REPO"
command -v xcodegen >/dev/null 2>&1 && xcodegen generate --quiet

set +e
xcodebuild -project GrimDawner.xcodeproj -scheme GrimDawner -configuration "$CONFIG" test |
  grep -E "error:|Test run with|failed|✘"
STATUS=${PIPESTATUS[0]}
set -e

[ "$STATUS" -eq 0 ] && echo "test ✅" || echo "test ❌"
exit "$STATUS"
