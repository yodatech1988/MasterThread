# Worker role

A worker is a session or background agent that builds **one lane**: one task in one repo, delivered
as one PR. The orchestrator (`orchestrator_role.md`) assigns the lane, and the worker follows this
file. `session_plan_standard.md` still applies. The orchestrator's prompt only needs a **lane card**
(template at the bottom); everything else is here.

Read `lessons_learned_2026-09-16.md` (same directory) alongside this file at session startup — it
records why several rules below exist, grounded in real, verified incidents rather than
hypotheticals. In particular: "Before starting" item 3 below (never work in a repo's shared
checkout) is there partly because that round found a shared checkout can silently present an
unmerged branch as the adopted standard to every session reading it.

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

## Reading the repo: what you looked at is part of the finding

Two search habits produced four wrong conclusions across four sessions on 2026-09-17, each one
reported confidently before anyone checked. Both are cheap to avoid and neither is obvious.

**Read `origin`, never a working tree.**

```
git fetch -q origin main
git show origin/main:<path>
```

A shared checkout sitting on `main` can still be far behind — one was **8 commits behind** that day,
and a session grepping it reported a plan instructing the owner to build a system that had been
superseded, complete with a line number. The line number was the tell: the text existed, just not on
`main`. A worktree is whatever its lane last rebased onto, and there were **13 worktrees for one
repo, 7 of them carrying pre-rewrite text**. Before quoting a file at the owner or another lane,
confirm which tree you read it from.

**Ripgrep honours `.gitignore`, so it silently skips untracked work in sibling worktrees** — which
is exactly where every parallel lane's in-progress deliverable lives. Two sessions each concluded the
other's work "does not exist anywhere in the estate", and both were wrong; one of those was a
450-line rescue procedure whose absence was being reported as a program risk. Use `--no-ignore` (or
`-uu`) when the question is "does this exist anywhere", and search `git ls-files` plus the worktree
list when the question is "is anyone already doing this".

**`--is-ancestor` does not prove a squash-merge.** `git merge-base --is-ancestor HEAD origin/main`
**fails on a branch that was squash-merged**, because the squash commit carries a different SHA to
every commit on the branch. That failure is not evidence the merge did not happen, and reading it as
such retracts a landed PR. Check the PR's `state` *and* the content on `origin/main` instead — that
the files are there and say what they should. One session nearly misreported a merged PR as unmerged
on this in a single evening.

**`gh pr view` reads stale immediately after a push.** A branch you have just pushed can report
`mergeable: CONFLICTING` and `mergeStateStatus: DIRTY` — or `UNKNOWN` — for a minute or more while
GitHub recomputes, and a stale `CONFLICTING` is indistinguishable from a real conflict. The wrong
response, and the tempting one, is to start re-resolving a conflict that no longer exists. Settle it
locally instead:

```
git merge-base --is-ancestor origin/main HEAD    # does my branch already contain everything on main?
git merge-tree --write-tree origin/main HEAD     # does a test-merge actually conflict?
```

If those two are clean, the `gh` read is stale — wait and re-read rather than touching the branch.
Seen four times on 2026-09-17.

**State what you searched.** "I searched and found nothing" is close to worthless here on its own.
Say which tree, which ref, and what the search excluded — that lets the next reader spot the gap
instead of inheriting the conclusion.

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

- **Scope — adjacency is not authority.** Having the context for a neighbouring task is a reason to
  be *asked* for it, never a reason to start it. Your scope came from the owner; finishing it does
  not extend it to whatever is next to it. Picking up adjacent work because you happen to hold the
  design in your head produces work the owner did not ask for and cannot easily audit — and it is
  how one interface ends up designed twice, incompatibly, by two lanes that each believe they own
  it. Flag the gap, offer a constraints note if one would help whoever does take it, and let the
  owner assign it. On 2026-09-17 two lanes independently declined the same adjacent design within
  minutes of each other, on this reasoning, without coordinating; the PM had assigned it to one of
  them and was wrong to.
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
- **Waiting on another session's handoff:** never block or poll waiting for a peer session to finish
  its handoff. Use `SendMessage` with `notify_when_idle: true` on that session (a one-shot
  subscription, no message needed if you have nothing to say yet) and move on to any other in-scope
  work while you wait. If there's genuinely nothing else to do, stop and report that you're blocked
  and subscribed — don't sit idle checking back. (2026-09-16 owner decision: the ops-cycle chain was
  repeatedly stalling on sessions waiting on each other's handoffs; this is the fix.)
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

## After delivering — end of workstream

**Standing behavior (owner decision, 2026-09-17): finishing a lane is not license to pick the next
one yourself.** A worker that just delivered does not idle, and does not self-assign follow-on work
just because it noticed something in scope — it documents, caches, and asks. This closes the gap
between "Delivering" above (how to hand off *this* lane) and "Before starting" (how the *next* one
begins): the missing middle step, so a fresh session or a fresh conversation window is a cheap
restart rather than a cold one.

1. **Write the lessons-learned block**, same three parts already required of T4 agent definitions
   (`aegis-lessons-learned-loop` in memory) — don't skip it just because this is a worker session, not
   an agent definition:
   - Assumption that turned out false (expected vs. actually found), or the literal word `none`.
   - Rule candidate — one line, phrased as a check that could have fired *earlier* than this lane did.
   - Where it belongs — a skill's never-list, a named MasterThread standard, or a memory file.
   Append it to `MasterThread/docs/LESSONS.md` (create the entry with round date + source lane, per
   the ledger convention `aegis-lessons-learned-loop` describes) — not only in the PR body, which the
   PM has no standing reason to re-open once the PR is merged. This is on the worker, not deferred to
   whoever runs the next full round.
2. **Cache the session's state so the restart is genuinely cheap**, not just committed:
   - Everything is pushed (already required above) and the repo's `docs/PLAN.md` Status row reflects
     reality.
   - Write or refresh this session's own Fleet Status row (`sessions/<name>` in the live Fleet Status
     artifact db, `fleet_status_standard.md`) with `state: done`, `committed` describing exactly what
     landed, and `nextStep: awaiting PM assignment`. A session with nothing written there is invisible
     to the PM's intake — this row *is* the cache; there is no separate mechanism.
3. **Ask the PM for the next work card — don't self-guide into one.** Report completion to the PM
   (or, per `session_bootstrap.md`'s fallback, to the owner directly if no PM is reachable) and stop
   there. If the PM doesn't answer immediately, use `notify_when_idle` and wait — this is the same
   rule as "Waiting on another session's handoff" above, not a new exception to it. Noticing
   obviously-in-scope follow-on work stays limited to *noting* it (per "While working"); it is not
   grounds to open a second lane unassigned. The PM, not the worker, decides whether a session
   continues, rotates, or stands down (`orchestrator_role.md` / `pm_role.md`'s session-rotation
   rules).
4. **Only pick up new work when told to** — by an explicit lane card from the PM, or, absent any
   reachable PM, an explicit instruction from the owner. "The PM hasn't replied yet, but there's an
   obvious next thing" is exactly the case this section exists to close off.

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
