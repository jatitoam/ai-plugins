#!/usr/bin/env bash
# Bump a plugin's version at every client and registry sync point.
# Usage: ./scripts/bump.sh <plugin-id> <major|minor|patch>
set -euo pipefail
exec python3 "$(dirname "$0")/marketplace.py" bump "$@"
