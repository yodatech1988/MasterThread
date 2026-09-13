# Repositories: the ledger

The single index of every repo, its session plan and its next session. Process:
[`standards/sessions/session_plan_standard.md`](../standards/sessions/session_plan_standard.md).
The PR that finishes a session updates that repo's row. Detail lives in each repo's
`docs/PLAN.md`, issues and PRs, not here.

For the AEGIS network, the cross-repo *work* map stays in core `docs/OUTSTANDING.md`. This page
tracks *plans and sessions*, and links there rather than duplicating it.

*(This page previously listed five planned repos that were never created. It was replaced with
the real inventory on 2026-09-12.)*

*(Refreshed 2026-09-12 ~22:10 UTC against GitHub. Every Round 1 "Session 0" plan is merged, so
each active row now points at its `docs/PLAN.md` and its next numbered session. The only open
agent PRs anywhere are claude-agents #7 and #8.)*

## Do first: cross-cutting

| # | Action | Where | Why |
|---|---|---|---|
| 1 | ~~Review and merge **core PR #43**, "Stop re-reviewing on every push; cap per-run spend"~~ — merged | core | In the 3 days to 2026-09-12, 82 Claude review runs across core (49), site-chernarus (25), services (5) and website (3). This is the largest avoidable API spend. |
| 2 | ~~Work down the **site-chernarus PR backlog** (15 open) before new sessions there~~ — 0 open as of the 2026-09-12 audit | site-chernarus | Standard rule 4: each unmerged PR makes later sessions pay to re-read and rebase. |
| 3 | Rotate the Anthropic key before it expires **2026-10-03** | core #5 | Owner-only; every Claude-backed agent and CI review stops otherwise. core Session 3 turns the issue into a written procedure, but the rotation itself stays with Jeremy. |
| 4 | ~~Create **aegis-mods**~~ (created 2026-09-12, private; PRs #1 AEGIS_Metrics, #2 AEGIS_TeddyBear, #3 audit fixes and #4 AEGIS_Economy merged) and ~~write its Session 0 `docs/PLAN.md`~~ (5 sessions queued: Skins, PvPGuard move, Vehicles, Aircraft, Quest 1033). Still open: import the remaining `P:\AEGIS_*` sources | aegis-mods | That mod source has no git history or backup. All future gameplay work ships as Workshop modules: [`standards/dayz/workshop_mod_standard.md`](../standards/dayz/workshop_mod_standard.md). Note core #8: no `P:` drive is mounted on the current machine, so locating the source is a Jeremy step. |
| 5 | ~~Review and merge core PR #47 and site-chernarus PR #49~~ — both merged 2026-09-12 | core, site-chernarus | See "Standing decision" below for the canon change they landed. |
| 6 | Review and merge **claude-agents PR #7** (audit fixes) and **PR #8** (ticket button + form) | claude-agents | The only open agent PRs in the org. Two at once breaks standard rule 4, so merge #7 first and rebase #8 on it before any Session 1 there. |
| 7 | Deploy **website** with `wrangler deploy` (Cloudflare connector auth, website #3) | website | Merging never deploys aegisdirective.net. `/fund/` (PR #16) and every fix since are live in git only; the site still 404s on `/fund/` as of 2026-09-12. |
| 8 | Upload `@AEGIS_Metrics` to production over SFTP and restart | site-chernarus #48 | site-chernarus PR #50 sets `serverMods` and keeps player data out of git; the zip is built (`GitHub\AEGIS_Metrics_server_upload.zip`). Only the upload and restart remain, and both need Jeremy's credentials. |

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
trigger, currently only a lore/website placeholder with no repo yet. Concretely:

- Any new site repo's **Session 0** must read `nasdara-monetization-plan.md` and re-decide, in that
  repo's own `docs/PLAN.md`, whether donations and/or the paused tiered perks apply to it.
- Every site's go-live plan (modeled on site-chernarus's `docs/aegis-chernarus-golive-plan.md`)
  carries a Phase 5.6 line item: "Revisit `nasdara-monetization-plan.md` and `docs/DONATIONS_PLAN.md`;
  confirm Bohemia registration/renewal state before any paid perk goes live." (site-chernarus #46
  and #47, merged 2026-09-12.)
- Re-verify Bohemia's rules haven't changed and the approval-window deadline (Jan 31, 2027, if
  registration is ever completed) is still tracked, each time this is revisited.

**Progress (2026-09-12 late):** Sessions 2 and 3 of `docs/DONATIONS_PLAN.md` are **merged** —
website PR #16 (`/fund/` page) and services PR #10 (`#fund-the-server` embed script). Both ship
with `.tbc` placeholders for the PayPal handle and the "funded through" date; only Jeremy can supply
those (plan §3) and the `#fund-the-server` channel/webhook. Session 1 (policy doc updates in core and
site-chernarus) and Session 4 (monthly routine, this repo) haven't been started. website Session 2
re-verifies `/fund/` once real values exist.

## Building rule: modules, not site edits

All AEGIS gameplay code is built as a Workshop module, per the
[Workshop mod standard](../standards/dayz/workshop_mod_standard.md): gameplay modules in
`aegis-mods`, prebuilt points of interest (`AEGIS_POI*`) in `aegis-poi` (owner decision 2026-09-12,
standard rule 1). Site repos only install modules (Workshop ID, version or tag) and commit their
`settings.json` overrides. A site-repo PR that adds Enforce Script (`mods/`, mission `init.c` logic)
is redirected to the module repo. site-chernarus PR #43 (`AEGIS_PvPGuard`) merged before the rule
existed, so its code sits in the site repo until the migration in the standard's "Where existing
work goes" table happens.

## Active

| Repo | Area | Plan | Next session | Owner action |
|---|---|---|---|---|
| [jarvis](https://github.com/yodatech1988/jarvis) | Personal assistant | `docs/PLAN.md` (PR #1; #2 model fallback and #3 audit fixes also merged) | Session 1: live-test `npm run cli` with the three prompts. Blocked only on the key | Paste `ANTHROPIC_API_KEY` into the local `.env` (already created); choose escalation consent (default `ask`) |
| [core](https://github.com/yodatech1988/core) | AEGIS shared tooling, canon, reusable CI | `docs/PLAN.md` ([#50](https://github.com/yodatech1988/core/pull/50), 5 sessions) | Session 1: tell the truth about the review pipeline (workflow comments, how-to-read-the-check). #51 audit fixes merged after the plan | Rotate the key (#5; becomes a procedure in Session 3). #7 RFFS folder name and #8 `P:\` source location are still yours |
| [aegis-mods](https://github.com/yodatech1988/aegis-mods) | Every AEGIS Workshop module: Metrics, TeddyBear, Economy live/merged | `docs/PLAN.md` (5 sessions: Skins, move PvPGuard, Vehicles, Aircraft, Quest 1033 "Contraband Run") | Backlog: merge or close PR #5 (Economy trader buy/sell bridge) first. Then Session 1: build `AEGIS_Skins` | Confirm Workshop publisher account when a module is ready to publish |
| [aegis-poi](https://github.com/yodatech1988/aegis-poi) | Prebuilt POI modules: `AEGIS_POI` framework, `_Trader`, `_BlackMarket`, `_Vault` | `docs/PLAN.md` ([#1](https://github.com/yodatech1988/aegis-poi/pull/1), 6 sessions; #2 API research and #3 audit fixes merged) | Session 1: repo tooling and CI that actually checks (`check_module.py` + prefab/settings schema) | Workshop publishing defaults to *unpublished*; confirm or override. Economy numbers wait on site-chernarus #6 |
| [site-chernarus](https://github.com/yodatech1988/site-chernarus) | AEGIS Chernarus server config | `docs/PLAN.md` ([#53](https://github.com/yodatech1988/site-chernarus/pull/53), 5 sessions). `validate` now runs for real (#51); #54 audit fixes merged | Session 1: reconcile README/STATUS/go-live plan with the verified 2026-09-12 state. Session 2 then posts the Phase 2 decision brief on #41 | Production instance (#5); market sign-off (#6); the four Phase 2 answers on #41 (everything after Session 5 waits on them); SFTP upload + restart for `@AEGIS_Metrics` (#48) |
| [services](https://github.com/yodatech1988/services) | admin-bot (built, not deployed); the three AEGIS databases (`docs/DATABASES.md`); `event-relay` (built, not deployed) | `docs/PLAN.md` has four tracks. admin-bot: 3 sessions, none started (be-rcon's framing disagreement is still open — no live capture yet). `dayz_ops`: O1-O4 and O6 merged, live, password rotated, hourly heartbeat/alerts running. `dayz_economy`: `0001` live (#15). `dayz_community`: schema drafted, not yet built live (#16) | `dayz_ops` O5 (player sessions from `.ADM` logs) once a sample exists; `dayz_ops` O7 and `event-relay` both wait on the admin-bot VPS (Session 3) | admin-bot: create the Discord app + VPS. `dayz_ops` (#17): age key + economy/community DB passwords for backups, one `.ADM` sample. `dayz_economy` (#19) and `event-relay` (#33) have their own owner checklists |
| [claude-agents](https://github.com/yodatech1988/claude-agents) | Community, Patreon, chat and economy agents | `docs/PLAN.md` ([#6](https://github.com/yodatech1988/claude-agents/pull/6), 5 sessions) | Merge #7 then #8 first (rule 4). Then Session 1: live-confirmation checklist for chat-ai and economy-worker | Review/merge [#7](https://github.com/yodatech1988/claude-agents/pull/7) and [#8](https://github.com/yodatech1988/claude-agents/pull/8) |
| [website](https://github.com/yodatech1988/website) | aegisdirective.net (built, never deployed) | `docs/PLAN.md` ([#18](https://github.com/yodatech1988/website/pull/18), 3 sessions). Session 1 ([#19](https://github.com/yodatech1988/website/pull/19)) done | Session 2: verify `/fund/` still matches the PayPal/no-perks policy, once real values exist | `wrangler deploy` (Cloudflare auth, #3); PayPal Business account + `paypal.me` handle; hosting funded-through date |
| [handymansfield](https://github.com/yodatech1988/handymansfield) | Agent back-office: job intake, invoicing, payments, expenses, month-end | `docs/PLAN.md` ([#3](https://github.com/yodatech1988/handymansfield/pull/3), 5 sessions; goal drafted from Drive/Gmail/QuickBooks). #4 audit fixes merged | Session 1: framework and job intake (drafts only, no client data in git) | Confirm or edit the drafted goal paragraph in `docs/PLAN.md` |
| [vehicle-tracker](https://github.com/yodatech1988/vehicle-tracker) | OBD2 GPS ingestion (Teltonika FMC003 -> Traccar -> Worker/D1), geofence-based visit detection for HandyMansfield time-on-site billing and a movement log for Jeremy's son | `docs/PLAN.md` (written directly to main, no PR). Ingestion Worker, D1 schema, and 3 job-site geofences (from QBO addresses) are built, deployed and smoke-tested live | Session 1: first real device on the pipeline, once the FMC003 + SIM arrive and a Traccar host is chosen | Buy FMC003 + 1NCE SIM (in progress, long lead time); pick where Traccar runs (Oracle free-tier ARM VM is the default); `son_care` geofences wait on the autism-care payment arrangement |
| [business-finance](https://github.com/yodatech1988/business-finance) | HandyMansfield receipt/invoice routing into QuickBooks via IMAP polling (no DNS/Cloudflare — revised from the original Cloudflare Email Routing plan, which needed an Enterprise-only Cloudflare feature) | `docs/PLAN.md` ([#1](https://github.com/yodatech1988/business-finance/pull/1) plan, [#2](https://github.com/yodatech1988/business-finance/pull/2) IMAP revision — both merged, 4 sessions) | Session 1: IMAP polling skeleton against receipts@handymansfield.com, once that mailbox exists | Create the receipts@handymansfield.com mailbox + app password in Namecheap Private Email; later, Intuit OAuth app registration (Session 3) |
| [personal-finance](https://github.com/yodatech1988/personal-finance) | Local-first personal/household finance automation — no cloud, no email/domain anywhere, encrypted at rest and in transit | `docs/PLAN.md` ([#1](https://github.com/yodatech1988/personal-finance/pull/1) plan, [#2](https://github.com/yodatech1988/personal-finance/pull/2) Session 1, [#3](https://github.com/yodatech1988/personal-finance/pull/3) Session 2, [#4](https://github.com/yodatech1988/personal-finance/pull/4) Session 3 — all merged, 4 sessions total) | Sessions 1-3 done (local `age`-encrypted vault, one-file ingestion, and a local folder-watcher — owner decided against any email-based intake, which also dropped the domain prerequisite entirely). Session 4 is next but blocked | Session 4 is blocked until you create a personal QuickBooks company |
| [MasterThread](https://github.com/yodatech1988/MasterThread) | This ledger and org standards | this page | Keep rows current. Donations plan Session 4 (monthly routine checklist) lives here and is not started. Issues #1 and #2 (2025-11 sketches for log-tailer agents and a Discord bot layout, superseded by services and claude-agents) closed 2026-09-12 | — |
| [repo-template](https://github.com/yodatech1988/repo-template) | Standard for new repos | n/a | Merge [PR #4](https://github.com/yodatech1988/repo-template/pull/4) (`CLAUDE.md` + `docs/PLAN.md` stubs) | — |
| [get-wired-solutions](https://github.com/yodatech1988/get-wired-solutions) | Get Wired Solutions LLC operations. First line of business: Ohio HCV (HQS/NSPIRE) landlord inspection service, contracted through PHAs | `docs/PLAN.md` ([#3](https://github.com/yodatech1988/get-wired-solutions/pull/3), Session 0 done pending merge; Sessions 1-2 queued) | Merge #3, then Session 1: close the two insurance gaps found reviewing the COI (owned-auto liability, Professional Liability/E&O — both currently unpriced) | Call biBERK (844-472-0967) for the two insurance quotes; call CMHA Cincinnati (513-721-4580) before the RFP 2026-2002 question deadline 2026-02-18; identify small Ohio county PHA targets by direct call (small-panel scope, not high-volume) |

## Stable: no plan until work is planned

| Repo | Area | Note |
|---|---|---|
| [repo-template](https://github.com/yodatech1988/repo-template) | Standard for new repos | PRs #4 (`CLAUDE.md` + `docs/PLAN.md` stubs) and #5 (.gitignore, protection script) merged 2026-09-12. |
| [be-rcon](https://github.com/yodatech1988/be-rcon) | BattlEye RCON client (a submodule of services) | Changes arrive through services sessions (#2 login-phase fix merged 2026-09-12). |
| [DayZServer](https://github.com/yodatech1988/DayZServer) | Earlier server config dump | Superseded by site-chernarus; its README now says it is not the live deploy source (#3, #4). Candidate to archive. |

## Scaffolds: repo-template files only, no goal written yet

Each needs a one-paragraph goal from the owner before a Session 0 is worth running. Until then,
opening a session there spends tokens without a target.

| Repo | Area |
|---|---|
| [family-support](https://github.com/yodatech1988/family-support) | Family goals, checklists, resources |
| [personal-growth](https://github.com/yodatech1988/personal-growth) | Personal growth tracking |
| [3d-printing](https://github.com/yodatech1988/3d-printing) | Prints and slicer profiles |
| [flightory-stork-vtol](https://github.com/yodatech1988/flightory-stork-vtol) | Flightory Stork VTOL build |

## Dormant or archived: no sessions

| Repo | Note |
|---|---|
| [AEGIS-Directive](https://github.com/yodatech1988/AEGIS-Directive) | Archived; superseded by core and site repos. |
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
