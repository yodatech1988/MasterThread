"""console-cost: build the Fable Ops Console `state/cost` doc from exported Execution Board
rounds/runs (ArtifactData out_dir export) plus the live meter. Writes only the output JSON file;
the cost steward then writes that file to the Console db with ArtifactData.

  python console-cost.py EXPORT_DIR OUT_JSON
EXPORT_DIR holds rounds/*.json and runs/*.json as ArtifactData's out_dir saves them.
"""
import glob, importlib.util, json, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("cs", os.path.join(HERE, "cost-steward.py"))
cs = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(cs)

exp, out = sys.argv[1], sys.argv[2]
now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
today = now[:10]

def load(sub):
    docs = {}
    for p in glob.glob(os.path.join(exp, sub, "*.json")):
        d = json.load(open(p, encoding="utf8"))
        docs[os.path.basename(p)[:-5]] = d.get("data", d)
    return docs

rounds, runs = load("rounds"), load("runs")
named = set()
attributed = {}
rlist, rounds_usd, today_usd = [], 0.0, 0.0
for rid, r in sorted(rounds.items(), key=lambda kv: kv[1].get("start", "")):
    usd = float(r.get("spentUSD") or 0)
    rounds_usd += usd
    if (r.get("start") or "")[:10] == today:
        today_usd += usd
    rlist.append({"name": rid, "usd": round(usd, 2), "state": "open" if r.get("status") == "open" else "closed"})
    for k in ("members", "meterMembers"):
        # members may be session names (strings) or the PM's lane objects; only strings name a session
        named.update(m for m in (r.get(k) or []) if isinstance(m, str))
    for k in ("bySession", "byMember"):
        v = r.get(k)
        if isinstance(v, dict):
            named.update(v.keys())
            for n, c in v.items():
                try: attributed[n] = attributed.get(n, 0.0) + float(c or 0)
                except (TypeError, ValueError): pass

# headless runs not charged to any round
unrounded_runs = [(k, float(v.get("costUSD") or 0)) for k, v in runs.items() if not v.get("round")]
runs_usd = sum(u for _, u in unrounded_runs)
today_usd += sum(u for k, u in unrounded_runs if (runs[k].get("at") or k)[:10] == today)

# live sessions: a session no round has named contributes its whole meter spend; a session some
# round HAS named contributes only the remainder above what the rounds' bySession lines already
# charged it (its spend outside every round window), so nothing is dropped or counted twice.
live = []
for r in cs.rows():
    n, c = r["name"], float(r["cost"] or 0)
    if n in named:
        rem = c - attributed.get(n, 0.0)
        if rem > 0.005:
            live.append((n + " (outside rounds)", rem))
    else:
        live.append((n, c))
live_usd = sum(c for _, c in live)
today_usd += live_usd  # every live session on this PC started today (2026-09-22); revisit if not

total = rounds_usd + runs_usd + live_usd
doc = {
    "totalUsd": round(total, 2),
    "since": min((r.get("start") for r in rounds.values() if r.get("start")), default=today),
    "scope": "Fable project (MasterThread rounds + headless runs + seat sessions)",
    "rounds": rlist,
    "todayUsd": round(today_usd, 2),
    "updatedAt": now,
    "source": "cost-steward.py + Execution Board rounds/runs",
    "breakdown": {"roundsUsd": round(rounds_usd, 2), "unroundedRunsUsd": round(runs_usd, 2),
                   "liveSessionsNotInAnyRoundUsd": round(live_usd, 2),
                   "liveSessionsNotInAnyRound": [{"name": n, "usd": round(c, 2)} for n, c in live]},
    "basis": "API-equivalent at claude.com list prices, subagents included. Rounds carry their own spentUSD (runs charged inside a round are not re-added). A live session some round has named is counted through those rounds plus its remainder above what they charged it, shown as '<name> (outside rounds)'; a session no round has named contributes its whole meter spend. Estimate, not a bill; subscription marginal cost is $0.",
}
# Machine-wide day what-if from the F8 ledger (tools/cost-monitor on origin/main, read-only), a second
# scope beside the project total: every transcript in this project folder today, all sessions, all models.
def machine_day():
    import re, subprocess
    # scratch outside the repo checkout: writing under tools/ leaves untracked files that trip the
    # session-stop git check (seat finding on PR #219)
    import tempfile
    cm = os.path.join(tempfile.gettempdir(), "console-cost", "cost-monitor")
    os.makedirs(cm, exist_ok=True)
    repo = "C:/Users/yoda_/GitHub/MasterThread"
    # refresh the ref first: origin/main is only as fresh as the last fetch (found 18:25Z: a stale ref
    # ran the pre-#217 ledger for two minutes after the merge)
    subprocess.run(["git", "-C", repo, "fetch", "-q", "origin", "main"], capture_output=True, timeout=60)
    for f in ("cost_monitor.py", "config.json"):
        src = subprocess.run(["git", "-C", repo, "show", f"origin/main:tools/cost-monitor/{f}"],
                             capture_output=True, text=True, encoding="utf-8")
        if src.returncode != 0:
            return {"error": "could not read tools/cost-monitor from origin/main"}
        open(os.path.join(cm, f), "w", encoding="utf-8").write(src.stdout)
    r = subprocess.run([sys.executable, os.path.join(cm, "cost_monitor.py"), "--no-write", "--days", "1",
                        "--config", os.path.join(cm, "config.json"), "--state-dir", os.path.join(cm, "state"),
                        "--projects-dir", os.path.expanduser("~/.claude/projects/C--Users-yoda-")],
                       capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=300)
    m = re.search(r"Evaluated day (\S+): what-if \$([\d.]+)-\$([\d.]+) \((\S+) \$([\d.]+) = (\d+)%\)(?:; headless \(reported\) \$([\d.]+))?", r.stdout)
    if not m:
        return {"error": "cost_monitor.py output not parsed", "tail": r.stdout[-300:] + r.stderr[-300:]}
    return {"day": m.group(1), "usdLow": float(m.group(2)), "usdHigh": float(m.group(3)),
            "topModel": m.group(4), "topModelUsd": float(m.group(5)), "topModelPct": int(m.group(6)),
            "headlessReportedUsd": float(m.group(7)) if m.group(7) else None,
            "scope": "every transcript under ~/.claude/projects/C--Users-yoda- for the UTC day, all sessions and models, not only Fable project work",
            "source": "tools/cost-monitor/cost_monitor.py on origin/main (F8 ledger), --no-write"}
# L1 pilot spend from the drop folder. Scheduled pilot reports are NDJSON transcripts, not the
# {envelope,...} wrapper (Run-L1Pilot.ps1 omits -Report), so the ledger skips them; the stream's
# final "result" object still carries total_cost_usd with costBasis list, and that is read here.
def l1_pilot():
    import re
    R = os.path.expandvars(r"%APPDATA%/AEGIS/reports")
    byday, uncosted, models = {}, [], set()
    for f in sorted(glob.glob(R + "/*.json")):
        txt = open(f, encoding="utf-8", errors="replace").read()
        e = None
        try:
            d = json.loads(txt, strict=False); e = d.get("envelope") or d
        except Exception:
            for l in reversed(txt.splitlines()):
                l = l.strip()
                if not l: continue
                try: o = json.loads(l, strict=False)
                except Exception: continue
                if o.get("type") == "result": e = o; break
        b = os.path.basename(f); m = re.search(r"\.(\d{4})(\d{2})(\d{2})-", b)
        day = f"{m.group(1)}-{m.group(2)}-{m.group(3)}" if m else "?"
        if e and e.get("total_cost_usd") is not None:
            byday[day] = byday.get(day, 0.0) + float(e["total_cost_usd"])
            for k, v in (e.get("modelUsage") or {}).items(): models.add(f"{k}:{v.get('costBasis')}")
        else:
            uncosted.append(b)
    return {"todayUsd": round(byday.get(today, 0.0), 4), "sinceUsd": round(sum(byday.values()), 4),
            "since": min(byday) if byday else None, "byDay": {d: round(c, 4) for d, c in sorted(byday.items())},
            "costedReports": sum(1 for _ in glob.glob(R + "/*.json")) - len(uncosted), "uncostedReports": uncosted,
            "basis": "total_cost_usd from each report's envelope, or from the final result object of an NDJSON transcript when the wrapper is missing; costBasis list on every costed report; not inside totalUsd (pilot is not a Fable project round)",
            "models": sorted(models)}
try:
    doc["l1Pilot"] = l1_pilot()
except Exception as e:
    doc["l1Pilot"] = {"error": f"{type(e).__name__}: {e}"[:200]}
try:
    doc["machineDayWhatIf"] = machine_day()
except Exception as e:  # never let the second scope break the first
    doc["machineDayWhatIf"] = {"error": f"{type(e).__name__}: {e}"[:200]}
json.dump(doc, open(out, "w", encoding="utf-8"), indent=1)
print(f"total ${total:.2f}  rounds ${rounds_usd:.2f}  unrounded runs ${runs_usd:.2f}  live-unrounded ${live_usd:.2f} {[n for n,_ in live]}  today ${today_usd:.2f}")
