"""compactions.py: extract compact_boundary events from Claude Code transcripts,
with before/after behavioral-signal rates for a later priority/size join.

Read-only. Scans ~/.claude/projects/**/*.jsonl. Never prints or stores transcript
text -- only numbers and ids (session id, boundary uuid prefix, model name, counts).

  python compactions.py                 print a summary table
  python compactions.py --json OUT.json write rows as a JSON list
  python compactions.py --since ISO     only compactions at/after this timestamp

Row shape: id, session, timestamp, model, trigger, pre_tokens, post_tokens,
reread_before/after, correction_before/after, tool_error_before/after,
turns_before/after, priority (null), size (null). Rates are per assistant turn
over a window of N=20 assistant turns on each side, within the same session.
"""
import json, os, sys, glob, re

ROOT = os.path.join(os.path.expanduser("~"), ".claude", "projects")
N_WINDOW = 20

CORRECTION_PATTERNS = [
    re.compile(r"\bno\b", re.I),
    re.compile(r"\bwrong\b", re.I),
    re.compile(r"that'?s not", re.I),
    re.compile(r"\bi said\b", re.I),
    re.compile(r"\bagain\b", re.I),
    re.compile(r"\bstop\b", re.I),
    re.compile(r"\brevert\b", re.I),
    re.compile(r"\bundo\b", re.I),
]


def get_text(content):
    """Concatenate text blocks for pattern matching only; never returned/printed raw."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(block.get("text", ""))
        return " ".join(parts)
    return ""


def analyze_file(path):
    """One pass over a transcript. Returns (session_id, events, boundaries).

    events: list of dicts tagged with turn_idx (assistant-turn counter):
      assistant_turn, read (with is_reread), tool_result (with is_error),
      user_correction_msg
    boundaries: list of dicts with turn_idx, uuid, timestamp, trigger,
      pre_tokens, post_tokens, model (nearest preceding assistant model)
    """
    events = []
    boundaries = []
    turn_idx = 0
    read_files_seen = set()
    tool_use_index = {}
    session_id = None
    last_model = None

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                continue

            if session_id is None:
                sid = entry.get("sessionId")
                if sid:
                    session_id = sid

            etype = entry.get("type")

            if etype == "system" and entry.get("subtype") == "compact_boundary":
                cm = entry.get("compactMetadata") or {}
                boundaries.append({
                    "turn_idx": turn_idx,
                    "uuid": entry.get("uuid"),
                    "timestamp": entry.get("timestamp"),
                    "trigger": cm.get("trigger"),
                    "pre_tokens": cm.get("preTokens"),
                    "post_tokens": cm.get("postTokens"),
                    "model": last_model,
                })
                continue

            msg = entry.get("message") if isinstance(entry, dict) else None

            if etype == "assistant" and isinstance(msg, dict):
                turn_idx += 1
                model = msg.get("model")
                if model:
                    last_model = model
                events.append({"kind": "assistant_turn", "turn_idx": turn_idx})
                content = msg.get("content")
                if isinstance(content, list):
                    for block in content:
                        if isinstance(block, dict) and block.get("type") == "tool_use":
                            tool_use_index[block.get("id")] = {"name": block.get("name")}
                            if block.get("name") == "Read":
                                fp = (block.get("input") or {}).get("file_path")
                                if fp:
                                    events.append({
                                        "kind": "read",
                                        "turn_idx": turn_idx,
                                        "is_reread": fp in read_files_seen,
                                    })
                                    read_files_seen.add(fp)

            elif etype == "user" and isinstance(msg, dict):
                content = msg.get("content")
                if isinstance(content, list):
                    has_tool_result = False
                    for block in content:
                        if isinstance(block, dict) and block.get("type") == "tool_result":
                            has_tool_result = True
                            events.append({
                                "kind": "tool_result",
                                "turn_idx": turn_idx,
                                "is_error": bool(block.get("is_error")),
                            })
                    if not has_tool_result:
                        txt = get_text(content)
                        if txt and any(p.search(txt) for p in CORRECTION_PATTERNS):
                            events.append({"kind": "user_correction_msg", "turn_idx": turn_idx})
                elif isinstance(content, str):
                    if content and any(p.search(content) for p in CORRECTION_PATTERNS):
                        events.append({"kind": "user_correction_msg", "turn_idx": turn_idx})

    return session_id, events, boundaries


def window_rate(events, boundary_turn, n, side, kind, pred=lambda e: True):
    if side == "before":
        lo, hi = boundary_turn - n, boundary_turn
    else:
        lo, hi = boundary_turn, boundary_turn + n
    count = 0
    for ev in events:
        t = ev["turn_idx"]
        if lo < t <= hi and ev["kind"] == kind and pred(ev):
            count += 1
    n_turns = sum(1 for ev in events if ev["kind"] == "assistant_turn" and lo < ev["turn_idx"] <= hi)
    return count, n_turns, (count / n_turns if n_turns else 0.0)


def scan(since=None):
    rows = []
    files = glob.glob(os.path.join(ROOT, "**", "*.jsonl"), recursive=True)
    for path in files:
        try:
            os.path.getsize(path)
        except OSError:
            continue
        try:
            session_id, events, boundaries = analyze_file(path)
        except OSError:
            continue
        if not boundaries:
            continue
        for b in boundaries:
            ts = b.get("timestamp")
            if since and (not ts or ts < since):
                continue
            bt = b["turn_idx"]
            reread_b_n, turns_b, reread_b = window_rate(events, bt, N_WINDOW, "before", "read", lambda e: e.get("is_reread"))
            reread_a_n, turns_a, reread_a = window_rate(events, bt, N_WINDOW, "after", "read", lambda e: e.get("is_reread"))
            corr_b_n, _, corr_b = window_rate(events, bt, N_WINDOW, "before", "user_correction_msg")
            corr_a_n, _, corr_a = window_rate(events, bt, N_WINDOW, "after", "user_correction_msg")
            err_b_n, _, err_b = window_rate(events, bt, N_WINDOW, "before", "tool_result", lambda e: e.get("is_error"))
            err_a_n, _, err_a = window_rate(events, bt, N_WINDOW, "after", "tool_result", lambda e: e.get("is_error"))
            uuid = b.get("uuid") or ""
            rows.append({
                "id": f"{session_id}-{uuid[:8]}",
                "session": session_id,
                "timestamp": ts,
                "model": b.get("model"),
                "trigger": b.get("trigger"),
                "pre_tokens": b.get("pre_tokens"),
                "post_tokens": b.get("post_tokens"),
                "reread_before": reread_b,
                "reread_after": reread_a,
                "correction_before": corr_b,
                "correction_after": corr_a,
                "tool_error_before": err_b,
                "tool_error_after": err_a,
                "turns_before": turns_b,
                "turns_after": turns_a,
                "priority": None,
                "size": None,
            })
    return rows


def mean(vals):
    vals = [v for v in vals if v is not None]
    return sum(vals) / len(vals) if vals else None


def print_summary(rows):
    print(f"{len(rows)} compaction events")
    print(f"{'id':<45} {'trigger':<10} {'pre':>8} {'post':>8} {'model':<20} "
          f"{'rrB':>5} {'rrA':>5} {'corB':>5} {'corA':>5} {'errB':>5} {'errA':>5}")
    for r in rows:
        print(f"{r['id']:<45} {str(r['trigger']):<10} {str(r['pre_tokens']):>8} {str(r['post_tokens']):>8} "
              f"{str(r['model']):<20} {r['reread_before']:.2f} {r['reread_after']:.2f} "
              f"{r['correction_before']:.2f} {r['correction_after']:.2f} "
              f"{r['tool_error_before']:.2f} {r['tool_error_after']:.2f}")
    print()
    print(f"mean reread_rate: before={mean([r['reread_before'] for r in rows]):.3f} "
          f"after={mean([r['reread_after'] for r in rows]):.3f}")
    print(f"mean correction_rate: before={mean([r['correction_before'] for r in rows]):.3f} "
          f"after={mean([r['correction_after'] for r in rows]):.3f}")
    print(f"mean tool_error_rate: before={mean([r['tool_error_before'] for r in rows]):.3f} "
          f"after={mean([r['tool_error_after'] for r in rows]):.3f}")


def main():
    args = sys.argv[1:]
    since = None
    json_out = None
    i = 0
    while i < len(args):
        if args[i] == "--since" and i + 1 < len(args):
            since = args[i + 1]
            i += 2
        elif args[i] == "--json" and i + 1 < len(args):
            json_out = args[i + 1]
            i += 2
        else:
            i += 1

    rows = scan(since=since)

    if json_out:
        with open(json_out, "w", encoding="utf-8") as f:
            json.dump(rows, f, indent=2)
        print(f"wrote {len(rows)} rows to {json_out}")
    else:
        print_summary(rows)


if __name__ == "__main__":
    main()
