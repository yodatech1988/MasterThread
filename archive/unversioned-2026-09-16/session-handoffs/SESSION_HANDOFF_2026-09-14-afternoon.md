# Session handoff: 2026-09-14 afternoon (consolidated)

This is the single source of truth for the next orchestrator. It replaces every earlier handoff
today, including its own earlier drafts — don't read git history on this file, don't re-survey
GitHub, just start here.

## Read first

1. MasterThread `standards/sessions/orchestrator_role.md` (#39) — the orchestrator role: manage,
   don't implement; model/effort table; the round workflow.
2. `worker_role.md` + `researcher_role.md` (#40) — what a dispatched lane/research card follows.
3. `priority_classification.md` (#42) — the P0–P3 tiers used below.
4. `task_sizing.md` (#43) — the S/M/L/XL sizes used below; dispatch largest-first per tier on a
   fresh window.
5. Run `MasterThread\tools\usage-monitor\check-usage.ps1` before dispatching anything — **but see
   "Known tooling gap" below**, it currently reports no data in this harness.

Run the orchestrator itself on **Sonnet 5 / medium**.

---

## Where things stand right now

**The single biggest blocker: GitHub Actions billing is down**, org-wide. Every job on every repo
that hasn't moved to the VPS runner shows `runner_id: 0`, 0 ms — GitHub never assigns a runner. This
is not a code problem in any PR; don't debug individual "failing" checks without checking
`runner_id` first. Standing owner decision (2026-09-14): fix this by moving compute to the OVH VPS,
never by raising the GitHub spending limit or adding a payment method.

**The fix is built but stuck on merges only Jeremy can do** — see "Merge queue" below.

### Merged today (full list, chronological within each repo)

| Repo | Merged PRs |
|---|---|
| site-chernarus | #78 (orchestrator re-vendor), #80 (S4 economy defects), #81 (S5 rarity), #82 (go-live Sessions 6–17 plan), #83 (S17 pull guard), #84 (S6 local boot, 0/0/0), #85 (Krasnostav + Svetloyarsk safe zones removed) |
| aegis-mods | #21 + 11 research docs (#24 closed into #27; #29's Mining code parked on branch `agent/aegis-mods/mining-module-draft`), #34 (S3 Skills), #35 (S4 Stealth/Survival), #36 (S6 Medicine) |
| aegis-poi | #6 (research), #7 (S2 framework), #8 (S3 Trader) |
| core | #70 (S3) |
| services | #85 (docs), #87 (V10 credential/token expiry monitor — **not yet installed**, no SSH access this session) |
| website | #25 (connect widget — **not deployed**, needs `wrangler deploy`) |
| be-rcon | #4 (sequence-0 fix) |
| claude-agents | #20 (chat monitor reads Expansion's ExpLog over SFTP; RCON used only for the roster) |
| MasterThread | #38 (ledger), #39 (orchestrator role), #40 (worker/researcher roles), #41 (usage-monitor tool), #42 (priority classification), #43 (task sizing) |

Also live: `services` repo variable `ECONOMY_CATALOG_SYNC_ENABLED=true` (263 orphan rows
deactivated, not deleted). Live push to production Chernarus done at 14:02 server time: 7 files
from `f4a0b7b` (`HardlineSettings.json`, `SafeZoneSettings.json`, `nasdara_mmg_types.xml`, 3 Market
files, `Traders/Weapons_T3.json`); `dayz.json`/MiniMap deliberately held back. Restart verified
clean (0 Hardline errors, 0 MARKET CONFIGURATION ERROR, 0 script errors).

### Not merged — reviewed, ready, blocked on Jeremy

| PR | What it does | Why `gh` can't merge it |
|---|---|---|
| **core#74** | Self-hosted Actions runner + revert path, core's 3 workflows | Required checks stuck `QUEUED` (no runner ever assigned). `--admin` refuses to merge past a queued check at all — GitHub won't allow it regardless of permissions. |
| **services#86** | V7 (scheduled jobs → systemd timers) + V9 (self-hosted runner), services' 6 workflows, `ops/vps/` scripts | Same as core#74 — stuck `QUEUED`. |
| **site-chernarus#88** | Fish/meat/pelt sell-only, Gator tractor removed entirely, `expansionbus` removed from traders only, M4 SPR price diagnosis (no code fix) | Checks resolve to `FAILURE` (same `runner_id: 0` root cause), but here `--admin` is refused outright: `GraphQL: 2 of 2 required status checks are failing`. This repo's branch protection has no API-level bypass at all, even for a failing (not just queued) required check. |

**Note the inconsistency:** services#86/#87 both merged (#87 without even needing `--admin`), but
core and site-chernarus refuse every path. Branch protection strictness differs per repo; don't
assume one repo's merge behavior predicts another's.

**Merge order:** core#74 → services#86 → site-chernarus#88 (this last one unblocks the P2/XL
explosives-removal lane). **All three need Jeremy's click in the GitHub web UI.**

**After core#74 and services#86 merge:** try the actual VPS install from a **fresh** Claude Code
session (not this one — see "SSH permission" below for why). Once that succeeds, extract the
handoff script `C:\Users\yoda_\GitHub\AEGIS-Install-VPS-CI-Runner.cmd` and also run
services#87's install steps (`ops/vps/install-credential-check.sh` on the box, schedule
`tools\CredentialCheck.ps1` on the PC) — both were built this session with no SSH access available.

---

## Backlog, triaged (priority tier, then size — largest first per tier on a fresh window)

Re-check every row at the start of a round: a P1 blocker may already be cleared, or something may
have turned into a P0. Check `check-usage.ps1`'s remaining budget before starting an L/XL row.

| Tier | Size | Item | State | Next step |
|---|---|---|---|---|
| P1 | — | Merge queue (see above) | core#74, services#86, site-chernarus#88 all reviewed and ready | **Owner click**, web UI, in that order |
| P1 | S–M | Usage-monitor tool doesn't work in this harness | See "Known tooling gap" below | Test from a terminal CLI session; if it works there, the gap is VS-Code-specific |
| P2 | XL | site-chernarus: remove all explosives (Session 7) | Inventory done: `GitHub\SESSION7_EXPLOSIVES_INVENTORY_2026-09-14.md` — 20 classes across ~17 files, 7 ambiguous classes need an owner call | Waits on site-chernarus#88 merging first. Then: owner rules on the 7 ambiguous classes, edits, validators, local boot (out of game only), PR. History suggests a fix-reboot round is likely — **dispatch early in a fresh window** |
| P2 | L | aegis-poi: Session 4 (Black Market) bug bisect | Branch `agent/aegis-poi/session4-blackmarket` pushed, no PR. **Jeremy stopped this mid-work himself** | Bisecting an intermittent `RoundTrip()` crash in `AEGIS_POI_BlackMarket_TestHarness` — investigative, could run long. Local boot, out of game only. **Confirm with Jeremy before resuming** |
| P2 | L | aegis-mods: Session 5 (Hunting/Fishing) | Branch `agent/aegis-mods/session5-hunting-fishing`, no PR | Local boot-test (out of game only), open PR. Check whether the `AEGIS_Skills` panel bug (next row) got fixed first |
| P2 | M | site-chernarus **#87 — COT admin tool** (not the merged services#87 above; different repo, same number) | Draft PR, off-plan, opened by the aegis-pricing session | **Owner:** confirm Workshop ID 1564026768 (Community Online Tools) is still subscribable, and whether it's wanted alongside VPPAdminTools, before merge |
| P2 | S | aegis-mods: `AEGIS_Skills` panel bug | Not fixed as of last check | `ActionAegisSkillsPanel` is never registered in `ActionConstructor`/`PlayerBase.SetActions`, so the in-game panel can't open. Narrow, local-boot-testable |
| P2 | S | aegis-pricing: Session 3 in-game verification | Master fixed, tagged `v0.1.0` (done). Verification table not recorded | Needs Jeremy in game with the chat monitor running — a handful of interactive steps |
| P3 | L | claude-agents: headless chat-triggered Claude Code | chat-ai reads Expansion's ExpLog (#20, done); owner-chat-reader running | **Owner decision, security-relevant, before any build.** Don't dispatch until Jeremy decides |
| P3 | M | chat-ai `!ask`/`!link` still on RCON chat | Broken — RCON never carries chat on this server | Move onto the same `expansionChat.js` log source claude-agents#20 built. Low urgency |
| P3 | S | core: `#login` password unmasked in Expansion's log | Found, not fixed | Rotate the BE admin password after go-live (core `docs/ops/SECRET-ROTATION.md` §10 already covers this); fold into the next rotation pass |

### Done this round, nothing further needed

- **Token-efficiency audit** (P1, was size L) — complete, saved to
  `GitHub\TOKEN_EFFICIENCY_AUDIT_2026-09-14.md`. Two real findings worth acting on:
  1. Every PR review across 9 repos defaults to Opus/high with no size gate (`core`'s shared
     `claude-review.yml`) — the actual mechanism behind the known "82 reviews in 3 days" pattern.
  2. A genuine bug: `pr-review.yml` re-reviews on *any* label add, not just the intended one —
     confirmed duplicate Opus runs on the same PR, 5 seconds and 21 minutes apart.
  Neither fix has been applied yet — that's new backlog, not yet tiered. Someone should turn these
  into a P1/P2 lane capping effort by PR size and fixing the label trigger.
- **VPS credential/token expiry monitor** (P1, was size TBD) — clarified as VPS-side credential
  monitoring (not Claude usage) and built as services#87, merged. Not installed (no SSH access).

---

## Known tooling gap: usage-monitor doesn't work in this harness

`MasterThread\tools\usage-monitor\check-usage.ps1` has reported "No usage data yet" all day, in both
the original session and a fresh post-reset session. `%APPDATA%\AEGIS\claude-usage-state.json` has
never been written by a real session — confirmed by checking this session's own transcript for a
real `rate_limits` field (only synthetic test data from building the tool exists, and that was
deleted during cleanup before the `statusLine` setting was even wired in). This session runs in the
VS Code extension harness; it likely doesn't invoke a configured `statusLine` command the way the
terminal CLI does. **Test from a terminal CLI session to isolate whether this is harness-specific**
before relying on this tool for the orchestrator's Cost rule. Until then, ask Jeremy for the number
directly (he can read `/usage` or claude.ai's usage settings) rather than assuming the tool works.

---

## Owner decisions needed

1. **GitHub Actions billing / merge queue** — three web-UI clicks (see above). Not a decision, just
   action only Jeremy can take.
2. **Explosives (P2):** the 7 ambiguous classes — chemical gas/teargas grenades, bear/tripwire
   traps, smoke rounds left with no launcher, decorative props, AI War Zones explosion effects, the
   inactive raid whitelist.
3. **6 missing mods on the E: dev server?** (RedFalcon Heliz, Blackouts ATM, SimpleTraderSigns, MMG,
   Paragon, MiniMap Relocated — Session 6 borrowed the Steam Workshop copies to boot-test.)
4. **`AEGIS_Pricing` settings file isn't in git**; live runs the placeholder curve (1000→95/103,
   2500→90/106). Keep or set real values?
5. **site-chernarus#87, COT admin tool** — wanted alongside VPPAdminTools? Still subscribable?
6. **Headless chat-triggered Claude Code (P3)** — full tool access, a restricted set, or don't
   build it? Security-relevant; don't dispatch without an answer.
7. **New from the token-efficiency audit** — approve capping PR-review effort by size and fixing
   the label-trigger bug? (Not blocking anything, just needs a yes to become a lane.)

---

## Standing rules learned today

- **Never start a local DayZServer while Jeremy is in game.** It kicks his client. Check
  `Get-Process *DayZ*` (`DayZ_x64`/`DayZ_BE` running = he's in game) before any local boot test.
- **Chat monitor:** `claude-agents\scripts\RconKey.ps1 -Run owner-chat-reader`. Reads Expansion's
  server-side chat log over SFTP (BattlEye RCON never carries chat on this server) and prints
  `OWNER_CHAT` about 10 s after each message.
- **Worktrees:** pre-create with `GitHub\New-ParallelWorktrees.ps1 -Repo <folder> -Slugs <slug>`.
  Never let a lane pick its own folder.
- **Review before merge, always** — `aegis-mods` and `aegis-poi` have no Claude review; the
  orchestrator is the only reviewer there. For everywhere else, check `runner_id` on a "failing"
  check before assuming it's a real bug (see the billing block above).
- **Merging past a broken required check:** behavior is inconsistent per repo (`services` allows
  `--admin` or even a plain merge through; `core`/`site-chernarus` refuse both `QUEUED` and
  `FAILURE` required checks via any API path). Don't assume one repo's outcome predicts another's —
  check `mergeable` and try plain merge, then `--admin`, before concluding it needs the web UI.
- **Usage:** run `check-usage.ps1` before and during a round, but see the known gap above. Past
  ~80%, issue the pause order per tier (P0/P1 finish their step, P2/P3 stop immediately) —
  `priority_classification.md`. Session-only `CronCreate` reminders die if the session closes before
  firing; don't rely on one alone to resume work.
- **github-44** (one of an earlier round's parallel sessions) went unreachable when a pause order
  went out; if it's ever relevant again, check whether it's still running before starting a new lane
  in whatever repo it was working.
