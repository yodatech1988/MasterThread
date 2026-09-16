---
name: dispatch-lane
description: Use when the round-start dispatch plan is ready and it's time to actually hand a lane to a worker session — creates the isolated worktree, checks for collisions, and emits a properly formatted lane card.
---

# dispatch-lane

## When to use this

- Immediately after `round-start` has produced an ordered dispatch plan, for each lane about to
  be assigned to a worker session or background agent.
- Any time a single new lane is being added mid-round (e.g. a P0 that just appeared).
- Not for read-only fan-out (a `pr-state-sweep`, a `plan-status-check`, an advisor verdict) — those
  go straight to a T4 subagent via `docs/AGENTS.md`, no worktree, no lane card.

## Procedure

1. **Check `ListAgents` first.** Confirm no other live session is already working this repo/branch
   — a duplicate dispatch into the same repo is a collision by construction
   (`session_plan_standard.md` rule 9: never two write lanes in one repo at once).

2. **Run the `collision-check` subagent** (Haiku, read-only, `docs/AGENTS.md`) against the target
   repo before creating anything. It confirms: no existing open PR/branch already covers this task,
   and no stale worktree from a previous run is still sitting there uncleaned.

3. **Enforce "one open agent PR per repo."** If `collision-check` (or your own `gh pr list -R
   yodatech1988/<repo> --state open`) shows an existing open agent PR for this repo, that PR *is*
   the lane — don't open a second one. Route the new work as a follow-up commit to that PR (via
   `land-pr`'s re-check step) or queue it for after that PR merges/closes.

4. **Create the lane's worktree yourself, before dispatching**, using
   `GitHub\New-ParallelWorktrees.ps1`. Per that script's own header warning, call it **in-process**
   (dot-and-ampersand `& .\New-ParallelWorktrees.ps1 ...` in the current PowerShell session, or
   dot-source it) — **never** spawn a nested `powershell -File ...` process for it, because a
   comma-separated `-Slugs` array does not reliably bind across a fresh process boundary (observed:
   the second slug silently bound to `-DefaultBranch` instead). If the current shell hasn't
   bypassed execution policy yet this session, run
   `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force` first.

   ```
   & C:\Users\yoda_\GitHub\New-ParallelWorktrees.ps1 -Repo <repo> -Slugs '<slug>'
   ```

   This matches `session_plan_standard.md` rule 9's convention exactly:
   `git worktree add ../_wt-<repo>-<slug> -b agent/<repo>/<slug> origin/<default>`.
   Never let the worker create or pick its own worktree path — that ambiguity is the root cause of
   the 2026-09-14 aegis-mods collision (one lane's PR ended up carrying two other lanes' commits).

5. **Emit the lane card** in the exact `worker_role.md` format, pointing the worker at the file
   itself rather than re-explaining its rules:

   ```
   You are a worker: follow MasterThread standards/sessions/worker_role.md.
   Lane: <id> — <repo> — <one-line task>
   Priority: <P0/P1/P2/P3 — one line why, per MasterThread standards/sessions/priority_classification.md>
   Size: <S/M/L/XL, per MasterThread standards/sessions/task_sizing.md>
   Worktree: C:\Users\yoda_\GitHub\<_wt-...> on branch <agent/...>
   Read: <files/issues/PLAN session>
   Do: <scope>
   Out of scope: <list>
   Done when: <checklist, incl. baseline counts>
   Extra constraints: <live/in-game/collision notes, if any>
   ```

   The card only needs what's specific to this lane — `worker_role.md` already carries the
   never-list, attribution, pause protocol, one-PR rule, and report format, so don't repeat those
   in the card.

6. **If the lane needs a specialist reviewer at land time**, note which one in "Extra constraints"
   now (per `land-pr`'s scope routing) so the worker/orchestrator doesn't have to re-derive it
   later: `diff-reviewer` for a normal PR, `live-reviewer` only if the task is genuinely
   live-prod/credential/money/death-path/contract scope.

## Never

- Never dispatch into a repo without running `collision-check` (or the manual `gh pr list`/`gh pr
  view` equivalent) first — a session collision from two lanes racing the same repo is a recorded
  incident.
- Never let a worker choose or create its own worktree folder; always pre-create it with
  `New-ParallelWorktrees.ps1` and hand over the exact path.
- Never call `New-ParallelWorktrees.ps1` via a nested `powershell -File ...` process — call it
  in-process (dot-and-ampersand) per its own header warning; a spawned process can silently
  mis-bind a multi-value `-Slugs` array.
- Never open a second agent PR in a repo that already has one open — that's the "one open agent PR
  per repo" rule, and violating it piles up rebase conflicts every later session pays for.
- Never write a lane card that duplicates `worker_role.md`'s never-list, attribution or pause
  protocol instead of pointing at the file — the card is only the lane-specific delta.

## Done-when

- `collision-check` (or the manual equivalent) has run clean for this repo/branch.
- The lane's worktree exists at the expected `_wt-<repo>-<slug>` path on `agent/<repo>/<slug>`,
  created in-process by `New-ParallelWorktrees.ps1`, before the lane card is sent.
- A lane card in the exact `worker_role.md` template has been handed to the worker, with an exact
  worktree path (never "pick one yourself").
- At most one open agent PR exists for the target repo after dispatch.
