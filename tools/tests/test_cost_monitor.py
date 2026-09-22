"""Tests for tools/cost-monitor/cost_monitor.py -- run with
`python -m unittest discover -s tools/tests` from the repo root.

Everything here is FAKE: invented session ids, invented model rates (verified_on 2000-01-01), invented
message text. Nothing reads the real ~/.claude/projects folder, the real ops-policies checkout, the
real %APPDATA%\\AEGIS\\cost state directory, or the network. Every run of the tool goes through
--state-dir / --projects-dir / --rates-file seams pointing at a temporary directory."""
import ast
import datetime as dt
import importlib.util
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

# The rates loader needs PyYAML. Without it the tool exits 3 by design (README), so every test that
# runs the tool end to end cannot pass; skip those cleanly instead of failing (CI job `check` installs
# no PyYAML). The tests that never reach the rates loader still run.
HAVE_YAML = importlib.util.find_spec("yaml") is not None
requires_yaml = unittest.skipUnless(HAVE_YAML, "PyYAML is not installed (pip install pyyaml)")

HERE = pathlib.Path(__file__).resolve().parent
TOOL = HERE.parent / "cost-monitor" / "cost_monitor.py"
_spec = importlib.util.spec_from_file_location("cost_monitor", TOOL)
cm = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cm)

NOW = dt.datetime(2026, 9, 20, 12, 0, 0, tzinfo=dt.timezone.utc)
SID1 = "aaaaaaaa-0000-4000-8000-000000000001"
SID2 = "bbbbbbbb-0000-4000-8000-000000000002"
TEXT_SENTINEL = "FAKE-MESSAGE-TEXT-THAT-MUST-NEVER-BE-PRINTED"
KEY_SENTINEL = "sk-ant-FAKE-VALUE-THAT-MUST-NEVER-BE-PRINTED"

RATES_YAML = """
version: 1
verification_record: "FAKE fixture record"
models:
  haiku:  {id: claude-haiku-4-5, display_name: Fake Haiku, in: 1.00, out: 5.00, verified_on: "2000-01-01"}
  sonnet: {id: claude-sonnet-5, display_name: Fake Sonnet, in: 2.00, out: 10.00, verified_on: "2000-01-01"}
  opus:   {id: claude-opus-5, display_name: Fake Opus, in: 5.00, out: 25.00, verified_on: "2000-01-01"}
  fable:  {id: claude-fable-5-1, display_name: Fake Fable, in: 10.00, out: 50.00, verified_on: "2000-01-01", cache_read_factor_override: 0.025}
"""


def config(**thresholds):
    th = {"status": "TEST", "opus_whatif_alert_usd_per_day": 1000, "opus_whatif_stop_usd_per_day": 2000,
          "opus_share_alert_fraction": 0.5, "opus_share_min_day_usd": 1000000,
          "session_output_alert_tokens": 10000000}
    th.update(thresholds)
    return {"thresholds": th, "cache_multipliers": {"status": "TEST", "read": 0.1, "write_5m": 1.25, "write_1h": 2.0},
            "alert_on_api_key": True, "ledger_min_interval_minutes": 0}


def assistant(mid, model, out, day="2026-09-20", inp=0, cr=0, cw=0, text=TEXT_SENTINEL):
    return json.dumps({"type": "assistant", "timestamp": day + "T01:00:00.000Z",
                       "message": {"id": mid, "model": model, "content": [{"type": "text", "text": text}],
                                   "usage": {"input_tokens": inp, "output_tokens": out,
                                             "cache_read_input_tokens": cr, "cache_creation_input_tokens": cw}}})


def title(sid, text):
    return json.dumps({"type": "ai-title", "aiTitle": text, "sessionId": sid})


class Env:
    """A throwaway projects dir, state dir, rates file and config."""

    def __init__(self, cfg=None, rates=RATES_YAML):
        self._tmp = tempfile.TemporaryDirectory()
        root = pathlib.Path(self._tmp.name)
        self.projects, self.state, self.reports = root / "projects", root / "state", root / "reports"
        self.projects.mkdir()
        self.reports.mkdir()
        self.rates, self.config = root / "models.yaml", root / "config.json"
        self.rates.write_text(rates, encoding="utf-8")
        self.config.write_text(json.dumps(cfg or config()), encoding="utf-8")

    def close(self):
        self._tmp.cleanup()

    def session(self, sid, lines, subagent=None):
        path = (self.projects / sid / "subagents" / (subagent + ".jsonl")) if subagent else (self.projects / (sid + ".jsonl"))
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "a", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(lines) + "\n")
        os.utime(path, (NOW.timestamp(), NOW.timestamp()))
        return path

    def run(self, *extra, registry=lambda name: False, api_env=None, now=None):
        out, err = io.StringIO(), io.StringIO()
        argv = ["--projects-dir", str(self.projects), "--state-dir", str(self.state), "--rates-file", str(self.rates),
                "--config", str(self.config), "--reports-dir", str(self.reports)] + list(extra)
        env = {"ANTHROPIC_API_KEY": KEY_SENTINEL} if api_env else {}
        with mock.patch.dict(os.environ, env, clear=False):
            if not api_env:
                os.environ.pop("ANTHROPIC_API_KEY", None)
            code = cm.main(argv, now=now or NOW, out=out, err=err, registry=registry)
        return code, out.getvalue(), err.getvalue()

    def headless_report(self, agent, stamp, envelope, checked_at="2026-09-20T01:00:00Z", suffix=""):
        path = self.reports / ("%s.%s%s.json" % (agent, stamp, suffix))
        path.write_text(json.dumps({"envelope": envelope, "checkedAt": checked_at, "command": "claude -p ..."}),
                        encoding="utf-8")
        return path

    def headless_ndjson_report(self, agent, stamp, text, suffix="", mtime=None):
        """Writes a raw multi-line NDJSON transcript (no {envelope, checkedAt, command} wrapper) --
        what Invoke-ReadOnlyAgent.ps1 writes when called without -Report."""
        path = self.reports / ("%s.%s%s.json" % (agent, stamp, suffix))
        path.write_text(text, encoding="utf-8", newline="\n")
        if mtime is not None:
            os.utime(path, (mtime.timestamp(), mtime.timestamp()))
        return path

    def headless_bytes_report(self, agent, stamp, raw_bytes, suffix=""):
        """Writes arbitrary raw bytes as a report file -- for non-UTF-8 content (a stray invalid
        byte, or a UTF-16LE-with-BOM file, e.g. what PowerShell 5.1's `>` writes)."""
        path = self.reports / ("%s.%s%s.json" % (agent, stamp, suffix))
        path.write_bytes(raw_bytes)
        return path

    def status(self):
        return json.loads((self.state / "status.json").read_text(encoding="utf-8"))

    def ledger_lines(self, day="2026-09-20"):
        path = self.state / ("ledger-%s.jsonl" % day)
        return path.read_text(encoding="utf-8").splitlines() if path.exists() else []


class EnvTestCase(unittest.TestCase):
    def setUp(self):
        self.env = Env()
        self.addCleanup(self.env.close)


# ------------------------------------------------------------------ counting
@requires_yaml
class DedupeTests(EnvTestCase):
    def test_streamed_response_counts_once_with_its_final_output(self):
        # The real shape: one response, three lines, output_tokens 7, 7, 920.
        self.env.session(SID1, [assistant("msg_1", "claude-opus-5", 7, inp=10, cw=16851),
                                assistant("msg_1", "claude-opus-5", 7, inp=10, cw=16851),
                                assistant("msg_1", "claude-opus-5", 920, inp=10, cw=16851),
                                assistant("msg_2", "claude-opus-5", 100, inp=5)])
        code, out, _ = self.env.run()
        counts = self.env.status()["by_model"]["claude-opus-5"]["counts"]
        self.assertEqual(counts["out"], 1020, "920 + 100, not the first-seen 7 + 100")
        self.assertEqual(counts["msgs"], 2)
        self.assertEqual(counts["in"], 15, "input is counted once per response, not once per line")
        self.assertEqual(counts["cache_write"], 16851)

    def test_order_of_the_lines_does_not_matter(self):
        self.env.session(SID1, [assistant("msg_1", "claude-opus-5", 920), assistant("msg_1", "claude-opus-5", 7)])
        self.env.run()
        self.assertEqual(self.env.status()["by_model"]["claude-opus-5"]["counts"]["out"], 920)

    def test_synthetic_responses_are_skipped(self):
        self.env.session(SID1, [assistant("msg_s", "<synthetic>", 500), assistant("msg_1", "claude-opus-5", 5)])
        self.env.run()
        self.assertNotIn("<synthetic>", self.env.status()["by_model"])

    def test_lines_without_usage_or_with_bad_json_are_ignored(self):
        self.env.session(SID1, ["not json at all", json.dumps({"type": "user", "message": {"content": "hi"}}),
                                assistant("msg_1", "claude-opus-5", 5)])
        code, _, _ = self.env.run()
        self.assertEqual(self.env.status()["by_model"]["claude-opus-5"]["counts"]["msgs"], 1)

    def test_window_excludes_days_before_it(self):
        self.env.session(SID1, [assistant("msg_old", "claude-opus-5", 50, day="2026-09-17"),
                                assistant("msg_new", "claude-opus-5", 60, day="2026-09-20")])
        self.env.run("--days", "2")
        self.assertEqual(self.env.status()["by_model"]["claude-opus-5"]["counts"]["out"], 60)
        self.assertEqual(self.env.ledger_lines("2026-09-17"), [])


# ------------------------------------------------------------------ pricing
@requires_yaml
class PricingTests(EnvTestCase):
    def test_opus_dollars_are_exact(self):
        # base = 1e6*5 + 1e5*25 + 2e6*5*0.1 = 8.5e6 ; write low +5e5*5*1.25, high +5e5*5*2.0
        self.env.session(SID1, [assistant("msg_1", "claude-opus-5", 100000, inp=1000000, cr=2000000, cw=500000)])
        self.env.run()
        m = self.env.status()["by_model"]["claude-opus-5"]
        self.assertAlmostEqual(m["usd_low"], 11.625)
        self.assertAlmostEqual(m["usd_high"], 13.5)
        self.assertAlmostEqual(m["usd_io"], 7.5)

    def test_a_models_own_cache_read_override_wins(self):
        # Fable: 1e6*10 in + 4e6 cache reads at 10*0.025 = 10 + 1 = $11, not 10 + 4.
        self.env.session(SID1, [assistant("msg_1", "claude-fable-5-1", 0, inp=1000000, cr=4000000)])
        self.env.run()
        self.assertAlmostEqual(self.env.status()["by_model"]["claude-fable-5-1"]["usd_low"], 11.0)

    def test_dated_snapshot_id_is_priced_and_labelled(self):
        self.env.session(SID1, [assistant("msg_1", "claude-haiku-4-5-20251001", 0, inp=1000000)])
        code, out, _ = self.env.run()
        self.assertEqual(self.env.status()["by_model"]["claude-haiku-4-5-20251001"]["match"], "dated-suffix")
        self.assertIn("(dated-suffix match)", out)
        self.assertEqual(code, 0)

    def test_unknown_model_is_unpriced_never_guessed(self):
        self.env.session(SID1, [assistant("msg_1", "claude-mystery-9", 1000, inp=1000000),
                                assistant("msg_2", "claude-opus-5", 0, inp=1000000)])
        code, out, _ = self.env.run()
        st = self.env.status()
        self.assertFalse(st["by_model"]["claude-mystery-9"]["priced"])
        self.assertIsNone(st["by_model"]["claude-mystery-9"]["usd_high"])
        self.assertAlmostEqual(st["totals"]["usd_high"], 5.0, msg="unknown model adds nothing to the dollar total")
        self.assertIn("UNPRICED", out)
        self.assertEqual(code, 3)

    def test_near_miss_ids_are_not_matched(self):
        for near in ("claude-opus-5-preview", "claude-opus-50", "claude-opus-5-2025", "claude-opus-5-20251001x"):
            self.assertEqual(cm.match_model(near, {"claude-opus-5": {"key": "opus"}}), (None, None), near)
        self.assertEqual(cm.match_model("claude-opus-5-20251001", {"claude-opus-5": {"key": "opus"}})[1], "dated-suffix")

    def test_report_quotes_the_rates_source_and_verification_date(self):
        self.env.session(SID1, [assistant("msg_1", "claude-opus-5", 5)])
        _, out, _ = self.env.run()
        self.assertIn("file:" + str(self.env.rates), out)
        self.assertIn("2000-01-01", out)
        self.assertIn("FAKE fixture record", out)
        self.assertIn("WHAT-IF", out)
        self.assertIn("CONFIRMED", cm.load_config(str(TOOL.parent / "config.json"))["cache_multipliers"]["status"])


def assistant_ttl(mid, model, out, cw_5m=0, cw_1h=0, day="2026-09-20", inp=0, cr=0, text=TEXT_SENTINEL):
    """A response whose usage carries the TTL split (usage.cache_creation.ephemeral_5m/1h_input_tokens),
    the real API shape per docs/FABLE_AGENT_SUBAGENT_PLAN.md sec 11's build-time envelope example."""
    return json.dumps({"type": "assistant", "timestamp": day + "T01:00:00.000Z",
                       "message": {"id": mid, "model": model, "content": [{"type": "text", "text": text}],
                                   "usage": {"input_tokens": inp, "output_tokens": out,
                                             "cache_read_input_tokens": cr,
                                             "cache_creation_input_tokens": cw_5m + cw_1h,
                                             "cache_creation": {"ephemeral_5m_input_tokens": cw_5m,
                                                                "ephemeral_1h_input_tokens": cw_1h}}}})


@requires_yaml
class TTLCachePricingTests(EnvTestCase):
    """F8: cache-write pricing is TTL-aware. A response with the real TTL split prices exactly at the
    confirmed per-TTL rate; a response with only the aggregate (TTL unknown) keeps the original
    low(5m)-high(1h) range convention, so the range now means 'which TTL was this', not 'what is the
    rate' -- write_5m=1.25x, write_1h=2.0x are both confirmed rates (config.json), not assumptions."""

    def test_a_1h_ttl_write_is_priced_exactly_not_as_a_range(self):
        # 1e6 in @ $5 + 5e5 cache-write @ 1h(2.0x) * $5 = 5e6 + 5e6 = $10, low == high.
        self.env.session(SID1, [assistant_ttl("msg_1", "claude-opus-5", 0, cw_1h=500000, inp=1000000)])
        self.env.run()
        m = self.env.status()["by_model"]["claude-opus-5"]
        self.assertAlmostEqual(m["usd_low"], 10.0)
        self.assertAlmostEqual(m["usd_high"], 10.0, msg="a confirmed 1h-TTL write has no uncertainty left")

    def test_a_5m_ttl_write_is_priced_exactly_at_the_cheaper_rate(self):
        # 5e5 cache-write @ 5m(1.25x) * $5 = $3.125, plus $5 input.
        self.env.session(SID1, [assistant_ttl("msg_1", "claude-opus-5", 0, cw_5m=500000, inp=1000000)])
        self.env.run()
        m = self.env.status()["by_model"]["claude-opus-5"]
        self.assertAlmostEqual(m["usd_low"], 8.125)
        self.assertAlmostEqual(m["usd_high"], 8.125)

    def test_a_mixed_5m_and_1h_response_prices_each_bucket_at_its_own_rate(self):
        self.env.session(SID1, [assistant_ttl("msg_1", "claude-opus-5", 0, cw_5m=200000, cw_1h=300000, inp=0)])
        self.env.run()
        m = self.env.status()["by_model"]["claude-opus-5"]
        expected = (200000 * 5 * 1.25 + 300000 * 5 * 2.0) / 1e6
        self.assertAlmostEqual(m["usd_low"], expected)
        self.assertAlmostEqual(m["usd_high"], expected)

    def test_aggregate_only_cache_write_with_no_ttl_split_still_ranges(self):
        # Old transcript shape (no usage.cache_creation object): unknown TTL, same low-high range as before.
        self.env.session(SID1, [assistant("msg_1", "claude-opus-5", 0, inp=0, cw=500000)])
        self.env.run()
        m = self.env.status()["by_model"]["claude-opus-5"]
        self.assertAlmostEqual(m["usd_low"], 500000 * 5 * 1.25 / 1e6)
        self.assertAlmostEqual(m["usd_high"], 500000 * 5 * 2.0 / 1e6)
        self.assertLess(m["usd_low"], m["usd_high"], "unknown TTL is still a genuine range")

    def test_shipped_config_confirms_both_ttl_rates(self):
        cfg = cm.load_config(str(TOOL.parent / "config.json"))["cache_multipliers"]
        self.assertEqual(cfg["write_5m"], 1.25)
        self.assertEqual(cfg["write_1h"], 2.0)
        self.assertIn("CONFIRMED", cfg["status"])


@requires_yaml
class RatesSourceTests(unittest.TestCase):
    def test_default_source_is_origin_main_not_the_working_tree(self):
        with tempfile.TemporaryDirectory() as repo:
            def git(*a):
                subprocess.run(["git", "-C", repo, "-c", "user.name=t", "-c", "user.email=t@example.invalid",
                                "-c", "core.autocrlf=false"] + list(a), check=True, capture_output=True)
            try:
                git("init", "-q")
            except (OSError, subprocess.CalledProcessError):
                self.skipTest("git unavailable")
            path = pathlib.Path(repo, "routing", "models.yaml")
            path.parent.mkdir()
            path.write_text(RATES_YAML, encoding="utf-8")
            git("add", "-A")
            git("commit", "-q", "-m", "fake")
            git("update-ref", "refs/remotes/origin/main", "HEAD")
            path.write_text(RATES_YAML.replace("in: 5.00, out: 25.00", "in: 999.00, out: 999.00"), encoding="utf-8")
            rates, meta = cm.load_rates(None, repo)
            self.assertEqual(rates["claude-opus-5"]["in"], 5.0, "must read the merged file, not the edited working tree")
            self.assertIn("origin/main:routing/models.yaml", meta["source"])

    def test_missing_ref_is_an_error_not_a_guess(self):
        with tempfile.TemporaryDirectory() as repo:
            self.assertRaises(cm.RatesError, cm.load_rates, None, repo)


# ------------------------------------------------------------------ labels and rows
@requires_yaml
class RowTests(EnvTestCase):
    def test_sessions_and_subagents_are_separate_rows_labelled_by_title(self):
        self.env.session(SID1, [title(SID1, "Fake planning session"), assistant("msg_1", "claude-opus-5", 10)])
        self.env.session(SID1, [assistant("msg_2", "claude-sonnet-5", 20)], subagent="agent-fake0001")
        self.env.session(SID2, [assistant("msg_3", "claude-sonnet-5", 30)])
        code, out, _ = self.env.run()
        rows = json.loads(self.env.ledger_lines()[0])["sessions"]
        by = {(r["kind"], r["id"], r["agent"]): r for r in rows}
        self.assertEqual(by[("session", SID1, "")]["label"], "Fake planning session")
        self.assertEqual(by[("subagent", SID1, "agent-fake0001")]["label"], "Fake planning session / agent-fake0001")
        self.assertEqual(by[("session", SID2, "")]["label"], SID2[:8], "no title falls back to the short id")
        self.assertEqual(len(rows), 3)

    def test_a_session_that_switches_model_gets_one_row_per_model(self):
        self.env.session(SID1, [assistant("msg_1", "claude-opus-5", 10), assistant("msg_2", "claude-sonnet-5", 20)])
        self.env.run()
        rows = json.loads(self.env.ledger_lines()[0])["sessions"]
        self.assertEqual(sorted(r["model"] for r in rows), ["claude-opus-5", "claude-sonnet-5"])

    def test_labels_are_one_printable_ascii_line(self):
        self.assertEqual(cm.safe_label("a" + chr(10) + "b" + chr(233) + "c"), "a b c")
        self.assertEqual(len(cm.safe_label("x" * 500)), 60)


# ------------------------------------------------------------------ privacy
@requires_yaml
class PrivacyTests(EnvTestCase):
    def test_message_text_never_reaches_stdout_stderr_status_or_ledger(self):
        self.env.session(SID1, [title(SID1, "Fake title"), assistant("msg_1", "claude-opus-5", 10, text=TEXT_SENTINEL)])
        self.env.session(SID1, [assistant("msg_2", "claude-sonnet-5", 10, text=TEXT_SENTINEL)], subagent="agent-fake0001")
        code, out, err = self.env.run()
        blobs = [out, err, (self.env.state / "status.json").read_text(encoding="utf-8")] + self.env.ledger_lines()
        for blob in blobs:
            self.assertNotIn(TEXT_SENTINEL, blob)

    def test_api_key_is_reported_by_presence_and_the_value_never_appears(self):
        self.env.session(SID1, [assistant("msg_1", "claude-opus-5", 5)])
        code, out, err = self.env.run(api_env=True)
        st = (self.env.state / "status.json").read_text(encoding="utf-8")
        self.assertEqual(code, 1)
        self.assertIn("process=SET", out)
        for blob in (out, err, st):
            self.assertNotIn(KEY_SENTINEL, blob)
        self.assertTrue(json.loads(st)["api_key_present"]["process"])

    def test_api_key_in_user_or_machine_environment_alerts(self):
        self.env.session(SID1, [assistant("msg_1", "claude-opus-5", 5)])
        code, out, _ = self.env.run(registry=lambda name: name == "machine")
        self.assertEqual(code, 1)
        self.assertIn("machine=SET", out)
        self.assertIn("user=not set", out)

    def test_api_key_that_cannot_be_checked_is_reported_not_alerted(self):
        self.env.session(SID1, [assistant("msg_1", "claude-opus-5", 5)])
        code, out, _ = self.env.run(registry=lambda name: None)
        self.assertEqual(code, 0)
        self.assertIn("could not check", out)

    def test_api_key_absent_is_clean(self):
        self.env.session(SID1, [assistant("msg_1", "claude-opus-5", 5)])
        code, out, _ = self.env.run()
        self.assertEqual(code, 0)
        self.assertIn("process=not set, user=not set, machine=not set", out)


class RegistryProbeTests(unittest.TestCase):
    """The API key check must enumerate value NAMES and never call QueryValueEx."""

    def fake_winreg(self, names, no_more=True):
        fake = mock.MagicMock()
        fake.HKEY_CURRENT_USER, fake.HKEY_LOCAL_MACHINE = object(), object()
        fake.OpenKey.return_value.__enter__.return_value = "key"
        fake.QueryValueEx.side_effect = AssertionError("QueryValueEx must not be called")

        def enum(key, i):
            if i < len(names):
                return (names[i], "SECRET-VALUE-NEVER-SEEN", 1)
            exc = OSError("no more data")
            exc.winerror = 259
            raise exc
        fake.EnumValue.side_effect = enum
        return fake

    def test_finds_the_name_without_querying_the_value(self):
        with mock.patch.dict(sys.modules, {"winreg": self.fake_winreg(["Path", "anthropic_api_key"])}):
            self.assertIs(cm._registry_has_key("user"), True)

    def test_absent_name_is_false_not_could_not_check(self):
        with mock.patch.dict(sys.modules, {"winreg": self.fake_winreg(["Path", "TEMP"])}):
            self.assertIs(cm._registry_has_key("machine"), False)


class DefaultProjectsTests(unittest.TestCase):
    def test_default_slug_is_derived_from_the_checkout_location_not_hardcoded(self):
        source = pathlib.Path(TOOL).read_text(encoding="utf-8")
        self.assertNotIn("c--Users-yoda", source)
        workspace = str(pathlib.Path(TOOL).resolve().parents[3])
        self.assertEqual(os.path.basename(cm.default_projects_dir()), cm.project_slug(workspace))

    def test_slug_rules_match_claude_codes_folder_names(self):
        self.assertEqual(cm.project_slug("C:" + chr(92) + "Users" + chr(92) + "yoda_" + chr(92) + "GitHub"), "c--Users-yoda--GitHub")
        self.assertEqual(cm.project_slug("/home/a.b/work"), "-home-a-b-work")


# ------------------------------------------------------------------ thresholds and exit codes
@requires_yaml
class ThresholdTests(unittest.TestCase):
    def run_with(self, lines, **thresholds):
        env = Env(config(**thresholds))
        self.addCleanup(env.close)
        env.session(SID1, lines)
        code, out, err = env.run()
        return env, code, out

    def test_under_every_threshold_is_exit_0(self):
        env, code, _ = self.run_with([assistant("m1", "claude-opus-5", 0, inp=1000000)],
                                     opus_whatif_alert_usd_per_day=6, opus_whatif_stop_usd_per_day=9)
        self.assertEqual(code, 0)
        self.assertEqual(env.status()["state"], "ok")

    def test_opus_alert_threshold_is_exit_1(self):
        env, code, out = self.run_with([assistant("m1", "claude-opus-5", 0, inp=1000000)],
                                       opus_whatif_alert_usd_per_day=4, opus_whatif_stop_usd_per_day=8)
        self.assertEqual(code, 1)
        self.assertEqual([b["kind"] for b in env.status()["breaches"]], ["opus_whatif_alert"])
        self.assertIn("[ALERT]", out)

    def test_opus_stop_threshold_is_exit_2(self):
        env, code, out = self.run_with([assistant("m1", "claude-opus-5", 0, inp=2000000)],
                                       opus_whatif_alert_usd_per_day=4, opus_whatif_stop_usd_per_day=8)
        self.assertEqual(code, 2)
        self.assertEqual(env.status()["state"], "stop-and-ask")
        self.assertEqual([b["kind"] for b in env.status()["breaches"]], ["opus_whatif_stop"])

    def test_alerts_use_the_high_cache_write_estimate(self):
        # $5 of input plus 1e6 cache-write tokens: low $11.25, high $15. A limit of $12 only trips on high.
        env, code, _ = self.run_with([assistant("m1", "claude-opus-5", 0, inp=1000000, cw=1000000)],
                                     opus_whatif_alert_usd_per_day=12, opus_whatif_stop_usd_per_day=90)
        self.assertEqual(code, 1)

    def test_one_sessions_output_spike_alerts(self):
        env, code, out = self.run_with([assistant("m1", "claude-sonnet-5", 400000)], session_output_alert_tokens=300000)
        self.assertEqual(code, 1)
        self.assertEqual([b["kind"] for b in env.status()["breaches"]], ["session_output_spike"])

    def test_opus_share_of_the_day_alerts(self):
        # Opus $5, Sonnet $2: Opus is 71%.
        env, code, _ = self.run_with([assistant("m1", "claude-opus-5", 0, inp=1000000), assistant("m2", "claude-sonnet-5", 0, inp=1000000)],
                                     opus_share_alert_fraction=0.5, opus_share_min_day_usd=1)
        self.assertEqual(code, 1)
        self.assertEqual([b["kind"] for b in env.status()["breaches"]], ["opus_share"])
        self.assertAlmostEqual(env.status()["totals"]["opus_share"], 5 / 7)

    def test_opus_share_is_ignored_on_a_tiny_day(self):
        env, code, _ = self.run_with([assistant("m1", "claude-opus-5", 0, inp=1000000)],
                                     opus_share_alert_fraction=0.5, opus_share_min_day_usd=100)
        self.assertEqual(code, 0)

    def test_a_breach_on_an_earlier_day_does_not_change_todays_exit(self):
        env = Env(config(opus_whatif_stop_usd_per_day=8, opus_whatif_alert_usd_per_day=4))
        self.addCleanup(env.close)
        env.session(SID1, [assistant("m1", "claude-opus-5", 0, inp=9000000, day="2026-09-18"),
                           assistant("m2", "claude-opus-5", 0, inp=1, day="2026-09-20")])
        code, _, _ = env.run()
        self.assertEqual(code, 0)
        code, _, _ = env.run("--day", "2026-09-18")
        self.assertEqual(code, 2)

    def test_precedence_stop_over_alert_over_unknown(self):
        env, code, _ = self.run_with([assistant("m1", "claude-opus-5", 0, inp=2000000), assistant("m2", "claude-mystery-9", 5)],
                                     opus_whatif_alert_usd_per_day=4, opus_whatif_stop_usd_per_day=8)
        self.assertEqual(code, 2)
        env, code, _ = self.run_with([assistant("m1", "claude-opus-5", 0, inp=1000000), assistant("m2", "claude-mystery-9", 5)],
                                     opus_whatif_alert_usd_per_day=4, opus_whatif_stop_usd_per_day=8)
        self.assertEqual(code, 1)
        self.assertEqual(sorted(b["kind"] for b in env.status()["breaches"]), ["opus_whatif_alert", "unpriced_model"])

    def test_defaults_ship_marked_as_pending_owner_approval(self):
        shipped = cm.load_config(str(TOOL.parent / "config.json"))
        self.assertIn("pending owner approval", shipped["thresholds"]["status"])
        self.assertEqual(shipped["thresholds"]["opus_whatif_alert_usd_per_day"], 50)
        self.assertEqual(shipped["thresholds"]["opus_whatif_stop_usd_per_day"], 100)
        # F8 (2026-09-22): cache write rates are now CONFIRMED per-TTL (plan secs 1b/11), not an
        # ASSUMED range -- only the read ratio is still unconfirmed against a price page.
        self.assertIn("CONFIRMED", shipped["cache_multipliers"]["status"])
        self.assertEqual(shipped["cache_multipliers"]["write_5m"], 1.25)
        self.assertEqual(shipped["cache_multipliers"]["write_1h"], 2.0)


@requires_yaml
class CouldNotReadTests(EnvTestCase):
    def test_missing_transcripts_dir_is_exit_3(self):
        self.env.projects.rmdir()
        code, out, err = self.env.run()
        self.assertEqual(code, 3)
        self.assertIn("not found", err)
        self.assertFalse(self.env.state.exists(), "a failed read writes nothing")

    def test_missing_or_malformed_rates_is_exit_3(self):
        self.env.rates.unlink()
        self.assertEqual(self.env.run()[0], 3)
        self.env.rates.write_text("models: [not, a, mapping]", encoding="utf-8")
        self.assertEqual(self.env.run()[0], 3)

    def test_an_empty_transcripts_dir_is_unknown_not_ok(self):
        code, out, err = self.env.run()
        self.assertEqual(code, 3)
        self.assertIn("no usage found", err)
        self.assertFalse(self.env.state.exists())

    def test_files_that_hold_no_usage_at_all_are_unknown_not_ok(self):
        self.env.session(SID1, [json.dumps({"type": "user", "message": {"content": "hi"}})])
        self.assertEqual(self.env.run()[0], 3)

    def test_a_quiet_evaluated_day_with_data_elsewhere_is_still_ok(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5, day="2026-09-19")])
        code, out, _ = self.env.run()
        self.assertEqual(code, 0, "no usage today, but the window has data, so this is a quiet day")

    def test_a_day_with_no_data_and_an_unreadable_file_is_unknown(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5, day="2026-09-19")])
        (self.env.projects / "locked.jsonl").mkdir()   # matches *.jsonl but cannot be opened as a file
        code, out, err = self.env.run()
        self.assertEqual(code, 3)
        self.assertIn("could not be read", err)
        self.assertIn("no_data_for_day", out)
        self.assertEqual(self.env.status()["exit_code"], 3)

    def test_a_day_with_no_data_and_a_stale_newest_transcript_is_unknown(self):
        path = self.env.session(SID1, [assistant("m1", "claude-opus-5", 5, day="2026-09-19")])
        old = (NOW - dt.timedelta(days=3)).timestamp()
        os.utime(path, (old, old))
        code, _, err = self.env.run()
        self.assertEqual(code, 3)
        self.assertIn("more than 24 hours old", err)

    def test_stale_transcripts_do_not_matter_when_the_evaluated_day_has_data(self):
        path = self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        old = (NOW - dt.timedelta(days=3)).timestamp()
        os.utime(path, (old, old))
        (self.env.projects / "locked.jsonl").mkdir()
        self.assertEqual(self.env.run()[0], 0)

    def test_malformed_config_is_exit_3(self):
        self.env.config.write_text(json.dumps({"thresholds": {}}), encoding="utf-8")
        code, _, err = self.env.run()
        self.assertEqual(code, 3)
        self.assertIn("missing", err)

    def test_unwritable_state_dir_is_exit_3(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        self.env.state.write_text("a file, not a directory", encoding="utf-8")
        self.assertEqual(self.env.run()[0], 3)


def envelope(total_cost_usd, model_usage, extra=None):
    """A fixture CLI --output-format json result envelope, the F3 drop-folder report's own field, per
    docs/FABLE_AGENT_SUBAGENT_PLAN.md sec 11's real build-time example."""
    e = {"type": "result", "subtype": "success", "is_error": False, "num_turns": 1,
         "total_cost_usd": total_cost_usd, "permission_denials": [], "usage": {}, "modelUsage": model_usage}
    e.update(extra or {})
    return e


def model_usage(cost_usd, basis="list", canonical="claude-haiku-4-5", provider="firstParty",
                in_tok=10, out_tok=272, cr=17722, cw=35331):
    return {"inputTokens": in_tok, "outputTokens": out_tok, "cacheReadInputTokens": cr,
            "cacheCreationInputTokens": cw, "costUSD": cost_usd, "canonicalModel": canonical,
            "provider": provider, "costBasis": basis}


@requires_yaml
class HeadlessDropFolderTests(EnvTestCase):
    """F8: the drop folder (F3 report files, {envelope, checkedAt, command}) is a second, independent
    ledger source. Its own total_cost_usd/modelUsage.costUSD is read directly (list-price-equivalent
    already, per the CLI itself) rather than re-priced against routing/models.yaml."""

    def test_a_headless_report_contributes_its_reported_dollars(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])   # give the day a transcript entry too
        self.env.headless_report("pr-state-sweep", "20260920-010000",
                                 envelope(0.0738042, {"claude-haiku-4-5-20251001": model_usage(0.0738042)}),
                                 checked_at="2026-09-20T01:00:05Z")
        code, out, _ = self.env.run()
        st = self.env.status()
        self.assertAlmostEqual(st["totals"]["headless_usd"], 0.0738042)
        self.assertEqual(st["totals"]["headless_reports"], 1)
        self.assertIn("pr-state-sweep", out)
        self.assertEqual(code, 0)

    def test_two_reports_for_the_agent_the_same_day_both_count(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        self.env.headless_report("gate-execution-auditor", "20260920-010000",
                                 envelope(0.01, {"claude-haiku-4-5-20251001": model_usage(0.01)}))
        self.env.headless_report("gate-execution-auditor", "20260920-050000",
                                 envelope(0.02, {"claude-haiku-4-5-20251001": model_usage(0.02)}),
                                 checked_at="2026-09-20T05:00:00Z")
        self.env.run()
        st = self.env.status()
        self.assertAlmostEqual(st["totals"]["headless_usd"], 0.03)
        self.assertEqual(st["totals"]["headless_reports"], 2)

    def test_a_report_outside_the_window_is_excluded(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        self.env.headless_report("pr-state-sweep", "20260910-010000",
                                 envelope(9.99, {"claude-haiku-4-5-20251001": model_usage(9.99)}),
                                 checked_at="2026-09-10T01:00:00Z")
        self.env.run("--days", "7")
        self.assertAlmostEqual(self.env.status()["totals"]["headless_usd"], 0.0)

    def test_a_non_list_cost_basis_is_a_breach_and_alerts(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        self.env.headless_report("pr-state-sweep", "20260920-010000",
                                 envelope(0.05, {"claude-haiku-4-5-20251001": model_usage(0.05, basis="subscription")}))
        code, out, _ = self.env.run()
        kinds = [b["kind"] for b in self.env.status()["breaches"]]
        self.assertIn("headless_cost_basis", kinds)
        self.assertIn("costBasis", out)
        self.assertEqual(code, 1)

    def test_a_malformed_report_file_is_a_finding_not_a_crash(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        (self.env.reports / "bad.20260920-010000.json").write_text("not json", encoding="utf-8")
        code, out, _ = self.env.run()
        kinds = [b["kind"] for b in self.env.status()["breaches"]]
        self.assertIn("headless_report_unreadable", kinds)
        self.assertNotIn("Traceback", out)

    def test_a_report_missing_the_envelope_checkedat_shape_is_a_finding(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        (self.env.reports / "bad2.20260920-010000.json").write_text(json.dumps({"foo": "bar"}), encoding="utf-8")
        self.env.run()
        kinds = [b["kind"] for b in self.env.status()["breaches"]]
        self.assertIn("headless_report_shape", kinds)

    def test_an_absent_reports_dir_is_zero_headless_not_an_error(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        import shutil
        shutil.rmtree(self.env.reports)
        code, out, _ = self.env.run()
        self.assertEqual(code, 0)
        self.assertAlmostEqual(self.env.status()["totals"]["headless_usd"], 0.0)

    def test_headless_only_day_with_no_transcripts_still_evaluates(self):
        # No transcript session at all -- only a headless report -- must not be refused as "no usage found".
        self.env.headless_report("pr-state-sweep", "20260920-010000",
                                 envelope(0.5, {"claude-haiku-4-5-20251001": model_usage(0.5)}))
        code, out, _ = self.env.run()
        self.assertNotEqual(code, 3)
        self.assertAlmostEqual(self.env.status()["totals"]["headless_usd"], 0.5)

    def test_headless_rows_are_written_to_the_ledger(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        self.env.headless_report("pr-state-sweep", "20260920-010000",
                                 envelope(0.5, {"claude-haiku-4-5-20251001": model_usage(0.5)}))
        self.env.run()
        rec = json.loads(self.env.ledger_lines()[0])
        self.assertEqual(len(rec["headless"]), 1)
        self.assertEqual(rec["headless"][0]["id"], "pr-state-sweep")
        self.assertAlmostEqual(rec["headless"][0]["cost_usd"], 0.5)

    def test_message_text_never_reaches_the_headless_path_either(self):
        # There is none to leak -- the report shape carries no message text -- but the command field
        # (a full prompt in some invocations, per F3's own doc comment) must not be echoed anywhere.
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        path = self.env.headless_report("pr-state-sweep", "20260920-010000",
                                        envelope(0.5, {"claude-haiku-4-5-20251001": model_usage(0.5)}))
        rec = json.loads(path.read_text(encoding="utf-8"))
        rec["command"] = TEXT_SENTINEL
        path.write_text(json.dumps(rec), encoding="utf-8")
        code, out, err = self.env.run()
        st = (self.env.state / "status.json").read_text(encoding="utf-8")
        for blob in (out, err, st) + tuple(self.env.ledger_lines()):
            self.assertNotIn(TEXT_SENTINEL, blob)


# ------------------------------------------------------------------ headless NDJSON fallback
NDJSON_FIXTURE = (HERE / "fixtures" / "headless" / "ndjson-transcript-sample.json").read_text(encoding="utf-8")


@requires_yaml
class HeadlessNdjsonFallbackTests(EnvTestCase):
    """L1-pilot gap (2026-09-22): Invoke-ReadOnlyAgent.ps1 called without -Report writes a raw
    `--output-format stream-json` transcript (one JSON object per line) instead of the intended
    {envelope, checkedAt, command} wrapper. cost_monitor.py must still book it, by falling back to
    the last `type: result` line as the envelope, so ~$2 of real L1-pilot spend isn't silently unbooked."""

    def test_ndjson_transcript_is_read_via_its_last_result_event(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        self.env.headless_ndjson_report("gate-execution-auditor", "20260920-090000", NDJSON_FIXTURE)
        code, out, _ = self.env.run()
        st = self.env.status()
        self.assertAlmostEqual(st["totals"]["headless_usd"], 0.0234)
        self.assertEqual(st["totals"]["headless_reports"], 1)
        self.assertEqual(code, 0)
        self.assertNotIn("headless_report_unreadable", [b["kind"] for b in st["breaches"]])
        self.assertNotIn("headless_report_shape", [b["kind"] for b in st["breaches"]])

    def test_ndjson_fallback_row_is_written_to_the_ledger_and_tagged(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        self.env.headless_ndjson_report("pr-state-sweep", "20260920-090000", NDJSON_FIXTURE)
        self.env.run()
        rec = json.loads(self.env.ledger_lines()[0])
        self.assertEqual(len(rec["headless"]), 1)
        row = rec["headless"][0]
        self.assertEqual(row["id"], "pr-state-sweep")
        self.assertAlmostEqual(row["cost_usd"], 0.0234)
        self.assertEqual(row["source"], "ndjson-fallback")

    def test_a_well_formed_report_is_tagged_source_report_not_fallback(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        self.env.headless_report("pr-state-sweep", "20260920-010000",
                                 envelope(0.5, {"claude-haiku-4-5-20251001": model_usage(0.5)}))
        self.env.run()
        rec = json.loads(self.env.ledger_lines()[0])
        self.assertEqual(rec["headless"][0]["source"], "report")

    def test_ndjson_checked_at_falls_back_to_mtime_when_filename_has_no_parseable_stamp(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        # No agent.STAMP.json shape at all -- HEADLESS_FILENAME_STAMP_RE will not match this name.
        self.env.headless_ndjson_report("weird-name-no-stamp", "extra", NDJSON_FIXTURE,
                                        suffix="", mtime=NOW)
        code, out, _ = self.env.run()
        self.assertAlmostEqual(self.env.status()["totals"]["headless_usd"], 0.0234)

    def test_ndjson_transcript_with_no_result_line_is_a_finding_not_a_crash(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        no_result = "\n".join(NDJSON_FIXTURE.splitlines()[:-1]) + "\n"   # drop the result line
        self.env.headless_ndjson_report("gate-execution-auditor", "20260920-090000", no_result)
        code, out, _ = self.env.run()
        kinds = [b["kind"] for b in self.env.status()["breaches"]]
        self.assertIn("headless_report_unreadable", kinds)
        self.assertNotIn("Traceback", out)

    def test_ndjson_fixture_text_never_leaks(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        self.env.headless_ndjson_report("gate-execution-auditor", "20260920-090000", NDJSON_FIXTURE)
        code, out, err = self.env.run()
        st = (self.env.state / "status.json").read_text(encoding="utf-8")
        for blob in (out, err, st) + tuple(self.env.ledger_lines()):
            self.assertNotIn("FAKE-FIXTURE-TEXT", blob)
            self.assertNotIn("FAKE-FIXTURE-TOOL-RESULT", blob)
            self.assertNotIn("FAKE-FIXTURE-FINAL-TEXT", blob)

    def test_a_file_with_an_invalid_utf8_byte_is_a_finding_not_a_raise(self):
        # 0xff 0xfe 0x8f is not valid UTF-8 (0xff/0xfe are never valid UTF-8 lead bytes); decoding it
        # with encoding="utf-8" must raise UnicodeDecodeError, which scan_headless has to catch.
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        self.env.headless_bytes_report("gate-execution-auditor", "20260920-090000", b"\xff\xfe\x8f")
        code, out, _ = self.env.run()   # must not raise
        kinds = [b["kind"] for b in self.env.status()["breaches"]]
        self.assertIn("headless_report_unreadable", kinds)
        self.assertNotIn("Traceback", out)

    def test_a_utf16le_bom_file_is_a_finding_not_a_raise(self):
        # PowerShell 5.1's `>` redirection writes UTF-16LE with a BOM by default. Decoded as UTF-8
        # (what this reader always uses), the BOM bytes (FF FE) and the null bytes between UTF-16LE
        # characters are invalid UTF-8 and must raise UnicodeDecodeError, not crash scan_headless.
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        raw = '{"envelope": {}, "checkedAt": "2026-09-20T01:00:00Z"}'.encode("utf-16-le")
        raw = b"\xff\xfe" + raw   # UTF-16LE BOM
        self.env.headless_bytes_report("pr-state-sweep", "20260920-090000", raw)
        code, out, _ = self.env.run()   # must not raise
        kinds = [b["kind"] for b in self.env.status()["breaches"]]
        self.assertIn("headless_report_unreadable", kinds)
        self.assertNotIn("Traceback", out)


# ------------------------------------------------------------------ ledger
@requires_yaml
class LedgerTests(EnvTestCase):
    def test_no_write_touches_nothing(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        code, out, _ = self.env.run("--no-write")
        self.assertFalse(self.env.state.exists())

    def test_ledger_is_append_only_and_a_rerun_appends_nothing(self):
        path = self.env.session(SID1, [assistant("m1", "claude-opus-5", 5, day="2026-09-19"),
                                       assistant("m2", "claude-opus-5", 5, day="2026-09-20")])
        self.env.run()
        first19, first20 = self.env.ledger_lines("2026-09-19"), self.env.ledger_lines("2026-09-20")
        self.assertEqual((len(first19), len(first20)), (1, 1))
        self.env.run()
        self.assertEqual((self.env.ledger_lines("2026-09-19"), self.env.ledger_lines("2026-09-20")), (first19, first20))

        with open(path, "a", encoding="utf-8", newline="\n") as fh:
            fh.write(assistant("m3", "claude-opus-5", 50, day="2026-09-20") + "\n")
        self.env.run()
        after20 = self.env.ledger_lines("2026-09-20")
        self.assertEqual(len(after20), 2)
        self.assertEqual(after20[0], first20[0], "the earlier line is untouched")
        self.assertEqual(self.env.ledger_lines("2026-09-19"), first19, "a finished day stops growing")

    def test_streaming_growth_appends_a_new_line_with_the_final_count(self):
        path = self.env.session(SID1, [assistant("m1", "claude-opus-5", 7)])
        self.env.run()
        with open(path, "a", encoding="utf-8", newline="\n") as fh:
            fh.write(assistant("m1", "claude-opus-5", 920) + "\n")
        self.env.run()
        lines = [json.loads(x) for x in self.env.ledger_lines()]
        self.assertEqual([x["models"][0]["out"] for x in lines], [7, 920])

    def test_ledger_and_status_carry_the_honest_caveats(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 5)])
        self.env.run()
        rec = json.loads(self.env.ledger_lines()[0])
        self.assertTrue(rec["what_if_not_a_bill"])
        self.assertEqual(rec["rates_verified_on"], ["2000-01-01"])
        st = self.env.status()
        for key in ("state", "exit_code", "generated_at", "evaluated_day", "totals", "thresholds", "breaches", "api_key_present", "rates", "coverage"):
            self.assertIn(key, st)
        self.assertEqual(st["generated_at"], "2026-09-20T12:00:00Z")
        self.assertTrue(st["what_if_not_a_bill"])
        self.assertIn("only", st["coverage"])
        self.assertEqual(st["thresholds"]["status"], "TEST", "status.json echoes the config's own status marker")


@requires_yaml
class LedgerThrottleTests(unittest.TestCase):
    """A ledger line is a full snapshot of its day, so the current day is appended at most once per
    interval; a finished day is appended at once so its final line is never lost."""

    def setUp(self):
        cfg = config()
        cfg["ledger_min_interval_minutes"] = 60
        self.env = Env(cfg)
        self.addCleanup(self.env.close)
        self.path = self.env.session(SID1, [assistant("m1", "claude-opus-5", 5, day="2026-09-20")])

    def grow(self, mid, day="2026-09-20"):
        with open(self.path, "a", encoding="utf-8", newline="\n") as fh:
            fh.write(assistant(mid, "claude-opus-5", 50, day=day) + "\n")

    def test_current_day_changes_inside_the_interval_are_not_appended(self):
        self.env.run(now=NOW)
        self.grow("m2")
        self.env.run(now=NOW + dt.timedelta(minutes=30))
        self.assertEqual(len(self.env.ledger_lines()), 1)
        self.assertEqual(self.env.status()["generated_at"], "2026-09-20T12:30:00Z", "status.json is still refreshed")

    def test_current_day_is_appended_once_the_interval_has_passed(self):
        self.env.run(now=NOW)
        self.grow("m2")
        self.env.run(now=NOW + dt.timedelta(minutes=61))
        self.assertEqual(len(self.env.ledger_lines()), 2)

    def test_the_first_line_of_a_day_is_never_throttled(self):
        self.env.run(now=NOW)
        self.assertEqual(len(self.env.ledger_lines()), 1)

    def test_a_finished_day_is_appended_immediately(self):
        self.grow("m_old", day="2026-09-19")
        self.env.run(now=NOW)
        self.assertEqual(len(self.env.ledger_lines("2026-09-19")), 1)
        self.grow("m_late", day="2026-09-19")
        self.env.run(now=NOW + dt.timedelta(minutes=1))
        self.assertEqual(len(self.env.ledger_lines("2026-09-19")), 2, "yesterday is not the current day, so no throttle")

    def test_shipped_default_is_an_hour(self):
        self.assertEqual(cm.load_config(str(TOOL.parent / "config.json"))["ledger_min_interval_minutes"], 60)


# ------------------------------------------------------------------ the call site and the guard rails
class CallSiteTests(EnvTestCase):
    def test_running_the_script_as_a_child_process_returns_the_documented_exit_code(self):
        self.env.session(SID1, [assistant("m1", "claude-opus-5", 0, inp=1000000)])
        cfg = config(opus_whatif_alert_usd_per_day=4, opus_whatif_stop_usd_per_day=8)
        self.env.config.write_text(json.dumps(cfg), encoding="utf-8")
        proc = subprocess.run([sys.executable, str(TOOL), "--projects-dir", str(self.env.projects), "--state-dir", str(self.env.state),
                               "--rates-file", str(self.env.rates), "--config", str(self.env.config), "--day", "2026-09-20", "--days", "40"],
                              capture_output=True, text=True, encoding="utf-8")
        # The child uses the real clock, so 2026-09-20 may be outside its 40-day window; it must still
        # exit with a documented code and never raise.
        self.assertIn(proc.returncode, (0, 1, 2, 3))
        self.assertNotIn("Traceback", proc.stderr)


class NoModelCallsTests(unittest.TestCase):
    ALLOWED = {"argparse", "collections", "datetime", "glob", "hashlib", "json", "os", "re", "subprocess", "sys", "yaml", "winreg"}

    def test_imports_contain_no_network_or_model_client(self):
        tree = ast.parse(TOOL.read_text(encoding="utf-8"))
        imported = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imported.update(n.name.split(".")[0] for n in node.names)
            elif isinstance(node, ast.ImportFrom):
                imported.add((node.module or "").split(".")[0])
        self.assertLessEqual(imported, self.ALLOWED, "unexpected import: %s" % sorted(imported - self.ALLOWED))

    def test_the_only_subprocess_is_git(self):
        tree = ast.parse(TOOL.read_text(encoding="utf-8"))
        calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
                 and isinstance(n.func.value, ast.Name) and n.func.value.id == "subprocess"]
        self.assertTrue(calls, "expected the git calls to exist, otherwise this test guards nothing")
        for call in calls:
            first = call.args[0]
            self.assertIsInstance(first, ast.List)
            self.assertEqual(first.elts[0].value, "git")


if __name__ == "__main__":
    unittest.main()
