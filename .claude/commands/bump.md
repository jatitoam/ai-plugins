---
description: Bump a plugin's version in all five places, then validate
argument-hint: <plugin-id> <major|minor|patch>
allowed-tools: Bash(./scripts/bump.sh *), Bash(./scripts/validate.sh), Bash(git status *), Bash(git diff *)
---

Bump the version of a plugin in this marketplace.

Arguments given: `$ARGUMENTS`

Steps:

1. If no plugin id was given, list the plugin ids from `index.yaml` and ask which one.
2. If no level was given, infer it from the changes since the last version bump and
   propose it, following the semver rules in `CLAUDE.md`: `patch` for fixes and copy
   edits, `minor` for new backwards-compatible capability, `major` for breaking
   changes to a skill's contract. State your reasoning in one line and confirm before
   running.
3. Run `./scripts/bump.sh <plugin-id> <level>`. Never hand-edit the five version
   fields — the script is the only supported way to change them.
4. Run `./scripts/validate.sh` and report the result.
5. Show `git status` and remind that the bump still needs a commit on a branch and a
   PR. Do not commit or push unless explicitly asked.

If `bump.sh` refuses because the version fields are out of sync, do not work around
it. Report the mismatch it printed and ask how to reconcile.
