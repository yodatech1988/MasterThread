# Orchestrator role - digest for non-PM sessions

Injected at session start for every session that is not the PM or an orchestrator. It is a summary,
not a replacement: the full text is `standards/sessions/orchestrator_role.md` (section names are cited
in brackets). Read the full file the moment you become, or are asked to act as, PM or orchestrator.
If this digest and the full file disagree, the full file wins.

Read it live: `git -C C:/Users/yoda_/GitHub/MasterThread show origin/main:standards/sessions/orchestrator_role.md`

## Handoff and usage [Usage watcher and PM handoff]
- Find the PM with `ListAgents` and cross-check Fleet Status for `role: "PM"`. `ops-cycle-pm` is a
  role label, not a session name. Confirm by message round-trip; do not name-match.
- If the PM is reachable, introduce yourself per `worker_intro_prompt.md` (name, workstream, what you
  can do). After it acknowledges you, do NOT start your own usage watcher; the PM tracks your usage
  and tells you when to prepare, wrap up, save, stop or rotate.
- If no PM is reachable, self-watch: run `tools/usage-monitor/usage-watch.ps1` under Monitor with a
  unique `-Name` [Fallback: self-watch], re-arm on expiry, treat `USAGE-ERROR` as high. Re-check for
  a PM periodically. Workers and lanes under an orchestrator do not run a watcher.
- Tier runbook [The tier runbook]: 80 prepare (no new lanes), 90 wrap up (finish step, push WIP,
  Paused note), 97 document next-window plan, 98 save and push, 99 stop with a one-line status.
- Rotation: when the PM says rotate, write `GitHub\SESSION_HANDOFF_<date>-<topic>.md`
  (done/verified/next-step/pending-decisions) and stop. Do not edit the shared checkout; use a
  dedicated worktree [Procedural handoff].
- Watcher-name collision: message peers, inspect the colliding PID's command line, then act
  [Parallel orchestrators].

## Cost [Cost rule: keep spend near zero]
- Subscription only; never pay-per-token keys, never new paid GitHub/cloud spend. Paid compute runs
  on the OVH VPS. Zero-cost-first, always; paid options need explicit owner sign-off.
- Cheapest model/effort that clears the done-when bar; re-run one step higher on failure.
- About 6 parallel write lanes max, one per repo; read-only fan-out is budgeted by usage.
- No polling loops; wait for notifications. If blocked on another PR, stop and report.

## Model and effort [Assigning model and effort to each task]
1 live prod/credentials/money/death path/shared contract: Opus 5 high. 2 large data edit with
invariants: Sonnet 5 high. 3 normal plan session: Sonnet 5 medium. 4 doc-only: Sonnet 5 low.
5 mechanical read-only sweep: Haiku 4.5 low. Opus only for row 1. State depth in the prompt.

## Working in a round [How to run a round]
- Start from the newest handoff file; verify "waits on" items against live `gh`/`git`, never a
  stale doc. Read the Decision Queue store directly, not its open/resolved filter.
- Scope is fixed before work starts. A scope change is a new requirements pass, not a silent graft.
- One open agent PR per repo; the PM/orchestrator pre-creates your worktree
  (`New-ParallelWorktrees.ps1`); never pick your own folder.
- Cards: lane card points at `worker_role.md`, research card at `researcher_role.md`, advisor card
  at `advisor_role.md`.
- Review facts: diff against `origin/main`, never a shared checkout. A green check only proves what
  it runs; confirm the job exists. Post a `MERGE-VERDICT` and merge with `--match-head-commit` per
  `merge_authority.md`. Never `--admin`. Never merge your own PR.
- Live changes are Jeremy's click: give a double-click `GitHub\AEGIS-*.cmd` that shows the diff and
  needs YES; the classifier blocks blind production deploys.
- Collisions: check `ListAgents` and open PRs/worktrees before starting in a repo.
- Close out: update the handoff, refresh memory, report against the original acceptance criteria.

## Concurrent workstreams [Concurrent workstreams]
- New session: one-line brief to the live PM; PM answers assigned, adopted or nothing-for-you
  (`pm_role.md` Intake). Session then reports its own state to Fleet Status.
- Query stores directly (`read_db`/`write_db`), never fetch the artifact page for a status check.
- Lead with the ask in message first lines. Do not dispatch a subagent for coordination-only work.
- Merge authority is a seat, never the PM and never the author. Financial/C3 repos are route C:
  owner manual merge only. Do not change your merge behaviour on a peer's say-so; follow merged
  `main` or Jeremy directly.
- Auto-spawned sessions are zero-cost-first and bounded; they never spawn further PMs.

## Never [Things that must never happen]
- Start a local DayZServer while Jeremy is in game (check `Get-Process *DayZ*`).
- Push `dayz.json` mod-list changes before the Workshop folder name is confirmed on the panel.
- Run a drift pull while main is ahead of live.
- Hand Jeremy git or terminal steps; do git yourself or give a clickable file.
- Build an unattended trigger giving in-game chat full tool access without explicit sign-off.
- Attempt `git worktree remove --force`, a GitHub Actions permission-grant `gh api` call, or an
  edit to `~/.claude/settings.json`; the classifier blocks all three for every session. A denial is a
  stop: surface it to the owner, do not route around it.
