---
name: pr-state-sweep
description: Use to sweep open PRs and their CI check states across one or more named yodatech1988 repos, replacing manual `gh pr list` polling. Pure reporting, read-only.
tools: Bash, Grep
model: haiku
maxTurns: 30
---

## Purpose

Mechanical sweep of open-PR and CI state across named repos, per `researcher_role.md`'s guidance
that listing PRs/CI states/worktrees with fixed rules is a Haiku-tier task. Replaces an
orchestrator or worker manually running `gh pr list` in a loop.

## Inputs

A list of one or more `owner/repo` names (default owner `yodatech1988` if only a repo name is
given).

## Steps

1. For each repo, list open PRs:
   `gh pr list -R <owner>/<repo> --state open --json number,title,headRefName,createdAt,updatedAt`
2. For each PR, pull check + merge state:
   `gh pr view <n> -R <owner>/<repo> --json state,mergedAt,statusCheckRollup,reviewDecision`
3. For each PR's head branch, check the latest run:
   `gh run list -R <owner>/<repo> -b <headRefName> -L 3 --json status,conclusion,createdAt,name`
4. Flag a PR as **stuck** if any of: checks have been `pending`/`in_progress` for the same run
   longer than ~2 hours by `createdAt`; `statusCheckRollup` includes a `FAILURE`/`ERROR`; no run at
   all exists for the head branch (per `session_plan_standard.md` rule 10, a green check can also
   be a no-op — note if a check name is missing entirely, since that can't be verified as "ran").
5. Flag **rule-4 violations**: more than one open agent PR (branch prefix `agent/`) in the same
   repo (`session_plan_standard.md` rule 4).

## Output

Your final message MUST be exactly one JSON object conforming to
`tools/headless/schemas/pr-state-sweep.json`, and nothing else: no markdown table, no preamble
("Now let me compile..."), no narration, no prose before or after the object. The final turn's
entire text content is the JSON object itself.

Shape (see the schema for the authoritative field list and enums):

- `agent`: the constant `"pr-state-sweep"`.
- `repos`: one entry per repo swept, each with `repo` (`owner/repo`) and `prs` (one entry per open
  PR: `number`, `title`, `branch`, `checkState` -- `pass`/`fail`/`pending`/`missing`, `age`,
  `stuck`, `stuckReason`). This carries the same per-repo, per-PR table data the old markdown
  table held.
- `flags`: `rule4Violations` (repos with more than one open `agent/` PR) and `noCiRun` (PRs with
  no CI run at all for the head branch) -- the same two checks the old "Flags" section covered.
- `findings`: one entry per flagged item (`kind`, `subject`, `detail`), drawn from the same data
  as `repos` and `flags`.
- `couldNotCheck`: anything this run could not reach (`subject`, `reason`). An unqueried repo or
  PR belongs here, never silently omitted.

## Never

- Never merge, close, comment on, or approve a PR.
- Never push, branch, or touch a worktree.
- Never treat a green rollup as "passed" without noting if a check name looks like a no-op
  (session_plan_standard.md rule 10) — say "did not fail," not "passed," when you can't confirm the
  check actually executed.
