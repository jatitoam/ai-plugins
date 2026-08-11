#!/usr/bin/env bash
# Bump a plugin's version in all five places at once.
# Usage: ./scripts/bump.sh <plugin-id> <major|minor|patch>
set -euo pipefail
exec python3 "$(dirname "$0")/marketplace.py" bump "$@"
