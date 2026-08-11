# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A Claude plugin marketplace for AI-augmented engineering workflows. Plugins are collections of **skills**, **commands**, and **MCP servers** installed into Claude Code.

The repo currently has **zero plugins registered**. What exists today is the harness — registry files, marketplace metadata, and the tooling scripts described below — that plugins will be added into. Claude Code is the only supported client; there is no AGENTS.md and no Codex support.

## No Build System

There is no build step, no package manager, and no test suite. Development is editing YAML, Markdown, and script files directly.

There is no repo-wide runtime dependency. The repo's own tooling (`scripts/*.sh`) needs only bash and `python3` from the standard library. Individual plugins declare their own dependencies in their own docs.

## Plugin Architecture

```
plugins/<plugin-id>/
├── plugin.yaml          # Plugin metadata and skill/command/mcp_server lists
├── skills/<skill-id>/
│   ├── SKILL.md         # Instructs Claude how to behave when the skill is triggered
│   ├── scripts/         # Scripts Claude invokes during skill execution
│   └── references/      # Markdown docs Claude reads at runtime for context
```

- `index.yaml` — top-level registry; must be updated when adding a plugin
- `.claude-plugin/marketplace.json` — marketplace distribution metadata

## How Skills Work

A skill is activated when Claude recognizes the user's intent matches the skill's `description` in `SKILL.md` frontmatter. Claude then follows the numbered steps in that file, consulting `references/` docs and invoking `scripts/` via shell commands.

Skills may ship `scripts/` (in any language) and `references/`; the skill body says when each should be used.

## Repo Tooling

| Script | What it does | When to use |
|--------|---------------|-------------|
| `scripts/new-plugin.sh <plugin-id> "<display name>" "<description>" [category]` | Scaffolds `plugins/<plugin-id>/` at version `0.1.0` and registers it in `index.yaml` and `.claude-plugin/marketplace.json` (`category` defaults to `general`) | Starting a new plugin |
| `scripts/bump.sh <plugin-id> <major\|minor\|patch>` | Bumps a plugin's version across all five sync points atomically | After any change to a plugin's behavior or metadata |
| `scripts/validate.sh` | Checks registry consistency, version-field agreement, and skill/frontmatter correctness across the whole repo | Before every commit |

`.claude/commands/bump.md` exposes `scripts/bump.sh` as the `/bump` slash command.

## Adding a New Plugin

1. Run `scripts/new-plugin.sh <plugin-id> "<display name>" "<description>" [category]` — this creates `plugins/<plugin-id>/plugin.yaml`, `plugins/<plugin-id>/.claude-plugin/plugin.json`, an empty `skills/` directory, and registers the plugin in `index.yaml` and `.claude-plugin/marketplace.json` for you.
2. Add skills under `plugins/<plugin-id>/skills/<skill-id>/SKILL.md`. The skill's frontmatter `name` must equal its directory name.
3. List each skill in **both** registries — under `skills:` in `plugins/<plugin-id>/plugin.yaml` (as `- id:` / `path:`) and under `skills:` in that plugin's `index.yaml` entry (as a plain id). The scaffold script does not do this; `validate.sh` fails if the two lists disagree or if a skill directory is unlisted.
4. **Update `README.md`** — add a row to the Plugins table with the plugin id, description, and skill/command/mcp counts.
5. Run `scripts/validate.sh` and fix any reported issues before committing.

### What `validate.sh` checks

Every plugin directory is registered in both registries and vice versa; the five version fields agree per plugin and are valid semver; `plugin.json`/`plugin.yaml` names match the directory; each declared skill exists on disk with a `SKILL.md` carrying `name` and `description` frontmatter whose `name` matches its directory; no undeclared skill directories; the skill lists in `plugin.yaml` and `index.yaml` match; and each plugin has a row in the README Plugins table. It exits non-zero on any failure.

## Versioning

Follow [semver](https://semver.org/): `MAJOR.MINOR.PATCH`.
- **PATCH** — bug fixes, copy edits, non-functional changes
- **MINOR** — new backwards-compatible features (new skill parameters, new sections, new scripts)
- **MAJOR** — breaking changes (removed parameters, incompatible JSON shape changes)

Do **not** roll over to the next major version just because the minor or patch number reaches 9 or 10. `1.9.0 → 1.10.0` is correct semver.

A plugin's version must agree across five files:

1. `plugins/<plugin-id>/.claude-plugin/plugin.json` — version the CLI reads for update detection
2. `plugins/<plugin-id>/plugin.yaml` — canonical plugin definition
3. `.claude-plugin/marketplace.json` — the plugin's entry inside `"plugins": [...]`
4. `.claude-plugin/marketplace.json` — the **top-level** `"version"` field (controls whether `claude plugin marketplace update` fetches fresh data at all)
5. `index.yaml` — top-level registry entry for the plugin

**Use `scripts/bump.sh <plugin-id> <major|minor|patch>` to bump a plugin's version — do not hand-edit these five fields.** The script updates all four plugin-scoped fields to the new plugin version and gives the marketplace top-level `version` its own independent patch bump, printing a before→after line per file. It refuses to run if the five are already out of sync, printing what each field currently holds; reconcile them by hand, confirm with `scripts/validate.sh`, then bump. Run `scripts/validate.sh` before committing any change.

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
