#!/usr/bin/env bash
#
# test.sh — run the engine's test suite.
#
# The tests live with the engine package, so they run on their own: no app is built and none is
# launched.
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

cd "$REPO/Engine"

set +e
swift test $([ "$CONFIG" = "Release" ] && echo "-c release") 2>&1 |
  sed 's/\x1b\[[0-9;]*m//g' |
  grep -E "error:|Test run with|failed|✘"
STATUS=${PIPESTATUS[0]}
set -e

[ "$STATUS" -eq 0 ] && echo "test ✅" || echo "test ❌"
exit "$STATUS"
