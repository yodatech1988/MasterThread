#!/usr/bin/env python3
"""Regenerate docs/AGENTS.md's "Global" table from claude-agents/*.md frontmatter.

Why this exists: before 2026-09-16, docs/AGENTS.md's Global table was hand-written and hand-edited
one PR at a time (see PR #50, #52) as the live roster under ~/.claude/agents grew past what the
doc tracked -- it reached 70 live agents while the doc indexed 25. A hand-written index rots
independently of the files it describes, silently, the same way any hand-maintained copy drifts
from its source. This script removes the hand-editing step: the table is derived from the actual
committed files every time, so the two cannot silently diverge.

Usage:
    python tools/generate_agents_md.py            # print the table to stdout
    python tools/generate_agents_md.py --write     # replace the Global table in docs/AGENTS.md
    python tools/generate_agents_md.py --check     # verify docs/AGENTS.md against claude-agents/
                                                    # and roster_meta.json; exit non-zero on drift

Only the "## Global (...)" section of docs/AGENTS.md is touched -- the "MasterThread/.claude/agents/"
and "Repo-local" sections describe agents that don't live in claude-agents/, so they're left alone.

KNOWN GAP as of 2026-09-17 (audit: docs/AGENT_ROSTER_AUDIT_2026-09-17.md, MasterThread PR #84,
recommendation R4): #52 landed and added a Role column (A = advisor / R = researcher, per
`standards/sessions/advisor_role.md`) to every docs/AGENTS.md table by hand, plus a whole
"Advisors against MasterThread's own standards" section -- none of it derived from this script,
because it was never finished. The audit also found the predictable result of that: three live
agents missing from the roster, three roster rows for agents that were never merged, and one
model mismatch (F1-F3), with nothing anywhere checking for any of it (F4).

This revision adds `--check` (see the module docstring's Usage section): a verification mode that
parses whatever markdown tables already exist in docs/AGENTS.md -- it does NOT require the doc to
have been produced by this script's own `--write`, so it can run against the current hand-edited
file as-is. It also extends `build_rows`/`render_table` so that, when `claude-agents/roster_meta.json`
exists, generation emits Role and Headless columns sourced from that file rather than needing them
re-derived from frontmatter (the classification itself is still an editorial judgment call, made in
roster_meta.json, not guessed here).

Still true: `--write` has deliberately NOT been run against docs/AGENTS.md in the PR that adds
`--check` (see that PR's body for why -- merge-order dependency on the roster-corrections PR).
`--check` on current main fails for the reasons the roster-corrections PR is fixing; once that
lands, `--check` should pass, and `--write` can be revisited separately with the Role/Headless
columns it now knows how to emit.
"""
import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
AGENTS_DIR = ROOT / "claude-agents"
AGENTS_MD = ROOT / "docs" / "AGENTS.md"
ROSTER_META = AGENTS_DIR / "roster_meta.json"

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)
WRITE_TOOLS = {"Write", "Edit", "NotebookEdit"}

# Section headings whose tables index agents that live under ~/.claude/agents/ (the global
# roster, mirrored into claude-agents/). "MasterThread/.claude/agents/" and "Repo-local" describe
# agents that live elsewhere on purpose and are excluded from the "must have a file" rule.
GLOBAL_SECTION_MARKER = "~/.claude/agents/"

ROSTER_META_ROLES = {"A", "R", "D"}
ROSTER_META_HEADLESS = {"yes", "needs-connector", "needs-local-keys", "local-only"}
ROSTER_META_READONLY = {"tools", "instruction", "n/a"}


def parse_frontmatter(text: str) -> dict:
    m = FRONTMATTER_RE.match(text)
    if not m:
        raise ValueError("no frontmatter block found")
    fields: dict[str, str] = {}
    key = None
    for line in m.group(1).splitlines():
        if not line.strip():
            continue
        kv = re.match(r"^([A-Za-z_]+):\s*(.*)$", line)
        if kv:
            key, val = kv.group(1), kv.group(2).strip()
            fields[key] = val
        elif key:
            # continuation line (frontmatter value wrapped across lines)
            fields[key] += " " + line.strip()
    return fields


def one_liner(description: str) -> str:
    """First clause of the description field, trimmed to keep the table scannable."""
    # descriptions are written as "Use when X. Does Y." or "Use to X ... -- Z"; take up to the
    # first " -- " or first ". " after a reasonable length, else the whole thing capped at a word
    # boundary (never mid-word) with an ellipsis.
    for sep in (" -- ", ". "):
        idx = description.find(sep)
        if idx != -1 and idx < 160:
            return description[:idx].strip().rstrip(".")
    limit = 140
    if len(description) <= limit:
        return description.strip().rstrip(".")
    cut = description[:limit].rsplit(" ", 1)[0]
    return cut.strip().rstrip(".,;") + "…"


def classify(tools: str) -> str:
    tool_list = {t.strip() for t in tools.split(",")}
    return "write" if tool_list & WRITE_TOOLS else "read-only"


def build_rows(meta: dict | None = None) -> list[dict]:
    """One dict per claude-agents/*.md file. When `meta` (roster_meta.json's parsed content) is
    given, each row also carries "role" and "headless" (empty string if that agent has no entry)."""
    rows = []
    for path in sorted(AGENTS_DIR.glob("*.md")):
        if path.name == "SYNC.md":
            continue
        fields = parse_frontmatter(path.read_text(encoding="utf-8"))
        name = fields.get("name", path.stem)
        model = fields.get("model", "?")
        tools = fields.get("tools", "")
        description = fields.get("description", "")
        row = {
            "name": name,
            "model": model,
            "access": classify(tools),
            "purpose": one_liner(description),
            "tools": tools,
        }
        if meta is not None:
            meta_entry = meta.get(name, {})
            row["role"] = meta_entry.get("role", "")
            row["headless"] = meta_entry.get("headless", "")
        rows.append(row)
    return rows


def render_table(rows: list[dict], meta_present: bool = False) -> str:
    write_count = sum(1 for r in rows if r["access"] == "write")
    columns = ["Agent", "Model"]
    if meta_present:
        columns += ["Role", "Headless"]
    columns += ["Access", "Purpose"]

    source_note = "`claude-agents/*.md` frontmatter"
    if meta_present:
        source_note += " and `claude-agents/roster_meta.json`"
    lines = [
        f"_Generated by `tools/generate_agents_md.py` from {source_note} — do not hand-edit this "
        f"table. {len(rows)} agents, {write_count} write-capable (has Write/Edit/NotebookEdit), "
        f"{len(rows) - write_count} read-only by tool grant._",
        "",
        "| " + " | ".join(columns) + " |",
        "|" + "|".join(["---"] * len(columns)) + "|",
    ]
    for r in rows:
        cells = [f"`{r['name']}`", r["model"]]
        if meta_present:
            cells += [r.get("role", ""), r.get("headless", "")]
        cells += [r["access"], r["purpose"]]
        lines.append("| " + " | ".join(cells) + " |")
    return "\n".join(lines) + "\n"


def load_roster_meta(path: pathlib.Path = ROSTER_META) -> tuple[dict | None, list[str]]:
    """Returns (meta_dict_or_None, warnings). meta is None (with a warning) when the file doesn't
    exist yet -- callers should skip meta-dependent rules in that case, not fail."""
    if not path.exists():
        return None, [f"{path} does not exist -- skipping roster_meta.json checks"]
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return None, [f"{path} is not valid JSON ({exc}) -- skipping roster_meta.json checks"]
    if not isinstance(data, dict):
        return None, [f"{path} is not a JSON object -- skipping roster_meta.json checks"]
    return data, []


# ---------------------------------------------------------------------------
# --check: parse whatever markdown tables already exist in docs/AGENTS.md and compare them
# against claude-agents/*.md and roster_meta.json. Does not require the doc to have been produced
# by --write.
# ---------------------------------------------------------------------------

_TABLE_ROW_RE = re.compile(r"^\s*\|.*\|\s*$")
_TABLE_SEP_RE = re.compile(r"^\s*\|(\s*:?-+:?\s*\|)+\s*$")


def clean_cell(text: str) -> str:
    """Strips a table cell down to comparable content: surrounding whitespace, one layer of
    `**bold**` wrapping the whole cell, and backticks."""
    text = text.strip()
    if text.startswith("**") and text.endswith("**") and len(text) >= 4:
        text = text[2:-2].strip()
    text = text.strip("`").strip()
    return text


def split_row(line: str) -> list[str]:
    body = line.strip()
    if body.startswith("|"):
        body = body[1:]
    if body.endswith("|"):
        body = body[:-1]
    return [cell.strip() for cell in body.split("|")]


def parse_tables(doc_text: str) -> list[dict]:
    """Returns a list of {"heading": str|None, "headers": [...], "rows": [[cell, ...], ...]} for
    every markdown table in `doc_text`, tagged with the nearest preceding "## " heading."""
    lines = doc_text.splitlines()
    tables = []
    heading = None
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if line.startswith("## "):
            heading = line[3:].strip()
            i += 1
            continue
        if (
            _TABLE_ROW_RE.match(line)
            and i + 1 < n
            and _TABLE_SEP_RE.match(lines[i + 1])
        ):
            headers = split_row(line)
            i += 2
            rows = []
            while i < n and _TABLE_ROW_RE.match(lines[i]) and not _TABLE_SEP_RE.match(lines[i]):
                rows.append(split_row(lines[i]))
                i += 1
            tables.append({"heading": heading, "headers": headers, "rows": rows})
            continue
        i += 1
    return tables


def _col_index(headers: list[str], *names: str) -> int | None:
    lowered = [h.strip().lower() for h in headers]
    for name in names:
        if name in lowered:
            return lowered.index(name)
    return None


def collect_doc_rows(doc_text: str) -> dict[str, list[dict]]:
    """Agent name -> list of {"model", "role", "headless", "is_global"} for every row across
    every table in docs/AGENTS.md that has an "Agent" column."""
    doc_rows: dict[str, list[dict]] = {}
    for table in parse_tables(doc_text):
        headers = table["headers"]
        agent_idx = _col_index(headers, "agent")
        if agent_idx is None:
            continue
        model_idx = _col_index(headers, "model")
        role_idx = _col_index(headers, "role")
        headless_idx = _col_index(headers, "headless")
        is_global = GLOBAL_SECTION_MARKER in (table["heading"] or "")
        for row in table["rows"]:
            if agent_idx >= len(row):
                continue
            name = clean_cell(row[agent_idx])
            if not name:
                continue
            entry = {
                "model": clean_cell(row[model_idx]) if model_idx is not None and model_idx < len(row) else None,
                "role": clean_cell(row[role_idx]) if role_idx is not None and role_idx < len(row) else None,
                "headless": clean_cell(row[headless_idx]) if headless_idx is not None and headless_idx < len(row) else None,
                "is_global": is_global,
            }
            doc_rows.setdefault(name, []).append(entry)
    return doc_rows


def check_roster(doc_text: str, agent_files: dict[str, str], meta: dict | None) -> list[str]:
    """Returns a list of human-readable problem strings (empty if the roster is in sync).

    `agent_files` is agent name -> model, built from claude-agents/*.md frontmatter.
    `meta` is roster_meta.json's parsed content, or None if it doesn't exist (meta rules skipped).
    """
    problems: list[str] = []
    doc_rows = collect_doc_rows(doc_text)

    # Rule: every claude-agents/*.md file has a row somewhere in docs/AGENTS.md.
    for name in sorted(agent_files):
        if name not in doc_rows:
            problems.append(f"claude-agents/{name}.md has no row in any docs/AGENTS.md table")

    # Rule: a row's Model cell disagrees with the file's frontmatter model.
    for name in sorted(doc_rows):
        if name not in agent_files:
            continue
        file_model = agent_files[name]
        for entry in doc_rows[name]:
            if entry["model"] and entry["model"] != file_model:
                problems.append(
                    f"{name}: docs/AGENTS.md Model cell says '{entry['model']}' but "
                    f"claude-agents/{name}.md frontmatter says '{file_model}'"
                )

    # Rule: a row in a GLOBAL section has no file in claude-agents/.
    for name in sorted(doc_rows):
        if name in agent_files:
            continue
        if any(entry["is_global"] for entry in doc_rows[name]):
            problems.append(
                f"{name}: has a row in a global (~/.claude/agents/) section of docs/AGENTS.md "
                f"but no claude-agents/{name}.md file"
            )

    if meta is None:
        return problems

    # Rule: roster_meta.json entries vs. claude-agents/*.md files.
    for name in sorted(agent_files):
        if name not in meta:
            problems.append(f"claude-agents/{name}.md has no roster_meta.json entry")
    for name in sorted(meta):
        if name not in agent_files:
            problems.append(f"roster_meta.json entry '{name}' has no claude-agents/{name}.md file")

    allowed_fields = {
        "role": ROSTER_META_ROLES,
        "headless": ROSTER_META_HEADLESS,
        "readonly": ROSTER_META_READONLY,
    }
    for name, entry in sorted(meta.items()):
        if not isinstance(entry, dict):
            problems.append(f"roster_meta.json entry '{name}' is not an object")
            continue
        for field, allowed in allowed_fields.items():
            value = entry.get(field)
            if value not in allowed:
                problems.append(
                    f"roster_meta.json entry '{name}' field '{field}' is '{value}', not one of "
                    f"{sorted(allowed)}"
                )
        if not isinstance(entry.get("dormant"), bool):
            problems.append(
                f"roster_meta.json entry '{name}' field 'dormant' is '{entry.get('dormant')}', "
                "not a JSON boolean"
            )

    # Rule: a row's Role/Headless cell disagrees with the meta entry.
    for name in sorted(doc_rows):
        if name not in meta or not isinstance(meta[name], dict):
            continue
        meta_role = meta[name].get("role")
        meta_headless = meta[name].get("headless")
        for entry in doc_rows[name]:
            if entry["role"] and meta_role and entry["role"] != meta_role:
                problems.append(
                    f"{name}: docs/AGENTS.md Role cell says '{entry['role']}' but "
                    f"roster_meta.json says '{meta_role}'"
                )
            if entry["headless"] and meta_headless and entry["headless"] != meta_headless:
                problems.append(
                    f"{name}: docs/AGENTS.md Headless cell says '{entry['headless']}' but "
                    f"roster_meta.json says '{meta_headless}'"
                )

    return problems


def replace_global_section(doc: str, table: str) -> str:
    # Global section runs from its "## Global (...)" heading to the next "## " heading.
    pattern = re.compile(
        r"(## Global \(`~/\.claude/agents/`, available in every repo\)\n\n)"
        r".*?"
        r"(\n\n## )",
        re.DOTALL,
    )
    replacement = r"\1" + table.replace("\\", "\\\\") + r"\2"
    new_doc, count = pattern.subn(replacement, doc)
    if count != 1:
        raise SystemExit(
            "could not find exactly one Global section to replace in docs/AGENTS.md "
            f"(found {count}) -- check the heading text hasn't changed"
        )
    return new_doc


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--write", action="store_true", help="write docs/AGENTS.md in place")
    group.add_argument(
        "--check",
        action="store_true",
        help="verify docs/AGENTS.md against claude-agents/*.md and roster_meta.json; "
        "exits non-zero with a problem list if anything disagrees",
    )
    args = parser.parse_args()

    meta, meta_warnings = load_roster_meta()

    if args.check:
        for warning in meta_warnings:
            print(f"warning: {warning}", file=sys.stderr)
        agent_files = {row["name"]: row["model"] for row in build_rows()}
        doc_text = AGENTS_MD.read_text(encoding="utf-8")
        problems = check_roster(doc_text, agent_files, meta)
        if not problems:
            print("generate_agents_md.py --check: in sync, no problems found.")
            return 0
        print(f"generate_agents_md.py --check: {len(problems)} problem(s) found:")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    rows = build_rows(meta)
    table = render_table(rows, meta_present=meta is not None)

    if not args.write:
        sys.stdout.write(table)
        return 0

    doc = AGENTS_MD.read_text(encoding="utf-8")
    new_doc = replace_global_section(doc, table)
    AGENTS_MD.write_text(new_doc, encoding="utf-8")
    print(f"Wrote {len(rows)} agents into {AGENTS_MD}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
