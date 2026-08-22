#!/usr/bin/env python3
"""Contract test for the code-general delegation-ladder skill.

Guards the properties that a past refactor silently broke: the skill's trigger
description was narrowed, the Claude adapter became reachable only on the
dispatch path, and the SessionStart hook started contradicting the optional
system-prompt canon.

These are *structural* checks on purpose. They assert that a required idea is
present and that required ordering holds — not that a particular sentence is
spelled a particular way. Prose in these files is meant to be edited; a copy
edit must not fail the build, while deleting a load-bearing instruction must.

Run directly, or via `scripts/validate.sh`, which discovers every
`plugins/<id>/tests/check-*.py`. Exits non-zero and lists every problem.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parent.parent
REPO = PLUGIN_ROOT.parent.parent
SKILL = PLUGIN_ROOT / "skills" / "delegation-ladder" / "SKILL.md"
ADAPTER = PLUGIN_ROOT / "skills" / "delegation-ladder" / "references" / "claude-code.md"
POINTER = PLUGIN_ROOT / "hooks" / "delegation-pointer.sh"

# Description vocabulary. The skill's description is its only trigger surface in
# Claude Code, so it must stay deliberately over-inclusive. We require the core
# inclusion clause plus broad coverage of each vocabulary group, rather than
# every individual word, so the wording stays editable.
TASK_WORDS = (
    "implementing a feature", "fixing a bug", "refactoring", "debugging",
    "investigating", "reviewing code", "exploring", "mapping a codebase",
    "researching", "writing docs", "plans", "tickets", "migrating data",
    "independent parts",
)
TASK_WORDS_MIN = 10
DELEGATION_WORDS = (
    "delegate", "subagents", "spawn agents", "parallelize", "fan out",
    "choose a model", "who should do the work",
)
DELEGATION_WORDS_MIN = 5

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


def flat(text: str) -> str:
    """Lowercase with runs of whitespace collapsed, so line wrapping is free."""
    return " ".join(text.lower().split())


def frontmatter_description(text: str) -> str:
    m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not m:
        return ""
    block = m.group(1)
    d = re.search(r"^description:\s*(>[-+]?\s*\n((?:[ \t]+.*\n?)+)|(.+))$", block, re.M)
    if not d:
        return ""
    return flat(d.group(2) or d.group(3) or "")


def covered(text: str, words: tuple[str, ...]) -> list[str]:
    return [w for w in words if w in text]


# ---------------------------------------------------------------- SKILL.md
skill = read(SKILL)
if skill is not None:
    flat_skill = flat(skill)
    description = frontmatter_description(skill)

    if check(bool(description), f"{rel(SKILL)}: frontmatter has no readable description"):
        # The clause that keeps the gate over-inclusive rather than reserved for
        # "multiple substantial independent workstreams".
        check(
            "more than one step" in description,
            f"{rel(SKILL)}: description must trigger on work of 'more than one step' — "
            "narrowing this silently stops the skill from firing on ordinary "
            "multi-step tasks",
        )
        hits = covered(description, TASK_WORDS)
        check(
            len(hits) >= TASK_WORDS_MIN,
            f"{rel(SKILL)}: description names only {len(hits)} of "
            f"{len(TASK_WORDS)} task types (need >= {TASK_WORDS_MIN}); missing: "
            f"{', '.join(w for w in TASK_WORDS if w not in hits)}",
        )
        hits = covered(description, DELEGATION_WORDS)
        check(
            len(hits) >= DELEGATION_WORDS_MIN,
            f"{rel(SKILL)}: description names only {len(hits)} of "
            f"{len(DELEGATION_WORDS)} explicit delegation requests (need >= "
            f"{DELEGATION_WORDS_MIN}); missing: "
            f"{', '.join(w for w in DELEGATION_WORDS if w not in hits)}",
        )

    # The adapter must be loaded before the gate runs, not merely before
    # dispatch: a gate that concludes "inline" must still have read it.
    adapter_h = re.search(r"^##\s+.*\badapter\b.*$", skill, re.M | re.I)
    gate_h = re.search(r"^##\s+.*\bgate\b.*$", skill, re.M | re.I)
    if check(
        adapter_h is not None and gate_h is not None,
        f"{rel(SKILL)}: needs a host-adapter section and a gate section",
    ):
        check(
            adapter_h.start() < gate_h.start(),
            f"{rel(SKILL)}: the host-adapter section must come before the gate "
            "section, so the adapter is read even when the gate decides to work inline",
        )
        check(
            "references/claude-code.md" in skill[: gate_h.start()],
            f"{rel(SKILL)}: the Claude adapter link must appear before the gate section",
        )

    check(
        flat_skill.count("inline") >= 2,
        f"{rel(SKILL)}: working inline must be described as a legitimate gate "
        "outcome, not just an omission",
    )

# -------------------------------------------------------- claude-code.md
adapter = read(ADAPTER)
if adapter is not None:
    flat_adapter = flat(adapter)

    # Tier routing table: one row per tier, whatever the work column says.
    for tier in ("opus", "sonnet", "haiku"):
        check(
            re.search(rf"^\|.*\|\s*{tier}\s*\|", flat_adapter.replace(" | ", " | "), re.M)
            is not None
            or re.search(rf"\|[^|\n]*\|\s*{tier}\s*\|", adapter, re.I) is not None,
            f"{rel(ADAPTER)}: tier table has no row routing work to {tier}",
        )

    # Guidance for each lead model, so no lead is left without a ladder.
    for lead in ("fable", "opus", "sonnet"):
        check(
            re.search(rf"\b{lead}\b[^.]{{0,40}}\b(leads|is the lead|lead)\b", flat_adapter)
            is not None,
            f"{rel(ADAPTER)}: no ladder guidance for the case where {lead} leads",
        )

    check(
        "fleetview" in flat_adapter and re.search(r"\[[A-Z][\w .-]*\]", adapter) is not None,
        f"{rel(ADAPTER)}: must keep the FleetView convention of prefixing an agent "
        "description with the model name in brackets, with an example",
    )
    check(
        re.search(r"\b(eight|8)\b[^.]{0,30}\bagents\b", flat_adapter) is not None,
        f"{rel(ADAPTER)}: must keep the ask-first ceiling of about eight parallel agents",
    )
    check(
        "outside the current repository" in flat_adapter,
        f"{rel(ADAPTER)}: must keep the ask-first rule for writing outside the repository",
    )
    check(
        "delegation-canon.md" in flat_adapter,
        f"{rel(ADAPTER)}: must link the optional canon at delegation-canon.md",
    )
    check(
        "canon" in flat_adapter
        and re.search(r"\bstanding\b[^.]{0,60}\bauthoriz", flat_adapter) is not None,
        f"{rel(ADAPTER)}: must state that the installed canon is the user's standing "
        "authorization",
    )

# --------------------------------------------------- delegation-pointer.sh
pointer = read(POINTER)
if pointer is not None:
    flat_pointer = flat(pointer)

    check(
        re.search(r"install-canon\.sh\"?\s+--sync", pointer) is not None,
        f"{rel(POINTER)}: must keep syncing the stable canon copy (--sync), or plugin "
        "updates stop propagating to the system-prompt layer",
    )
    check(
        "code-general:delegation-ladder" in flat_pointer,
        f"{rel(POINTER)}: must name the skill to invoke",
    )
    check(
        "canon" in flat_pointer
        and re.search(r"\bstanding\b[^.]{0,80}\bauthoriz", flat_pointer) is not None,
        f"{rel(POINTER)}: must point at the canon as the source of standing "
        "authorization when it is installed",
    )
    # Heuristic backstop, not a proof: the hook is injected into the same context
    # as the canon, so a blanket denial there reads as a direct contradiction of
    # the user's own system prompt. Broad enough to catch the phrasings we have
    # actually seen; a novel wording would still slip through.
    contradiction = re.search(
        r"(grants? no permission|no permission to (use|dispatch|spawn)"
        r"|does not grant (you )?permission|neither grants?)",
        flat_pointer,
    )
    if contradiction is not None:
        errors.append(
            f"{rel(POINTER)}: hook text contradicts the optional standing canon "
            f"({contradiction.group(0)!r}) — it is injected alongside the canon, so a "
            "blanket denial here conflicts with the user's own system prompt"
        )

# ------------------------------------------------------------------ report
name = Path(__file__).name
if errors:
    print(f"FAIL  {name}: {len(errors)} problem(s):\n", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    print("", file=sys.stderr)
    sys.exit(1)

print(f"OK    {name}: delegation contract intact")
