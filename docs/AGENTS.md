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
| `handoff-drift-reviewer` | sonnet | **A** | Checks a session handoff against the documented procedure; called by the outgoing session, not the incoming one | `orchestrator_role.md` "PM handoff"; `aegis-skills-program` |
| `lane-card-writer` | sonnet | R | Formats a worker/research card with Priority+Size | `worker_role.md`, `researcher_role.md`, `task_sizing.md` |
| `pm-agent` | sonnet | **A** | Judgment layer for ops-platform's headless PM (triage/digest/escalation text only, Read/Grep only, no dispatch or self-scheduling) | `ops-platform` task 2.25; `aegis-pm-self-generation-limits`; Decision Queue card `headless-pm-cmd-run-mechanism-2026-09-17` |
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
| `badlands-mod-readiness-advisor` | sonnet | **A** | `site-badlands` | Verdict against the real mod-readiness tracker |
| `badlands-hosting-plan-advisor` | sonnet | **A** | `site-badlands` | Verdict against the real hosting plan doc |
| `badlands-release-prep-advisor` | sonnet | **A** | `site-badlands` | Verdict against the real release-prep research doc |
| `badlands-status-reporter` | haiku | R | `site-badlands` | Fact summary from `STATUS.md` + `docs/PLAN.md` |
| `badlands-mod-readiness-inventory` | haiku | R | `site-badlands` | Fact list of mods + readiness state |
| `canon-consistency-advisor` | sonnet | **A** | `core` | Checks a proposed lore change against the real canon bible (8 files) |
| `secret-rotation-schedule-advisor` | haiku | **A** | `core` | Verdict against the real `docs/ops/SECRET-ROTATION.md` expiry tables |
| `vendored-validator-advisor` | sonnet | **A** | `core` | Verdict against `docs/ops/VENDORED-VALIDATOR.md`; found site-chernarus's drift check has never run, 6 files already diverged |
| `canon-bible-inventory` | haiku | R | `core` | Lists the real canon docs + last-modified dates |
| `secret-rotation-schedule-reporter` | haiku | R | `core` | Reports which schedule entries are due, fact-only |
| `vendored-validator-status-reporter` | haiku | R | `core` | Reports validator version/drift state, fact-only |
| `model-policy-advisor` | sonnet | **A** | `claude-agents` | Checks a model choice against the real `model-policy` ROLES map; flags disagreement with `worker_role.md` rather than silently reconciling |
| `bug-report-triage-advisor` | sonnet | **A** | `claude-agents` | Checks a bug report against the real `bug-report-agent/src/triage.js` — that package has no severity scale, says so rather than inventing one |
| `economy-worker-schema-advisor` | sonnet | **A** | `claude-agents` | Checks a query/migration against the real `economy-worker/schema.sql` |
| `be-rcon-query-reporter` | haiku | R | `claude-agents` | Wraps `be-rcon`'s real read-only `players` query only |
| `bug-report-inventory` | haiku | R | `claude-agents` | Lists open bug-report PRs via the real naming convention |
| `economy-worker-health-check` | haiku | R | `claude-agents` | Read-only Cloudflare Worker deploy/health status |

## Advisors against MasterThread's own standards (global, `~/.claude/agents/`)

Every real (non-stub) file in `standards/architecture`, `standards/coding`, `standards/release`,
`standards/requirements`, `standards/testing`, and `standards/maintenance` now has a paired Advisor
(checks compliance) and, for the higher-value ones, a matching drafter Agent (produces new content
in that standard's real format). `MasterThread/policies/*` (compliance, data, dayz, discord,
engineering, patreon) are excluded — every file there is a literal 0-byte stub; building against
them would mean inventing rules, which none of these do.

| Agent | Model | Purpose |
|---|---|---|
| `api-spec-advisor` | sonnet | Verdict against `api_spec_standard.md`'s real required sections |
| `architecture-doc-advisor` | sonnet | Verdict against `architecture_doc_standard.md`'s real required sections |
| `mermaid-styleguide-advisor` | haiku | Verdict against `mermaid_styleguide.md`'s real rules |
| `sequence-diagram-advisor` | haiku | Verdict against `sequence_diagram_standard.md`'s real rules |
| `error-handling-advisor` | haiku | Verdict against `error_handling.md`'s real rules |
| `file-structure-advisor` | haiku | Verdict against `file_structure.md`'s real rules |
| `logging-conventions-advisor` | haiku | Verdict against `logging_conventions.md`'s real rules |
| `naming-conventions-advisor` | haiku | Verdict against `naming_conventions.md`'s real rules |
| `changelog-advisor` | haiku | Verdict against `changelog_standard.md`'s real format |
| `release-notes-advisor` | haiku | Verdict against `release_notes_standard.md`'s real format |
| `rollout-plan-advisor` | sonnet | Verdict against `rollout_plan_standard.md` — thin standard (5 bullets, no worked template), flagged rather than treated as complete |
| `acceptance-criteria-advisor` | sonnet | Verdict against `acceptance_criteria.md`'s real `AC-NNN` format |
| `functional-requirements-advisor` | sonnet | Verdict against `functional_requirements.md`'s real `FR-XXX` format |
| `technical-requirements-advisor` | haiku | Verdict against `technical_requirements.md`'s real rules |
| `user-story-advisor` | haiku | Verdict against `user_story_format.md`'s real template |
| `integration-testing-advisor` | sonnet | Verdict against `integration_testing.md`'s real Scope/Guidelines |
| `load-testing-advisor` | sonnet | Verdict against `load_testing.md`'s real Targets/Metrics |
| `simulation-testing-advisor` | sonnet | Verdict against `simulation_testing.md` — very thin (12 lines, no real document structure), flagged |
| `test-case-advisor` | haiku | Verdict against `test_case_standard.md`'s real ID/Steps/Expected format |
| `escalation-matrix-advisor` | sonnet | Verdict against `escalation_matrix.md` — thin (4 example rows, no real taxonomy), flagged |
| `issue-triage-advisor` | sonnet | Verdict against `issue_triage_standard.md`'s real P0-P3 severities (no label taxonomy exists, flagged) |
| `changelog-entry-drafter` | sonnet | Drafts a changelog entry in the real Added/Changed/Fixed/Removed format |
| `release-notes-drafter` | sonnet | Drafts release notes in the real 5-section format |
| `user-story-drafter` | sonnet | Drafts a user story in the real role/capability/value template |
| `test-case-drafter` | sonnet | Drafts a test case in the real ID/Preconditions/Steps/Expected format |
| `acceptance-criteria-drafter` | sonnet | Drafts acceptance criteria in the real `AC-NNN` format |
| `api-spec-drafter` | sonnet | Drafts an API spec skeleton in the real 5-section format |
| `mermaid-diagram-drafter` | sonnet | Drafts a diagram per the real style rules |
| `sequence-diagram-drafter` | sonnet | Drafts a sequence diagram in the real syntax/naming rules |
| `rollout-plan-drafter` | sonnet | Drafts a rollout plan — kept to exactly the standard's 5 sections, `TODO` markers rather than invented structure |
| `functional-requirements-drafter` | sonnet | Drafts functional requirements in the real `FR-XXX` format |
| `technical-requirements-drafter` | sonnet | Drafts a technical requirements doc in the real format |
| `integration-test-plan-drafter` | sonnet | Drafts an integration test plan in the real format |
| `simulation-test-plan-drafter` | sonnet | Drafts a simulation test note — standard is too thin for a full plan shape, scoped down accordingly |
| `architecture-doc-drafter` | sonnet | Drafts an architecture doc skeleton in the real required sections |
| `load-test-plan-drafter` | sonnet | Drafts a load test plan in the real format |
| `standards-stub-finder` | haiku | Sweeps `standards/`+`policies/` and reports stub vs real (>5 lines) — exists because this exact mistake happened repeatedly while building this roster |
| `policy-coverage-reporter` | sonnet | Cross-refs this file against every real standard/policy doc with no agent yet |

## More global mechanical reporters (`~/.claude/agents/`)

| Agent | Model | Purpose |
|---|---|---|
| `claude-session-archive-status` | haiku | Wraps `Invoke-Archive.ps1`'s real status output; never triggers a run |
| `github-org-repo-inventory` | haiku | `gh repo list yodatech1988` fact table — name/visibility/last-push/archived |
| `discord-bot-key-age-reporter` | haiku | Real DPAPI key-file ages for the two named Discord bot keys; the second key's actual path differs from the assumed one — found and corrected during build |
| `ovh-vps-usage-reporter` | haiku | Wraps `OvhApiKey.ps1 GET /vps` (scope `/vps/*`, no `DELETE`), fact-only |
| `workshop-mod-inventory` | haiku | Lists real `module.json` files across `aegis-mods`/`aegis-poi`; found `aegis-poi` has no real modules yet, only test fixtures |

## Adding a new one

1. Ground it in a real standard, policy, or script — never invent process the agent then improvises.
2. Pin the cheapest model the task's judgment actually needs (see `orchestrator_role.md`'s table).
3. List only the tools it needs; deny writes explicitly where a slip would be costly (live, money,
   secrets, Discord/Patreon sends).
4. Add its row here in the same PR.
