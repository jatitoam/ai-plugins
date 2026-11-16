#!/usr/bin/env bash
# claude-move / pack.sh — gather Claude memories + chats modified since a REQUIRED date
# into a tar.gz in a REQUIRED handoff folder, plus a copy of unpack.sh next to it.
#
# Usage: pack.sh --since YYYY-MM-DD --dest <folder> [--project <substring>] [--dry-run]
#   Both --since and --dest are mandatory; there are no defaults on purpose.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

SINCE="" DEST="" PROJECT="" DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)   SINCE="${2:-}";   [[ -n $SINCE ]]   || die "--since needs a value";   shift 2 ;;
    --dest)    DEST="${2:-}";    [[ -n $DEST ]]    || die "--dest needs a value";    shift 2 ;;
    --project) PROJECT="${2:-}"; [[ -n $PROJECT ]] || die "--project needs a value"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) die "unexpected argument: $1 (see --help)" ;;
  esac
done

[[ -n $SINCE ]] || die "--since YYYY-MM-DD is REQUIRED. No default on purpose."
[[ -n $DEST ]]  || die "--dest <folder> is REQUIRED. No default on purpose."
[[ $DEST == /* ]] || DEST="$PWD/$DEST"
DEST="${DEST%/}"
[[ $SINCE =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "date must be YYYY-MM-DD, got: $SINCE"
# BSD date normalizes overflow (2026-02-30 -> 03-02), so require a round-trip match.
[[ "$(date -j -f %Y-%m-%d "$SINCE" +%Y-%m-%d 2>/dev/null)" == "$SINCE" ]] || die "invalid calendar date: $SINCE"

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
[[ -d $CFG/projects ]] || die "no projects/ under config dir $CFG"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOST="$(hostname -s)"
STAMP="$(date +%Y%m%d-%H%M%S)"
NAME="claude-move_${HOST}_since-${SINCE}_${STAMP}"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
LIST="$WORK/files.lst"; : > "$LIST"
MEM=0 CHAT=0 GLOB=0

cd "$CFG"

# 1) Project memories + 2) chats (session transcripts, subagents, tool-results)
for pdir in projects/*/; do
  pdir="${pdir%/}"
  [[ -z $PROJECT || $pdir == *"$PROJECT"* ]] || continue
  while IFS= read -r -d '' f; do
    printf '%s\0' "$f" >> "$LIST"
    if [[ $f == "$pdir"/memory/* ]]; then MEM=$((MEM+1)); else CHAT=$((CHAT+1)); fi
  done < <(find "$pdir" -type f -newermt "$SINCE" ! -name .DS_Store -print0)
done

# 3) Global user-level memory (instructions, rules, refs) — skipped when --project is set
if [[ -z $PROJECT ]]; then
  while IFS= read -r -d '' f; do
    printf '%s\0' "$f" >> "$LIST"; GLOB=$((GLOB+1))
  done < <(find CLAUDE.md rules refs -type f -newermt "$SINCE" ! -name .DS_Store -print0 2>/dev/null || true)
fi

TOTAL=$((MEM+CHAT+GLOB))
SIZE_KB=0
if [[ $TOTAL -gt 0 ]]; then
  SIZE_KB=$(xargs -0 du -k < "$LIST" | awk '{s+=$1} END{print s+0}')
fi

MANIFEST="$WORK/MANIFEST.txt"
{
  echo "name:        $NAME"
  echo "source_host: $HOST"
  echo "source_home: $HOME"
  echo "config_dir:  $CFG"
  echo "since:       $SINCE (files with mtime after $SINCE 00:00 local)"
  echo "dest:        $DEST"
  echo "project:     ${PROJECT:-<all>}"
  echo "created:     $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "counts:      memory=$MEM chats=$CHAT global=$GLOB total=$TOTAL (~${SIZE_KB} KB uncompressed)"
  echo "---"
  tr '\0' '\n' < "$LIST"
} > "$MANIFEST"

head -9 "$MANIFEST"
if [[ $DRY -eq 1 ]]; then
  echo "--- dry-run: per-project breakdown ---"
  tr '\0' '\n' < "$LIST" | awk -F/ '{print $1"/"$2 (($3=="memory")?"  [memory]":"")}' | sort | uniq -c
  exit 0
fi
[[ $TOTAL -gt 0 ]] || { echo "Nothing modified since $SINCE. No archive created."; exit 0; }


mkdir -p "$DEST"
cp "$MANIFEST" "$WORK/.claude-move-manifest.txt"
# bsdtar applies a later -C before reading -T, so build plain tar, append manifest, then gzip.
tar -cf "$WORK/$NAME.tar" --null -T "$LIST"
tar -rf "$WORK/$NAME.tar" -C "$WORK" .claude-move-manifest.txt
gzip -c "$WORK/$NAME.tar" > "$DEST/$NAME.tar.gz.part" && mv "$DEST/$NAME.tar.gz.part" "$DEST/$NAME.tar.gz"
cp "$MANIFEST" "$DEST/$NAME.manifest.txt"
cp "$SKILL_DIR/scripts/unpack.sh" "$DEST/unpack.sh"; chmod +x "$DEST/unpack.sh"

echo "---"
echo "archive:  $DEST/$NAME.tar.gz ($(du -h "$DEST/$NAME.tar.gz" | cut -f1))"
echo "manifest: $DEST/$NAME.manifest.txt"
echo "unpacker: $DEST/unpack.sh"
echo "On the other laptop (same folder path, after it syncs):"
echo "  bash \"$DEST/unpack.sh\" --dry-run   # preview"
echo "  bash \"$DEST/unpack.sh\"             # apply"
