---
name: subagent-model-labels
description: >
  Use when a subagent dispatch was blocked for a missing or mismatched model
  label, when choosing how to label an agent's description, or when asked to
  install, verify, disable, or troubleshoot the label guard. Also use when
  asked why an Agent call was denied, what the bracket prefix means, which
  model tier a delegated task should carry, or whether the guard is loaded.
  Covers the convention, its enforcement hook, and the escape hatch.
---

# Subagent Model Labels

Every subagent dispatch carries the model it runs as, at the front of its
`description`, in square brackets:

```
[Sonnet 5] Map webhook handlers
[Haiku 4.5] Dry-run the runbook
[Opus 4.8] Review the migration plan
```

The label is what makes a fleet legible at a glance: a FleetView full of rows
with no tier is a fleet whose cost and depth you cannot read. The rest of the
description stays its normal 3-5 words.

## Why this is a hook and not just a rule

The convention lives in prose in
[../delegation-ladder/references/delegation-canon.md](../delegation-ladder/references/delegation-canon.md).
Prose in the prompt layer is a soft constraint: adherence decays as a session
grows, because salience falls off with distance from the instruction, not with
context fill. A rule that holds for the first ten dispatches and lapses on the
thirtieth is not a rule.

So the convention ships twice, doing two different jobs:

| Layer | Mechanism | Job |
|---|---|---|
| Enforcement | `hooks/guard-subagent-model-label.sh`, a `PreToolUse` guard on `Agent` | Deterministic. Cannot decay. Denies an unlabeled dispatch. |
| Explanation | This skill | Loads when someone hits the denial or asks about labelling. Explains *which* tier and why. |

Neither substitutes for the other. The hook cannot judge whether `[Haiku 4.5]`
was the right call for a deep audit; it only knows the label is present and
self-consistent. Tier selection stays a judgment call, governed by
[../delegation-ladder/SKILL.md](../delegation-ladder/SKILL.md).

## What the guard accepts

A description must open with a bracketed model family, optionally versioned,
followed by the task:

- Family: `Opus`, `Sonnet`, `Haiku`, or `Fable`, matched case-insensitively.
- Version: optional, dotted digits — `[Sonnet 5]`, `[Haiku 4.5]`, `[Opus 4.8]`,
  and bare `[Sonnet]` all pass.

Deliberately a shape check, not an allowlist of exact names. An allowlist goes
stale the day a model ships and starts denying correct labels; the failure mode
of a stale allowlist is worse than the failure mode of a loose one, because it
blocks legitimate work rather than letting a typo through.

When the call also sets `model`, the label must agree with it — `model: "opus"`
under a `[Haiku 4.5]` label is denied. This catches the second-order failure a
presence check misses: a label that is present but lying. Version is not
cross-checked, only family, since the host resolves an alias like `opus` to
whichever version is current.

When `model` is omitted, the agent inherits the lead's model; label the tier it
will actually run as, which is the lead's own.

A fork is where those two rules collide: `subagent_type: "fork"` always runs as
the lead and the host discards any `model` passed with it, so a `model` on a
fork describes nothing. The guard skips the cross-check there rather than deny a
label that correctly names the lead's tier. Label a fork with the lead's model,
whatever `model` says.

A payload that parses but carries a wrongly typed field is still judged: a
`description` that is not a string is no label and gets denied, and a `model`
that is not a string is treated as no override. Only stdin the guard cannot read
or parse at all fails open — otherwise passing `model` as a number would be
enough to switch the guard off.

## When a dispatch is denied

The denial is not fatal and needs no user intervention. The reason string
returns to the model, which re-issues the same call with the label. It costs one
turn.

Treat it as a prompt to re-examine the tier, not just to satisfy the check.
Re-issuing `[Opus 5]` on work that Haiku handles reliably passes the guard and
misses its point.

## Verifying it is loaded

A guard that never denies is indistinguishable from no guard, so inspecting
config proves nothing. Dispatch a deliberately unlabeled agent with a trivial
prompt and confirm it comes back denied. Piping JSON into the script by hand
tests the script; only a real dispatch tests the wiring.

## Disabling it

Set `CODE_GENERAL_LABEL_GUARD=off` in the environment. The guard exits without a
decision and every dispatch proceeds.

Reach for this when adopting the plugin in a session whose workflow predates the
convention, not to get past a single denial — that one is cheaper to fix by
adding the label.
