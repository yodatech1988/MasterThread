# Handoff — Autonomous ops cycle PM (2026-09-16, supersedes 2026-09-15's)

**You are the project manager for the autonomous ops cycle program.** Sonnet 5 / low effort. You
manage; lanes do the building. Read this file first, not the 2026-09-15 one — this one reflects
what actually happened, including two corrections to that file's own assumptions.

---

## 0. Do these two things before anything else

**1. Start the usage watcher** (required of every orchestrator; do not skip):

```
Monitor  command: MT=C:/Users/yoda_/GitHub/MasterThread; N=ops-cycle-pm; git -C $MT fetch -q origin main; git -C $MT show origin/main:tools/usage-monitor/usage-watch.ps1 > "$APPDATA/AEGIS/usage-watch.$N.ps1" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$APPDATA/AEGIS/usage-watch.$N.ps1" -HandoffRoot C:/Users/yoda_/GitHub -Name $N -Program "autonomous ops cycle PM" 2>&1 || echo "USAGE-ERROR could not load or run usage-watch.ps1 from MasterThread origin/main"
         description: Claude usage tiers for ops-cycle-pm
         timeout_ms: 1800000
```

Re-arm with the same `-Name` every ~30 min. Act on `USAGE TIER` lines: 80 = stop dispatching,
90 = pause lanes, 97 = write the next handoff, 98 = commit it, 99 = stop. **This session hit
`USAGE-ERROR` once (three 429s from the rate-limit endpoint) — usage was genuinely UNKNOWN for a
stretch, not just unlucky polling.** Treat that reading as high and don't dispatch new lanes until
a clean read comes back. As of the last clean read: 10% of the 5-hour window, 9% weekly, but **three
orchestrators now share this account's limit** — `ops-cycle-pm` (you), `agent-roster-pm`, and
`sessionless-unblock-20260915`. You're the aggregator from 80% on. Check `/usage` before anything
big, not just the watcher.

**2. Read the authority document.** Still the single source of truth for design and the 93-task
work tree:

- `Artifact` tool, `action: "read"`, `url: https://claude.ai/artifact/WZsmRodvsHAbVFj54JghKf`
- Status report for the owner: `https://claude.ai/artifact/FNaa1dZWGDd6sN9vsuvhcZ`
- New this session: a checkpoint on tiered dispatch (Scout/Builder/Operator model, real tool-call
  cost data): `https://claude.ai/artifact/6uWe34wXL6b9aERnrcnYdC`

**3. Also load `MasterThread` docs/AGENTS.md.** A 30-agent T4 roster landed mid-session (PR #50):
cheap, narrow, read-only agents (`pr-state-sweep`, `plan-status-check`, `worktree-sweep`,
`collision-check`, `origin-reader`, `lane-card-writer`, `secret-rotation-auditor`,
`github-2fa-audit`, etc.), installed globally at `~/.claude/agents/`. **Use these instead of doing
drift checks by hand** — this session manually found two stale PLAN.md status tables and did a
5-repo PR sweep, which is exactly `plan-status-check` and `pr-state-sweep`'s job. The ~6-lane fleet
cap now only bounds *write* lanes (worktree/branch/PR); read-only T4 fan-out is budget-gated, not
lane-count-gated. Fire several in parallel for reconnaissance before spending an Opus lane on
discovery.

---

## 1. Standing rules — unchanged, plus two learned this session

Same table as before (nothing AEGIS-branded on the vault; no git/terminal steps for Jeremy; no
stacked PRs; zero cost first; no PATs/static keys; verify before merge; don't re-raise settled
decisions; no local DayZ boots while Jeremy plays). Two additions:

| Rule | Detail |
|---|---|
| **A classifier denial is a decision point, not a retry loop** | Three denials this session (`aideinit` as audit tampering, Cloudflare/DNS setup, Anthropic workspace creation as a permission grant) were all correct calls, not bugs. Don't work around any of them — report and let the owner decide. Build an owner-run `.cmd` tool instead when the action is small enough (see `Vault-AideBaseline.cmd`, `create-ops-workspaces.cjs`). |
| **Test capability, don't assume it from "who" in the work tree** | The work tree marks several tasks `"who":"you"`. Two of those turned out to be wrong this session: Anthropic Console workspace creation (0.6) is a real, working API call, not UI-only — I created none because of the classifier, but the *capability* exists. OVH "set a spending cap" (part of 1.10/Session 9) doesn't exist as *any* mechanism, UI or API — the work tree's own wording was wrong. Verify each owner-only claim once before repeating it. |

---

## 2. Where things stand

**Progress: PR count moved from 25 merged / 0 open (start of session) to 28 merged / 0 open now.**
Three lanes landed, plus three direct doc corrections.

### Landed this session

- **`ops-infra#7`** (merged) — AppArmor enforcement on all four vault zones. Root cause and fix are
  in the previous handoff; holds up, negative tests pass, re-apply is `changed=0`.
- **`ops-infra#8`** (merged **by the owner directly**, 2026-09-16T01:16 UTC — not by me) — LUKS
  containers (`vault-data` auto-unlock, `vault-sealed` passphrase-only) and the vault's first real
  age/SOPS identities. Verified live post-merge: `/srv/vault` and `/srv/sealed` both mounted from
  their mappers, re-apply `changed=0`, no age key material on the unencrypted root. **The owner has
  since completed both remaining steps**: `Vault-Sealed.cmd` → Init, and `VaultRecoveryKey.cmd` →
  Generate. **Not yet done: the AIDE baseline refresh** (see below).
- **`ops-platform#9`** (merged) — task 2.11, the GitHub issue-form (`work.yml`) that maps 1:1 onto
  `requestToIssue.js`'s validation. 154/154 tests.
- **`ops-platform` and `ops-policies` `docs/PLAN.md`** (direct pushes, docs-only) — both status
  tables claimed every PR was "open for review"/"in review"; all 16 were actually merged. Corrected
  against `origin/main` and `gh pr list`, not the stale local checkouts (both were 30-40 commits
  behind — remember to `git merge --ff-only origin/main` before trusting a local `ops-platform` or
  `ops-policies` checkout).
- **`ops-infra/docs/PLAN.md` Decision C** (direct push, docs-only) — corrected: **OVH Public Cloud
  has no hard spending cap, on any project, ever.** Verified against OVH's own billing docs. The
  only native lever is a forecast-based *email alert* (project → Billing → Current usage tab) — it
  doesn't block or throttle anything. The original task text assumed a control that doesn't exist.
  Owner declined the zero-cost Backblaze B2 alternative (doesn't want a second storage account) and
  accepted the email alert as the ceiling. **This means Session 9 is no longer blocked on an
  impossible owner action** — see §4.
- **`MasterThread#51`** (merged) — added a worked calibration example to `task_sizing.md` per a
  peer session's request: two same-carded Opus/high lanes (AppArmor 62 tool calls/29 min, LUKS+age
  129/96 min) and two manual sweeps that were exactly T4-agent shaped.
- **`jarvis` (master, direct push)** — `tools/create-ops-workspaces.cjs`, a companion script for
  `AnthropicAdminKeyTool.ps1 -Run` that creates the four Console workspaces idempotently. Not yet
  run (classifier-blocked for me; owner runs it via the click-through tool instead).

### Still open, unmerged

None. All five repos show zero open PRs as of this handoff.

### Not deployed yet (unchanged from last handoff)

`ops-platform` (154 tests) and `ops-policies` (all sessions merged) are fully built, fully tested,
and sitting idle until SPIRE/federation exist on the vault.

---

## 3. New tool built this session: the owner click-through

**`C:\Users\yoda_\GitHub\Complete-OpsCycleOwnerTasks.cmd`** — one double-click wizard, 8 steps, for
everything left that only the owner can do. Safe to re-run; nothing destructive. As of this
handoff:

| # | Step | Status |
|---|---|---|
| 1 | AIDE baseline refresh | **Not done.** Report was reviewed (313 added/211 removed/732 changed, every entry traces to Sessions 7 and 11, nothing unexplained) — recommend Refresh. `Vault-AideBaseline.cmd` in `ops-infra/tools/` (merged, permanent location now that #8 landed). |
| 2 | Create 4 Anthropic workspaces | **Not done** (classifier-blocked for me; script is ready and idempotent) |
| 3 | Anthropic spend limits + disable key creation | Console-UI-only, confirmed via two independent checks (workspace object has no such field; the dedicated Spend Limits API is Enterprise-only and this org has exactly one seat, confirmed via `/v1/organizations/users`) |
| 4 | OVH spending cap | **Corrected**: no such control exists; set the forecast email alert instead (Billing → Current usage) |
| 5 | OVH storage separation | Not done, not urgent |
| 6 | Discord private server | Not done |
| 7 | GitHub 2FA method check | Not done |
| 8 | Cloudflare permission decision | Not a click — see §4, biggest real blocker |

If the owner says any of 1-7 are done, verify over SSH/API before believing it (same discipline as
everything else) — don't just mark it done because it was said.

---

## 4. The queue, re-ordered by what's actually true now

1. **Session 8 — Postgres and hash-chained audit log.** Opus 5/high. **Now genuinely ready** — both
   its dependencies (Session 7, Session 2's floor) are merged. Read `Sessions 2 and 7 PRs` per its
   own "Read:" line before starting. This is the next lane to dispatch.
2. **Sessions 5+6 — Cloudflare Tunnel + Access, then close port 22.** Opus 5/high. **Still the
   single biggest blocker.** Not blocked by DNS (`bergervault.link` resolves on Cloudflare
   nameservers, confirmed) or by dependencies — blocked by Claude Code's own auto-mode classifier
   under "DNS / Domain / Cert Changes." I did not attempt to work around it. Three ways forward,
   all requiring the owner:
   a. Owner tells a session directly to allow DNS/domain/cert changes for this lane (the session can
      then add the permission rule itself).
   b. Owner does the Cloudflare Tunnel + Access setup by hand (bigger job, not a click).
   c. Leave it queued.
   This gates the approval app (2.28) and both business/household phases downstream — worth
   revisiting with the owner explicitly rather than letting it sit.
3. **Session 9 — restic backups.** Sonnet 5/medium. **Downgraded from "blocked" to "ready, with a
   caveat."** OVH Object Storage as primary (same account, no new vendor — owner declined
   Backblaze), PC append-only copy off-site over the vault's Cloudflare Tunnel once that lands
   (Sessions 5/6 dependency — actually check this: Session 9 may not strictly need the tunnel if the
   PC copy path can use something else in the interim; verify before assuming it's blocked on
   Sessions 5/6 too). No spending cap exists to set; recommend the owner set the forecast email
   alert as a nice-to-have, not a hard gate.
4. **Session 10 — restore test.** After 8 and 9. Phase 1 exit.
5. **Phase 2 build-out** — unchanged, still blocked on SPIRE/federation (needs Session 10) and the
   owner's Console/CI steps.

### The CI host situation (update from a peer session, not yet verified by me)

A peer session (`github-ce`) relayed that the owner has decided on a small dedicated personal-account
VPS for ops-repo CI/release-signing key custody — a deliberate, owner-approved exception to
zero-cost-first, and the owner is provisioning it himself. **Do not provision, order, or spend
anything toward this.** Pick it up as a self-hosted runner host for the ops repos once it appears,
without disrupting whatever's in flight. Not yet confirmed live as of this handoff — check before
assuming it exists.

---

## 5. Merging — unchanged from last handoff, still correct

Same guidance: check base branch before merging, use the async merge API for stacked PRs, never let
Jeremy merge these himself. Nothing new to add — no stacking happened this session.

---

## 6. Waiting on the owner

1. **Cloudflare classifier decision** (§4.2) — the actual critical path now.
2. **AIDE baseline refresh** — `Vault-AideBaseline.cmd`, step 1 of the click-through.
3. **The 4 Anthropic workspaces + spend limits/key-creation-disable** — steps 2-3 of the click-through.
4. **Discord private server, GitHub 2FA method, OVH storage separation** — steps 5-7.
5. **Confirm the CI VPS** once it exists (see §4).
6. Same longer-tail items from 2026-09-15's handoff not yet touched: Phase 4/5 answers (QuickBooks
   company count, invoice auto-send threshold, etc.) — not urgent, raise when those phases start.

`ops-policies/docs/OPEN_QUESTIONS.md` still has 31 open questions on safe defaults, none blocking.

---

## 7. Cost — now with real per-lane data instead of a lump estimate

Three lanes actually ran this session (real token/tool-call/duration figures from their completion
reports, not estimates):

| Lane | Model | Tokens | Tool calls | Wall clock |
|---|---|---|---|---|
| AppArmor (Session 11 finish) | Opus 5, high | 180,719 | 62 | 29 min |
| LUKS + age identities (Session 7) | Opus 5, high | 313,303 | 129 | 96 min |
| Work issue form (task 2.11) | Sonnet 5 | 109,976 | 52 | 5 min |

Rough blended-rate estimate (85/15 input/output split assumed, no cache discount applied — actual
is very likely lower): **~$4.30 for these three lanes**, on top of the 2026-09-15 checkpoint's
$143.10 program-to-date figure. Both figures are token-count estimates, not billed dollars.

**Attempted and not finished this session: pulling real billed cost from the Admin Cost Report API**
(`GET /v1/organizations/cost_report`) instead of estimating. Confirmed the Admin key can reach it
(other org endpoints — `/v1/organizations/me`, `/v1/organizations/users`, `/v1/organizations/spend_limits/effective`
— all returned real data), but two parameter-shape issues weren't resolved before this handoff was
written: `limit` must be ≤31, and it needs an explicit `ending_at` (not just `starting_at`) or it
400s with "ending date must be after starting date." **Next session: fix those two params and this
becomes the real, per-day, real-dollar cost source** — worth wiring into `ops-platform`'s accountant
(task 2.23) once that's deployed, rather than the token-count estimate above. The user specifically
asked for cost to be "logged as actual cost per system" (i.e., per zone) — this API plus the
already-built `packages/ledger/src/accountant.js` (`spendPerZone`) is the real mechanism; nothing
persists this automatically yet because the ledger isn't deployed.

Also confirmed this session: **this org is not Claude Enterprise** (one seat, no RBAC groups) — the
dedicated Spend Limits API doesn't apply here at all, on top of being the wrong scope (per-seat, not
per-workspace).

---

## 8. Memory files worth knowing

Same list as 2026-09-15's handoff, plus: **`github-stacked-pr-merge`, `aegis-usage-monitor-tool`,
`aegis-orchestrator-role`, `aegis-zero-cost-first`, `aegis-parallel-worktree-system`,
`aegis-worktree-remove-no-force`, `aegis-verify-before-merge`, `jeremy-no-git-commands`,
`jeremy-directness-preference`**. Consider adding a new one this session earned: *classifier denials
under DNS/cert, audit-tampering, and permission-grant categories are correct-by-design, not bugs to
route around — always stop and report, per §1's new rule.*

Worktrees safe to prune now (PR merged, check `git status` first, never `--force`):
`_wt-ops-infra-apparmor`, `_wt-ops-infra-session7-encryption`, `_wt-ops-platform-work-issue-form`,
`_wt-MasterThread-task-sizing-note`. **Leave `_wt-ops-infra-session56-cloudflare-access` in place**
— it exists for whenever the Cloudflare lane is unblocked, and creating it again would need a fresh
`New-ParallelWorktrees.ps1` run anyway, so pruning it saves nothing.

**Open question raised by the owner and not yet answered:** "who joined the server" — asked at the
very end of this session with no server specified (the not-yet-created ops-cycle Discord server, or
the DayZ game server — both plausible, session had no visibility into either). Ask the owner to
clarify which server at the start of next session; don't guess.
