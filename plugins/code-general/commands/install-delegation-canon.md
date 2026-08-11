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

2. Explain in one or two lines what will change in their shell rc file, and ask
   for explicit confirmation. This edits a file outside the repository — do not
   proceed without a yes.

3. On confirmation, run it for real:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/skills/delegation-ladder/scripts/install-canon.sh"
   ```

4. Report the backup path it printed, and tell the user to run `source ~/.zshrc`
   (or open a new terminal), then verify with `type claude` — the function should
   pass `--append-system-prompt-file` pointing at the stable canon copy
   (`~/.claude-delegation/canon.md` by default), not at the plugin directory.
   The plugin's SessionStart hook keeps that copy in sync on later updates.

If the user passes `--uninstall`, `--rc <path>`, or any other argument to this
command, forward it to the script verbatim.
