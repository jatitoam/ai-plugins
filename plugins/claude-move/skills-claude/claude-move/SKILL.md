---
name: claude-move
description: Move Claude Code memories (project auto-memory, global CLAUDE.md/rules/refs) and chat transcripts modified since an EXPLICIT start date into an EXPLICIT destination folder (e.g. a synced iCloud folder), plus an unpack.sh that applies them on the other laptop from that same folder. Use when the user asks to move, transfer, sync, migrate or carry Claude memories/chats/sessions to another laptop ("mueve las memorias", "pasa los chats a la otra laptop"), or to apply a pending claude-move archive on the receiving laptop.
argument-hint: <since YYYY-MM-DD> <destination-folder>
---

# claude-move

> **Host scope: Claude Code only.** It moves Claude Code's local config dir
> (`projects/`, `CLAUDE.md`, `rules/`, `refs/`); Codex keeps its state elsewhere.

Hands Claude-local state (which does NOT sync between machines) to another laptop
through a folder both laptops can see at the same path. Install this plugin on both
laptops; the scripts live in this skill's `scripts/` directory.

## Parameters — both REQUIRED, both stated by the user

| Parameter | Flag | Meaning |
|---|---|---|
| start date | `--since YYYY-MM-DD` | files with mtime after that day 00:00 local (the day is included) |
| destination folder | `--dest <folder>` | where the archive, manifest and `unpack.sh` are written; must be reachable at the same path on the other laptop |

If either is missing from the user's request, ASK. Never infer them from a previous run,
an existing archive, the conversation, or a "usual" folder. `pack.sh` refuses to run
without both, and rejects invalid dates such as `2026-02-30`.

Optional: `--project <substring>` limits to project dirs whose name contains it (global
files are then skipped); `--dry-run` previews without writing.

Config dir: `$CLAUDE_CONFIG_DIR`, fallback `~/.claude`. Check which one this session
uses (`echo "$CLAUDE_CONFIG_DIR"`) and pass it explicitly when running a script from
a shell that may not have it set — otherwise unpack writes into the wrong dir.

## What travels

| Kind | Source (relative to config dir) |
|---|---|
| memory | `projects/*/memory/**` (incl. `MEMORY.md`) |
| chats | everything else under `projects/*/`: `<session>.jsonl`, `<session>/subagents/`, `tool-results/` |
| global | `CLAUDE.md`, `rules/**`, `refs/**` |

Not moved: `settings.json`, `.claude.json`, `history.jsonl`, plugins, skills
(machine-specific or synced by other means). Say so if the user expects them.

## Pack (source laptop)

Run `scripts/pack.sh` from this skill's directory:

```bash
bash <skill-dir>/scripts/pack.sh --since <DATE> --dest "<FOLDER>" --dry-run   # counts + per-project breakdown
bash <skill-dir>/scripts/pack.sh --since <DATE> --dest "<FOLDER>"             # write the bundle
```

Output in `<FOLDER>`: `claude-move_<host>_since-<DATE>_<stamp>.tar.gz`, a matching
`.manifest.txt` (header + full file list), and a fresh `unpack.sh`. Report the archive
path, size and counts — call out `memory=0` explicitly, since users usually expect
memories to be included. Transcripts may contain secrets or third-party data pulled
by tools (emails, attachments), so only use a private destination.

## Unpack (receiving laptop)

The `unpack.sh` that runs is the copy next to the archive. It is a downloaded file:
read it and run `--dry-run` before applying, and list the archive
(`tar -tzvf`) to confirm no absolute paths, `..` components or symlinks.

```bash
CLAUDE_CONFIG_DIR=<config-dir> bash "<FOLDER>/unpack.sh" --dry-run
CLAUDE_CONFIG_DIR=<config-dir> bash "<FOLDER>/unpack.sh"
```

- Applies every `claude-move_*.tar.gz` next to the script that is not yet listed in
  `<FOLDER>/.applied-<host>`; skips archives packed on the same host. `--force`
  overrides both; explicit archive names may be passed.
- Never deletes. A missing file is copied; an identical one is skipped; a `MEMORY.md` index is
  merged as the union of its lines; a newer incoming file overwrites after the local
  one is backed up to `<config>/claude-move-backups/<stamp>/`; a newer LOCAL file is
  kept and the incoming copy goes to `.../incoming-older/`. Report every KEEP-LOCAL
  line to the user, because those files were edited on both laptops and need reconciling by hand.
- Project dir names encode absolute paths; the script warns if `$HOME` differs
  between laptops.
- Afterwards, verify every manifest entry exists under the config dir, then offer to
  delete the handoff folder (it holds the transcripts in a synced location).
- Restart Claude Code sessions so memories reload; moved chats show up in
  `/resume` for the matching project.
