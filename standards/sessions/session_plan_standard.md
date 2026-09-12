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
the first two; the review cap (core PR #43) fixes the third.

## Rules

1. **One session = one conversation = one PR.** Start fresh each time; never continue a finished session.
2. **Open Claude Code in the repo folder**, not the `GitHub/` root, so only that repo's context loads.
3. **A session reads only its Read list.** If it needs more, it records why in the PR, so the plan improves.
4. **At most one open agent PR per repo.** Merge or close it before starting the next session.
   Unmerged PRs pile up conflicts, and every later session pays to re-read and rebase them.
5. **Contracts go in the plan.** When pieces must fit together (interfaces, schemas, file formats),
   write them in `docs/PLAN.md` so a session never has to read another session's code to comply.
6. **The PR that finishes a session also updates the plan.** Tick the session and correct any contract
   it changed. If the next session changed, update the repo's row in MasterThread `docs/REPOS.md`.
7. **Secrets and business decisions go to the owner.** Everything else, the session decides and
   records. An open owner decision gets a stated default so sessions aren't blocked on it.
8. **No repo-wide surveys.** A plan-writing session (Session 0) reads the README, the open issue/PR
   *titles*, and the docs those name, not the source tree.

## `docs/PLAN.md` shape

Use [`PLAN_template.md`](PLAN_template.md). Every session has:

| Field | Purpose |
|---|---|
| Read | The exact files or sections to load. Nothing else. |
| Do | The change, concretely enough to start without exploring. |
| Out of scope | What is deliberately left for later, so the session doesn't drift. |
| Done when | Checkable: tests, a command's output, a merged PR. |
| You | Anything only the owner can do (credentials, installs, decisions). Omit if none. |
| Starter prompt | One line to paste into a fresh session. |

Keep each session to roughly one PR a reviewer can read in one sitting. If a session needs more,
split it. Aim for 3–7 sessions per plan; write the next plan when this one is done.

## Session 0: writing a plan for a repo that has none

Starter prompt, run from inside the repo folder:

> Follow MasterThread `standards/sessions/session_plan_standard.md` Session 0. Read only README.md,
> the open issue and PR titles (`gh issue list`, `gh pr list`), and docs they reference. Write
> docs/PLAN.md from the template and a ≤15-line CLAUDE.md, open one PR, and tell me which MasterThread
> REPOS.md row to update.

The plan must state which open PRs to merge or close first. Rule 4 applies to the backlog too.

## `CLAUDE.md` in each repo

Claude Code loads this on every turn, so it stays short: a pointer, not documentation.

```markdown
# <repo>

Work here follows MasterThread `standards/sessions/session_plan_standard.md`.

- Plan: `docs/PLAN.md`. Do one session per conversation, and read only that session's Read list.
- At most one open agent PR at a time; branch `agent/<repo>/<slug>`, squash merge.
- Tests: `<command>`.
- Never commit secrets; `.env.example` documents what's needed.
```
