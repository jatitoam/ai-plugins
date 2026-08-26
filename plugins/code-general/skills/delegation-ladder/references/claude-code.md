# Claude Code adapter

Read this adapter before running the gate, including when the eventual decision
is to work inline. Claude Code dispatches subagents with the Agent tool. Use only
models available in the current session; when the familiar tiers are present,
route them as:

| Work | Model tier |
|---|---|
| Deep investigation, difficult design, adversarial review | Opus |
| Contained implementation, authoring, codebase mapping | Sonnet |
| Mechanical bulk, dry-runs, simple verification | Haiku |

When Fable or another Mythos-class model leads, use Opus for deep investigation
and adversarial review, Sonnet for contained implementation and mapping, and
Haiku for mechanical work.

When Opus leads, shift work down one tier: Opus keeps deep investigation and
final judgment, Sonnet handles implementation and exploration, and Haiku handles
mechanical work and dry-runs. Use an independent Opus reviewer for artifacts the
lead authored when the stakes justify it.

When Sonnet leads, it keeps sequencing, judgment, and precision edits; Haiku
handles mechanical work and dry-runs. Escalate to Opus for deep investigation or
high-stakes adversarial review.

Prefix the Agent description with the selected model's human-readable name, for
example `[Sonnet] Map webhook handlers`. This plugin ships a `PreToolUse` guard
that denies an unlabelled dispatch, so treat the label as required rather than
as a FleetView nicety. The `subagent-model-labels` skill covers the convention,
what the guard accepts, and how to turn it off.

## Optional standing authorization

Claude Code installations that deliberately want standing authorization may use
the canon in [delegation-canon.md](delegation-canon.md). When the current system
prompt contains that canon, it is the user's standing authorization: dispatch
without asking again. Otherwise follow the active authorization policy. This is
a Claude-only, user-installed policy layer; Codex does not use it.

Install or remove it through `/code-general:install-delegation-canon`. Preview
installation first and obtain explicit confirmation before the script edits a
shell rc file.

The grant covers the Agent tool only. Workflow and deep-research retain their
own authorization requirements. Ask before dispatching more than about eight
agents at once or writing outside the current repository. Dispatched agents do
not inherit permission to sub-delegate unless the user grants it.
