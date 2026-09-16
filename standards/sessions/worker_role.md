# Worker role

A worker is a session or background agent that builds **one lane**: one task in one repo, delivered
as one PR. The orchestrator (`orchestrator_role.md`) assigns the lane, and the worker follows this
file. `session_plan_standard.md` still applies. The orchestrator's prompt only needs a **lane card**
(template at the bottom); everything else is here.

## Before starting

1. Read only what the lane card lists. Don't re-survey other repos.
2. **Check for collisions.** Confirm the PR or branch the card names isn't already merged or
   taken:
   - `gh pr list -R yodatech1988/<repo> --state all --head <branch>`
   - `gh pr view <n> --json state`
3. **Work only in the worktree the card gives you.**
   - If it's missing, wait briefly and check again. Never create your own worktree unless the card
     says to, and then only with `GitHub\New-ParallelWorktrees.ps1`.
   - Never work in a repo's shared checkout (the plain folder under `GitHub\`).
4. **Fix the Status table first.** Correct your repo's `docs/PLAN.md` Status table against merged PRs
   on origin; it's often stale.

## While working

- Stay inside the card's scope. For anything out of scope: if it's small and obviously wrong, note it
  in the PR body; if it's bigger, file an issue after checking for duplicates. Don't fix it.
- **Verify invariants against real files** (live data, installed mod PBOs, the vanilla script
  extract), not memory or plan text. Plans and hook maps have been wrong. Cite the evidence in the PR.
  Never commit third-party mod source.
- **Business, design, money and gameplay-balance decisions:** list them in the PR body with a
  recommended default. Don't decide them yourself.
- **Tests and validators** (validate, pytest, npm test, econ_check, boot-test) must match the stated
  baseline. Report real counts, and never claim a pass you didn't observe. Anything that needs a
  real game client is an owner play-test item; list it and don't claim it.
- **Bulk or destructive batches** (the same action against N similar items — a worktree sweep, a
  batch edit, a mass removal) follow `session_plan_standard.md` rule 12: verify a small pilot batch
  against live state first and report it before the full set; re-check every single item against
  live reality immediately before acting on it, even when the list came from the lane card itself —
  a list is a claim, not verified state; capture any real content a destructive action would
  otherwise lose into a durable, git-tracked location before removing it.

## Never

- **Live actions:** no SFTP writes, no RCON beyond read-only `players`, no push, no restart, no repo
  variables or secrets, no deploys. Those are the owner's click, prepared by the orchestrator.
- **Local servers:** don't start a local DayZServer if `Get-Process *DayZ*` shows `DayZ_x64` or
  `DayZ_BE` (the owner is in game, and a local start kicks him). If you do start one, use your own
  port, profile and instanceId, back up any dev-server files you overwrite, and never kill a server
  you didn't start.
- **Git:**
  - no bare `git stash` (use a unique-tagged stash or a WIP commit)
  - no `--force` worktree removal
  - no force-push except `--force-with-lease` to your own agent branch
  - no merging your own PR, and no `--admin`
  - no GitHub Actions permission-grant via `gh api`, and no editing `~/.claude/settings.json`
    yourself — all three of these (plus `--force` worktree removal above) are hard-blocked by the
    auto-mode classifier for every session even with explicit written owner authorization already in
    hand; don't retry or route around a denial, report it and let the orchestrator/PM route it to
    Jeremy (`SESSION_HANDOFF_2026-09-16-pm-github28-close.md`; `docs/LESSONS.md`)
- **Secrets:** don't print, log or commit them. Credentials come from DPAPI stores
  (`%APPDATA%\AEGIS\*.clixml`) and go into a child process's environment only.
- **Loops:** no polling longer than a few minutes. If you're blocked on another PR, stop and report.
- **Cost:** don't create anything that spends money (paid runners, API keys, cloud resources).
- **Another session's checkout:** never edit a file in a repo checkout you don't own a dedicated
  worktree for — including a shared, non-worktree checkout another session is actively using, even
  to hand it a correction or content it would want. Send it as a message instead and let that session
  apply its own edit. Doing this even once, silently, is indistinguishable from an attempt to inject
  content outside review, regardless of whether the content itself was accurate
  (`docs/LESSONS.md` "Shared checkout... seen twice").

## Pause order

If the orchestrator sends "PAUSE" (usage limit):
1. Check your lane card's Priority. P0/P1: finish the step you're on and land the fix if you can
   before pausing. P2/P3: stop right now, mid-step is fine — don't spend more usage finishing.
2. Push WIP to your agent branch.
3. Write "Paused YYYY-MM-DD" (done, verified, exact next step, pending owner decisions) as a PR
   comment, or in your branch's PLAN.md Status row. Include how big the task actually turned out to
   be against its card's Size estimate (tool-call count if you have it, or "needed a second
   reboot round") — this is the calibration data `task_sizing.md`'s bands are built from.
4. Stop and reply in 3 lines or fewer.

"boots allowed" lifts a local-server pause.

## Delivering

- **One PR.** Commit messages end with the attribution line from the session's system reminder
  (currently `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`). The PR body ends
  with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- **The PR body contains:**
  - what changed and why
  - evidence
  - validator results
  - verified vs simulated
  - owner decisions
  - which files would deploy live, and how
- **Report back concisely, under ~25 lines:**
  - PR URL
  - done-when checklist, each item marked verified, simulated or pending
  - findings outside scope
  - owner steps
  - how the task's actual size compared to its card's estimate (per `task_sizing.md`)
- **Close your own lane out.** Once the PR merges, prune your worktree yourself
  (`session_plan_standard.md` rule 9) — this is part of finishing the lane, not a future cleanup
  sweep's job. If the PR can't merge yet (owner review pending, blocked on another PR), say so and
  leave the worktree; don't prune early and don't leave it dangling once it's actually done.

## Lane card (what the orchestrator sends)

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
