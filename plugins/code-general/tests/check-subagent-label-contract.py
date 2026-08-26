#!/usr/bin/env python3
"""Contract test for the code-general subagent-model-labels skill + guard.

Guards the wiring that a silent edit could rot without any single file
looking wrong: the `PreToolUse` matcher on `Agent` in hooks.json got removed
or mangled while touching the file (the guard stops running, nobody notices
-- a guard that never denies looks identical to no guard), adding the new
matcher-group displaced the pre-existing `SessionStart` entry that points at
delegation-pointer.sh, a guard script lost its executable bit (silently
fails open on every platform that respects the bit), the wrapper lost its
`CODE_GENERAL_LABEL_GUARD` escape hatch or its `command -v python3`
fail-open check (a machine without python3 gets every dispatch blocked
instead of waved through), or the host gate slipped -- the Claude-only skill
drifting back under skills/, vanishing from the Claude manifest's roots, or
the Codex manifest widening past ./skills/ and exposing it.

Scoped to this plugin's own invariants. Registration in plugin.yaml and
index.yaml, frontmatter validity, and undeclared skills on disk are checked
generically by scripts/validate.sh for every plugin -- including a scan of
every `skills*` root, so a Claude-only skill cannot go unregistered -- and
are deliberately not repeated here. Two assertions for one breakage means
two places to update when the generic check moves.

One exception is deliberate: guard-subagent-model-label.py's executable bit.
validate.sh checks the executability of scripts named in hooks.json, and the
.py is invoked by the wrapper rather than by the harness, so nothing generic
sees it.

The second half runs `guard-subagent-model-label.py` for real, as a
subprocess, over a table of dispatch payloads, and asserts on its stdout --
this is the only way to catch the decision logic itself drifting from the
documented contract (denying a correctly labelled dispatch, allowing an
unlabelled one, cross-checking the label's version instead of just its
family, or losing the fail-open behaviour on malformed stdin).

These are *structural and behavioural* checks on purpose, not a pin on
exact prose: file contents are meant to be edited, wiring and decisions are
not.

Run directly, or via `scripts/validate.sh`, which discovers every
`plugins/<id>/tests/check-*.py`. Exits non-zero and lists every problem.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parent.parent
REPO = PLUGIN_ROOT.parent.parent
# Claude-only on purpose: the guard is a Claude Code PreToolUse hook on the
# Agent tool, so the skill explaining it is meaningless under Codex. Codex
# hardcodes its skill scan to <plugin>/skills, so staying out of that directory
# is the only mechanism that actually keeps it off the Codex load path.
CLAUDE_SKILLS_DIR = PLUGIN_ROOT / "skills-claude"
PORTABLE_SKILLS_DIR = PLUGIN_ROOT / "skills"
SKILL_DIR = CLAUDE_SKILLS_DIR / "subagent-model-labels"
CLAUDE_MANIFEST = PLUGIN_ROOT / ".claude-plugin" / "plugin.json"
CODEX_MANIFEST = PLUGIN_ROOT / ".codex-plugin" / "plugin.json"
SKILL = SKILL_DIR / "SKILL.md"
GUARD_SH = PLUGIN_ROOT / "hooks" / "guard-subagent-model-label.sh"
GUARD_PY = PLUGIN_ROOT / "hooks" / "guard-subagent-model-label.py"
HOOKS_JSON = PLUGIN_ROOT / "hooks" / "hooks.json"
DECIDER = GUARD_PY

errors: list[str] = []


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(REPO))
    except ValueError:
        return str(path)


def check(condition: bool, message: str) -> bool:
    if not condition:
        errors.append(message)
    return bool(condition)


def read(path: Path) -> str | None:
    if not check(path.is_file(), f"{rel(path)}: missing"):
        return None
    return path.read_text()


def read_json(path: Path) -> dict | None:
    text = read(path)
    if text is None:
        return None
    try:
        data = json.loads(text)
    except json.JSONDecodeError as e:
        errors.append(f"{rel(path)}: not valid JSON ({e})")
        return None
    if not isinstance(data, dict):
        errors.append(f"{rel(path)}: expected a JSON object at the top level")
        return None
    return data


# ---------------------------------------------------------------- hooks.json
hooks_text = read(HOOKS_JSON)
hooks_data: dict | None = None
if hooks_text is not None:
    try:
        hooks_data = json.loads(hooks_text)
    except json.JSONDecodeError as e:
        errors.append(f"{rel(HOOKS_JSON)}: invalid JSON ({e})")

if hooks_data is not None:
    hooks_obj = hooks_data.get("hooks", {}) if isinstance(hooks_data, dict) else {}

    # ---- PreToolUse: Agent matcher-group must exist and target the guard ----
    pretool = hooks_obj.get("PreToolUse", [])
    agent_groups = [
        g for g in pretool if isinstance(g, dict) and g.get("matcher") == "Agent"
    ]
    if check(
        bool(agent_groups),
        f"{rel(HOOKS_JSON)}: PreToolUse has no matcher-group with "
        '"matcher": "Agent" -- the label guard is not wired up',
    ):
        commands = [
            h.get("command", "")
            for g in agent_groups
            for h in g.get("hooks", [])
            if isinstance(h, dict)
        ]
        check(
            any(
                "guard-subagent-model-label.sh" in c and "${CLAUDE_PLUGIN_ROOT}" in c
                for c in commands
            ),
            f"{rel(HOOKS_JSON)}: the Agent matcher-group command must reference "
            "guard-subagent-model-label.sh via the ${CLAUDE_PLUGIN_ROOT} idiom",
        )

    # ---- SessionStart: must not have been displaced by the new guard ----
    sessionstart = hooks_obj.get("SessionStart", [])
    ss_commands = [
        h.get("command", "")
        for g in sessionstart
        if isinstance(g, dict)
        for h in g.get("hooks", [])
        if isinstance(h, dict)
    ]
    check(
        any("delegation-pointer.sh" in c for c in ss_commands),
        f"{rel(HOOKS_JSON)}: SessionStart must still point at "
        "delegation-pointer.sh -- adding the Agent guard must not displace it",
    )

# --------------------------------------------------- guard scripts present
for script in (GUARD_SH, GUARD_PY):
    if check(script.is_file(), f"{rel(script)}: missing"):
        check(
            os.access(script, os.X_OK),
            f"{rel(script)}: not executable (chmod +x) -- a non-executable "
            "hook command fails to launch",
        )

# ------------------------------------------------------------- host gating
# Codex scans <plugin>/skills wholesale and offers no per-skill exclusion, so
# the only structural gate is the skill's location. Claude Code's `skills`
# manifest field is additive to the default skills/ scan, so the Claude-only
# root has to be named there or the skill silently stops loading.
check(
    not (PORTABLE_SKILLS_DIR / "subagent-model-labels").exists(),
    f"{rel(PORTABLE_SKILLS_DIR)}/subagent-model-labels/ must not exist: Codex "
    "scans skills/ wholesale, so a Claude-only skill placed there loads under "
    "Codex, where the Agent tool, PreToolUse hooks and the label convention it "
    "documents do not exist",
)
check(
    SKILL.is_file(),
    f"{rel(SKILL)}: the Claude-only skill must live under "
    f"{rel(CLAUDE_SKILLS_DIR)}/, off the Codex skill-scan path",
)

claude_manifest = read_json(CLAUDE_MANIFEST)
if claude_manifest is not None:
    declared_roots = claude_manifest.get("skills")
    if isinstance(declared_roots, str):
        declared_roots = [declared_roots]
    roots = {str(r).strip("./") for r in declared_roots or []}
    check(
        CLAUDE_SKILLS_DIR.name in roots,
        f"{rel(CLAUDE_MANIFEST)}: the `skills` list must name "
        f"{CLAUDE_SKILLS_DIR.name!r}, otherwise Claude Code never scans it and "
        "the skill stops loading for the one host it is written for",
    )
    check(
        PORTABLE_SKILLS_DIR.name in roots,
        f"{rel(CLAUDE_MANIFEST)}: the `skills` list must still name "
        f"{PORTABLE_SKILLS_DIR.name!r}. Redundant in the common case -- the "
        "default scan of skills/ was measured to happen even when the list "
        "omits it -- but the docs carve out a marketplace entry resolving to "
        "the marketplace root, where the list replaces the default instead of "
        "adding to it. Naming both roots is correct under either behaviour, "
        "and the cost of being wrong is the portable skill silently vanishing",
    )

codex_manifest = read_json(CODEX_MANIFEST)
if codex_manifest is not None:
    # Exactly the portable root, not merely "not the Claude-only one". Codex's
    # `skills` takes a single string and supplements its hardcoded skills/ scan,
    # so anything broader -- "./", a parent, a second root -- can reach a
    # host-scoped tree while a not-equal-to-skills-claude check still passes.
    codex_skills = str(codex_manifest.get("skills") or "").strip("./")
    check(
        codex_skills == PORTABLE_SKILLS_DIR.name,
        f"{rel(CODEX_MANIFEST)}: `skills` must be exactly "
        f"'./{PORTABLE_SKILLS_DIR.name}/', got {codex_manifest.get('skills')!r}. "
        "Any broader path can expose a host-scoped root such as "
        f"{CLAUDE_SKILLS_DIR.name}/ to Codex",
    )

skill_body = read(SKILL) or ""
check(
    "Codex" in skill_body,
    f"{rel(SKILL)}: must state its host scope in the body -- the directory "
    "gate is structural, but a reader who opens the file on another host needs "
    "to be told in band that it does not apply there",
)

# --------------------------------------------------- wrapper fail-open shape
guard_sh_text = read(GUARD_SH)
if guard_sh_text is not None:
    check(
        "CODE_GENERAL_LABEL_GUARD" in guard_sh_text,
        f"{rel(GUARD_SH)}: must still check CODE_GENERAL_LABEL_GUARD -- "
        "removing it deletes the escape hatch for sessions that predate "
        "the convention",
    )
    skill_text = read(SKILL) or ""
    check(
        "CODE_GENERAL_LABEL_GUARD" in skill_text,
        f"{rel(SKILL)}: must still document the CODE_GENERAL_LABEL_GUARD "
        "escape hatch by name -- renaming it in one file and not the other "
        "leaves the documented way to disable the guard silently inert",
    )
    check(
        "command -v python3" in guard_sh_text,
        f"{rel(GUARD_SH)}: must still guard on `command -v python3` -- "
        "removing it means a machine without python3 gets every dispatch "
        "blocked instead of waved through",
    )

# ------------------------------------------------------------ behavioural
def run_decider(stdin_text: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(DECIDER)],
        input=stdin_text,
        capture_output=True,
        text=True,
    )


def payload(description: object, model: object = None, **extra: object) -> str:
    """Build a PreToolUse payload. `description`/`model` are deliberately typed
    `object`: the wrongly-typed-field cases below depend on being able to send a
    non-string through, which is exactly the shape that once disabled the guard.
    """
    tool_input: dict[str, object] = {"description": description}
    if model is not None:
        tool_input["model"] = model
    tool_input.update(extra)
    return json.dumps({"tool_input": tool_input})


# (label, stdin sent to the decider, expect a deny decision)
CASES: list[tuple[str, str, bool]] = [
    (
        "versioned Sonnet label, no model",
        payload("[Sonnet 5] Map handlers"),
        False,
    ),
    (
        "versioned Haiku label, no model",
        payload("[Haiku 4.5] Sweep files"),
        False,
    ),
    (
        "bare family label (no version), no model",
        payload("[Sonnet] Do a thing"),
        False,
    ),
    (
        "no label at all",
        payload("Map handlers"),
        True,
    ),
    (
        "unknown family",
        payload("[Gandalf 5] Do a thing"),
        True,
    ),
    (
        "label contradicts explicit model",
        payload("[Haiku 4.5] Deep audit", "opus"),
        True,
    ),
    (
        "label agrees with explicit model",
        payload("[Opus 5] Deep audit", "opus"),
        False,
    ),
    (
        "lowercase family is case-insensitive",
        payload("[opus 5] lowercase family"),
        False,
    ),
    (
        "quote and bracket inside description don't break JSON parsing",
        payload('[Sonnet 5] Handle the "foo[bar]" case'),
        False,
    ),
    (
        "a fork ignores `model`, so a lead-tier label must not be contradicted",
        payload("[Opus 5] Fork the context", "sonnet", subagent_type="fork"),
        False,
    ),
    (
        "non-string model must not smuggle an unlabelled dispatch through",
        payload("Map handlers", 5),
        True,
    ),
    (
        "non-string description is no label, not a free pass",
        payload(5, "opus"),
        True,
    ),
    (
        "tool_input of the wrong type is still judged, not waved through",
        json.dumps({"tool_input": None}),
        True,
    ),
    (
        "malformed stdin fails open",
        "not json {{{",
        False,
    ),
]

if GUARD_PY.is_file() and os.access(GUARD_PY, os.X_OK):
    for case_name, stdin_text, expect_deny in CASES:
        result = run_decider(stdin_text)
        stdout = result.stdout
        if expect_deny:
            try:
                data = json.loads(stdout)
            except json.JSONDecodeError:
                errors.append(
                    f"decider case {case_name!r}: expected a deny decision, "
                    f"stdout was not JSON: {stdout!r}"
                )
                continue
            decision = (
                data.get("hookSpecificOutput", {}).get("permissionDecision")
                if isinstance(data, dict)
                else None
            )
            check(
                decision == "deny",
                f"decider case {case_name!r}: expected permissionDecision="
                f"'deny', got {decision!r} (stdout: {stdout!r})",
            )
        else:
            check(
                stdout.strip() == "",
                f"decider case {case_name!r}: expected allow (empty stdout), "
                f"got: {stdout!r}",
            )
else:
    errors.append(
        f"{rel(GUARD_PY)}: missing or not executable, skipped behavioural "
        "decider cases"
    )

# ------------------------------------------------------------------ report
name = Path(__file__).name
if errors:
    print(f"FAIL  {name}: {len(errors)} problem(s):\n", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    print("", file=sys.stderr)
    sys.exit(1)

print(f"OK    {name}: subagent model label contract intact")
