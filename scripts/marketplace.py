#!/usr/bin/env python3
"""Marketplace maintenance tooling for the ai-plugins repo.

Subcommands:
    validate                          check the whole repo for consistency
    bump <plugin-id> <level>          bump a plugin's version in all five places
    new-plugin <id> <name> <desc>     scaffold and register a new plugin

Standard library only. The YAML files in this repo are written by these scripts
and use a deliberately small YAML subset (mappings, sequences of scalars,
sequences of mappings, folded `>` scalars, and empty `[]`), so a tiny parser is
enough and no third-party dependency is needed.
"""

from __future__ import annotations

import json
import re
import sys
import textwrap
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
INDEX = REPO / "index.yaml"
MARKETPLACE = REPO / ".claude-plugin" / "marketplace.json"
README = REPO / "README.md"
PLUGINS_DIR = REPO / "plugins"

SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
PLUGIN_ID_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")


class Fail(Exception):
    """A user-facing error that should abort with a clear message."""


# --------------------------------------------------------------------------
# Minimal YAML subset: parser
# --------------------------------------------------------------------------


def _indent_of(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def _scalar(raw: str):
    raw = raw.strip()
    if raw in ("[]", "{}"):
        return [] if raw == "[]" else {}
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'":
        return raw[1:-1]
    return raw


def _parse_block(lines: list[str], i: int, indent: int):
    """Parse a block at `indent`. Returns (value, next_index)."""
    # Skip blanks and comments.
    while i < len(lines) and (not lines[i].strip() or lines[i].lstrip().startswith("#")):
        i += 1
    if i >= len(lines) or _indent_of(lines[i]) < indent:
        return None, i

    if lines[i].lstrip().startswith("- "):
        return _parse_seq(lines, i, indent)
    return _parse_map(lines, i, indent)


def _parse_seq(lines: list[str], i: int, indent: int):
    items = []
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        if _indent_of(line) != indent or not line.lstrip().startswith("- "):
            break
        body = line.lstrip()[2:]
        if ":" in body and not body.strip().startswith("#"):
            # Sequence of mappings: re-materialize the first key at the
            # mapping's own indent so _parse_map sees a uniform block.
            item_indent = indent + 2
            synthetic = [" " * item_indent + body] + lines[i + 1 :]
            value, consumed = _parse_map(synthetic, 0, item_indent)
            items.append(value)
            i = i + consumed  # `consumed` counts the synthetic first line too
        else:
            items.append(_scalar(body))
            i += 1
    return items, i


def _parse_map(lines: list[str], i: int, indent: int):
    result: dict = {}
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        cur = _indent_of(line)
        if cur < indent:
            break
        if cur > indent:
            raise Fail(f"unexpected indentation at line {i + 1}: {line!r}")
        if line.lstrip().startswith("- "):
            break
        if ":" not in line:
            raise Fail(f"expected 'key: value' at line {i + 1}: {line!r}")
        key, _, rest = line.strip().partition(":")
        key = key.strip()
        rest = rest.strip()
        if rest in (">", "|", ">-", "|-"):
            text, i = _parse_folded(lines, i + 1, indent, fold=rest[0] == ">")
            result[key] = text
        elif rest == "":
            value, i = _parse_block(lines, i + 1, indent + 2)
            result[key] = {} if value is None else value
        else:
            result[key] = _scalar(rest)
            i += 1
    return result, i


def _parse_folded(lines: list[str], i: int, indent: int, fold: bool):
    chunks: list[str] = []
    while i < len(lines):
        line = lines[i]
        if line.strip() and _indent_of(line) <= indent:
            break
        chunks.append(line.strip())
        i += 1
    while chunks and not chunks[-1]:
        chunks.pop()
    if fold:
        return " ".join(c for c in chunks if c), i
    return "\n".join(chunks), i


def parse_yaml(path: Path):
    lines = path.read_text().splitlines()
    value, _ = _parse_block(lines, 0, 0)
    return {} if value is None else value


# --------------------------------------------------------------------------
# Minimal YAML subset: renderers
# --------------------------------------------------------------------------


def _folded(text: str, indent: int) -> str:
    pad = " " * indent
    body = textwrap.fill(" ".join(text.split()), width=76 - indent)
    return "\n".join(pad + line for line in body.splitlines())


def render_index(data: dict) -> str:
    plugins = data.get("plugins") or []
    if not plugins:
        return "plugins: []\n"
    out = ["plugins:"]
    for p in plugins:
        out.append(f"  - id: {p['id']}")
        out.append(f"    path: {p['path']}")
        out.append(f"    display_name: {p['display_name']}")
        out.append("    description: >")
        out.append(_folded(p["description"], 6))
        out.append(f"    version: {p['version']}")
        skills = p.get("skills") or []
        if skills:
            out.append("    skills:")
            out.extend(f"      - {s}" for s in skills)
        else:
            out.append("    skills: []")
    return "\n".join(out) + "\n"


def render_plugin_yaml(data: dict) -> str:
    out = [
        f"name: {data['name']}",
        f"display_name: {data['display_name']}",
        "description: >",
        _folded(data["description"], 2),
        f"version: {data['version']}",
    ]
    skills = data.get("skills") or []
    if skills:
        out.append("skills:")
        for s in skills:
            out.append(f"  - id: {s['id']}")
            out.append(f"    path: {s['path']}")
    else:
        out.append("skills: []")
    out.append("commands: []" if not data.get("commands") else "commands:")
    for c in data.get("commands") or []:
        out.append(f"  - {c}")
    out.append("mcp_servers: []" if not data.get("mcp_servers") else "mcp_servers:")
    for m in data.get("mcp_servers") or []:
        out.append(f"  - {m}")
    return "\n".join(out) + "\n"


# --------------------------------------------------------------------------
# JSON helpers
# --------------------------------------------------------------------------


def read_json(path: Path) -> dict:
    return json.loads(path.read_text())


def write_json(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


# --------------------------------------------------------------------------
# Semver
# --------------------------------------------------------------------------


def parse_semver(value: str, where: str) -> tuple[int, int, int]:
    m = SEMVER_RE.match(str(value).strip())
    if not m:
        raise Fail(f"{where}: {value!r} is not a MAJOR.MINOR.PATCH version")
    return int(m[1]), int(m[2]), int(m[3])


def bump_semver(value: str, level: str, where: str) -> str:
    major, minor, patch = parse_semver(value, where)
    if level == "major":
        return f"{major + 1}.0.0"
    if level == "minor":
        return f"{major}.{minor + 1}.0"
    if level == "patch":
        return f"{major}.{minor}.{patch + 1}"
    raise Fail(f"unknown bump level {level!r}; use major, minor, or patch")


# --------------------------------------------------------------------------
# Frontmatter
# --------------------------------------------------------------------------


def read_frontmatter(path: Path) -> dict:
    lines = path.read_text().splitlines()
    if not lines or lines[0].strip() != "---":
        raise Fail(f"{rel(path)}: missing YAML frontmatter (file must start with ---)")
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    except StopIteration:
        raise Fail(f"{rel(path)}: frontmatter is never closed with ---")
    block = lines[1:end]
    value, _ = _parse_block(block, 0, 0)
    return value or {}


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(REPO))
    except ValueError:
        return str(path)


# --------------------------------------------------------------------------
# Repo model
# --------------------------------------------------------------------------


def plugin_dirs() -> list[str]:
    if not PLUGINS_DIR.is_dir():
        return []
    return sorted(
        p.name
        for p in PLUGINS_DIR.iterdir()
        if p.is_dir() and not p.name.startswith(".")
    )


def version_sites(plugin_id: str) -> list[tuple[str, str | None]]:
    """The four plugin-scoped version fields, as (label, value) pairs."""
    sites: list[tuple[str, str | None]] = []

    pj = PLUGINS_DIR / plugin_id / ".claude-plugin" / "plugin.json"
    sites.append((rel(pj), read_json(pj).get("version") if pj.is_file() else None))

    py = PLUGINS_DIR / plugin_id / "plugin.yaml"
    sites.append((rel(py), parse_yaml(py).get("version") if py.is_file() else None))

    entry = next(
        (p for p in read_json(MARKETPLACE).get("plugins", []) if p.get("name") == plugin_id),
        None,
    )
    sites.append((f"{rel(MARKETPLACE)} (entry)", entry.get("version") if entry else None))

    idx = next(
        (p for p in (parse_yaml(INDEX).get("plugins") or []) if p.get("id") == plugin_id),
        None,
    )
    sites.append((rel(INDEX), idx.get("version") if idx else None))

    return sites


# --------------------------------------------------------------------------
# validate
# --------------------------------------------------------------------------


def cmd_validate(_argv: list[str]) -> int:
    errors: list[str] = []

    def check(condition: bool, message: str) -> bool:
        if not condition:
            errors.append(message)
        return condition

    market = read_json(MARKETPLACE)
    index = parse_yaml(INDEX)

    try:
        parse_semver(market.get("version", ""), f"{rel(MARKETPLACE)} top-level version")
    except Fail as e:
        errors.append(str(e))

    on_disk = set(plugin_dirs())
    in_index = {p.get("id") for p in (index.get("plugins") or [])}
    in_market = {p.get("name") for p in market.get("plugins", [])}

    for missing in sorted(on_disk - in_index):
        errors.append(f"plugins/{missing}/ exists but is not registered in {rel(INDEX)}")
    for missing in sorted(on_disk - in_market):
        errors.append(f"plugins/{missing}/ exists but is not registered in {rel(MARKETPLACE)}")
    for ghost in sorted(in_index - on_disk):
        errors.append(f"{rel(INDEX)} lists '{ghost}' but plugins/{ghost}/ does not exist")
    for ghost in sorted(in_market - on_disk):
        errors.append(f"{rel(MARKETPLACE)} lists '{ghost}' but plugins/{ghost}/ does not exist")

    readme = README.read_text() if README.is_file() else ""
    skill_count = 0

    for pid in sorted(on_disk):
        root = PLUGINS_DIR / pid
        pj_path = root / ".claude-plugin" / "plugin.json"
        py_path = root / "plugin.yaml"

        if not check(pj_path.is_file(), f"{pid}: missing {rel(pj_path)}"):
            continue
        if not check(py_path.is_file(), f"{pid}: missing {rel(py_path)}"):
            continue

        pj = read_json(pj_path)
        py = parse_yaml(py_path)

        check(pj.get("name") == pid, f"{rel(pj_path)}: name is {pj.get('name')!r}, expected {pid!r}")
        check(bool(pj.get("description")), f"{rel(pj_path)}: description is empty")
        check(py.get("name") == pid, f"{rel(py_path)}: name is {py.get('name')!r}, expected {pid!r}")
        check(bool(py.get("display_name")), f"{rel(py_path)}: display_name is empty")

        entry = next((p for p in market.get("plugins", []) if p.get("name") == pid), None)
        if entry is not None:
            expected_source = f"./plugins/{pid}"
            check(
                entry.get("source") == expected_source,
                f"{rel(MARKETPLACE)} entry '{pid}': source is {entry.get('source')!r}, "
                f"expected {expected_source!r}",
            )

        idx_entry = next(
            (p for p in (index.get("plugins") or []) if p.get("id") == pid), None
        )
        if idx_entry is not None:
            check(
                idx_entry.get("path") == f"plugins/{pid}",
                f"{rel(INDEX)} entry '{pid}': path is {idx_entry.get('path')!r}, "
                f"expected 'plugins/{pid}'",
            )

        # The five-file version invariant.
        sites = version_sites(pid)
        values = {v for _, v in sites if v is not None}
        if len(values) > 1:
            detail = "; ".join(f"{label}={value}" for label, value in sites)
            errors.append(f"{pid}: version fields disagree -> {detail}")
        for label, value in sites:
            if value is None:
                errors.append(f"{pid}: no version found in {label}")
            else:
                try:
                    parse_semver(value, f"{pid} version in {label}")
                except Fail as e:
                    errors.append(str(e))

        # Skills.
        declared = py.get("skills") or []
        for skill in declared:
            if not isinstance(skill, dict) or "id" not in skill or "path" not in skill:
                errors.append(f"{rel(py_path)}: each skill needs an 'id' and a 'path'")
                continue
            sid = skill["id"]
            sdir = root / skill["path"]
            smd = sdir / "SKILL.md"
            if not check(smd.is_file(), f"{pid}: skill '{sid}' has no {rel(smd)}"):
                continue
            skill_count += 1
            check(
                sdir.name == sid,
                f"{pid}: skill '{sid}' lives in directory {sdir.name!r}; they must match",
            )
            try:
                fm = read_frontmatter(smd)
            except Fail as e:
                errors.append(str(e))
                continue
            check(bool(fm.get("name")), f"{rel(smd)}: frontmatter has no 'name'")
            check(bool(fm.get("description")), f"{rel(smd)}: frontmatter has no 'description'")
            if fm.get("name"):
                check(
                    fm["name"] == sid,
                    f"{rel(smd)}: frontmatter name is {fm['name']!r}, expected {sid!r}",
                )

        # Skills on disk that were never declared.
        skills_dir = root / "skills"
        if skills_dir.is_dir():
            declared_ids = {s["id"] for s in declared if isinstance(s, dict) and "id" in s}
            for found in sorted(d.name for d in skills_dir.iterdir() if d.is_dir()):
                check(
                    found in declared_ids,
                    f"{pid}: skills/{found}/ exists but is not listed in {rel(py_path)}",
                )

        # index.yaml skill list must mirror plugin.yaml.
        if idx_entry is not None:
            idx_skills = set(idx_entry.get("skills") or [])
            yaml_skills = {s["id"] for s in declared if isinstance(s, dict) and "id" in s}
            if idx_skills != yaml_skills:
                errors.append(
                    f"{pid}: skills in {rel(INDEX)} ({sorted(idx_skills)}) do not match "
                    f"{rel(py_path)} ({sorted(yaml_skills)})"
                )

        check(
            f"[{pid}]" in readme or f"| {pid} " in readme,
            f"{pid}: no row for this plugin in README.md — add one to the Plugins table",
        )

    if errors:
        print(f"FAIL  {len(errors)} problem(s):\n", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        print("", file=sys.stderr)
        return 1

    print(f"OK  {len(on_disk)} plugin(s), {skill_count} skill(s), versions in sync")
    return 0


# --------------------------------------------------------------------------
# bump
# --------------------------------------------------------------------------


def cmd_bump(argv: list[str]) -> int:
    if len(argv) != 2:
        raise Fail("usage: bump.sh <plugin-id> <major|minor|patch>")
    plugin_id, level = argv
    if level not in ("major", "minor", "patch"):
        raise Fail(f"unknown bump level {level!r}; use major, minor, or patch")
    if not (PLUGINS_DIR / plugin_id).is_dir():
        raise Fail(f"no such plugin: plugins/{plugin_id}/")

    sites = version_sites(plugin_id)
    for label, value in sites:
        if value is None:
            raise Fail(f"{plugin_id}: no version found in {label} — run validate.sh first")
    values = {v for _, v in sites}
    if len(values) > 1:
        detail = "\n".join(f"    {label} = {value}" for label, value in sites)
        raise Fail(
            f"{plugin_id}: version fields are already out of sync, refusing to bump:\n"
            f"{detail}\n  Reconcile them by hand, then run validate.sh."
        )

    old = sites[0][1]
    new = bump_semver(old, level, f"{plugin_id} version")

    market = read_json(MARKETPLACE)
    old_top = market.get("version", "0.0.0")
    new_top = bump_semver(old_top, "patch", f"{rel(MARKETPLACE)} top-level version")

    # 1. plugins/<id>/.claude-plugin/plugin.json
    pj_path = PLUGINS_DIR / plugin_id / ".claude-plugin" / "plugin.json"
    pj = read_json(pj_path)
    pj["version"] = new
    write_json(pj_path, pj)

    # 2. plugins/<id>/plugin.yaml
    py_path = PLUGINS_DIR / plugin_id / "plugin.yaml"
    py = parse_yaml(py_path)
    py["version"] = new
    py_path.write_text(render_plugin_yaml(py))

    # 3 + 4. marketplace.json: the plugin entry and the top-level version
    for entry in market.get("plugins", []):
        if entry.get("name") == plugin_id:
            entry["version"] = new
    market["version"] = new_top
    write_json(MARKETPLACE, market)

    # 5. index.yaml
    index = parse_yaml(INDEX)
    for entry in index.get("plugins") or []:
        if entry.get("id") == plugin_id:
            entry["version"] = new
    INDEX.write_text(render_index(index))

    print(f"{plugin_id}: {old} -> {new} ({level})\n")
    width = max(len(label) for label, _ in sites) + 2
    for label, _ in sites:
        print(f"  {label.ljust(width)} {old} -> {new}")
    print(f"  {f'{rel(MARKETPLACE)} (top-level)'.ljust(width)} {old_top} -> {new_top}")
    print("\nNext: run ./scripts/validate.sh, then commit.")
    return 0


# --------------------------------------------------------------------------
# new-plugin
# --------------------------------------------------------------------------


def cmd_new_plugin(argv: list[str]) -> int:
    if len(argv) not in (3, 4):
        raise Fail(
            'usage: new-plugin.sh <plugin-id> "<display name>" "<description>" [category]'
        )
    plugin_id, display_name, description = argv[:3]
    category = argv[3] if len(argv) == 4 else "general"
    if not PLUGIN_ID_RE.match(plugin_id):
        raise Fail(f"invalid plugin id {plugin_id!r}: use lowercase-kebab-case")
    root = PLUGINS_DIR / plugin_id
    if root.exists():
        raise Fail(f"plugins/{plugin_id}/ already exists")

    market = read_json(MARKETPLACE)
    if any(p.get("name") == plugin_id for p in market.get("plugins", [])):
        raise Fail(f"{rel(MARKETPLACE)} already has an entry named {plugin_id!r}")
    index = parse_yaml(INDEX)
    plugins = index.get("plugins") or []
    if any(p.get("id") == plugin_id for p in plugins):
        raise Fail(f"{rel(INDEX)} already has an entry with id {plugin_id!r}")

    version = "0.1.0"

    (root / ".claude-plugin").mkdir(parents=True)
    (root / "skills").mkdir()
    (root / "skills" / ".gitkeep").write_text("")

    write_json(
        root / ".claude-plugin" / "plugin.json",
        {"name": plugin_id, "description": description, "version": version},
    )
    (root / "plugin.yaml").write_text(
        render_plugin_yaml(
            {
                "name": plugin_id,
                "display_name": display_name,
                "description": description,
                "version": version,
                "skills": [],
                "commands": [],
                "mcp_servers": [],
            }
        )
    )

    market.setdefault("plugins", []).append(
        {
            "name": plugin_id,
            "source": f"./plugins/{plugin_id}",
            "description": description,
            "version": version,
            "category": category,
        }
    )
    market["version"] = bump_semver(
        market.get("version", "0.0.0"), "patch", f"{rel(MARKETPLACE)} top-level version"
    )
    write_json(MARKETPLACE, market)

    plugins.append(
        {
            "id": plugin_id,
            "path": f"plugins/{plugin_id}",
            "display_name": display_name,
            "description": description,
            "version": version,
            "skills": [],
        }
    )
    index["plugins"] = plugins
    INDEX.write_text(render_index(index))

    print(f"Created plugins/{plugin_id}/ at version {version}\n")
    print(f"  plugins/{plugin_id}/.claude-plugin/plugin.json")
    print(f"  plugins/{plugin_id}/plugin.yaml")
    print(f"  plugins/{plugin_id}/skills/")
    print(f"  registered in {rel(INDEX)}")
    print(f"  registered in {rel(MARKETPLACE)} (top-level version bumped)")
    print("\nNext:")
    print(f"  1. Add skills under plugins/{plugin_id}/skills/<skill-id>/SKILL.md")
    print(f"  2. List each one under 'skills:' in plugins/{plugin_id}/plugin.yaml")
    print(f"     and in the '{plugin_id}' entry in index.yaml")
    print("  3. Add a row to the Plugins table in README.md")
    print("  4. Run ./scripts/validate.sh")
    return 0


# --------------------------------------------------------------------------


COMMANDS = {"validate": cmd_validate, "bump": cmd_bump, "new-plugin": cmd_new_plugin}


def main(argv: list[str]) -> int:
    if not argv or argv[0] not in COMMANDS:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    try:
        return COMMANDS[argv[0]](argv[1:])
    except Fail as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
