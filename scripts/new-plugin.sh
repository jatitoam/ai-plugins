#!/usr/bin/env bash
# Scaffold a new plugin and register it in index.yaml and marketplace.json.
# Usage: ./scripts/new-plugin.sh <plugin-id> "<display name>" "<description>"
set -euo pipefail
exec python3 "$(dirname "$0")/marketplace.py" new-plugin "$@"
