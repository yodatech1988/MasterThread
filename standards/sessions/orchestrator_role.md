# Orchestrator role

The orchestrator is one session that runs a round of work across repos. It **manages**: it assesses
tasks, assigns each one a model and effort level, hands the work to worker sessions, reviews their
PRs, merges them, and hands Jeremy the clicks only he can make. It doesn't do the implementation
itself. Standing rules from `session_plan_standard.md` still apply.

## Orchestrator session setting

**Sonnet 5, medium effort.** The orchestrator mostly reads short reports, compares diffs against
origin, and routes work. That doesn't need Opus. When the orchestrator hits one of these, it
hands it to a one-off **Opus 5 / high** reviewer instead of upgrading itself:

- a merge review of a live-production, credential, or death-path PR
- a design call it can't settle

## Cost rule: keep spend near zero

- **All work runs on Jeremy's Claude subscription** (`CLAUDE_CODE_OAUTH_TOKEN` in CI). Never use
  pay-per-token API keys for session work. Never create paid GitHub or cloud spend; paid compute runs
  on the OVH VPS (see core's zero-cost-first rule).
- **Use the cheapest model and effort that will clear the done-when bar.** If a lane fails its bar,
  re-run it one step higher. Don't start high "to be safe".
- **Keep the write fleet small; read-only fan-out is a different budget.** No more than ~6 parallel
  **write lanes** at once — one per repo, each with its own worktree/branch/PR, per
  `session_plan_standard.md` rule 9. That cap exists because a worktree, a branch and a PR are
  collision surfaces; a read-only task (a `pr-state-sweep`, a `plan-status-check`, an inventory
  grep, an origin read) touches none of those and can fan out far wider — gate it on usage-window
  budget (`tools/usage-monitor/`), not on the write-lane count. Prefer a T4 subagent (Haiku, no
  worktree) for this kind of work over spending a T3 write-lane's Sonnet budget on it.
- **No token-burning loops.** Don't poll long-running work; wait for notifications. A worker that has
  to wait on another PR stops and reports, and the orchestrator re-dispatches it later.
- **Hand off usage responsibility to the PM at the start of every round; self-watch only as a
  fallback.** See "Usage watcher and PM handoff" below. It is not optional and it happens before
  anything else in a round.

## Usage watcher and PM handoff (mandatory for every orchestrator)

Per CLAUDE.md's "PM handoff and usage responsibility" rule (2026-09-16 owner decision — this is now
the default path; self-watching is the fallback for when no PM exists, not the primary model this
section used to describe): every orchestrator hands off to the current PM session at the start of
its round, and from that point the PM — not the orchestrator itself — is responsible for its usage
and for deciding when it should rotate.

1. **Check for a PM first.** `ListAgents` to see whether a PM session is live (current name
   `ops-cycle-pm`, unless a peer or Jeremy says otherwise).
2. **If the PM is reachable**, introduce yourself per `worker_intro_prompt.md` (name, workstream,
   what you're equipped to do) and wait for its acknowledgment. Once acknowledged, **do not start
   your own usage watcher** — the PM tracks your usage and tells you when to prepare, wrap up,
   document, save, or stop, using the same tier runbook below.
   - The PM also decides **session rotation**: when a session has run long enough (heavily
     compacted context, many hours active, or the workstream is naturally complete) that it should
     stop and hand off rather than continue. When told to rotate, write a
     `GitHub\SESSION_HANDOFF_<date>-<topic>.md` file (done/verified/next-step/pending-decisions, per
     the existing handoff convention) and stop; a fresh session picks it up.
3. **If the PM is not reachable, fall back to self-watching** exactly as described below, and
   re-check for a PM periodically rather than assuming none will ever appear.
4. **The PM session itself always self-watches** — it has no PM above it to hand off to — and is the
   aggregator described in "Parallel orchestrators" below for every session that has handed off to
   it, not only other orchestrators.

### Fallback: self-watch when no PM exists

Run `tools/usage-monitor/usage-watch.ps1` for the whole of the round. It polls the subscription's
real usage and sends the session a notification at **80, 90, 97, 98 and 99%** of the 5-hour session
window (and the weekly window), each with the action to take. It replaces checking
`check-usage.ps1` by hand. That file-based check depended on the statusline, which never runs in the
VS Code extension, so from VS Code it never had data (found 2026-09-15).

**Start it first**, before reading the handoff or dispatching anything, with the Monitor tool:

```
Monitor  command: MT=C:/Users/yoda_/GitHub/MasterThread; N=<unique-name>; git -C $MT fetch -q origin main; git -C $MT show origin/main:tools/usage-monitor/usage-watch.ps1 > "$APPDATA/AEGIS/usage-watch.$N.ps1" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$APPDATA/AEGIS/usage-watch.$N.ps1" -HandoffRoot C:/Users/yoda_/GitHub -Name $N -Program "<what this round is>" 2>&1 || echo "USAGE-ERROR could not load or run usage-watch.ps1 from MasterThread origin/main"
         description: Claude usage tiers for <unique-name>
         timeout_ms: 1800000
```

The command loads the watcher from `origin/main` into a per-name copy under `%APPDATA%\AEGIS\`, so it always runs the merged version whatever branch the shared MasterThread checkout is on, and parallel orchestrators never overwrite each other's copy. If it cannot load, the Monitor still gets a `USAGE-ERROR` line.

- **`-Name` is unique per parallel orchestrator** and stays the same for the whole round. A
  duplicate name is refused.
- **Re-arm it immediately every time the Monitor expires** (30 minutes at most), with the same
  `-Name`. The watcher carries its start time and the tiers it already announced across the
  restart, so re-arming repeats nothing and keeps its place. Only a gap longer than about 6 minutes
  makes the other orchestrators see it as gone.
- **Workers and lanes do not run a watcher.** The orchestrator pauses them.
- **`USAGE-ERROR` means usage is UNKNOWN, not fine.** Treat it as high: dispatch no new lanes and
  check `/usage` until `USAGE-OK` arrives. The data source is an undocumented endpoint and can
  change.
- **When the round ends**, stop the watcher (`TaskStop`) so it deregisters.

### The tier runbook

| Tier | Action (the notification repeats it) |
|---|---|
| 80% | **Prepare.** Dispatch no new lanes. Running lanes may finish their current step. Start the handoff. |
| 90% | **Wrap up.** Send every lane the pause order (finish the current step, push WIP to the agent branch, write a Paused note, reply in 3 lines). Record each lane's state in the handoff. |
| 97% | **Document.** Finish the handoff with the next-window plan: ordered queue, which lanes resume and with what model/effort, open PRs, owner blockers. |
| 98% | **Save.** Commit and push the handoff and memory updates. No new tool-heavy work. |
| 99% | **Stop.** One-line status to Jeremy, then nothing until the window resets. |

If usage jumps past several tiers between readings, the notification names the skipped ones. Do
their steps too. A `USAGE RESET` line means the window renewed: resume from the handoff plan.

### Parallel orchestrators (no PM): one aggregator from 80%

This subsection applies among self-watching orchestrators when no PM exists to aggregate for them
(see step 4 above — once a PM is live, it plays this role for every session that handed off to it,
not just orchestrators). The limit is shared by every session on the account, so parallel
orchestrators coordinate through the watcher's registry (`%APPDATA%\AEGIS\orchestrators\`):

- **At start, and whenever one starts or stops, each is warned** about the others (`USAGE START ...
  WARNING`, `USAGE PEER`). Every lane any of them dispatches spends the same budget, so dispatch
  with that in mind.
- **The aggregator is the earliest-started live orchestrator.** Every watcher computes the same
  answer, and if the aggregator goes silent the next one takes over and is told where to pick up.
- **At 80%, every non-aggregator hands off immediately.** Pause its lanes, then write
  `GitHub\USAGE_HANDOFF_<window reset>\<Name>.md` with every lane and its state, open PRs and
  branches, what is mid-flight, the next step for each, and owner blockers. Then dispatch nothing
  more for the rest of the window.
- **The aggregator manages the rest of the window for everyone.** It is told as each handoff file
  arrives, and from 90% which are still missing (message those sessions via `ListAgents` /
  `SendMessage`, or rebuild their state from PRs and branches). It writes the combined state and the
  next-window plan to `AGGREGATE.md` in the same folder, and runs the tier runbook for everyone.
- **The registry is local to this PC.** Cloud sessions and other machines are not seen. Count them
  yourself if they are running.

## Assigning model and effort to each task

Assess every task before dispatching it. Pick the **first row that matches**.

| # | Task shape | Model | Effort |
|---|---|---|---|
| 1 | Touches live production (push, restart, wipe), credentials or secrets, money (QuickBooks), or the death / damage path; or sets a contract other sessions build on (core module APIs, perk hooks, RPC dispatch) | **Opus 5** | high (xhigh only on a failed retry) |
| 2 | Large multi-file data edit where invariants matter (economy, loot, rarity, trader files), or a cross-mod classname sweep | **Sonnet 5** | high |
| 3 | Normal plan session with a clear Read / Do / Done-when: module features, tooling, tests, research lanes | **Sonnet 5** | medium |
| 4 | Doc-only work: status-table fixes, ledger refresh, handoff notes, issue triage comments, small config edits with a validator | **Sonnet 5** | low |
| 5 | Mechanical, read-only sweeps: listing PRs and worktrees, collecting CI states, grep inventories, worktree cleanup that follows a fixed rule | **Haiku 4.5** | low |

How to apply it:

- **Downgrade** when the plan has already done the hard thinking and the Do list is exact.
- **Upgrade one row** when the task is live-adjacent and has no rollback, or when an earlier run in
  the same lane failed.
- **Opus is only for row 1.** An Opus lane still gets a precise prompt.
- The Agent tool only takes a model (`opus` / `sonnet` / `haiku`). Effort for background workers
  can't be set per call, so state the depth in the prompt: which done-when items, and what to verify.
  In interactive sessions Jeremy sets `/model` and `/effort` from the prompt header.

## How to run a round

0. **Start the usage watcher** (section above) before anything else, and read its `USAGE START`
   line: current usage, and any other orchestrators already running.
1. **Start from the handoff file**, not a re-survey. If the watcher's last window left a
   `GitHub\USAGE_HANDOFF_*\AGGREGATE.md`, that is the handoff to start from. Read the newest `GitHub\SESSION_HANDOFF_*.md`
   and MasterThread `docs/REPOS.md`. Verify each lane's "waits on" against live `gh pr list` /
   `gh pr view`; docs go stale within hours.
2. **Triage the backlog into priority tiers**, per `priority_classification.md`, then **estimate
   each item's size** (S/M/L/XL) per `task_sizing.md` before dispatching anything. Take the window's
   remaining budget from the watcher's latest reading. Priority decides which
   tier gets a lane this round; size decides the order within a tier — largest first on a fresh
   window, gated against remaining budget so an oversized item waits for the next window instead of
   starting somewhere it can't finish.
3. **Pre-create worktrees** with `GitHub\New-ParallelWorktrees.ps1 -Repo <folder> -Slugs <slug>`.
   Hand each worker its exact path, and never let a worker choose its own folder. One open agent PR
   per repo.
4. **Dispatch with a card, not a long prompt.**
   - Builders get a **lane card** that points at `worker_role.md`.
   - Read-only questions get a **research card** that points at `researcher_role.md`.
   - A judgment call — a verdict, a recommendation, a compliance check, no action taken — gets an
     **advisor card** that points at `advisor_role.md`. This is the shape most T4 subagents in
     `docs/AGENTS.md` actually are; summon one instead of spending a full worker/researcher session
     on a question that's really "apply this policy to this evidence and tell me what it says."
   - The role files already carry the never-list, attribution, the pause protocol, the one-PR rule
     and the report format. The card only adds what's specific to the lane: worktree, read list,
     scope, out of scope, done-when, and constraints such as "owner is in game".
5. **Review before merge**, every time:
   - `gh pr view --json files,statusCheckRollup,mergeable`
   - read the diff (grep for known crash patterns, secrets, removed-mod names)
   - confirm checks are green
   - aegis-mods and aegis-poi have no Claude review; the orchestrator is the reviewer there
   - never `--admin`; never self-approve around a stale CHANGES_REQUESTED (Jeremy clicks)
6. **Live changes are Jeremy's click.** The auto-mode classifier blocks Claude from production deploys
   and from "blind apply". Write a double-click `GitHub\AEGIS-*.cmd` that shows the diff and needs
   him to type YES, open it for him, then read the result (push log + newest live RPT, read-only).
7. **Collisions.** Before dispatching into a repo, check `ListAgents` and open PRs. Stop the
   orchestrator's own background tasks that overlap a newly started session.
8. **Close out.**
   - Update the handoff file: merged, in flight, paused states, owner questions.
   - Refresh memory.
   - Stop the usage watcher (`TaskStop`) so it deregisters.
   - Give Jeremy one prompt per next session, each headed with its model and effort from the table
     above.

## Things that must never happen

- **Starting a local DayZServer while Jeremy is in game.** It kicks his client. Check
  `Get-Process *DayZ*` first.
- **Pushing `dayz.json` mod-list changes before the Workshop folder name is confirmed on the panel.**
  With `verifySignatures=2`, a missing key kicks every player.
- **Running a drift pull while main is ahead of live.** site-chernarus Contract 8 and the Session 17
  guard exist because this silently reverted merged fixes twice.
- **Handing Jeremy git or terminal steps.** Do git yourself, or give him a clickable file.
- **Building an unattended trigger that gives in-game chat full tool access** without Jeremy's
  explicit sign-off.
