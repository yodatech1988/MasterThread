#!/usr/bin/env python
"""Zero-model-call cost monitor for Claude Code transcripts (Phase 1).

Reads ~/.claude/projects/<project>/**/*.jsonl, counts each API response once, and reports input,
output, cache-read and cache-write tokens per day, per model, per session and per subagent, with a
WHAT-IF dollar estimate at list rates. It is a meter, not a bill.

Hard rules (each is pinned by a test in tools/tests/test_cost_monitor.py):
  * No model calls, no network. The only subprocess is `git show` against the local rates repo.
  * Read-only over the transcripts. It reads usage numbers, ids, model names, timestamps and the
    session's aiTitle. It never prints or stores message text.
  * A model missing from the rates file is UNPRICED. It is never guessed.

Exit codes: 0 ok, 1 alert, 2 stop-and-ask, 3 unknown / could not read.
"""
import argparse
import collections
import datetime as dt
import glob
import hashlib
import json
import os
import re
import subprocess
import sys

try:
    import yaml
except ImportError:  # reported as exit 3 in main()
    yaml = None

NL = chr(10)
BS = chr(92)
HERE = os.path.dirname(os.path.abspath(__file__))


def project_slug(path):
    """Every non-alphanumeric character becomes a hyphen; a Windows drive letter is lower-cased."""
    slug = re.sub(r"[^A-Za-z0-9]", "-", path)
    return slug[0].lower() + slug[1:] if re.match(r"^[A-Za-z]:", path) else slug


def default_projects_dir():
    """Claude Code names a project folder after the working directory with every character that is not a
    letter or digit turned into '-'. The workspace is the folder that holds this checkout
    (<workspace>/<repo>/tools/cost-monitor), so the slug is derived from where the tool lives rather
    than hardcoded. Pass --projects-dir for any other layout."""
    workspace = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
    return os.path.join(os.path.expanduser("~"), ".claude", "projects", project_slug(workspace))


DEFAULT_PROJECTS = default_projects_dir()
DEFAULT_RATES_REPO = os.path.join(os.path.expanduser("~"), "GitHub", "ops-policies")
RATES_REF = "origin/main"
RATES_PATH = "routing/models.yaml"
DATED_SUFFIX = re.compile(r"^-[0-9]{8}$")
FIELDS = ("in", "out", "cache_read", "cache_write", "cache_write_5m", "cache_write_1h", "cache_write_unknown", "msgs")
API_KEY_NAME = "ANTHROPIC_API_KEY"
ERROR_NO_MORE_ITEMS = 259   # winreg.EnumValue past the last value
MACHINE_ENV_KEY = BS.join(["SYSTEM", "CurrentControlSet", "Control", "Session Manager", "Environment"])

OK, ALERT, STOP, UNKNOWN = 0, 1, 2, 3
STALE_HOURS = 24   # newest transcript older than this on a day with no data is a blind spot
STATE_NAMES = {OK: "ok", ALERT: "alert", STOP: "stop-and-ask", UNKNOWN: "unknown"}


def default_state_dir():
    return os.path.join(os.environ.get("APPDATA") or os.path.expanduser("~"), "AEGIS", "cost")


def default_reports_dir():
    """The Fable headless drop folder (F3, plan:617): one {envelope, checkedAt, command} report per
    headless run, written by tools/headless/Invoke-ReadOnlyAgent.ps1 -Report. D6 keeps it on this PC."""
    return os.path.join(os.environ.get("APPDATA") or os.path.expanduser("~"), "AEGIS", "reports")


HEADLESS_STAMP_RE = re.compile(r"^(?P<agent>.+)\.\d{8}-\d{6}(?:-\d+)?$")
HEADLESS_FILENAME_STAMP_RE = re.compile(r"\.(?P<ymd>\d{8})-(?P<hms>\d{6})(?:-\d+)?\.json$")


def _checked_at_from_filename(name):
    """A report's own filename stamp (agent.YYYYMMDD-HHMMSS[-N].json), used as a checkedAt fallback
    when the report carries none of its own (an NDJSON transcript, see _last_result_event). Returns
    an ISO UTC string, or None if the filename does not carry a parseable stamp."""
    m = HEADLESS_FILENAME_STAMP_RE.search(name)
    if not m:
        return None
    try:
        stamp = dt.datetime.strptime(m.group("ymd") + m.group("hms"), "%Y%m%d%H%M%S")
    except ValueError:
        return None
    return stamp.strftime("%Y-%m-%dT%H:%M:%SZ")


def _last_result_event(text):
    """A report file written without Invoke-ReadOnlyAgent.ps1's -Report flag is a raw
    `--output-format stream-json` transcript instead of the intended {envelope, checkedAt, command}
    wrapper: one JSON object per line, streamed as the run progresses (system/assistant/user/... events),
    with a final `type: result` event that carries the same fields the envelope was always meant to
    have (total_cost_usd, modelUsage, num_turns, ...). This is the NDJSON fallback (2026-09-22, F-ledger
    gap: 19/19 gate-execution-auditor and 19/22 pr-state-sweep L1-pilot reports were written this way).

    Returns the last line whose parsed `type` is "result" as a dict, matching the shape scan_headless
    already expects for `envelope`; or None if the text is not single-JSON and no such line is found."""
    result = None
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if isinstance(row, dict) and row.get("type") == "result":
            result = row
    return result


def safe_label(text, limit=60):
    """A label is shown to a human, so keep it one printable ASCII line."""
    return re.sub(r"[^ -~]+", " ", str(text or "")).strip()[:limit]


# ------------------------------------------------------------------------------------ rates
class RatesError(Exception):
    pass


def load_rates(rates_file=None, repo=DEFAULT_RATES_REPO):
    """Returns (models, meta). models: id -> {key, name, in, out, read_factor, verified_on}.

    Default source is `git show origin/main:routing/models.yaml` in the ops-policies checkout: the
    rate table as merged, never a working tree. `rates_file` exists for tests."""
    if yaml is None:
        raise RatesError("PyYAML is not installed (pip install pyyaml)")
    if rates_file:
        try:
            with open(rates_file, encoding="utf-8") as fh:
                text = fh.read()
        except OSError as exc:
            raise RatesError("cannot read rates file %s: %s" % (rates_file, exc))
        source = "file:" + rates_file
    else:
        try:
            text = subprocess.run(["git", "-C", repo, "show", "%s:%s" % (RATES_REF, RATES_PATH)],
                                  capture_output=True, text=True, encoding="utf-8", check=True).stdout
            sha = subprocess.run(["git", "-C", repo, "rev-parse", "--short", RATES_REF],
                                 capture_output=True, text=True, check=True).stdout.strip()
        except (OSError, subprocess.CalledProcessError) as exc:
            raise RatesError("cannot read %s:%s from %s: %s" % (RATES_REF, RATES_PATH, repo, exc))
        source = "git:%s@%s (%s:%s)" % (repo.replace(BS, "/"), sha, RATES_REF, RATES_PATH)
    try:
        doc = yaml.safe_load(text)
        entries = doc["models"]
    except Exception as exc:
        raise RatesError("rates file is not the expected shape: %s" % exc)
    if not isinstance(entries, dict) or not entries:
        raise RatesError("rates file 'models' must be a non-empty mapping")
    models = {}
    for key, m in entries.items():
        try:
            models[m["id"]] = {"key": key, "name": m.get("display_name", key), "in": float(m["in"]),
                               "out": float(m["out"]), "verified_on": str(m.get("verified_on", "unknown")),
                               "read_factor": m.get("cache_read_factor_override")}
        except (KeyError, TypeError, ValueError) as exc:
            raise RatesError("model %r has no usable id/in/out: %s" % (key, exc))
    meta = {"source": source, "verification_record": str(doc.get("verification_record", "unknown")),
            "verified_on": sorted({m["verified_on"] for m in models.values()})}
    return models, meta


def match_model(model, rates):
    """Exact id, or a known id plus a dated snapshot suffix (claude-haiku-4-5-20251001).
    Returns (entry, how) or (None, None). Nothing else is ever matched."""
    if model in rates:
        return rates[model], "exact"
    for rid, entry in rates.items():
        if model.startswith(rid) and DATED_SUFFIX.match(model[len(rid):]):
            return entry, "dated-suffix"
    return None, None


def usd(counts, entry, cfg):
    """(low, high, io_only) what-if dollars, or None when the model is unpriced.

    Cache-write pricing is TTL-aware (F8, 2026-09-22): a response whose usage.cache_creation carries
    the 5m/1h split is priced at the CONFIRMED per-TTL rate for each bucket -- low and high collapse
    to the same exact number. A response with only the aggregate cache_creation_input_tokens (TTL
    unknown -- an older transcript shape, or a model that doesn't report the split) keeps the original
    low(5m)-high(1h) range convention, so the uncertainty is about which TTL was used, never about
    the rate itself."""
    if entry is None:
        return None
    cm = cfg["cache_multipliers"]
    read = entry["read_factor"] if entry["read_factor"] is not None else cm["read"]
    base = counts["in"] * entry["in"] + counts["out"] * entry["out"] + counts["cache_read"] * entry["in"] * read
    confirmed = (counts["cache_write_5m"] * entry["in"] * cm["write_5m"] +
                counts["cache_write_1h"] * entry["in"] * cm["write_1h"])
    unknown = counts["cache_write_unknown"]
    low = base + confirmed + unknown * entry["in"] * cm["write_5m"]
    high = base + confirmed + unknown * entry["in"] * cm["write_1h"]
    return low / 1e6, high / 1e6, (counts["in"] * entry["in"] + counts["out"] * entry["out"]) / 1e6


# ------------------------------------------------------------------------------------ scanning
def scan(projects_dir, today, days):
    """Reads every transcript once. Returns (best, titles, stats).

    A response is written on several lines, and only `output_tokens` differs between them: it grows
    while the response streams (7, 7, 920). The last line is the final count and is never lower than
    an earlier one, so per message id the line with the greatest output_tokens is kept. Keeping the
    first line instead undercounts output badly (Opus 17-84%, Haiku ~98% on 2026-09-17..20)."""
    first_day = today - dt.timedelta(days=days - 1)
    cutoff_mtime = dt.datetime.combine(first_day, dt.time(), tzinfo=dt.timezone.utc).timestamp()
    best, titles = {}, {}
    stats = {"files": 0, "unreadable": 0, "lines": 0, "responses": 0, "newest_mtime": None}
    for path in glob.glob(os.path.join(projects_dir, "**", "*.jsonl"), recursive=True):
        try:
            mtime = os.path.getmtime(path)
            if stats["newest_mtime"] is None or mtime > stats["newest_mtime"]:
                stats["newest_mtime"] = mtime
            if mtime < cutoff_mtime:
                continue
            fh = open(path, encoding="utf-8", errors="replace")
        except OSError:
            stats["unreadable"] += 1
            continue
        parts = os.path.relpath(path, projects_dir).replace(BS, "/").split("/")
        kind = "subagent" if "subagents" in parts else "session"
        sid = parts[0][:-6] if parts[0].endswith(".jsonl") else parts[0]
        agent = os.path.splitext(parts[-1])[0] if kind == "subagent" else ""
        stats["files"] += 1
        with fh:
            for line in fh:
                stats["lines"] += 1
                has_title = '"aiTitle"' in line
                if not has_title and '"usage"' not in line:
                    continue
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                if has_title and row.get("aiTitle"):
                    titles[(sid, agent)] = safe_label(row["aiTitle"])
                msg = row.get("message") or {}
                usage, mid, model = msg.get("usage"), msg.get("id"), msg.get("model")
                if not usage or not mid or not model or model == "<synthetic>":
                    continue
                out = usage.get("output_tokens") or 0
                if mid in best and best[mid]["out"] >= out:
                    continue
                # TTL split (usage.cache_creation.ephemeral_5m_input_tokens / ephemeral_1h_input_tokens),
                # when the API reports it, prices exactly (F8). Its absence -- an older transcript shape,
                # or a response that only carries the aggregate cache_creation_input_tokens -- is priced
                # as unknown-TTL, kept separate rather than guessed into one bucket or the other.
                cache = usage.get("cache_creation") or {}
                cw_5m = cache.get("ephemeral_5m_input_tokens") or 0
                cw_1h = cache.get("ephemeral_1h_input_tokens") or 0
                if cw_5m or cw_1h:
                    cw_total, cw_unknown = cw_5m + cw_1h, 0
                else:
                    cw_total = usage.get("cache_creation_input_tokens") or 0
                    cw_unknown = cw_total
                best[mid] = {"out": out, "in": usage.get("input_tokens") or 0,
                             "cache_read": usage.get("cache_read_input_tokens") or 0,
                             "cache_write": cw_total, "cache_write_5m": cw_5m, "cache_write_1h": cw_1h,
                             "cache_write_unknown": cw_unknown,
                             "model": model, "day": (row.get("timestamp") or "")[:10],
                             "sid": sid, "kind": kind, "agent": agent}
    stats["responses"] = len(best)
    return best, titles, stats


def aggregate(best, titles, first_day):
    by_model = collections.defaultdict(collections.Counter)   # (day, model)
    by_row = collections.defaultdict(collections.Counter)     # (day, kind, sid, agent, model)
    for r in best.values():
        if not r["day"] or r["day"] < first_day:
            continue
        for tgt in (by_model[(r["day"], r["model"])], by_row[(r["day"], r["kind"], r["sid"], r["agent"], r["model"])]):
            for f in FIELDS[:-1]:   # every count field except msgs, which is incremented separately
                tgt[f] += r[f]
            tgt["msgs"] += 1
    rows = []
    for (day, kind, sid, agent, model), c in sorted(by_row.items()):
        parent = titles.get((sid, "")) or sid[:8]
        label = titles.get((sid, agent)) or (parent if kind == "session" else "%s / %s" % (parent, agent[:14]))
        row = {"day": day, "kind": kind, "id": sid, "agent": agent, "model": model, "label": label}
        row.update({f: c[f] for f in FIELDS})
        rows.append(row)
    return by_model, rows


# ------------------------------------------------------------------------------------ headless (F8)
def scan_headless(reports_dir, today, days):
    """Reads the Fable headless drop folder (F3, plan:617) as a second, independent ledger source
    alongside scan()'s interactive-transcript read. Each report is exactly {envelope, checkedAt,
    command}; the envelope is the CLI's own --output-format json result, already reported at
    API-list-price parity while billed against the subscription (plan sec 11). This reads
    envelope.total_cost_usd / modelUsage rather than re-pricing tokens against routing/models.yaml,
    and asserts every modelUsage entry's costBasis == "list" -- a future CLI change to a different
    basis (e.g. "subscription") is a finding, not a silent change to what the ledger means.

    Returns (rows, findings, stats). Never raises: a missing folder is zero reports, not an error --
    most sessions never run a headless agent. A malformed report file is a finding, not a crash.

    A report that is not a single JSON object is retried as an NDJSON stream-json transcript
    (_last_result_event): its last `type: result` line stands in for `envelope`, and `checkedAt` is
    derived from the filename's own stamp (or the file's mtime, if that fails to parse) since a raw
    transcript carries no checkedAt of its own. Rows from this path carry `source: "ndjson-fallback"`
    so the ledger can tell them apart from a normal -Report envelope (source: "report")."""
    first_day, last_day = today - dt.timedelta(days=days - 1), today
    rows, findings = [], []
    stats = {"files": 0, "unreadable": 0, "reports": 0}
    if not os.path.isdir(reports_dir):
        return rows, findings, stats
    for path in sorted(glob.glob(os.path.join(reports_dir, "*.json"))):
        stats["files"] += 1
        name = os.path.basename(path)
        m = HEADLESS_STAMP_RE.match(os.path.splitext(name)[0])
        agent = m.group("agent") if m else os.path.splitext(name)[0]
        ndjson_fallback = False
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except OSError:
            stats["unreadable"] += 1
            findings.append(("unknown", "headless_report_unreadable", "%s could not be read" % name))
            continue
        try:
            rec = json.loads(text)
        except ValueError:
            result_event = _last_result_event(text)
            if result_event is None:
                stats["unreadable"] += 1
                findings.append(("unknown", "headless_report_unreadable", "%s could not be read as JSON" % name))
                continue
            checked_at = (_checked_at_from_filename(name)
                         or dt.datetime.fromtimestamp(os.path.getmtime(path), dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
            rec = {"envelope": result_event, "checkedAt": checked_at, "command": None}
            ndjson_fallback = True
        if not isinstance(rec, dict) or "envelope" not in rec or "checkedAt" not in rec:
            stats["unreadable"] += 1
            findings.append(("unknown", "headless_report_shape", "%s is not the {envelope, checkedAt, command} shape" % name))
            continue
        envelope = rec.get("envelope")
        if not isinstance(envelope, dict):
            stats["unreadable"] += 1
            findings.append(("unknown", "headless_report_shape", "%s envelope is not a JSON object" % name))
            continue
        day = str(rec.get("checkedAt") or "")[:10]
        if not day or day < first_day.isoformat() or day > last_day.isoformat():
            continue
        model_usage = envelope.get("modelUsage") or {}
        if not model_usage:
            findings.append(("unknown", "headless_no_model_usage", "%s has no modelUsage to verify costBasis against" % name))
            continue
        stats["reports"] += 1
        for model_id, mu in model_usage.items():
            if not isinstance(mu, dict):
                continue
            basis = mu.get("costBasis")
            if basis != "list":
                findings.append(("alert", "headless_cost_basis",
                                 "%s model %s reports costBasis=%r, not 'list' -- its dollar figure may no longer be API-list-price-equivalent"
                                 % (name, model_id, basis)))
            rows.append({"day": day, "kind": "headless", "id": agent, "agent": "", "model": model_id, "label": agent,
                        "in": int(mu.get("inputTokens") or 0), "out": int(mu.get("outputTokens") or 0),
                        "cache_read": int(mu.get("cacheReadInputTokens") or 0),
                        "cache_write": int(mu.get("cacheCreationInputTokens") or 0),
                        "msgs": 1, "cost_usd": float(mu.get("costUSD") or 0.0), "cost_basis": basis,
                        "provider": mu.get("provider"), "canonical_model": mu.get("canonicalModel"),
                        "report_total_cost_usd": envelope.get("total_cost_usd"), "report_file": name,
                        "source": "ndjson-fallback" if ndjson_fallback else "report"})
    return rows, findings, stats


# ------------------------------------------------------------------------------------ api key
def _registry_has_key(hive_name):
    """True / False, or None when it cannot be checked (not Windows, or access denied)."""
    try:
        import winreg
    except ImportError:
        return None
    hive, sub = ((winreg.HKEY_CURRENT_USER, "Environment") if hive_name == "user"
                 else (winreg.HKEY_LOCAL_MACHINE, MACHINE_ENV_KEY))
    try:
        with winreg.OpenKey(hive, sub) as key:
            # Names only. EnumValue returns (name, data, type); the data is dropped unread, so the
            # value is never assigned to anything, printed or stored.
            index = 0
            while True:
                try:
                    name = winreg.EnumValue(key, index)[0]
                except OSError as exc:
                    if getattr(exc, "winerror", None) == ERROR_NO_MORE_ITEMS:
                        return False   # ran out of names without seeing the key
                    raise
                if name.upper() == API_KEY_NAME:
                    return True
                index += 1
    except FileNotFoundError:
        return False
    except OSError:
        return None


def check_api_key(env=None, registry=_registry_has_key):
    """Presence only, in the current process and the User and Machine environments. Only the fact
    that the name exists is kept. The registry is enumerated by NAME only and the data that comes back
    with each name is discarded unread; the value is never assigned to anything, printed or stored,
    and no files are scanned."""
    env = os.environ if env is None else env
    result = {"process": API_KEY_NAME in env, "user": registry("user"), "machine": registry("machine")}
    result["present_anywhere"] = any(v is True for v in result.values())
    return result


# ------------------------------------------------------------------------------------ evaluate
def evaluate(day, by_model, rows, rates, cfg, api_key, headless_rows=(), headless_findings=()):
    """Returns (state_code, breaches, totals) for one UTC day. Alerts use the HIGH cache-write
    estimate, so an uncertain multiplier can only make the monitor louder, never quieter.

    headless_rows/headless_findings (F8) fold in the drop-folder scan: its own reported dollars are
    additive to totals under a separate headless_usd key (not re-priced or merged into by_model,
    whose dollars come from routing/models.yaml), and its findings (e.g. a costBasis breach) can
    raise the day's exit code exactly like any other breach."""
    th = cfg["thresholds"]
    breaches, per_model, unpriced = [], {}, {}
    for (d, model), c in by_model.items():
        if d != day:
            continue
        entry, how = match_model(model, rates)
        price = usd(c, entry, cfg)
        if price is None:
            unpriced[model] = int(c["in"] + c["out"] + c["cache_read"] + c["cache_write"])
        per_model[model] = {"counts": dict(c), "priced": price is not None, "match": how,
                            "family": entry["key"] if entry else None,
                            "usd_low": price[0] if price else None, "usd_high": price[1] if price else None,
                            "usd_io": price[2] if price else None}
    priced = [v for v in per_model.values() if v["priced"]]
    total_high = sum(v["usd_high"] for v in priced)
    opus_high = sum(v["usd_high"] for v in priced if v["family"] == "opus")
    share = (opus_high / total_high) if total_high else 0.0
    totals = {"day": day, "usd_low": sum(v["usd_low"] for v in priced), "usd_high": total_high,
              "opus_usd_high": opus_high, "opus_share": share, "unpriced_tokens": unpriced,
              "by_model": per_model}

    if opus_high >= th["opus_whatif_stop_usd_per_day"]:
        breaches.append(("stop", "opus_whatif_stop", "Opus what-if $%.2f/day >= stop-and-ask $%s" % (opus_high, th["opus_whatif_stop_usd_per_day"])))
    elif opus_high >= th["opus_whatif_alert_usd_per_day"]:
        breaches.append(("alert", "opus_whatif_alert", "Opus what-if $%.2f/day >= alert $%s" % (opus_high, th["opus_whatif_alert_usd_per_day"])))
    if share >= th["opus_share_alert_fraction"] and total_high >= th["opus_share_min_day_usd"]:
        breaches.append(("alert", "opus_share", "Opus is %.0f%% of the day's priced what-if ($%.2f of $%.2f)" % (share * 100, opus_high, total_high)))
    for r in rows:
        if r["day"] == day and r["out"] >= th["session_output_alert_tokens"]:
            breaches.append(("alert", "session_output_spike", "%s %s (%s) wrote %d output tokens today >= %d" % (r["kind"], r["label"], r["model"], r["out"], th["session_output_alert_tokens"])))
    if cfg.get("alert_on_api_key", True) and api_key["present_anywhere"]:
        where = [k for k in ("process", "user", "machine") if api_key[k] is True]
        breaches.append(("alert", "api_key_present", "%s is set in: %s. It outranks the subscription token and turns work into metered billing." % (API_KEY_NAME, ", ".join(where))))
    if unpriced:
        breaches.append(("unknown", "unpriced_model", "no verified rate for: %s. The day's dollar total is a floor." % ", ".join(sorted(unpriced))))

    headless_today = [r for r in headless_rows if r["day"] == day]
    totals["headless_usd"] = sum(r["cost_usd"] for r in headless_today)
    totals["headless_reports"] = len({r["report_file"] for r in headless_today})
    breaches.extend(headless_findings)

    kinds = {b[0] for b in breaches}
    code = STOP if "stop" in kinds else ALERT if "alert" in kinds else UNKNOWN if "unknown" in kinds else OK
    return code, breaches, totals


# ------------------------------------------------------------------------------------ writing
def _digest(payload):
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode("utf-8")).hexdigest()


def write_ledger(state_dir, by_model, rows, rates, meta, cfg, now, headless_rows=()):
    """Append-only, one file per data day. A line is appended only when that day's content changed
    since the file's last line, so a rerun adds nothing and a finished day stops growing. Older
    lines are never rewritten, which is what keeps history if Claude prunes old transcripts.
    Session rows carry a `label` (the aiTitle). Anything that copies the ledger off this PC must
    drop it.

    headless_rows (F8) are appended under their own `headless` key per day, alongside `sessions` --
    a distinct source (the drop folder, not a transcript), never merged into the same rows."""
    os.makedirs(state_dir, exist_ok=True)
    fingerprint = {"rates": meta["source"], "verified": meta["verified_on"], "cache": cfg["cache_multipliers"]}
    interval = cfg.get("ledger_min_interval_minutes", 60)
    written = []
    for day in sorted({d for d, _ in by_model} | {r["day"] for r in headless_rows}):
        model_rows = []
        for (d, model), c in sorted(by_model.items()):
            if d != day:
                continue
            entry, how = match_model(model, rates)
            price = usd(c, entry, cfg)
            row = {"model": model, "priced": price is not None, "match": how,
                   "usd_low": round(price[0], 4) if price else None, "usd_high": round(price[1], 4) if price else None}
            row.update({f: c[f] for f in FIELDS})
            model_rows.append(row)
        session_rows = [r for r in rows if r["day"] == day]
        headless_day_rows = [r for r in headless_rows if r["day"] == day]
        digest = _digest([model_rows, session_rows, headless_day_rows, fingerprint])
        path = os.path.join(state_dir, "ledger-%s.jsonl" % day)
        last_digest = last_at = None
        if os.path.exists(path):
            with open(path, encoding="utf-8") as fh:
                for line in fh:
                    if line.strip():
                        rec = json.loads(line)
                        last_digest, last_at = rec.get("digest"), rec.get("written_at")
        if last_digest == digest:
            continue
        # Every line is a full snapshot of its day, so a busy day appended on every change would grow
        # by tens of KB per run. The CURRENT day is therefore throttled; a finished day is appended
        # immediately, so its final line is never lost.
        if last_at and day == now.date().isoformat() and interval > 0:
            age = now - dt.datetime.strptime(last_at, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
            if age < dt.timedelta(minutes=interval):
                continue
        record = {"schema": 1, "day": day, "written_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"), "digest": digest,
                  "what_if_not_a_bill": True, "rates_source": meta["source"], "rates_verified_on": meta["verified_on"],
                  "cache_multipliers": cfg["cache_multipliers"], "models": model_rows, "sessions": session_rows,
                  "headless": headless_day_rows}
        with open(path, "a", encoding="utf-8", newline=NL) as fh:
            fh.write(json.dumps(record, sort_keys=True) + NL)
        written.append(path)
    return written


def write_status(state_dir, code, breaches, totals, api_key, meta, cfg, stats, now):
    os.makedirs(state_dir, exist_ok=True)
    status = {"schema": 1, "generated_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"), "exit_code": code,
              "state": STATE_NAMES[code], "evaluated_day": totals["day"], "what_if_not_a_bill": True,
              "totals": {k: v for k, v in totals.items() if k != "by_model"},
              "by_model": totals["by_model"],
              "breaches": [{"severity": s, "kind": k, "detail": d} for s, k, d in breaches],
              "thresholds": cfg["thresholds"], "cache_multipliers": cfg["cache_multipliers"],
              "api_key_present": api_key, "rates": meta, "coverage": stats["coverage"],
              "read": {k: stats[k] for k in ("files", "unreadable", "lines", "responses")}}
    path = os.path.join(state_dir, "status.json")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline=NL) as fh:
        json.dump(status, fh, indent=2, sort_keys=True)
        fh.write(NL)
    os.replace(tmp, path)
    return path


# ------------------------------------------------------------------------------------ report
def report(out, by_model, rows, rates, meta, cfg, stats, totals, breaches, api_key, code, top,
           headless_rows=(), reports_dir=None):
    def p(s=""):
        out.write(s + NL)
    cm, th = cfg["cache_multipliers"], cfg["thresholds"]
    p("Claude Code cost monitor -- WHAT-IF at list rates, NOT a bill. Zero model calls.")
    p("Coverage: %s. Nothing outside these transcripts is included." % stats["coverage"])
    p("Read: %d files, %d lines, %d unique API responses (%d unreadable files)." % (stats["files"], stats["lines"], stats["responses"], stats["unreadable"]))
    p("Rates: %s" % meta["source"])
    p("       verification record: %s; per-model verified_on: %s" % (meta["verification_record"], ", ".join(meta["verified_on"])))
    p("Cache write rates (%s): 5-minute TTL %sx, 1-hour TTL %sx (confirmed per-TTL). Cache-write tokens of"
      % (cm["status"], cm["write_5m"], cm["write_1h"]))
    p("  unknown TTL are priced as a %sx-%sx low-high range. Cache read %sx (a model's own override wins)."
      % (cm["write_5m"], cm["write_1h"], cm["read"]))
    p("Thresholds (%s): Opus alert $%s, stop-and-ask $%s per day." % (th["status"], th["opus_whatif_alert_usd_per_day"], th["opus_whatif_stop_usd_per_day"]))
    p()
    p("%-11s %-28s %6s %10s %10s %13s %12s  %s" % ("day(UTC)", "model", "msgs", "input", "output", "cache_read", "cache_write", "what-if $ (low-high)  [in+out only]"))
    for (day, model), c in sorted(by_model.items()):
        entry, how = match_model(model, rates)
        price = usd(c, entry, cfg)
        if price is None:
            cost = "UNPRICED (no verified rate)"
        else:
            cost = "$%.2f-$%.2f  [$%.2f]%s" % (price[0], price[1], price[2], "  (dated-suffix match)" if how == "dated-suffix" else "")
        p("%-11s %-28s %6d %10d %10d %13d %12d  %s" % (day, model, c["msgs"], c["in"], c["out"], c["cache_read"], c["cache_write"], cost))
    p()
    p("Top %d sessions/subagents by output tokens, evaluated day %s:" % (top, totals["day"]))
    day_rows = sorted((r for r in rows if r["day"] == totals["day"]), key=lambda r: -r["out"])[:top]
    for r in day_rows:
        p("  %-8s %-8s %-22s out=%9d in=%7d cache_read=%12d msgs=%5d  %s" % (r["id"][:8], r["kind"], r["model"], r["out"], r["in"], r["cache_read"], r["msgs"], r["label"]))
    if not day_rows:
        p("  (no usage recorded for that day)")
    p()
    names = {True: "SET", False: "not set", None: "could not check"}
    p("%s (presence only, value never stored or printed): %s" % (API_KEY_NAME, ", ".join("%s=%s" % (k, names[api_key[k]]) for k in ("process", "user", "machine"))))
    p()
    day_headless = [r for r in headless_rows if r["day"] == totals["day"]]
    p("Headless drop-folder reports (F3, %s): $%.4f across %d report(s) for %s."
      % (reports_dir or "?", totals.get("headless_usd", 0.0), totals.get("headless_reports", 0), totals["day"]))
    for r in sorted(day_headless, key=lambda r: -r["cost_usd"]):
        p("  %-24s %-28s $%.4f  (costBasis=%s)" % (r["id"], r["model"], r["cost_usd"], r["cost_basis"]))
    if not day_headless:
        p("  (none)")
    p()
    p("Evaluated day %s: what-if $%.2f-$%.2f (Opus $%.2f = %.0f%%); headless (reported) $%.4f"
      % (totals["day"], totals["usd_low"], totals["usd_high"], totals["opus_usd_high"], totals["opus_share"] * 100, totals.get("headless_usd", 0.0)))
    for sev, kind, detail in breaches:
        p("  [%s] %s: %s" % (sev.upper(), kind, detail))
    p("Exit %d (%s)" % (code, STATE_NAMES[code]))


# ------------------------------------------------------------------------------------ main
def load_config(path):
    with open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
    required = (("thresholds", ("opus_whatif_alert_usd_per_day", "opus_whatif_stop_usd_per_day", "opus_share_alert_fraction",
                                "opus_share_min_day_usd", "session_output_alert_tokens", "status")),
                ("cache_multipliers", ("read", "write_5m", "write_1h", "status")))
    for section, keys in required:
        missing = [k for k in keys if k not in cfg.get(section, {})]
        if missing:
            raise ValueError("config section %r is missing %s" % (section, missing))
    return cfg


def main(argv=None, now=None, out=None, err=None, registry=_registry_has_key):
    out, err = out or sys.stdout, err or sys.stderr
    ap = argparse.ArgumentParser(description="Zero-model-call Claude Code cost monitor (what-if, not a bill).")
    ap.add_argument("--projects-dir", default=DEFAULT_PROJECTS,
                    help="Claude Code project folder to read (default: derived from where this checkout lives)")
    ap.add_argument("--state-dir", default=default_state_dir())
    ap.add_argument("--rates-file", help="test seam; default reads origin/main of the ops-policies checkout")
    ap.add_argument("--rates-repo", default=DEFAULT_RATES_REPO)
    ap.add_argument("--config", default=os.path.join(HERE, "config.json"))
    ap.add_argument("--reports-dir", default=default_reports_dir(),
                    help="Fable headless drop folder (F3 report files) to also ingest (default: %%APPDATA%%\\AEGIS\\reports)")
    ap.add_argument("--days", type=int, default=7, help="UTC days to read, ending today (default 7)")
    ap.add_argument("--day", help="UTC day to evaluate, YYYY-MM-DD (default today)")
    ap.add_argument("--top", type=int, default=10)
    ap.add_argument("--no-write", action="store_true", help="report only; touch nothing under --state-dir")
    args = ap.parse_args(argv)
    now = now or dt.datetime.now(dt.timezone.utc)
    today = now.date()
    days = max(1, args.days)
    try:
        cfg = load_config(args.config)
        rates, meta = load_rates(args.rates_file, args.rates_repo)
    except (OSError, ValueError, RatesError) as exc:
        err.write("cost-monitor: cannot start: %s%s" % (exc, NL))
        return UNKNOWN
    if not os.path.isdir(args.projects_dir):
        err.write("cost-monitor: transcripts directory not found: %s%s" % (args.projects_dir, NL))
        return UNKNOWN
    best, titles, stats = scan(args.projects_dir, today, days)
    stats["coverage"] = "project folder %s only" % os.path.basename(args.projects_dir.rstrip("/" + BS))
    if not stats["files"] and stats["unreadable"]:
        err.write("cost-monitor: every transcript file was unreadable" + NL)
        return UNKNOWN
    headless_rows, headless_findings, headless_stats = scan_headless(args.reports_dir, today, days)
    by_model, rows = aggregate(best, titles, (today - dt.timedelta(days=days - 1)).isoformat())
    if not by_model and not headless_rows:
        # Reading nothing is not the same as spending nothing: a mistyped folder or pruned transcripts
        # would otherwise report "ok" and look like a quiet week.
        err.write("cost-monitor: no usage found in %d file(s) over the last %d day(s); refusing to report ok%s" % (stats["files"], days, NL))
        return UNKNOWN
    api_key = check_api_key(registry=registry)
    code, breaches, totals = evaluate(args.day or today.isoformat(), by_model, rows, rates, cfg, api_key,
                                      headless_rows=headless_rows, headless_findings=headless_findings)
    if not any(r["day"] == totals["day"] for r in rows) and not any(r["day"] == totals["day"] for r in headless_rows):
        # A day with no data is a quiet day only if we could have seen its data. Files we could not
        # read, or a newest transcript that stopped growing, mean it may be a blind spot instead.
        why = []
        if stats["unreadable"]:
            why.append("%d transcript file(s) could not be read" % stats["unreadable"])
        newest = stats["newest_mtime"]
        if newest is None or newest < (now - dt.timedelta(hours=STALE_HOURS)).timestamp():
            why.append("the newest transcript is more than %d hours old" % STALE_HOURS)
        if why:
            detail = "no usage recorded for %s, and %s; this may be a blind spot, not a quiet day" % (totals["day"], " and ".join(why))
            breaches.append(("unknown", "no_data_for_day", detail))
            err.write("cost-monitor: " + detail + NL)
            if code == OK:
                code = UNKNOWN
    report(out, by_model, rows, rates, meta, cfg, stats, totals, breaches, api_key, code, args.top,
           headless_rows=headless_rows, reports_dir=args.reports_dir)
    if not args.no_write:
        try:
            wrote = write_ledger(args.state_dir, by_model, rows, rates, meta, cfg, now, headless_rows=headless_rows)
            write_status(args.state_dir, code, breaches, totals, api_key, meta, cfg, stats, now)
        except OSError as exc:
            err.write("cost-monitor: cannot write under %s: %s%s" % (args.state_dir, exc, NL))
            return UNKNOWN
        out.write("Ledger: %d day file(s) appended under %s; status.json refreshed.%s" % (len(wrote), args.state_dir, NL))
    return code


if __name__ == "__main__":
    sys.exit(main())
