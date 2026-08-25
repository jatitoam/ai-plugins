# AI Plugins — Claude Code and Codex Marketplace

A curated collection of cross-agent skills and host-specific plugin adapters
for AI-augmented engineering workflows.

## Structure

```
plugins/
└── <plugin-id>/
    ├── .codex-plugin/plugin.json   # Codex manifest
    ├── .claude-plugin/plugin.json  # Claude Code manifest
    ├── plugin.yaml          # Plugin metadata
    ├── skills/
    │   └── <skill-id>/
    │       ├── SKILL.md     # Skill definition (triggers, steps, behavior)
    │       ├── scripts/     # Helper scripts invoked by the skill
    │       └── references/  # Shared and host-specific runtime guidance
    ├── commands/            # Slash commands (optional)
    ├── hooks/hooks.json     # Hooks registered with the harness (optional)
    └── mcp/                 # MCP server definitions (optional)
index.yaml                   # Top-level registry of all plugins
```

## Plugins

| Plugin | Description | Skills | Commands | Hooks | MCP Servers |
|--------|-------------|--------|----------|-------|-------------|
| code-general | Cross-agent delegation and orchestration policy with Claude Code and Codex adapters. Claude's standing-authorization canon is optional. | 2 | 1 | 1 | 0 |

## Plugin Concepts

| Concept | What it is |
|---------|-----------|
| **Skill** | A portable `SKILL.md` workflow shared by compatible agents. Host-specific behavior belongs in adapter references. |
| **Command** | A slash command (e.g. `/bump`) that invokes a skill or workflow directly. |
| **MCP Server** | A Model Context Protocol server that exposes tools, resources, or prompts to an agent. |

## Bumping a Plugin Version

Five plugin-version fields must stay synchronized, and the independent Claude
marketplace cache version must also advance on every release:

| File | Why it must be updated |
|------|------------------------|
| `plugins/<plugin-id>/.claude-plugin/plugin.json` | Version authority for `claude plugin update` — **this is what the CLI checks** |
| `plugins/<plugin-id>/.codex-plugin/plugin.json` | Version and metadata read by Codex |
| `plugins/<plugin-id>/plugin.yaml` | Canonical plugin definition |
| `.claude-plugin/marketplace.json` (plugin entry) | Repo registry used by `claude plugin install` |
| `.claude-plugin/marketplace.json` (top-level `version`) | Controls whether `claude plugin marketplace update` fetches fresh data at all |
| `index.yaml` | Top-level registry entry for the plugin |

This is enforced by tooling rather than discipline. Run:

```bash
scripts/bump.sh <plugin-id> <major|minor|patch>
```

This updates all six fields atomically — the five plugin-scoped fields to the
new plugin version, plus the marketplace top-level `version`, which gets its
own independent patch bump. A `/bump` slash command
(`.claude/commands/bump.md`) wraps this script.

## Updating the plugin locally

When a plugin is updated remotely, the marketplace and plugin must be updated locally to reflect the new version. Run:

```bash
claude plugin marketplace update ai-plugins
claude plugin update <plugin-id>@ai-plugins
```

The marketplace must be refreshed first — otherwise the CLI reads a stale registry and reports the old version as latest.

## Adding a New Plugin

1. Run `scripts/new-plugin.sh <plugin-id> "<display name>" "<description>" [category]`. This scaffolds both client manifests, `plugin.yaml`, and an empty `skills/` directory at version `0.1.0`, then registers the plugin in `index.yaml`, `.claude-plugin/marketplace.json`, and `.agents/plugins/marketplace.json`. `category` defaults to `general`.
2. Add each skill under `skills/<skill-id>/SKILL.md`. The frontmatter `name` must equal the directory name.
3. List each skill in **both** registries: under `skills:` in `plugins/<plugin-id>/plugin.yaml` and under `skills:` in that plugin's `index.yaml` entry. Same for any `hooks/hooks.json` under `hooks:` in both files — and `chmod +x` the scripts it invokes. The scaffold script does not do this for you.
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
hooks: []
mcp_servers: []
```

### SKILL.md frontmatter

```yaml
---
name: skill-name
description: >
  One or two sentences describing when a compatible agent should activate this skill.
  Include trigger phrases.
---
```
