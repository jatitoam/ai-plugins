---
description: Install or repoint the delegation canon at the system-prompt layer (edits your shell rc).
argument-hint: "[--dry-run | --uninstall | --rc <path>]"
---

Install the delegation canon so it reaches Claude Code's **system prompt**, where
it can override the hard-coded "do not call the AgentTool unless the user
requested it" restriction.

Do this in order, and do not skip the dry run:

1. Run the installer in preview mode and show the user its full output:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/skills/delegation-ladder/scripts/install-canon.sh" --dry-run
   ```

2. If the dry run exits non-zero with an unsupported-shell or unsupported-platform
   error (fish, Windows, or a shell it cannot place safely), **stop**. Relay the
   script's own instructions verbatim — it prints the hand-written equivalent or
   the `--rc <path>` it needs — and do not try to work around it by picking an rc
   file yourself. Guessing a target is the failure the detection exists to prevent.

3. Otherwise, explain in one or two lines what will change in their shell rc file,
   name the file the dry run reported, and ask for explicit confirmation. This
   edits a file outside the repository — do not proceed without a yes.

4. On confirmation, run it for real:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/skills/delegation-ladder/scripts/install-canon.sh"
   ```

5. Report the backup path it printed and **the rc file it actually targeted** —
   the script detects this from the user's login shell (zsh or bash), so do not
   assume `~/.zshrc`. Tell the user to run `source <that file>`
   (or open a new terminal), then verify with `type claude` — the function should
   pass `--append-system-prompt-file` pointing at the stable canon copy
   (`~/.claude-delegation/canon.md` by default), not at the plugin directory.
   The plugin's SessionStart hook keeps that copy in sync on later updates.

If the user passes `--uninstall`, `--rc <path>`, or any other argument to this
command, forward it to the script verbatim.
