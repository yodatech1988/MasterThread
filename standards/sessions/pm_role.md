# PM role

**Status:** owner-confirmed 2026-09-17 (Ops Decision Queue card `pr81-q1-pm-orchestrates-workstreams`:
"Yes - PM orchestrates workstreams via a register"); takes effect when the owner merges this file.
Owner direction the same day: *"the PM role needs to
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

Staffing and the budget both depend on knowing the fleet's actual membership, which neither
`ListAgents` (live but with no memory of who arrived or left) nor Fleet Status (self-reported, so
silent about sessions that never wrote a row) provides on its own. The PM arms the recurring roster
check in [`fleet_roster_monitor.md`](fleet_roster_monitor.md) at takeover; it reports joins,
departures and sustained idleness, and only when they change.

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
| `dispatchable` | Boolean. True when `next` can start without an owner action or an unmerged dependency. The heartbeat tick (below) dispatches only from `dispatchable: true` rows; `blocked-owner` rows are batched for the owner instead. Without this bit the PM cannot tell "waiting on the owner" from "waiting on me" — exactly the confusion behind the 2026-09-18 stall (see "The control loop"). |
| `state` | `active`, `blocked-owner`, `blocked-merge`, `blocked-dependency`, `paused-usage`, `done`. |
| `blocker` | What exactly, who clears it, since when. |
| `mergeRoute` | Default route for its PRs per `merge_authority.md`. |
| `verified` | When the PM last checked this row against live `gh`, not against a report. |

A register row is stale when a state-changing event on *that row's own* `now` item — its PR, branch,
or named blocker — postdates the row's `verified` timestamp, not when anything at all happened in
the row's repo (register-verifier's first live run, 2026-09-18T02:25Z, flagged two rows verified at
02:14Z and 02:20Z as stale purely because an unrelated PR updated at 02:23:52Z in the same repo). The
PM re-verifies a row against `gh` before acting on it or reporting it to the owner; a peer's report
updates the row only after that check. A verification pass takes one snapshot of the newest relevant
event per row at the start of the pass and compares every row against that snapshot, so rows checked
early in the pass aren't judged stale relative to rows checked later in the same pass. A staleness
rule that fires on every row is indistinguishable from one that fires on none, and both leave the PM
re-verifying everything by hand — the cost the register exists to remove.

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

## Completion handshake (the PM's side of "what's next")

`worker_role.md` "After delivering — end of workstream" (MasterThread PR #82, open at time of
writing) has a worker that finishes a lane write its lessons block, set its Fleet Status row to
`state: done` / `nextStep: awaiting PM assignment`, report to the PM, and start nothing until told.
The PM's half:

1. **Answer in one message, with exactly one of:** **continue** (the lane card from the
   workstream's `next`), **rotate** (write the handoff and stop; a fresh session takes the card),
   or **stand down** (workstream done or paused; prune the worktree once the PR merges).
2. **The answer should already exist.** `next` is kept filled so that replying is a lookup, not a
   planning session. Holding an on-deck card is what makes the reply instant; it is not permission
   for the worker to start it unasked. If the PM has to think about what comes next only when the
   worker asks, the register was stale.
3. **Verify before answering**: the delivered PR's state via `gh`, then move the register row
   (`now` ← `next`, refill `next`, update `state` and `verified`).
4. **Decide continue vs rotate on the session's condition**, not only the backlog: heavily
   compacted context, many hours active, or a change of repo all favour rotate.
5. **Read the lessons block.** A rule candidate that repeats across lanes is promoted into a
   standard or skill through a worker lane; the PM does not edit standards itself.
6. **If the PM cannot answer promptly** (usage unknown or high, mid-rotation), it says so in one
   line with when to expect an answer. A worker left waiting with no reply is the PM's failure;
   a worker self-assigning because of it is the outcome this handshake exists to prevent.

## The control loop

The PM is event-driven — it acts on a session's report, a usage tier, a PR state change it was
notified of, an owner message, the start of a round — **and it also runs a heartbeat tick**, added
2026-09-18 after the owner observed a live PM (`busy` in `ListAgents`) that had gone quiet: no
events were arriving, so nothing woke it, and the design of "event-driven" *was* the stall. Owner,
directly: *"we need to make adjustments so the pm never stalls"* / *"the pm should be constantly
monitoring usage and activating agents and teams of agents with sub agents to be working backlog"*
/ *"as a pm not a worker."*

**The heartbeat.** At takeover, the PM arms `CronCreate "*/10 * * * *"` (or `/loop 10m`) whose
prompt IS the control loop, run whether or not any event arrived:

1. Read `%APPDATA%\AEGIS\claude-usage-state.json` for current usage. Never conclude "usage
   unknown" from a 429 or a failed call — the state file, not a live re-check, is the source.
2. `ListAgents` → pipe the roster into `fleet-roster-watch.ps1` (`fleet_roster_monitor.md`).
3. **Register**: for every staffed workstream whose `now` is delivered, dispatch its `next`; for
   every unstaffed workstream at priority ≤P1 with a `dispatchable: true` item, spawn a team
   (below), while 5-hour usage is under 80% and write lanes are under 6.
4. Own Decision Queue cards by `get` (not a full `list`).
5. Write its own `sessions` row and, last, `%APPDATA%\AEGIS\pm-heartbeat.json`
   (`tools/pm-heartbeat/Write-PmHeartbeat.ps1`) so an external watchdog can tell a live-but-stalled
   PM from a working one.

**The invariant, verbatim: a tick never ends with dispatchable work, budget, and idle capacity all
present at once.** A quiet tick — nothing dispatchable, or budget/capacity genuinely exhausted — is
a no-op and says nothing to the owner; it still writes the heartbeat file.

**Permission posture.** The PM seat's coordination tools must not prompt, or every gated call stalls
it exactly as before, indistinguishably from outside: `ArtifactData`, `SendMessage`, `Agent`,
`CronCreate`/`CronList`/`CronDelete`, `Bash(gh pr list *)`, `Bash(gh pr view *)`,
`Bash(gh api repos/*)` (GET only), `Bash(git fetch *)`, `Bash(git show *)`,
`Bash(git worktree add *)`, `Bash(git worktree list)`, and the `New-ParallelWorktrees.ps1` call.
Only the owner can add these — a session editing its own `settings.json` is classifier-blocked
(self-modification) — so this is filed as one Decision Queue card with the exact list above (see
"Open owner decisions" #3). Prompting mode is not itself a stall — the 2026-09-18 PM dispatched
throughout — but an unattended PM in prompting mode stalls at the first gated step of a dispatch,
and from outside the two are indistinguishable; the watchdog therefore detects "no tick while
budget and dispatchable work exist", never permission mode alone.

On each event (heartbeat tick or otherwise):

1. **Update the register** from the event, then verify the affected row against `gh`.
2. **Unblock.** For each blocked workstream: is the blocker the seat's (tell the seat its priority),
   another workstream's (decide the sequence), or the owner's (add to the owner batch)?
3. **Keep workers loaded.** A worker finishing a lane gets its next card in the PM's first reply
   (see "Completion handshake"). If `next` is empty
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

### Teams, not lanes the PM works itself

The PM dispatches via the `Agent` tool with `run_in_background: true` — one Sonnet **lead** per
lane, briefed with the lane card, told to spawn its own roster subagents for research and
verification, and to report back in three lines. The PM pre-creates the worktree
(`New-ParallelWorktrees.ps1`) and hands the lead its exact path; a lead never picks its own
folder. Read-only teams (sweeps, verifiers) are Haiku and budgeted by usage, not by lane count.
This is `fleet_structure.md`'s "workers run subagents beneath them" applied to the PM's own
dispatch, not a new pattern.

### A PM, not a worker — the checks

The PM never runs `gh pr diff`, never reads a card body to verify it, never edits a standard,
never SSHes — each of those is a dispatch (`diff-reviewer`, `register-verifier`, a worker lane).
Checks that would fail if this were ignored: a tick's own tool calls are limited to `ListAgents`,
`ArtifactData`, `SendMessage`, `Agent`, `CronCreate`, the usage/roster scripts, worktree creation,
and `gh pr list`/`gh pr view`; a tick over ~10 of its own tool calls is a finding; and the
`dispatchable-and-idle` count (dispatchable rows with no lane running against them) at the end of
a tick must be 0.

## The owner interface

Only the PM talks to the owner on the fleet's behalf (exception: `fleet_structure.md` rule 5).

- **Decisions go to the Decision Queue, batched**, each with a recommendation and what it unblocks.
  Rank and decide what is the PM's to decide; bring only secrets, money, live production, security
  settings, and genuine business calls.
- **One decision per card.** A PR or plan that carries several decisions is several cards, never one
  merge/hold card the owner cannot answer piece by piece. Every session files its own owner decisions
  this way by default (owner decision 2026-09-17, in `~/.claude/CLAUDE.md`); the PM's job is to keep
  the queue batched, de-duplicated and actually visible to him.
- **An owner reply that is a question is not a resolution.** The queue page marks any submitted text
  resolved (found 2026-09-17: a card answered with a question vanished from his open view). Reopen it
  with a `corrections` entry and answer the question.
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
- **A headless PM** (ops-platform `packages/project-manager`, the `pm-agent` reasoning layer) is
  *intended* to run the deterministic parts of this loop — register upkeep, the merge audit, digest
  assembly — and to recommend, never to dispatch, merge, spawn a further PM, or resolve a decision.
  **Build state, checked 2026-09-18** (`git show origin/main` on ops-platform): **not built.**
  `packages/project-manager` implements digest assembly only; `bin/start.js` throws
  unconditionally; no register, merge-audit, Fleet Status, or `gh` code exists on any main branch;
  `pm-agent` has no definition anywhere on main. Treat the paragraph above as intent, not fact,
  until that changes. **General rule**: any standard that names a mechanism carries its build state
  — `built and verified on <date> by <command>`, or `not built` — so a later reader can't mistake
  intent for fact — the same category error the 2026-09-18 PM-process review found in six other
  standards in one evening (a register, a supervisor script, a roster generator, a `queue` writer,
  required checks, and this paragraph).

## Open owner decisions

1. Register location: a new Fleet Status `workstreams` collection (recommended) or the handoff file.
2. Lead threshold: about five active workstreams (recommended) or another number.
3. ~~PM-seat permission allow list~~ — **owner decision, 2026-09-18**, recorded on Decision Queue
   card `pm-seat-permission-allowlist-2026-09-18` (resolved on the page 00:58:24Z, option B: the
   read-only set plus `git worktree add` / `New-ParallelWorktrees.ps1`). The card is the record;
   ops recommended, the owner decided. The change is applied only by the owner running
   `AEGIS-Allow-PM-Seat-Tools.cmd` himself — a resolved card authorises the change, not the run.

Related: `merge_authority.md`, `fleet_structure.md`, `orchestrator_role.md`,
`priority_classification.md`, `task_sizing.md`, `decision_queue_standard.md`,
`fleet_status_standard.md`, `headless_readiness_ladder.md`.
