---
name: round-start
description: Use at the very beginning of an orchestrator/PM round — before reading a handoff, before dispatching anything — to arm the usage watcher, pull real ledger/PR state, triage and size the backlog, and produce a dispatch plan.
---

# round-start

## When to use this

- You are opening (or resuming) an orchestrator or PM session that will dispatch work across
  repos this window.
- The very first tool call of the round, before reading `SESSION_HANDOFF_*.md` or touching
  `docs/REPOS.md` — the watcher must be live before anything else spends usage
  (`standards/sessions/orchestrator_role.md`, "Usage watcher": "It is not optional and it starts
  before anything else in a round").
- Also use when resuming after a Monitor expiry (re-arm) or after a `USAGE RESET` line.

## Procedure

1. **Arm the usage watcher first**, per `standards/sessions/orchestrator_role.md` "Usage watcher".
   Pick a unique `-Name` for this session (check `ListAgents` / the registry under
   `%APPDATA%\AEGIS\orchestrators\` for collisions first — see the never-list below):

   ```
   Monitor  command: MT=C:/Users/yoda_/GitHub/MasterThread; N=<unique-name>; git -C $MT fetch -q origin main; git -C $MT show origin/main:tools/usage-monitor/usage-watch.ps1 > "$APPDATA/AEGIS/usage-watch.$N.ps1" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$APPDATA/AEGIS/usage-watch.$N.ps1" -HandoffRoot C:/Users/yoda_/GitHub -Name $N -Program "<what this round is>" 2>&1 || echo "USAGE-ERROR could not load or run usage-watch.ps1 from MasterThread origin/main"
            description: Claude usage tiers for <unique-name>
            timeout_ms: 1800000
   ```

   Read its `USAGE START` line: current usage tier, and any other live orchestrators/peers. If it
   prints `USAGE-ERROR`, treat usage as unknown/high — dispatch nothing until a real reading
   (`/usage` or `usage-window-reporter`) comes back `USAGE-OK`.
   Re-arm with the same `-Name` every time the Monitor expires (at most every 30 min; a gap over
   ~6 min drops you from the peer registry).

2. **Start from the handoff, not a re-survey.** Read, in order:
   - The newest `GitHub\USAGE_HANDOFF_*\AGGREGATE.md` if one exists (last window's aggregator
     close-out) — that supersedes an older `SESSION_HANDOFF_*.md`.
   - Otherwise the newest `GitHub\SESSION_HANDOFF_<date>-<topic>.md` (list the directory, sort by
     date in the filename — don't guess which is newest from memory).
   - `MasterThread/docs/REPOS.md` for the per-repo ledger (plan, current session, next session).

3. **Re-verify every claimed in-flight lane against live state before trusting it.** Docs go stale
   within hours (`orchestrator_role.md` step 1). For each lane the handoff/ledger calls "in
   progress" or "waiting on PR #N":
   - `gh pr list -R yodatech1988/<repo> --state all --head <branch>`
   - `gh pr view <n> --json state,mergeable,statusCheckRollup`
   A PR shown "open" in a doc but actually merged/closed changes that lane's status immediately —
   don't carry a stale "waiting on" forward. Prefer the `plan-status-check` and `pr-state-sweep`
   T4 subagents (Haiku, read-only, `docs/AGENTS.md`) for this sweep instead of doing it by hand.

4. **Triage the backlog into priority tiers** per `standards/sessions/priority_classification.md`
   (P0 live-blocking → P1 unblocking → P2 plan work → P3 deferred). Gather items from: the
   handoff's open items and paused lanes, each active repo's `docs/PLAN.md` "not started" rows,
   and any recorded-but-unactioned owner decision.

5. **Size each item** per `standards/sessions/task_sizing.md` (S/M/L/XL by shape: file/repo count,
   whether a local boot-test loop is likely, whether scope is fully known). Sort dispatch order:
   priority tier first, size descending second within a tier — largest first while the window is
   fresh, unless it's blocked by something smaller.

6. **Gate against the parallel-write-lane cap.** Per `orchestrator_role.md`'s cost rule: no more
   than ~6 parallel **write lanes** (one per repo, each with its own worktree/branch/PR,
   `session_plan_standard.md` rule 9) at once. Read-only fan-out (a `pr-state-sweep`, a
   `plan-status-check`, an origin grep) is a separate, much wider budget gated on usage headroom,
   not the write-lane count — prefer a Haiku T4 subagent for it instead of spending a write lane's
   Sonnet budget.
   Also apply the size gate from `task_sizing.md`: fresh window → anything can start, largest
   first; usage past ~40-50% → no new XL; near ~70-80% → S only (P0/P1 L only if nothing smaller
   is left in that tier).

7. **Produce the dispatch plan**: an ordered list of lanes, each with repo, one-line task,
   priority tier, size, and the model/effort row it maps to from `orchestrator_role.md`'s table
   (row 1 Opus/high for live-prod/credential/money/death-path/contract work, row 2 Sonnet/high for
   large invariant-sensitive edits, row 3 Sonnet/medium for a normal plan session, row 4
   Sonnet/low for doc-only, row 5 Haiku/low for mechanical read-only sweeps). This plan is the
   handoff to `dispatch-lane` — do not hand-wave "dispatch the usual repos"; name each lane.

## Never

- Never dispatch a new lane, or even read the handoff, before the usage watcher is armed and its
  `USAGE START` line is read — usage overruns are exactly what the watcher exists to prevent.
- Never trust a handoff file's or `REPOS.md`'s "waiting on PR #N" without re-checking `gh pr
  view --json state` first — a PR merging mid-session and stranding commits is a recorded
  incident.
- Never exceed ~6 parallel write lanes; never let a read-only fan-out task consume a write-lane
  slot when a Haiku T4 subagent would do.
- Never start a new XL-sized lane once usage is past ~40-50% for the window, and never start
  anything but P0/P1-L-if-nothing-smaller once usage is near ~70-80%.
- Never reuse another live orchestrator's `-Name` for the watcher (check `ListAgents` and the
  `%APPDATA%\AEGIS\orchestrators\` registry first) — a duplicate name is refused, and picking a
  fresh one without checking risks confusing the peer/aggregator protocol.

## Done-when

- The usage watcher is armed and has printed its `USAGE START` line (or a confirmed `USAGE-OK`
  after a prior `USAGE-ERROR`).
- Every lane the plan is about to dispatch has been checked against live `gh pr` state this round
  (not assumed from a doc).
- A written dispatch plan exists: ordered lane list, each with repo / task / priority / size /
  model-effort row, respecting the write-lane cap and the size-vs-usage gate.
