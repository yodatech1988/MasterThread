"""Smoke and unit tests for tools/decision-queue/dq_monitor.py -- run with
`python -m unittest discover -s tools/tests` from the repo root.

The fixtures under tools/tests/fixtures/dq_monitor/ are five hand-made cards (one per audited
shape); no artifact or network access is involved."""
import datetime as dt
import importlib.util
import io
import pathlib
import tempfile
import unittest
from contextlib import redirect_stdout

HERE = pathlib.Path(__file__).resolve().parent
FIXTURES = HERE / "fixtures" / "dq_monitor"
_spec = importlib.util.spec_from_file_location(
    "dq_monitor", HERE.parent / "decision-queue" / "dq_monitor.py")
mon = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mon)

NOW = dt.datetime(2026, 9, 19, 12, 0, 0, tzinfo=dt.timezone.utc)


class StampDiscriminatorTests(unittest.TestCase):
    def test_millisecond_stamp_is_page_written(self):
        self.assertFalse(mon.is_session_written(
            {"status": "resolved", "resolvedAt": "2026-09-19T07:05:00.260Z"}))

    def test_whole_second_stamp_is_session_written(self):
        self.assertTrue(mon.is_session_written(
            {"status": "resolved", "resolvedAt": "2026-09-19T07:30:00Z"}))

    def test_open_or_unstamped_card_is_never_counted(self):
        self.assertFalse(mon.is_session_written(
            {"status": "open", "resolvedAt": "2026-09-19T07:30:00Z"}))
        self.assertFalse(mon.is_session_written({"status": "resolved"}))


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.rows = mon.load_cards(str(FIXTURES))
        self.text = "\n".join(mon.report(self.rows, NOW))

    def test_loads_all_fixtures_and_unwraps_data(self):
        self.assertEqual(len(self.rows), 5)
        by_id = {r["_id"]: r for r in self.rows}
        self.assertEqual(by_id["resolved-by-session"]["status"], "resolved")

    def test_totals(self):
        self.assertIn("total 5 open 3 resolved 2", self.text)

    def test_oldest_owner_required_first(self):
        a = self.text.split("[A]")[1].split("[B]")[0]
        self.assertLess(a.index("open-action-unchecked"), a.index("open-decision"))
        self.assertNotIn("open-no-kind-no-rec", a)  # not ownerRequired

    def test_claimed_unverified_listed(self):
        self.assertIn("open-action-unchecked | claimComment='I did it'", self.text)

    def test_follow_up_pending_listed(self):
        self.assertIn("resolved-by-session | still to click", self.text)

    def test_session_written_count_is_one_of_two(self):
        self.assertIn("count 1 of 2", self.text)

    def test_hygiene_flags(self):
        e = self.text.split("[E]")[1]
        self.assertIn("no kind: 1 | options w/o recommendedOption: 1", e)
        self.assertIn("['open-action-unchecked']", e)
        self.assertIn("resolvedAt < createdAt (stamp drift): 0", e)


class StampDriftTests(unittest.TestCase):
    def test_resolved_before_created_is_counted(self):
        rows = [{"_id": "x", "status": "resolved", "createdAt": "2026-09-19T07:00:00.000Z",
                 "resolvedAt": "2026-09-19T06:00:00.000Z"}]
        self.assertIn("resolvedAt < createdAt (stamp drift): 1", "\n".join(mon.report(rows, NOW)))


class ReadOnlyAndCliTests(unittest.TestCase):
    def test_main_prints_and_returns_zero_without_touching_input(self):
        before = {p.name: p.read_bytes() for p in FIXTURES.glob("*.json")}
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = mon.main(["dq_monitor.py", str(FIXTURES)])
        self.assertEqual(rc, 0)
        self.assertIn("[D] session-written", buf.getvalue())
        self.assertEqual(before, {p.name: p.read_bytes() for p in FIXTURES.glob("*.json")})

    def test_bad_arguments_return_usage_error(self):
        with redirect_stdout(io.StringIO()):
            self.assertEqual(mon.main(["dq_monitor.py"]), 2)
            with tempfile.TemporaryDirectory() as d:
                self.assertEqual(mon.main(["dq_monitor.py", d + "/nope"]), 2)


if __name__ == "__main__":
    unittest.main()
