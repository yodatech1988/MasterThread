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
- **Keep the fleet small.** No more than ~6 parallel lanes, one per repo. Parallel lanes multiply
  usage.
- **No token-burning loops.** Don't poll long-running work; wait for notifications. A worker that has
  to wait on another PR stops and reports, and the orchestrator re-dispatches it later.
- **Watch Jeremy's usage.** Run `tools/usage-monitor/check-usage.ps1` (this repo) at the start of a
  round and periodically during a long one — it reads the subscription's 5-hour/weekly percentage
  from a file `tools/usage-monitor/statusline.ps1` keeps current (see that tool's README for why
  this is the only machine-readable source for an individual Pro/Max seat; the Admin API doesn't
  cover it). When it reports the threshold crossed (~80%), send every session a pause order: finish
  the current step, push WIP to the agent branch, write a "Paused" note (PR comment or PLAN.md
  Status row), stop, and reply in 3 lines. Record the states in the handoff file, then run
  `check-usage.ps1 -Acknowledge`.

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

1. **Start from the handoff file**, not a re-survey. Read the newest `GitHub\SESSION_HANDOFF_*.md`
   and MasterThread `docs/REPOS.md`. Verify each lane's "waits on" against live `gh pr list` /
   `gh pr view`; docs go stale within hours.
2. **Triage the backlog into priority tiers** per `priority_classification.md` before dispatching
   anything, and check `tools/usage-monitor/check-usage.ps1` for the window's remaining budget. Tier
   decides which items get a lane this round and which pause first if usage runs out.
3. **Pre-create worktrees** with `GitHub\New-ParallelWorktrees.ps1 -Repo <folder> -Slugs <slug>`.
   Hand each worker its exact path, and never let a worker choose its own folder. One open agent PR
   per repo.
4. **Dispatch with a card, not a long prompt.**
   - Builders get a **lane card** that points at `worker_role.md`.
   - Read-only questions get a **research card** that points at `researcher_role.md`.
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
