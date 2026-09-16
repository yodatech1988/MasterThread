# Session Handoff — 2026-09-16 — Fleet PM (github-64)

**PM:** github-64. Took over ~01:17 after a confused handoff from github-bd; Jeremy confirmed the
role directly, twice, in conversation. **Live document** — updated ~02:00, supersedes the earlier
rotation snapshot in this file.

## Fleet structure

- **PM:** github-64 — talks to leads, QC and merge authority only
- **Team A lead:** github-47 — github-4b, github-9a, github-4f, github-80, github-1e
- **Team B lead:** github-fa — github-54, github-f9, github-7a, github-85, github-4e
- **QC lane:** github-6b [534bc0] — reports to PM, outside both teams
- **Merge authority:** github-8e — reports to PM, sole merger, outside both teams

Rosters were formally delegated to the leads; PM no longer assigns members directly.

## THE PROVENANCE EVENT (read this first)

`~/.claude/CLAUDE.md` has CreationTime **and** LastWriteTime of 2026-09-16 00:46:05 — created
wholesale that morning. It contains the "PM handoff and usage responsibility: **required for every
session**" rule, self-labeled "(2026-09-16 owner decision)". MasterThread PR #54 was opened 25 min
later citing that text as owner authority; PR #55 cites it too. All 16 sessions launched that night
started from it.

**Resolution:** Jeremy confirmed agents collectively wrote it, **but he orchestrated every step**.
It is legitimate owner-directed policy. No rollback. PM freeze lifted.

**But three Team B sessions (github-54, github-85, github-f9) independently concluded they need
Jeremy's word directly, not the PM's relay, and are parked by choice.** Each escalated in its own
conversation. This is correct reasoning, not obstruction: a relayed "the owner confirms my authority
is legitimate," delivered by the session whose authority is in question, is structurally weak
evidence however true it is. **Do not pressure them.** They unpark when Jeremy answers them
directly, or they stay parked — that costs capacity, not correctness.

Fixes adopted fleet-wide as a result:
- Every QC verdict states reviewing session (and whether own read / diff-reviewer / live-reviewer)
  and authoring session.
- Both team leads state their own session identity, name the member a finding came from, and
  distinguish "I verified this" from "member X reported this."
- GitHub has **no session-level attribution** (all commits are author `yodatech1988`), so the PM's
  dispatch ledger is the only source. A commit/PR trailer carrying session name was proposed to
  Jeremy as a permanent fix.

## Traps discovered (these caused real confusion)

1. **Shared checkout on a feature branch.** `GitHub\MasterThread` sits on
   `agent/masterthread/fleet-pm-policies` (PR #54's branch), so its HEAD contains content
   origin/main lacks. Two sessions reached opposite conclusions about the same file. **Read
   `origin/main` explicitly, never the shared working tree.** (`docs/REPOS.md` was verified
   identical between the two, so QC's scan coverage was sound.)
2. **Green CI is not evidence.** claude-agents has no secret-scan job at all — its green checks say
   nothing about secrets. Several repos' red checks are equally meaningless (runner infra bug).
3. **Merged ≠ live.** services #97 merged ≠ runner fixed (needs VPS re-install); aegis-poi #13
   merged ≠ boot-verified (needs signing key); services #98 merged ≠ deployed (aegis-services has
   **no deploy workflow at all** — verified). Only Tier 4 content is genuinely live-bound.

## Merge queue — 23 tracked, 0 merged

Blocked because **github-8e's own classifier refuses merge-without-review.** Independent of the
provenance question. Three possible paths: Jeremy merges directly / Jeremy grants a permission rule
/ github-85's typed-YES tool (parked, see above — so only the first two are currently live options).

- **Tier 1 — docs/config (18):** aegis-mods #47, aegis-pricing #8, site-badlands #6, claude-agents
  #25/#26, MasterThread #52/#44/#55/#56, site-chernarus #98/#92/#99, core #77, services #93/#98,
  ops-policies #12/#13, aegis-poi #12
- **Tier 2 — credential tooling (1):** claude-agents #27 (GitHubTwoFactorKey.ps1) — live-reviewer
  PASS, PM cleared directly. "No secrets" is a manual-read finding, **not** CI-verified.
- **Tier 3 — wider blast radius (2):** aegis-poi #13 (untested game-script), services #97
  (fleet-wide runner fix)
- **Tier 4 — live production economy (3):** site-chernarus #96/#94/#88 — needs Jeremy or
  live-reviewer regardless of QC
- **Needs branch update first:** aegis-poi #12, #13 (BEHIND)

**services #97 is the highest-value merge in the queue** — it fixes the runner bug currently making
CI meaningless across several repos. Chain: merge #97 → Jeremy re-runs the runner installer on the
VPS (owner step) → CI signal becomes trustworthy again.

## Work completed this round

- **aegis-poi #13** (github-1e): found a **real production crash**, not a test artifact —
  `ReputationGate`'s `map<EntityAI,int>` held raw entity handles never cleared on delete (`Clear()`
  had zero call sites), and `BlackMarket.Shutdown()` can delete a trader via role cleanup without
  touching the gate. Fixed + `Unregister()`, 12/12 tests pass, **not boot-verified**. Guard-role
  feature deliberately split to a follow-up rather than stacking unverified code.
- **services #98** (github-80): CS5 rate limiting + resend-confirmation. Independent review caught a
  real **TOCTOU race** (count-then-insert let a concurrent burst exceed the limit); fixed with a
  regression test before the PR opened. Also corrected a stale CS4 status after verifying
  community-api is actually live.
- **services #97** (github-7a): runner gh CLI + gitleaks + unzip fixes, root-caused to
  `ops/vps/install-actions-runner.sh` (not ops-infra as first assumed).
- **MasterThread #55/#56, ops-policies #13, claude-agents #26/#27, site-chernarus #99** — see ledger
  below.
- **Classification research** (github-9a): found a **real conflict** — `_security-public` classes
  bill/transaction amounts C3 (no model access); `ops-policies` tags them D2 and is *already*
  running them through Haiku. Opposite handling of the same fact, live today. Owner decision.
  `_security-public` has no `.git` at all, so item 3 (platform-enclave text) is drafted and held
  until the repo exists 2026-09-19.

## Dispatch ledger (only source of PR→session attribution)

services #97 → github-7a · MasterThread #55, claude-agents #26, claude-agents #27 → github-4f ·
ops-policies #13, MasterThread #56 → github-9a · site-chernarus #99 → github-54 · aegis-poi #13 →
github-1e · services #98 → github-80. Everything else in the queue predates this fleet.

## Open decisions — Jeremy only

1. **Merge path** for the 23-PR queue (direct / permission grant / tool).
2. **Direct word to github-54, github-85, github-f9** in their own conversations — unparks three
   sessions including the merge tool.
3. **GitHub Actions org billing failure** — blocks jarvis #14, core #73, handymansfield #10.
4. **Financial classification conflict** — narrow C3 to match shipping D2, or stop ops-policies'
   finance-zone model exposure.
5. **website #27** — real PayPal `hosted_button_id` on the live donate page.
6. **deploy-loot.yml** — (a) enable as-is, (b) enable + generalize (design+build), (c) leave off.
7. **Mod signing key** — recommended option (C), a confined test-only keypair, **only if** the test
   key can be structurally barred from the live trusted-keys set and `publish.ps1`; with
   `verifySignatures=2` a wrongly-signed mod kicks every player.
8. **site-chernarus#48 progression metrics** — needs a human in-game check + SFTP/restart.
9. **Loot XML sync Phase C/D** — still blocked on Jeremy's password run.

## github-f9's parked lane — VPS SSH permission fix (preserved verbatim)

github-f9 declined to commit anything while parked (zero git action by choice) and pasted this
instead. Reproduced here so it survives the worktree. It also sits, uncommitted, at
`_wt-ops-infra-vps-ssh-permission-fix\LANE_STATUS.md` — **do not clean that worktree.**

> **What was found.** The "auto-mode classifier blocking SSH writes to the VPS" is this machine's
> global `C:\Users\yoda_\.claude\settings.json`. Its `permissions.allow` list pre-approves exactly
> two SSH invocations to the ops VPS (40.160.90.128): `ssh -i ~/.ssh/aegis-vps-admin-bot
> ubuntu@40.160.90.128*` and the same for user `aegis`. Anything else — different command shape,
> different key/user, scp, non-Bash SSH — falls through to an interactive prompt, blocking the
> unattended VPS-CI runner install. "Fixing" it means broadening that allowlist: a permission-settings
> edit.
>
> **Not investigated** (all three deliberately, because each is analysis in direct service of an edit
> to its own permission config): whether a narrower allow-pattern matching only the commands the
> runner install actually issues would unblock it without a blanket widen; what commands the runner
> install actually issues over SSH; whether any path other than editing global settings.json exists.
>
> **Why holding.** Dispatched through a peer chain (github-bd → github-fa → f9) that produced two
> confirmed-false or unverified claims earlier the same night. Not treating "the PM greenlit it" as
> sufficient authority for a permission widen against a production host. Raised directly with Jeremy.
>
> Worktree otherwise untouched: clean, `agent/ops-infra/vps-ssh-permission-fix`, current with
> origin/main as of dispatch.

**PM note — a path f9 did not have visibility into.** Its third unexplored option may dissolve the
blocker entirely. live-reviewer's review of ops-infra #9 (same night, different lane) established
that `tools/Invoke-Ansible.ps1` already exists as the repo's hardened remote-execution path: it runs
in a `--read-only` container, single-key-per-run, pinned known_hosts, and hard-refuses `-Apply`
against the edge host. If the runner install can be driven through that instead of raw SSH, **no
permission widen is needed at all** — which removes the exact thing f9 is objecting to rather than
asking it to accept the objection. Worth investigating before anyone proposes an allowlist change.

## Owner instructions issued via the Ops Decision Queue (2026-09-16 ~06:22-06:26 UTC)

Preserved here because the artifact's store was cleared at Jeremy's instruction after dispatch. **All
four were filed by the page as `status: resolved` and collapsed out of view** — the queue treats "the
owner typed something" as a decision, so a request for work looks identical to a closed item and
nobody sees it again. Design fix routed to github-54; until it lands, read the store directly rather
than trusting the page's open/resolved split.

| Item | What Jeremy actually wrote | Dispatched to |
|---|---|---|
| `restart-backup-hookpoint` | "I dont understand this context well enough to provide feedback investigate, try to self resolve, but give me better context to help me understand if you cant self resolve." | github-54 |
| `restart-backup-retention` | "resolve this using ops agent" | github-54 |
| `restart-backup-transport` | "review all of github to find where this exists, I feel like it was part of early build and harden stages." | github-54 — search ALL repos, not just REPOS.md-listed ones |
| `vps-drift-checker-hold` | "This doesnt make sense to me to clairfy, please provide me with context and impact." | PM answered directly |

The fifth item, `deploy-loot-scope`, was a genuine decision and is recorded as such: **leave
deploy-loot.yml disabled for now; enable it only after Session 13 closes the known gap** —
`deploy_loot.py` currently counts "#shutdown sent" as success rather than confirming a clean reboot,
which risks a false-green auto-deploy on a live pricing push.

## Follow-ups logged, not started

- `Get-StoredConfig` raw terminating error across all three `*Key.ps1` scripts (pre-existing).
- Delete untracked `tools/github-2fa/` from the MasterThread checkout — **only after** #27 merges.
- Dupe-exploit monitoring: hold behind gh-federation Sessions 5/6, not independently buildable.
- Guard-role (`blackmarket_guard`) implementation, after boot-testing is unblocked.
- Policy-stub audit (github-54): inventory done — **29 zero-length stubs**, all under
  `MasterThread/policies/`; `standards/`'s 32 files are all real. Per-stub "which agent cites it"
  analysis not started (session parked).
