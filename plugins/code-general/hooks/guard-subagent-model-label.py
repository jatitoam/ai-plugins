#!/usr/bin/env python3
"""Decide whether an Agent dispatch carries a usable model label.

Invoked by guard-subagent-model-label.sh with the PreToolUse tool call on
stdin. Emits a deny decision on stdout, or nothing at all to let the call
through. Never raises: a malformed payload fails open, because a guard that
crashes on an unexpected shape would block every dispatch.

Two checks, in order:

  1. `description` opens with a bracketed model family, optionally versioned.
     Deliberately a shape check rather than an allowlist of exact model names,
     which would start denying correct labels the day a new model ships.
  2. If `model` is set explicitly, the label's family agrees with it. This is
     the case a presence check misses -- a label that is present but lying.
     Family only: the host resolves an alias like `opus` to whichever version
     is current, so pinning the version here would deny correct labels.
     Skipped for `subagent_type: "fork"`, where the host ignores `model`
     outright and the fork runs as the lead -- cross-checking there would deny
     a correct label for naming the tier the agent will actually run as.

Only the read-and-parse of stdin fails open. A payload that parses but carries
an unexpected field *type* is still judged: a non-string `description` is no
label, and a non-string `model` is simply no override. Folding those into the
fail-open path would let any caller disable the guard by passing `model` as a
number.
"""

from __future__ import annotations

import json
import re
import sys

# Aliases the Agent tool accepts, mapped to the family a label must name.
FAMILIES = {
    "opus": "Opus",
    "sonnet": "Sonnet",
    "haiku": "Haiku",
    "fable": "Fable",
}

# Built from FAMILIES rather than spelled out again: two hand-maintained lists
# of the same families drift, and the way they drift is silent -- a family the
# regex accepts but FAMILIES does not simply stops being cross-checked.
LABEL = re.compile(
    r"^\[\s*(?P<family>" + "|".join(map(re.escape, FAMILIES)) + r")"
    r"(?P<version>\s+\d+(?:\.\d+)*)?\s*\]\s+\S",
    re.IGNORECASE,
)

GUIDANCE = (
    "Pick the tier per code-general:delegation-ladder -- Opus for deep "
    "investigation and adversarial review, Sonnet for contained implementation "
    "and codebase mapping, Haiku for mechanical bulk and simple verification. "
    "Label the tier the agent will actually run as: when you set `model`, the "
    "label must match it; when you omit it, the agent inherits the lead's model."
)


def deny(reason: str) -> None:
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        },
        sys.stdout,
    )
    sys.exit(0)


def text(value: object) -> str:
    """Normalise a payload field to a string. A non-string is not a value."""
    return value.strip() if isinstance(value, str) else ""


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return  # Fail open only on stdin we could not read or parse.

    tool_input = payload.get("tool_input") if isinstance(payload, dict) else None
    if not isinstance(tool_input, dict):
        tool_input = {}

    description = text(tool_input.get("description"))
    model = text(tool_input.get("model")).lower()
    subagent_type = text(tool_input.get("subagent_type")).lower()

    match = LABEL.match(description)
    if not match:
        deny(
            "BLOCKED: a subagent description must open with its model tier in "
            "square brackets, then the task.\n\n"
            "  [Sonnet 5] Map webhook handlers\n\n"
            "Accepted families: Opus, Sonnet, Haiku, Fable -- with or without a "
            "version, so [Sonnet 5], [Haiku 4.5] and [Sonnet] all pass.\n\n"
            f"Got: {description or '<empty>'}\n\n"
            f"Re-issue this Agent call with the label prefixed. {GUIDANCE}"
        )

    # A fork always runs as the lead; the host ignores `model` for it.
    if model and subagent_type != "fork":
        want = FAMILIES.get(model)
        if want and match.group("family").lower() != want.lower():
            deny(
                "BLOCKED: the model label contradicts the `model` parameter, so "
                "the description names a tier this agent will not run as.\n\n"
                f"  description: {description}\n"
                f"  model:       {model}  (label should name {want})\n\n"
                "Fix whichever one is wrong -- change the label to match the "
                "model, or change the model to match the intended tier. "
                f"{GUIDANCE}"
            )


if __name__ == "__main__":
    main()
