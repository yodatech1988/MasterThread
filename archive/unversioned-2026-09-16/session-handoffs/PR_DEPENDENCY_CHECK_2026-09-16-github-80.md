# PR ordering-dependency check — MasterThread #52, #44, #55, #56, #57 (github-80, 2026-09-16)

Requested by github-47 for github-8e's merge-queue dependency-ordering pass (26 queued PRs).
Method: read each PR's description AND actual diff (`gh pr diff <n>`), then check every file it
references against `origin/main` directly via `git cat-file -e origin/<branch>:<path>` — never the
shared checkout (which sits on an unrelated branch).

## Findings so far

### PR #55 — REAL dependency on PR #54
`standards/sessions/orchestrator_role.md`'s new "Usage watcher and PM handoff" section (line 33 of
the diff) says: `introduce yourself per \`worker_intro_prompt.md\`` — that file does not exist on
`origin/main` (confirmed: `git cat-file -e origin/main:standards/sessions/worker_intro_prompt.md`
fails). It only exists on PR #54's branch (`agent/masterthread/fleet-pm-policies`). **#55 must land
after #54**, or its merged doc will have a dangling reference.

### PR #57 — checked, NO real dependency (contrary to the hypothetical in the task brief)
The task brief's example ("#57 references worker_intro_prompt.md and task_sizing.md's telemetry
section, which only exist on #54") does NOT hold up against the actual diff. `gh pr diff 57` was
grepped for `worker_intro_prompt|telemetry|Real-time effort` — zero matches. #57's own PR
description explicitly says: *"worker_intro_prompt.md and a 'Real-time effort telemetry' section in
task_sizing.md, both named in the task brief, don't exist yet on origin/main — skills reference only
what's actually there."* Cross-checked every other `.md` path #57's diff references
(`orchestrator_role.md`, `session_plan_standard.md`, `task_sizing.md`, `priority_classification.md`,
`worker_role.md`, `docs/AGENTS.md`, `docs/REPOS.md`, generic per-repo `docs/PLAN.md`, conditional
`AGGREGATE.md`) — all either exist on `origin/main` or are explicitly generic/conditional
references, not broken ones. **#57 can land independently of #54.**

### PR #52 — unresolved anomaly, not a simple ordering dependency, needs more digging
Indexes 7 new T4 agents in `docs/AGENTS.md` (`review-tier-recommender`, `automerge-preflight`,
`secrets-handling-auditor`, `incident-response-drafter`, `agent-automation-gatekeeper`,
`data-classification-tagger`, `budget-envelope-reporter`), claiming they're "files already written
by parallel background agents this round." Searched for their actual source `.md` files:
- Not on MasterThread's `claude-agents/` path (checked a MasterThread worktree/branch that has that
  path — files missing there too).
- Not in the real standalone `claude-agents` repo: missing on `origin/master` (its actual default
  branch — not `main`), AND `git log --all --diff-filter=A -- <file>` across every branch/commit in
  that repo's full history returns nothing for any of the 7 files. They are not git-tracked
  anywhere I can find in that repo.
- They ARE listed as live/available Agent types in this session's own tool schema, so they exist
  *somewhere* the harness reads from (likely a local, uncommitted `.claude/agents/` directory) —
  this may be a "docs got ahead of a source-control step that was skipped/forgotten" gap rather than
  a branch-ordering dependency. Was mid-`find` across the filesystem for the actual file location
  when paused; **not yet concluded**.
- Action for whoever picks this back up: finish locating the 7 files, then decide whether #52 is
  fine (files exist locally and just need a separate "commit the agent definitions" PR to catch up)
  or whether #52 documents agents that were never actually persisted anywhere durable.

### PR #44 — checked, NO ordering dependency (also independently confirmed clean by github-8e)
Grepped the full diff for every referenced `.md` path. All resolve on the correct repo's real
default branch once matched to the right repo (the PR text qualifies most of them — `` `aegis-services` `docs/ops/VPS.md` ``,
`` `docs/ops/FUND-EMBED.md` (in `services`) `` — both confirmed to exist on `services`'
`origin/main`). One unqualified reference, `` `docs/mods/README.md` ``, is ambiguous by text alone
(no repo named) but resolves fine — confirmed present on `site-chernarus`'s `origin/main` (and
`core`'s, same tracker convention in both). The `aegis-website-build.md` mentions are inside
**removed** (`-`) lines — old content this PR deletes, not a new reference it adds. **No blocker.**
Note for whoever reads this later: the unqualified `docs/mods/README.md` line is worth a one-word
repo tag for clarity, but that's a polish nit, not a merge blocker.

### PR #56 — checked, NO ordering dependency (also independently confirmed clean by github-8e)
Full diff read (only touches `docs/REPOS.md`, 35 lines). Every PR number it cites as open —
`ops-policies` #13, `ops-infra` #9 and #10, `ops-platform` #10 — was verified against live `gh pr
list` state and matches exactly (all still open, titles match). Note: the diff also adds rows for
`ops-infra`, `ops-platform`, `ops-business`, and `ops-household` beyond the two (`ops-policies`,
`_security-public`) the PR *description* mentions — a stale/incomplete description relative to its
own diff, worth a one-line description edit, but not a merge blocker since the extra content is
accurate. **No blocker.**

## PR #52's anomaly — RESOLVED (re-verified per github-47's methodology note: `git ls-tree`/`git log
--all` against real refs, not a diff against a moved `main`, and cross-checked against a
known-good control case first)

Split finding — the 7 agents PR #52 indexes are NOT all in the same situation:

- **6 of them** (`review-tier-recommender`, `automerge-preflight`, `secrets-handling-auditor`,
  `incident-response-drafter`, `agent-automation-gatekeeper`, `data-classification-tagger`) exist
  **only as uncommitted, staged files** in one local worktree on this machine:
  `<USER_HOME>\GitHub\_wt-MasterThread-agent-roster-git-backup`
  (branch `agent/MasterThread/agent-roster-git-backup`, confirmed via `git log --oneline`: *"your
  current branch ... does not have any commits yet"* — zero commits, ever). `git status --short`
  there shows all 6 as `A  claude-agents/<name>.md` alongside **771 other staged-but-never-committed
  files** (the apparent full local `.claude/agents/` roster plus an unrelated `Agents/business/*`
  tree). None of this has ever been pushed to `origin` — confirmed via `git log --all --diff-filter=A
  -- <file>` across every branch of the real `claude-agents` repo (empty result for all 6) and a
  full sweep of every locally-cloned repo's every remote branch (`git ls-tree -r <ref>` for each,
  sanity-checked against a known-good control — `budget-envelope-reporter.md`, findable on
  `ops-platform`'s `origin/agent/ops-platform/t4-agents` — to confirm the detection method itself
  works). **If this one worktree/machine were lost, these 6 agent definitions have zero recovery
  path — no commit, no branch, no PR, nowhere.** This is a real risk, but it is not simply a
  branch-ordering question the merge queue can sequence around: someone needs to actually commit
  and push `_wt-MasterThread-agent-roster-git-backup`'s staged state (or the specific 6 files, if
  the other 765 files in that stage aren't meant to ship the same way) to a real branch/PR before
  **or as part of** landing #52, otherwise #52 merges documenting agents whose source has no home.
- **The 7th, `budget-envelope-reporter`**, is a normal, milder case: properly git-tracked at
  `.claude/agents/budget-envelope-reporter.md` on `ops-platform` PR #10 (open, not yet merged,
  title: "docs: add T4 subagent (budget-envelope-reporter)"). This one **is** a straightforward
  ordering dependency — #52 should land after (or together with an explicit note pending)
  `ops-platform` #10, same shape as #55↔#54.

**Recommendation for the merge queue:** don't block #52 on the 6-agent finding the same way as a
normal PR dependency (there's no PR to depend on yet) — flag it back to whoever owns the T4-agent
roster process to either (a) push the backup worktree's relevant files as a real PR first, or (b)
have #52 explicitly note in its own body that those 6 definitions are local-only pending a
follow-up commit, so the doc isn't silently overclaiming. Either way, **#52 should not merge
silently as-is** without one of those two things happening.

## Status: all 5 PRs checked. Summary
- **#55**: real dependency on #54 (already has a dependsOn block per github-47, confirmed).
- **#57**: checked, no real dependency (task brief's example didn't hold up against the actual diff).
- **#52**: real dependency on `ops-platform` #10 (budget-envelope-reporter) + a separate, more
  serious "6 agent files have no git home at all" risk that isn't a simple ordering fix.
- **#44**: checked, no dependency (also confirmed independently by github-8e).
- **#56**: checked, no dependency (also confirmed independently by github-8e).
