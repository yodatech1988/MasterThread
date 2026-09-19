#!/usr/bin/env python3
"""Report-only audit of the Ops Decision Queue's `decisions` collection.

Usage:  python dq_monitor.py <dir-of-exported-card-json>

Input is a directory of one JSON file per card, the shape ArtifactData's `out_dir` export writes
(each file is the card, or `{"data": <card>}`; the file name minus `.json` is the card's doc id).
Export first (ArtifactData `list` with `out_dir`) and pass that directory; this script never talks
to the artifact or the network.

It only READS and PRINTS. It writes nothing, resolves nothing, reopens nothing and files nothing.
Per standards/sessions/decision_queue_standard.md ("Auditing the board"), what it reports is for a
human or the PM to act on: report a suspect card, never reopen it, under any signature.

Sections:
  A  open, owner-required cards, oldest first
  B  claimed by the owner but not yet verified/closed
  C  resolved with followUpPending (work still outstanding)
  D  resolutions whose `resolvedAt` has no milliseconds (session-written, not the page)
  E  hygiene: action cards without executabilityCheck, cards without kind, options without
     recommendedOption, action cards still `not-checked`, stamp drift (resolvedAt < createdAt)
"""
import datetime as dt
import glob
import json
import os
import re
import sys

# The page stamps `resolvedAt` with milliseconds ("...T22:09:27.260Z") when the owner clicks;
# a session composing a stamp writes whole seconds ("...T18:30:00Z"). Measured 2026-09-17 across
# 114 resolved cards the separation was total. See decision_queue_standard.md, "The discriminator
# that works: milliseconds". This says who WROTE the stamp; it is not proof anything is wrong,
# and a resolution echoing options[recommendedOption] is NOT evidence of a defect.
PAGE_WRITTEN_STAMP = re.compile(r"\.\d{3}Z$")


def parse_ts(s):
    try:
        return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def load_cards(directory):
    rows = []
    for f in glob.glob(os.path.join(directory, "*.json")):
        with open(f, encoding="utf-8") as fh:
            j = json.load(fh)
        j = j.get("data", j)
        j["_id"] = os.path.basename(f)[:-5]
        rows.append(j)
    return rows


def age_hours(card, now, key="createdAt"):
    t = parse_ts(card.get(key) or "")
    return (now - t).total_seconds() / 3600 if t else None


def is_session_written(card):
    """Resolved card whose resolvedAt lacks milliseconds (i.e. not written by the page)."""
    r = card.get("resolvedAt") or ""
    return card.get("status") == "resolved" and bool(r) and not PAGE_WRITTEN_STAMP.search(r)


def report(rows, now):
    out = []
    op = [j for j in rows if j.get("status") != "resolved"]
    out.append(f"total {len(rows)} open {len(op)} resolved {len(rows) - len(op)}")

    out.append("\n[A] open, owner-required, oldest first (age h):")
    for j in sorted(op, key=lambda j: -(age_hours(j, now) or 0))[:12]:
        if j.get("ownerRequired"):
            out.append(f"  {age_hours(j, now) or -1:5.1f}h {j.get('kind', '?'):8} {j['_id']}")

    out.append("\n[B] claimed by owner, not verified/closed:")
    for j in op:
        if j.get("claimedAt") and not j.get("verifiedAt"):
            out.append(f"  {j['_id']} | claimComment={str(j.get('claimComment'))[:60]!r} | "
                       f"checkResult={str(j.get('checkResult'))[:40]!r}")

    out.append("\n[C] resolved with followUpPending (real work still outstanding):")
    for j in rows:
        if j.get("status") == "resolved" and j.get("followUpPending"):
            out.append(f"  {j['_id']} | {str(j.get('followUpNote'))[:70]}")

    out.append("\n[D] session-written resolutions (whole-second resolvedAt, standard says report, never reopen):")
    n = sum(1 for j in rows if is_session_written(j))
    out.append(f"  count {n} of {sum(1 for j in rows if j.get('status') == 'resolved')}")

    out.append("\n[E] hygiene: action cards missing executabilityCheck / cards missing kind / "
               "options without recommendedOption:")
    out.append("  action no executabilityCheck: " + str(
        [j["_id"] for j in rows if j.get("kind") == "action" and j.get("status") != "resolved"
         and not j.get("executabilityCheck")][:8]))
    out.append(f"  no kind: {len([j for j in op if not j.get('kind')])} | options w/o recommendedOption: "
               f"{len([j for j in op if j.get('options') and j.get('recommendedOption') is None])}")
    out.append("  action executabilityCheck == not-checked (PM should hold relay): " + str(
        [j["_id"] for j in op if j.get("executabilityCheck") == "not-checked"][:8]))
    drift = [j for j in rows if parse_ts(j.get("resolvedAt") or "") and parse_ts(j.get("createdAt") or "")
             and parse_ts(j["resolvedAt"]) < parse_ts(j["createdAt"])]
    out.append(f"  resolvedAt < createdAt (stamp drift): {len(drift)}")
    return out


def main(argv):
    if len(argv) != 2 or not os.path.isdir(argv[1]):
        print(__doc__)
        return 2
    print("\n".join(report(load_cards(argv[1]), dt.datetime.now(dt.timezone.utc))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
