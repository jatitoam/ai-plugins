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
Before any multi-step task, planning or execution, invoke
`code-general:delegation-ladder` and follow its Claude Code adapter. The optional
system-prompt canon, when installed, supplies standing Agent-tool authorization;
otherwise follow the active authorization policy.
EOF
