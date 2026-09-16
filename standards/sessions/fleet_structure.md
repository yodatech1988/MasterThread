# Fleet structure

**Status:** owner-directed, 2026-09-16. Supersedes the two-team/two-lead model used on the night of
2026-09-15/16. Applies to any multi-session round.

## Seats

Eight sessions. No team leads.

| Seat | Count | Reports to | Notes |
|---|---|---|---|
| PM | 1 | the owner | Directly manages all six workers. Self-watches usage (no PM above it). |
| Worker | 6 | the PM | Each holds a current task **and** a queued next task. |
| Peer review + merge authority | 1 | the PM | One combined seat. Reviews, then merges. |

The previous model inserted two team leads between the PM and the workers. It was dropped because
every instruction and every finding travelled two hops in each direction, and several of the night's
errors were introduced or amplified in relay — including a restructure justified by a PM that did not
exist, and a dispatch chain that produced two confirmed-false claims. Direct management of six is
within one session's capacity; the relay layer was not paying for itself.

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
