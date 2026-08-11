#!/usr/bin/env bash
# install-canon.sh
#
# Wires up a zsh `claude` wrapper function that passes
# `--append-system-prompt-file <canon.md>` so Claude Code's hard-coded
# "don't call the AgentTool unless requested" restriction is overridden
# with this plugin's delegation canon.
#
# Usage:
#   install-canon.sh [--rc <path>] [--dry-run] [--uninstall] [--sync] [-h|--help]
#
# See the delegation-ladder skill's SKILL.md for context.

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

MARKER_BEGIN="# >>> code-general:delegation-canon >>>"
MARKER_END="# <<< code-general:delegation-canon <<<"
CANON_VAR_NAME="_CLAUDE_DELEGATION_CANON"
PREV_MARKER_PREFIX="# code-general:delegation-canon previous value: "

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_CANON="$SKILL_DIR/references/delegation-canon.md"

# The rc file must NOT point at $PLUGIN_CANON directly: installed plugins live
# at a version-scoped path (~/.claude*/plugins/cache/<mkt>/<plugin>/<version>/),
# so a direct reference pins the canon to the version installed today and breaks
# when that version is pruned. Instead the canon is copied to a stable path that
# survives plugin updates and uninstalls, and the plugin's SessionStart hook
# re-syncs it (`--sync`) on every session so updates propagate on their own.
CANON="${CLAUDE_DELEGATION_CANON_PATH:-$HOME/.claude-delegation/canon.md}"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

MODE="install"
DRY_RUN=0
RC_OVERRIDE=""

print_help() {
  cat <<EOF
Usage: $SCRIPT_NAME [--rc <path>] [--dry-run] [--uninstall] [--sync] [-h|--help]

Wires (or removes) a 'claude' wrapper function that appends this plugin's
delegation canon via --append-system-prompt-file.

The target rc file is detected from your login shell (\$SHELL) unless you
name one explicitly. zsh and bash are supported; fish and Windows are not.

The canon is copied from the plugin to a stable path so it survives plugin
version bumps; the rc file points at that stable copy.

  plugin copy: $PLUGIN_CANON
  stable copy: $CANON

Options:
  --rc <path>   Target rc file (default: \$SHELL_RC, else detected from \$SHELL:
                zsh -> \${ZDOTDIR:-\$HOME}/.zshrc, bash -> ~/.bashrc or ~/.bash_profile)
  --dry-run     Print what would change; write nothing; exit 0
  --uninstall   Remove the managed block (or warn about an adopted wrapper)
  --sync        Refresh the stable canon copy only; touch no rc file. Silent on
                stdout — this is what the plugin's SessionStart hook runs.
  -h, --help    Show this help

Environment:
  SHELL_RC                      Overrides the default rc file (lower priority than --rc)
  CLAUDE_DELEGATION_CANON_PATH  Overrides the stable canon path
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rc)
      [[ $# -ge 2 ]] || { echo "$SCRIPT_NAME: error: --rc requires a path argument" >&2; exit 1; }
      RC_OVERRIDE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --uninstall)
      MODE="uninstall"
      shift
      ;;
    --sync)
      MODE="sync"
      shift
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      echo "$SCRIPT_NAME: error: unknown argument: $1" >&2
      print_help >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Platform and shell detection
# ---------------------------------------------------------------------------
#
# Resolving the rc file is deliberately deferred to do_install/do_uninstall
# rather than done here: --sync touches no rc file at all, and it is what the
# SessionStart hook runs on every session. It must never fail because the user
# happens to be on a shell or platform this installer cannot wire up.

RC_FILE=""
DETECTED_SHELL=""

# True (0) on Windows-native shells. WSL is deliberately excluded: it is a
# Linux userland where the normal zsh/bash path works.
is_windows() {
  case "${OS:-}" in
    Windows_NT) return 0 ;;
  esac
  case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
  esac
  return 1
}

# Basename of the user's login shell ("zsh", "bash", "fish"), or empty if it
# cannot be determined. $SHELL is the right signal and $BASH_VERSION is not:
# this script always runs under bash via its shebang, whatever shell the user
# actually lives in.
#
# Must always succeed: the caller assigns it with DETECTED_SHELL="$(detect_shell)",
# and a nonzero return from a plain assignment kills the script under `set -e`
# with no diagnostic at all — the exact silent failure this file exists to stop.
# $SHELL set-but-empty is routine under launchd, systemd, CI and `docker exec`.
detect_shell() {
  local s="${SHELL:-}"
  if [[ -n "$s" ]]; then
    printf '%s' "${s##*/}"
  fi
  return 0
}

# Prints the rc file a given shell actually reads, or nothing if this script
# does not support that shell.
default_rc_for_shell() {
  local shell_name="$1"
  local candidates=()
  case "$shell_name" in
    zsh)
      printf '%s' "${ZDOTDIR:-$HOME}/.zshrc"
      return 0
      ;;
    bash)
      # Which file bash reads depends on how the terminal starts it, and the
      # answer differs per platform. Terminal.app and iTerm start *login*
      # shells, which read .bash_profile/.bash_login/.profile and never .bashrc
      # unless one of those sources it — so on Darwin, preferring an existing
      # .bashrc would reintroduce the silent failure this detection exists to
      # prevent. Most Linux terminals start interactive non-login shells, which
      # read .bashrc. Only files the shell would actually source are candidates;
      # within that set, prefer one that already exists.
      if [[ "$(uname -s 2>/dev/null || true)" == "Darwin" ]]; then
        candidates=("$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile")
      else
        candidates=("$HOME/.bashrc")
      fi
      local f
      for f in "${candidates[@]}"; do
        [[ -f "$f" ]] && { printf '%s' "$f"; return 0; }
      done
      printf '%s' "${candidates[0]}"
      return 0
      ;;
  esac
  return 0
}

# Follows a symlink chain to the file that actually holds the content. Dotfiles
# are commonly symlinks into a managed repo (~/.zshrc -> ~/dotfiles/zshrc), and
# writing via `mv` would replace the *link* with a regular file — silently
# detaching the user's repo while reporting success. `readlink -f` is not
# portable to older macOS, hence the loop. Always succeeds; on a cycle or an
# unreadable link it returns the path unchanged.
resolve_symlink() {
  local p="$1"
  local target dir i=0
  while [[ -L "$p" ]]; do
    i=$((i + 1))
    if [[ "$i" -gt 20 ]]; then
      printf '%s' "$p"
      return 0
    fi
    target="$(readlink "$p" 2>/dev/null || true)"
    if [[ -z "$target" ]]; then
      printf '%s' "$p"
      return 0
    fi
    if [[ "$target" == /* ]]; then
      p="$target"
    else
      dir="$(dirname "$p")"
      p="$dir/$target"
    fi
  done
  printf '%s' "$p"
  return 0
}

# Sets RC_FILE (and DETECTED_SHELL). $1 is "install" (refuse when the target
# cannot be determined safely) or "uninstall" (exit 0 — there is nothing this
# script could have written on a shell it refuses to write to).
resolve_rc_file() {
  local mode="${1:-install}"

  if is_windows; then
    {
      echo "$SCRIPT_NAME: error: Windows is not supported (for now)."
      echo "$SCRIPT_NAME: the wrapper is a POSIX shell function written into a shell rc file;"
      echo "$SCRIPT_NAME: there is no cmd.exe or PowerShell equivalent here yet."
      echo "$SCRIPT_NAME: under WSL, run this from inside the Linux userland instead."
    } >&2
    exit 1
  fi

  DETECTED_SHELL="$(detect_shell)"

  # fish is refused even with an explicit --rc: the managed block is POSIX
  # function syntax, which fish cannot parse. Writing it into config.fish would
  # break shell startup outright, not merely fail to take effect.
  if [[ "$DETECTED_SHELL" == "fish" ]]; then
    if [[ "$mode" == "uninstall" ]]; then
      echo "$SCRIPT_NAME: fish detected; this script never writes a wrapper for fish. Nothing to uninstall." >&2
      exit 0
    fi
    {
      echo "$SCRIPT_NAME: error: fish is not supported — its syntax cannot parse the POSIX function this script writes."
      echo "$SCRIPT_NAME: add the equivalent to your config.fish by hand:"
      echo "$SCRIPT_NAME:"
      echo "$SCRIPT_NAME:     function claude"
      echo "$SCRIPT_NAME:         command claude --append-system-prompt-file $CANON \$argv"
      echo "$SCRIPT_NAME:     end"
      echo "$SCRIPT_NAME:"
      echo "$SCRIPT_NAME: then copy the canon into place yourself:"
      echo "$SCRIPT_NAME:     mkdir -p $(dirname "$CANON") && cp $PLUGIN_CANON $CANON"
    } >&2
    exit 1
  fi

  local implied
  implied="$(default_rc_for_shell "$DETECTED_SHELL")"

  if [[ -n "$RC_OVERRIDE" ]]; then
    RC_FILE="$RC_OVERRIDE"
  elif [[ -n "${SHELL_RC:-}" ]]; then
    RC_FILE="$SHELL_RC"
  else
    RC_FILE="$implied"
  fi

  if [[ -z "$RC_FILE" ]]; then
    # Unsupported or undetectable shell, and no explicit target given. Guessing
    # here is what produced the silent failure this function prevents: a valid
    # block written into a file the user's shell never reads.
    if [[ "$mode" == "uninstall" ]]; then
      echo "$SCRIPT_NAME: could not determine an rc file for shell '${DETECTED_SHELL:-unknown}'; pass --rc <path> if you wired one up by hand." >&2
      exit 0
    fi
    {
      local shell_desc
      if [[ -z "${SHELL+set}" ]]; then
        shell_desc="\$SHELL is unset"
      elif [[ -z "$SHELL" ]]; then
        shell_desc="\$SHELL is set but empty"
      else
        shell_desc="\$SHELL=$SHELL"
      fi
      echo "$SCRIPT_NAME: error: unsupported or undetectable login shell ($shell_desc)."
      echo "$SCRIPT_NAME: this script wires up zsh and bash automatically."
      echo "$SCRIPT_NAME: if your shell reads a POSIX-syntax rc file, name it explicitly:"
      echo "$SCRIPT_NAME:     $SCRIPT_NAME --rc <path-to-your-rc-file>"
    } >&2
    exit 1
  fi

  if [[ -L "$RC_FILE" ]]; then
    local resolved
    resolved="$(resolve_symlink "$RC_FILE")"
    if [[ -n "$resolved" && "$resolved" != "$RC_FILE" ]]; then
      echo "$SCRIPT_NAME: note: $RC_FILE is a symlink; writing through it to $resolved." >&2
      RC_FILE="$resolved"
    fi
  fi

  # A path that exists but is not a regular file cannot be an rc file, and `mv`
  # into a directory *succeeds* — it drops the temp file inside and installs
  # nothing, while every message downstream reports success.
  if [[ -e "$RC_FILE" && ! -f "$RC_FILE" ]]; then
    echo "$SCRIPT_NAME: error: $RC_FILE exists but is not a regular file; refusing to write to it." >&2
    exit 1
  fi

  # An explicit target that contradicts the detected shell is allowed — the user
  # said where — but it gets called out, because a wrapper in a file the login
  # shell never reads fails silently rather than loudly.
  if [[ -n "$RC_OVERRIDE" || -n "${SHELL_RC:-}" ]]; then
    if [[ -n "$implied" && "$implied" != "$RC_FILE" ]]; then
      echo "$SCRIPT_NAME: note: targeting $RC_FILE, but your login shell (${DETECTED_SHELL:-unknown}) reads $implied." >&2
      echo "$SCRIPT_NAME: note: make sure $RC_FILE is sourced at startup, or the wrapper will never load." >&2
    fi
  fi
}

# ---------------------------------------------------------------------------
# Temp file bookkeeping / cleanup
# ---------------------------------------------------------------------------

TMP_FILES=()
cleanup() {
  # Preserve the real exit status: without this, the last command run
  # inside this trap (e.g. a false `[[ ]]` test) would silently become
  # the script's final exit code.
  local rc=$?
  local f
  if [[ ${#TMP_FILES[@]} -gt 0 ]]; then
    for f in "${TMP_FILES[@]}"; do
      [[ -n "$f" && -f "$f" ]] && rm -f "$f"
    done
  fi
  exit "$rc"
}
trap cleanup EXIT

# Creates a temp file beside the rc file and reports its path in TMP_LAST.
# It sets a global rather than printing one, deliberately: callers would write
# `t="$(mk_tmp)"`, which runs the TMP_FILES append inside a command-substitution
# subshell, so the parent's cleanup trap would never learn the file exists and
# any failure before the `mv` would strand it in the user's home directory.
TMP_LAST=""
mk_tmp() {
  local dir
  dir="$(dirname "$RC_FILE")"
  TMP_LAST="$(mktemp "$dir/.install-canon.XXXXXX")"
  TMP_FILES+=("$TMP_LAST")
}

# Prints a file's permission bits (e.g. 644). Empty if they cannot be read.
file_mode() {
  stat -f '%OLp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Canon existence check (required at runtime, not at parse time)
# ---------------------------------------------------------------------------

require_canon() {
  if [[ ! -f "$PLUGIN_CANON" ]]; then
    echo "$SCRIPT_NAME: error: canon file not found at $PLUGIN_CANON" >&2
    echo "$SCRIPT_NAME: expected it at ../references/delegation-canon.md relative to this script" >&2
    exit 1
  fi
}

# Copy the plugin's canon to the stable path if it is missing or stale.
# Never writes to stdout: the SessionStart hook runs this, and hook stdout is
# injected into the session as context.
#
# $1: "create" to create the stable copy when absent (install), anything else
#     (default) to refresh only a copy that already exists — the hook must not
#     scatter files on machines where the wrapper was never installed.
sync_canon() {
  local mode="${1:-refresh-only}"
  require_canon
  if [[ ! -f "$CANON" && "$mode" != "create" ]]; then
    return 0
  fi
  if [[ -f "$CANON" ]] && cmp -s "$PLUGIN_CANON" "$CANON"; then
    return 0
  fi
  local dir tmp
  dir="$(dirname "$CANON")"
  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.canon.XXXXXX")"
  TMP_FILES+=("$tmp")
  cat "$PLUGIN_CANON" >"$tmp"
  mv "$tmp" "$CANON"
  TMP_FILES=("${TMP_FILES[@]/$tmp}")
  echo "$SCRIPT_NAME: refreshed $CANON from $PLUGIN_CANON" >&2
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

read_file_or_empty() {
  local f="$1"
  if [[ -f "$f" ]]; then
    cat "$f"
  else
    printf ''
  fi
}

# True (0) if $1 contains the exact managed-block markers as whole lines.
has_managed_block() {
  local content="$1"
  grep -qxF "$MARKER_BEGIN" <<<"$content" && grep -qxF "$MARKER_END" <<<"$content"
}

# Both slicing functions below assume BEGIN precedes END. If a hand edit or a
# bad merge inverted them, head/tail ranges overlap and the file *duplicates*
# content on every run instead of being rewritten. Refuse and let the user look.
assert_markers_ordered() {
  local content="$1"
  local begin_line end_line
  begin_line="$(find_line_number "$content" "$MARKER_BEGIN")"
  end_line="$(find_line_number "$content" "$MARKER_END")"
  if [[ -z "$begin_line" || -z "$end_line" || "$begin_line" -ge "$end_line" ]]; then
    {
      echo "$SCRIPT_NAME: error: the managed-block markers in $RC_FILE are out of order"
      echo "$SCRIPT_NAME: (begin at line ${begin_line:-none}, end at line ${end_line:-none})."
      echo "$SCRIPT_NAME: rewriting from here would duplicate content rather than replace it."
      echo "$SCRIPT_NAME: fix the block by hand — it runs from '$MARKER_BEGIN'"
      echo "$SCRIPT_NAME: to '$MARKER_END' — then re-run."
    } >&2
    exit 1
  fi
}

# Prints the line number (1-based) of the first line assigning
# _CLAUDE_DELEGATION_CANON=, or nothing if none found.
find_canon_var_line() {
  local content="$1"
  # `|| true`: grep exits 1 on no match, which under pipefail would make
  # this pipeline (and its command substitution caller) fail under set -e.
  grep -n "^${CANON_VAR_NAME}=" <<<"$content" | head -n1 | cut -d: -f1 || true
}

# Prints the current value (unquoted) of the first _CLAUDE_DELEGATION_CANON=
# assignment, or nothing if none found.
find_canon_var_value() {
  local content="$1"
  local line
  line="$(grep "^${CANON_VAR_NAME}=" <<<"$content" | head -n1 || true)"
  [[ -z "$line" ]] && return 0
  line="${line#${CANON_VAR_NAME}=}"
  # strip a single layer of surrounding quotes, if present
  line="${line%\"}"; line="${line#\"}"
  line="${line%\'}"; line="${line#\'}"
  printf '%s' "$line"
}

# Resolve the real claude binary. Fails loudly rather than guessing: a wrong
# path here produces a wrapper that shadows a working `claude` with a broken one.
resolve_claude_bin() {
  local found
  found="$(command -v claude 2>/dev/null || true)"
  if [[ "$found" == /* ]]; then
    printf '%s' "$found"
    return 0
  fi
  # `command -v` returns a bare name when `claude` is already a shell function
  # or alias in the calling shell, which tells us nothing about the binary.
  if [[ -x "$HOME/.local/bin/claude" ]]; then
    printf '%s' "$HOME/.local/bin/claude"
    return 0
  fi
  echo "$SCRIPT_NAME: error: could not resolve the claude binary." >&2
  echo "$SCRIPT_NAME: 'command -v claude' gave '${found:-nothing}' and $HOME/.local/bin/claude is not executable." >&2
  echo "$SCRIPT_NAME: install Claude Code first, or add the wrapper to your rc file by hand." >&2
  exit 1
}

# True (0) if the content defines a claude()/claude-<something>() shell function.
has_claude_function() {
  local content="$1"
  grep -qE '^[[:space:]]*claude(-[A-Za-z0-9_-]+)?[[:space:]]*\(\)' <<<"$content"
}

build_managed_block() {
  local claude_bin
  claude_bin="$(resolve_claude_bin)"
  cat <<EOF
$MARKER_BEGIN
_CLAUDE_BIN="$claude_bin"
${CANON_VAR_NAME}="$CANON"

claude() {
  # Degrade instead of failing: claude exits with an error if the file passed to
  # --append-system-prompt-file is missing, which would break every invocation.
  if [ -f "\$${CANON_VAR_NAME}" ]; then
    "\$_CLAUDE_BIN" --append-system-prompt-file "\$${CANON_VAR_NAME}" "\$@"
  else
    echo "warning: delegation canon missing at \$${CANON_VAR_NAME}; launching without it" >&2
    "\$_CLAUDE_BIN" "\$@"
  fi
}
$MARKER_END
EOF
}

# Prints the 1-based line number of the first line in $1 that exactly
# matches $2, or nothing if not found.
find_line_number() {
  local content="$1"
  local needle="$2"
  grep -nxF "$needle" <<<"$content" | head -n1 | cut -d: -f1 || true
}

# Replaces the existing managed block (markers inclusive) in $1 with a
# freshly generated block ($2). Prints the new full content.
#
# Deliberately implemented with head/tail line slicing rather than awk:
# macOS's default awk (the "one true awk") rejects multi-line strings
# passed via -v ("newline in string"), and the managed block is
# multi-line, so it cannot safely be threaded through awk -v.
replace_managed_block() {
  local content="$1"
  local block="$2"
  local begin_line end_line total_lines
  begin_line="$(find_line_number "$content" "$MARKER_BEGIN")"
  end_line="$(find_line_number "$content" "$MARKER_END")"
  total_lines="$(printf '%s\n' "$content" | wc -l | tr -d ' ')"

  if [[ "$begin_line" -gt 1 ]]; then
    printf '%s\n' "$content" | head -n "$((begin_line - 1))"
  fi
  printf '%s\n' "$block"
  if [[ "$end_line" -lt "$total_lines" ]]; then
    printf '%s\n' "$content" | tail -n "+$((end_line + 1))"
  fi
}

# Rewrites only the value of the first _CLAUDE_DELEGATION_CANON= line in $1
# to $2 (already the desired quoted value, e.g. "\"/path\""). Prints the new
# full content.
#
# The first time it does this it records the pre-existing value in a comment
# directly above the line, so --uninstall can put it back. If that comment is
# already there it is left alone: it holds the true pre-plugin value.
rewrite_canon_var_line() {
  local content="$1"
  local new_value_quoted="$2"
  local prev_comment=""
  if ! grep -q "^${PREV_MARKER_PREFIX}" <<<"$content"; then
    local old_line
    old_line="$(grep "^${CANON_VAR_NAME}=" <<<"$content" | head -n1 || true)"
    prev_comment="${PREV_MARKER_PREFIX}${old_line#${CANON_VAR_NAME}=}"
  fi
  # Values arrive via the environment, not `awk -v`: -v processes backslash
  # escapes in the assigned value, so a path containing \t would be recorded
  # (and later restored) as a literal tab. This is the one path whose entire
  # job is faithful restoration of the user's original line.
  CANON_AWK_VAR="$CANON_VAR_NAME" \
  CANON_AWK_NEW="$new_value_quoted" \
  CANON_AWK_PREV="$prev_comment" \
  awk '
    BEGIN {
      var = ENVIRON["CANON_AWK_VAR"]
      newval = ENVIRON["CANON_AWK_NEW"]
      prev = ENVIRON["CANON_AWK_PREV"]
      done = 0; pat = "^" var "="
    }
    !done && $0 ~ pat {
      if (prev != "") print prev
      print var "=" newval
      done = 1
      next
    }
    { print }
  ' <<<"$content"
}

# Restores the recorded pre-plugin value and drops the marker comment.
# Prints the new full content.
restore_canon_var_line() {
  local content="$1"
  local prev_value
  prev_value="$(grep "^${PREV_MARKER_PREFIX}" <<<"$content" | head -n1 || true)"
  prev_value="${prev_value#${PREV_MARKER_PREFIX}}"
  # Via the environment, not `awk -v` — see rewrite_canon_var_line.
  CANON_AWK_VAR="$CANON_VAR_NAME" \
  CANON_AWK_OLD="$prev_value" \
  CANON_AWK_PREFIX="$PREV_MARKER_PREFIX" \
  awk '
    BEGIN {
      var = ENVIRON["CANON_AWK_VAR"]
      oldval = ENVIRON["CANON_AWK_OLD"]
      prefix = ENVIRON["CANON_AWK_PREFIX"]
      done = 0; pat = "^" var "="; ppat = "^" prefix
    }
    $0 ~ ppat { next }
    !done && $0 ~ pat { print var "=" oldval; done = 1; next }
    { print }
  ' <<<"$content"
}

# Removes the managed block (markers inclusive) from $1. Prints new content.
remove_managed_block() {
  local content="$1"
  local begin_line end_line total_lines
  begin_line="$(find_line_number "$content" "$MARKER_BEGIN")"
  end_line="$(find_line_number "$content" "$MARKER_END")"
  total_lines="$(printf '%s\n' "$content" | wc -l | tr -d ' ')"

  if [[ "$begin_line" -gt 1 ]]; then
    printf '%s\n' "$content" | head -n "$((begin_line - 1))"
  fi
  if [[ "$end_line" -lt "$total_lines" ]]; then
    printf '%s\n' "$content" | tail -n "+$((end_line + 1))"
  fi
}

# Appends the managed block to $1 (old content), returning new full content.
append_managed_block() {
  local content="$1"
  local block="$2"
  if [[ -z "$content" ]]; then
    printf '%s\n' "$block"
  else
    printf '%s\n\n%s\n' "$content" "$block"
  fi
}

backup_rc() {
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  local backup="${RC_FILE}.bak.${ts}"
  # Two runs in the same second must not overwrite the first run's backup —
  # that backup may be the only copy of the pre-install rc file.
  local n=1
  while [[ -e "$backup" ]]; do
    backup="${RC_FILE}.bak.${ts}.${n}"
    n=$((n + 1))
  done
  cp "$RC_FILE" "$backup"
  # rc files routinely hold exported secrets; don't widen their exposure.
  chmod 600 "$backup"
  echo "$SCRIPT_NAME: backed up $RC_FILE -> $backup (mode 600)"
}

# Writes $2 (new content) into $1 (rc file path) safely: temp file + mv.
write_rc() {
  local rc_file="$1"
  local new_content="$2"
  # Preserve the rc file's existing permissions: mktemp creates at 600, and
  # that mode would otherwise survive the `mv` and silently tighten a file the
  # user may deliberately keep group- or world-readable.
  local mode=""
  [[ -f "$rc_file" ]] && mode="$(file_mode "$rc_file")"

  local tmp
  mk_tmp
  tmp="$TMP_LAST"
  printf '%s\n' "$new_content" >"$tmp"
  mv "$tmp" "$rc_file"
  [[ -n "$mode" ]] && chmod "$mode" "$rc_file"
  # mv succeeded; remove from cleanup list so trap doesn't try to delete
  # the now-relocated (nonexistent at tmp path) file.
  local kept=()
  local f
  if [[ ${#TMP_FILES[@]} -gt 0 ]]; then
    for f in "${TMP_FILES[@]}"; do
      [[ "$f" == "$tmp" ]] || kept+=("$f")
    done
  fi
  if [[ ${#kept[@]} -gt 0 ]]; then
    TMP_FILES=("${kept[@]}")
  else
    TMP_FILES=()
  fi
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

do_install() {
  resolve_rc_file install
  require_canon

  local old_content
  old_content="$(read_file_or_empty "$RC_FILE")"

  local new_content=""
  local action_desc=""

  if has_managed_block "$old_content"; then
    assert_markers_ordered "$old_content"
    local block
    block="$(build_managed_block)"
    new_content="$(replace_managed_block "$old_content" "$block")"
    action_desc="replaced managed block with a freshly generated one"
  else
    local var_line
    var_line="$(find_canon_var_line "$old_content")"
    # Adopting requires a wrapper to adopt. A bare variable assignment with no
    # claude() function around it installs nothing, and reporting success there
    # sends the user off to run `type claude` on a wrapper that doesn't exist —
    # the likely path being someone who followed half of the refusal message
    # below and then re-ran.
    if [[ -n "$var_line" ]] && ! has_claude_function "$old_content"; then
      {
        echo "$SCRIPT_NAME: error: $RC_FILE has a ${CANON_VAR_NAME}= line but no claude() function to use it."
        echo "$SCRIPT_NAME: setting the variable alone installs nothing."
        echo "$SCRIPT_NAME: either delete that line and re-run (this script will write the whole wrapper),"
        echo "$SCRIPT_NAME: or add a claude() function that passes:"
        echo "$SCRIPT_NAME:     --append-system-prompt-file \"\$${CANON_VAR_NAME}\""
      } >&2
      exit 1
    fi
    if [[ -n "$var_line" ]]; then
      local quoted="\"$CANON\""
      new_content="$(rewrite_canon_var_line "$old_content" "$quoted")"
      action_desc="adopted existing hand-written wrapper (rewrote ${CANON_VAR_NAME}= to point at plugin canon)"
    elif has_claude_function "$old_content"; then
      # Appending our own claude() here would define a second function later in
      # the file, silently shadowing theirs — and with it any CLAUDE_CONFIG_DIR
      # or other flags it sets. Refuse and let the user wire it up.
      {
        echo "$SCRIPT_NAME: error: $RC_FILE already defines a claude() function that this script did not write,"
        echo "$SCRIPT_NAME: and there is no ${CANON_VAR_NAME}= line to adopt. Appending our own wrapper would"
        echo "$SCRIPT_NAME: shadow yours and drop whatever it sets (e.g. CLAUDE_CONFIG_DIR). Refusing."
        echo "$SCRIPT_NAME:"
        echo "$SCRIPT_NAME: Fix it by hand: add this line above your function,"
        echo "$SCRIPT_NAME:     ${CANON_VAR_NAME}=\"$CANON\""
        echo "$SCRIPT_NAME: and pass --append-system-prompt-file \"\$${CANON_VAR_NAME}\" inside it."
        echo "$SCRIPT_NAME: Then re-run this script; it will adopt and maintain that line."
        echo "$SCRIPT_NAME: Existing definition(s):"
        grep -nE '^[[:space:]]*claude(-[A-Za-z0-9_-]+)?[[:space:]]*\(\)' <<<"$old_content" || true
      } >&2
      exit 1
    else
      local block
      block="$(build_managed_block)"
      new_content="$(append_managed_block "$old_content" "$block")"
      action_desc="appended a new managed block (no existing wrapper found)"
    fi
  fi

  if [[ "$old_content" == "$new_content" ]]; then
    echo "$SCRIPT_NAME: $RC_FILE already points at $CANON; nothing to do."
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "$SCRIPT_NAME: [dry-run] login shell: ${DETECTED_SHELL:-unknown}; target rc: $RC_FILE"
    echo "$SCRIPT_NAME: [dry-run] would copy $PLUGIN_CANON -> $CANON"
    echo "$SCRIPT_NAME: [dry-run] would then: $action_desc in $RC_FILE"
    echo "$SCRIPT_NAME: [dry-run] --- diff ---"
    diff <(printf '%s\n' "$old_content") <(printf '%s\n' "$new_content") || true
    return 0
  fi

  # Deferred until every refusal above has passed: a refused install must not
  # leave the stable canon copy behind on a machine it never wired up.
  sync_canon create

  if [[ ! -f "$RC_FILE" ]]; then
    echo "$SCRIPT_NAME: $RC_FILE does not exist; it will be created."
  else
    backup_rc
  fi

  write_rc "$RC_FILE" "$new_content"
  echo "$SCRIPT_NAME: $action_desc in $RC_FILE"

  cat <<EOF

Next steps:
  1. Reload your shell config:
       source "$RC_FILE"
     (or just open a new terminal)
  2. Verify the wrapper is active:
       type claude
     should show a shell function (not just a binary path).
  3. Verify the canon file is readable:
       head -1 "$CANON"

The rc file points at the stable copy above, not at the plugin directory.
The plugin's SessionStart hook re-syncs that copy every session, so
'claude plugin update' propagates canon changes with no re-run of this script
(they take effect the session after the update).
EOF
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

do_uninstall() {
  resolve_rc_file uninstall

  local old_content
  old_content="$(read_file_or_empty "$RC_FILE")"

  if [[ ! -f "$RC_FILE" ]]; then
    echo "$SCRIPT_NAME: $RC_FILE does not exist; nothing to uninstall."
    return 0
  fi

  if has_managed_block "$old_content"; then
    assert_markers_ordered "$old_content"
    local new_content
    new_content="$(remove_managed_block "$old_content")"

    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "$SCRIPT_NAME: [dry-run] would remove managed block from $RC_FILE"
      echo "$SCRIPT_NAME: [dry-run] --- diff ---"
      diff <(printf '%s\n' "$old_content") <(printf '%s\n' "$new_content") || true
      return 0
    fi

    backup_rc
    write_rc "$RC_FILE" "$new_content"
    echo "$SCRIPT_NAME: removed managed block from $RC_FILE"
    echo "$SCRIPT_NAME: note: the stable canon copy at $CANON was left in place; delete it yourself if you want it gone."
    return 0
  fi

  local var_value
  var_value="$(find_canon_var_value "$old_content")"
  if [[ -n "$var_value" && "$var_value" == "$CANON" ]]; then
    # Adopted hand-written wrapper. If we recorded the pre-plugin value on
    # install, put it back; the user's own functions are never touched.
    if grep -q "^${PREV_MARKER_PREFIX}" <<<"$old_content"; then
      local new_content
      new_content="$(restore_canon_var_line "$old_content")"

      if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "$SCRIPT_NAME: [dry-run] would restore the previous ${CANON_VAR_NAME} value in $RC_FILE"
        echo "$SCRIPT_NAME: [dry-run] --- diff ---"
        diff <(printf '%s\n' "$old_content") <(printf '%s\n' "$new_content") || true
        return 0
      fi

      backup_rc
      write_rc "$RC_FILE" "$new_content"
      echo "$SCRIPT_NAME: restored the previous ${CANON_VAR_NAME} value in $RC_FILE; your claude() functions were left untouched."
      echo "$SCRIPT_NAME: note: the stable canon copy at $CANON was left in place; delete it yourself if you want it gone."
      return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "$SCRIPT_NAME: [dry-run] would back up $RC_FILE and then warn (no content change)" >&2
      return 0
    fi
    backup_rc
    {
      echo "$SCRIPT_NAME: warning: found a hand-written ${CANON_VAR_NAME}= line pointing at"
      echo "$SCRIPT_NAME: warning: this plugin's canon file, with no recorded previous value."
      echo "$SCRIPT_NAME: warning: it is not inside a managed block, so it will NOT be removed"
      echo "$SCRIPT_NAME: warning: automatically (your claude()/claude-*() functions were"
      echo "$SCRIPT_NAME: warning: hand-written and are left untouched)."
      echo "$SCRIPT_NAME: warning: line found:"
      grep -n "^${CANON_VAR_NAME}=" <<<"$old_content" | head -n1 || true
      echo "$SCRIPT_NAME: warning: edit or remove it yourself in $RC_FILE if you want to fully uninstall."
    } >&2
    return 0
  fi

  echo "$SCRIPT_NAME: no managed block and no adopted wrapper found for this plugin's canon path in $RC_FILE; nothing to do."

  # Versions of this script before shell detection wrote the block to
  # ${ZDOTDIR:-$HOME}/.zshrc regardless of which shell the user actually ran,
  # so a bash user who installed back then has a block sitting in a file this
  # run never looks at. Point at it instead of leaving them to find it.
  local other found=""
  for other in "${ZDOTDIR:-$HOME}/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
    [[ "$other" == "$RC_FILE" || ! -f "$other" ]] && continue
    if grep -qxF "$MARKER_BEGIN" "$other" 2>/dev/null; then
      found="$found $other"
    fi
  done
  if [[ -n "$found" ]]; then
    {
      echo "$SCRIPT_NAME: note: a managed block from this plugin is still present in:$found"
      echo "$SCRIPT_NAME: note: (earlier versions wrote to ~/.zshrc regardless of your login shell)."
      echo "$SCRIPT_NAME: note: remove it with: $SCRIPT_NAME --uninstall --rc <that file>"
    } >&2
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

case "$MODE" in
  install)
    do_install
    ;;
  uninstall)
    do_uninstall
    ;;
  sync)
    sync_canon
    ;;
esac
