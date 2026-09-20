# Token efficiency audit — yodatech1988 org, 2026-09-14

Researcher pass, read-only, against `origin/<default>` for all repos (not local checkouts). Two
parts: (A) spend that still needs Claude but is shaped wastefully, and (B) recurring actions that
don't need an LLM at all and fit the VPS cron/systemd-timer pattern core#74/services#86 just built
for ops-scheduled/ops-backup/economy-catalog-sync/economy-monitor
(`services/docs/ops/VPS.md`, `services/ops/vps/aegis-run-job.sh` on PR #86's branch). Each part is
ranked highest-impact first.

## PART A — wasteful but still needs Claude

### A1. Every PR review runs Opus 5 at `high` effort, regardless of PR size (highest impact)

`core/.github/workflows/claude-review.yml` (the reusable workflow every other repo's
`pr-review.yml` calls via `uses: yodatech1988/core/.github/workflows/claude-review.yml@main`)
defaults `model: claude-opus-5` / `effort: high` unconditionally (lines ~138-149). The header's own
justification (line ~108-113) says this is fine because it's "low volume (one run per PR push)" —
that assumption is now false. Measured today: **68 PRs in `core` and 77 in `services` in the last 3
days** (`gh pr list --search "created:>=2026-09-11"`), the large majority small doc/status/one-file
fixes from parallel automated sessions, not the rare, high-stakes human PR the reasoning pictures.
Every one of those still gets a full Opus-5/high review-and-verdict pass because the workflow has
no size- or content-based gate — a one-line `STATUS.md` typo fix and a multi-file schema change cost
the same review. `core`, `services`, `site-chernarus`, `aegis-mods`, `aegis-poi`, `aegis-pricing`,
`website`, `claude-agents`, `site-badlands` all wire into this same reusable workflow, so the fix
(a cheaper model/effort default for small/docs-only diffs, escalating to Opus/high only past a
line/file threshold or a path filter such as "touches `.github/` or a DB migration") multiplies
across 9 repos at once. This is the same 82-review-in-3-days pattern already flagged in memory
(`aegis-claude-review-rollout-status`); this audit adds the root cause (fixed model/effort, no
size gate) and the confirmed blast radius (9 repos share one workflow).

### A2. `labeled` re-review fires a second full Opus pass, sometimes minutes apart

`pr-review.yml` triggers on `[opened, reopened, ready_for_review, labeled]` — no `synchronize`
(intentional, already documented as a cost control). But `labeled` has no filter on *which* label;
any label add re-runs the full review. Run history shows this actually happening: `core`'s
2026-09-14T14:09:49Z and 14:09:54Z runs are the same PR (Session 5 / core#72 & site-chernarus#86)
five seconds apart, and `services`' 06:31:39Z/06:52:22Z runs are the same "gateway Session G3" PR
21 minutes apart. Restricting the trigger to `github.event.label.name == 'claude-review'` (the
label the header says is the intended re-review mechanism) instead of any label would remove
accidental re-reviews triggered by bookkeeping labels (`owner-review`, `do-not-merge`, etc.).

### A3. `claude.yml` (mention-triggered Claude Code) is already tightly gated — low priority

`core/.github/workflows/claude.yml` and `services/.github/workflows/claude.yml` only fire on
`issue_comment`/`pull_request_review_comment`/`pull_request_review` from the repo owner (the
Discord-ticket exploit path was removed 2026-09-12, per the file's own header). No other repo has
this workflow. This one is not wasteful as configured — flagging only so it isn't mistaken for a
gap; no action needed.

### A4. Nothing found for "effort set higher than PLAN.md specifies" or "full-repo re-surveys"

Checked `site-chernarus/docs/PLAN.md` and `aegis-mods/docs/PLAN.md`: both specify a model
(Sonnet 5 / Opus 5) per session with a stated reason (e.g. "Opus 5 — it's destructive, one-shot and
hard to reverse"), and `MasterThread/standards/sessions/task_sizing.md` gives real tool-call bands
per size tier. Today's session handoff (`GitHub\SESSION_HANDOFF_2026-09-14-afternoon.md`) explicitly
tells the next orchestrator "don't re-survey GitHub" and points at itself — that discipline is
already the standing rule, not a gap. The one place effort is *not* size-scoped is A1 above (the
review workflow), which is a workflow default, not a session picking its own effort.

### A5. Dead-but-firing workflow calls (minor, Actions minutes not tokens)

`aegis-mods`, `aegis-poi`, `aegis-pricing`, `claude-agents`, `site-badlands` all call
`pr-review.yml` but have no `CLAUDE_CODE_OAUTH_TOKEN`/`ANTHROPIC_API_KEY` secret yet (each file's
own header says so). Every PR in those 5 repos still triggers the workflow_call, which fails fast
with a visible credential error — no model tokens spent, just wasted Actions minutes and a
red/no-op check. Not a token-efficiency item, but worth folding into whatever PR fixes A1, since
it's the same file.

## PART B — doesn't need Claude, candidate for a VPS timer

For each candidate: current mechanism, frequency, and the concrete VPS replacement (script +
systemd unit, following `aegis-run-job.sh` + `install-scheduled-timers.sh` from services PR #86).

### B1. PR/CI status polling ("wait for the check to go green") — highest impact of Part B

Every orchestrator round in this workflow does repeated `gh pr view --json state`, `gh pr checks`,
and `gh run list` calls from inside a live Claude session just to notice when a check finishes or a
PR merges — pure waiting, no judgment (`aegis-check-pr-state-before-followup-push` memory exists
specifically because a session pushed follow-up commits to an already-merged PR). This runs inside
every dispatched session today, not as a separate job — it's overhead riding on top of whatever the
session is actually doing, once per open PR per round, many times a day across 9+ repos.
**Replacement:** a `aegis-pr-watch` script (Node/bash + `gh` CLI, no auth beyond the existing
deploy-key/gh-cli login already on the VPS) polling `gh pr list --state open --json number,mergedAt,
statusCheckRollup` across the org every 2-5 minutes, writing a small JSON status file the next
Claude session reads instead of polling itself. Ship as `ops/vps/aegis-run-job.sh pr-watch` +
`aegis-pr-watch.timer` (`OnUnitActiveSec=3min`), Discord-alerting only on a state *transition*
(opened→checks-failed, checks-passed→still-unmerged-after-N-minutes), same `notify()` pattern
already in `aegis-run-job.sh`.

### B2. Worktree cleanup sweeps

`New-ParallelWorktrees.ps1` and the `aegis-worktree-remove-no-force` / `parallel-session-collision`
memories describe a fixed rule applied by hand each session: check `git worktree list`, cross-check
each worktree's branch against its PR's merge state via `gh pr view --json state`, and only then
`git worktree remove`. No synthesis — it is "is this PR merged/closed AND is the worktree clean" for
every worktree, every repo. Currently done ad hoc by whatever session notices stale worktrees
(no fixed cadence, no citation of a specific automated run — it's manual). **Replacement:** a
PowerShell or bash sweep run on a schedule against the PC (not the VPS, since worktrees live in
`<USER_HOME>\GitHub`) — `Cleanup-Worktrees.ps1` iterating every repo's `git worktree list
--porcelain`, resolving each branch's PR via `gh pr view <branch> --json state,mergedAt`, and
removing (never `--force`) only worktrees with a clean `git status` whose PR is merged or closed.
Windows equivalent of a systemd timer is Task Scheduler; since the PC isn't always on, a simple
"run me at the start of the next session" pre-check script achieves the same effect without needing
always-on infra.

### B3. PLAN.md status-table diffing (merged PR numbers vs. table rows)

Multiple PLAN.md files (site-chernarus, aegis-mods, services) carry a Status table listing session
numbers against PR numbers; keeping that table in sync with what's actually merged is exactly what
several of today's "docs: reconcile ... status" commits did by hand inside Claude sessions (e.g.
services' "docs: reconcile VPS/economy/admin-bot/stats status", "docs: correct M3's stale rotation
step"). The mechanical half — for each table row, does its cited PR number's `state`/`mergedAt`
match the row's claimed status — is a `gh pr view <n> --json state,mergedAt` loop with a diff
against the markdown table; only the prose narrative around a discrepancy needs a model.
**Replacement:** `check-plan-status.mjs <repo> <path-to-PLAN.md>`, run against origin (no checkout
needed — `git show origin/main:docs/PLAN.md` + `gh pr view`), on a daily systemd timer, posting a
Discord alert (or writing a small `docs/PLAN-DRIFT.md` note) only when a row's cited PR status
disagrees with its table entry — the fix itself still goes through a Claude session, but the
detection stops costing a survey.

### B4. Credential/token expiry checks — flag, don't duplicate

The prompt's own reference (`jarvis`'s "check-expiry.cjs pattern") does not actually exist in the
`jarvis` repo yet (checked the full tree — no file with "expir" in the name); this is a pattern
description, not a shipped tool. More importantly, **today's other P1 lane is explicitly building a
VPS-side credential monitor** (`SESSION_HANDOFF_2026-09-14-afternoon.md` §"Two more tasks queued
... 1. VPS token monitor, alerts to the orchestrator at set intervals"). Building a second expiry
checker here would duplicate that lane. Recommendation: this audit flags the overlap; the token
monitor being sized/built separately should absorb the `nasdara-dev-key`/`ANTHROPIC_API_KEY`
expiry-date checks already tracked in memory (`aegis-claude-review-rollout-status`,
`aegis-verify-secret-rotation-before-asking`) rather than a second implementation.

### B5. Boot-log triage's counting half

`site-chernarus/docs/PLAN.md` assigns Opus 5 to boot-log triage explicitly because "it triages a
large log and decides which findings are data bugs" (line ~283) — the judgment half is correctly
kept on a model. But the same sessions also do fixed-rule counting first (RPT/ADM grep counts of
`Hardline errors`, `MARKET CONFIGURATION ERROR`, `script (E)` occurrences — see the 2026-09-14
14:02 push note: "0 Hardline errors, 0 MARKET CONFIGURATION ERROR, 0 script (E)"). That grep-and-count
step needs no model. **Replacement:** a `count-boot-errors.sh <RPT-file>` run automatically right
after each restart (systemd path unit watching the RPT directory for a new file, or triggered from
the existing restart-orchestrator hook) that greps the fixed pattern set and writes a one-line
summary; the Claude session then only opens if any count is non-zero, skipping the mechanical pass
entirely on the (usual) clean-boot case.

### B6. Same-shape items not otherwise covered

`ops-scheduled.yml`/`ops-backup.yml`/`economy-*.yml` are **already non-LLM today** (plain
`node`/`mysqldump` scripts on a cron trigger) — their waste was GitHub Actions minutes, not Claude
tokens, and is already mid-fix via core#74/services#86 (unmerged as of this audit). No further
Claude-side action needed there; listed only so it isn't miscounted as a new finding.

## Priority order

**Part A:** A1 (org-wide Opus/high default, 9 repos, ~145 PR-reviews/3 days in 2 repos alone) >
A2 (accidental `labeled` re-reviews) > A5 (dead workflow calls, Actions minutes only) > A3/A4 (no
action needed, listed for completeness).

**Part B:** B1 (PR/CI polling, runs inside every session every round) > B2 (worktree sweeps,
manual today, real but unmeasured recurring cost) > B3 (PLAN.md status diffing, several
docs-reconciliation commits today were exactly this) > B5 (boot-log counting half, occasional but
cheap to remove) > B4 (don't build — overlaps the in-flight VPS token-monitor lane).
