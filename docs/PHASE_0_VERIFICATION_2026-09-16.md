# Phase 0 verification, 2026-09-16

> **Superseded in part by `PHASE_0_VERIFICATION_2026-09-17.md`.** Tasks 0.4 and 0.6 are now
> live-verified DONE, and 0.7/0.8/0.10 have moved. The Anthropic Console access gap this document
> records as `CANNOT VERIFY FROM HERE` was closed on 2026-09-17 via the stored Admin API key, not
> via the Console. Everything below is left exactly as written, as the record of what was knowable
> that night.

Verification of the "Autonomous ops cycle" work tree's Phase 0 (Lock decisions and accounts, 10
tasks — [artifact](https://claude.ai/artifact/WZsmRodvsHAbVFj54JghKf)), against live systems where
any tool access exists, not against the plan's own saved notes. Every Phase 0 task is owner-tier
(`"you"`) — no session can complete these directly; the deliverable is what to click, not what to
build.

**Anthropic Console has no tool/API access from any session tonight.** Every item below that needed
a Console check is `CANNOT VERIFY FROM HERE`, stated plainly rather than trusted from a note.

| Task | Status | Evidence | Destination if not done |
|---|---|---|---|
| 0.1 Confirm two hosts | **DONE** | Live OVH API check: `vps-736c134b` (aegis-public-edge) and `vps-6bfe4b32` (personal-vault) both exist, state=running. | — |
| 0.2 Confirm Discord for chat | **DONE** as a decision | Not independently checkable (a choice, not a system state). Infra it implies (bots actually running) is separately unconfirmed — memory shows credential tooling exists, neither bot confirmed live. Out of this task's literal scope. | — |
| 0.3 Set budget envelope | **DONE**, cross-checked | The noted $10/mo game envelope matches the real, independently-confirmed OVH cost for aegis-public-edge ($10/mo). Numbers agree, not just a note claiming so. | — |
| 0.4 DayZ Gaming Server workspace exists | **CANNOT VERIFY FROM HERE** | No Console access. | console.anthropic.com → Workspaces → look for one named "DayZ Gaming Server" (or similar). No fleet-side obstacle to remove first. |
| 0.5 Federation rules, 4 repos | **Leaning NOT DONE as a live control** | `gh-federation` repo has real design docs referencing the pattern, but no rule file names core/services/site-chernarus/website specifically, and memory notes the Worker/D1 deploy (the actual live enforcement) is blocked on an owner step. Design real, enforcement unconfirmed live. | Needs the Worker/D1 deploy step from gh-federation's own plan — an owner action, specifics in that repo's docs/PLAN.md. |
| 0.6 Create 4 workspaces | **NOT DONE** (per saved state; Console access gap prevents independent confirmation either way) | — | console.anthropic.com → Workspaces → "+ New workspace" → create: Platform, Business, Household, Finance. |
| 0.7 Disable API-key creation + spend limits, all 5 workspaces | **NOT DONE**, sequenced behind 0.4/0.6 | Can't set limits on workspaces that may not exist yet. | Once 0.6 is done: each workspace → Settings → API Keys (disable creation) and Settings → Usage & Billing (spend limit). Menu labels approximate — from general Console layout knowledge, not a live look. |
| 0.8 Hardware key vs TOTP on GitHub | **CANNOT VERIFY FROM HERE**, confirmed with real attempts, not assumed | Tried: `gh api user` (the `two_factor_authentication` field returns `null` for this token type), the security-keys/WebAuthn-adjacent endpoint (404; the scope it requests, `admin:ssh_signing_key`, is for SSH *signing* keys — a different feature, not 2FA factors), GraphQL's `viewer` schema (nothing there), and a full response-header dump from `gh api user` (only `X-OAuth-Scopes` present, nothing about 2FA method). GitHub's REST/GraphQL APIs do not expose which 2FA factor is enrolled, for any token, by design. | github.com/settings/security → "Two-factor methods" section → check for a "Security key" entry alongside/instead of "Authenticator app." |
| 0.9 Create 5 private repos | **DONE**, live-verified | `gh api repos/yodatech1988/<repo>` confirmed all five (ops-platform, ops-policies, ops-infra, ops-business, ops-household) exist, private=true, created 2026-09-15T19:12–19:13Z. Not taken from the saved note. | — |
| 0.10 Review Anthropic commercial terms / zero-retention question | **CANNOT VERIFY**, inherently owner-only | Not a system state — reading terms and asking a question. | Anthropic's commercial/enterprise terms and data-retention policy, reachable from the Console's account/billing area, or by asking Anthropic sales/support directly. No specific URL given here — none was verified live, and a guessed link is worse than none. |

## Net: what's actually clickable right now

Unblocked owner actions today: **0.4, 0.6, 0.8 (a check, not a change), 0.10.** 0.7 waits on 0.6.
0.5 needs a real verdict on whether the Worker/D1 deploy step counts as done — not enough context
here to call it either way.

## A pattern worth carrying forward

Every Phase 1 item (verified separately, by Team A) that the saved notes marked done but couldn't be
independently re-confirmed from a session without host/SSH access fell into the same shape: real
Ansible code exists in `ops-infra`, but whether it's actually been *applied* to a live host is a
different, narrower kind of unverified than something that's simply absent from the repo entirely.
Worth keeping those two categories — "code exists, applied-state unknown" vs. "genuinely not
started" — distinct in any future verification pass, rather than treating all "unconfirmed" items as
equally uncertain.
