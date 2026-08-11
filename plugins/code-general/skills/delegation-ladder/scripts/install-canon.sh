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

Wires (or removes) a zsh 'claude' wrapper function that appends this
plugin's delegation canon via --append-system-prompt-file.

The canon is copied from the plugin to a stable path so it survives plugin
version bumps; the rc file points at that stable copy.

  plugin copy: $PLUGIN_CANON
  stable copy: $CANON

Options:
  --rc <path>   Target rc file (default: \$SHELL_RC, else \${ZDOTDIR:-\$HOME}/.zshrc)
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

if [[ -n "$RC_OVERRIDE" ]]; then
  RC_FILE="$RC_OVERRIDE"
elif [[ -n "${SHELL_RC:-}" ]]; then
  RC_FILE="$SHELL_RC"
else
  RC_FILE="${ZDOTDIR:-$HOME}/.zshrc"
fi

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

mk_tmp() {
  local dir
  dir="$(dirname "$RC_FILE")"
  local t
  t="$(mktemp "$dir/.install-canon.XXXXXX")"
  TMP_FILES+=("$t")
  printf '%s' "$t"
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
  awk -v var="$CANON_VAR_NAME" -v newval="$new_value_quoted" -v prev="$prev_comment" '
    BEGIN { done = 0; pat = "^" var "=" }
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
  awk -v var="$CANON_VAR_NAME" -v oldval="$prev_value" -v prefix="$PREV_MARKER_PREFIX" '
    BEGIN { done = 0; pat = "^" var "="; ppat = "^" prefix }
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
  cp "$RC_FILE" "$backup"
  # rc files routinely hold exported secrets; don't widen their exposure.
  chmod 600 "$backup"
  echo "$SCRIPT_NAME: backed up $RC_FILE -> $backup (mode 600)"
}

# Writes $2 (new content) into $1 (rc file path) safely: temp file + mv.
write_rc() {
  local rc_file="$1"
  local new_content="$2"
  local tmp
  tmp="$(mk_tmp)"
  printf '%s\n' "$new_content" >"$tmp"
  mv "$tmp" "$rc_file"
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
  require_canon
  [[ "$DRY_RUN" -eq 1 ]] || sync_canon create

  local old_content
  old_content="$(read_file_or_empty "$RC_FILE")"

  local new_content=""
  local action_desc=""

  if has_managed_block "$old_content"; then
    local block
    block="$(build_managed_block)"
    new_content="$(replace_managed_block "$old_content" "$block")"
    action_desc="replaced managed block with a freshly generated one"
  else
    local var_line
    var_line="$(find_canon_var_line "$old_content")"
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
    echo "$SCRIPT_NAME: [dry-run] would copy $PLUGIN_CANON -> $CANON"
    echo "$SCRIPT_NAME: [dry-run] would $action_desc in $RC_FILE"
    echo "$SCRIPT_NAME: [dry-run] --- diff ---"
    diff <(printf '%s\n' "$old_content") <(printf '%s\n' "$new_content") || true
    return 0
  fi

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
  local old_content
  old_content="$(read_file_or_empty "$RC_FILE")"

  if [[ ! -f "$RC_FILE" ]]; then
    echo "$SCRIPT_NAME: $RC_FILE does not exist; nothing to uninstall."
    return 0
  fi

  if has_managed_block "$old_content"; then
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
