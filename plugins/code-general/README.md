# code-general

Delegation and orchestration policy for Claude Code: the `delegation-ladder`
skill (a routing gate that decides what to delegate, and to which model tier,
before work starts) plus the canon that authorizes it — the standing,
pre-granted permission to spawn subagents without asking each time.

## Install

```bash
claude plugin marketplace add jatitoam/ai-plugins
claude plugin install code-general@ai-plugins
```

## Post-install setup (required)

The delegation grant is enforced at three layers, strongest first:

| Layer | Mechanism | Active after install? |
|---|---|---|
| System prompt | A `claude()` shell wrapper passing `--append-system-prompt-file <canon>` | **No — requires a manual step** |
| Session context | This plugin's `hooks/hooks.json` SessionStart hook, injecting a pointer to the skill | Yes, automatically |
| Skill | `delegation-ladder`, triggered by its description | Yes, automatically |

The hook and the skill work immediately, no action needed. The system-prompt
layer does not — nothing prompts you to set it up. It's also the layer that
matters most: it's the only one that sits inside the system prompt itself,
where it outranks Claude Code's hard-coded "do not call the AgentTool unless
the user requested it" restriction by recency and specificity. Without it,
the hook and skill can *suggest* delegating, but the underlying restriction
is still in force — delegation stays an ask-first exception rather than
standing policy.

To enable it, run:

```
/code-general:install-delegation-canon
```

This previews the change with `--dry-run`, asks for confirmation, then edits
your shell rc file. Run it deliberately, once, after installing the plugin.

## What the installer does to your machine

`skills/delegation-ladder/scripts/install-canon.sh` (invoked by the slash
command above, or directly):

- Writes a marker-delimited managed block (`# >>> code-general:delegation-canon >>>` … `# <<< … <<<`) into your shell rc — default `${ZDOTDIR:-$HOME}/.zshrc`, overridable with `--rc <path>` or the `SHELL_RC` env var.
- That block defines a `claude()` shell function which calls the real `claude` binary with `--append-system-prompt-file "$_CLAUDE_DELEGATION_CANON"`.
- Copies the canon text to a stable path, `~/.claude-delegation/canon.md` (overridable via `CLAUDE_DELEGATION_CANON_PATH`), and points the rc file there — never at the plugin's own directory. Installed plugins live under a version-scoped path (`~/.claude*/plugins/cache/<marketplace>/<plugin>/<version>/…`); pointing the rc file there would pin it to whatever version happened to be installed the day you ran this, and break the moment that version is pruned.
- Backs up the existing rc file to `<rc>.bak.<timestamp>` at mode 600 before writing.
- Supports `--dry-run` (prints the diff, writes nothing) and `--uninstall`.
- The wrapper degrades gracefully: if the canon file at `$_CLAUDE_DELEGATION_CANON` ever goes missing, `claude()` prints a warning and launches without `--append-system-prompt-file` rather than failing outright.

## Caveats

- Targets **zsh**. Bash users: pass `--rc <path>` to your bash rc file. Fish users: the script won't help — write the wrapper function by hand.
- Takes effect only after you `source <rc>` or open a new terminal; the current shell keeps its old `claude`.
- The installer **refuses to run** if your rc already defines a `claude()` function it didn't write and there's no `_CLAUDE_DELEGATION_CANON=` line to adopt — appending its own wrapper would silently shadow yours (and drop anything it sets, e.g. `CLAUDE_CONFIG_DIR`). It prints manual wiring instructions instead and exits.
- If a `_CLAUDE_DELEGATION_CANON=` line *does* already exist (a hand-written wrapper), the installer adopts it — rewriting the value to point at the canon and recording the previous value in a comment above it, so `--uninstall` can restore it.

## Verify

```bash
source ~/.zshrc   # or open a new terminal
type claude       # should print a shell function, not just a binary path,
                  # passing --append-system-prompt-file at ~/.claude-delegation/canon.md
head -1 ~/.claude-delegation/canon.md   # should be readable
```

## Updating

The SessionStart hook runs `install-canon.sh --sync` on every session, which
refreshes the stable canon copy from the plugin's version whenever they
differ (silent — it never writes to stdout, since hook stdout is injected
into the session as context). This means:

```bash
claude plugin marketplace update ai-plugins
claude plugin update code-general@ai-plugins
```

propagates canon-text edits automatically, with no need to re-run the
installer. Changes take effect the session *after* the update — the shell
wrapper reads the canon file at `claude` launch time, so the session that
performed the update is still running on the old text.

## Uninstall

```
/code-general:install-delegation-canon --uninstall
```

The command forwards any arguments straight to the script, so `--uninstall`,
`--dry-run`, and `--rc <path>` all work through it.

Removes the managed block from the rc file (or, for an adopted hand-written
wrapper, restores the previously recorded `_CLAUDE_DELEGATION_CANON` value
and leaves your `claude()` function untouched). The stable canon copy at
`~/.claude-delegation/canon.md` is deliberately left in place — delete it
yourself if you want it gone.

## What's in the plugin

| Component | Path |
|---|---|
| Skill `delegation-ladder` | `skills/delegation-ladder/SKILL.md` |
| Command `install-delegation-canon` | `commands/install-delegation-canon.md` |
| Hook (SessionStart) | `hooks/hooks.json` → `hooks/delegation-pointer.sh` |

## Scope of the grant

Granted, standing: the Agent tool, including several agents dispatched in
parallel in one message. Not granted: the Workflow tool and deep-research —
those keep their own per-task opt-in.
