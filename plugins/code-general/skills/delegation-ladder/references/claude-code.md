# Claude Code adapter

Claude Code dispatches subagents with the Agent tool. Use only models available
in the current session; when the familiar tiers are present, route them as:

| Work | Model tier |
|---|---|
| Deep investigation, difficult design, adversarial review | Opus |
| Contained implementation, authoring, codebase mapping | Sonnet |
| Mechanical bulk, dry-runs, simple verification | Haiku |

When Opus is the lead, it normally keeps deep investigation and final judgment,
using an independent Opus reviewer only when the stakes justify the cost.

Prefix the Agent description with the selected model's human-readable name when
FleetView is available, for example `[Sonnet] Map webhook handlers`.

## Optional standing authorization

Claude Code installations that deliberately want standing authorization may use
the canon in [delegation-canon.md](delegation-canon.md). This is a Claude-only,
user-installed policy layer; the portable skill does not depend on it.

Install or remove it through `/code-general:install-delegation-canon`. Preview
installation first and obtain explicit confirmation before the script edits a
shell rc file.

The grant covers the Agent tool only. Workflow and deep-research retain their
own authorization requirements. Ask before dispatching more than about eight
agents at once or writing outside the current repository. Dispatched agents do
not inherit permission to sub-delegate unless the user grants it.
