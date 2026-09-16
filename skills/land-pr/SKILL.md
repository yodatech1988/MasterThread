---
name: land-pr
description: Use when a lane's PR is ready to receive a follow-up push, be reviewed, or be merged — re-checks live PR state before writing anything, routes to the correct reviewer agent by scope, verifies a stacked-PR merge landed for real, and updates the repo's PLAN.md afterward.
---

# land-pr

## When to use this

- Before pushing any follow-up commit to an existing PR branch (a fix requested by review, a pause
  WIP push, a rebase).
- Before merging any PR.
- After a PR (or a stack of PRs) shows as merged, to confirm it actually landed on `origin/main`.

## Procedure

1. **Re-check PR state before pushing anything, every single time** — even if you checked it five
   minutes ago in the same session:

   ```
   gh pr view <n> --json state,mergeable,statusCheckRollup
   ```

   A PR can merge mid-session (another session, or the owner clicking merge) and strand your next
   commit on a dead branch. If `state` is not `OPEN`, stop — don't push. Re-derive whether the
   work still applies (new PR? already landed some other way?) before continuing.

2. **Route the merge review to the correct reviewer by scope**, per `docs/AGENTS.md` and
   `worker_role.md`'s model table row 1:
   - **Default: `diff-reviewer`** (Sonnet, `docs/AGENTS.md`) — for every normal PR. It reads
     `gh pr diff <n>` for known crash patterns, accidentally committed secrets, and removed-mod /
     removed-file names reappearing.
   - **Reserve `live-reviewer`** (Opus, `docs/AGENTS.md`) **only** for PRs that touch live
     production (push/restart/wipe), credentials/secrets, money (QuickBooks), the death/damage
     path, or that set a contract other sessions build on (core module APIs, perk hooks, RPC
     dispatch) — `orchestrator_role.md`'s model/effort row 1. Don't default to it "to be safe"; an
     Opus review on ordinary work is the cost mistake `orchestrator_role.md`'s cost rule exists to
     prevent.

3. **Do the standard pre-merge checks** (`orchestrator_role.md` step 5 / `session_plan_standard.md`
   rule 10) regardless of which reviewer ran:
   - `gh pr view --json files,statusCheckRollup,mergeable`
   - Read the diff yourself; a green check means "did not fail", not "passed" — confirm what
     actually ran (e.g. a `validate` job with no token can report success while skipping
     everything).
   - Diff any "identical to X" claim against `origin/<default>` of X, not a local checkout.
   - A stale bot review (CHANGES_REQUESTED) is dismissed only after the fix is verified in the
     diff — never `--admin`, never self-approve around it.
   - Never merge your own PR.

4. **For a stacked PR, verify the merge landed correctly** — don't trust "the PR shows merged" by
   itself (a stacked merge can land in a parent branch instead of `main`,
   `github-stacked-pr-merge` incident class):

   ```
   git fetch origin
   git merge-base --is-ancestor <branch> origin/main && echo "landed on main" || echo "NOT on main yet"
   ```

   Only treat the work as actually shipped once this returns "landed on main" (exit 0).

5. **Update the repo's `docs/PLAN.md` Status table afterward.** Tick the session's row, correct any
   contract the PR changed, and — if the *next* session to run in that repo changed as a result —
   update that repo's row in `MasterThread/docs/REPOS.md` too (`session_plan_standard.md` rule 6).

## Never

- Never push a follow-up commit without re-checking `gh pr view --json state` first — a PR merging
  mid-session and stranding commits is a recorded incident (`aegis-check-pr-state-before-followup-push`).
- Never send an ordinary PR to `live-reviewer` by default — it's Opus-tier and reserved for
  live/credential/money/death-path/contract scope only; everything else goes to `diff-reviewer`.
- Never treat "the PR shows merged" as proof it landed on `main` for a stacked PR — confirm with
  `git merge-base --is-ancestor <branch> origin/main`.
- Never merge with `--admin`, never self-approve to get around a stale CHANGES_REQUESTED, and never
  merge your own PR.
- Never skip updating `docs/PLAN.md`'s Status table (and `REPOS.md` if the next session changed) —
  a stale plan is exactly what makes the *next* round's `round-start` re-verification necessary.

## Done-when

- The PR's live state was confirmed `OPEN` immediately before the push that landed it, or the merge
  itself.
- The correct-scope reviewer (`diff-reviewer` by default, `live-reviewer` only for row-1 scope) has
  produced a verdict, and its findings are addressed or explicitly deferred with a reason.
- For a stacked PR, `git merge-base --is-ancestor <branch> origin/main` confirms it, not just the
  PR's displayed state.
- `docs/PLAN.md`'s Status table row is updated to match, and `REPOS.md` is updated if the next
  session changed.
