---
name: delegation-ladder
description: >
  Use when a request has multiple substantial independent workstreams, needs
  independent review, or explicitly asks to delegate, use subagents,
  parallelize, fan out, or choose models.
---

# Delegation Ladder

Delegate to reduce wall-clock time or buy independent judgment, not merely
because a task has several steps. Keep tightly coupled, sequential, and small
localized work inline.

## Run the gate

1. Identify the work the lead must keep: sequencing, decisions, final review
   and assembly, secrets policy, and user communication.
2. Delegate a remaining part only when it is substantial and independently
   executable, or when an independent review materially improves confidence.
3. Choose the least expensive available model that can perform each part
   reliably. Use a stronger model for deep investigation, difficult design, or
   adversarial review; a balanced model for contained implementation and
   mapping; and a fast model for mechanical work and dry-runs.
4. Launch independent parts concurrently. Sequence work only when one part's
   output is required by the next.
5. Give every subagent a self-contained brief: exact scope, relevant paths,
   expected output, and write/read-only boundaries.
6. Verify subagent results against the actual sources of truth. The lead owns
   the final result.

Doing the work inline is the normal outcome when delegation adds more overhead
than value.

## Host adapter

Use only tools and models exposed by the current host. This skill supplies
routing guidance; it does not grant permissions or override host, repository,
or user instructions.

- In Claude Code, read [references/claude-code.md](references/claude-code.md)
  before dispatching.
- In Codex, read [references/codex.md](references/codex.md) before dispatching.
- On another host, apply the gate with that host's available capabilities and
  permission model.

## Useful patterns

- **Investigate before editing:** test assumptions against code, data, or the
  live system before encoding them.
- **Author low, review high:** let an economical model produce contained work;
  use a stronger independent reviewer when the stakes justify it.
- **Prove operability at the target tier:** have the intended execution tier
  dry-run a runbook or prompt when its ability to follow it matters.
- **Stay proportionate:** irreversible, financial, production, or client-facing
  work earns stronger verification; routine work stays lean.
