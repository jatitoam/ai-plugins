#!/usr/bin/env bash
# PreToolUse hook on the Agent tool: every subagent dispatch names its model.
# A PreToolUse hook receives the tool call as JSON on stdin and may emit a
# permission decision as JSON on stdout; emitting nothing lets the call proceed.
#
# The bracket-prefix convention is documented in the delegation canon, but prose
# in the prompt layer decays over a long session. This makes it deterministic.
# See skills-claude/subagent-model-labels/SKILL.md for the convention and the
# rationale. It lives outside skills/ because that tree is portable: Codex
# scans it wholesale, and this guard is Claude-only.
set -uo pipefail

# Escape hatch for sessions whose workflow predates the convention.
[ "${CODE_GENERAL_LABEL_GUARD:-on}" = "off" ] && exit 0

# Fail open. A guard that cannot run must not wedge every dispatch, and the
# decision logic needs a real JSON parser -- descriptions contain quotes and
# brackets, which is exactly where a shell-only parse goes wrong.
command -v python3 >/dev/null 2>&1 || exit 0
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || exit 0

decider="$CLAUDE_PLUGIN_ROOT/hooks/guard-subagent-model-label.py"
[ -f "$decider" ] || exit 0

exec python3 "$decider"
