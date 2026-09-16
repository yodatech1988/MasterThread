---
name: round-closeout
description: Use at the end of an orchestrator/PM round (a usage-tier 97/98/99 order, or a natural stopping point) to write the next SESSION_HANDOFF file, refresh stale notes, and hand off the next session's launch prompt.
---

# round-closeout

## When to use this

- The round has reached a natural end (every lane's PR merged or closed, per
  `session_plan_standard.md`'s round definition), or
- The usage watcher has hit tier 97 ("Document") or later — this skill's write-up is exactly what
  that tier requires — or
- A session is rotating per the owner's PM-handoff convention (heavily compacted context, many
  hours active, or workstream naturally complete).

## Procedure

1. **Write the next `GitHub\SESSION_HANDOFF_<date>-<topic>.md`**, in the same done/verified/
   next-step/pending-decisions shape the existing files already use (see the newest one under
   `GitHub\` for the current convention before writing a new one — don't invent a new shape).
   Cover, for every lane touched this round:
   - **Done** — merged PRs, landed changes, verified with `git merge-base --is-ancestor` where a
     stacked merge was involved (per `land-pr`).
   - **Verified** — what was actually confirmed (tests run, diffs read, live state checked) vs.
     claimed.
   - **Next step** — the exact next action per lane/repo, concrete enough that a fresh session
     doesn't need to re-derive it.
   - **Pending owner decisions** — anything still waiting on Jeremy, each with the default in force
     until he answers (`session_plan_standard.md` rule 7).
   - If a lane paused mid-round, note how its actual size compared to its `task_sizing.md` estimate
     (tool-call count, or "needed a second reboot round") — this is the calibration data
     `task_sizing.md`'s bands are built from.

2. **Refresh stale memory-equivalent notes.** Check whether anything this round changed a fact that
   a memory note, `docs/REPOS.md` row, or `docs/AGENTS.md` row currently asserts differently, and
   correct it in the same close-out — a stale ledger is exactly what forces the next round's
   `round-start` to re-verify everything against live `gh` state instead of trusting the doc.

3. **Check `docs/LESSONS.md` for anything seen twice.** If this round (or the handoff you just
   wrote) repeats a false-assumption-or-rule-candidate that already appears once in
   `docs/LESSONS.md`, promote it now — add it to the relevant skill's Never-list or to a standards
   doc — per that file's promotion rule, rather than leaving it to accumulate a third time.

4. **Emit the next-session launch prompt(s)**, one per lane/repo that should resume, each headed
   with its model and effort row from `orchestrator_role.md`'s table (row 1 Opus/high ... row 5
   Haiku/low) — never leave the next session to guess its own model.

5. **Stop the usage watcher** (`TaskStop`) so it deregisters, once the handoff is written and
   pushed. Don't leave a stale registration for the next round's peer-detection to trip over.

## Never

- Never close out a round without a written `SESSION_HANDOFF_*.md` — "I'll just remember" or
  relying on conversation history is exactly the anti-pattern `session_plan_standard.md` exists to
  stop (a session's history isn't read by anyone else).
- Never claim a test/validator "passed" in the handoff if it wasn't actually run this round —
  report real counts or mark it pending (`worker_role.md` "Tests and validators").
- Never leave a lesson that's already been seen once sitting unpromoted a second time — that's the
  whole point of the seen-twice rule in `docs/LESSONS.md`.
- Never hand off a next-session prompt without a model/effort row — that's how a cheap task
  accidentally starts on Opus, or a live-adjacent one starts underpowered on Haiku.
- Never leave the usage watcher running (undegistered) after the round is genuinely done — it
  pollutes the peer/aggregator registry for the next round.

## Done-when

- `GitHub\SESSION_HANDOFF_<date>-<topic>.md` exists, committed/pushed, with done/verified/
  next-step/pending-decisions filled in for every lane touched this round.
- Any stale ledger/memory fact this round's work contradicted has been corrected in the same
  close-out.
- Any lesson now seen twice has been promoted into a skill's Never-list or a standard, not just
  logged again in `docs/LESSONS.md`.
- Every next-session prompt handed to Jeremy (or queued for the next round) carries an explicit
  model/effort row.
- The usage watcher has been stopped (`TaskStop`) if the round is fully closed.
