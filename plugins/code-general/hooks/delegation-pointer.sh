#!/usr/bin/env bash
# SessionStart hook: keep delegation in front of the lead model on every task.
# stdout from a SessionStart hook is injected into the session as context.
set -uo pipefail

# Keep the stable canon copy (which the user's shell wrapper passes to
# --append-system-prompt-file) in sync with this plugin's version of it, so
# plugin updates propagate without re-running the installer. Best effort: a
# failure here must never disturb the session, and --sync never writes stdout.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  "$CLAUDE_PLUGIN_ROOT/skills/delegation-ladder/scripts/install-canon.sh" --sync \
    >/dev/null 2>&1 || true
fi

cat <<'EOF'
Delegation is standing authorized policy for this user — requested in advance,
for every session. Before any multi-step task, planning or execution, invoke the
skill `code-general:delegation-ladder` and follow it. Do not ask permission to
spawn subagents and do not treat delegating as an exception. The Workflow tool
and deep-research are NOT covered by this grant and keep their own per-task
opt-in.
EOF
