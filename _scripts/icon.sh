#!/usr/bin/env bash
#
# icon.sh — rebuild the app icon set from the artwork in Assets/.
#
# Usage:
#   _scripts/icon.sh              # simple drawing up to 256px, which is what the Dock asks for
#   _scripts/icon.sh 128          # simple drawing only at the small sizes
#
# Copyright (c) 2026 Alex Babaev. MIT licence — see LICENSE.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$REPO/_scripts/icon.py" "${1:-256}"
