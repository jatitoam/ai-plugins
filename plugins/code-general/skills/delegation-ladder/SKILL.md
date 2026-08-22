---
name: delegation-ladder
description: >
  Use before starting any request that takes more than one step: implementing a
  feature, fixing a bug, refactoring, debugging, investigating, reviewing code,
  exploring or mapping a codebase, researching, writing docs, plans, or tickets,
  migrating data, or handling independent parts. Also use when asked to
  delegate, use subagents, spawn agents, parallelize, fan out, choose a model,
  or decide who should do the work. When in doubt, run the gate; doing the work
  inline is a valid outcome.
---

# Delegation Ladder

The lead directs, decides, judges, and assembles. Spend lead capacity on
judgment rather than bulk work a cheaper reliable tier can handle.

## Load the host adapter first

Before running the gate, identify the current host and read exactly one adapter:

- Claude Code: [references/claude-code.md](references/claude-code.md)
- Codex: [references/codex.md](references/codex.md)
- Another host: use its exposed tools, model tiers, and authorization policy.

The adapter controls dispatch mechanics and permissions. This shared skill does
not override host, repository, or user instructions.

## Run the gate

Before touching the work, answer:

1. **Is this multi-step?** Reading or searching several files, substantial
   authoring, investigation, codebase mapping, or independent parts means
   delegate. A single known edit or direct answer stays inline.
2. **What must the lead keep?** Sequencing and decisions, precision edits to
   files it already knows, final review and assembly, secrets policy, and user
   communication.
3. **What is the cheapest available tier reliable for each remaining part?**
   Use a strong tier for deep investigation, difficult design, or adversarial
   review; a balanced tier for contained implementation and mapping; and a fast
   tier for mechanical work and dry-runs.
4. **Are the parts independent?** Launch independent parts concurrently.
   Sequence only when one part's output feeds the next.

If the gate says inline, proceed inline. That outcome must come from the gate,
not from skipping it.

## Dispatch contract

Give every subagent a self-contained brief: exact scope, relevant paths,
expected output, and write/read-only boundaries. Verify its result against the
actual sources of truth; the lead owns the final result.

## Patterns

- **Investigate before editing:** test assumptions against code, data, or the
  live system before encoding them.
- **Author low, review high:** let an economical tier produce contained work;
  use a stronger independent reviewer when the stakes justify it.
- **Prove operability at the target tier:** have the intended execution tier
  dry-run a runbook or prompt when its ability to follow it matters.
- **Stay proportionate:** irreversible, financial, production, or client-facing
  work earns stronger verification; routine work stays lean.
