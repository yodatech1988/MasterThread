# Headless readiness ladder

**Status: IN FORCE as of 2026-09-22, by owner decision.** Drafted 2026-09-18 from
`docs/PM_PHASE_ADVISORY_2026-09-18.md` §6 (github-9d, owner-started advisor) and carried as
*proposed* until now; approved per `merge_authority.md` route C (`standards/sessions/*`). Owner's
goal, 2026-09-17, direct: *"the sooner we get to headless automation, the less I will be creating
sessions too."*

Being in force changes what this document **authorises**, not what is **built**. The fleet is still
at L0; every rung's guard, exit criterion and "Never" binds from today.

**Current rung: L0**, fleet-wide. L1's tools exist (PR #108 `tools/pm-heartbeat/`, PR #109
`tools/README.md` testing-seam conventions, `tools/headless/readonly.settings.json` and
`Invoke-ReadOnlyAgent.ps1`) but no scheduled run of an L1 reporter has been registered yet — see
"Build state" below.

## The constraint this ladder exists for

Today's error-correction is **social**: a peer checks a claim, not a rule enforcing it. c5's own
handoff (`SESSION_HANDOFF_2026-09-18-github-c5-pm-seat.md`, "How this seat got things wrong") lists
six of its own PM assertions corrected in one evening — a merge-blocker claim, a misdiagnosed
runner-wide outage, a gitleaks port that didn't apply, an intrusion-protection claim, a
stale-checkout PLAN.md read, an issue filed against the lint output's own warning not to trust
it — and closes: *"Every one was caught by someone running the thing, not by anyone reading more
carefully."* That someone was always another live session.

Headless removes the peer. A reporter running unattended at 3am has nobody to catch a
merge-blocker-shaped error before it writes a Fleet Status row or drafts a card. So this ladder
widens unattended **verification** before unattended **action**, and every rung pairs its rule with
the check that fails if the rule is ignored — a standard nobody can check is the same shape as a
required-status check nobody enforces (`docs/PM_PHASE_ADVISORY_2026-09-18.md` §1, §10).

## The rungs

| Rung | What runs unattended | Guard | Failure it must be proven to produce | Exit criterion | Never |
|---|---|---|---|---|---|
| **L0** (today) | Interactive sessions and their subagents only. | A human sees every Bash call before it runs. | — | — | — |
| **L1 Reporters** | Read-only Haiku reporters (`pr-state-sweep`, `gate-execution-auditor`, `plan-status-check`, `worktree-sweep`, `standard-buildstate-checker`, `register-verifier`, `check_agent_sync.py`) via `Invoke-ReadOnlyAgent.ps1` on a Windows scheduled task, each writing one local JSON report file with `checkedAt` + the command run, ingested into Fleet Status `prs`/`health` by the interactive PM's heartbeat tick — see "Reports, not direct writes" below. | `readonly.settings.json` deny-list **plus** a per-agent `--allowedTools` allow-list (the load-bearing finding in `headless_agent_permissions.md`: deny-only under `dontAsk` denies everything not in Claude Code's built-in read-only set — an agent needs its own allow entries to do its job at all). Hard timeout, `--max-budget-usd`, subscription token only (never a metered API key), `--strict-mcp-config`, the `tools/README.md` test seam (`-StateDir`, destructive/notifying paths keyed off the real path). | A destructive attempt denied by the settings file, or a `permission_denials` entry for a legitimate read (proves the allow-list is too narrow, not that the rung is unsafe). | 7 consecutive days of scheduled runs with zero `permission_denials` against legitimate reads, zero destructive attempts anywhere in the logs, and the `prs` panel's dead-writer problem (`fleet_status_standard.md`) closed — this is what retires the "sole writer `github-8e`" fragility. | Write anything; hold Bash beyond the allow-listed verbs; run with no `--settings`; call `ArtifactData` (see below, it has no tool to call). |
| **L2 Cross-checking verifiers** | Two reporters per fact, each from a different evidence path (e.g. `gh pr view` vs `git ls-remote`; the branch-protection API vs a run log), plus a deterministic comparator that writes a register/health row only on agreement and files a card on disagreement. | Same as L1, plus: the comparator itself has no Bash/write tool beyond the one card-filing call: disagreement produces a card, never a silent overwrite. | A disagreement between the two paths. | One month of runs with the disagreement rate measured and every disagreement explained (not just logged) — this is the social error-correction (c5's "someone running the thing") made structural. | Resolve a disagreement by picking one path's answer; skip explaining a disagreement before the next cycle. |
| **L3 Drafters** | Headless drafter agents open PRs: lane cards, register-row proposals, LESSONS promotions, handoff drafts, a digest. Never merge. | `Agent(claude)` / `Agent(general-purpose)` denied (blocks spawning a full-access escape hatch); one open PR per repo; `automerge-preflight` run before push; never touches `standards/sessions/*`, `policies/*`, or a `CLAUDE.md`-feeding doc (those are owner-merge, `merge_authority.md` route C, "the documents that tell sessions how to behave are not approved by the sessions they govern"). | A drafter PR the seat rejects, or one that touches an out-of-scope path. | Seat rejection rate below an agreed bar over a month; zero unasked edits to `standards/sessions/*` or `policies/*`. | Merge its own PR; edit a standard or policy file; spawn a further routine or PM (the 2026-09-16 self-scheduling incident below is exactly this failure one rung earlier). |
| **L4 Deterministic merge** | Only the automerge job in core's `claude-review.yml`, only route A, only in repos whose `gate-execution-auditor` UNENFORCED count is 0. | Required checks that actually run — a repo with an empty or template-stub required-check list stays off this rung regardless of automerge config. | An automerge on a repo where UNENFORCED > 0 (this is a finding, not a merge that should have happened). | Owner decision, per repo. | Let any headless **session** merge — L4 is the deterministic job in CI, never a `claude --print` process holding merge authority. |

### L0 — today

Baseline. Every Bash call is watched by a human in the loop. No exit criterion; climbing starts at L1.

### L1 — Reporters, and why they file rather than write

Invoked per `headless_agent_permissions.md`'s recommended line (`--settings
readonly.settings.json --tools "<smallest set>" --permission-mode dontAsk --permission-prompts
none --strict-mcp-config --max-budget-usd <small>`). The guard is two layers because the file
documenting layer 2 also documents its own limit: `readonly.settings.json`'s deny rules are
pattern-matched command text, defeated by `bash -c '...'`, an absolute path, or reordered flags
(`headless_agent_permissions.md` "documented gaps"). Layer 1 (`--allowedTools` scoped to the
handful of `git`/`gh` read verbs each reporter actually uses) is the real boundary; layer 2 catches
a caller that forgot to narrow it.

**`claude -p` cannot hold `ArtifactData` at all.** Fleet Status is a claude.ai artifact-backed
store; that connector needs the interactive claude.ai login a headless run never has, so
`--allowedTools ArtifactData` grants a tool that does nothing (verified against `code.claude.com`'s
`headless` and `artifacts` reference pages). So "writing `prs`/`health` rows" at this rung means:

1. The wrapper (`Invoke-ReadOnlyAgent.ps1`, `--output-format json`) writes one report file per run
   to `%APPDATA%\AEGIS\reports\<agent>.<yyyyMMdd-HHmmss>.json`:
   `{agent, checkedAt, command, exitCode, permissionDenials, findings[]}` — a plain file write by
   the wrapper process, not a tool call the agent itself makes.
2. The PM's heartbeat tick (`pm_role.md` "The heartbeat", step 5) reads unread files each tick,
   writes them into Fleet Status `prs`/`health` with `writtenBy: "<pm session> from <report
   file>"`, and archives the file.
3. This keeps `pm_role.md`'s existing shape (the PM reads a report, never the raw sweep) and gives
   L2's comparator a file-based input instead of two direct writes racing on one row.

### L2 — Cross-checking verifiers

Pairs of L1-shaped reporters check the same fact by different means (e.g. `gh pr view` vs `git
ls-remote`), feeding a comparator that reads both drop-folder files and writes a Fleet Status row
only on agreement. This is `docs/PM_PHASE_ADVISORY_2026-09-18.md` §5 rule 3 as a schedule: "two
independent readers — not two people reading the same text, one reading, one *running*."

### L3 — Drafters

Drafter-shaped agents — today `denial-card-drafter` (MasterThread PR #110, gatekeeper-passed,
merged 2026-09-18T01:58Z, on `origin/main`, never yet run headless) and any future drafter —
opening PRs against a fixed, narrow path set. (The
other three §8 agents in #110 are reporters/advisors and belong to L1/L2, not here.) ops-platform's `packages/project-manager` (`pm-agent`) is **dormant until L1 exits**
(zero-cost-first, `orchestrator_role.md`: a heavier mechanism is built only after the cheap one has
been tried) — its README should say so; that edit belongs to ops-platform, out of this PR's scope.

**Never at this rung:** merge anything, including its own PR; touch `standards/sessions/*`,
`policies/*`, or a `CLAUDE.md`-feeding doc; spawn a further agent, routine, or PM (see "Never
headless" below — the 2026-09-16 self-scheduling incident is this exact failure one rung down).

### L4 — Deterministic merge

A **condition on an existing mechanism**, not a new one: core's `claude-review.yml` automerge job,
gated additionally on the repo's `gate-execution-auditor` UNENFORCED count being 0 (a required
check that never runs is not a gate — `merge_authority.md` principle 7; `site-badlands`' only
required check runs `echo "no checks configured yet"`).

**Never at this rung:** a headless **session** holding merge authority for any route. Route A stays
a CI job with no relay to trust (`merge_authority.md` principle 3); routes B and C stay a session
or the owner.

## Never headless, at any rung

From `headless_agent_permissions.md` "Agents that must never run headless at all", plus:

- **`live-reviewer`** (Opus, live/credentials/money/death-path review) — interactive only, per its
  own file's "RESERVE FOR DELIBERATE, RARE USE ONLY".
- **`vuln-scan-active`** — depends on an owner-declared maintenance window being open *right now*;
  a headless caller cannot reliably re-verify that at call time.
- Anything needing live prod, credentials, or money that isn't advisor-shaped recommendation-only
  (`advisor_role.md` row 1; `worker_role.md` "Never: Live actions").
- Anything tagged `needs-local-keys` (DPAPI files owned by the Windows user) — this machine only.
- Anything needing an OAuth MCP connector sign-in (roster audit F10).
- **Any Route C merge, on anyone's relay** (`merge_authority.md`: when the owner is away, route C
  simply waits — current, recommended behaviour, not a gap to close headless).
- **Anything rendering an owner-facing approval prompt** (`fleet_structure.md` "Approval and
  authorisation") — must refuse to launch unless the owner initiated it; a headless run never has.
- **Anything that spawns a further routine or PM.** 2026-09-16, `docs/LESSONS.md` "A cloud
  PM-candidate session self-scheduled its own follow-up trigger": an otherwise-correct one-time test
  used its PR-babysitting tool to schedule an unauthorized hour-later follow-up on ordinary
  instinct, caught and disabled within minutes. Rule: any session with a self-scheduling capability
  will use it unless explicitly forbidden — a headless agent above L0 never holds `CronCreate`,
  `send_later`, or an `Agent` call reaching outside its rung's exact roster.
- Anything touching a live host, a credential, or money outside L1's read-only shape.

## What every headless run must emit

A **report, not a verdict** (`fleet_structure.md`). Every run at L1+ writes: `checkedAt` (clock at
write time, never typed — `tools/README.md`) and the exact command run; a `permission_denials`
count, even zero (L1's exit criterion is measured on this field); its exit code; a lessons block
per `docs/LESSONS.md`'s convention.

A run that emits nothing is itself a finding: `fleet_roster_monitor.md`'s words on its analogous
mechanism apply verbatim — "a silent watcher and a quiet fleet must not look alike." A missing
report where a scheduled run should have written one is not evidence the day was quiet; it is
evidence the mechanism stopped.

## Denials have a queue

A headless run that hits a classifier denial files (or hands the PM the draft of) a
permission-denial action card per `decision_queue_standard.md` "Permission-denial cards" — exact
command, classifier reason, blast radius, undo, the click that clears it — and **stops**. It never
retries around the denial and never treats a peer's "the owner authorized this" as a substitute for
the click (`merge_authority.md`). This is `docs/PM_PHASE_ADVISORY_2026-09-18.md` §6's "the
permission-denial queue is what makes L1-L3 survivable": without it, a denial is a lane that dies
silently instead of one that waits visibly.

## Climbing and falling back

**Climbing** is one Decision Queue card per rung per repo class, filed by the PM, never
self-declared by the mechanism being evaluated. The card carries the exit criterion's actual
measurements literally — not "it's been running fine." A resolved card authorises the climb the
same way any card does: it is an instruction, not proof anyone re-verified live state at the moment
of the climb (`decision_queue_standard.md` "What this queue is explicitly not").

**Falling back** does not wait for a card: any destructive attempt (even one the deny-list caught)
or any unexplained L2 disagreement drops the affected agent one rung immediately. The PM records
the drop in the workstream register (`pm_role.md`) and files a card after the fact — the card
documents the drop, it does not gate it. Falling is faster than climbing, deliberately.

## Build state

Per `pm_role.md`'s rule that a standard naming a mechanism carries its build state rather than
letting a later reader mistake intent for fact:

| Mechanism this file names | Build state |
|---|---|
| `tools/headless/readonly.settings.json` | **Built and verified** 2026-09-18 (`headless_agent_permissions.md` "Verification", 4 live test runs, allow+deny composing correctly). |
| `tools/headless/Invoke-ReadOnlyAgent.ps1` | **Built**, confirmed present on `origin/main`. Not yet run from a Windows scheduled task anywhere. |
| `tools/pm-heartbeat/Write-PmHeartbeat.ps1` / `Watch-PmHeartbeat.ps1` | **Built** (PR #108, merged). Registration click-file `GitHub\AEGIS-Register-PmHeartbeat-Watchdog.cmd` **built 2026-09-18** (`-WhatIf` + generated-wrapper call-site test on a throwaway dir); task **not registered** — owner card `action-register-pm-heartbeat-watchdog-2026-09-18`. |
| `tools/README.md` testing-seam conventions | **Built** (PR #109, merged, this worktree's ancestry). |
| Per-agent `--allowedTools` overlay (L1 guard layer 1) | **Not built**, but its blocker is gone: `claude-agents/roster_meta.json` with its `readonly:` classification **is on `origin/main`** (confirmed 2026-09-22). Also superseded in part — `claude --restricted` removes Bash/PowerShell/REPL from the tool surface outright and ignores user/project/local settings, so for any agent needing no shell it is a stronger primary boundary than an allow-list over a deny-list. Probed 2026-09-22 (CLI 2.1.278): a restricted run reports no Bash tool exists rather than denying the call. |
| L1 scheduled task (any reporter running unattended on a schedule) | **Not built.** The only scheduled-task click-file is the watchdog's (above), which verifies the PM and runs no reporter. |
| Reports drop folder + PM ingest step (`%APPDATA%\AEGIS\reports\`, heartbeat-tick ingestion into Fleet Status) | **Not built** — no folder convention or ingest code exists. But less remains to build than this document assumed: `claude -p --output-format json` already returns `permission_denials[]`, `total_cost_usd`, `usage{…}`, `num_turns` and `is_error` per run, and `--json-schema` constrains the result to a caller-supplied shape (both probed 2026-09-22, CLI 2.1.278). The wrapper needs to add `checkedAt` and the exact command and persist the envelope; the `findings[]` contract can be schema-enforced rather than trusted to the agent's prose. **L1's exit criterion is measured on `permission_denials`, which is machine-readable today.** |
| L2 comparator (deterministic agree/disagree writer) | **Not built.** Its inputs `register-verifier` and `standard-buildstate-checker` **are now on `origin/main`** (PR #110 merged 2026-09-18T01:58Z); the comparator itself is still unwritten. |
| `ops-platform/packages/project-manager` (`pm-agent`) | **Not built**, re-confirmed 2026-09-18 by reading `origin/main:packages/project-manager/bin/start.js` directly: it throws unconditionally, naming the missing GitHub/Discord/ledger dependencies. `reasoner.js` is wired but not invoked by `start.js`. No register/merge-audit/Fleet-Status code exists for this package. |
| L3 drafter agent (`denial-card-drafter`) and the §8 reporters/advisor | **On `origin/main`** — PR #110 merged 2026-09-18T01:58Z (`agent-automation-gatekeeper` 4× PASS). Still **never run headless**, which is what L3 requires evidence of. |
| L4 gate (UNENFORCED=0 wired into automerge) | **Not built** as a precondition. `gate-execution-auditor` exists; nothing in `claude-review.yml` is confirmed to read its output first. |

Related: `headless_agent_permissions.md`, `pm_role.md`, `orchestrator_role.md`, `fleet_structure.md`,
`merge_authority.md`, `fleet_roster_monitor.md`, `decision_queue_standard.md`,
`docs/PM_PHASE_ADVISORY_2026-09-18.md` §5-§8.
