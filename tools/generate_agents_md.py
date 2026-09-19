#!/usr/bin/env python3
"""Keep docs/AGENTS.md's derived facts generated from claude-agents/, and fail CI when they drift.

Why this exists: before 2026-09-16, docs/AGENTS.md was hand-written and hand-edited one PR at a
time (see PR #50, #52) as the live roster under ~/.claude/agents grew past what the doc tracked --
it reached 70 live agents while the doc indexed 25. A hand-written index rots independently of the
files it describes, silently. The 2026-09-17 audit (docs/AGENT_ROSTER_AUDIT_2026-09-17.md, R4)
found the result: three live agents missing, three rows for agents never merged, one model mismatch.

What is generated, and what is not:
  * DERIVED (rewritten by --write, verified by --check): the Model cell (from each agent file's
    frontmatter), the Role and Headless cells (from claude-agents/roster_meta.json), and the
    membership of the "Advisors against MasterThread's own standards" section (every *-advisor and
    *-drafter file, plus any roster_meta.json entry with "group": "standards", minus any entry with
    "group": "other"). A new advisor/drafter file therefore gets its row from --write with no hand
    edit; its Purpose starts as the description's first sentence.
  * HAND-WRITTEN (never touched once a row exists): the Purpose, Grounded in and Repo cells and the
    prose around the tables -- editorial text, not facts about the files. Rows for agents that have
    no file in claude-agents/ (MasterThread-local and repo-local agents) are left exactly as written.
  The classification itself (Role, Headless, group) is an editorial judgment made once, in
  roster_meta.json, and validated there.

Usage:
    python tools/generate_agents_md.py            # print a flat table of every agent to stdout
    python tools/generate_agents_md.py --write     # make docs/AGENTS.md's derived cells match
    python tools/generate_agents_md.py --check     # verify docs/AGENTS.md against claude-agents/
                                                    # and roster_meta.json; exit non-zero on drift.
                                                    # Drift includes "--write would change a line".
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
        group = entry.get("group")
        if group is not None and group not in ROSTER_META_GROUPS:
            problems.append(
                f"roster_meta.json entry '{name}' field 'group' is '{group}', not one of "
                f"{sorted(ROSTER_META_GROUPS)} (or absent)"
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


# ---------------------------------------------------------------------------
# Derived cells and the Advisors section. `--write` rewrites these in place; `--check` fails when
# doing so would change anything. Prose columns (Purpose, Grounded in, Repo) stay hand-written
# because they are editorial text, not facts about the agent's files.
# ---------------------------------------------------------------------------

NL = chr(10)
ADVISORS_HEADING = "## Advisors against MasterThread's own standards"
ROLE_CELLS = {"A": "**A**", "D": "**D**", "R": "R"}
STANDARDS_SUFFIXES = ("-advisor", "-drafter")
ROSTER_META_GROUPS = {"standards", "other"}


def role_cell(role: str) -> str:
    """How a Role value is written in the doc: Advisor and Drafter are bold, Researcher is plain."""
    return ROLE_CELLS.get(role, role)


def advisor_section_names(agent_files: dict, meta: dict | None) -> list[str]:
    """Names that belong in the Advisors section, sorted. Rule: a file named *-advisor or
    *-drafter, unless its roster_meta.json entry says `"group": "other"` (an advisor or drafter
    grounded in a policy or a tool rather than a standards/ file); plus any entry that says
    `"group": "standards"` (e.g. the two reporters that read the standards tree)."""
    meta = meta or {}
    names = []
    for name in sorted(agent_files):
        group = meta.get(name, {}).get("group") if isinstance(meta.get(name), dict) else None
        if group == "standards" or (group != "other" and name.endswith(STANDARDS_SUFFIXES)):
            names.append(name)
    return names


def _row_line(cells: list[str]) -> str:
    return "| " + " | ".join(cells) + " |"


def sync_doc(doc_text: str, agent_files: dict, meta: dict | None, purposes: dict | None = None) -> str:
    """Returns docs/AGENTS.md with every derived cell made to match the files:
    Model (from frontmatter), Role and Headless (from roster_meta.json) in every table that has
    those columns, and the Advisors section's table rebuilt to hold exactly the right agents.
    Existing rows keep their order and their prose cells; new rows are appended alphabetically with
    `purposes[name]` (the one-line description) as their Purpose. Rows of agents that have no file
    (repo-local, MasterThread-local) are left exactly as written."""
    meta = meta or {}
    purposes = purposes or {}
    wanted = advisor_section_names(agent_files, meta)
    lines = doc_text.split(NL)
    out: list[str] = []
    heading = None
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if line.startswith("## "):
            heading = line[3:].strip()
        is_table_start = _TABLE_ROW_RE.match(line) and i + 1 < n and _TABLE_SEP_RE.match(lines[i + 1])
        if not is_table_start:
            out.append(line)
            i += 1
            continue
        headers = split_row(line)
        agent_idx = _col_index(headers, "agent")
        j = i + 2
        body = []
        while j < n and _TABLE_ROW_RE.match(lines[j]) and not _TABLE_SEP_RE.match(lines[j]):
            body.append(lines[j])
            j += 1
        if agent_idx is None:
            out.extend(lines[i:j])
            i = j
            continue
        model_idx = _col_index(headers, "model")
        role_idx = _col_index(headers, "role")
        headless_idx = _col_index(headers, "headless")
        is_advisors = (heading or "").startswith(ADVISORS_HEADING[3:])
        new_body = []
        seen = set()
        for row_line in body:
            cells = split_row(row_line)
            name = clean_cell(cells[agent_idx]) if agent_idx < len(cells) else ""
            if is_advisors and name not in wanted:
                continue  # no longer belongs here; --check then reports it if it has no other row
            orig_cells = list(cells)
            if name in agent_files and len(cells) == len(headers):
                # Only rewrite a cell whose VALUE differs (clean_cell strips bold/backticks), so a
                # deliberate emphasis such as **opus** is not fought over.
                entry = meta.get(name) if isinstance(meta.get(name), dict) else {}
                if model_idx is not None and agent_files[name] and clean_cell(cells[model_idx]) != agent_files[name]:
                    cells[model_idx] = agent_files[name]
                if role_idx is not None and entry.get("role") and clean_cell(cells[role_idx]) != entry["role"]:
                    cells[role_idx] = role_cell(entry["role"])
                if headless_idx is not None and entry.get("headless") and clean_cell(cells[headless_idx]) != entry["headless"]:
                    cells[headless_idx] = entry["headless"]
                if cells != orig_cells:
                    row_line = _row_line(cells)
            seen.add(name)
            new_body.append(row_line)
        if is_advisors:
            for name in wanted:
                if name in seen:
                    continue
                entry = meta.get(name) if isinstance(meta.get(name), dict) else {}
                cells = [""] * len(headers)
                cells[agent_idx] = "`" + name + "`"
                if model_idx is not None:
                    cells[model_idx] = agent_files[name]
                if role_idx is not None:
                    cells[role_idx] = role_cell(entry.get("role", ""))
                if headless_idx is not None:
                    cells[headless_idx] = entry.get("headless", "")
                for k, h in enumerate(headers):
                    if h.strip().lower() == "purpose":
                        cells[k] = purposes.get(name, "")
                new_body.append(_row_line(cells))
        out.extend([line, lines[i + 1]])
        out.extend(new_body)
        i = j
    return NL.join(out)


def drift_lines(doc_text: str, synced: str, limit: int = 12) -> list[str]:
    """Human-readable list of the lines --write would change (for --check's report)."""
    import difflib

    a, b = doc_text.split(NL), synced.split(NL)
    found = []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if tag == "equal":
            continue
        was = " // ".join(x.strip()[:90] for x in a[i1:i2]) or "(nothing)"
        now = " // ".join(x.strip()[:90] for x in b[j1:j2]) or "(removed)"
        found.append(f"line {i1 + 1}: {was}  ->  {now}")
    return found[:limit] + ([f"... and {len(found) - limit} more"] if len(found) > limit else [])



def load_agent_facts() -> tuple[dict, dict]:
    """(agent name -> model, agent name -> one-line purpose) from claude-agents/*.md."""
    rows = build_rows()
    return {r["name"]: r["model"] for r in rows}, {r["name"]: r["purpose"] for r in rows}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--write", action="store_true", help="make docs/AGENTS.md's derived cells match the files")
    group.add_argument(
        "--check",
        action="store_true",
        help="verify docs/AGENTS.md against claude-agents/*.md and roster_meta.json; "
        "exits non-zero with a problem list if anything disagrees or --write would change a line",
    )
    args = parser.parse_args()

    meta, meta_warnings = load_roster_meta()

    if args.check:
        for warning in meta_warnings:
            print(f"warning: {warning}", file=sys.stderr)
        agent_files, purposes = load_agent_facts()
        doc_text = AGENTS_MD.read_text(encoding="utf-8")
        problems = check_roster(doc_text, agent_files, meta)
        for line in drift_lines(doc_text, sync_doc(doc_text, agent_files, meta, purposes)):
            problems.append(f"docs/AGENTS.md is not what --write would produce: {line}")
        if not problems:
            print("generate_agents_md.py --check: in sync, no problems found.")
            return 0
        print(f"generate_agents_md.py --check: {len(problems)} problem(s) found:")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    if not args.write:
        rows = build_rows(meta)
        sys.stdout.write(render_table(rows, meta_present=meta is not None))
        return 0

    agent_files, purposes = load_agent_facts()
    doc = AGENTS_MD.read_text(encoding="utf-8")
    new_doc = sync_doc(doc, agent_files, meta, purposes)
    if new_doc == doc:
        print("docs/AGENTS.md already matches; nothing written.", file=sys.stderr)
        return 0
    AGENTS_MD.write_text(new_doc, encoding="utf-8")
    print(f"Updated derived cells in {AGENTS_MD}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
