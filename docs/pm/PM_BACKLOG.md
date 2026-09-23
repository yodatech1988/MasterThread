> **Round-2 snapshot, 2026-09-18.** This is a versioned copy of `GitHub\PM_BACKLOG_2026-09-18.md`
> as it stood when github-94's round record (`docs/pm/ROUND_2026-09-18_github-94.md`) was written.
> The live backlog continues to be edited at that path outside this repo; this copy is a point-in-
> time record for the round, not the working document — check the live file for current state.

# PM backlog — 2026-09-18

Built by github-c1, verified 2026-09-18T02:5x-03:0xZ. Sources: PM_NOTES_2026-09-18-github-94.md,
PM_PHASE_ADVISORY_2026-09-18.md §§7-9, ESTATE_FACTS_CACHE.md, 15 open Decision Queue cards
(live query), every repo's docs/PLAN.md on origin (23 repos swept), MasterThread docs/AGENTS.md
roster-gap check (via `policy-coverage-reporter`), MEMORY.md `(queued)` entries.

**Excluded categories, per instruction:** owner-only actions (live host/credential/money clicks —
these live in the Decision Queue, not here); mod-content work (paused per
`aegis-mod-work-pause-2026-09-14` — cuts nearly all of site-chernarus/site-badlands/aegis-mods/
aegis-poi/aegis-pricing's PLAN.md items, and the faction-boot-test Decision Queue follow-on);
payments (frozen); handymansfield Sessions 3-5 (payments/expenses/month-end — money-touching);
website PayPal-preset reconciliation (money-config — flagged to the owner directly, not listed as a
dev lane here).

**Capacity note:** "dispatchable-now" honors the one-open-agent-PR-per-repo rule using a live
`gh pr list --state open` per repo (checked 2026-09-18T02:5x-03:0xZ), except MasterThread, which
the PM confirmed has room (#115/#116 merged, only draft #93 remains). Where a repo already has
capacity used, only the first queued row for that repo is marked dispatchable; later rows for the
same repo are `no — queued behind repo capacity` with the earlier row as prerequisite.

---

## P1 — unblocks owner or fleet

| id | repo | task | done-when | model/effort | size | mergeRoute | prerequisites | dispatchable-now | source |
|---|---|---|---|---|---|---|---|---|---|
| p1-01 | MasterThread | Add "claimedAt is not evidence of a claim" note to `decision_queue_standard.md` (verbatim text in PM_NOTES §1) | PR merged; standard states `checkResult`/`claimComment` must be read alongside `claimedAt`, and `checkedBy:owner`+pre-dating `checkedAt` is a positive Done signal | Sonnet / medium | S | C | none | **yes** | PM_NOTES §1, PM instruction 03:10Z |
| p1-02 | MasterThread | `pm_role.md`: replace "does not poll" with heartbeat-tick description; add `dispatchable` register field; add "PM not worker" checks | PR merged, text matches live heartbeat behavior | Sonnet / medium | S | C | p1-01 merged (repo capacity) | no — queued behind p1-01 | Advisory §9 P1 |
| p1-03 | MasterThread | `tools/pm-heartbeat/`: `pm-heartbeat.json` writer + `Watch-PmHeartbeat.ps1` scheduled-task watchdog | Script + self-test pass; owner click-file registers the task | Sonnet / medium | S | C + owner click | p1-02 | no — queued | Advisory §9 P1 |
| p1-04 | MasterThread | `decision_queue_standard.md`: permission-denial cards (category `permission/denial`) + executability check required on action cards | PR merged; a denial-card template exists and one card is refiled through it as proof | Sonnet / medium | S | C | p1-01 (same file) | no — queued | Advisory §9 P1, §0.4 |
| p1-05 | MasterThread | `headless_agent_permissions.md`: remove the `overnight-sweep-supervisor.ps1` reference (file doesn't exist on origin/main) | PR merged, no dangling reference | Haiku 4.5 | XS | C | none (different file, could run parallel to p1-01 if repo capacity allowed — capped at 1) | no — queued | Advisory §9 P1, §1 table |
| p1-06 | core | Gitleaks-mirror fix: replace `secret-scan.yml`'s hand-rolled `git grep` with the pinned-binary `$RUNNER_TEMP` pattern already proven in `claude-session-archive/ci.yml` | PR merged; workflow runs gitleaks successfully on a self-hosted job, no `/tmp` dependency | Sonnet / medium | S | B (merge-authority) | none | **yes** — core has 0 open PRs | PM_NOTES §7 |
| p1-07 | claude-session-archive | Re-verify `ci.yml`'s current review/CI behavior — settle whether it's still hitting the class-3 zero-jobs failure (earlier claim that it "dropped pr-review.yml" was retracted; this repo never had one, only `ci.yml`) | Report states CONFIRMED/CHANGED with run ID + timestamp, cache updated | Haiku 4.5 | S | B | none | **yes** — 0 open PRs | ESTATE_FACTS_CACHE.md correction 2026-09-18T03:1xZ |
| p1-08 | MasterThread | Scope + create a `PLAN_template.md` drafter agent (paired with an advisor per roster convention) — genuinely uncovered standard, only gap found in the full AGENTS.md sweep | New agent def passes `agent-automation-gatekeeper`, lands via `claude-agents/`, AGENTS.md row added | Sonnet / medium | M | B (agents are seat-merged) | p1-01..05 clear MasterThread capacity | no — queued | policy-coverage-reporter sweep 2026-09-18 |
| p1-09 | ops-infra | Codify the CI runner's required packages (`unzip`, `gh`) in Ansible so a host rebuild can't silently drop them again (root cause of the "regressed off a working host" finding) | New Ansible task/role installs both packages idempotently; PR merged | Sonnet / medium | S | B | owner runs `AEGIS-Fix-Runner-Unzip.cmd` first (otherwise nothing to codify against) | no — ops-infra has 1 open PR (#37) AND owner-gated prereq | ESTATE_FACTS_CACHE.md, Decision Queue `action-install-unzip-gha-runner-2026-09-17` |
| p1-10 | ops-infra | Doc fix: `docs/PLAN.md`/four-box plan says "ops-ci", live OVH label is "ops-ca" — fix the doc, not the label (label may be deliberate) | PR merged, doc matches live label | Haiku 4.5 | XS | C | none | no — 1 open PR (#37) blocks | PM_NOTES §2 |
| p1-11 | ops-infra | Settle where (if anywhere) `security/evidence/` port-scan evidence lives — `docs/FIREWALL.md`'s own status table says "Not yet" while github-b6's handoff and the doc both point at a directory that doesn't exist on main | PR merged: either the directory + evidence lands, or the doc stops citing it | Sonnet / medium | S | C | p1-10 (repo capacity) | no — queued | PM_NOTES §3 |

**Round-2 note on p1-06, p1-10, p1-11:** by the time the round record was written, p1-10 and p1-11
had both been superseded — ops-infra #37 and #38 merged, fixing the ops-ci/ops-ca naming across
`PRODUCTION_LAYOUT.md`, `CONTROLS.md`, `FIREWALL.md` and `PLAN.md`, and independently confirming
`security/evidence/` already exists on `origin/main` with real content (p1-11's premise was false).
p1-06 (core gitleaks mirror) was scoped and verified ready by this session but explicitly dropped
this round on PM instruction (budget) — still queued, unchanged, ready to resume.

## P2 — truth/hygiene

| id | repo | task | done-when | model/effort | size | mergeRoute | prerequisites | dispatchable-now | source |
|---|---|---|---|---|---|---|---|---|---|
| p2-01 | MasterThread | `docs/AGENTS.md`: finish `generate_agents_md.py` (currently drops a column) and add a CI `--check` step so the roster is generated, not hand-kept | Generator output matches hand file column-for-column; CI fails on drift | Sonnet / medium | M | C | MasterThread capacity clears | no — queued | Advisory §1 table, §9 P2 |
| p2-02 | MasterThread | Fix `docs/AGENTS.md` index mis-credit: `postmortem_template.md` is followed by `incident-response-drafter`'s actual body but isn't credited in the index's "Grounded in" column | PR merged, index corrected | Haiku 4.5 | XS | C | MasterThread capacity | no — queued | policy-coverage-reporter sweep |
| p2-03 | MasterThread | New `standards/sessions/headless_readiness_ladder.md` (L0-L4 rungs + per-rung exit checks, per Advisory §6) | PR merged | Sonnet / medium | M | C | p1-01..05 land first | no — queued | Advisory §9 P2 |
| p2-04 | MasterThread | Scope + create 2 of the 4 agents from Advisory §8: `register-verifier` (exists already — verify it's current) and `standard-buildstate-checker` (exists already — verify current); the 2 NOT yet built are `owner-instruction-verifier` and `denial-card-drafter` — **correction: both now exist in the live roster** (confirmed via ListAgents' agent-type listing this session) — drop this row, no gap remains | n/a — already built | — | — | — | — | **not a real gap — verified built, retracted** | Advisory §8 cross-checked against live roster 2026-09-18 |
| p2-05 | ops-platform | `reasoner.js`: add `--settings`/`--permission-mode dontAsk`/`--permission-prompts none`, or mark the package dormant in its README if headless PM is not being pursued | PR merged either way — code fix or explicit dormancy note | Sonnet / medium | S | B | owner decision: build vs. drop (flag as a question, don't guess) | **yes** to start (0 open PRs) but should confirm owner intent before the code path (dormancy-note path is safe to just do) | Advisory §9 P3, §1 table |
| p2-06 | ops-policies | Session 9: "Ops-agent review batch" — resolve the ~18 queued owner questions sitting in PLAN.md, one PR per cluster (this is exactly the owner-attention-reduction work the advisory recommends) | First cluster PR merged, question count reduced and tracked | Sonnet / medium | M | C | none | **yes** — 0 open PRs | ops-policies PLAN.md sweep |
| p2-07 | claude-agents | Redesign the owner in-game chat-watch loop: replace the context-heavy `Monitor`-based tail with retirable/archivable subagents (owner explicitly asked for this 2026-09-16, filed as claude-agents issue #29) | Design doc + first implementation PR merged | Sonnet / medium | M | B | claude-agents' existing open PR (#30, plan-truth) clears | no — 1 open PR blocks | MEMORY `aegis-subagent-chat-watch-queued`, issue #29 |
| p2-08 | ops-household | Session 1: Family profile schema | PR merged, schema lands with no live-data touch | Sonnet / medium | S | B | none | **yes** — 0 open PRs, PLAN.md states no blockers | ops-household PLAN.md sweep |
| p2-09 | ops-household | Session 2: Consent tracking + note delivery | PR merged | Sonnet / medium | M | B | p2-08 merges (repo capacity) | no — queued | ops-household PLAN.md sweep |
| p2-10 | ops-household | Session 6: Right-to-delete runbook + drill (the drill itself has no stated blocker) | Runbook + drill script merged, drill executed in a safe/test context | Sonnet / medium | S | B | p2-08, p2-09 (repo capacity) | no — queued | ops-household PLAN.md sweep |
| p2-11 | ops-business | Session 1: data model + scope allowlist — **fixtures-only scope is available now**, full wiring is blocked on the Phase 2 gateway | PR merged for the fixtures/schema slice only | Sonnet / medium | S | B | none | **yes** — 0 open PRs, partial scope explicitly unblocked | ops-business PLAN.md sweep |
| p2-12 | website | Session 3: re-check for other stale docs (same class of defect as the donations-page audit) | PR merged listing/fixing any found | Haiku 4.5 | S | B | none | **yes** — 0 open PRs | website PLAN.md sweep |
| p2-13 | website | Session 6: Survival Handbook–style rules page | PR merged | Sonnet / medium | M | B | p2-12 (repo capacity) | no — queued | website PLAN.md sweep |

## P3 — nice

| id | repo | task | done-when | model/effort | size | mergeRoute | prerequisites | dispatchable-now | source |
|---|---|---|---|---|---|---|---|---|---|
| p3-01 | gh-federation | Session 4: discord-community enqueues via Cloudflare Worker instead of Octokit | PR merged | Sonnet / medium | M | B | claude-agents Session 3 (cross-repo, itself blocked on that repo's PR capacity) | no | gh-federation PLAN.md sweep |
| p3-02 | gh-federation | Session 5: bug-report-agent two-hop triage | PR merged | Sonnet / medium | M | B | p3-01 | no — queued | gh-federation PLAN.md sweep |
| p3-03 | gh-federation | Session 6: roll the pull workflow out to all routed repos | PR merged | Sonnet / medium | S | B | p3-01, p3-02 | no — queued | gh-federation PLAN.md sweep |
| p3-04 | repo-template | Write the Session 0 plan (currently a literal "Plan: not written yet" stub) | PLAN.md has a real Session 0 scoped | Haiku 4.5 | XS | B | none | **yes** — 0 open PRs | repo-template PLAN.md sweep |
| p3-05 | jarvis | Scaffold what CAN be built without Discord credentials (project has literally never started; creds are the only blocker for the rest) | A PR that separates "needs Discord creds" from "doesn't" in PLAN.md, plus any credential-free scaffolding | Haiku 4.5 | S | B | none for the scoping half; full build owner-gated on creds | **yes** for the scoping-only slice | MEMORY `jarvis-never-started`, jarvis PLAN.md sweep |
| p3-06 | be-rcon | Write an initial `docs/PLAN.md` (repo currently has none) | PLAN.md exists with at least a Session 0 | Haiku 4.5 | XS | B | none | **yes** — 0 open PRs | PLAN.md sweep (404) |
| p3-07 | gh-federation-selftest | Write an initial `docs/PLAN.md` (repo currently has none) | PLAN.md exists with at least a Session 0 | Haiku 4.5 | XS | B | none | **yes** — 0 open PRs | PLAN.md sweep (404) |
| p3-08 | ops-platform | Confirm build-vs-drop decision for `packages/project-manager` (currently only implements digest assembly; `bin/start.js` unconditionally throws) — this is a QUESTION, not a lane; route to the PM as a Decision Queue card, not a dev dispatch | Card filed and answered | — | XS | — (card) | none | n/a — this is a card to file, not a lane | Advisory §1 table, §9 owner-decisions list |

**Round-2 note on p3-06, p3-07:** both merged this round (be-rcon #7, gh-federation-selftest #2)
per github-c1's plan-stubs report.

---

## Not listed here — already in the Decision Queue as owner actions

Two cards have owner answers sitting **unactioned** (found by the Decision Queue sweep), worth the
PM's immediate attention since they're not "waiting on the owner" anymore:

- `factions-action-rep-flags-and-boot-test-2026-09-17` — owner said "run it now" (02:50:42Z); nobody
  has run the boot-test procedure yet. **Excluded from this backlog as mod-content/owner-assisted
  in-game work**, but flagging since the owner's answer is stale.
- `action-verify-paypal-donate-amount-presets-2026-09-17` — owner gave specific preset/recurring
  preferences (02:52:25Z); no PR or task filed to reconcile website copy or PayPal config.
  **Excluded here as money-touching** — needs the PM or owner to route it, not a standing dev lane.

## Retracted while building this

`p2-04` above was drafted from Advisory §8 (which listed 4 agents as "to scope, none exist today")
but a live cross-check against the current agent roster this session found `owner-instruction-
verifier` and `denial-card-drafter` both already exist and are live-callable. The advisory was
correct as of 01:00Z; the roster has moved since. Don't re-propose these two.

---

**Totals:** 8 P1 rows (3 dispatchable now) + 12 P2 rows (5 dispatchable now, 1 retracted) + 8 P3 rows
(5 dispatchable now, 1 is a card-not-a-lane) = **28 rows, 13 dispatchable right now** without
breaching the one-open-PR-per-repo cap, spread across 11 different repos so they can run in parallel.

---

## Added post-snapshot, 2026-09-23 — owner-gated, card not a lane

Filed by a worker session (masterthread-c0) that hit this live, per `p3-08`'s convention: an
owner-permission blocker is a Decision Queue card, not a dev dispatch. No live PM session was
reachable via `ListAgents` at filing time, so this is recorded here for PM pickup rather than
handed to a PM directly.

| id | repo | task | done-when | model/effort | size | mergeRoute | prerequisites | dispatchable-now | source |
|---|---|---|---|---|---|---|---|---|---|
| p1-12 | (new repos) | Create `yodatech1988/federal-statutes-regs-rag` and `yodatech1988/federal-caselaw-live-lookup` on GitHub, then land each repo's `SCOPE.md` (statutes/regs repo: owner-supplied `SCOPE.md` + `source-catalog.csv`; case-law repo: stub scope referencing the statutes/regs repo as its sibling per the "explicitly out of scope, tracked elsewhere" boundary) | Both repos exist and each has a merged/pushed `SCOPE.md` matching the boundary stated in the source document | Sonnet / low | XS | — (card) | **owner must create the two repos, or grant the GitHub App `Administration`/repo-creation permission on the `yodatech1988` account** | n/a — blocked on owner action, not a lane | This session, 2026-09-23: `mcp__github__create_repository` returned `403 Resource not accessible by integration` for both repos; `get_me` confirms `yodatech1988` is a personal account, not an org, which GitHub Apps generally cannot create repos under even with broader permissions |

**Note:** once the repos exist, pushing the two scope documents is a trivial XS lane with no other
blockers — the only owner action needed is the repo creation (or a permission grant) itself.
