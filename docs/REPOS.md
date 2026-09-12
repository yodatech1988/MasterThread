# Repositories: the ledger

The single index of every repo, its session plan and its next session. Process:
[`standards/sessions/session_plan_standard.md`](../standards/sessions/session_plan_standard.md).
The PR that finishes a session updates that repo's row. Detail lives in each repo's
`docs/PLAN.md`, issues and PRs, not here.

For the AEGIS network, the cross-repo *work* map stays in core `docs/OUTSTANDING.md`. This page
tracks *plans and sessions*, and links there rather than duplicating it.

*(This page previously listed five planned repos that were never created. It was replaced with
the real inventory on 2026-09-12.)*

*(Audit note, 2026-09-12: verified against GitHub, these PRs named below as pending are merged —
core #35 #39 #41 #42 #43, services #10, website #16, repo-template #4, site-chernarus #43. Rows not
otherwise rewritten; the next session on each repo should refresh its row.)*

## Do first: cross-cutting

| # | Action | Where | Why |
|---|---|---|---|
| 1 | ~~Review and merge **core PR #43**, "Stop re-reviewing on every push; cap per-run spend"~~ — merged | core | In the 3 days to 2026-09-12, 82 Claude review runs across core (49), site-chernarus (25), services (5) and website (3). This is the largest avoidable API spend. |
| 2 | ~~Work down the **site-chernarus PR backlog** (15 open) before new sessions there~~ — 0 open as of the 2026-09-12 audit | site-chernarus | Standard rule 4: each unmerged PR makes later sessions pay to re-read and rebase. |
| 3 | Rotate the Anthropic key before it expires **2026-10-03** | core #5 | Owner-only; every Claude-backed agent and CI review stops otherwise. |
| 4 | ~~Create **aegis-mods**~~ (created 2026-09-12, private; PRs #1 AEGIS_Metrics and #2 AEGIS_TeddyBear merged) and import the remaining `P:\AEGIS_*` sources | aegis-mods | That mod source has no git history or backup. All future gameplay work ships as Workshop modules: [`standards/dayz/workshop_mod_standard.md`](../standards/dayz/workshop_mod_standard.md). |
| 5 | ~~Review and merge core PR #47 and site-chernarus PR #49~~ — both merged 2026-09-12 | core, site-chernarus | See "Standing decision" below for the canon change they landed. |

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
that was supposed to leave stubs in site-chernarus never fully took effect; `aegis-network-canon-bible.md`
there had already drifted from core's copy before this session touched anything, unrelated cleanup
still needed). `site-chernarus`'s canon bible, technical requirements, both site dossiers, the go-live
plan, the questlines doc, and the site-dossier template were all updated to match, in the same PR.

## Standing rule: always carry a live monetization plan

Monetization (`site-chernarus/docs/nasdara-monetization-plan.md`) is **paused, not abandoned**, and
the no-counter-value donations plan (`docs/DONATIONS_PLAN.md`, this repo) runs independently of that
pause. Jeremy's standing instruction (2026-09-12): keep a monetization plan current at all times, and
explicitly revisit it whenever a **new AEGIS site/map goes live** — Deer Isle (map two) is the next
trigger, currently only a lore/website placeholder with no repo yet. Concretely:

- Any new site repo's **Session 0** must read `nasdara-monetization-plan.md` and re-decide, in that
  repo's own `docs/PLAN.md`, whether donations and/or the paused tiered perks apply to it.
- Every site's go-live plan (modeled on site-chernarus's, currently at
  `_wt-chernarus-golive-plan/docs/aegis-chernarus-golive-plan.md`) should carry a Phase 4/5 line item:
  "Revisit `nasdara-monetization-plan.md` and `docs/DONATIONS_PLAN.md`; confirm Bohemia
  registration/renewal state before any paid perk goes live."
- Re-verify Bohemia's rules haven't changed and the approval-window deadline (Jan 31, 2027, if
  registration is ever completed) is still tracked, each time this is revisited.

**Progress (2026-09-12 evening):** Sessions 2 and 3 of `docs/DONATIONS_PLAN.md` are drafted and
in review — website PR #16 and services PR #10 (see their rows above). Both ship with `.tbc`
placeholders for the PayPal handle and the "funded through" date; only Jeremy can supply those
(plan §3) and the `#fund-the-server` channel/webhook. Session 1 (policy doc updates) and Session 4
(monthly routine) haven't been started.

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
| [jarvis](https://github.com/yodatech1988/jarvis) | Personal assistant | `docs/PLAN.md` (merged in PR #1) | Session 1: live-test `npm run cli` with the three prompts (PR #1 merged; blocked only on the key) | Paste `ANTHROPIC_API_KEY` into the local `.env` (already created); choose escalation consent (default `ask`) |
| [core](https://github.com/yodatech1988/core) | AEGIS shared tooling, canon, reusable CI | none | [PR #47](https://github.com/yodatech1988/core/pull/47) (map-parity canon rewrite) merged; next is [Session 0 (#44)](https://github.com/yodatech1988/core/issues/44) | Merge/close PRs #35 #39 #41 #42 #43 |
| [aegis-mods](https://github.com/yodatech1988/aegis-mods) | Every AEGIS gameplay module (Metrics and TeddyBear merged; Core, Skills, PvPGuard, Vehicles, Aircraft, Skins to come) | stub only | Session 0: write `docs/PLAN.md` from the standard's "Where existing work goes" table (PRs #1–#3 already landed `build.ps1`, `boot-test.ps1`, the public key and two modules). Session 1: import `P:\AEGIS_*` with junctions and migrate `AEGIS_PvPGuard` out of site-chernarus. The plan should account for packaging annual Theme Season mod bundles (see "Standing decision" above) once that's scoped | Write the one-paragraph goal in `docs/PLAN.md`; back up `AEGIS_Directive.biprivatekey` offline; confirm Workshop publisher account; delete `P:\AEGIS_HelloWorld` |
| [aegis-poi](https://github.com/yodatech1988/aegis-poi) | Prebuilt POI modules: `AEGIS_POI` framework, `_Trader`, `_BlackMarket`, `_Vault` | `docs/PLAN.md` (Session 0 merged in PR #1; API research merged in PRs #2, #3) | Session 1: `tools/check_module.py`, fixtures, CI that fails when it checks nothing | Signing key at `P:\Keys\AEGIS_Directive.biprivatekey` for Session 2 onward |
| [site-chernarus](https://github.com/yodatech1988/site-chernarus) | AEGIS Chernarus server config | none | [PR #49](https://github.com/yodatech1988/site-chernarus/pull/49) (map-parity doc updates) merged; next is [Session 0 (#44)](https://github.com/yodatech1988/site-chernarus/issues/44), whose first job is the 15-PR backlog | Production instance decision (#5); market sign-off (#6) |
| [services](https://github.com/yodatech1988/services) | admin-bot (the only live agent), RCON client | none | [Session 0 (#9)](https://github.com/yodatech1988/services/issues/9) | Review/merge [PR #10](https://github.com/yodatech1988/services/pull/10) (donations plan Session 3: `#fund-the-server` embed script); create that channel + webhook, `gh secret set DISCORD_WEBHOOK_FUND` |
| [claude-agents](https://github.com/yodatech1988/claude-agents) | Community, Patreon, chat and economy agents | none | [Session 0 (#5)](https://github.com/yodatech1988/claude-agents/issues/5) | — |
| [website](https://github.com/yodatech1988/website) | aegisdirective.net (never deployed) | none | [Session 0 (#15)](https://github.com/yodatech1988/website/issues/15) | Review/merge [PR #16](https://github.com/yodatech1988/website/pull/16) (donations plan Session 2: `/fund/` page); confirm PayPal Business account + `paypal.me` handle; Cloudflare connector auth when deploying (#3) |
| [MasterThread](https://github.com/yodatech1988/MasterThread) | This ledger and org standards | this page | Keep rows current. Standards refreshed 2026-09-12 evening (worktree, verify-before-merge, cost and rounds rules; two module homes; map parity). Issues #1 and #2 (2025 folder-structure and log-tailer notes) are still open and belong to the housekeeping lane; #3 was closed as obsolete | Close #1 and #2 or state what they still ask for |
| [repo-template](https://github.com/yodatech1988/repo-template) | Standard for new repos | n/a | Merge [PR #4](https://github.com/yodatech1988/repo-template/pull/4) (`CLAUDE.md` + `docs/PLAN.md` stubs) | — |

## Stable: no plan until work is planned

| Repo | Area | Note |
|---|---|---|
| [be-rcon](https://github.com/yodatech1988/be-rcon) | BattlEye RCON client (a submodule of services) | Changes arrive through services sessions. |
| [DayZServer](https://github.com/yodatech1988/DayZServer) | Earlier server config dump | Superseded by site-chernarus. Candidate to archive. |

## Scaffolds: repo-template files only, no goal written yet

Each needs a one-paragraph goal from the owner before a Session 0 is worth running. Until then,
opening a session there spends tokens without a target.

| Repo | Area |
|---|---|
| [get-wired-solutions](https://github.com/yodatech1988/get-wired-solutions) | Get Wired Solutions LLC operations |
| [handymansfield](https://github.com/yodatech1988/handymansfield) | HandyMansfield handyman business |
| [quickbooks-business](https://github.com/yodatech1988/quickbooks-business) | Business finance automation (no real data committed) |
| [quickbooks-family](https://github.com/yodatech1988/quickbooks-family) | Family finance automation (no real data committed) |
| [family-support](https://github.com/yodatech1988/family-support) | Family goals, checklists, resources |
| [personal-growth](https://github.com/yodatech1988/personal-growth) | Personal growth tracking |
| [3d-printing](https://github.com/yodatech1988/3d-printing) | Prints and slicer profiles |
| [flightory-stork-vtol](https://github.com/yodatech1988/flightory-stork-vtol) | Flightory Stork VTOL build |

## Dormant or archived: no sessions

| Repo | Note |
|---|---|
| [AEGIS-Directive](https://github.com/yodatech1988/AEGIS-Directive) | Archived; superseded by core and site repos. |
| [Business-development](https://github.com/yodatech1988/Business-development) | 2023 README, plus `game-server-email-and-paypal-setup.md` (contact email + PayPal + Bohemia contact setup, added 2026-09-12). |
| [Finance-business](https://github.com/yodatech1988/Finance-business) | Generated code, 2023. Superseded by quickbooks-business. |
| [Google-Cloud-AGI](https://github.com/yodatech1988/Google-Cloud-AGI) | Generated code, 2023. |
| [jeremybergerai](https://github.com/yodatech1988/jeremybergerai) | Demo app, 2023. |
| Smol-Dev | Local clone only, 2023. |

Local folders without a GitHub repo: `dayz-skin-library` (core PR #39 merged it into core as
staging; the Workshop mod standard sends it on to `aegis-mods` as `AEGIS_Skins` once each texture's
permission is checked), `dayz-vehicle-sources` (staged third-party assets), `TrulyFreeAssets_Various`
(someone else's fork).
