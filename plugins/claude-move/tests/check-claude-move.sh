#!/usr/bin/env bash
# Contract test for the claude-move plugin (run directly or via scripts/validate.sh).
#
# Guards what a silent edit could break without any file looking wrong:
#   - host gate: the Claude-only skill stays under skills-claude/, the Claude
#     manifest names that root, and the Codex manifest never widens past ./skills/
#   - pack.sh keeps refusing to run without --since/--dest and rejects
#     calendar-overflow dates (BSD date silently normalizes 2026-02-30)
#   - a real pack -> unpack round trip between two throwaway config dirs keeps
#     the merge contract: new files copied, MEMORY.md merged as a line union with
#     a backup, a locally-newer file kept with the incoming copy parked under
#     incoming-older/, an already-applied archive skipped on re-run, and
#     skills/claude-move/* from pre-plugin archives never installed.
# Behavioural on purpose: prose in SKILL.md is free to change; this is not.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/skills-claude/claude-move/scripts"
FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=1; }

# --- host gate ---------------------------------------------------------------
[[ -f $ROOT/skills-claude/claude-move/SKILL.md ]] || fail "skill moved out of skills-claude/ (Codex would load a Claude-only skill)"
[[ ! -e $ROOT/skills/claude-move ]] || fail "skills/claude-move exists: Codex loads everything under skills/"
python3 - "$ROOT" <<'EOF' || FAIL=1
import json, sys
root = sys.argv[1]
c = json.load(open(f"{root}/.claude-plugin/plugin.json"))
x = json.load(open(f"{root}/.codex-plugin/plugin.json"))
ok = True
if "./skills-claude/" not in (c.get("skills") or []):
    print("FAIL: Claude manifest no longer lists ./skills-claude/ -> skill silently disappears", file=sys.stderr); ok = False
if x.get("skills") != "./skills/":
    print("FAIL: Codex manifest 'skills' must stay ./skills/ (would expose the Claude-only skill)", file=sys.stderr); ok = False
sys.exit(0 if ok else 1)
EOF
for f in "$S/pack.sh" "$S/unpack.sh"; do
  [[ -x $f ]] || fail "$(basename "$f") lost its executable bit"
  bash -n "$f" || fail "$(basename "$f") has a syntax error"
done

# --- pack.sh argument guards -------------------------------------------------
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/src/projects"
CLAUDE_CONFIG_DIR="$T/src" bash "$S/pack.sh" --dest "$T/x" >/dev/null 2>&1 && fail "pack.sh ran without --since"
CLAUDE_CONFIG_DIR="$T/src" bash "$S/pack.sh" --since 2026-01-01 >/dev/null 2>&1 && fail "pack.sh ran without --dest"
CLAUDE_CONFIG_DIR="$T/src" bash "$S/pack.sh" --since 2026-02-30 --dest "$T/x" >/dev/null 2>&1 && fail "pack.sh accepted 2026-02-30"

# --- round trip ---------------------------------------------------------------
P=projects/-tmp-proj
mkdir -p "$T/src/$P/memory" "$T/dst/$P/memory" "$T/hand"
printf -- '- [a](a.md) — a\n- [b](b.md) — b\n' > "$T/src/$P/memory/MEMORY.md"
echo b                > "$T/src/$P/memory/b.md"
echo chat             > "$T/src/$P/s1.jsonl"
echo incoming         > "$T/src/$P/conflict.jsonl"
printf -- '- [a](a.md) — a\n' > "$T/dst/$P/memory/MEMORY.md"
echo local-newer      > "$T/dst/$P/conflict.jsonl"
touch -t 203001010000 "$T/dst/$P/conflict.jsonl"   # local is newer than incoming

CLAUDE_CONFIG_DIR="$T/src" bash "$S/pack.sh" --since 2000-01-01 --dest "$T/hand" >/dev/null
A="$(ls "$T/hand"/claude-move_*.tar.gz)"
# Simulate a pre-plugin archive that still carries the skill itself.
gunzip -c "$A" > "$T/a.tar"
mkdir -p "$T/legacy/skills/claude-move" && echo x > "$T/legacy/skills/claude-move/SKILL.md"
tar -rf "$T/a.tar" -C "$T/legacy" skills/claude-move/SKILL.md
gzip -c "$T/a.tar" > "$A"
# Rename so the archive is not "packed on this host".
mv "$A" "$T/hand/claude-move_OTHERHOST_test.tar.gz"
[[ -x $T/hand/unpack.sh ]] || fail "pack.sh did not drop an executable unpack.sh next to the archive"

out="$(CLAUDE_CONFIG_DIR="$T/dst" bash "$T/hand/unpack.sh")"
[[ -f $T/dst/$P/s1.jsonl ]]          || fail "new chat file was not copied"
[[ -f $T/dst/$P/memory/b.md ]]       || fail "new memory file was not copied"
grep -qF '[b](b.md)' "$T/dst/$P/memory/MEMORY.md" || fail "MEMORY.md union did not add the missing index line"
[[ $(grep -cF '[a](a.md)' "$T/dst/$P/memory/MEMORY.md") -eq 1 ]] || fail "MEMORY.md union duplicated an existing line"
[[ $(cat "$T/dst/$P/conflict.jsonl") == local-newer ]] || fail "locally-newer file was overwritten"
ls "$T/dst"/claude-move-backups/*/incoming-older/$P/conflict.jsonl >/dev/null 2>&1 || fail "incoming-older copy of the kept file is missing"
ls "$T/dst"/claude-move-backups/*/$P/memory/MEMORY.md >/dev/null 2>&1 || fail "MEMORY.md was merged without a backup"
[[ ! -e $T/dst/skills/claude-move ]] || fail "unpack installed skills/claude-move (would shadow the plugin)"
grep -q 'KEEP-LOCAL' <<<"$out" || fail "unpack did not report the KEEP-LOCAL file"

again="$(CLAUDE_CONFIG_DIR="$T/dst" bash "$T/hand/unpack.sh")"
grep -q 'already applied' <<<"$again" || fail "re-running unpack re-applied an applied archive"

[[ $FAIL -eq 0 ]] && echo "claude-move contract: OK"
exit "$FAIL"
