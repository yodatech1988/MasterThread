# Session handoff — 2026-09-14 evening (live in-game session)

This session ran while Jeremy played Chernarus live, fixing reported issues in real time and
pushing/restarting between play sessions. Read this before continuing; it replaces re-surveying.

## What's live on the server right now

Boot confirmed clean after the last restart (0 market errors, `@BallerZ_Teddys` gone,
`@AEGIS_Pricing` active, selftest 28/28):

- Junk market item `(158 individual parts)` removed from Vehicle_Parts + 5 trader stock files.
- `@BallerZ_Teddys` removed from the mod list (cut in #32, never actually removed from live).
- Weapon nominals set to the plan's §5b targets (site-chernarus#69).
- All 5 trader outposts got their missing building files — this was why traders looked like they
  were floating (site-chernarus#70). Buildings come only from mission `.map` files under
  `expansion/objects/`; that folder was empty on live and had never been in git either.
- Ammo/magazine/attachment trader categories relabeled by weapon family (site-chernarus#71).
- Map markers rebuilt from the real trader layout; admin teleport list matches (site-chernarus#72).
- Tisy/Tier4 military loot: two tagging bugs fixed — police items had been tagged Military, and
  every modded magazine was tagged Tier4 regardless of its actual gun (site-chernarus#73).
- Tisy loot slot oversubscription relieved: rolled back #19's 2.5× multiplier on 32 non-gun
  entries (ammo/mags/optics, not guns — those stay at #69's targets); MMG and Paragon gear mods'
  own shipped loot config wired into `ce_nasdara` (they were installed but had zero loot entries,
  so their items could never spawn); big-caliber ammo/mags for guns nobody can loot cut from 20 to
  2 (site-chernarus#76).
- 52 market misfiles re-applied (site-chernarus#75) — these were fixed once already in #57/#59,
  then silently reverted by #66's live-state pull because live never actually got #59's push.
  **This is the second time this exact category of loss has happened** (see "watch for" below).
- `AEGIS_Core` (aegis-mods) built and merged (#31 + #32 follow-up). RPC ID **19420** (one engine ID,
  string sub-dispatch — clear of vanilla 0–180 and CF's 10042). Caught a real bug along the way:
  the draft RPC dispatch used `GameScript.CallFunctionParams` with a `ParamsReadContext` argument,
  which **crashes the engine with no `(E)` line at all** — `boot-test.ps1` was reporting a false
  `RESULT: STARTED` on a dead process. Fixed both the dispatch (now a typed virtual call) and
  `boot-test.ps1` (now fails if the process died or a `.mdmp` appeared). This protects every future
  module's boot test, not just Core's.

## New automation, not yet turned on

**site-chernarus#74**, merged: `.github/workflows/deploy-loot.yml`. Auto-pushes and restarts on any
merge touching `db/types.xml`, `ce_nasdara/**`, or `profiles/ExpansionMod/Market/**` — no more manual
`.cmd` clicks for loot/economy changes. Gated by repo variable `LOOT_DEPLOY_ENABLED` (currently
unset/false). **To turn on:** set that variable to `true`. No new secrets needed — it reuses
`SFTP_HOST/PORT/USER/REMOTE_ROOT`, `RCON_HOST/PORT`, `NASDARASYNC_SFTP_PASSWORD`,
`NASDARASYNC_RCON_PASSWORD`, already present from `deploy-metrics.yml`/`deploy-pricing.yml`.

**Known open question on it, Jeremy's call:** a push to `main` always applies for real once
enabled — there's no dry-run-by-default step. Merging a loot PR *is* the live push. If a second
manual-apply gate is wanted instead, that's a follow-up PR.

**Bug found twice tonight, now handled in the new workflow but NOT in my manual scratchpad
scripts:** the RCON `say`/`#shutdown` sequence dropped its connection mid-warning both times I ran
it by hand, leaving the server "warned but never restarted" until I noticed and finished the job
manually. `deploy-loot.yml`'s restart logic (via `sync/deploy_loot.py`) retries and resumes from the
shutdown step on exactly this failure — tested with 19 new unit tests. The ad hoc scripts in
`%TEMP%\...\scratchpad\live\apply_and_restart.py` do **not** have this fix; don't reuse them as
permanent tooling.

## In progress, not finished

- **Minimap request** (Jeremy, in-game, 2026-09-14 08:01 server time) — resolved to a PR, not yet
  merged/live: **site-chernarus#77** adds `@MiniMap_Relocated` (workshop id 2979165671) to
  `server/dayz.json`. Needs a server-side add, not just a client `-mod=`, because both `@MiniMap`
  and `@MiniMap Relocated` ship signed PBOs and this server runs `verifySignatures=2` — an untrusted
  signed addon gets the client BE-kicked even though the mod has no script dependency on
  Expansion/CF/Dabs (its only `requiredAddons` is vanilla `DZ_Data`). Recommend `@MiniMap_Relocated`
  over the plain `@MiniMap` (same author, repositioned widget, the two conflict — never load both).
  **Before merging:** the on-disk Shockbyte folder name for this Workshop id is a convention-based
  guess (`sync/mods/folder-names.json` entry is flagged `provenance: "confirm_on_panel"`) — confirm
  it on the panel per this repo's own stated policy, same as core#7's RedFalcon folder-name gap.
  **After merging:** restart (players off), then confirm both `.bikey` files landed in the server's
  `keys/` folder from the workshop pull, or `verifySignatures` will kick everyone including Jeremy.
  `AEGIS-Join-Chernarus.cmd` was deliberately left unedited — don't add it there until the server
  side is live, or Jeremy's own client risks the same kick.

## Owner decisions still waiting (not touched, real money/business — see prior turn for full detail)

**handymansfield PR #9 (merged) — 6 questions**, none decided:
1. QuickBooks confirmed as system of record?
2. Which real job to invoice next — and should 3 recent jobs (Applewood Plaza, 257 Bartley, 255
   Bartley), never entered in QuickBooks, be backfilled too?
3. Tax on labor/materials? (Dry run charged none, matching past Sheets invoices.)
4. Start billing drive time going forward? (No past invoice included it.)
5. Applewood's "Return trip Tuesday" line has no price — free, or missed?
6. Confirm the $55 extended rate and $120 emergency rate.

## Watch for next time

- **The #66-style loss pattern.** Twice now (#59→#66, and it could happen again), a live-state
  pull has silently reverted merged fixes because the fix had been merged to git but never actually
  pushed+restarted before the pull ran. Now that `deploy-loot.yml` exists, loot/economy fixes
  auto-push on merge once `LOOT_DEPLOY_ENABLED=true`, which should close this gap for that file set
  going forward — but any manual `git merge`-only fix to files outside those three paths is still
  exposed to the same failure mode. Worth asking whether a similar auto-deploy should cover trader
  `.map`/structure files and map markers too (site-chernarus#70/#72's files), since those are
  exactly the kind of "merged but not pushed" fix that gets lost.
- **11 open aegis-mods research PRs (#18–#28)** from a documented mod-review protocol
  (`docs/MOD_REVIEW_PROTOCOL.md`, added in #21) — confirmed not a collision with anything built
  tonight, but nobody has triaged/merged them yet.
- **A parallel session shared a worktree with the AEGIS_Core build** (`_wt-mods-session1-core`) and
  merged PR #31 mid-edit. It worked out (the merged code was correct), but flag before starting
  Session 2 (`AEGIS_Skills`) that more than one interactive session may be running plan work at
  once tonight — check `gh pr list` and worktree state before assuming a clean start.
- Tisy's loot changes phase in gradually through the normal restock loop, not instantly — restarts
  restore the previous session's item-count snapshot rather than reseeding fresh (confirmed via
  `sync/ownership.json`'s `storage_1`/`players.db` `ignore` rule and `restart_orchestrator.py`
  never touching them). An immediate reset would need a `storage_1` wipe or `RestartSpawn=1` in
  `globals.xml` — neither was done; ask before doing either.

## Starter prompt for next session

`Read GitHub\SESSION_HANDOFF_2026-09-14-evening.md in full. Check whether the minimap investigation
left a PR; if not, re-run it. Then ask Jeremy for the 6 handymansfield answers if he's around, and
check whether he wants LOOT_DEPLOY_ENABLED flipped on.`
