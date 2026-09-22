"""Unit tests for tools/check_depends_on.py -- run with
`python -m unittest discover -s tools/tests` from the repo root.

No network access: the GitHub API is replaced by a dict-backed fake."""
import importlib.util
import io
import os
import pathlib
import unittest
from contextlib import redirect_stdout
from unittest import mock

HERE = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("check_depends_on", HERE.parent / "check_depends_on.py")
dep = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dep)

REPO = "yodatech1988/MasterThread"


class ParserTests(unittest.TestCase):
    def parse(self, body):
        return dep.parse_depends_on(body, REPO)

    def test_no_lines(self):
        self.assertEqual(self.parse("Just a PR.\n\nNothing here."), ([], []))
        self.assertEqual(self.parse(None), ([], []))

    def test_short_ref_uses_current_repo(self):
        self.assertEqual(self.parse("Depends-on: #169"), ([(REPO, 169)], []))

    def test_cross_repo_ref(self):
        self.assertEqual(self.parse("Depends-on: yodatech1988/ops-platform#42"),
                         ([("yodatech1988/ops-platform", 42)], []))

    def test_url_ref(self):
        self.assertEqual(self.parse("Depends-on: https://github.com/yodatech1988/core/pull/7"),
                         ([("yodatech1988/core", 7)], []))

    def test_several_on_one_line_and_several_lines(self):
        refs, errs = self.parse("depends-on: #1, #2 and #3\nDEPENDS-ON: #4\n")
        self.assertEqual(errs, [])
        self.assertEqual([n for _, n in refs], [1, 2, 3, 4])

    def test_bullet_bold_and_backticks(self):
        body = "- Depends-on: #10\n**Depends-on:** #11\n* Depends-on: `#12`\n"
        self.assertEqual([n for _, n in self.parse(body)[0]], [10, 11, 12])

    def test_duplicates_removed(self):
        refs, _ = self.parse("Depends-on: #5\nDepends-on: yodatech1988/masterthread#5")
        self.assertEqual(refs, [(REPO, 5)])

    def test_none_means_no_dependencies(self):
        self.assertEqual(self.parse("Depends-on: none"), ([], []))
        self.assertEqual(self.parse("Depends-on: None."), ([], []))

    def test_fenced_examples_ignored(self):
        body = "Example:\n```\nDepends-on: #999\nDepends-on: owner/repo#N\n```\nDepends-on: #3\n"
        self.assertEqual(self.parse(body), ([(REPO, 3)], []))

    def test_prose_is_not_read(self):
        self.assertEqual(self.parse("This depends on: the owner merging first"), ([], []))

    def test_unreadable_ref_fails_closed(self):
        refs, errs = self.parse("Depends-on: 169")
        self.assertEqual(refs, [])
        self.assertEqual(len(errs), 1)
        self.assertIn("'169'", errs[0])

    def test_empty_line_fails_closed(self):
        refs, errs = self.parse("Depends-on:")
        self.assertEqual(refs, [])
        self.assertEqual(len(errs), 1)


def pr(number, *, merged=False, state="open", base="main", default="main", body="", sha=None,
       title="t"):
    return {"number": number, "title": title, "merged": merged, "state": state, "body": body,
            "base": {"ref": base, "repo": {"default_branch": default}},
            "head": {"sha": sha or f"{number:040d}"},
            "merge_commit_sha": f"m{number:039d}" if merged else None}


class FakeGitHub:
    def __init__(self, routes, compare="behind"):
        self.routes = routes
        self.compare = compare
        self.posts = []

    def get(self, path):
        if "/compare/" in path:
            return 200, {"status": self.compare}
        if path in self.routes:
            return 200, self.routes[path]
        return 404, None

    def post(self, path):
        self.posts.append(path)
        return 201, None


def route(p, repo=REPO):
    return {f"/repos/{repo}/pulls/{p['number']}": p}


class EvaluateTests(unittest.TestCase):
    def run_check(self, gh, number):
        out = io.StringIO()
        with redirect_stdout(out), mock.patch.dict(os.environ, {"GITHUB_STEP_SUMMARY": ""}):
            rc = dep.cmd_check(gh, REPO, number)
        return rc, out.getvalue()

    def test_passes_with_no_dependencies(self):
        gh = FakeGitHub(route(pr(200)))
        rc, out = self.run_check(gh, 200)
        self.assertEqual(rc, 0)
        self.assertIn("PASS", out)

    def test_passes_when_dependency_merged_into_main(self):
        gh = FakeGitHub({**route(pr(200, body="Depends-on: #169")), **route(pr(169, merged=True, state="closed"))})
        rc, out = self.run_check(gh, 200)
        self.assertEqual(rc, 0, out)

    def test_fails_when_dependency_open(self):
        gh = FakeGitHub({**route(pr(175, body="Depends-on: #169")), **route(pr(169, title="plan"))})
        rc, out = self.run_check(gh, 175)
        self.assertEqual(rc, 1)
        self.assertIn("#169 (plan) is still open", out)
        self.assertIn("::error title=depends-on::", out)

    def test_fails_when_dependency_closed_unmerged(self):
        gh = FakeGitHub({**route(pr(2, body="Depends-on: #1")), **route(pr(1, state="closed"))})
        rc, out = self.run_check(gh, 2)
        self.assertEqual(rc, 1)
        self.assertIn("closed without merging", out)

    def test_fails_when_dependency_merged_into_side_branch(self):
        side = pr(176, merged=True, state="closed", base="agent/x/feature")
        gh = FakeGitHub({**route(pr(190, body="Depends-on: #176")), **route(side)})
        rc, out = self.run_check(gh, 190)
        self.assertEqual(rc, 1)
        self.assertIn("merged into 'agent/x/feature', not 'main'", out)

    def test_fails_when_merge_commit_not_on_default(self):
        gh = FakeGitHub({**route(pr(2, body="Depends-on: #1")), **route(pr(1, merged=True))},
                        compare="diverged")
        rc, out = self.run_check(gh, 2)
        self.assertEqual(rc, 1)
        self.assertIn("is not on 'main'", out)

    def test_fails_when_pr_targets_side_branch(self):
        gh = FakeGitHub(route(pr(186, base="agent/x/feature")))
        rc, out = self.run_check(gh, 186)
        self.assertEqual(rc, 1)
        self.assertIn("targets 'agent/x/feature', not 'main'", out)

    def test_fails_when_dependency_missing_or_unreadable(self):
        gh = FakeGitHub(route(pr(2, body="Depends-on: yodatech1988/private#9")))
        rc, out = self.run_check(gh, 2)
        self.assertEqual(rc, 1)
        self.assertIn("not found, or not readable", out)

    def test_fails_when_dependency_is_an_issue(self):
        gh = FakeGitHub({**route(pr(2, body="Depends-on: #50")),
                         f"/repos/{REPO}/issues/50": {"number": 50}})
        rc, out = self.run_check(gh, 2)
        self.assertEqual(rc, 1)
        self.assertIn("is an issue, not a pull request", out)

    def test_fails_on_self_reference_and_parse_error(self):
        gh = FakeGitHub(route(pr(7, body="Depends-on: #7\nDepends-on: seven")))
        rc, out = self.run_check(gh, 7)
        self.assertEqual(rc, 1)
        self.assertIn("cannot depend on itself", out)
        self.assertIn("FAIL parse", out)

    def test_fails_closed_when_pr_itself_unreadable(self):
        rc, out = self.run_check(FakeGitHub({}), 404)
        self.assertEqual(rc, 1)
        self.assertIn("failing closed", out)


class RecheckTests(unittest.TestCase):
    def setUp(self):
        self.open_pr = pr(200, body="Depends-on: #169", sha="a" * 40)
        self.routes = {
            f"/repos/{REPO}/pulls?state=open&per_page=100": [self.open_pr, pr(201)],
            **route(pr(169, merged=True, state="closed")),
            f"/repos/{REPO}/actions/workflows/depends-on.yml/runs?event=pull_request&head_sha={'a' * 40}&per_page=1":
                {"workflow_runs": [{"id": 555, "status": "completed", "conclusion": "failure"}]},
        }

    def recheck(self, gh, env):
        out = io.StringIO()
        with redirect_stdout(out), mock.patch.dict(os.environ, env, clear=False):
            rc = dep.cmd_recheck(gh, REPO)
        return rc, out.getvalue()

    def test_rerun_suppressed_outside_actions(self):
        gh = FakeGitHub(self.routes)
        rc, out = self.recheck(gh, {"GITHUB_ACTIONS": "", "GITHUB_REPOSITORY": ""})
        self.assertEqual(rc, 0)
        self.assertEqual(gh.posts, [])
        self.assertIn("RERUN suppressed (non-default target = test)", out)

    def test_rerun_suppressed_for_other_repo(self):
        gh = FakeGitHub(self.routes)
        self.recheck(gh, {"GITHUB_ACTIONS": "true", "GITHUB_REPOSITORY": "someone/else"})
        self.assertEqual(gh.posts, [])

    def test_rerun_fires_in_actions_on_own_repo(self):
        gh = FakeGitHub(self.routes)
        rc, out = self.recheck(gh, {"GITHUB_ACTIONS": "true", "GITHUB_REPOSITORY": REPO})
        self.assertEqual(rc, 0, out)
        self.assertEqual(gh.posts, [f"/repos/{REPO}/actions/runs/555/rerun-failed-jobs"])

    def test_no_rerun_while_still_blocked(self):
        self.routes.update(route(pr(169)))  # dependency back to open
        gh = FakeGitHub(self.routes)
        rc, out = self.recheck(gh, {"GITHUB_ACTIONS": "true", "GITHUB_REPOSITORY": REPO})
        self.assertEqual(gh.posts, [])
        self.assertIn("#200: still blocked", out)


if __name__ == "__main__":
    unittest.main()
