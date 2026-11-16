#!/usr/bin/env bash
# claude-move / unpack.sh — apply claude-move archives found NEXT TO THIS SCRIPT
# (i.e. in the --dest folder pack.sh wrote to; run it from that same path on the
# receiving laptop) into this laptop's Claude config dir.
# Never deletes; every overwrite is backed up.
#
# Usage: unpack.sh [--dry-run] [--force] [archive.tar.gz ...]
#   no archives given -> every claude-move_*.tar.gz not yet applied on THIS host
#   --force           -> also re-apply already-applied archives / ones packed on this host
#
# Merge rules per file:
#   missing here                -> copy
#   identical                   -> skip
#   */memory/MEMORY.md          -> union: append index lines missing here (backup first)
#   incoming newer (mtime)      -> backup local copy, then overwrite
#   local newer                 -> keep local; incoming saved under backups/…/incoming-older/
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOST="$(hostname -s)"
APPLIED="$HERE/.applied-$HOST"
DRY=0 FORCE=0 ARCHIVES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) ARCHIVES+=("$1") ;;
  esac
  shift
done

[[ -d $CFG ]] || die "config dir $CFG not found (set CLAUDE_CONFIG_DIR?)"
touch "$APPLIED" 2>/dev/null || true

if [[ ${#ARCHIVES[@]} -eq 0 ]]; then
  while IFS= read -r a; do ARCHIVES+=("$a"); done < <(ls -1 "$HERE"/claude-move_*.tar.gz 2>/dev/null || true)
fi
[[ ${#ARCHIVES[@]} -gt 0 ]] || { echo "No archives in $HERE"; exit 0; }

STAMP="$(date +%Y%m%d-%H%M%S)"
BK="$CFG/claude-move-backups/$STAMP"
mtime() { stat -f %m "$1"; }

for A in "${ARCHIVES[@]}"; do
  [[ $A == /* ]] || A="$HERE/$A"
  BASE="$(basename "$A")"
  [[ -f $A ]] || { echo "skip (missing): $BASE"; continue; }
  if [[ $FORCE -eq 0 ]]; then
    grep -qxF "$BASE" "$APPLIED" 2>/dev/null && { echo "skip (already applied on $HOST): $BASE"; continue; }
    [[ $BASE == claude-move_"$HOST"_* ]] && { echo "skip (packed on this host): $BASE"; continue; }
  fi

  echo "=== $BASE"
  T="$(mktemp -d)"
  tar -xzpf "$A" -C "$T" || { rm -rf "$T"; die "cannot extract $BASE (still syncing from iCloud?)"; }
  SRC_HOME="$(awk '/^source_home:/{print $2}' "$T/.claude-move-manifest.txt" 2>/dev/null || true)"
  [[ -z $SRC_HOME || $SRC_HOME == "$HOME" ]] || \
    echo "WARN: source HOME=$SRC_HOME, here HOME=$HOME — project dirs encode absolute paths and may not match."

  NEW=0 SAME=0 UPD=0 MERGED=0 KEPT=0
  while IFS= read -r -d '' f; do
    rel="${f#$T/}"
    [[ $rel == .claude-move-manifest.txt ]] && continue
    # Archives from the pre-plugin version carried the skill itself; the plugin
    # now provides it, and a local copy would shadow the installed one.
    [[ $rel == skills/claude-move/* ]] && { echo "  skip    $rel (provided by the claude-move plugin)"; continue; }
    dst="$CFG/$rel"
    if [[ ! -e $dst ]]; then
      NEW=$((NEW+1)); [[ $DRY -eq 1 ]] && { echo "  new     $rel"; continue; }
      mkdir -p "$(dirname "$dst")"; cp -p "$f" "$dst"
    elif cmp -s "$f" "$dst"; then
      SAME=$((SAME+1))
    elif [[ $(basename "$rel") == MEMORY.md ]]; then
      add="$(awk 'NR==FNR{seen[$0]=1;next} !seen[$0] && NF' "$dst" "$f")"
      if [[ -z $add ]]; then SAME=$((SAME+1)); continue; fi
      MERGED=$((MERGED+1)); [[ $DRY -eq 1 ]] && { echo "  merge   $rel (+$(printf '%s\n' "$add" | wc -l | tr -d ' ') lines)"; continue; }
      mkdir -p "$BK/$(dirname "$rel")"; cp -p "$dst" "$BK/$rel"
      printf '%s\n' "$add" >> "$dst"
    elif [[ $(mtime "$f") -gt $(mtime "$dst") ]]; then
      UPD=$((UPD+1)); [[ $DRY -eq 1 ]] && { echo "  update  $rel"; continue; }
      mkdir -p "$BK/$(dirname "$rel")"; cp -p "$dst" "$BK/$rel"; cp -p "$f" "$dst"
    else
      KEPT=$((KEPT+1)); [[ $DRY -eq 1 ]] && { echo "  KEEP-LOCAL (local newer) $rel"; continue; }
      mkdir -p "$BK/incoming-older/$(dirname "$rel")"; cp -p "$f" "$BK/incoming-older/$rel"
      echo "  KEEP-LOCAL (local newer; incoming saved in backups/incoming-older) $rel"
    fi
  done < <(find "$T" -type f -print0)
  rm -rf "$T"

  echo "  new=$NEW updated=$UPD merged_index=$MERGED kept_local=$KEPT identical=$SAME"
  if [[ $DRY -eq 0 ]]; then
    grep -qxF "$BASE" "$APPLIED" 2>/dev/null || echo "$BASE" >> "$APPLIED"
  fi
done

[[ $DRY -eq 1 ]] && echo "(dry-run: nothing written)"
[[ $DRY -eq 0 && -d $BK ]] && echo "backups of replaced files: $BK"
exit 0
