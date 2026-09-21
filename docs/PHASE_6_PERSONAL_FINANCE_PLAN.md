# Phase 6 — Personal finance (read-only): scope, plan, agent scoping

Status: DRAFT for owner review, 2026-09-21. Nothing dispatched; no Phase 6 lane exists.
Source of truth for task IDs: the ops-cycle authority plan (https://claude.ai/artifact/WZsmRodvsHAbVFj54JghKf), rescored 2026-09-21 against origin/main and gh only. Live hosts and owner consoles were NOT checked.
Task IDs 6.1-6.10 are cited in PRs and cards: do not renumber.

## 1. Research findings (what is true today)

**Live check, 2026-09-21 ~14:40Z (gh REST + origin/main across ops-platform, ops-policies, ops-infra, ops-business, ops-household, MasterThread):**
- 4.1/4.2/4.8 NOT done. ops-business plan: nightly pull "blocked on 4.1/4.2", invoice drafting "blocked on 4.8"; only a fixtures-only gateway stub exists.
- 5.4 NOT done. ops-household plan: "blocked on the owner creating the private household Discord server". Merged so far: #1-#6 (plan, 5.1 schema, consent tools, right-to-delete part 1).
- 2.28 approval app, 2.30 passkey enrollment, 2.31 gate test: no trace in any repo. ops-platform has no approval-app package; ops-platform PR #18 (routing loader, described as "not wired") MERGED 2026-09-21, as were #16, #17 and #19; nothing deployed to the vault. ops-policies holds passkey/egress Rego (policy only, PR #7 merged).
- 3.12: no evidence anywhere.
- vault-prod: "never been ordered" (ops-infra docs/PLAN.md line 21). Only aegis-public-edge and vault-dev are in the inventory. ops-infra PRs #43 (draft) and #44 open.
- 7.1-7.4: no PRs or task entries found.
- PARTIAL PRIOR ART: ops-policies (S7, PR #5, merged 2026-09-15) already has a redaction test spec and reference redactor: `tests/redaction/*`, `tools/reference_redactor.py`, `tools/checks_redaction.py`, `schema/redaction-*.schema.json`. The production redaction pipeline is NOT built (ops-platform). 6.4/6.6/6.7 must build on this, not start from zero.
- No SimpleFIN, Plaid or Presidio paths in any of the six repos. No finance/redaction PRs open.
- Owner-only steps leave no repo trace, so these were checked in the Decision Queue (357 cards) and Fleet Status `workstreams` (11 rows), read 2026-09-21:
  - Hardware keys (needed for 2.30 passkey enrollment): card `action-buy-two-hardware-keys-vault-prod-2026-09-17` is resolved as **PARKED, "NOT done, NOT verified"** (owner instruction 2026-09-19); owner's own note is to buy two keys next pay period, reminder set for Thu 2026-09-24. So 2.30 is not done.
  - 5.4 blocker: card `ops-platform-discord-channel-private-server-2026-09-21` resolved 2026-09-21, "Yes - a separate private Discord server". Deciding is done; creating the server is still the owner's step and nothing shows it exists.
  - Access path to vault-prod decided 2026-09-17: Tailscale main (login + approval app), Cloudflare Access backup; follow-up still pending.
  - Bill amounts (`ops-policies-q32-bill-amount-model-exposure`, resolved 2026-09-18): an isolated amount with no account, routing or identity data is C2, matching what the finance zone already does. This governs what 6.8 may show a model.
  - No Intuit (4.1) or Phase 6 cards exist. No `workstreams` row mentions finance, 2.30, 4.1, 5.4 or 3.12. Whether 4.1 was done off-repo remains unverified, but no card or repo trace says it was.

**From the plan artifact (its own rescore, not live-verified):**
- Phase 6 is 0 of 10 done, 0 in progress.
- Phase order is 0, 1, 2, 3, 4, 5, 6, then 7 (Review). The owner set the order to Phases 3, 4, 5, 6 and then the review (plan artifact, 2026-09-21). Phase 6 does not wait on the review.
- Phase 6 waits on 4.8 (categorization writes) and 5.4 (Discord reminders). Transitively it waits on 3.12, 2.28 (approval app, not yet built), 2.30 (owner enrolls hardware key + phone passkey) and 2.31 (gate test). vault-prod is not ordered.
- Phase 7 (review) now runs after Phase 6, so its scope covers every zone, including finance (7.2 depends on 6.9).
- Finance zone budget is $0 (task 0.3) until this phase earns one. Spend limits are prepaid only, auto-reload off (0.7, closed 2026-09-21).
- No `ops-finance` repo exists. Existing: ops-platform, ops-policies, ops-infra, ops-business, ops-household. The plan does not say where Phase 6 code lands.
- Two older repos exist, checked read-only 2026-09-21 (file tree, README and docs/PLAN.md only): `yodatech1988/personal-finance` (private, last push 2026-09-13) is a small local-first JavaScript vault: age-encrypted receipt/statement ingest and a folder watcher, with tests and CI; its plan leaves QuickBooks filing blocked on a personal QBO company. It has no bank feed, redaction pipeline or pay-run code, so it is at most prior art for encrypted storage, not a home for Phase 6. `yodatech1988/business-finance` (private, last push 2026-09-16) holds HandyMansfield receipt-to-QuickBooks routing: a plan, README, CI and one setup script, with no application code. It is business-side and not relevant to Phase 6.
- Phase docs pattern seen once: MasterThread `docs/PHASE_0_VERIFICATION_<date>.md`.
- Not linked to Phase 6 in the plan: QuickBooks (Phase 4 only), Venmo/payments repo, tax records folders.

Could not check: live hosts, owner consoles, whether 4.8/5.4 are further along than the plan's rescore, the Scorecard artifact.

## 2. Scope

**Goal (from the plan):** read-only account feeds, a redaction pipeline with leak tests, and a weekly pay run the owner approves and pays himself.

**Exit criterion:** the redaction pipeline passes its leak tests AND the owner has approved and paid one weekly pay run himself.

**In scope:** feed ingestion (read scopes), bill text extraction, redaction + token map + second-pass leak check, fake-bill test suite, weekly pay-run preparation with anomaly flags, retention jobs, the owner's first passkey-approved pay run.

**Out of scope (hard rules from the plan):**
- The system never executes payments. Owner approves by passkey, then pays in his bank's bill pay.
- Online banking passwords are never stored. Feed scopes are read only.
- No D2/D3 data on Discord; alerts say only "approval waiting, see the app".
- Redaction happens in code, not in a model. Model use is Haiku 4.5 on redacted text only, for odd bills.
- Payment execution / new-payee cooling period is a possible LATER phase, not this one.

## 3. Tasks, ordering and agent scoping

Format: id, title, who / size / hold, depends on.

### Group A: Feeds and extraction
| ID | Task | Who / size / hold | After | Agent brief |
|---|---|---|---|---|
| 6.1 | Choose read-only feed (SimpleFIN or Plaid, read scopes) | you / S / no | 4.8, 5.4 | Owner decision card. Research agent (read-only, Sonnet) compares cost, bank coverage, read-scope guarantees, retention. Recommend, never sign up. |
| 6.2 | Parsers: JSON, OFX, CSV | agent / M / no | 6.1 | Write lane, one repo. Must test on synthetic fixtures only. |
| 6.3 | Bill text extraction (pdfplumber, Tesseract) | agent / S / no | 6.1 | Write lane. Synthetic PDFs and scans only. |

### Group B: Redaction (all HOLD: owner approval before merge)
| ID | Task | Who / size / hold | After | Agent brief |
|---|---|---|---|---|
| 6.4 | Presidio + custom rules: ABA checksum, Luhn, SSN, EIN, payee-adjacent account numbers | agent / M / HOLD | 6.3 | Write lane. Deterministic code. Must not call any model. |
| 6.5 | Encrypted token map; values restored only inside the vault | agent / S / HOLD | 6.4 | Write lane; touches credentials/crypto, so live-reviewer (Opus) reviews, not diff-reviewer. |
| 6.6 | Second-pass leak check; failure blocks the API call and routes to weekly review | agent / S / HOLD | 6.4 | Write lane. Fail closed. |
| 6.7 | Fake-bill test suite with planted numbers, in the protected policy path; runs on every pipeline change | agent / M / HOLD | 6.6 | Write lane. Verify tests actually fail when a planted number leaks (mutation check), and that the CI gate really executes (gate-execution-auditor). |

### Group C: Pay run
| ID | Task | Who / size / hold | After | Agent brief |
|---|---|---|---|---|
| 6.8 | Weekly pay run with anomaly flags | agent / M / no | 6.2, 6.5, 6.7 | Write lane. Bill-prep agent: deterministic rules first, Haiku 4.5 on redacted text for odd bills. Output goes to the approval app only. |
| 6.9 | Owner approves first pay run by passkey, pays in his bank | you / XS / HOLD | 6.8 | Action card, one step per card, clickable links. Never resolved by a session. |
| 6.10 | Retention: raw 90 d, digests 1 y, audit 7 y, D2 transcripts 30 d | agent / S / no | 6.2 | Write lane. Verify against the retention list in the plan's data-handling design. |

### Critical path
6.1 -> 6.3 -> 6.4 -> 6.6 -> 6.7 -> 6.8 -> 6.9. Parallel branches: 6.2 (after 6.1), 6.5 (after 6.4), 6.10 (after 6.2).
Write lanes cap at ~6 in parallel, one per repo/worktree; realistically 2 at a time here because the pipeline pieces share a repo.

### Existing agents that fit
- collision-check before any lane dispatch.
- diff-reviewer for 6.2, 6.3, 6.10; live-reviewer (Opus, deliberate) for 6.4-6.8 because they touch credentials and money-adjacent paths.
- gate-execution-auditor for the 6.7 CI gate.
- data-classification-tagger for every field the pipeline handles.
- secrets-handling-auditor after 6.5.
- click-file-builder / denial-card-drafter only if an owner click-file is needed.

### Agent gap (per standing rule: scope and create rather than ad hoc)
No agent exists for "leak-test mutation check" (plant a number, confirm the pipeline catches it) or for bank-feed vendor comparison. Propose two agent definitions, checked before joining the roster: `redaction-leak-tester` (read-only + test runner, synthetic data only) and `feed-vendor-researcher` (read-only, web). Not built yet.

## 4. Entry gate (do not dispatch 6.x until all true)
1. Phases 4 and 5 are far enough along for 4.8 and 5.4 (item 2); Phase 6 does not wait on the Phase 7 review.
2. 4.8 and 5.4 done, verified on main AND running (a tick means code on main, not deployed).
3. 2.28 approval app exists and 2.30/2.31 passed (passkey path works).
4. vault-prod ordered and hardened; finance envelope workspace `finance-redacted` defined.
5. Finance zone budget decided (currently $0) and a repo for the code named.

## 5. Risks
- Approval app and vault-prod do not exist: 6.5, 6.8, 6.9 cannot be real until they do.
- Real bank data appearing in tests or logs. Mitigation: synthetic fixtures only, leak suite in protected path, no real feed connected before 6.7 passes.
- A test suite that goes green without running (false-green). Mitigation: gate-execution-auditor.
- Feed vendor retention/terms are unknown until 6.1 research.
- Order dependency chain is long; the plan itself estimates Game Zone alone at ~14 Oct, so Phase 6 is well after that. No date is committed.

## 6. Open decisions (each would be its own Decision Queue card; NOT filed yet)
1. Where does Phase 6 code live: new `ops-finance` repo, or inside ops-platform / ops-household? (Recommend a new private repo, matching the per-zone repo split.)
2. SimpleFIN vs Plaid (this is 6.1 itself; needs research first).
3. Finance-zone monthly budget once Phase 6 starts (currently $0).
4. Approve creating the two new agents above.

Cards are dependent on the entry gate, so per owner rule they are drafted here and filed only when their parent is resolved.

## 7. Gaps in this document (not done unless documented)
- Live-checked via gh/origin and the Decision Queue + Fleet Status stores (section 1). NOT checked: live hosts, the Scorecard artifact, whether owner steps were done outside any card, repos outside the six (payments, services, claude-agents), archived MasterThread ops-cycle handoffs. The gh code search hit a rate limit at the end; last searches ran on same-session saved copies.
- Task text comes from a subagent's read of the plan artifact; I did not independently re-read the artifact. The plan's design doc is not in any repo, so task IDs have no in-repo source of truth.
- No effort/cost estimate in dollars; no dates.
- This file is the plan document only. It changes no standard or task ID and files no Decision Queue card.

## 8. Relationship to the Phase 6 review page
An independent review of Phase 6 is queued in Fleet Status `workstreams` as `review-personal-finance-phase-6`, with its page at https://claude.ai/artifact/LJaAic7zGr4vpuk2VJ2hJz. Its trigger is the plan's `done` list containing 6.9 and 6.7 (as recorded 2026-09-21; recheck against the plan, not this file).
- This document is the **build plan** (scope, order, agent briefs, entry gate). The page is the **review** that runs when the phase closes.
- If a task, dependency or exit criterion changes, update both in the same piece of work, and add a change-log line to the review page.
- The review's planned checks (fresh leak suite on new planted numbers, gateway has no payment endpoint, audit log for the first pay run) should be treated as extra acceptance criteria for 6.7, 6.8 and 6.9.
