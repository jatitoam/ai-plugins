#!/usr/bin/env bash
# Check the marketplace for consistency. Run before every commit.
#
# Two layers:
#   1. marketplace.py validate — generic, repo-wide registry/version/skill checks
#      that know nothing about any individual plugin.
#   2. Per-plugin contract tests — every executable plugins/<id>/tests/check-*
#      is run in turn. This is where a plugin guards its own invariants, so
#      plugin-specific assertions stay out of the shared tooling.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(dirname "$here")"
status=0

python3 "$here/marketplace.py" validate "$@" || status=1

shopt -s nullglob
for test in "$repo"/plugins/*/tests/check-*; do
  [ -f "$test" ] || continue
  if [ ! -x "$test" ]; then
    echo "FAIL  ${test#"$repo"/}: contract test is not executable (chmod +x it)" >&2
    status=1
    continue
  fi
  "$test" || status=1
done

exit "$status"
