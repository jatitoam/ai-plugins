# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A cross-agent plugin marketplace for AI-augmented engineering workflows. Portable **skills** are shared by Claude Code and Codex; commands, hooks, and other integrations may be host-specific.

The repo supports Claude Code and Codex manifests. Keep shared behavior in `skills/` and isolate host-specific behavior in clearly named adapter references or host-specific integration files.

## No Build System

There is no build step, no package manager, and no test suite. Development is editing YAML, Markdown, and script files directly.

There is no repo-wide runtime dependency. The repo's own tooling (`scripts/*.sh`) needs only bash and `python3` from the standard library. Individual plugins declare their own dependencies in their own docs.

## Plugin Architecture

```
plugins/<plugin-id>/
├── .codex-plugin/plugin.json   # Codex metadata
├── .claude-plugin/plugin.json  # Claude Code metadata
├── plugin.yaml          # Plugin metadata and skill/command/hook/mcp_server lists
├── skills/<skill-id>/
│   ├── SKILL.md         # Portable agent instructions
│   ├── scripts/         # Scripts invoked during skill execution
│   └── references/      # Shared or host-specific runtime context
├── commands/<name>.md   # Slash commands, exposed as /<plugin-id>:<name> (optional)
└── hooks/hooks.json     # Hooks the plugin registers with the harness (optional)
```

Component directories live at the plugin root — never inside `.claude-plugin/`,
which holds only `plugin.json`.

- `index.yaml` — top-level registry; must be updated when adding a plugin
- `.claude-plugin/marketplace.json` — marketplace distribution metadata
- `.agents/plugins/marketplace.json` — Codex marketplace distribution metadata

## How Skills Work

A skill is activated when Claude recognizes the user's intent matches the skill's `description` in `SKILL.md` frontmatter. Claude then follows the numbered steps in that file, consulting `references/` docs and invoking `scripts/` via shell commands.

Skills may ship `scripts/` (in any language) and `references/`; the skill body says when each should be used.

## Repo Tooling

| Script | What it does | When to use |
|--------|---------------|-------------|
| `scripts/new-plugin.sh <plugin-id> "<display name>" "<description>" [category]` | Scaffolds both client manifests at version `0.1.0` and registers the plugin in both marketplaces and `index.yaml` (`category` defaults to `general`) | Starting a new plugin |
| `scripts/bump.sh <plugin-id> <major\|minor\|patch>` | Bumps a plugin's version across all six sync points atomically | After any change to a plugin's behavior or metadata |
| `scripts/validate.sh` | Checks registry consistency, version-field agreement, and skill/frontmatter correctness across the whole repo | Before every commit |

`.claude/commands/bump.md` exposes `scripts/bump.sh` as the `/bump` slash command.

## Adding a New Plugin

1. Run `scripts/new-plugin.sh <plugin-id> "<display name>" "<description>" [category]` — this creates `plugin.yaml`, both client manifests, an empty `skills/` directory, and registers the plugin in `index.yaml` and both marketplaces.
2. Add skills under `plugins/<plugin-id>/skills/<skill-id>/SKILL.md`. The skill's frontmatter `name` must equal its directory name.
3. List each skill in **both** registries — under `skills:` in `plugins/<plugin-id>/plugin.yaml` (as `- id:` / `path:`) and under `skills:` in that plugin's `index.yaml` entry (as a plain id). The scaffold script does not do this; `validate.sh` fails if the two lists disagree or if a skill directory is unlisted. Do the same under `hooks:` in both files for any `hooks/hooks.json` the plugin ships, and `chmod +x` every script the hook invokes.
4. **Update `README.md`** — add a row to the Plugins table with the plugin id, description, and skill/command/mcp counts.
5. Run `scripts/validate.sh` and fix any reported issues before committing.

### What `validate.sh` checks

Every plugin directory is registered in both registries and vice versa; the five plugin-scoped version fields agree and all six version fields are valid semver; both client manifests and `plugin.yaml` match the directory; each declared skill exists on disk with valid frontmatter; no skill directory is undeclared; registry skill lists agree; and each plugin has a README row. It exits non-zero on any failure.

For hooks it additionally checks: no undeclared `hooks/*.json` file on disk; every declared hook path exists; the `hooks:` lists in `plugin.yaml` and `index.yaml` match; and each `hooks.json` is valid JSON whose `${CLAUDE_PLUGIN_ROOT}/…` command references resolve to files that exist **and are executable**. A hook injects behavior into every session, so it is never allowed to go undeclared.

## Versioning

Follow [semver](https://semver.org/): `MAJOR.MINOR.PATCH`.
- **PATCH** — bug fixes, copy edits, non-functional changes
- **MINOR** — new backwards-compatible features (new skill parameters, new sections, new scripts)
- **MAJOR** — breaking changes (removed parameters, incompatible JSON shape changes)

Do **not** roll over to the next major version just because the minor or patch number reaches 9 or 10. `1.9.0 → 1.10.0` is correct semver.

A plugin has five synchronized plugin-version fields plus one independent
Claude marketplace cache version:

1. `plugins/<plugin-id>/.claude-plugin/plugin.json` — version the CLI reads for update detection
2. `plugins/<plugin-id>/.codex-plugin/plugin.json` — version Codex reads
3. `plugins/<plugin-id>/plugin.yaml` — canonical plugin definition
4. `.claude-plugin/marketplace.json` — the plugin's entry inside `"plugins": [...]`
5. `.claude-plugin/marketplace.json` — the **top-level** `"version"` field (controls whether `claude plugin marketplace update` fetches fresh data at all)
6. `index.yaml` — top-level registry entry for the plugin

**Use `scripts/bump.sh <plugin-id> <major|minor|patch>` to bump a plugin's version — do not hand-edit these six fields.** The script updates all five plugin-scoped fields to the new plugin version and gives the Claude marketplace top-level `version` its own independent patch bump. It refuses to run if plugin-scoped versions are already out of sync. Run `scripts/validate.sh` before committing any change.

## Updating the Plugin Locally

When a plugin is updated remotely, run these two commands in order to update the marketplace and plugin locally:

```bash
claude plugin marketplace update ai-plugins
claude plugin update <plugin-id>@ai-plugins
```

The marketplace refresh must come first — skipping it causes the CLI to report the old version as latest.

## Git Workflow

Every change goes on a `feat/<name>` or `fix/<name>` branch and lands via pull request; never commit directly to `main`. Stage files explicitly by path — never `git add .` or `git add -A`. Never force-push.

Commit messages use a scope prefix, e.g. `feat(<plugin-id>): add skill for X`. Version-bump commits cite the new version, e.g. `chore(<plugin-id>): bump to 1.2.0`.
