---
name: delegation-ladder
description: >
  Routing gate that runs BEFORE starting work: decides whether to do it inline or
  hand parts to subagents, and at which model tier. Invoke FIRST — before reading
  files, writing code, or drafting — on any request that takes more than one step:
  implementing a feature, fixing a bug, refactoring, debugging, investigating,
  reviewing code, exploring or mapping a codebase, researching, writing docs,
  plans, or tickets, migrating data, or any request with independent parts. Also
  invoke on "delegate", "use subagents", "spawn agents", "parallelize", "fan out",
  "which model", "who should do this". When in doubt, invoke it: the gate is cheap
  and "do it inline" is a valid outcome.
---

# Delegation Ladder

The lead model directs, decides, judges, and assembles. It should spend its
capacity on judgment, not on bulk work a cheaper tier handles reliably.

Delegation is **standing authorized policy** — the user has requested it in
advance, for every session. Do not ask permission to spawn a subagent and do not
narrate delegating as if it were an exception. See
`references/delegation-canon.md` for the authorization text and
`scripts/install-canon.sh` for installing it at the system-prompt layer.

## 1. Run the gate

Before touching the work, answer in one line each:

1. **Is this multi-step?** Reading/searching several files, authoring anything
   substantial, investigating a cause, mapping a codebase, or any task with
   independent parts → delegate. A single known edit or a direct answer → do it.
2. **What must the lead keep?** (Section 2.) Everything else is delegable.
3. **What is the cheapest tier that is reliable for each delegable part?**
   (Section 3.)
4. **Are the parts independent?** If yes, launch them in a **single message** so
   they run concurrently. Sequence only when one agent's output feeds another's
   prompt.

If the answer is "do it inline", that is a legitimate outcome — but it must be
the result of this gate, not the default.

Two brakes on the gate:

- **Answer a question as a question.** This gate governs *how* to do work the
  user asked for. It is not license to start work they did not ask for. Recommend
  and proceed on sensible defaults, but surface the choices that are genuinely
  theirs rather than silently choosing.
- **Cost-proportionate rigor.** Match the ceremony to the stakes. High-stakes or
  irreversible work (production data, money, anything client-facing) earns heavy
  verification and adversarial review; routine work stays lean. This is also the
  rationale for "cheapest tier that is reliable" — not every task earns Opus.

## 2. The lead never delegates

- Sequencing and decisions
- Precision edits to files whose current state it already knows
- Final review and assembly of agent output
- Secrets-handling policy
- Communication with the user

## 3. The ladder — pick the cheapest tier that is reliable

When **Fable** (or any Mythos-class model) is the lead:

| Tier | Delegate to it |
|---|---|
| Opus | Deep investigation and evidence-gathering, adversarial review of code/docs against sources of truth, design/planning input on complex systems |
| Sonnet | Contained implementation or authoring from a precise spec, structured codebase/doc mapping, API/`gh` inspection tasks |
| Haiku | Mechanical bulk (sweeps, renames, conversions), dry-run/operability checks, simple verification passes |

When **Opus** is the lead, shift everything one tier down: Opus keeps deep
investigation and final judgment itself — spawning a *parallel* Opus agent for
adversarial review of artifacts it authored, so the reviewer is independent;
Sonnet does implementation, authoring, and exploration; Haiku does mechanical
bulk and dry-runs.

When **Sonnet** is the lead, it keeps sequencing, judgment, and precision edits;
Haiku takes mechanical bulk and dry-runs; escalate *up* to Opus only for deep
investigation and adversarial review of anything high-stakes.

## 4. Label every subagent with its model

Prefix each agent's `description` (the short text shown in the FleetView row)
with the model it runs as, in square brackets — e.g. `[Opus 4.8] Explore
teaching-claude-plugin repo`, `[Sonnet 5] Map webhook handlers`, `[Haiku 4.5]
Dry-run the runbook`. Use the human-readable name of the `model` assigned to that
agent; if the agent inherits the lead's model (no explicit `model`), use the
lead's model name. Keep the rest of the description within its normal 3–5 words.

## 5. Patterns that work

- **Investigate before editing.** Launch an evidence-gathering agent before
  changing anything based on an assumption — including the user's stated
  assumption. Surface contradictions with evidence instead of encoding them into
  the change.
- **Parallelize.** Independent agents go in a single message. Sequence only on a
  real data dependency.
- **Author low, review high.** Content authored by a lower tier gets an
  adversarial review by a higher tier against the actual sources of truth (code,
  configs, live systems) — then the lead applies the fixes itself rather than
  looping another author pass.
- **Prove operability at the target tier.** A doc, runbook, or command meant to
  be executed by a small model gets a read-only dry-run by that same model (e.g.
  Haiku narrates exactly what it would run); its confusions are the defect list.
- **Write self-contained agent specs.** Exact paths, expected outputs, hard
  boundaries ("read-only", "do not touch X", "report, don't fix"). A vague prompt
  wastes the tier's entire run.

## 6. Scope of the grant

- **Granted, standing:** the Agent tool, including several agents in parallel in
  one message.
- **Not granted:** the Workflow tool and deep-research — those keep their own
  per-task opt-in ("use a workflow", "ultracode").
- **Ask first** beyond ~8 parallel subagents in one message, or when a subagent
  would write outside the current repository.
- Subagents dispatched for a specific task inherit no grant to sub-delegate;
  nesting stays off unless the user asks.

## 7. Installing the canon (system-prompt layer)

Claude Code's own system prompt may carry a hard-coded restriction such as "Do
not call the AgentTool unless the user requested it". A skill body cannot
reliably override system-prompt text, and it only loads once something has
already decided to invoke it. Three layers of enforcement, strongest first:

| Layer | Mechanism | Strength |
|---|---|---|
| System prompt | `claude --append-system-prompt-file <canon>` via a shell wrapper — install with `scripts/install-canon.sh` | Sits in the system prompt itself, so it outranks the restriction by recency and specificity (it appends — it does not delete the original text) |
| Session context | This plugin's `hooks/hooks.json` SessionStart hook, injecting a pointer to this skill | Present every session, no shell changes |
| Skill | This file, triggered by the description above | Loads when the task shape matches |

To install or repoint the system-prompt layer, prefer the slash command
`/code-general:install-delegation-canon`, which wraps the script with the dry-run
and confirmation steps. Directly:

```bash
"$CLAUDE_PLUGIN_ROOT/skills/delegation-ladder/scripts/install-canon.sh" --dry-run
"$CLAUDE_PLUGIN_ROOT/skills/delegation-ladder/scripts/install-canon.sh"
```

The script edits the user's shell rc file. Always show the `--dry-run` output and
get explicit confirmation before running it for real. It detects the login shell
from `$SHELL` and picks the rc file that shell actually reads — zsh
(`${ZDOTDIR:-$HOME}/.zshrc`) and bash (`~/.bashrc` or `~/.bash_profile`,
whichever exists, platform-appropriate when neither does). It **refuses** rather
than guessing on fish (its syntax cannot parse the POSIX function, so it prints
the hand-written equivalent), on Windows-native shells (unsupported for now; use
WSL), and on any other shell unless you name the target with `--rc <path>`. An
explicit `--rc`/`SHELL_RC` that contradicts the detected shell is honored, with a
warning that the file must actually be sourced at startup. It also refuses to
append its own wrapper when it finds an existing `claude()` definition it did not
write, rather than shadowing your configuration.

The rc file must never point at this plugin's copy of the canon directly:
installed plugins live at a version-scoped path
(`~/.claude*/plugins/cache/<marketplace>/<plugin>/<version>/…`), so a direct
reference pins the canon to whichever version was installed that day and breaks
when that version is pruned. The installer therefore copies the canon to a
stable path — `~/.claude-delegation/canon.md`, overridable with
`CLAUDE_DELEGATION_CANON_PATH` — and points the rc file there. The SessionStart
hook runs `install-canon.sh --sync` every session to refresh that copy, so
`claude plugin update` propagates canon edits on its own; they take effect the
session after the update, since the shell reads the file at launch.
