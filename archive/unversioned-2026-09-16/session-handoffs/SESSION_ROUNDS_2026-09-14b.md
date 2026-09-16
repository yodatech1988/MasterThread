# Session rounds: full GitHub review (2026-09-14, evening)

Covers every repo. It folds in `SESSION_ROUNDS_2026-09-14.md` (the aegis-mods research lanes, all
still unstarted, are lane R1-3 here) and replaces `SESSION_HANDOFF_2026-09-14.md`'s "next steps".
Rules from MasterThread `standards/sessions/session_plan_standard.md` still apply:

- One session = one fresh conversation, opened in the named repo folder.
- Each session works in its own git worktree.
- At most one open agent PR per repo.
- Run `gh pr view --json state` before pushing follow-up commits.

## What GitHub actually looks like (checked live, 2026-09-14 ~06:00 UTC)

**Open PRs: 2, both green.** services#71 (VPS hardening docs) and core#69 (`OvhApiKey.ps1`).
Neither was auto-merged. While they're open, rule 4 blocks new sessions in those two repos.

**The docs lag behind the repos. Don't trust them without checking.**
- MasterThread `docs/REPOS.md` is wrong in at least 7 rows:
  - aegis-pricing: says #1/#3/#4 are unmerged. All three are merged.
  - gh-federation: says "plan amendment next". Sessions 1–3 are merged.
  - services, claude-agents, site-chernarus, core and handymansfield are also out of date.
- The **Status tables in each repo's `docs/PLAN.md` are also out of date:**
  - core: Session 2 shows "in review" but is merged.
  - site-chernarus: everything shows "not started", but Session 1 is #61, merged.
  - aegis-pricing: Sessions 1–2 show "not started", but both are merged.
  - aegis-poi: Session 1 shows "open" but is merged.
  - claude-agents: Session 1 shows "in review" but is merged.
  - handymansfield: Session 1 shows "in review" but is merged.
  - claude-session-archive: Session 4 shows "in progress" but is merged.
  - Each session below fixes its own repo's table first, so no separate cleanup PRs are needed.

**Where things really stand:**
- **Chernarus.** Phase 2 of the go-live plan is met: owner answers are on site-chernarus#41.
  `@AEGIS_Pricing` is deployed to production for a live test. **Nobody has confirmed the server
  came back clean** after the panel restart.
- **OVH VPS.** `community-api`, `economy-api` and `event-relay` are live behind the tunnel.
  - The PC's old `community-api` pm2 entries are still running.
  - event-relay has not had an end-to-end test event.
- **gh-federation.** Sessions 1–3 are merged. The Worker and D1 database are **not deployed**.
  - **`wrangler` is already logged in on this PC** (`wrangler whoami` works), so a session can
    deploy it now. You don't have to do it by hand.
  - `wrangler.toml` still has the `database_id` placeholder.
- **Economy automation (services#58) is no longer blocked.** #55 and #56 are both closed.
- **core#5.** The Anthropic key half is **done**: `nasdara-dev-key` is inactive and the new key
  expires 2027-01-01. Still open: the plaintext DayZ join, BattlEye admin and VPPAdminTools
  passwords.
- **aegis-mods.** Lanes #9–#14 have zero comments. No `AEGIS_Core` code exists yet.
- **services has no Claude credential (#57).** Its `review / review` check "passes" in 7 seconds,
  which means it's skipping.
- **Discord work is parked** (owner, 2026-09-14). Everything Discord-shaped is in the Parked table
  at the bottom.

## How models and effort were picked

| Model | Effort | Used for |
|---|---|---|
| **Opus 5** | high | Live production actions, access control and credentials, money (QuickBooks), secret-leak risk, and contract-setting code other sessions build on (`AEGIS_Core`, perk hooks, death path) |
| **Sonnet 5** | high | Big multi-file data edits where the invariants matter (economy defects, payments matching) |
| **Sonnet 5** | medium | Normal plan sessions with a clear Read/Do/Done-when, research lanes, verification runs |
| **Sonnet 5** | low | Doc-only checks and small fixes |

Set these with `/model` and `/effort` at the start of each conversation. Everything runs on the
subscription. If an Opus 5 / high session misses its done-when bar, re-run it at **xhigh**. Don't
switch models.

---

## Round 0: you (about 20 min, no sessions)

In order of what each one unblocks:

1. **Merge services#71 and core#69** with the Merge button on GitHub. Both are green. This clears
   rule 4 for R1-6 and R1-7.
2. **Be ready to join Chernarus in game** with `@AEGIS_Pricing` loaded. R1-1 and R1-1b both need you
   in game at the same time. That's the only live window this round needs.
3. **Answer handymansfield Session 2's two questions.** Is QuickBooks the system of record? Which
   real job should be invoiced next? R1-8 asks you anyway if you skip this.
4. **Anthropic Console → Settings → Workload identity → Connect workload → GitHub Actions**, with one
   rule scoped to `yodatech1988/claude-agents`. It produces 4 identifiers, not secrets.
   gh-federation Session 5 (R2-4) can't be tested without it.
5. **Steam:** confirm you're unsubscribed from the removed mod family's 4 Workshop items. Local files
   are gone, but that doesn't cancel the subscription.
6. **services#57:** run `/install-github-app` for `services` so its PR review really runs.

**Defaults I've applied. Say so if you want something different:**
- `@BallerZ_Teddys` is still loaded on live, even though #32 cut it. It gets removed in the go-live
  push (R3-2), not before.
- The Shockbyte port `22319` reservation should be released. It can't host custom code (services#33).

## Round 0.5: worktree cleanup (run alone, before Round 1)

There are about 100 `_wt-*` folders in `GitHub\`. Run this **before** starting Round 1. Otherwise
it could remove a worktree a parallel session is using.

| ID | Open in | Model | Effort |
|---|---|---|---|
| R0-W | `C:\Users\yoda_\GitHub` | Sonnet 5 | medium |

> `List every git worktree under C:\Users\yoda_\GitHub (the _wt-* folders, _worktrees\*, and core-tmp-pr69). For each one, show git status, unpushed commits, and whether its branch's PR is merged, closed or open (gh pr list --head <branch> --state all). Remove only worktrees that are clean, fully pushed, and whose PR is merged or closed. Use git worktree remove from the owning repo — never --force, never rm, never touch a main checkout. Leave everything else and give me one table: folder, repo, branch, PR state, why it was kept. Then git worktree prune in each repo.`

---

## Round 1: run in parallel now

Every lane is in a different repo. R1-6 and R1-7 wait only on the Round 0 merges.

| ID | Open in | Session | Model | Effort |
|---|---|---|---|---|
| R1-1 | `aegis-pricing` | Session 3: server health check + in-game price verification (**with you**) | Opus 5 | high |
| R1-1b | `claude-agents` | Chat and GUID live confirmation (claude-agents#14), **while you're in game for R1-1** | Sonnet 5 | medium |
| R1-2 | `aegis-site-chernarus` | Session 3: weapon nominals to §5b targets | Sonnet 5 | medium |
| R1-3 | `aegis-mods` | Research lane H0 (#9). If you have capacity, run H1–H5 (#10–#14) alongside it | Sonnet 5 | medium |
| R1-4 | `gh-federation` | Finish Session 3: deploy Worker + D1, then a live pull/ack test | Opus 5 | high |
| R1-5 | `claude-session-archive` | Session 5: `run.js` + gitleaks gate + publishing | Opus 5 | high |
| R1-6 | `aegis-core` | Session 3: secret-rotation procedure for what's left of #5 | Sonnet 5 | medium |
| R1-7 | `aegis-services` | Turn on economy automation (#58) | Sonnet 5 | medium |
| R1-8 | `handymansfield` | Session 2: invoicer agent | Opus 5 | high |
| R1-9 | `aegis-website` | Session 2: `/fund/` policy check | Sonnet 5 | low |
| R1-10 | `jarvis` *(optional)* | Session 2: backend abstraction (confirmed not built: no `src/backends/`) | Sonnet 5 | medium |

**R1-1: aegis-pricing, Opus 5 / high**
> `Read docs/PLAN.md Session 3 only. The module is already live on production, not a local test server: site-chernarus#67 re-added it and deploy-pricing ran with apply=true. The rollback snapshot is site-chernarus .sync-cache/rollback/20260914-053430/. Step 1: confirm the server came back clean after the panel restart — RCON login on port 20196 (not 2305), and no (E) lines or MARKET CONFIGURATION ERROR in the newest RPT. If it isn't clean, stop and tell me before doing anything else. Step 2: walk me through the Session 3 verification table in game, capturing menu price vs charged price with logTrades on, and fix what fails. Step 3: fix this plan's Status table (Sessions 0–2 merged as #1, #3, #4). Open one PR.`

**R1-1b: claude-agents, Sonnet 5 / medium** (start it at the same time as R1-1)
> `Read issue #14 only. I'm about to be in game on Chernarus for another session. Run .\scripts\RconKey.ps1 -Run owner-chat-reader and confirm the two unchecked items: the GUID formula (OWNER_ONLINE fires) and the chat-line format (OWNER_CHAT vs OWNER_UNPARSED). Tell me when to type a test message in chat. If the parser is wrong, fix packages/chat-ai/src/chatLine.js from the captured line, citing it in a comment per docs/PLAN.md Contracts. Tick the boxes on #14, fix the PLAN.md Status table (Session 1 #15 merged), and open one PR only if code changed. No draft-PR-per-chat-line test this time.`

**R1-2: site-chernarus, Sonnet 5 / medium**
> `Read docs/PLAN.md Session 3 only. Work in your own git worktree. Set weapon nominals to the §5b targets. Before that, correct the Status table: Session 0 is #53 (merged), Session 1 is #61 (merged), and Session 2 is superseded by the 2026-09-14 owner-decisions comment on #41 (Phase 2 met). Nothing here pushes to the server. One PR.`

**R1-3: aegis-mods, Sonnet 5 / medium** (one conversation per lane)
> `Read docs/PLAN.md "Clean-room rule" and "Research lanes" only. Run lane H0: post the hook map to issue #9 and label it hook-map-ready.`

For H1–H5, use the same prompt with `H1`/`#10`, `H2`/`#11`, `H3`/`#12`, `H4`/`#13`, `H5`/`#14`.

**R1-4: gh-federation, Opus 5 / high**
> `Read docs/PLAN.md Session 3 only. PR #5 merged, but its done-when bar isn't met because nothing is deployed. wrangler is already authenticated on this PC (wrangler whoami works). Create the D1 database, replace the database_id placeholder in wrangler.toml, apply the schema, and wrangler deploy — all on the free tier; stop and ask if anything would cost money. Then create a throwaway private test repo, add the template workflow, enqueue one task manually, and confirm it pulls and acks. If the auto-mode classifier blocks a command, tell me the exact command to approve rather than skipping it. Ask before deleting the test repo. Update the Status table with the Worker URL and open one PR.`

**R1-5: claude-session-archive, Opus 5 / high**
> `Read docs/PLAN.md Session 5 only. First mark Session 4 merged (#9) in the Status table. Build src/run.js and the CI/gitleaks config per the Target section, and upgrade the scheduled task to the full pipeline. Validate redaction by running --dry-run against the real ~/.claude/projects into the scratchpad before any live run.`

**R1-6: core, Sonnet 5 / medium** (after core#69 merges)
> `Read docs/PLAN.md Session 3 only, plus issue #5's last comment. The Anthropic key half is already done (nasdara-dev-key inactive, new key expires 2027-01-01) — record that, don't redo it. Make docs/ops/SECRET-ROTATION.md the complete procedure for what's left: DayZ join, BattlEye admin, VPPAdminTools passwords. Check each against live state or .clixml mtimes before calling it overdue. Add the checklist to #5's body. Fix the Status table (Session 2 #58 merged). One PR.`

**R1-7: services, Sonnet 5 / medium** (after services#71 merges)
> `Read issue #58 and the "Track: dayz_economy" status table in docs/PLAN.md only. #55 and #56 are closed — confirm their closing comments link green runs. Then ask me to approve setting ECONOMY_CATALOG_SYNC_ENABLED and ECONOMY_MONITOR_ENABLED to true, trigger one run of each workflow, and post both run links on #58. Alerting is a no-op without a Discord webhook, and Discord is parked — record that gap on #58 instead of creating a webhook. Open a PR only if a workflow needs fixing.`

**R1-8: handymansfield, Opus 5 / high**
> `Read docs/PLAN.md Session 2 only. First fix the Status table (Session 1 merged as #5). Ask me the two You questions if I haven't answered them. Build the invoicer agent, dry-run it against the last 3 Sheets invoices, and write nothing to QuickBooks or Gmail without my explicit yes. Open one PR.`

**R1-9: website, Sonnet 5 / low**
> `Read docs/PLAN.md Session 2 only. Verify /fund/ still matches the PayPal/no-perks donation policy after PRs #14 and #16, fix drift if any, and mark Session 1 as deployed live 2026-09-13 in the Status table. Open a PR.`

**R1-10: jarvis, Sonnet 5 / medium** (optional)
> `Read docs/PLAN.md Session 2 and its Contracts. Implement it, tests first.`

### Round 1 close-out: refresh the ledger (after Round 1's PRs merge)

| ID | Open in | Model | Effort |
|---|---|---|---|
| R1-Z | `MasterThread` | Sonnet 5 | medium |

> `Read docs/REPOS.md and standards/sessions/session_plan_standard.md only. Rebuild every Active row and the "Do first" table from live GitHub (gh pr list --state all, gh issue list) and each repo's docs/PLAN.md on origin — never a local checkout. Rows known to be stale: aegis-pricing, gh-federation, claude-agents, services, site-chernarus, core, handymansfield; "Do first" items 3 and 8 are done. Add a standing note that Discord work is parked as of 2026-09-14. One PR.`

---

## Round 2: after each lane's Round 1 PR merges

| ID | Open in | Session | Waits on | Model | Effort |
|---|---|---|---|---|---|
| R2-1 | `aegis-site-chernarus` | Session 4: launcher spellings, ammo sell rate, design-call list on #40 | R1-2 | Sonnet 5 | high |
| R2-2 | `aegis-mods` | Session 1: `AEGIS_Core` | H0 posted | Opus 5 | high |
| R2-3 | `aegis-pricing` | Session 4: standing label in trader menu | R1-1 | Sonnet 5 | medium |
| R2-4 | `claude-agents` | gh-federation Session 5: bug-report two-hop enqueue + WIF triage | R1-4, Round 0 #4 | Opus 5 | high |
| R2-5 | `aegis-core` | Session 4: `VENDORED-VALIDATOR.md` | R1-6 | Sonnet 5 | low |
| R2-6 | `claude-session-archive` | Session 6: backfill + verify | R1-5 | Sonnet 5 | medium |
| R2-7 | `handymansfield` | Session 3: payments reconciler | R1-8 | Sonnet 5 | high |
| R2-8 | `aegis-website` | Session 3: stale-docs pass | R1-9 | Sonnet 5 | low |
| R2-9 | `jarvis` *(optional)* | Session 3: Ollama backend + tool probe | R1-10 | Sonnet 5 | medium |

Prompts:
- **R2-1, R2-2, R2-3, R2-5, R2-6, R2-7, R2-8:** use the starter prompt from that session's section
  of the repo's `docs/PLAN.md`, as written.
- **R2-9:** the plan's starter prompt, plus: *"You: ollama pull what you propose."*
- **R2-4 is different.** The code goes in claude-agents, but the plan lives in gh-federation:

> `Read C:\Users\yoda_\GitHub\gh-federation\docs\PLAN.md Session 5 only. Work in claude-agents in your own worktree. The Worker is live at <URL from R1-4's Status table>. The WIF rule for claude-agents exists (ask me for the 4 identifiers — they're not secrets). Wire bug-report-agent's two-hop enqueue + WIF triage, open one PR in claude-agents, then a one-line Status-table PR in gh-federation.`

## Round 3: go-live prep and the next module sessions

| ID | Open in | Session | Waits on | Model | Effort |
|---|---|---|---|---|---|
| R3-1 | `aegis-site-chernarus` | Session 5: rarity ↔ price coherence in `HardlineSettings.json` | R2-1 | Opus 5 | high |
| R3-2 | `aegis-site-chernarus` | Write the Phase 3–4 go-live plan (Sessions 6+) | R3-1 | Opus 5 | high |
| R3-3 | `aegis-mods` | Session 2: `AEGIS_Skills` framework, Immunity, Medicine | R2-2, H1 | Opus 5 | high |
| R3-4 | `aegis-core` | Session 5: cut `v0.1.0` + a pin issue per consuming repo | R2-5 | Sonnet 5 | low |
| R3-5 | `aegis-poi` | Session 2: `AEGIS_POI` framework | nothing (fix Status table: S1 #4 merged; the standard amendment already landed in MasterThread#10) | Opus 5 | high |
| R3-6 | `aegis-pricing` | Session 5: Economy/services integration issues | R2-3 | Sonnet 5 | medium |
| R3-7 | `handymansfield` | Session 4: expenses | R2-7 | Sonnet 5 | medium |
| R3-8 | `aegis-services` | VPS V6 rebuild drill (**wipes the VPS; needs your yes**) | nothing | Sonnet 5 | high |

**R3-2: site-chernarus, Opus 5 / high.** This is the session that turns into real go-live.
> `Read docs/PLAN.md "After Session 5", docs/aegis-chernarus-golive-plan.md §3 Phases 3–4 and §5–6, and the 2026-09-14 owner-decisions comment on #41 only. Write Sessions 6+ into docs/PLAN.md, one PR, no server actions. It must cover: full server/ tree boot-tested on the local E: dev server with a clean log read; the AEGIS_Pricing live-test outcome from aegis-pricing Session 3 (keep or pull); removing @BallerZ_Teddys; @AEGIS_Metrics install (#48); the reputation wipe at go-live; snapshot → whole-tree push → one restart in a quiet window → nasdarasync verify → core.lock verified; the go-live announcement drafted for me to post by hand (Discord is parked); and the two-week §6 measurement. Mark which steps are my clicks, because the auto-mode classifier blocks live deploys and restarts.`

**Later, in order.** Each has its model already written in its plan.
- aegis-mods Sessions 3–15.
- aegis-poi Sessions 3–6.
- aegis-pricing Sessions 6–7. Session 7 needs a Workshop publisher account.
- handymansfield Session 5.
- jarvis Sessions 4–6.
- gh-federation Session 6, for non-Discord routed repos.

---

## Parked or blocked: don't open sessions for these

| What | Why | What unblocks it |
|---|---|---|
| claude-agents Sessions 2, 7, 8, 9; gh-federation Session 4; services admin-bot 1–3, V3 admin-bot half, V5, O7, EV3; jarvis Discord bring-up | **Discord parked** (owner, 2026-09-14) | You un-park Discord |
| claude-agents Session 3 (Patreon perks) | You use PayPal, not Patreon | Probably drop it. Confirm when Discord is un-parked |
| Stop the PC's `community-api` / `cloudflared-community-api` pm2 entries | Auto-mode classifier blocks it | Approve the command when a services session asks. It's a one-click approval, not a session |
| services O5 (player sessions) | Needs one `.ADM` sample with names removed | You share a sample |
| services nightly DB backups (#17 §4) | Needs an `age` key kept offline | You run `age-keygen` once. A session can walk you through it |
| vehicle-tracker Session 1 | FMC003 + SIM haven't arrived | Hardware |
| business-finance Session 1 | `receipts@handymansfield.com` mailbox doesn't exist | Namecheap panel |
| personal-finance Session 4 | No personal QuickBooks company | You create one |
| website `/fund/` real values | PayPal handle + funded-through date | You supply them |
| get-wired-solutions, family-support, personal-growth, 3d-printing, flightory-stork-vtol | No goal written | A one-paragraph goal from you |
| DayZServer | Superseded by site-chernarus | Archive it (your call; default is archive) |
