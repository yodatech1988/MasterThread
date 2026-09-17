"""Unit tests for tools/check_agent_sync.py -- run with `python -m unittest` from the repo root,
or `python -m unittest discover -s tools/tests`.

live_vs_mirror and compare_across_repos are pure functions over filename->content dicts, so most
of this needs no filesystem or git at all. `_read_md_dir` gets a light check against a real temp
directory since it's the one function that touches disk.
"""
import pathlib
import sys
import tempfile
import unittest

TOOLS_DIR = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(TOOLS_DIR))

import check_agent_sync as sync  # noqa: E402


class LiveVsMirrorTests(unittest.TestCase):
    def test_in_sync_reports_nothing(self):
        files = {"a.md": "content a", "b.md": "content b"}
        local_only, repo_only, differs = sync.live_vs_mirror(files, dict(files))
        self.assertEqual(local_only, [])
        self.assertEqual(repo_only, [])
        self.assertEqual(differs, [])

    def test_local_only_file(self):
        live = {"a.md": "x", "only-local.md": "y"}
        mirror = {"a.md": "x"}
        local_only, repo_only, differs = sync.live_vs_mirror(live, mirror)
        self.assertEqual(local_only, ["only-local.md"])
        self.assertEqual(repo_only, [])
        self.assertEqual(differs, [])

    def test_repo_only_file(self):
        live = {"a.md": "x"}
        mirror = {"a.md": "x", "only-repo.md": "y"}
        local_only, repo_only, differs = sync.live_vs_mirror(live, mirror)
        self.assertEqual(local_only, [])
        self.assertEqual(repo_only, ["only-repo.md"])
        self.assertEqual(differs, [])

    def test_content_differs(self):
        live = {"a.md": "live version"}
        mirror = {"a.md": "mirror version"}
        local_only, repo_only, differs = sync.live_vs_mirror(live, mirror)
        self.assertEqual(differs, ["a.md"])

    def test_crlf_only_difference_is_ignored(self):
        live = {"a.md": "line1\r\nline2\r\n"}
        mirror = {"a.md": "line1\nline2\n"}
        local_only, repo_only, differs = sync.live_vs_mirror(live, mirror)
        self.assertEqual(differs, [])

    def test_all_three_lists_at_once(self):
        live = {"shared.md": "same", "local-only.md": "z", "changed.md": "live text"}
        mirror = {"shared.md": "same", "repo-only.md": "z", "changed.md": "mirror text"}
        local_only, repo_only, differs = sync.live_vs_mirror(live, mirror)
        self.assertEqual(local_only, ["local-only.md"])
        self.assertEqual(repo_only, ["repo-only.md"])
        self.assertEqual(differs, ["changed.md"])


class ReadMdDirTests(unittest.TestCase):
    def test_reads_only_md_files_non_recursive(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "keep.md").write_text("keep me", encoding="utf-8")
            (root / "ignore.txt").write_text("not markdown", encoding="utf-8")
            sub = root / "subdir"
            sub.mkdir()
            (sub / "nested.md").write_text("should not be picked up", encoding="utf-8")

            files = sync._read_md_dir(root)
            self.assertEqual(files, {"keep.md": "keep me"})

    def test_missing_directory_returns_empty(self):
        files = sync._read_md_dir(pathlib.Path("/does/not/exist/at/all"))
        self.assertEqual(files, {})


class CompareAcrossReposTests(unittest.TestCase):
    def test_identical_content_across_repos_is_not_reported(self):
        repo_contents = {
            "repo-a": {"shared.md": "same text"},
            "repo-b": {"shared.md": "same text"},
        }
        self.assertEqual(sync.compare_across_repos(repo_contents), {})

    def test_differing_content_across_repos_is_reported(self):
        repo_contents = {
            "repo-a": {"shared.md": "version A"},
            "repo-b": {"shared.md": "version B"},
            "repo-c": {"shared.md": "version A"},
        }
        differing = sync.compare_across_repos(repo_contents)
        self.assertEqual(set(differing), {"shared.md"})
        self.assertEqual(differing["shared.md"], ["repo-a", "repo-b", "repo-c"])

    def test_file_in_only_one_repo_is_not_reported(self):
        repo_contents = {
            "repo-a": {"solo.md": "only here"},
            "repo-b": {"other.md": "unrelated"},
        }
        self.assertEqual(sync.compare_across_repos(repo_contents), {})

    def test_crlf_only_difference_is_ignored(self):
        repo_contents = {
            "repo-a": {"shared.md": "line1\r\nline2\r\n"},
            "repo-b": {"shared.md": "line1\nline2\n"},
        }
        self.assertEqual(sync.compare_across_repos(repo_contents), {})


class DiscoverRepoClonesTests(unittest.TestCase):
    def test_skips_underscore_and_core_tmp_prefixed_dirs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            for name in ("real-repo", "_wt-worktree", "core-tmp-scratch", "also-real"):
                d = root / name
                d.mkdir()
                (d / ".git").mkdir()
            # A directory with no .git at all must also be skipped.
            (root / "not-a-repo").mkdir()

            clones = sync.discover_repo_clones(root)
            names = [name for name, _path in clones]
            self.assertEqual(names, ["also-real", "real-repo"])


if __name__ == "__main__":
    unittest.main()
