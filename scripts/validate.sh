#!/usr/bin/env bash
# Check the marketplace for consistency. Run before every commit.
set -euo pipefail
exec python3 "$(dirname "$0")/marketplace.py" validate "$@"
