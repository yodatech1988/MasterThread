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


if __name__ == "__main__":
    unittest.main()
