# Agent roster (T4 subagents)

The single index of every Claude Code subagent definition across the org, added 2026-09-15 as the
breadth lever for `standards/sessions/orchestrator_role.md`'s tiered model (T0 owner, T1 program PM,
T2 round orchestrator, T3 lane lead, T4 task subagent, T5 deterministic script). A T4 entry's whole
value is that its instructions live once in its definition file — a caller summons it with a one-line
task instead of re-pasting a policy doc, and its model is pinned in frontmatter so cost routing can't
drift the way the interactive default has (see `orchestrator_role.md`'s model/effort table).

Each agent's file is the source of truth; this table is the index, not a duplicate.

The top-level `Agents/` tree (76 persona/io-contract spec folders from before 2026-09-11) was a
template set that was never implemented and is archived at
`archive/Agents-templates-2026-09-11/` — it is not part of this roster.

`claude-agents/roster_meta.json` carries the same Role/Headless facts as this table, plus a
`readonly` field, in one machine-parseable file (one entry per file in `claude-agents/`). Most of
the ~25 global agents that hold unrestricted `Bash` are `readonly: instruction` — nothing in their
tool list stops a write, only their own prose says not to. A deny-list for what a headless run may
not do is tracked separately in `standards/sessions/headless_agent_permissions.md`.

**Role** (per `standards/sessions/advisor_role.md`): **A**dvisor renders a judgment/verdict and takes
no action; **D**rafter produces new content in a standard's format for the caller to place, renders
no verdict and takes no action; **R** is researcher-shaped (reports facts/state, no judgment call to
render). Blank means not yet classified — a real gap, not a "doesn't apply."

**Headless** (per the 2026-09-17 roster audit's F10/R11): whether the agent can run as
`claude --print --agent <name>` with no human watching. `yes` — tools are only `Read`/`Grep`, or
read-only `git`/`gh` calls, with no machine-local secrets. `needs-connector` — uses an OAuth MCP
connector (QuickBooks, Drive, …) that a non-interactive session cannot sign in to. `needs-local-keys`
— reads a DPAPI `.clixml` key file under `%APPDATA%\AEGIS` or wraps a `*Key.ps1` tool, so it only
works as the Windows user who owns those keys, on this PC. `local-only` — needs this PC's local
files, GPU, or game install (a local DayZ server boot, a local whisper.cpp/XTTS model, Windows Task
Scheduler state) and has no path to running anywhere else.

## Global (`~/.claude/agents/`, available in every repo)

| Agent | Model | Role | Headless | Purpose | Grounded in |
|---|---|---|---|---|---|
| `pr-state-sweep` | haiku | R | yes | PR/CI state sweep across named repos | Token-efficiency audit B1 |
| `plan-status-check` | haiku | R | yes | PLAN.md Status table vs real PR state, origin only | B3; `researcher_role.md` |
| `worktree-sweep` | haiku | R | yes | Reports safe-to-remove worktrees; never removes | B2; `aegis-worktree-remove-no-force` |
| `worktree-prune-executor` | haiku | R | yes | Prunes only stale worktree registrations whose directory is already gone, dry run first; the separate authorized step `worktree-sweep` points to; never removes | B2; `aegis-worktree-remove-no-force` |
| `origin-reader` | haiku | R | yes | Reads a file/dir from `origin/<default>`, never local | `researcher_role.md` |
| `collision-check` | haiku | R | yes | Pre-dispatch PR/branch/worktree collision check | `orchestrator_role.md` "Collisions"; `parallel-session-collision` |
| `handoff-drift-reviewer` | sonnet | **A** | yes | Checks a session handoff against the documented procedure; called by the outgoing session, not the incoming one | `orchestrator_role.md` "PM handoff"; `aegis-skills-program` |
| `lane-card-writer` | sonnet | R | yes | Formats a worker/research card with Priority+Size | `worker_role.md`, `researcher_role.md`, `task_sizing.md` |
| `diff-reviewer` | sonnet | **A** | yes | Pre-merge diff review: crash patterns, secrets, removed names | `session_plan_standard.md` rule 10 |
| `post-merge-verifier` | sonnet | R | yes | Confirms a merged PR actually landed: merge commit is an ancestor of `origin/<default>`, claimed files present with expected content, post-merge CI conclusion (and execution signature where stated), and a stated read-only done-test passes; reports LANDED / PARTIAL / NOT LANDED; never reverts, re-runs a workflow, or touches a live host | `session_plan_standard.md` rule 10 extended post-merge; `merge_authority.md` principles 5-6; `DEV_SUITE_COVERAGE_2026-09-22.md` "Post-merge verification" gap |
| `test-baseline-runner` | sonnet | R | yes | Runs stated validators, reports real counts only | `worker_role.md` "Tests and validators" |
| `live-reviewer` | **opus** | **A** | yes | Live prod / credential / money / death-path review only | `worker_role.md` model table row 1 |
| `secret-rotation-auditor` | haiku | R | needs-local-keys | Tests live connection / `.clixml` mtime before flagging overdue | `aegis-verify-secret-rotation-before-asking` |
| `github-2fa-audit` | haiku | R | yes | Confirms 2FA/token posture via `gh api`, read-only | `aegis-github-2fa-enabled` |
| `battleye-guid-verifier` | haiku | R | yes | Computes/verifies BE GUID from a Steam64 ID | `aegis-battleye-guid-formula` |
| `usage-window-reporter` | haiku | R | yes | One-off usage spot-check, no standing watch | `tools/usage-monitor/` |
| `patreon-entitlement-checker` | sonnet | **A** | yes | Patreon tier vs Discord role vs entitlement policy | `policies/patreon/entitlements.md` — dormant |
| `cohort-digest` | haiku | R | yes | Mechanical cohort/signup rollup, no judgment | — dormant |
| `support-triage` | sonnet | **A** | yes | Classifies a ticket, proposes routing, never replies | `policies/discord/support.md` — dormant |
| `moderation-flagger` | haiku | **A** | yes | Flags a message against policy; flag-only, no act tools | `policies/discord/moderation.md` — dormant |
| `announcement-drafter` | sonnet | **D** | yes | Drafts an announcement in the AEGIS voice; never sends | `policies/discord/announcements.md` — dormant |
| `review-tier-recommender` | haiku | **A** | yes | Recommends model/effort for a PR review, filling the gap `claude-review.yml` leaves open | Token audit A1 |
| `automerge-preflight` | haiku | **A** | yes | Checks a PR against `claude-review.yml`'s real automerge gates before it's pushed | Token audit A1/A2; `claude-review.yml` |
| `secrets-handling-auditor` | sonnet | **A** | yes | Audits a repo's secret-handling PRACTICE (storage, injection, gitignore) against org policy | `_security-public/policies/security/secrets_handling.md` |
| `local-transcript-secret-scanner` | sonnet | R | local-only | Scans local archived transcripts for secret-shaped content before a tier1 copy moves to a private repo; reports file:line + type, never the value | `SESSION_HANDOFF_2026-09-21-github-2d-pm-to-yoda-97.md:26`; `_security-public/policies/security/secrets_handling.md` |
| `incident-response-drafter` | sonnet | **D** | yes | Drafts a postmortem from the real P0-P3 severity table and response steps; proposes only | `_security-public/policies/security/incident_response.md` |
| `agent-automation-gatekeeper` | sonnet | **A** | yes | Reviews a *new* proposed agent against the org's automation policy before it's added | `_security-public/policies/security/agents_and_automation.md` |
| `data-classification-tagger` | haiku | **A** | yes | Tags data with the real C0-C3 classes, not a generic public/internal/confidential scheme | `_security-public/policies/data/classification.md` |
| `vuln-scan-passive` | sonnet | R | yes | Non-intrusive recon (`nmap -sV --open`, TLS check); runs anytime, no window needed | Owner-scoped security testing round |
| `vuln-scan-active` | sonnet | R | local-only | Safe-NSE vulnerability confirmation only, gated on `ops-infra`'s maintenance-window check | Owner-scoped security testing round; never attempts exploitation |
| `dependency-cve-scanner` | haiku | R | yes | `npm audit`/`pip-audit` against a repo's dependencies | Owner-scoped security testing round |
| `security-auditor` | sonnet | A | yes | Whole-estate security review (ops-cycle 7.1): passive-only, read-only audit of edge/vault-dev/ops-ca and the GitHub pipeline against `ops-infra` `docs/CONTROLS.md` + ansible verify tests; findings only, never fixes; active tests only via its caller inside an owner window | `ops-infra` `docs/CONTROLS.md`, `security/README.md`; `merge_authority.md`; `policies/security/*` are unratified stubs, not cited as rules |
| `ci-fixer` | sonnet | **D** | yes | L3 drafter (`headless_readiness_ladder.md`): given a repo + PR/run ID, reads the failing job's own log, finds root cause, and opens a minimal fix PR on a caller-provided branch, or reports the fix as owner-only with exact click steps; never merges, labels, re-runs, disables a check, or edits a test to pass | `headless_readiness_ladder.md` L3; `headless_agent_permissions.md`; `merge_authority.md` route C; `_security-public/policies/security/agents_and_automation.md` §1-3 |

## Legal research (global, `~/.claude/agents/`)

Brought into the mirror from local-only state per the 2026-09-17 roster audit's F1/R1. Two of the
three hold `WebSearch`/`WebFetch` — the only web-capable agents in the roster. A separate policy
review of these three against `_security-public/policies/security/agents_and_automation.md` is
running in a different lane; this PR only adds the files and their rows.

| Agent | Model | Role | Headless | Purpose | Grounded in |
|---|---|---|---|---|---|
| `legal-precedent-researcher` | sonnet | R | yes | Grounds a regulation/claim/dispute in quoted primary sources (statute text, agency guidance, case law); never concludes applicability | `_security-public/policies/compliance/regulations.md`, `regulatory_fact_questionnaire.md` |
| `legal-risk-assessor` | sonnet | **A** | yes | Turns facts + sourced research into a risk tier (1–4) and three resolution paths; never picks one | `_security-public/policies/compliance/regulations.md`, `regulatory_fact_questionnaire.md` |
| `attorney-referral-researcher` | sonnet | R | yes | After a Tier 1/2 lawyer-needed call, researches real attorneys/firms by practice area and jurisdiction; never ranks, contacts, or retains | `_security-public/policies/compliance/regulations.md`, `regulatory_fact_questionnaire.md` |
| `pm-agent` | sonnet | **A** | yes | Judgment layer for ops-platform's headless PM (triage/digest/escalation text only, Read/Grep only, no dispatch or self-scheduling) | `ops-platform` task 2.25; `aegis-pm-self-generation-limits`; Decision Queue card `headless-pm-cmd-run-mechanism-2026-09-17` |
| `blocked-work-sweep` | sonnet | R | yes | Compares what the Decision Queue and Fleet Status claim against live `gh`/disk state and reports blockers by root cause; never files or resolves a card | MasterThread PR #86; `decision_queue_standard.md` action-card contract |
| `gate-execution-auditor` | sonnet | R | yes | Checks each CI gate's last run for the tool's OWN output signature, not the job's conclusion, so a check that skipped or died early is caught; reports FALSE GREEN / INVISIBLE / UNRUNNABLE / UNENFORCED / HEALTHY. Mode 2 (merge-route audit): classifies each merged PR's actual route vs. its MERGE-VERDICT comment, reporting ROUTE-MISMATCH / STALE-VERDICT / SELF-MERGED / UNATTRIBUTED / CLEAN, baselined so pre-seat PRs land in one historical block, never itemised. Read-only, detects omission and mismatch, never attributes a merge to a session | Owner request 2026-09-17; `ESTATE_FACTS_CACHE.md` Claude-review failure classes; branch-protection audit 2026-09-18; owner decision `merge-seat-how-to-enforce-route-b-2026-09-18` (2026-09-18); `merge_authority.md`; `fleet_structure.md` provenance rules |
| `owner-instruction-verifier` | sonnet | **A** | yes | Executability check on an action card's steps before it's filed/relayed — traces each step to a primary source or a runnable command, WebFetches current vendor docs for named UI screens; verdict EXECUTABLE / UNVERIFIED-STEP n / IMPOSSIBLE-STEP n | `decision_queue_standard.md` "Executability check"; PM-process advisory §8 |
| `register-verifier` | haiku | R | yes | Checks `workstreams` register rows against live `gh`/`git` state; flags disagreement, empty `next` on staffed rows, stale `verified`, and the `dispatchable-and-idle` count the PM heartbeat must drive to 0 | `pm_role.md` "The workstream register", "The control loop"; PM-process advisory §8 |
| `denial-card-drafter` | haiku | **D** | yes | Drafts a complete Decision Queue action card in the "Permission-denial cards" shape from a classifier denial's raw facts; never files it | `decision_queue_standard.md` "Permission-denial cards"; PM-process advisory §8 |
| `click-file-builder` | sonnet | **D** | yes | Drafts an owner-run click-file pair (typed-YES gate, -WhatIf, retired guard, interactive-only gate); same-folder zz-UNDO; never runs anything it wrote | `skills/owner-click/SKILL.md` |
| `retirement-card-drafter` | haiku | **D** | yes | Drafts one Decision Queue action card per obsolete item, archive-never-delete; never files, never touches the item | `decision_queue_standard.md`; `SESSION_HANDOFF_2026-09-21-github-2d-pm-to-yoda-97.md:15` |
| `knowledge-extractor` | haiku | R | yes | Extracts source-cited facts from one tier1-labeled archive slice into a ledger, under a per-run cost cap; hard-refuses tier2/tier3 without an approved card. Re-review required once the owner decides tiered reading (open decision); tier 1 only until then. | `SESSION_HANDOFF_2026-09-21-github-2d-pm-to-yoda-97.md:15,26,32`; `FINAL_REVIEW_scope_plan_2026-09-21.md` §D item 11 |
| `schema-drafter` | sonnet | **D** | yes | Drafts a `--json-schema` document for a headless agent's report contract from that agent's own frontmatter + `## Output` section; never invents a field the source doesn't literally state; never writes the file or validates it against a real run | `headless_readiness_ladder.md` "What every headless run must emit" + build-state row on `--json-schema`; `DEV_SUITE_COVERAGE_2026-09-22.md` F4 |
| `wrapper-script-drafter` | sonnet | **D** | yes | Drafts a PowerShell headless-agent wrapper script by copying `tools/headless/Invoke-ReadOnlyAgent.ps1`'s exact conventions (claude.cmd resolution, fail-fast error handling, `--tools`/`--allowedTools` scoping, timeout+kill); returns the draft as text (no Write tool); never invents an undocumented CLI flag; never executes what it wrote | `tools/headless/Invoke-ReadOnlyAgent.ps1`; `tools/headless/README.md`; `DEV_SUITE_COVERAGE_2026-09-22.md` F2/F12 |
| `standards-doc-drafter` | sonnet | **D** | yes | Drafts a new `standards/sessions/*.md` document in the real shape (status line, scoped question, numbered rules, Sources section); always marks its own draft `PROPOSED, not ratified`; never writes the file, never claims ratification | `headless_readiness_ladder.md` status-line history; `merge_authority.md` route C; `DEV_SUITE_COVERAGE_2026-09-22.md` F9 |
| `standard-buildstate-checker` | haiku | R | yes | Sweeps `standards/`(+`policies/`) on `origin/<default>` for named mechanisms (scripts, tools, collections, agents, cross-repo paths) and reports which don't exist or lack a build-state marker | `pm_role.md` "Scaling and rotation" build-state rule; PM-process advisory §8 |

"Dormant" = Discord/Patreon automation stays paused per the standing owner decision
(`docs/REPOS.md`); the definition exists for when that's lifted, and creating the file triggers
nothing on its own.

## `MasterThread/.claude/agents/`

| Agent | Model | Headless | Purpose |
|---|---|---|---|
| `repo-ledger-refresh` | sonnet | yes | Regenerates `docs/REPOS.md` against live `gh` state |
| `handoff-writer` | sonnet | yes | Writes `SESSION_HANDOFF_*.md` from a round's end state |

## Repo-local (need that repo's own tools/paths)

R2 correction (2026-09-17 audit): the previous `invoice-drafter`/`expense-triage`/`quote-generator`
rows described agents from handymansfield PR #10, which closed unmerged — they exist nowhere on
origin. Replaced with `invoicer` and `job-intake`, the two agents actually on
`handymansfield` `origin/master`.

| Agent | Model | Role | Headless | Repo | Purpose |
|---|---|---|---|---|---|
| `mod-boot-test-runner` | sonnet | R | local-only | `aegis-mods`, `aegis-poi`, `aegis-pricing` | Wraps `tools/boot-test.ps1`; refuses while the owner is in game |
| `module-json-contract-checker` | haiku | **A** | yes | `aegis-mods`, `aegis-poi` | Validates `module.json` against `workshop_mod_standard.md` |
| `workshop-publish-preflight` | sonnet | **A** | yes | `aegis-mods` | Checks Workshop-publish readiness; never runs the actual publish |
| `classname-duplicate-triage` | haiku | **A** | yes | `site-chernarus` | Flags true dupes only — checks trader file first per `CLAUDE.md` |
| `economy-invariant-checker` | sonnet | **A** | yes | `site-chernarus` | Checks economy XML against policy AND the real files |
| `loot-table-reviewer` | sonnet | **A** | yes | `site-chernarus` | Reviews loot changes against `policies/dayz/loot_tables.md` |
| `rarity-price-reviewer` | sonnet | **A** | yes | `aegis-pricing` | Checks a curve against the real always-on guards (exchange exemption, spread, clamp ranges) |
| `vps-drift-checker` | sonnet | **A** | needs-local-keys | `ops-infra` | Read-only SSH diff of live config vs Ansible source |
| `invoicer` | sonnet | **D** | needs-connector | `handymansfield` | Turns a validated Job record into a proposed QuickBooks invoice + Gmail draft; proposes, never writes |
| `job-intake` | sonnet | **D** | needs-connector | `handymansfield` | Turns a free-text job note into a validated Job record, QuickBooks customer looked up read-only |
| `budget-envelope-reporter` | haiku | R | local-only | `ops-platform` | Read-only per-zone spend report via the real ledger `accountant.js`, never `reserve`/`settle` |
| `voice-transcriber` | haiku | R | local-only | `jarvis` | Wraps the already-built whisper.cpp CLI, output only |
| `voice-synthesizer` | haiku | **D** | local-only | `jarvis` | Wraps the already-built XTTS synthesis script; requires whose-voice-and-why before running |
| `badlands-mod-readiness-advisor` | sonnet | **A** | yes | `site-badlands` | Verdict against the real mod-readiness tracker |
| `badlands-hosting-plan-advisor` | sonnet | **A** | yes | `site-badlands` | Verdict against the real hosting plan doc |
| `badlands-release-prep-advisor` | sonnet | **A** | yes | `site-badlands` | Verdict against the real release-prep research doc |
| `badlands-status-reporter` | haiku | R | yes | `site-badlands` | Fact summary from `STATUS.md` + `docs/PLAN.md` |
| `badlands-mod-readiness-inventory` | haiku | R | yes | `site-badlands` | Fact list of mods + readiness state |
| `canon-consistency-advisor` | sonnet | **A** | yes | `core` | Checks a proposed lore change against the real canon bible (8 files) |
| `secret-rotation-schedule-advisor` | haiku | **A** | yes | `core` | Verdict against the real `docs/ops/SECRET-ROTATION.md` expiry tables |
| `vendored-validator-advisor` | sonnet | **A** | yes | `core` | Verdict against `docs/ops/VENDORED-VALIDATOR.md`; found site-chernarus's drift check has never run, 6 files already diverged |
| `canon-bible-inventory` | haiku | R | yes | `core` | Lists the real canon docs + last-modified dates |
| `secret-rotation-schedule-reporter` | haiku | R | yes | `core` | Reports which schedule entries are due, fact-only |
| `vendored-validator-status-reporter` | haiku | R | yes | `core` | Reports validator version/drift state, fact-only |
| `model-policy-advisor` | sonnet | **A** | yes | `claude-agents` | Checks a model choice against the real `model-policy` ROLES map; flags disagreement with `worker_role.md` rather than silently reconciling |
| `bug-report-triage-advisor` | sonnet | **A** | yes | `claude-agents` | Checks a bug report against the real `bug-report-agent/src/triage.js` — that package has no severity scale, says so rather than inventing one |
| `economy-worker-schema-advisor` | sonnet | **A** | yes | `claude-agents` | Checks a query/migration against the real `economy-worker/schema.sql` |
| `be-rcon-query-reporter` | haiku | R | needs-local-keys | `claude-agents` | Wraps `be-rcon`'s real read-only `players` query only |
| `bug-report-inventory` | haiku | R | yes | `claude-agents` | Lists open bug-report PRs via the real naming convention |
| `economy-worker-health-check` | haiku | R | needs-local-keys | `claude-agents` | Read-only Cloudflare Worker deploy/health status |

## Advisors against MasterThread's own standards (global, `~/.claude/agents/`)

Every real (non-stub) file in `standards/architecture`, `standards/coding`, `standards/release`,
`standards/requirements`, `standards/testing`, and `standards/maintenance` now has a paired Advisor
(checks compliance) and, for the higher-value ones, a matching drafter Agent (produces new content
in that standard's real format). `MasterThread/policies/*` (compliance, data, dayz, discord,
engineering, patreon) are excluded — every file there is a literal 0-byte stub; building against
them would mean inventing rules, which none of these do.

R3 correction (2026-09-17 audit): `rollout-plan-advisor`'s file (live and mirrored) pins `model:
haiku`; this table previously said `sonnet`. The file is the source of truth per `SYNC.md` — fixed
below.

| Agent | Model | Role | Headless | Purpose |
|---|---|---|---|---|
| `api-spec-advisor` | sonnet | **A** | yes | Verdict against `api_spec_standard.md`'s real required sections |
| `architecture-doc-advisor` | sonnet | **A** | yes | Verdict against `architecture_doc_standard.md`'s real required sections |
| `mermaid-styleguide-advisor` | haiku | **A** | yes | Verdict against `mermaid_styleguide.md`'s real rules |
| `sequence-diagram-advisor` | haiku | **A** | yes | Verdict against `sequence_diagram_standard.md`'s real rules |
| `error-handling-advisor` | haiku | **A** | yes | Verdict against `error_handling.md`'s real rules |
| `file-structure-advisor` | haiku | **A** | yes | Verdict against `file_structure.md`'s real rules |
| `logging-conventions-advisor` | haiku | **A** | yes | Verdict against `logging_conventions.md`'s real rules |
| `naming-conventions-advisor` | haiku | **A** | yes | Verdict against `naming_conventions.md`'s real rules |
| `changelog-advisor` | haiku | **A** | yes | Verdict against `changelog_standard.md`'s real format |
| `release-notes-advisor` | haiku | **A** | yes | Verdict against `release_notes_standard.md`'s real format |
| `rollout-plan-advisor` | haiku | **A** | yes | Verdict against `rollout_plan_standard.md` — thin standard (5 bullets, no worked template), flagged rather than treated as complete |
| `acceptance-criteria-advisor` | sonnet | **A** | yes | Verdict against `acceptance_criteria.md`'s real `AC-NNN` format |
| `functional-requirements-advisor` | sonnet | **A** | yes | Verdict against `functional_requirements.md`'s real `FR-XXX` format |
| `technical-requirements-advisor` | haiku | **A** | yes | Verdict against `technical_requirements.md`'s real rules |
| `user-story-advisor` | haiku | **A** | yes | Verdict against `user_story_format.md`'s real template |
| `integration-testing-advisor` | sonnet | **A** | yes | Verdict against `integration_testing.md`'s real Scope/Guidelines |
| `load-testing-advisor` | sonnet | **A** | yes | Verdict against `load_testing.md`'s real Targets/Metrics |
| `simulation-testing-advisor` | sonnet | **A** | yes | Verdict against `simulation_testing.md` — very thin (12 lines, no real document structure), flagged |
| `test-case-advisor` | haiku | **A** | yes | Verdict against `test_case_standard.md`'s real ID/Steps/Expected format |
| `escalation-matrix-advisor` | sonnet | **A** | yes | Verdict against `escalation_matrix.md` — thin (4 example rows, no real taxonomy), flagged |
| `issue-triage-advisor` | sonnet | **A** | yes | Verdict against `issue_triage_standard.md`'s real P0-P3 severities (no label taxonomy exists, flagged) |
| `changelog-entry-drafter` | sonnet | **D** | yes | Drafts a changelog entry in the real Added/Changed/Fixed/Removed format |
| `release-notes-drafter` | sonnet | **D** | yes | Drafts release notes in the real 5-section format |
| `user-story-drafter` | sonnet | **D** | yes | Drafts a user story in the real role/capability/value template |
| `test-case-drafter` | sonnet | **D** | yes | Drafts a test case in the real ID/Preconditions/Steps/Expected format |
| `acceptance-criteria-drafter` | sonnet | **D** | yes | Drafts acceptance criteria in the real `AC-NNN` format |
| `api-spec-drafter` | sonnet | **D** | yes | Drafts an API spec skeleton in the real 5-section format |
| `mermaid-diagram-drafter` | sonnet | **D** | yes | Drafts a diagram per the real style rules |
| `sequence-diagram-drafter` | sonnet | **D** | yes | Drafts a sequence diagram in the real syntax/naming rules |
| `rollout-plan-drafter` | sonnet | **D** | yes | Drafts a rollout plan — kept to exactly the standard's 5 sections, `TODO` markers rather than invented structure |
| `functional-requirements-drafter` | sonnet | **D** | yes | Drafts functional requirements in the real `FR-XXX` format |
| `technical-requirements-drafter` | sonnet | **D** | yes | Drafts a technical requirements doc in the real format |
| `integration-test-plan-drafter` | sonnet | **D** | yes | Drafts an integration test plan in the real format |
| `simulation-test-plan-drafter` | sonnet | **D** | yes | Drafts a simulation test note — standard is too thin for a full plan shape, scoped down accordingly |
| `architecture-doc-drafter` | sonnet | **D** | yes | Drafts an architecture doc skeleton in the real required sections |
| `load-test-plan-drafter` | sonnet | **D** | yes | Drafts a load test plan in the real format |
| `standards-stub-finder` | haiku | R | yes | Sweeps `standards/`+`policies/` and reports stub vs real (>5 lines) — exists because this exact mistake happened repeatedly while building this roster |
| `policy-coverage-reporter` | sonnet | R | yes | Cross-refs this file against every real standard/policy doc with no agent yet |
| `session-plan-advisor` | sonnet | **A** | yes | Verdict against `PLAN_template.md` and `session_plan_standard.md`'s real shape and 12 rules; defers Status-table drift to `plan-status-check` |
| `session-plan-drafter` | sonnet | **D** | yes | Drafts a multi-session plan in the real `PLAN_template.md` shape; `TODO: needs input` for anything not given |

## More global mechanical reporters (`~/.claude/agents/`)

| Agent | Model | Role | Headless | Purpose |
|---|---|---|---|---|
| `claude-session-archive-status` | haiku | R | local-only | Wraps `Invoke-Archive.ps1`'s real status output; never triggers a run |
| `archive-completeness-verifier` | haiku | R | yes | Per-file (path/size/SHA256) diff of a live tree against its archive copy; replaces file-count-only claims. Needed for `FINAL_REVIEW_scope_plan_2026-09-21.md` C7 |
| `github-org-repo-inventory` | haiku | R | yes | `gh repo list yodatech1988` fact table — name/visibility/last-push/archived |
| `discord-bot-key-age-reporter` | haiku | R | needs-local-keys | Real DPAPI key-file ages for the two named Discord bot keys; the second key's actual path differs from the assumed one — found and corrected during build |
| `ovh-vps-usage-reporter` | haiku | R | needs-local-keys | Wraps `OvhApiKey.ps1 GET /vps` (scope `/vps/*`, no `DELETE`), fact-only |
| `workshop-mod-inventory` | haiku | R | yes | Lists real `module.json` files across `aegis-mods`/`aegis-poi`; found `aegis-poi` has no real modules yet, only test fixtures |

## OVH hardware-management agents (`~/.claude/agents/`)

Extends `ovh-vps-usage-reporter`'s single-endpoint scope to the fuller Tier-A/B hardware-management
charter (`PM_INBOX/ovh-admin-agent/DESIGN_2026-09-25.md`). AEGIS-enclave only; the GWS mail host
(40.160.39.222) is excluded from every one of these agents, credential-level first (the
`aegis-hw-reader`/`aegis-hw-writer` IAM policies grant access only to the `aegis-hardware` resource
group, which the mail host is never a member of) — the Never-block line naming it explicitly is a
second layer, not the primary control. The four reporters below reach `ops-ca` through the same US
`read` IAM profile on `api.us.ovhcloud.com` as the other two AEGIS boxes; `ovh-config-preparer`
reaches it through the same US `read`/`write` profile pair (using only `read`) — in both cases it
is a member of the `aegis-hardware` resource group, not a separate CA-platform account.

| Agent | Model | Role | Headless | Purpose | Grounded in |
|---|---|---|---|---|---|
| `ovh-hardware-reporter` | haiku | R | needs-local-keys | Full Tier-A OVH hardware/edge-firewall/mitigation state for the AEGIS fleet, billing/services/renewal dropped from scope | `DESIGN_2026-09-25.md` §5/§6; gatekeeper PASS |
| `ovh-edge-firewall-auditor` | haiku | R | needs-local-keys | Diffs OVH edge-firewall state + externally observed open ports against `EXPECTED_PORTS.md`; CPG 3.S | `DESIGN_2026-09-25.md` §4a; gatekeeper PASS, no changes |
| `hardware-inventory-reconciler` | haiku | R | needs-local-keys | Reconciles OVH API inventory vs `ops-infra` `hosts.yml` (origin only) vs design-doc host list; CPG 2.A | `DESIGN_2026-09-25.md` §2a/§4a; gatekeeper PASS, no changes |
| `vps-patch-checker` | sonnet | R | yes | Mode A: infers AEGIS host patch state from `vuln-scan-passive` banners cross-referenced against USN/NVD; Mode B (SSH allowlist) described, not enabled; CPG 2.B | `DESIGN_2026-09-25.md` §1; gatekeeper PASS-WITH-CHANGES, applied |
| `cert-tls-watcher` | haiku | R | yes | TLS cert expiry (30/14/7-day)/chain/protocol/cipher checks for AEGIS public endpoints; kept separate from `vuln-scan-passive` (recurring fixed-list watch vs ad hoc breadth recon); CPG 3.S/3.K | `DESIGN_2026-09-25.md` §1/§4a; gatekeeper PASS-WITH-CHANGES, applied |
| `ovh-config-preparer` | sonnet | **D** | needs-local-keys | Prepares (never executes) Tier-B OVH writes — DNS record, VPS property, conditional edge-firewall rule — as a `click-file-builder` click-file, `live-reviewer`-reviewed, owner-run only. No `write`-profile credential reachable at all | `DESIGN_2026-09-25.md` §3/§4/§5/§6; `GATEKEEPER_REVIEW.md`; gatekeeper PASS-WITH-CHANGES, applied |

## Adding a new one

1. Ground it in a real standard, policy, or script — never invent process the agent then improvises.
2. Pin the cheapest model the task's judgment actually needs (see `orchestrator_role.md`'s table).
3. List only the tools it needs; deny writes explicitly where a slip would be costly (live, money,
   secrets, Discord/Patreon sends).
4. Add its `claude-agents/roster_meta.json` entry (role, headless, readonly, dormant) and run
   `python tools/generate_agents_md.py --write`: an advisor/drafter gets its row in the Advisors
   section automatically; any other agent needs a row in the section that fits, and `--write` then
   fills its Model/Role/Headless cells. `--check` (CI) fails if anything is missing or differs.
