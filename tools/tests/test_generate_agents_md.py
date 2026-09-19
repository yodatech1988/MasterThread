"""Unit tests for tools/generate_agents_md.py -- run with `python -m unittest` from the repo
root, or `python -m unittest discover -s tools/tests`.

Uses the small fixture agent files under tools/tests/fixtures/claude_agents/ (sample-reporter.md:
model haiku, sample-advisor.md: model sonnet, plus a SYNC.md that must be ignored) for
build_rows()-based tests, and inline doc-text strings for the pure `check_roster`/`parse_tables`
tests since those never touch the filesystem.
"""
import pathlib
import sys
import unittest

TOOLS_DIR = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(TOOLS_DIR))

import generate_agents_md as gen  # noqa: E402

FIXTURES = pathlib.Path(__file__).resolve().parent / "fixtures" / "claude_agents"


class BuildRowsTests(unittest.TestCase):
    def setUp(self):
        self._real_dir = gen.AGENTS_DIR
        gen.AGENTS_DIR = FIXTURES
        self.addCleanup(lambda: setattr(gen, "AGENTS_DIR", self._real_dir))

    def test_sync_md_is_ignored(self):
        rows = gen.build_rows()
        names = {r["name"] for r in rows}
        self.assertNotIn("SYNC", names)
        self.assertEqual(names, {"sample-reporter", "sample-advisor"})

    def test_model_and_access_from_frontmatter(self):
        rows = {r["name"]: r for r in gen.build_rows()}
        self.assertEqual(rows["sample-reporter"]["model"], "haiku")
        self.assertEqual(rows["sample-reporter"]["access"], "read-only")
        self.assertEqual(rows["sample-advisor"]["model"], "sonnet")

    def test_meta_role_headless_attached_when_given(self):
        meta = {"sample-reporter": {"role": "R", "headless": "yes"}}
        rows = {r["name"]: r for r in gen.build_rows(meta)}
        self.assertEqual(rows["sample-reporter"]["role"], "R")
        self.assertEqual(rows["sample-reporter"]["headless"], "yes")
        # No entry for sample-advisor -> blank, not a crash.
        self.assertEqual(rows["sample-advisor"]["role"], "")


class RenderTableTests(unittest.TestCase):
    def test_no_meta_has_four_columns(self):
        rows = [{"name": "a", "model": "haiku", "access": "read-only", "purpose": "p"}]
        table = gen.render_table(rows, meta_present=False)
        self.assertIn("| Agent | Model | Access | Purpose |", table)
        self.assertNotIn("Role", table)

    def test_meta_present_adds_role_and_headless_columns(self):
        rows = [
            {
                "name": "a",
                "model": "haiku",
                "access": "read-only",
                "purpose": "p",
                "role": "R",
                "headless": "yes",
            }
        ]
        table = gen.render_table(rows, meta_present=True)
        self.assertIn("| Agent | Model | Role | Headless | Access | Purpose |", table)
        self.assertIn("| `a` | haiku | R | yes | read-only | p |", table)


class LoadRosterMetaTests(unittest.TestCase):
    def test_missing_file_returns_none_with_warning(self, tmp_name="does-not-exist.json"):
        meta, warnings = gen.load_roster_meta(FIXTURES / tmp_name)
        self.assertIsNone(meta)
        self.assertEqual(len(warnings), 1)
        self.assertIn("does not exist", warnings[0])


class ParseTablesTests(unittest.TestCase):
    DOC = """# Roster

## Global (`~/.claude/agents/`, available in every repo)

| Agent | Model | Role | Purpose |
|---|---|---|---|
| `sample-reporter` | haiku | R | Reports a fact |
| `ghost-agent` | opus |  | No file exists for this one |

## Repo-local (need that repo's own tools/paths)

| Agent | Model | Repo | Purpose |
|---|---|---|---|
| `repo-only-agent` | sonnet | some-repo | Lives only in that repo, not global |
"""

    def test_finds_both_tables_with_headings(self):
        tables = gen.parse_tables(self.DOC)
        self.assertEqual(len(tables), 2)
        self.assertIn("Global", tables[0]["heading"])
        self.assertIn("Repo-local", tables[1]["heading"])

    def test_clean_cell_strips_backticks_and_bold(self):
        self.assertEqual(gen.clean_cell("`agent-name`"), "agent-name")
        self.assertEqual(gen.clean_cell("**A**"), "A")
        self.assertEqual(gen.clean_cell("  plain  "), "plain")

    def test_collect_doc_rows_marks_global_vs_not(self):
        doc_rows = gen.collect_doc_rows(self.DOC)
        self.assertTrue(doc_rows["sample-reporter"][0]["is_global"])
        self.assertFalse(doc_rows["repo-only-agent"][0]["is_global"])
        self.assertEqual(doc_rows["sample-reporter"][0]["model"], "haiku")
        self.assertEqual(doc_rows["sample-reporter"][0]["role"], "R")


class CheckRosterTests(unittest.TestCase):
    GLOBAL_HEADING = "## Global (`~/.claude/agents/`, available in every repo)"
    REPO_LOCAL_HEADING = "## Repo-local (need that repo's own tools/paths)"

    def _doc(self, global_rows="", repo_local_rows=""):
        return (
            f"{self.GLOBAL_HEADING}\n\n"
            "| Agent | Model | Role | Headless | Purpose |\n"
            "|---|---|---|---|---|\n"
            f"{global_rows}"
            f"\n{self.REPO_LOCAL_HEADING}\n\n"
            "| Agent | Model | Repo | Purpose |\n"
            "|---|---|---|---|\n"
            f"{repo_local_rows}"
        )

    def test_in_sync_has_no_problems(self):
        doc = self._doc(global_rows="| `agent-a` | haiku |  |  | does a thing |\n")
        problems = gen.check_roster(doc, {"agent-a": "haiku"}, meta=None)
        self.assertEqual(problems, [])

    def test_file_with_no_row_is_a_problem(self):
        doc = self._doc()
        problems = gen.check_roster(doc, {"agent-a": "haiku"}, meta=None)
        self.assertTrue(any("agent-a" in p and "no row" in p for p in problems))

    def test_model_mismatch_is_a_problem(self):
        doc = self._doc(global_rows="| `agent-a` | sonnet |  |  | does a thing |\n")
        problems = gen.check_roster(doc, {"agent-a": "haiku"}, meta=None)
        self.assertTrue(any("Model cell says 'sonnet'" in p for p in problems))

    def test_global_row_with_no_file_is_a_problem(self):
        doc = self._doc(global_rows="| `ghost-agent` | opus |  |  | no file for this |\n")
        problems = gen.check_roster(doc, {}, meta=None)
        self.assertTrue(any("ghost-agent" in p and "global" in p for p in problems))

    def test_repo_local_row_with_no_file_is_not_a_problem(self):
        # Repo-local rows describe agents that live in another repo's .claude/agents/, not
        # claude-agents/ -- the "row has no file" rule must not fire for them.
        doc = self._doc(repo_local_rows="| `elsewhere-agent` | sonnet | other-repo | lives elsewhere |\n")
        problems = gen.check_roster(doc, {}, meta=None)
        self.assertEqual(problems, [])

    def test_meta_missing_entry_is_a_problem(self):
        doc = self._doc(global_rows="| `agent-a` | haiku |  |  | does a thing |\n")
        problems = gen.check_roster(doc, {"agent-a": "haiku"}, meta={})
        self.assertTrue(any("agent-a" in p and "no roster_meta.json entry" in p for p in problems))

    def test_meta_entry_with_no_file_is_a_problem(self):
        doc = self._doc()
        meta = {"orphan-entry": {"role": "R", "headless": "yes", "readonly": "tools", "dormant": False}}
        problems = gen.check_roster(doc, {}, meta=meta)
        self.assertTrue(any("orphan-entry" in p and "no claude-agents" in p for p in problems))

    def test_meta_value_outside_allowed_set_is_a_problem(self):
        doc = self._doc(global_rows="| `agent-a` | haiku |  |  | does a thing |\n")
        meta = {"agent-a": {"role": "Z", "headless": "yes", "readonly": "tools", "dormant": False}}
        problems = gen.check_roster(doc, {"agent-a": "haiku"}, meta=meta)
        self.assertTrue(any("field 'role'" in p for p in problems))

    def test_meta_dormant_must_be_boolean(self):
        doc = self._doc(global_rows="| `agent-a` | haiku |  |  | does a thing |\n")
        meta = {"agent-a": {"role": "R", "headless": "yes", "readonly": "tools", "dormant": "false"}}
        problems = gen.check_roster(doc, {"agent-a": "haiku"}, meta=meta)
        self.assertTrue(any("'dormant'" in p for p in problems))

    def test_role_cell_disagrees_with_meta(self):
        doc = self._doc(global_rows="| `agent-a` | haiku | R |  | does a thing |\n")
        meta = {"agent-a": {"role": "A", "headless": "yes", "readonly": "tools", "dormant": False}}
        problems = gen.check_roster(doc, {"agent-a": "haiku"}, meta=meta)
        self.assertTrue(any("Role cell says 'R'" in p for p in problems))

    def test_headless_cell_disagrees_with_meta(self):
        doc = self._doc(global_rows="| `agent-a` | haiku |  | yes | does a thing |\n")
        meta = {
            "agent-a": {
                "role": "R",
                "headless": "needs-connector",
                "readonly": "tools",
                "dormant": False,
            }
        }
        problems = gen.check_roster(doc, {"agent-a": "haiku"}, meta=meta)
        self.assertTrue(any("Headless cell says 'yes'" in p for p in problems))

    def test_meta_none_skips_meta_rules_entirely(self):
        doc = self._doc(global_rows="| `agent-a` | haiku | Z |  | does a thing |\n")
        # 'Z' would be an invalid role if meta rules ran, but meta=None must skip them.
        problems = gen.check_roster(doc, {"agent-a": "haiku"}, meta=None)
        self.assertEqual(problems, [])


NL = chr(10)


def _doc(*lines):
    return NL.join(lines) + NL


ADV_HEAD = "## Advisors against MasterThread's own standards (global, `~/.claude/agents/`)"
GLOBAL_TABLE = _doc(
    "## Global (`~/.claude/agents/`, available in every repo)",
    "",
    "| Agent | Model | Role | Headless | Purpose | Grounded in |",
    "|---|---|---|---|---|---|",
    "| `sample-reporter` | sonnet | A | local-only | Hand purpose | hand grounding |",
    "",
)


class SyncDocTests(unittest.TestCase):
    FILES = {"sample-reporter": "haiku", "x-advisor": "sonnet", "y-drafter": "haiku", "z-reporter": "haiku"}
    META = {
        "sample-reporter": {"role": "R", "headless": "yes"},
        "x-advisor": {"role": "A", "headless": "yes"},
        "y-drafter": {"role": "D", "headless": "yes"},
        "z-reporter": {"role": "R", "headless": "yes", "group": "standards"},
    }

    def test_wrong_derived_cells_are_rewritten_and_prose_is_kept(self):
        out = gen.sync_doc(GLOBAL_TABLE, self.FILES, self.META)
        self.assertIn("| `sample-reporter` | haiku | R | yes | Hand purpose | hand grounding |", out)

    def test_bold_emphasis_on_a_correct_value_is_not_fought_over(self):
        doc = GLOBAL_TABLE.replace("| sonnet |", "| **haiku** |")
        out = gen.sync_doc(doc, self.FILES, {"sample-reporter": {"role": "A", "headless": "local-only"}})
        self.assertIn("**haiku**", out)

    def test_role_style_advisor_and_drafter_bold_reporter_plain(self):
        self.assertEqual(gen.role_cell("A"), "**A**")
        self.assertEqual(gen.role_cell("D"), "**D**")
        self.assertEqual(gen.role_cell("R"), "R")

    def test_agent_with_no_file_is_left_exactly_as_written(self):
        doc = _doc("## Repo-local", "", "| Agent | Model | Role | Headless | Repo | Purpose |", "|---|---|---|---|---|---|",
                   "| `local-only-agent` | **opus** | **A** | yes | some-repo | hand text |")
        self.assertEqual(gen.sync_doc(doc, self.FILES, self.META), doc)

    def test_sync_is_idempotent(self):
        once = gen.sync_doc(GLOBAL_TABLE, self.FILES, self.META)
        self.assertEqual(gen.sync_doc(once, self.FILES, self.META), once)

    def test_advisors_section_gets_new_rows_alphabetically_with_derived_cells(self):
        doc = _doc(ADV_HEAD, "", "| Agent | Model | Role | Headless | Purpose |", "|---|---|---|---|---|",
                   "| `y-drafter` | haiku | **D** | yes | hand y |")
        out = gen.sync_doc(doc, self.FILES, self.META, {"x-advisor": "Verdict on X", "z-reporter": "Reports Z"})
        rows = [l for l in out.split(NL) if l.startswith("| `")]
        self.assertEqual([r.split("|")[1].strip() for r in rows], ["`y-drafter`", "`x-advisor`", "`z-reporter`"])
        self.assertIn("| `x-advisor` | sonnet | **A** | yes | Verdict on X |", out)

    def test_advisors_section_drops_a_row_that_no_longer_belongs(self):
        doc = _doc(ADV_HEAD, "", "| Agent | Model | Role | Headless | Purpose |", "|---|---|---|---|---|",
                   "| `sample-reporter` | haiku | R | yes | not an advisor |")
        out = gen.sync_doc(doc, self.FILES, self.META)
        self.assertNotIn("sample-reporter", out)

    def test_advisors_section_keeps_a_row_for_an_agent_with_no_file(self):
        # a hand-written row for an advisor that has no claude-agents/ file must survive --write
        row = "| `hand-only-advisor` | **opus** | **A** | yes | hand text |"
        doc = _doc(ADV_HEAD, "", "| Agent | Model | Role | Headless | Purpose |", "|---|---|---|---|---|", row)
        out = gen.sync_doc(doc, self.FILES, self.META)
        self.assertIn(row, out)

    def test_group_other_keeps_a_drafter_out_and_group_standards_brings_a_reporter_in(self):
        meta = dict(self.META)
        meta["y-drafter"] = {"role": "D", "headless": "yes", "group": "other"}
        self.assertEqual(gen.advisor_section_names(self.FILES, meta), ["x-advisor", "z-reporter"])

    def test_check_reports_the_line_write_would_change(self):
        lines = gen.drift_lines(GLOBAL_TABLE, gen.sync_doc(GLOBAL_TABLE, self.FILES, self.META))
        self.assertEqual(len(lines), 1)
        self.assertIn("sample-reporter", lines[0])

    def test_no_drift_reports_nothing(self):
        synced = gen.sync_doc(GLOBAL_TABLE, self.FILES, self.META)
        self.assertEqual(gen.drift_lines(synced, gen.sync_doc(synced, self.FILES, self.META)), [])

    def test_invalid_group_value_is_a_problem(self):
        meta = {"sample-reporter": {"role": "R", "headless": "yes", "readonly": "n/a", "dormant": False, "group": "bogus"}}
        problems = gen.check_roster(GLOBAL_TABLE, {"sample-reporter": "haiku"}, meta)
        self.assertTrue(any("'group'" in p for p in problems))


if __name__ == "__main__":
    unittest.main()
