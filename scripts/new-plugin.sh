#!/usr/bin/env bash
# Scaffold a plugin and register it in both client marketplaces.
# Usage: ./scripts/new-plugin.sh <plugin-id> "<display name>" "<description>"
set -euo pipefail
exec python3 "$(dirname "$0")/marketplace.py" new-plugin "$@"
