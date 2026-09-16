# Handoff: Get Wired Solutions LLC — service scoping

Session `github-95`, 2026-09-15 → 2026-09-16. Take-over doc for whoever continues Get Wired
Solutions LLC's launch. Unrelated to the autonomous ops-cycle / `ops-policies` workstream — no
shared files, flagged here only where the two crossed.

## 1. What this session did

Jeremy asked to scope Get Wired Solutions LLC to sell his agents as a machine-learning-as-a-service
offering to local small businesses, covering security, isolated control, machine learning, and
built-in self-QC. No prior scoping existed — `get-wired-solutions` repo is still 2026-09-11 template
scaffolding (CI stub, PR template, CODEOWNERS, branch-protection script only).

Produced a full scope as an Artifact (not yet landed in the repo):

**Wired Back Office** — https://claude.ai/artifact/PUqKsHqRfviAywaQSMDCrR (private, owned by
Jeremy's account; 2 versions published so far)

Contents: the offer, target customer (local trades/property-management/insurance/auto/landscaping
in a ~40-mile Mansfield OH radius, health-data verticals excluded — see §3), an architecture
decision (client-held agents in the client's own accounts vs. a managed model, recommending
client-held exclusively through the first five clients), the four pillars as prospect-facing
copy — each with a "safe to say today" / "do not say yet" split — packaging and pricing (anchored
on replacement cost vs. a part-time office admin, not market research), the HandyMansfield proof
case and its conflict-of-interest problem, a gap register, a four-phase roadmap, and six decisions
left open for the owner.

The proof case is real and already running: HandyMansfield (Jeremy's own handyman business) has
Claude Code subagents that turn a finished job into a QuickBooks invoice and Gmail draft, match
Yardi/BofA ACH remittance advice to invoices, categorize expenses, and produce a month-end report.
Read-only tools, an owner-approval gate on every send. See `handymansfield/docs/PLAN.md`.

## 2. A correction mid-session, worth knowing

The first draft's top blocker was "the security and data policies are empty files," based on
`MasterThread/policies/` — genuinely true (all 29 files there are 5-28 byte stubs) but the **wrong
repo** for this claim. A peer session's cross-workstream ping (github-22, relaying the
`ops-policies` OPEN_QUESTIONS.md owner-review pass — see its handoff,
`SESSION_HANDOFF_2026-09-16-ops-policies-openq.md`) surfaced that the live policy-as-code pack is
`ops-policies`: four data classes with enforced constants (D3 "never reaches a model" is a schema
constant, not a setting), an egress gate and zone-separation rules in Rego with passing tests,
destination enrolment, a redaction leak-test corpus, JSON schemas, its own CI, and a 31-question
owner review just closed on 2026-09-16.

Corrected in the artifact (v2): the empty-stub finding downgraded from Blocker to a High-severity
"needs a client-facing summary, not new engineering" item; blockers before first sale went from 3
to 2 (both now paperwork — MSA/contract templates and E&O/cyber insurance, not policy content). Two
more owner answers strengthened the pitch directly: Q10's $3.00 invoice-passkey threshold became
concrete precedent for the "isolated control" pillar, and Q15's CISA/NIST SP 800-218 (SSDF)
citation replaced "don't say SOC 2" with an actual defensible standard to name instead. Q6/Q21's
GDPR framing hardened the recommendation to exclude health-data verticals (dental/medical/chiro) in
v1 — HIPAA plus GDPR Article 9 special-category is two regimes for a one-person firm to carry.

**Lesson for whoever cites security/data policy status next**: `MasterThread/policies/` is empty
stubs; `ops-policies` is the real pack. Don't conflate the two repos. This is also flagged in
github-22's handoff and in shared memory (`masterthread-policy-stubs-misground-agents.md`) — the T4
agents `agent-automation-gatekeeper` and `data-classification-tagger` are grounded in the empty
`MasterThread/policies/` paths and will return confident verdicts with nothing behind them. The PM
(github-92) has already scoped that as its own lane; not this session's to fix.

## 3. Open decisions for the owner (in the artifact, §"Six decisions")

1. **Delivery model** — client-held only through the first five clients (recommended), or offer
   managed hosting from the start?
2. **Pricing** — anchors ($1,200/$3,500/$8,000+ setup, $250/$650/$1,200+ monthly) are replacement-
   cost estimates, not surveyed against the local market.
3. **The name** — does "Get Wired Solutions" already read locally as electrical/IT work? Useful
   trust transfer or active confusion — only the owner knows the local read.
4. **Health-data verticals** — exclude dental/medical/chiropractic in v1 (recommended, strengthened
   this session by the GDPR/HIPAA overlap), or pursue with a BAA and the EU/international review
   that's already queued elsewhere as a follow-up (see `ops-policies` Q6/Q21).
5. **Disclosing HandyMansfield as the proof case** — recommended to disclose every time as the
   origin story rather than presenting it as a generic case study.
6. **The pipeline** — who Jeremy already knows in trades/property management within 40 miles. Not
   something this session can produce.

## 4. Not yet done — the actual next steps

Nothing has been written to the `get-wired-solutions` repo yet; everything so far is the Artifact.
Phase 0 in the roadmap (before anything is sold):

- Land the scope into `get-wired-solutions/docs/SCOPE.md` (offered to Jeremy, not yet actioned).
- Draw a two-page client-facing data-handling statement out of the `ops-policies` pack (see §2 —
  don't cite `MasterThread/policies/`).
- Draft MSA, SOW template, data-handling addendum (needs an Ohio small-business attorney).
- Get bound E&O and cyber liability insurance quotes.
- Confirm in writing what Anthropic's commercial terms permit stating to a client about data
  retention/training when reselling agent configuration as a service.
- Write a support model into the contract (business hours, no on-call, named escalation).
- Audit/stand up Get Wired's own back office (EIN, business bank, QuickBooks, W-9, invoice
  template) — worth confirming what already exists before assuming a gap.

No usage-watcher was registered for this session — it's a single-owner scoping conversation, not an
orchestrator dispatching lanes or workers (per the standing rule, that class of session is exempt).

## 5. Coordination notes

- Peer sessions this round: `github-bd`, `github-22` (finished its ops-policies handoff just before
  this one — see §2), `github-92` (PM, idle at last check). No file or repo overlap with any of
  their workstreams; the only intersection was the policy-stub correction in §2, already relayed.
- If a future session picks up Get Wired work, start from the Artifact URL above (read it with
  `Artifact` action `"read"` before editing) rather than re-deriving the scope — republish to the
  same URL to keep the link stable for Jeremy.
