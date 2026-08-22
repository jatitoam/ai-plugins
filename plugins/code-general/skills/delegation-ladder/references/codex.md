# Codex adapter

Use Codex's collaboration/subagent tools only when they are exposed in the
current session and delegation is allowed by the active user, repository, skill,
and host instructions. Installing this skill grants no standing permission.

- Trust the current tool schema and spawn allowlist over model names copied from
  documentation or earlier sessions.
- Choose models by role: strongest available for deep investigation or
  adversarial review, balanced for contained implementation and mapping, and
  fastest economical model for mechanical checks.
- Set model and reasoning effort explicitly when the spawn interface supports
  them.
- Prefer isolated context for self-contained work; include prior turns only
  when the task actually depends on them.
- Use the host's event/wait mechanism rather than short polling loops.
- Reuse an existing agent for follow-up fixes when the host supports it.

Codex needs no delegation canon, shell wrapper, SessionStart hook, AgentTool
label, or FleetView convention. Those are Claude Code integration details.
