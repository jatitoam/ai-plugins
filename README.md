# AI Plugins — Claude Plugin Marketplace

A curated collection of Claude plugins — skills, slash commands, and MCP servers — for AI-augmented engineering workflows.

## Structure

```
plugins/
└── <plugin-id>/
    ├── plugin.yaml          # Plugin metadata
    ├── skills/
    │   └── <skill-id>/
    │       ├── SKILL.md     # Skill definition (triggers, steps, behavior)
    │       ├── scripts/     # Helper scripts invoked by the skill
    │       └── references/  # Reference docs read by Claude at runtime
    ├── commands/            # Slash commands (optional)
    └── mcp/                 # MCP server definitions (optional)
index.yaml                   # Top-level registry of all plugins
```

## Plugins

| Plugin | Description | Skills | Commands | MCP Servers |
|--------|-------------|--------|----------|-------------|
| _none yet_ | Plugins will be added here. | — | — | — |

## Plugin Concepts

| Concept | What it is |
|---------|-----------|
| **Skill** | A `SKILL.md` file that instructs Claude to follow a specific multi-step workflow when triggered by certain user phrases. Can include helper scripts and reference documents. |
| **Command** | A slash command (e.g. `/bump`) that invokes a skill or workflow directly. |
| **MCP Server** | A Model Context Protocol server that exposes tools, resources, or prompts to Claude. |

## Bumping a Plugin Version

Five places must be updated in sync — the CLI reads each one for a different purpose:

| File | Why it must be updated |
|------|------------------------|
| `plugins/<plugin-id>/.claude-plugin/plugin.json` | Version authority for `claude plugin update` — **this is what the CLI checks** |
| `plugins/<plugin-id>/plugin.yaml` | Canonical plugin definition |
| `.claude-plugin/marketplace.json` (plugin entry) | Repo registry used by `claude plugin install` |
| `.claude-plugin/marketplace.json` (top-level `version`) | Controls whether `claude plugin marketplace update` fetches fresh data at all |
| `index.yaml` | Top-level registry entry for the plugin |

This is enforced by tooling rather than discipline. Run:

```bash
scripts/bump.sh <plugin-id> <major|minor|patch>
```

This updates all five fields atomically — the four plugin-scoped fields to the new plugin version, plus the marketplace top-level `version`, which gets its own independent patch bump — and prints a before→after line per file. It refuses to run if the five are already out of sync. A `/bump` slash command (`.claude/commands/bump.md`) wraps this script.

## Updating the plugin locally

When a plugin is updated remotely, the marketplace and plugin must be updated locally to reflect the new version. Run:

```bash
claude plugin marketplace update ai-plugins
claude plugin update <plugin-id>@ai-plugins
```

The marketplace must be refreshed first — otherwise the CLI reads a stale registry and reports the old version as latest.

## Adding a New Plugin

1. Run `scripts/new-plugin.sh <plugin-id> "<display name>" "<description>" [category]`. This scaffolds `plugins/<plugin-id>/` — `.claude-plugin/plugin.json`, `plugin.yaml`, and an empty `skills/` dir at version `0.1.0` — and registers the plugin in `index.yaml` and `.claude-plugin/marketplace.json` for you. `category` defaults to `general`.
2. Add each skill under `skills/<skill-id>/SKILL.md`. The frontmatter `name` must equal the directory name.
3. List each skill in **both** registries: under `skills:` in `plugins/<plugin-id>/plugin.yaml` and under `skills:` in that plugin's `index.yaml` entry. The scaffold script does not do this for you.
4. Update the README Plugins table by hand — add a row with the plugin id, description, and skill/command/mcp counts.
5. Run `scripts/validate.sh` and fix any reported issues.

### plugin.yaml schema

```yaml
name: my-plugin
display_name: My Plugin
description: What this plugin does.
version: 1.0.0
skills:
  - id: my-skill
    path: skills/my-skill
commands: []
mcp_servers: []
```

### SKILL.md frontmatter

```yaml
---
name: skill-name
description: >
  One or two sentences describing when Claude should activate this skill.
  Include trigger phrases.
---
```
