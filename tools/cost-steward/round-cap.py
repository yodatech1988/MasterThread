"""round-cap: spend of a named set of sessions (main + subagent transcripts) since a start time,
against a per-round cap. Reuses cost-steward.py's prices. Read-only apart from its state file.

  python round-cap.py ROUND START_ISO CAP "Name1,Name2,..."          one reading
  python round-cap.py ROUND START_ISO CAP "Name1,..." --watch N      print on 80% / 100% / each +$5
"""
import glob, importlib.util, json, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("cs", os.path.join(HERE, "cost-steward.py"))
cs = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(cs)
HOME = cs.HOME


def sessions_by_name(names):
    out = {}
    for f in glob.glob(os.path.join(HOME, ".claude", "sessions", "*.json")):
        try:
            r = json.load(open(f, encoding="utf8"))
        except (OSError, ValueError):
            continue
        if r.get("name") in names:
            out[r["name"]] = r["sessionId"]
    return out


def transcripts(sid):
    base = glob.glob(os.path.join(HOME, ".claude", "projects", "*", sid + ".jsonl"))
    subs = glob.glob(os.path.join(HOME, ".claude", "projects", "*", sid, "**", "*.jsonl"), recursive=True)
    return base + subs


def spend(path, start):
    seen = {}
    try:
        for line in open(path, encoding="utf8", errors="replace"):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            m = d.get("message")
            if d.get("type") != "assistant" or not isinstance(m, dict) or not m.get("usage"):
                continue
            if (d.get("timestamp") or "") < start:
                continue
            seen[m.get("id") or len(seen)] = (m.get("model"), m["usage"])
    except OSError:
        return 0.0
    cost = 0.0
    for mdl, u in seen.values():
        p = cs.price(mdl)
        if not p:
            continue
        cc = u.get("cache_creation") or {}
        w1h = cc.get("ephemeral_1h_input_tokens", u.get("cache_creation_input_tokens", 0))
        w5m = cc.get("ephemeral_5m_input_tokens", 0)
        cost += (u.get("input_tokens", 0) * p[0] + u.get("output_tokens", 0) * p[1] + w1h * p[2]
                 + w5m * p[3] + u.get("cache_read_input_tokens", 0) * p[4]) / 1e6
    return cost


def reading(names, start):
    ids = sessions_by_name(names)
    per = {n: sum(spend(t, start) for t in transcripts(s)) for n, s in ids.items()}
    missing = [n for n in names if n not in ids]
    # Headless `claude -p` runs get their own session and exit, so they are in no live registry
    # entry. Count any transcript touched since the round began that no live session owns
    # (conservative: an unrelated session that ended mid-round is counted too).
    live = set()
    for f in glob.glob(os.path.join(HOME, ".claude", "sessions", "*.json")):
        try:
            live.add(json.load(open(f, encoding="utf8"))["sessionId"])
        except (OSError, ValueError, KeyError):
            pass
    t0 = time.mktime(time.strptime(start[:19], "%Y-%m-%dT%H:%M:%S")) - time.timezone
    head = 0.0
    for p in glob.glob(os.path.join(HOME, ".claude", "projects", "*", "*.jsonl")):
        sid = os.path.basename(p)[:-6]
        try:
            if sid in live or os.path.getmtime(p) < t0:
                continue
        except OSError:
            continue
        head += sum(spend(t, start) for t in [p] + glob.glob(os.path.join(os.path.dirname(p), sid, "**", "*.jsonl"), recursive=True))
    if head:
        per["headless/ended"] = head
    return per, missing


def line(rnd, cap, per, missing):
    tot = sum(per.values())
    parts = "  ".join(f"{n} ${v:.2f}" for n, v in sorted(per.items(), key=lambda x: -x[1]))
    miss = f"  NOT FOUND: {','.join(missing)}" if missing else ""
    return f"ROUND {rnd} ${tot:.2f} of ${cap:.2f} ({tot / cap:.0%})  {parts}{miss}", tot


if __name__ == "__main__":
    rnd, start, cap, names = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4].split(",")
    if len(sys.argv) > 6 and sys.argv[5] == "--watch":
        every, step = int(sys.argv[6]), 5.0
        state = os.path.join(HERE, f"round-cap.{rnd}.state.json")
        try:
            last = json.load(open(state))
        except (OSError, ValueError):
            last = {"band": -1, "alert80": False, "alert100": False}
        while True:
            per, missing = reading(names, start)
            msg, tot = line(rnd, cap, per, missing)
            band = int(tot // step)
            if tot >= cap and not last["alert100"]:
                print("ROUND-CAP HALT " + msg, flush=True); last["alert100"] = True
            elif tot >= 0.8 * cap and not last["alert80"]:
                print("ROUND-CAP 80% " + msg, flush=True); last["alert80"] = True
            elif band > last["band"]:
                print("ROUND-CAP " + msg, flush=True)
            last["band"] = max(band, last["band"])
            try:
                with open(state, "w") as f:
                    json.dump(last, f)
            except OSError:
                pass
            time.sleep(every)
    else:
        print(line(rnd, cap, *reading(names, start))[0])
