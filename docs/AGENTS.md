# Agent roster (T4 subagents)

The single index of every Claude Code subagent definition across the org, added 2026-09-15 as the
breadth lever for `standards/sessions/orchestrator_role.md`'s tiered model (T0 owner, T1 program PM,
T2 round orchestrator, T3 lane lead, T4 task subagent, T5 deterministic script). A T4 entry's whole
value is that its instructions live once in its definition file — a caller summons it with a one-line
task instead of re-pasting a policy doc, and its model is pinned in frontmatter so cost routing can't
drift the way the interactive default has (see `orchestrator_role.md`'s model/effort table).

Each agent's file is the source of truth; this table is the index, not a duplicate.

**Role** (per `standards/sessions/advisor_role.md`): **A**dvisor renders a judgment/verdict and takes
no action; **R** is researcher-shaped (reports facts/state, no judgment call to render). Blank means
not yet classified — a real gap, not a "doesn't apply."

## Global (`~/.claude/agents/`, available in every repo)

| Agent | Model | Role | Purpose | Grounded in |
|---|---|---|---|---|
| `pr-state-sweep` | haiku | R | PR/CI state sweep across named repos | Token-efficiency audit B1 |
| `plan-status-check` | haiku | R | PLAN.md Status table vs real PR state, origin only | B3; `researcher_role.md` |
| `worktree-sweep` | haiku | R | Reports safe-to-remove worktrees; never removes | B2; `aegis-worktree-remove-no-force` |
| `origin-reader` | haiku | R | Reads a file/dir from `origin/<default>`, never local | `researcher_role.md` |
| `collision-check` | haiku | R | Pre-dispatch PR/branch/worktree collision check | `orchestrator_role.md` "Collisions"; `parallel-session-collision` |
| `lane-card-writer` | sonnet | R | Formats a worker/research card with Priority+Size | `worker_role.md`, `researcher_role.md`, `task_sizing.md` |
| `diff-reviewer` | sonnet | **A** | Pre-merge diff review: crash patterns, secrets, removed names | `session_plan_standard.md` rule 10 |
| `test-baseline-runner` | sonnet | R | Runs stated validators, reports real counts only | `worker_role.md` "Tests and validators" |
| `live-reviewer` | **opus** | **A** | Live prod / credential / money / death-path review only | `worker_role.md` model table row 1 |
| `secret-rotation-auditor` | haiku | R | Tests live connection / `.clixml` mtime before flagging overdue | `aegis-verify-secret-rotation-before-asking` |
| `github-2fa-audit` | haiku | R | Confirms 2FA/token posture via `gh api`, read-only | `aegis-github-2fa-enabled` |
| `battleye-guid-verifier` | haiku | R | Computes/verifies BE GUID from a Steam64 ID | `aegis-battleye-guid-formula` |
| `usage-window-reporter` | haiku | R | One-off usage spot-check, no standing watch | `tools/usage-monitor/` |
| `patreon-entitlement-checker` | sonnet | | Patreon tier vs Discord role vs entitlement policy | `policies/patreon/entitlements.md` — dormant |
| `cohort-digest` | haiku | R | Mechanical cohort/signup rollup, no judgment | — dormant |
| `support-triage` | sonnet | | Classifies a ticket, proposes routing, never replies | `policies/discord/support.md` — dormant |
| `moderation-flagger` | haiku | | Flags a message against policy; flag-only, no act tools | `policies/discord/moderation.md` — dormant |
| `announcement-drafter` | sonnet | | Drafts an announcement in the AEGIS voice; never sends | `policies/discord/announcements.md` — dormant |
| `review-tier-recommender` | haiku | **A** | Recommends model/effort for a PR review, filling the gap `claude-review.yml` leaves open | Token audit A1 |
| `automerge-preflight` | haiku | **A** | Checks a PR against `claude-review.yml`'s real automerge gates before it's pushed | Token audit A1/A2; `claude-review.yml` |
| `secrets-handling-auditor` | sonnet | **A** | Audits a repo's secret-handling PRACTICE (storage, injection, gitignore) against org policy | `_security-public/policies/security/secrets_handling.md` |
| `incident-response-drafter` | sonnet | **A** | Drafts a postmortem from the real P0-P3 severity table and response steps; proposes only | `_security-public/policies/security/incident_response.md` |
| `agent-automation-gatekeeper` | sonnet | **A** | Reviews a *new* proposed agent against the org's automation policy before it's added | `_security-public/policies/security/agents_and_automation.md` |
| `data-classification-tagger` | haiku | **A** | Tags data with the real C0-C3 classes, not a generic public/internal/confidential scheme | `_security-public/policies/data/classification.md` |
| `vuln-scan-passive` | sonnet | R | Non-intrusive recon (`nmap -sV --open`, TLS check); runs anytime, no window needed | Owner-scoped security testing round |
| `vuln-scan-active` | sonnet | | Safe-NSE vulnerability confirmation only, gated on `ops-infra`'s maintenance-window check | Owner-scoped security testing round; never attempts exploitation |
| `dependency-cve-scanner` | haiku | R | `npm audit`/`pip-audit` against a repo's dependencies | Owner-scoped security testing round |

"Dormant" = Discord/Patreon automation stays paused per the standing owner decision
(`docs/REPOS.md`); the definition exists for when that's lifted, and creating the file triggers
nothing on its own.

## `MasterThread/.claude/agents/`

| Agent | Model | Purpose |
|---|---|---|
| `repo-ledger-refresh` | sonnet | Regenerates `docs/REPOS.md` against live `gh` state |
| `handoff-writer` | sonnet | Writes `SESSION_HANDOFF_*.md` from a round's end state |

## Repo-local (need that repo's own tools/paths)

| Agent | Model | Role | Repo | Purpose |
|---|---|---|---|---|
| `mod-boot-test-runner` | sonnet | | `aegis-mods`, `aegis-poi`, `aegis-pricing` | Wraps `tools/boot-test.ps1`; refuses while the owner is in game |
| `module-json-contract-checker` | haiku | **A** | `aegis-mods`, `aegis-poi` | Validates `module.json` against `workshop_mod_standard.md` |
| `workshop-publish-preflight` | sonnet | **A** | `aegis-mods` | Checks Workshop-publish readiness; never runs the actual publish |
| `classname-duplicate-triage` | haiku | **A** | `site-chernarus` | Flags true dupes only — checks trader file first per `CLAUDE.md` |
| `economy-invariant-checker` | sonnet | **A** | `site-chernarus` | Checks economy XML against policy AND the real files |
| `loot-table-reviewer` | sonnet | **A** | `site-chernarus` | Reviews loot changes against `policies/dayz/loot_tables.md` |
| `rarity-price-reviewer` | sonnet | **A** | `aegis-pricing` | Checks a curve against the real always-on guards (exchange exemption, spread, clamp ranges) |
| `vps-drift-checker` | sonnet | **A** | `ops-infra` | Read-only SSH diff of live config vs Ansible source |
| `invoice-drafter` | sonnet | | `handymansfield` | Drafts (never sends) an invoice from a Job record |
| `expense-triage` | sonnet | | `handymansfield` | Proposes expense categorization, read-only |
| `quote-generator` | sonnet | **A** | `handymansfield` | Drafts a pre-job quote from the same Rates table `job-intake` uses |
| `budget-envelope-reporter` | haiku | R | `ops-platform` | Read-only per-zone spend report via the real ledger `accountant.js`, never `reserve`/`settle` |
| `voice-transcriber` | haiku | | `jarvis` | Wraps the already-built whisper.cpp CLI, output only |
| `voice-synthesizer` | haiku | | `jarvis` | Wraps the already-built XTTS synthesis script; requires whose-voice-and-why before running |

## Adding a new one

1. Ground it in a real standard, policy, or script — never invent process the agent then improvises.
2. Pin the cheapest model the task's judgment actually needs (see `orchestrator_role.md`'s table).
3. List only the tools it needs; deny writes explicitly where a slip would be costly (live, money,
   secrets, Discord/Patreon sends).
4. Add its row here in the same PR.
