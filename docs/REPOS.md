# Repositories: the ledger

The single index of every repo, its session plan and its next session. Process:
[`standards/sessions/session_plan_standard.md`](../standards/sessions/session_plan_standard.md).
The PR that finishes a session updates that repo's row. Detail lives in each repo's
`docs/PLAN.md`, issues and PRs, not here.

For the AEGIS network, the cross-repo *work* map stays in core `docs/OUTSTANDING.md`. This page
tracks *plans and sessions*, and links there rather than duplicating it.

*(This page previously listed five planned repos that were never created. It was replaced with
the real inventory on 2026-09-12.)*

## Do first: cross-cutting

| # | Action | Where | Why |
|---|---|---|---|
| 1 | Review and merge **core PR #43**, "Stop re-reviewing on every push; cap per-run spend" | core | In the 3 days to 2026-09-12, 82 Claude review runs across core (49), site-chernarus (25), services (5) and website (3). This is the largest avoidable API spend. |
| 2 | Work down the **site-chernarus PR backlog** (15 open) before new sessions there | site-chernarus | Standard rule 4: each unmerged PR makes later sessions pay to re-read and rebase. |
| 3 | Rotate the Anthropic key before it expires **2026-10-03** | core #5 | Owner-only; every Claude-backed agent and CI review stops otherwise. |
| 4 | Create **aegis-mods** and import the `P:\AEGIS_*` sources (Session 1 of its plan) | aegis-mods | That mod source has no git history or backup. All future gameplay work ships as Workshop modules: [`standards/dayz/workshop_mod_standard.md`](../standards/dayz/workshop_mod_standard.md). |
| 5 | Review and merge **core PR #47** and **site-chernarus PR #49**, the map-parity canon change | core, site-chernarus | See "Standing decision" below. Both are Session-0-adjacent — merge before, or fold into, each repo's Session 0. |

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

## Building rule: modules, not site edits

All AEGIS gameplay code is built as a Workshop module in `aegis-mods`, per the
[Workshop mod standard](../standards/dayz/workshop_mod_standard.md). Site repos only install modules
(Workshop ID + version) and commit their `settings.json` overrides. A site-repo PR that adds Enforce
Script (`mods/`, mission `init.c` logic) is redirected to `aegis-mods`. site-chernarus PR #43
(`AEGIS_PvPGuard`) is the first such PR.

## Active

| Repo | Area | Plan | Next session | Owner action |
|---|---|---|---|---|
| [jarvis](https://github.com/yodatech1988/jarvis) | Personal assistant | `docs/PLAN.md` (PR #1) | Session 1: live-test and merge PR #1 (tests and CI green; blocked only on the key) | Paste `ANTHROPIC_API_KEY` into the local `.env` (already created); choose escalation consent (default `ask`) |
| [core](https://github.com/yodatech1988/core) | AEGIS shared tooling, canon, reusable CI | none | Merge [PR #47](https://github.com/yodatech1988/core/pull/47) (map-parity canon rewrite) first; then [Session 0 (#44)](https://github.com/yodatech1988/core/issues/44) | Merge/close PRs #35 #39 #41 #42 #43 #47 |
| aegis-mods *(to create)* | Every AEGIS Workshop module: Core, Skills, PvPGuard, Vehicles, Aircraft, Skins | none | Session 0: create repo, write `docs/PLAN.md` from the standard's "Where existing work goes" table. Session 1: import `P:\AEGIS_*` with junctions, `build.ps1`, HelloWorld boot test. Its plan should account for packaging annual Theme Season mod bundles (see "Standing decision" above) once that's scoped | Generate and back up the `AEGIS` signing key; confirm Workshop publisher account |
| [site-chernarus](https://github.com/yodatech1988/site-chernarus) | AEGIS Chernarus server config | none | Merge [PR #49](https://github.com/yodatech1988/site-chernarus/pull/49) (map-parity doc updates) first; then [Session 0 (#44)](https://github.com/yodatech1988/site-chernarus/issues/44), whose first job is the 15-PR backlog | Production instance decision (#5); market sign-off (#6) |
| [services](https://github.com/yodatech1988/services) | admin-bot (the only live agent), RCON client | none | [Session 0 (#9)](https://github.com/yodatech1988/services/issues/9) | — |
| [claude-agents](https://github.com/yodatech1988/claude-agents) | Community, Patreon, chat and economy agents | none | [Session 0 (#5)](https://github.com/yodatech1988/claude-agents/issues/5) | — |
| [website](https://github.com/yodatech1988/website) | aegisdirective.net (never deployed) | none | [Session 0 (#15)](https://github.com/yodatech1988/website/issues/15) | Cloudflare connector auth when deploying (#3) |
| [MasterThread](https://github.com/yodatech1988/MasterThread) | This ledger and org standards | this page | Keep rows current. No open issues (#3, a 2023 env-var list for AutoGPT/DayZ automation, was closed as obsolete: nothing uses those vars, and each repo's `.env.example` is the source) | — |
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
| [Business-development](https://github.com/yodatech1988/Business-development) | README only, 2023. |
| [Finance-business](https://github.com/yodatech1988/Finance-business) | Generated code, 2023. Superseded by quickbooks-business. |
| [Google-Cloud-AGI](https://github.com/yodatech1988/Google-Cloud-AGI) | Generated code, 2023. |
| [jeremybergerai](https://github.com/yodatech1988/jeremybergerai) | Demo app, 2023. |
| Smol-Dev | Local clone only, 2023. |

Local folders without a GitHub repo: `dayz-skin-library` (core PR #39 proposes moving it into
core; the Workshop mod standard sends it to `aegis-mods` as `AEGIS_Skins` instead), `dayz-vehicle-sources` (staged third-party assets), `TrulyFreeAssets_Various` (someone
else's fork).
