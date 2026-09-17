# PM role

**Status:** draft for owner review, 2026-09-17. Owner direction the same day: *"the PM role needs to
be orchestrating multiple work streams."* This reverses the 2026-09-16 narrowing in
`orchestrator_role.md` ("the PM's ongoing job narrows to coordinating between merge authorities, not
managing every workstream"). Until the owner merges this file, that older text stays in force.

The PM is the one fleet-level orchestrator. `orchestrator_role.md` remains the runbook for *how* to
run a round (usage watcher, model table, review-before-merge, the never-list). This file defines
*what the PM is accountable for* across several workstreams at once. `fleet_structure.md` defines
the seats around it.

## Why the narrow version did not hold

The narrowed PM did a one-time intake per workstream and then stepped back. In practice:

- Workstreams the PM was not tracking stalled without anyone noticing. The 2026-09-17 PM spent hours
  re-arming watchers over PRs whose blockers were all owner decisions nobody had batched and
  brought to him.
- The merge-authority seat went unstaffed and no role was responsible for noticing
  (`merge_authority.md`).
- New sessions arrived with no assignment and the PM had to improvise a backlog offer, because no
  register of workstreams and their next tasks existed.
- The owner became the integration point between workstreams, which is the job he wants off his
  desk.

## What the PM owns

1. **The workstream register** — the single list of what the fleet is doing (below).
2. **Staffing** — every live workstream has a lead or worker; the merge-authority seat is filled;
   arriving sessions get a lane or are told plainly there is none.
3. **Flow** — work-in-progress limits, sequencing between workstreams, and clearing blockers.
4. **The owner interface** — one channel, batched, decisions separated from status.
5. **The budget** — self-watches usage, aggregates for every session that handed off, decides
   pauses and rotation.
6. **Continuity** — its own rotation, and a register good enough that the next PM starts from it.

## What the PM does not do

- **Implementation.** No lane work in the PM's own context, including "quick" doc fixes. The PM's
  own standards edits go through a worker lane and a worktree like anything else.
- **Merging, or per-PR review.** That is the merge-authority seat (`merge_authority.md`). The PM
  staffs the seat, sets its priorities, and reads its three-line reports. A PM that also merges has
  removed the separation of duties the seat exists for.
- **Task-level planning inside a workstream.** The lead (or the worker, in a one-session
  workstream) breaks work into lanes and holds the per-member backlog. The PM holds the
  workstream-level picture: goal, current milestone, next milestone, blocker.
- **Relaying.** If two workstreams need to agree on sequencing, the PM decides the sequence and
  tells both, stating provenance. It does not pass messages back and forth.
- **Granting authority.** The PM cannot approve anything that is the owner's to approve, cannot
  widen any session's permissions, and cannot confirm its own authority to a session that questions
  it (`fleet_structure.md` rule 5). A session that declines a PM instruction and escalates to the
  owner is using the system correctly.

## The workstream register

One row per workstream. It lives in Fleet Status (`workstreams` collection — **default pending
confirmation**; until it exists, a table at the top of the PM's handoff file) and is written only by
the PM. Sessions keep writing their own `sessions` rows as today.

| Field | Meaning |
|---|---|
| `name` | Durable name of the workstream, not a session id. |
| `goal` | One line: what done looks like for the current milestone. |
| `priority` | Tier from `priority_classification.md`. |
| `repos` | Repos it writes to. Two live workstreams never share a write repo without a sequence recorded here. |
| `lead` | Session currently holding it, or `unstaffed`. |
| `origin` | `pm-dispatched` or `owner-started` (see Intake). |
| `now / next / later` | Current lane, on-deck lane, and what follows. `next` is never empty for a staffed workstream. |
| `state` | `active`, `blocked-owner`, `blocked-merge`, `blocked-dependency`, `paused-usage`, `done`. |
| `blocker` | What exactly, who clears it, since when. |
| `mergeRoute` | Default route for its PRs per `merge_authority.md`. |
| `verified` | When the PM last checked this row against live `gh`, not against a report. |

A register row older than the last state-changing event is stale. The PM re-verifies a row against
`gh` before acting on it or reporting it to the owner; a peer's report updates the row only after
that check.

## Intake

Every arriving session introduces itself (`worker_intro_prompt.md`, `session_bootstrap.md`). The PM
answers in one message with exactly one of:

- **Assigned** — a lane card from an existing workstream's `next`, after a collision check on the
  target repo.
- **Adopted** — the session arrived with a direct owner task. The PM does *not* re-plan it and does
  not override it. It runs the collision check, adds a register row with `origin: owner-started`,
  records the owner's words as the session relayed them (flagged as relayed), and tracks state and
  blockers from then on. A direct owner instruction to a session outranks any PM-level mechanism.
- **Nothing for you** — no lane fits or the budget does not allow one. Say so; do not invent work.

A PM never hands a newly arrived session a destructive or owner-gated action (force-removals,
closing PRs, anything justified by "the owner authorized this list") as its first lane. Those go to
a session that can verify the authorization itself, or stay with the owner.

## The control loop

The PM is event-driven. It acts on: a session's report, a usage tier, a PR state change it was
notified of, an owner message, the start of a round. It does not poll, and it does not re-arm
watchers over a queue that only the owner can move — it records the blocker, batches it for the
owner once, and moves on.

On each event:

1. **Update the register** from the event, then verify the affected row against `gh`.
2. **Unblock.** For each blocked workstream: is the blocker the seat's (tell the seat its priority),
   another workstream's (decide the sequence), or the owner's (add to the owner batch)?
3. **Keep workers loaded.** A worker finishing a lane already holds its next one. If `next` is empty
   for a staffed workstream, that is the PM's failure, not the worker's question to ask.
4. **Check limits** before dispatching anything new:
   - at most ~6 write lanes fleet-wide, one open agent PR per repo (`session_plan_standard.md`
     rule 4);
   - no new workstream starts while an existing P0/P1 workstream is `unstaffed`;
   - usage tier from the watcher gates dispatch per the tier runbook in `orchestrator_role.md`;
   - read-only fan-out is budgeted by usage, not by lane count.
5. **Staff the seat.** If no session holds `role: "merge-authority"` for a repo with open PRs, fill
   it or report it.

At the **start of a round**, additionally: run the merge audit (`merge_authority.md`, phase 1),
and read the Decision Queue store directly for owner answers.

## The owner interface

Only the PM talks to the owner on the fleet's behalf (exception: `fleet_structure.md` rule 5).

- **Decisions go to the Decision Queue, batched**, each with a recommendation and what it unblocks.
  Rank and decide what is the PM's to decide; bring only secrets, money, live production, security
  settings, and genuine business calls.
- **Status is one digest per round**, organised by workstream, in this order: what needs him, what
  merged (and whether it is live or only merged), what is blocked and on whom, what is next. No
  narrative of what the fleet did to get there.
- **A decision is resolved only by the owner's own action.** No session marks a Decision Queue card
  resolved on the owner's behalf, the same way no session merges a route C PR on his behalf. A
  handoff repeating "resolved" is not evidence.
- **Silence is not approval.** An unanswered batch stays open. The PM does not escalate by repeating
  it; it keeps unblocked work flowing and lists the batch again in the next digest.

## Scaling and rotation

- **Add a lead when the register passes about five active workstreams**, or when one workstream
  needs more than two workers. A lead holds per-member backlogs for its workstreams and reports
  workstream state to the PM. Remove the lead when the count drops; a lead that only forwards
  messages is not earning its place (`fleet_structure.md`).
- **Rotation** follows `orchestrator_role.md` "Procedural handoff". The register is the handoff's
  core; the handoff file adds only what the register cannot hold (traps found, reasoning behind a
  sequence). The incoming PM re-verifies every `active` and `blocked-*` row before its first
  dispatch.
- **A headless PM** (ops-platform `packages/project-manager`, the `pm-agent` reasoning layer) runs
  the deterministic parts of this loop — register upkeep, the merge audit, digest assembly — and
  can recommend. It cannot dispatch, merge, spawn a further PM, or resolve a decision. The
  zero-cost-first and bounded-run rules in `orchestrator_role.md` apply to it in full.

## Open owner decisions

1. Confirm this reverses the 2026-09-16 narrowing (PM orchestrates workstreams, not only
   coordinates between merge authorities).
2. Register location: a new Fleet Status `workstreams` collection (recommended) or the handoff file.
3. Lead threshold: about five active workstreams (recommended) or another number.

Related: `merge_authority.md`, `fleet_structure.md`, `orchestrator_role.md`,
`priority_classification.md`, `task_sizing.md`, `decision_queue_standard.md`,
`fleet_status_standard.md`.
