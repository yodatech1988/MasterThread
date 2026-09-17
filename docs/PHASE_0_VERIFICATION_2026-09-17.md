# Phase 0 re-verification, 2026-09-17

Supersedes the status column of `PHASE_0_VERIFICATION_2026-09-16.md` for tasks 0.4, 0.6, 0.7, 0.8
and 0.10. That document's reasoning still stands and is not restated here; what changed is that the
Anthropic Console access gap it repeatedly recorded as `CANNOT VERIFY FROM HERE` **is closed**.

Phase 0 is "Lock decisions and accounts", 10 tasks, from the Autonomous ops cycle work tree
([artifact](https://claude.ai/artifact/WZsmRodvsHAbVFj54JghKf)). Every task is owner-tier.

## How the access gap closed

The 2026-09-16 pass concluded "Anthropic Console has no tool/API access from any session tonight."
That is true of the Console **web UI**, and it is why 0.4 and 0.6 sat unresolved for a day. It is not
true of the organization's state: an Anthropic **Admin API key** is stored on the owner's PC at
`%APPDATA%\AEGIS\anthropic-admin-key.clixml` (DPAPI, this Windows user only) and is injected into a
process by `jarvis/tools/AnthropicAdminKeyTool.ps1 -Run <script>`.

Every result below came from read-only `GET` calls made through that tool on 2026-09-17. No write
was made to the Anthropic organization by this session.

The general lesson, which generalizes past this plan: **"no Console access" and "no way to observe
the account" are different claims.** A day of `CANNOT VERIFY` on two tasks rested on treating them as
the same. Before recording a fact as unobservable, check whether a credential already on the box
answers it by another route.

## Live findings

| Task | 09-16 status | 09-17 status | Evidence read live today |
|---|---|---|---|
| 0.4 DayZ Gaming Server workspace exists | CANNOT VERIFY | **DONE** | `GET /v1/organizations/workspaces` returns `DayZ Gaming Server` (`wrkspc_01Ug34xPfn5vuPj6zth5Xf9t`), `archived_at: null`. |
| 0.6 Create 4 workspaces | NOT DONE | **DONE** | The same call returns all four — `Platform`, `Business`, `Household`, `Finance` — all unarchived. Five workspaces exist in total. |
| 0.7 Disable API-key creation + spend limits, 5 workspaces | NOT DONE, blocked on 0.6 | **Half impossible, half unblocked and carded** | See below. |
| 0.8 Hardware key vs TOTP on GitHub | CANNOT VERIFY | **Blocked on a purchase, not on a check** | Owner stated directly on 2026-09-17 that he has not bought the keys yet. |
| 0.10 Anthropic commercial terms / zero-retention | CANNOT VERIFY | **Reviewed; the ask is carded** | See below. |

0.1, 0.2, 0.3 and 0.9 were live-verified on 2026-09-16 and are not re-checked here. 0.5 (federation
rules on 4 repos) is unchanged and still needs a verdict on whether the gh-federation Worker/D1
deploy counts as done — this pass did not settle it.

### 0.6 resolves a contested tick, without a browser

`SESSION_HANDOFF_2026-09-17-93-task-progress-audit.md` records 0.6 as the single genuinely contested
tick between two audits (github-0c ticked it from a 2026-09-16 handoff note; github-2c could not see
it, having read only repos and `gh`), and lists "confirm 0.6 in a browser" as a next step. The call
above settles it from evidence rather than from a note, and that next step can be dropped.

### 0.7 is two tasks, and only one of them exists

**"Disable API-key creation" cannot be done as written.** Anthropic's Console exposes no such
control. Key creation is governed by organization role (Limited Developer, Developer, Admin), and
roles attach to people. Live membership:

- `GET /v1/organizations/users` → exactly one member, `jeremybergerai@gmail.com`, role `admin`.
- `GET /v1/organizations/workspaces/{id}/members` → **empty for all five workspaces.**

So the control would restrict nobody. Nor can a session route around it: Anthropic exposes no
key-creation API at all — `AnthropicAdminKeyTool.ps1`'s own header records this ("the admin key can
list and deactivate API keys org-wide but cannot create new ones"). Key creation is already a Console
click only the owner can make.

github-0c reached the same conclusion the same day from the opposite direction, auditing the plan's
task text rather than the account. Two methods, one answer: **the task needs rewording, not
building.**

**Spend limits are real, and the obvious version of them misses the biggest hole.** Anthropic's
per-workspace cap lives at Workspaces → *(workspace)* → **Limits** tab → **Change Limit**, and cannot
exceed the organization-wide cap. But `GET /v1/organizations/api_keys` shows 7 active keys, and
**four of them are not in any of the five workspaces** — `ADMIN API KEY`, `Jarvis`, `GITHUB` and
`Agent-Automation` sit in the account's Default workspace, which is not in the workspaces list and
takes no workspace limit. Capping the five named workspaces leaves those four governed only by the
organization limit. **The organization-wide cap is the one that matters**, and a card that asks only
for the five would have left the largest surface uncovered.

### Metered spend is effectively zero, which is what the caps should be sized to

`GET /v1/organizations/cost_report`, last 30 days: **$22.85 in total**, all of it on 2026-09-11,
09-12 and 09-13. Every day from 2026-09-14 onward reads **$0.00**. The switch to running session work
on the Claude subscription held.

**Read this endpoint's units before quoting it.** It returns **cents**, per the standing note two
sessions independently rediscovered on 2026-09-16. A first pass of this figure read as $2,285.15 —
a hundredfold overstatement that would have looked like a runaway-spend incident. The daily line
items carry `"currency": "USD"` alongside a cents amount, which is precisely the trap.

### 0.10: the terms were reviewed, and the answer is that the question barely applies

From Anthropic's privacy and platform documentation, read 2026-09-17:

- Zero data retention (ZDR) is **not automatic** — customers apply and Anthropic approves case by
  case.
- It covers **only** eligible Anthropic APIs, products used with a commercial organization API key
  (including Claude Code accessed via the API), and Claude Code for Enterprise plans.
- It does **not** cover Pro/Max subscription use.
- Without it, **30-day retention** of inputs and outputs is the standard commercial API term.
- Even under ZDR, user-safety classifier results are still retained.

Set against the spend figures above, the channel ZDR would cover currently carries **$0.00** of
traffic, while the sessions that actually touch credentials, the vault and financial repos run on the
subscription, which ZDR does not reach. The trigger to revisit is not a date but a change in
behaviour: metered API keys returning to real unattended use.

## What this leaves for the owner

Three cards filed on the Ops Decision Queue on 2026-09-17, one decision each:

| Card | Kind | What it asks |
|---|---|---|
| `phase0-action-set-workspace-spend-limits-2026-09-17` | action | Set the org cap first, then the five workspace caps, with alerts. |
| `phase0-disable-api-key-creation-not-a-real-control-2026-09-17` | decision | Reword 0.7; archive 3 unused legacy keys, or not. |
| `phase0-zero-data-retention-pursue-or-not-2026-09-17` | decision | Pursue a ZDR agreement now, or wait for a trigger. |

0.8 needs no card of its own: the existing `action-buy-two-hardware-keys-vault-prod-2026-09-17` card
covers the purchase, and was amended on 2026-09-17 to note that the same order also satisfies 0.8 —
one order, two things unblocked. Per that card, the owner cannot buy until his next pay period, and
it should not be nagged.

## Not carded, and someone should own it

The plan still describes **two hosts**; the owner approved a **four-host** layout on 2026-09-17
(`aegis-public-edge`, `vault-dev`, `ops-ci`, `vault-prod` — see
`SESSION_HANDOFF_2026-09-17-four-box-vault-layout.md`). Every Phase 1 scope shifts with it. This is a
genuine "lock decisions" item, it is still uncarded, and it was flagged as an unstarted next step by
both the four-box handoff and the 93-task audit. It is noted here so it stops being rediscovered.
