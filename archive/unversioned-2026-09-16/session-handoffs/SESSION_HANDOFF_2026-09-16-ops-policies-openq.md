# Handoff: ops-policies OPEN_QUESTIONS.md owner review

Session `ops-policies-openq-2026-09-16` (github-22), 2026-09-16. Take-over doc for whoever
continues S9/S10 in `ops-policies`.

## 1. What this session did

The owner reviewed all 31 questions in `ops-policies/docs/OPEN_QUESTIONS.md` and replied to each.
This session recorded every reply, applied the clean low-risk edits directly, and queued everything
requiring coordinated multi-file changes as new sessions rather than hand-editing schema/Rego under
time pressure.

- **PR #11 (merged):** every question now has an `Owner reply (2026-09-16)` line and an updated
  state. Direct edits applied: invoice passkey threshold `egress/destinations.yaml`
  `thresholds.invoice_passkey_over_usd` 0 → 3 (Q10). Advisory-only entries recorded with no config
  change: Q15 (CI hosting, CISA/NIST SP 800-218 citation, confirms keeping this repo off the edge
  runner allowlist), Q6/Q21 (EU/GDPR framing confirms the existing D3 floor for minors'/health data
  is already correct, doesn't loosen it), Q13 (Fable 5.1 stays off-limits through build/debug, a
  post-launch lore task is noted but has nowhere to live yet — no 30-day plan doc exists), Q11
  (confirms the dynamic-chunking pattern already shipped is right).
- **PR #12 (merged):** one-line addendum to Q15 — the CI advisory rules out the internet-facing game
  **edge** specifically, not the separate dedicated non-game CI VPS that appeared on the OVH account
  2026-09-15. Added after the PM's cross-workstream audit flagged the ambiguity.
- **`docs/PLAN.md`** now carries two new queued sessions (both still unbuilt — session cards not yet
  written, just scoped):
  - **S9 — dynamic budget model & Discord restructure.** Owner explicitly rejected the static
    per-zone `envelopes_usd_monthly` model (Q2-Q4, Q28) and wants a demand-driven,
    priority-weighted allocator: higher priorities always keep a reserved floor, lower priorities
    spend into a small proportion of headroom only when nothing higher-priority is queued. The
    existing zero-envelope hard-refusal stays in force as the fallback until S9's replacement
    ships — **do not remove it prematurely**. S9 also owns the Discord destination fix (Q18): three
    destinations, not two — the AEGIS community server (unchanged, game alerts only), a **new**
    private-channel/DM destination on that same AEGIS server (PM only), and a **new** separate
    family Discord (household/Jarvis only). **PM flagged that Q16 (sessionless PM design, creates
    its own Discord channels per workstream) and Q18's destination model need to be designed
    together** — building one without the other risks a channel model that contradicts the
    destination model.
  - **S10 — ops-agent review batch.** 18 questions the owner explicitly routed to "an ops agent"
    rather than deciding himself: Q1, Q5, Q7, Q8, Q9, Q14, Q17, Q19, Q20, Q22, Q23, Q24, Q25, Q26,
    Q27, Q29, Q30, Q31. **Not yet dispatched** — see §2.
  - Also queued but not yet scheduled anywhere: an EU/international data-residency and consent
    review (Q6/Q21 follow-up), a standing pricing-page-drift monitor (Q12 — distinct from cost
    reporting, see the memory note below), and Q16's larger asks (de-identified naming, single
    master-key custody, sessionless PM) forwarded to `ops-platform`/`ops-infra` planning — this
    repo holds no runtime and can't build any of that itself.

## 2. S10 dispatch — held, not started

I did not dispatch S10's research agents this session. Sequence:

1. Reached out to the PM (`ops-cycle-pm`) to coordinate before dispatching, per the owner's
   instruction to check whether S10 could run in parallel with the PM's own audit work.
2. Three active peer sessions (github-95, github-bd, github-92/PM) were separately notified about
   the merged PR #11 and asked to flag impact on their own workstreams. github-bd found a real
   duplication risk (see §3). github-95 found nothing blocking but flagged an unrelated defect
   (§3). github-92 (PM) completed a cross-workstream audit (§3) and corrected an outdated
   owner-facing status page that had quoted the now-dead static envelopes three times.
3. PM's own usage endpoint 429'd twice mid-audit; it held its own new dispatch and asked to be
   treated as high-usage until the signal read clean, and said it would signal when clear.
4. This session's usage watcher subsequently read clean (5-hour 7%, weekly 13%, well under the 80%
   aggregator threshold) — but the PM had said **it** would signal, not that a clean local reading
   was sufficient, so S10 was held rather than assumed unblocked.
5. Owner then asked to end the session before that explicit PM signal arrived.

**Next step:** either wait for the PM's clear-usage signal, or get explicit owner sign-off, before
dispatching S10. When dispatched, one PR per question or small cluster, read-only
research/recommendation drafting first (this repo requires owner merge on every PR — no agent
self-merge).

## 3. Findings surfaced during coordination (saved to shared memory, not yet acted on further)

- **Admin `cost_report` API mechanics** (two sessions independently rediscovered this): amounts are
  in cents, `ending_at` is required and clamps to the last complete UTC day, `limit` caps at 31 for
  daily buckets. Distinct concern from Q12's pricing-page-drift monitor — don't conflate spend
  reporting with price-change detection. See memory `aegis-admin-cost-report-api-mechanics.md`.
- **MasterThread `policies/` are near-empty stubs**, 5-28 bytes across all 29 files (verified twice
  against the full list after two earlier partial-slice reads gave narrower, each-partially-wrong
  ranges — don't restate a narrower figure). `agent-automation-gatekeeper` and
  `data-classification-tagger` cite these paths as their grounding and currently return
  verdicts with nothing real behind them. **PM has already scoped this as its own lane** (which
  agents are grounded in stub files, what they actually return) — held on the same usage signal.
  One memory entry exists (`masterthread-policy-stubs-misground-agents.md`); don't create a second.
- **github-bd's finding**: a separate `_security-public/policies/compliance/regulations.md` +
  fact-questionnaire effort is doing its own independent GDPR-for-minors/health-data analysis using
  a C0-C3/tag/enclave model, with no cross-reference to ops-policies' D0-D3/zone model, and neither
  repo is in MasterThread's `docs/REPOS.md` ledger. Not a blocker for anyone today, but two
  classification schemes drifting independently is a real risk — worth the PM including in its
  audit scope if not already.
- **PM verified independently** that the program's actual billed cost reads $0.00 against the Admin
  Cost Report API, consistent with the owner's rule that dev-phase planning/estimation runs on the
  Claude Code Max subscription rather than metered API (Q2's second half).

## 4. Coordination / usage notes

- This session's usage watcher is registered as `ops-policies-openq-2026-09-16`. Register your own
  name rather than reusing it if you're a distinct session identity picking this up.
- Other orchestrators sharing the account's usage limit this window: `ops-cycle-pm` (aggregator from
  80%, autonomous ops-cycle PM) and `sessionless-unblock-20260915` (separate, wrapping up unrelated
  work per its own 2026-09-16 handoff doc). Check `ListAgents` before assuming any peer session
  named here is still live — this window churns fast.
- `ops-policies` repo state: `main` is clean, PR #11 and #12 both merged, no open PRs from this
  session. `make check` passes locally except a pre-existing `opa` binary gap (Rego tests can't run
  in this environment) — not introduced by this session, present before it started.
