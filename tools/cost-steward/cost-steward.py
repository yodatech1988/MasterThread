"""cost-steward: read-only context/cost meter for live Claude Code sessions on this PC.

Reads ~/.claude/sessions/*.json (live session registry) and each session's transcript
jsonl, and reports context size, API-equivalent spend and the next-turn cost at list
prices. Writes nothing except its own state file (for --watch change detection).

  python cost-steward.py            one table, all live sessions
  python cost-steward.py --watch N  loop every N seconds, print only when a session's
                                    advice level changes (for a Monitor)
Prices: USD per MTok, claude.com/pricing read 2026-09-22; 1h cache write = 2x input.
"""
import json, os, sys, time, glob

HOME = os.path.expanduser("~")
PRICES = {  # input, output, cache_write_1h, cache_write_5m, cache_read
    "claude-fable-5-1": (10, 50, 20, 12.5, 0.25), "claude-fable-5": (10, 50, 20, 12.5, 0.25),
    "claude-opus-5": (5, 25, 10, 6.25, 0.5), "claude-opus-4-8": (5, 25, 10, 6.25, 0.5),
    "claude-sonnet-5": (2, 10, 4, 2.5, 0.2), "claude-haiku-4-5": (1, 5, 2, 1.25, 0.1),
}
# Advice thresholds (default pending owner confirmation; recalibrate from real data).
WARN_CTX, COMPACT_CTX, URGENT_CTX = 150_000, 250_000, 400_000
CACHE_TTL_S = 3600  # 1h cache: an idle session past this re-writes its whole context
STATE = os.path.join(os.environ.get("APPDATA", HOME), "AEGIS", "cost-steward.state.json")


def price(model):
    m = model or ""
    for k, v in PRICES.items():
        if m.startswith(k):
            return v
    return None


def alive(pid):
    try:
        import ctypes
        h = ctypes.windll.kernel32.OpenProcess(0x1000, False, pid)
        if not h:
            return False
        code = ctypes.c_ulong()
        ctypes.windll.kernel32.GetExitCodeProcess(h, ctypes.byref(code))
        ctypes.windll.kernel32.CloseHandle(h)
        return code.value == 259
    except Exception:
        return True


def scan(reg):
    paths = glob.glob(os.path.join(HOME, ".claude", "projects", "*", reg["sessionId"] + ".jsonl"))
    if not paths:
        return None
    seen, cost, last, last_t, model, compactions = {}, 0.0, None, None, None, 0
    for line in open(paths[0], encoding="utf8", errors="replace"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("type") == "system" and d.get("subtype") == "compact_boundary":
            compactions += 1
        m = d.get("message")
        if d.get("type") != "assistant" or not isinstance(m, dict) or not m.get("usage"):
            continue
        seen[m.get("id") or len(seen)] = (m.get("model"), m["usage"])  # last line per message id wins
        last, model, last_t = m["usage"], m.get("model"), d.get("timestamp")
    for mdl, u in seen.values():
        p = price(mdl)
        if not p:
            continue
        cc = u.get("cache_creation") or {}
        w1h = cc.get("ephemeral_1h_input_tokens", u.get("cache_creation_input_tokens", 0))
        w5m = cc.get("ephemeral_5m_input_tokens", 0)
        cost += (u.get("input_tokens", 0) * p[0] + u.get("output_tokens", 0) * p[1] + w1h * p[2]
                 + w5m * p[3] + u.get("cache_read_input_tokens", 0) * p[4]) / 1e6
    if not last:
        return None
    ctx = last.get("input_tokens", 0) + last.get("cache_read_input_tokens", 0) + last.get("cache_creation_input_tokens", 0)
    p = price(model) or (0, 0, 0, 0, 0)
    idle = None
    if last_t:
        try:
            import calendar
            idle = time.time() - calendar.timegm(time.strptime(last_t[:19], "%Y-%m-%dT%H:%M:%S"))
        except ValueError:
            pass
    warm_turn = ctx * p[4] / 1e6          # next turn if cache is warm
    cold_turn = ctx * p[2] / 1e6          # next turn if the 1h cache has expired
    if ctx >= URGENT_CTX:
        level = "COMPACT-NOW"
    elif ctx >= COMPACT_CTX:
        level = "COMPACT"
    elif ctx >= WARN_CTX:
        level = "WATCH"
    else:
        level = "OK"
    if idle is not None and idle > CACHE_TTL_S * 0.8 and ctx >= WARN_CTX and level in ("WATCH", "COMPACT"):
        level = "COMPACT-BEFORE-RESUME"
    return dict(name=reg.get("name"), status=reg.get("status"), model=model, ctx=ctx, cost=cost,
                turns=len(seen), compactions=compactions, idle=idle, warm=warm_turn, cold=cold_turn, level=level)


def rows():
    out = []
    for f in glob.glob(os.path.join(HOME, ".claude", "sessions", "*.json")):
        try:
            reg = json.load(open(f, encoding="utf8"))
        except (ValueError, OSError):
            continue
        if not alive(reg.get("pid", 0)):
            continue
        r = scan(reg)
        if r:
            out.append(r)
    return sorted(out, key=lambda r: -r["ctx"])


def fmt(r):
    idle = "?" if r["idle"] is None else f"{int(r['idle'] // 60)}m"
    return (f"{r['name']:<10} {r['level']:<22} ctx {r['ctx'] / 1000:>6.0f}k  {(r['model'] or '?'):<16} "
            f"spent ${r['cost']:>7.2f}  next turn ${r['warm']:.3f} warm / ${r['cold']:.2f} cold  "
            f"idle {idle:>4}  turns {r['turns']}  compactions {r['compactions']}  [{r['status']}]")


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--watch":
        every = int(sys.argv[2])
        while True:
            try:
                prev = json.load(open(STATE))
            except (OSError, ValueError):
                prev = {}
            cur = {}
            for r in rows():
                cur[r["name"]] = r["level"]
                if prev.get(r["name"]) != r["level"] and r["level"] != "OK":
                    print("COST-STEWARD " + fmt(r), flush=True)
            json.dump(cur, open(STATE, "w"))
            time.sleep(every)
    else:
        rs = rows()
        print(f"{len(rs)} live sessions  total spent ${sum(r['cost'] for r in rs):.2f} (API-equivalent, list prices)")
        for r in rs:
            print(fmt(r))
