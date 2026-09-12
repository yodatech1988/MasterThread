# Session plan standard

How AI-assisted work is planned and run across every yodatech1988 repo. The goal is to spend
tokens on doing the work, not on re-discovering context.

**GitHub is the ledger.** A plan lives in the repo it's about (`docs/PLAN.md`). Its progress lives in
that repo's issues and PRs. [`docs/REPOS.md`](../../docs/REPOS.md) in MasterThread is the one index
of every repo, its plan and its next session. No one reads a past conversation to find out where
things stand.

## Why

One long conversation re-sends its whole history on every turn, so cost grows with length rather
than with work. Broad sweeps ("review all my repos") read far more than any task needs. And the
automated Claude review on every PR push multiplied both. Small sessions with explicit read-lists fix
the first two; the review cap (core PR #43, merged 2026-09-12) fixes the third.

Two more lessons from the first day of running this (2026-09-12) are now rules 9 and 10: two
sessions edited the same shared checkout and collided (core PR #41), and a batch of nine all-green
PRs hid three real defects because the checks that were green had not actually run.

## Rules

1. **One session = one conversation = one PR.** Start fresh each time; never continue a finished session.
2. **Open Claude Code in the repo folder or worktree**, not the `GitHub/` root, so only that repo's
   context loads.
3. **A session reads only its Read list.** If it needs more, it records why in the PR, so the plan improves.
4. **At most one open agent PR per repo.** Merge or close it before starting the next session.
   Unmerged PRs pile up conflicts, and every later session pays to re-read and rebase them.
5. **Contracts go in the plan.** When pieces must fit together (interfaces, schemas, file formats),
   write them in `docs/PLAN.md` so a session never has to read another session's code to comply.
6. **The PR that finishes a session also updates the plan.** Tick the session and correct any contract
   it changed. If the next session changed, update the repo's row in MasterThread `docs/REPOS.md`.
7. **Secrets, money and business decisions go to the owner.** Everything else, the session decides
   and records. An open owner decision gets a stated default so sessions aren't blocked on it.
   Owner-only, always: real secrets and tokens; anything that spends money, including a test run
   (rule 11); business calls with no documented ranking; merging anything personal or financial
   (the auto-merge gate in core's `claude-review.yml` vetoes those, and the veto is never loosened
   without asking).
8. **No repo-wide surveys.** A plan-writing session (Session 0) reads the README, the open issue/PR
   *titles*, and the docs those name, not the source tree.
9. **Work in a worktree, never the shared checkout.** Fetch first, then branch from the remote
   default branch, not from whatever the local checkout happens to be on:

   ```
   git fetch origin
   git worktree add ../_wt-<repo>-<slug> -b agent/<repo>/<slug> origin/<default>
   ```

   Prune the worktree when the PR merges. Parallel sessions run across repos, never two in one repo
   (rule 4 makes that a collision by definition).
10. **Verify before merge.** A PR body, a commit message, an issue comment and a committed doc are
    claims, not evidence. Before merging:
    - Read the diff. Diff "identical to X" claims against `origin/<default>` of X, not a local checkout.
    - Treat a green check as "did not fail", not "passed". A check can be a no-op: site-chernarus
      `validate` ran nothing for weeks without a `CORE_READ_TOKEN`, and a Claude review with no API
      key reports success while skipping. Find out what actually ran.
    - Recount any number a doc states before repeating it, and check what a config value
      *resolves to*, not what it says (a `-1` that means "inherit" is not "off").
    - A "past decision" attested only by the repo's own PR/commit/issue trail is confirmed with the
      owner before it is treated as settled.
    - A stale bot review that blocks a PR is dismissed only after the fix is verified in the diff.
11. **Zero cost first.** Every repo follows core's cost rule (`docs/_project-context.md`, core PR
    #45): free tiers, owned hardware and open source by default; paid resources only when no free
    option works *and* live server, player data, security or a launch blocker depends on it. Any
    per-run paid automation is opt-in per repo, capped (`--max-budget-usd`), and runs on
    `opened`/`reopened`/`ready_for_review` only, with re-review through a label, never on every push.
    Adding or re-enabling spend is the owner's call, and the zero-cost alternative is presented with it.

## `docs/PLAN.md` shape

Use [`PLAN_template.md`](PLAN_template.md). Every session has:

| Field | Purpose |
|---|---|
| Read | The exact files or sections to load. Nothing else. |
| Do | The change, concretely enough to start without exploring. |
| Out of scope | What is deliberately left for later, so the session doesn't drift. |
| Done when | Checkable: tests, a command's output, a merged PR. |
| You | Anything only the owner can do (credentials, installs, decisions). Omit if none. |
| Model | Which model runs it (see "Rounds"). Omit to take the default. |
| Starter prompt | One line to paste into a fresh session. |

Keep each session to roughly one PR a reviewer can read in one sitting. If a session needs more,
split it. Aim for 3–7 sessions per plan; write the next plan when this one is done.

## Rounds: running sessions in parallel

Sessions run in **rounds**: all lanes start together, one per repo, each in its own worktree with
its own model and paste-ready prompt. A round ends when the owner merges or closes every lane's PR
in one sitting. The next round's prompts are written before the current one closes, so the owner
never waits on planning. The current round sheet is kept next to the checkouts
(`GitHub/SESSION_ROUNDS_<date>.md`); when a round closes, `docs/REPOS.md` rows are refreshed from it.

| Model | Use for | Reason |
|---|---|---|
| **Sonnet 5** (default) | Session 0 plans with a template and a short Read list; sessions whose `PLAN.md` already spells out the Do; housekeeping | Cheapest model that reliably follows a written spec. |
| **Opus 5** | Sessions that triage many PRs, or design a plan from scattered sources; PR review in CI | A wrong merge/close list costs more than the model delta. |
| **Fable 5.1** | One-off hard merges where two sessions already collided | One correct three-way merge beats a third attempt. |
| Haiku 4.5 | Nothing | Sessions touch unpushed work and delete worktrees. |

## Session 0: writing a plan for a repo that has none

Starter prompt, run from inside the repo folder:

> Follow MasterThread `standards/sessions/session_plan_standard.md` Session 0. Read only README.md,
> the open issue and PR titles (`gh issue list`, `gh pr list`), and docs they reference. Write
> docs/PLAN.md from the template and a ≤15-line CLAUDE.md, open one PR, and tell me which MasterThread
> REPOS.md row to update.

The plan must state which open PRs to merge or close first. Rule 4 applies to the backlog too.

A **new site repo's** Session 0 also reads the monetization plan and the donations plan and
re-decides, in its own `docs/PLAN.md`, whether either applies to that site
(`docs/REPOS.md`, "Standing rule: always carry a live monetization plan"). A **module repo's**
Session 0 follows the [Workshop mod standard](../dayz/workshop_mod_standard.md).

## `CLAUDE.md` in each repo

Claude Code loads this on every turn, so it stays short: a pointer, not documentation.

```markdown
# <repo>

Work here follows MasterThread `standards/sessions/session_plan_standard.md`.

- Plan: `docs/PLAN.md`. Do one session per conversation, and read only that session's Read list.
- At most one open agent PR at a time; branch `agent/<repo>/<slug>` in its own worktree, squash merge.
- Tests: `<command>`.
- Never commit secrets; `.env.example` documents what's needed.
```
