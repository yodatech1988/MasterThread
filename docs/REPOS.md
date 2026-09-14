# Repositories: the ledger

The single index of every repo, its session plan and its next session. Process:
[`standards/sessions/session_plan_standard.md`](../standards/sessions/session_plan_standard.md).
The PR that finishes a session updates that repo's row. Detail lives in each repo's
`docs/PLAN.md`, issues and PRs, not here.

For the AEGIS network, the cross-repo *work* map stays in core `docs/OUTSTANDING.md`. This page
tracks *plans and sessions*, and links there rather than duplicating it.

*(This page previously listed five planned repos that were never created. It was replaced with
the real inventory on 2026-09-12.)*

*(Refreshed 2026-09-14 ~12:25 UTC against live GitHub — `gh pr list`/`gh issue list`/`gh variable
list` per repo plus each repo's `docs/PLAN.md` on `origin`, never a local checkout. Other sessions
were merging PRs at the same moment; this is a snapshot as of the timestamp above, not a
guarantee nothing has moved since. Current work queue: `GitHub\SESSION_ROUNDS_2026-09-14c.md`,
which supersedes and replaces `SESSION_ROUNDS_2026-09-14b.md` for all DayZ-network work.)*

**Discord work is parked (standing, since 2026-09-14).** claude-agents Sessions 2/7/8/9,
gh-federation Session 4, admin-bot, the OVH VPS V3 admin half, V5 and services EV3 all wait on
Jeremy lifting that pause — don't start them unasked. This is separate from gh-federation's
Session 5 (two-hop WIF triage), which is parked for its own reason (needs one-time Anthropic
Console Workload Identity Federation setup, not DayZ-critical).

## Do first: cross-cutting

| # | Action | Where | Why |
|---|---|---|---|
| 1 | ~~Review and merge **core PR #43**, "Stop re-reviewing on every push; cap per-run spend"~~ — merged | core | In the 3 days to 2026-09-12, 82 Claude review runs across core (49), site-chernarus (25), services (5) and website (3). This is the largest avoidable API spend. |
| 2 | ~~Work down the **site-chernarus PR backlog** (15 open) before new sessions there~~ — 0 open as of the 2026-09-12 audit | site-chernarus | Standard rule 4: each unmerged PR makes later sessions pay to re-read and rebase. |
| 3 | ~~Rotate the Anthropic key before it expires 2026-10-03~~ — done 2026-09-13, `nasdara-dev-key` retired. core #70 (Session 3, merged 2026-09-14) turned the whole issue into a followable `docs/ops/SECRET-ROTATION.md` procedure with an expiry table | core #5, core #70 | Was the largest single point of failure (every Claude-backed agent and CI review stops on expiry); now a checklist, not a bare date. Issue #5 stays open for the VPPAdminTools/BattlEye-admin/DayZ-join rotations it also covers (see #9 below). |
| 4 | ~~Create **aegis-mods**~~ (created 2026-09-12) and its Session 0 plan. Now current: the clean-room replacement plan (#17, merged) has Sessions 1–3 merged — `AEGIS_Core` (#31), `AEGIS_Skills` framework/Immunity/Medicine (#33), `AEGIS_Skills` Metabolism/Athletics/Strength (#34, merged 2026-09-14). Session 4 (Stealth/Survival) is next. Still open: import the remaining `P:\AEGIS_*` sources | aegis-mods | That mod source has no git history or backup. All future gameplay work ships as Workshop modules: [`standards/dayz/workshop_mod_standard.md`](../standards/dayz/workshop_mod_standard.md). Note core #8: no `P:` drive is mounted on the current machine, so locating the source is a Jeremy step. |
| 5 | ~~Review and merge core PR #47 and site-chernarus PR #49~~ — both merged 2026-09-12 | core, site-chernarus | See "Standing decision" below for the canon change they landed. |
| 6 | ~~Review and merge **claude-agents PR #7** and **PR #8**~~ — both merged long ago; the repo is up to PR #19 as of 2026-09-14 | claude-agents | This line hadn't been refreshed since 2026-09-12 despite fourteen more merged PRs. |
| 7 | ~~Deploy **website** with `wrangler deploy`~~ — done 2026-09-13, verified live (`/`, `/fund/`, `/sites/`, `/directive/` all return 200; `/fund/` was 404ing before) | website | Cloudflare was already authenticated (stored OAuth token); no further deploy work outstanding here. |
| 8 | Flip the `METRICS_DEPLOY_ENABLED` repo variable to `true` (confirmed still `false` as of this refresh), run the deploy-metrics workflow (dry-run, then apply), then run `nasdarasync restart` yourself watching the panel | site-chernarus #48 | site-chernarus #60 (the workflow itself) merged 2026-09-13, and all its SFTP/RCON variables and secrets are set. This flip-and-restart is now the only remaining step. |
| 9 | **Merge core PR #71** (Session 4, `docs/ops/VENDORED-VALIDATOR.md`) | core | All 3 checks are green (`test`, both `scan` runs); the only thing blocking merge is a stale `CHANGES_REQUESTED` review from before the current diff (standard rule 10 — verify the fix, then dismiss). Session 5 (`v0.1.0` tag) can't start until this merges. |
| 10 | Finish the 3 remaining **gateway** owner steps: add the ssh/wrangler allow rules to `~/.claude/settings.json`, run `PushEnqueueSecrets.ps1`, run `PushVpsSecrets.ps1 gateway`, then the DNS route | services (gateway track, #72–#84 all merged) | Every line of the routing gate is built and merged (services docs/PLAN.md gateway track); only these clicks are left. |
| 11 | Approve `ECONOMY_CATALOG_SYNC_ENABLED=true` (still `false` as of this refresh), trigger one run, confirm no orphan inserts | services #58, #74 | #74 fixed the orphan-row bug 2026-09-14, but no scheduled sync run has fired for real since. |
| 12 | Click "Import loot (baseline)" in `EconomyDbKey.ps1`, confirm PASS on all 7 files | services #78 (merged) | Unblocks the item-DB incorporation track (`NEXT_STEPS_ITEM_DB_INCORPORATION_2026-09-14.md`). |
| 13 | One shared in-game window: confirm the newest Chernarus RPT is clean, walk the `@AEGIS_Pricing` verification table (`logTrades: 1`), and confirm claude-agents #14's GUID-formula/chat-line-format questions | aegis-pricing Session 3, claude-agents #14 | Both need you in game and nothing else; running them together saves a second login. |
| 14 | Decide the `aegis-mods` draft-PR triage table posted on #21 (2026-09-14): merge/close/keep for 13 open research drafts (#18–#30) and `aegis-poi` #6 | aegis-mods #21 | 13 open drafts break the one-open-PR-per-repo rule and pile up rebase cost for every later session there. |

## Standing decision: map parity, no cross-map reputation gating

Jeremy's decision (2026-09-12): **every AEGIS site starts equal.** No map inherits a floor set by
another map's ceiling, and no site's reputation/standing gates whether a player can reach or compete
on any other site — reputation is local to the site it was earned on, always. This withdraws the old
"Chernarus T4 becomes map two's T2" tier-overlap model and the cross-server reputation store it would
have needed (which was never built and was a hard blocker on launching a second server — it no longer
is one).

In its place: an **annual Theme Season** rotates the mod bundle and fictional framing network-wide
(all sites at once), which is now where long-term content escalation lives instead of a later map
being harder to start. Season length, packaging (`aegis-mods`), and whether player state resets at a
season boundary are open questions, not yet decided.

Recorded in `core` `docs/canon/aegis-cross-map-progression.md` (canonical, [core#47](https://github.com/yodatech1988/core/pull/47))
and mirrored in `site-chernarus` `docs/aegis-cross-map-progression.md` ([site-chernarus#49](https://github.com/yodatech1988/site-chernarus/pull/49),
a stale full duplicate that should eventually become a pointer stub — the earlier canon migration
that was supposed to leave stubs in site-chernarus never fully took effect). core's own canon bible
and site-dossier template were synced to the decision in [core#49](https://github.com/yodatech1988/core/pull/49).
`site-chernarus`'s canon bible, technical requirements, both site dossiers, the go-live plan, the
questlines doc, and the site-dossier template were all updated to match in site-chernarus#49.

## Standing rule: always carry a live monetization plan

Monetization (`site-chernarus/docs/nasdara-monetization-plan.md`) is **paused, not abandoned**, and
the no-counter-value donations plan (`docs/DONATIONS_PLAN.md`, this repo) runs independently of that
pause. Jeremy's standing instruction (2026-09-12): keep a monetization plan current at all times, and
explicitly revisit it whenever a **new AEGIS site/map goes live** — Deer Isle (map two) is the next
trigger, currently only a lore/website placeholder with no repo yet; site-badlands (Nasdara Province,
ships Oct 15 2026) is the nearer trigger and its own Session 0 already re-decided this (see the
Active table). Concretely:

- Any new site repo's **Session 0** must read `nasdara-monetization-plan.md` and re-decide, in that
  repo's own `docs/PLAN.md`, whether donations and/or the paused tiered perks apply to it.
- Every site's go-live plan (modeled on site-chernarus's `docs/aegis-chernarus-golive-plan.md`)
  carries a Phase 5.6 line item: "Revisit `nasdara-monetization-plan.md` and `docs/DONATIONS_PLAN.md`;
  confirm Bohemia registration/renewal state before any paid perk goes live." (site-chernarus #46
  and #47, merged 2026-09-12.)
- Re-verify Bohemia's rules haven't changed and the approval-window deadline (Jan 31, 2027, if
  registration is ever completed) is still tracked, each time this is revisited.

**Progress (as of 2026-09-14):** Sessions 2 and 3 of `docs/DONATIONS_PLAN.md` are **merged** —
website PR #16 (`/fund/` page) and services PR #10 (`#fund-the-server` embed script). **website
Session 2 (re-verify `/fund/` still matches the policy) also merged, as #21 — no drift found.** Both
`/fund/` and the embed still ship with `.tbc` placeholders for the PayPal handle and the "funded
through" date; only Jeremy can supply those (plan §3) and the `#fund-the-server` channel/webhook.
Session 1 (policy doc updates in core and site-chernarus) and Session 4 (monthly routine, this repo)
haven't been started.

## Building rule: modules, not site edits

All AEGIS gameplay code is built as a Workshop module, per the
[Workshop mod standard](../standards/dayz/workshop_mod_standard.md): gameplay modules in
`aegis-mods`, prebuilt points of interest (`AEGIS_POI*`) in `aegis-poi` (owner decision 2026-09-12,
standard rule 1), reputation-based trader pricing (`AEGIS_Pricing*`) in `aegis-pricing` (owner
decision 2026-09-13, standard rule 1). Site repos only install modules (Workshop ID, version or
tag) and commit their
`settings.json` overrides. A site-repo PR that adds Enforce Script (`mods/`, mission `init.c` logic)
is redirected to the module repo. site-chernarus PR #43 (`AEGIS_PvPGuard`) merged before the rule
existed, so its code sits in the site repo until the migration in the standard's "Where existing
work goes" table happens.

## Active

| Repo | Area | Plan | Next session | Owner action |
|---|---|---|---|---|
| [jarvis](https://github.com/yodatech1988/jarvis) | Personal assistant | `docs/PLAN.md` (PR #1; #2 model fallback, #3 audit fixes merged). Grown a voice/surfaces roadmap since | Session 1 (live-test `npm run cli`, merge PR #1) is still the first blocking step — unchanged, still waiting on the key. Independently, Session 2 (backend abstraction, #13) and the voice/surfaces framework (Sessions 8–13: chat monitor #4, planning #5–#7, voice fixes #8, speaker verification #9, voice cloning #10–#11, iPhone/Shortcuts #12) are all merged, but each one's own *live* check (real Claude round-trip, Discord bot restart, a real iPhone Shortcut) is still owner-pending. Session 14 (SMS) waits on an explicit go-ahead — it's the one surface with a per-message cost | Paste `ANTHROPIC_API_KEY` into the local `.env` (already created); choose escalation consent (default `ask`). Discord creds were also never filled in (see `jarvis-never-started` note) — blocks Session 8's live Discord check too |
| [core](https://github.com/yodatech1988/core) | AEGIS shared tooling, canon, reusable CI | `docs/PLAN.md` ([#50](https://github.com/yodatech1988/core/pull/50), 5 sessions) | Sessions 1 (#57), 2 (#58) and 3 (#70, secret-rotation procedure) all merged. **Session 4 (#71, `VENDORED-VALIDATOR.md`) is open, checks green, blocked only on a stale `CHANGES_REQUESTED` review** — see Do-first #9. Session 5 (tag `v0.1.0`) is next after that | Merge #71. Then work `docs/ops/SECRET-ROTATION.md`'s remaining items from issue #5 (VPPAdminTools, BattlEye admin, DayZ join — the Anthropic key itself is already done). #7 RFFS folder name and #8 `P:\` source location are still yours |
| [aegis-mods](https://github.com/yodatech1988/aegis-mods) | Every AEGIS Workshop module: Metrics, TeddyBear, Economy, Skins merged. Clean-room replacement plan for the removed unsafe mod family (skills/perks, medicine, start screen) is merged ([#17](https://github.com/yodatech1988/aegis-mods/pull/17)) | `docs/PLAN.md` (Sessions 1–11 `AEGIS_Core`/`AEGIS_Skills`/`AEGIS_Medicine`/`AEGIS_StartScreen`; 12–15 move PvPGuard, Vehicles, Aircraft, Quest 1033). Hook maps H0–H5 (#9–#14) all `hook-map-ready`. Sessions merged: 1 `AEGIS_Core` (#31), 2 Skills framework/Immunity/Medicine (#33), 3 Skills Metabolism/Athletics/Strength (#34, 2026-09-14) | Session 4: Skills Stealth/Survival, next in sequence. Separately, a triage table for the 13 open research drafts (#18–#30) and `aegis-poi`#6 is now posted on #21 (2026-09-14) — see Do-first #14 | Decide the #21 triage table; faction-name mapping sign-off before Session 10; confirm the removed mod family's Workshop items are unsubscribed on Steam (local files deleted 2026-09-14, subscription status still unconfirmed); Workshop publisher account when a module is ready |
| [aegis-poi](https://github.com/yodatech1988/aegis-poi) | Prebuilt POI modules: `AEGIS_POI` framework, `_Trader`, `_BlackMarket`, `_Vault` | `docs/PLAN.md` ([#1](https://github.com/yodatech1988/aegis-poi/pull/1), 6 sessions). Session 1 (#4) merged. **Session 2, the `AEGIS_POI` framework on `AEGIS_Core`, merged as #7 (2026-09-14)** — automated done-when passed; tag `AEGIS_POI-v0.1.0` waits only on an in-game player-handling check (Do-first #13-adjacent) | Session 3 is in progress now (parallel lane, live as of this refresh) | Confirm DemoCamp placement/object handling in game, then tag `v0.1.0`. Workshop publishing defaults to *unpublished*. The MasterThread standard-amendment PR this repo owes (referencing MasterThread #7) is still not opened |
| [aegis-pricing](https://github.com/yodatech1988/aegis-pricing) | `AEGIS_Pricing`: Expansion Market buy/sell prices scale by Hardline reputation | `docs/PLAN.md` ([#1](https://github.com/yodatech1988/aegis-pricing/pull/1), 7 sessions). Sessions 1 (#3) and 2 (#4) merged — **module is live on production** (site-chernarus #67 re-enabled it there, production instance recorded, RCon port fixed) | Session 3 (in-game verification, tags v0.1.0/v0.2.0) is in progress now (parallel lane, live as of this refresh) | In-game verification window (Do-first #13); Workshop publisher account before go-live; site-chernarus market sign-off (#6) for the real curve numbers |
| [site-chernarus](https://github.com/yodatech1988/site-chernarus) | AEGIS Chernarus server config | `docs/PLAN.md` ([#53](https://github.com/yodatech1988/site-chernarus/pull/53), 5 sessions). Session 1 (#61) merged; Session 2 superseded (answered directly by the 2026-09-14 owner-decisions comment on #41); Session 3 weapon nominals (#69) merged; **Session 4 economy defects + golive-doc reconciliation (#80) merged 2026-09-14** | Session 5: rarity↔price coherence in `HardlineSettings.json`, not started. 18 off-plan PRs also merged 2026-09-14 (#62–#78, listed in the repo's own PLAN.md) — most notably **#78 re-vendors `restart_orchestrator.py` from core**, closing the swallowed-TransportError live-restart risk, and #77 adds MiniMap Relocated (merged, not yet deployed) | Market sign-off (#6); walk the MiniMap Workshop-folder confirmation + restart + `.bikey` check with the re-vendored orchestrator, then set `LOOT_DEPLOY_ENABLED=true` (unblocked now that #78 is merged); flip `METRICS_DEPLOY_ENABLED` (Do-first #8) |
| [site-badlands](https://github.com/yodatech1988/site-badlands) | Future AEGIS site on Nasdara Province (DayZ Badlands DLC, ships **Oct 15 2026**) | `docs/PLAN.md` ([#1](https://github.com/yodatech1988/site-badlands/pull/1), 3 sessions). Session 0 merged; hosting decision folded in as its own PR (#2, merged — second Shockbyte instance, subscribe closer to release); **Session 2, the mod-ecosystem Nasdara-readiness tracker, merged as #4 (2026-09-14)** | Session 1 is next and needs no owner input to start: register the 1.29 "Road to Badlands" preview items into the live economy as a **site-chernarus** PR. Session 3 (go-live sequencing) is blocked on the Oct 1–5 hosting window | Nothing blocking Session 1. Subscribe to the second Shockbyte instance in the Oct 1–5 window for Session 3 |
| [services](https://github.com/yodatech1988/services) | admin-bot; the three AEGIS databases (`docs/DATABASES.md`); `event-relay`; OVH VPS migration; the personal/financial/game-server routing gateway; `stats-api` | `docs/PLAN.md`, now six tracks. **OVH VPS V0–V4 merged and live** (#69–#71, security-hardened), `community-api` running on the VPS, admin-bot itself parked per #85. **Gateway track fully built and merged** (#72–#84: plan, classify/hold engine, port-collision fix, admin-bot wired in, `PushVpsSecrets.ps1`/`aegis-start.sh` wiring, the now-live gh-federation Worker wired up) — only 3 owner clicks remain. `dayz_economy`: #74 fixed orphan rows from the category rename; sync is still `false`; loot-baseline import button (#78) merged, unclicked. `dayz_ops`: O1–O4/O6 live. `dayz_community`: schema live. `stats-api` NS1 build: **on hold, owner said so 2026-09-14** | Do-first #10 (gateway clicks), #11 (economy sync), #12 (loot import) | Gateway: ssh/wrangler allow rules + `PushEnqueueSecrets.ps1` + `PushVpsSecrets.ps1 gateway` + DNS route. `ECONOMY_CATALOG_SYNC_ENABLED=true` approval. Loot-baseline import click. E5 (issue the Chernarus economy-api server token) is now unblocked by the VPS work and just needs doing. `dayz_ops` O5 still needs an `.ADM` sample |
| [claude-agents](https://github.com/yodatech1988/claude-agents) | Community, Patreon, chat and economy agents; Discord ticket system | `docs/PLAN.md` grew to 9 sessions. Its own Status table still marks Session 1 (#15) "in review" though **#15 merged 2026-09-13** — stale, needs a refresh. `bug-report-agent` (#16, merged) landed cleanly this time: the tooling that was reported stranded after the merge landed properly in its own follow-up PRs, **#18 `RconKey.ps1` and #19 `DiscordKey.ps1`, both merged 2026-09-14** | Session 7 (needs #12, already merged) is next, then 8, then 9. **Issue #14 (in-game chat-monitor live confirmation: GUID formula, chat-line format, `say` privacy) is open and being worked live right now** (parallel lane, as of this refresh) | Confirm #14's three open questions in game (Do-first #13). `bug-report-agent` deliberately holds no Anthropic key — parked pending `gh-federation` Session 5, not stalled |
| [gh-federation](https://github.com/yodatech1988/gh-federation) | Federated (OIDC-based) GitHub write access for bots, so no bot ever holds a static cross-repo PAT/key | `docs/PLAN.md` ([#1](https://github.com/yodatech1988/gh-federation/pull/1), 6 sessions). **All of Sessions 0–3 are merged**: plan amendment (#2), OIDC verification (#3), Worker+D1 schema (#4), pull-workflow template (#5), and **the Session 3 deploy (#6) — the Worker is live at `gh-federation.jeremybergerai.workers.dev`**, D1 created, the `gh-federation-selftest` repo's real pull+ack run passed. `PushEnqueueSecrets.ps1` (#7) also merged, rebuilding `ENQUEUE_SECRETS` from DPAPI | Session 4 (roll the pull workflow out to routed repos) is parked with Discord work; Session 5 (two-hop WIF triage for `bug-report-agent`) is parked separately, needing one-time Anthropic Console WIF setup | One-time Anthropic Console Workload Identity Federation setup for `claude-agents`, when ready to unpark Session 5. Decide whether to delete the throwaway `gh-federation-selftest` repo (if so, also drop its allow-list entry and redeploy) |
| [website](https://github.com/yodatech1988/website) | aegisdirective.net — **deployed and live** 2026-09-13 | `docs/PLAN.md` ([#18](https://github.com/yodatech1988/website/pull/18), now 6 sessions). Session 1 (#19) done. **Session 2 (#21, verify `/fund/` still matches PayPal/no-perks policy) done 2026-09-14 — no drift found.** Issue #3 (build.py rewrite + deploy) is closed. **Session 5 (server-connect widget on `start.html`) merged as #25 (2026-09-14)** | Session 3 not started. Session 4 (wire `/status/` to `stats-api`) stays blocked — `stats-api` NS1 is on hold. Session 6 (Survival-Handbook-style rules cards) not started | PayPal Business account + `paypal.me` handle; hosting funded-through date |
| [handymansfield](https://github.com/yodatech1988/handymansfield) | Agent back-office: job intake, invoicing, payments, expenses, month-end. Second line of business: Ohio HCV (HQS/NSPIRE) landlord inspections | `docs/PLAN.md` ([#3](https://github.com/yodatech1988/handymansfield/pull/3), 5 sessions). #5 Session 1 (framework + job-intake agent) and #7 (Ohio HCV target-list fix) merged. **The repo's own PLAN.md still says Session 2 is "in review" — stale: #9 (invoicer agent) merged 2026-09-14**, dry run 3/3 Sheets totals equal | Session 3 (payments) is next. First real invoice from Session 2's invoicer still waits on the owner naming the job | Name the first real job for the invoicer to bill. Ohio HCV line has no numbered sessions yet — call Mansfield Metropolitan Housing Authority (419-524-0029) first, ask about `ncohiohousing.org`; get biBERK insurance quotes (844-472-0967) |
| [vehicle-tracker](https://github.com/yodatech1988/vehicle-tracker) | OBD2 GPS ingestion (Teltonika FMC003 → Traccar → Worker/D1), geofence-based visit detection for HandyMansfield billing and a movement log for Jeremy's son | `docs/PLAN.md` (written directly to main, no PR — unchanged, still 0 open/merged PRs). Full pipeline built, deployed and validated end to end against a local Traccar stand-in | Session 1: swap the local Traccar/OsmAnd test setup for the real FMC003 once it and the SIM arrive, and move the Docker stack to the Pi 5 | Buy FMC003 + 1NCE SIM (long lead time, in progress); Pi 5 (dev is on a Pi 3B+ for now); `son_care` geofences wait on the autism-care payment arrangement |
| [business-finance](https://github.com/yodatech1988/business-finance) | HandyMansfield receipt/invoice routing into QuickBooks via IMAP polling | `docs/PLAN.md` ([#1](https://github.com/yodatech1988/business-finance/pull/1) plan, [#2](https://github.com/yodatech1988/business-finance/pull/2) IMAP revision — both merged, 4 sessions; unchanged, no new PRs) | Session 1: IMAP polling skeleton against `receipts@handymansfield.com`, once that mailbox exists | Create the `receipts@handymansfield.com` mailbox + app password in Namecheap Private Email; later, Intuit OAuth app registration (Session 3) |
| [personal-finance](https://github.com/yodatech1988/personal-finance) | Local-first personal/household finance automation — no cloud, no email/domain anywhere | `docs/PLAN.md` ([#1](https://github.com/yodatech1988/personal-finance/pull/1)–[#4](https://github.com/yodatech1988/personal-finance/pull/4), Sessions 1–3 all merged; unchanged, no new PRs) | Session 4 (QuickBooks write path) is next but blocked | Session 4 is blocked until you create a personal QuickBooks company |
| [claude-session-archive](https://github.com/yodatech1988/claude-session-archive) | Archives every Claude Code session transcript under `~/.claude/projects/` to this repo: redacted, full-text searchable (SQLite+FTS5), AI-summarized | `docs/PLAN.md` (6 sessions; Sessions 1–4 all merged). **Session 5 (`src/run.js` full pipeline: discover → backup → parse → redact → render → summarize → gitleaks gate → index → auto-merging PR) merged as #11 (2026-09-14)** — the repo's own PLAN.md still says "in progress," stale | Session 6: full backfill of every existing session under `~/.claude/projects`, spot-check rendered output, update this row | None currently blocking. Standing open decision: raw backups stay unencrypted plaintext in `%LOCALAPPDATA%\ClaudeSessionArchive\raw\`; revisit if the threat model changes |
| [MasterThread](https://github.com/yodatech1988/MasterThread) | This ledger and org standards | this page (this PR keeps it current) | Keep rows current every round. Recent: #34 documents aegis-pricing as a third Workshop-module home, #37 documents the orchestrated-parallel-lanes exception to rule 9 | — |
| [repo-template](https://github.com/yodatech1988/repo-template) | Standard for new repos | n/a — no goal written, so no `docs/PLAN.md` session plan applies here | Nothing pending: PRs #4 (`CLAUDE.md`/`docs/PLAN.md` stubs), #5 (`.gitignore`, protection script) and #6 (Claude PR review + auto-merge rollout) are all merged. See "Stable" below | — |

## Stable: no plan until work is planned

| Repo | Area | Note |
|---|---|---|
| [repo-template](https://github.com/yodatech1988/repo-template) | Standard for new repos | PRs #4 (`CLAUDE.md` + `docs/PLAN.md` stubs), #5 (.gitignore, protection script) and #6 (Claude PR review + auto-merge rollout) merged. |
| [be-rcon](https://github.com/yodatech1988/be-rcon) | BattlEye RCON client (a submodule of services) | Changes arrive through services sessions (#2 login-phase fix merged 2026-09-12). |
| [DayZServer](https://github.com/yodatech1988/DayZServer) | Earlier server config dump | Superseded by site-chernarus; its README now says it is not the live deploy source (#3, #4). Candidate to archive. |

## Scaffolds: repo-template files only, no goal written yet

Each needs a one-paragraph goal from the owner before a Session 0 is worth running. Until then,
opening a session there spends tokens without a target.

| Repo | Area |
|---|---|
| [get-wired-solutions](https://github.com/yodatech1988/get-wired-solutions) | Get Wired Solutions LLC operations |
| [family-support](https://github.com/yodatech1988/family-support) | Family goals, checklists, resources |
| [personal-growth](https://github.com/yodatech1988/personal-growth) | Personal growth tracking |
| [3d-printing](https://github.com/yodatech1988/3d-printing) | Prints and slicer profiles |
| [flightory-stork-vtol](https://github.com/yodatech1988/flightory-stork-vtol) | Flightory Stork VTOL build |

## Dormant or archived: no sessions

| Repo | Note |
|---|---|
| [AEGIS-Directive](https://github.com/yodatech1988/AEGIS-Directive) | Archived; superseded by core and site repos. **Still gets docs-only fixes despite being archived**: unarchived-then-rearchived twice on 2026-09-14 for #1 (scrub every reference to the removed unsafe mod family from its retired docs) and #2 (redact plaintext VPPAdminTools/BattlEye-admin/DayZ-join passwords that were committed in the clear — flagged by claude-agents#14 and never actioned until now). #2 only stops the plaintext *record*; the live credential values behind it still need rotating on the Shockbyte panel. |
| [Business-development](https://github.com/yodatech1988/Business-development) | 2023 README, plus `game-server-email-and-paypal-setup.md` (contact email + PayPal + Bohemia contact setup, added 2026-09-12). |
| [Finance-business](https://github.com/yodatech1988/Finance-business) | Generated code, 2023. Superseded by business-finance. |
| [quickbooks-business](https://github.com/yodatech1988/quickbooks-business) | Archived 2026-09-13; was an empty repo-template placeholder, never used. Superseded by business-finance. |
| [quickbooks-family](https://github.com/yodatech1988/quickbooks-family) | Archived 2026-09-13; was an empty repo-template placeholder, never used. Superseded by personal-finance. |
| [Google-Cloud-AGI](https://github.com/yodatech1988/Google-Cloud-AGI) | Generated code, 2023. |
| [jeremybergerai](https://github.com/yodatech1988/jeremybergerai) | Demo app, 2023. |
| Smol-Dev | Local clone only, 2023. |

Local folders without a GitHub repo: `dayz-vehicle-sources` (staged third-party assets) and
`TrulyFreeAssets_Various` (someone else's fork). `dayz-skin-library` is now in git as core
`assets/dayz-skin-library/` (core #39, merged 2026-09-12); the Workshop mod standard still expects a
shippable `AEGIS_Skins` module in `aegis-mods` once rule 9 is checked per texture.
