# Fleet structure

**Status:** owner-directed, 2026-09-16. Supersedes the two-team/two-lead model used on the night of
2026-09-15/16. Applies to any multi-session round.

## Seats

**Headcount follows the work.** There is no fixed worker count: a worker exists because a workstream
needs one, and a workstream with nothing live has no worker. An earlier draft of this document
specified exactly six; the owner corrected it — *"we need to really scope workers to work streams not
just have set 6 workers."*

| Seat | Count | Reports to | Notes |
|---|---|---|---|
| PM | 1 | the owner | Self-watches usage (no PM above it). Only the PM talks to the owner. |
| Team lead | as needed | the PM | Holds each member's backlog: current, on deck, up next. |
| Worker | one per live workstream | its lead | Never idle — see below. Runs subagents beneath it. |
| Peer review + merge authority | 1 | the PM | One combined seat. Reviews, then merges. |
| Cost steward | 1 | the PM | Required: the PM dispatches nothing while it is vacant. Meters every session's context and cost and instructs compaction. |

What the PM is accountable for across workstreams is in `pm_role.md`; the review + merge seat's
routes, procedure and enforcement are in `merge_authority.md`; the cost steward's meter, thresholds
and instructions are in `cost_steward.md`.

A **workstream** is a named, durable piece of production with an owner and a backlog — not a task.
Workers are assigned to workstreams, and the number of workers is whatever the live workstreams
require.

**No worker is ever idle.** Each holds a current task, an on-deck task, and enough behind it that
finishing a lane never produces a "what now?" round-trip to the lead. Eliminating that round-trip is
the point. Backlog state (current / on deck / next, per member) is dashboard data the owner watches,
not internal bookkeeping.

**Workers run subagents beneath them.** A worker that does everything in its own context is the
leverage being left on the table; the agent roster exists to be used. Launch independent subagents in
a single message so they run concurrently. Two rules: a subagent's output is a **report, not a
verdict** — the worker verifies before relaying, because a confident summary is the easiest thing in
this system to mistake for a fact; and the expensive Opus-tier reviewer is deliberately rare, never a
default.

### On the lead layer

It has been removed once and restored once, and both decisions were right at the time. Removed
because every instruction and finding travelled two hops each way and several of the round's errors
were introduced or amplified in relay. Restored by the owner when the fleet grew past what one PM can
directly backlog. The cost is real, so pay it deliberately: leads exist to hold backlogs and keep
workers loaded, not to pass messages. If a lead is only forwarding, the layer is not earning its
place.

**Every relay states its provenance.** A lead passing on an instruction or a finding says whether it
verified the claim itself or is relaying it. This is not a formality: on 2026-09-16 the PM relayed a
live owner instruction that contradicted this very document, told a lead to treat it as settled, and
was caught by a worker that fetched the document fresh and checked. The instruction was genuine and
the document was stale — but the only verifiable record said otherwise, and the challenge was
correct.

## Why review and merge are one seat

They were separate on 2026-09-15/16 and the split produced duplicated verification: QC re-derived
state that merge authority then re-derived again from live `gh`, twice reaching different totals for
the same queue. Merging without having reviewed is the thing to prevent; reviewing and then merging
is one job. Combining them removes a handoff without removing a gate.

## Standing rules for the structure

1. **Workers always hold two tasks** — one in hand, one queued with the PM. A worker blocked on a
   merge is the only acceptable idle state, and even then the PM should have queued something
   read-only.
2. **Only the PM talks to the owner.** Workers and the review/merge seat report to the PM. The
   exception is a worker escalating a matter of its own conscience or authority — see rule 5.
3. **The PM self-watches usage** and is the aggregator for every session that has handed off to it.
4. **No session decides its own re-entry rule** for a tool that performs real, hard-to-reverse
   actions. That is an owner decision.
5. **A session may decline a PM instruction and escalate directly to the owner**, and must not be
   pressured out of it. On 2026-09-16 three sessions parked on exactly this basis and were
   substantively right to; one of them, had it complied with the relay it was given, would have
   widened production access to the wrong host. A relayed "the owner confirms my authority" delivered
   by the session whose authority is in question is weak evidence however true it happens to be.

## Provenance rules (adopted after real confusion)

- Every review verdict states the reviewing session, the authoring session, and whether the finding
  is the reviewer's own read or a relay.
- Anyone relaying a member's finding distinguishes "I verified this" from "member X reported this."
- GitHub carries **no session-level attribution** — every commit authors as the account owner — so the
  PM's dispatch ledger is the only PR→session record. Keep it current.

## Verification rules (each one was learned the expensive way)

- **Read `origin/<default>`, never a shared working tree.** A shared checkout parked on a feature
  branch caused two sessions to reach opposite conclusions about the same file.
- **Green CI is not evidence.** At least one repo has no secret-scan job at all; its green checks say
  nothing about secrets.
- **Red CI is not evidence either.** GitHub Actions is deliberately unfunded (see
  `aegis-github-actions-deliberately-unfunded` in the owner's memory): a failure may be runner
  funding, a known runner-provisioning gap, or real content. A finding that cites a CI failure must
  say which.
- **A silently queued job is worse than a red one.** A job pointed at a runner pool that does not
  exist, or that its repo is barred from, waits forever and emits nothing — invisible to a strategy
  that relies on failures being loud.
- **Check reusable-workflow callers individually.** Defaults can be overridden per call.
- **Verify the search term, not just the search.** A zero-hit search proves nothing if the canonical
  identifier differs from the name used in planning prose. This produced the night's largest false
  finding: a PR was halted as "fabricated content" when the content was present under its real
  identifiers.
- **Re-read a tool before re-running it.** Merged changes alter tools underneath you.
- **Pre-flight every new branch name for a case collision.** MasterThread currently carries
  `agent/MasterThread/*` and `agent/masterthread/*` as parallel namespaces across dozens of the same
  slugs. On Windows' case-insensitive filesystem, creating a branch whose path differs only in case
  from an existing one can silently produce an **orphan branch with no shared history** — the commits
  are fine, but GitHub refuses the PR with "no history in common with main." Recovery is to
  cherry-pick onto a branch created from `origin/<default>` under a non-colliding prefix, then verify
  the commit count and parent. Check `git ls-remote origin` in **both** casings before naming a
  branch.

## Approval and authorisation

An approval gate must bind **two** facts: that a human approved, and that the human initiated the
thing asking. Binding only one leaves a hole in either direction, and both directions were hit on
2026-09-16:

- A stored approval record is not proof a human clicked — it is forgeable by any session that can
  write to the store.
- A human click is not proof the human intended the run that produced it — a session's believed-
  harmless invocation rendered real merge dialogs on the owner's desktop, and the owner clicked them
  believing he had started the queue.

Therefore: any tool that renders an owner-facing prompt for a hard-to-reverse action must refuse to
launch unless the owner initiated it — an owner-typed flag, an interactive-session check, or an
owner-written marker file.
