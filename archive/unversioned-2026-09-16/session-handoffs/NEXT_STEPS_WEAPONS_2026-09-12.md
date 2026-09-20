# Chernarus: weapons not spawning — next steps (prepared 2026-09-12 23:08 EDT)

**Starter prompt** — paste this into a fresh Claude Code conversation to pick up where the prior
session left off:

> Read `<USER_HOME>\GitHub\NEXT_STEPS_WEAPONS_2026-09-12.md` in full, then continue the
> investigation and fix it. Work in `<USER_HOME>\GitHub\aegis-site-chernarus` (branch
> `ammo-market-categories`). If a fix requires deploying to the live server, tell Jeremy what to
> click rather than doing it yourself — see `jeremy-no-git-commands` guidance (do git myself, but
> hand off anything that needs the Shockbyte panel or an in-game/server-side action).

## The problem

Jeremy reported weapons are not spawning anywhere on the live Chernarus server — this affects
*all* weapons, not one specific gun, which points at something systemic (a whole types.xml
category/file failing to load, a broken shared tag/tier/category/usage/value string, or a
duplicate-classname parse failure) rather than a per-item typo.

## What's already known

Repo: `<USER_HOME>\GitHub\aegis-site-chernarus`, currently on branch `ammo-market-categories`
(up to date with `origin/ammo-market-categories`). Two untracked files sitting in the working tree
that are **not part of this investigation** — leave them alone unless they turn out to be related:
`docs/aegis-discord-kofi-setup-kit.md`, `rs_tmp.yml`.

Recent commits that touched weapon economy and are the most likely place a systemic break was
introduced (most recent first):

- `702e5a4` Merge origin/main, keep main's real pricing for HE/rocket rounds
- `79ce88d` Pin the Tier D and NBC Case Plus Workshop IDs (#30)
- `c9ba6a7` Fix ammo economy exploit: SellPricePercent -1 falls through, not non-sellable
- `342be0c` Vendor core's check_vendored_files_match / load_text_dir into validate.py (#29)
- `dd59dd6` Rebalance weapon economy on the real server: fix dead wreck loot, scale weapons to
  primary category (#19)
- `542b70c` Fix 66 duplicate market classnames from #39 without changing any payout (#51)
- `a9a8861` Economy coherence pass: complete the weapon ladder, fix market price defects, add
  analytics data guide (#39)

Note `542b70c` exists specifically because duplicate classnames were already found once in this
repo's generated market files — the same failure mode (a duplicate `<type name="...">` in
types.xml, or a duplicate entry across the files `cfgeconomycore.xml` loads) is a prime suspect,
because DayZ's economy loader can silently drop or fail an entire category/file on a duplicate or
malformed entry, killing spawns for everything in it at once.

## Investigation result (2026-09-12, background agent) — this is NOT a config bug

The background agent checked every plausible git-side cause and all of them are clean:

1. `server/mpmissions/dayzOffline.chernarusplus/db/types.xml` (1970 types, vanilla weapons) —
   valid XML, 0 duplicate classnames, no weapon entry with `nominal=0`/`min=0` (the only 0-nominal
   entries are unrelated inert skin variants like `AK74_Black`, pre-existing and irrelevant), every
   weapon has `count_in_map="1"`.
2. `ce_nasdara/nasdara_weapons_types.xml` (73 modded firearms) — same, clean, no classname overlap
   with `db/types.xml`.
3. `cfgeconomycore.xml` correctly registers `ce_nasdara/nasdara_weapons_types.xml`. It has no
   explicit `<ce folder="db">` block, but that's normal — `db/types.xml` is DayZ's hardcoded
   default table and has been unregistered-but-loaded since baseline (`7360e33`), not a recent
   regression.
4. `cfglimitsdefinition.xml` category/usage/tier lists match every string actually used in both
   types files — no orphaned tags.
5. The `ammo-market-categories` branch's diff vs `origin/main` touches **only** Expansion Market
   JSON pricing files (`Ammo_T1.json`, `Ammo_T2.json`, `BlackMarket_Ammo.json`) plus a doc — never
   `types.xml`, `cfgeconomycore.xml`, or `cfglimitsdefinition.xml`.

**The real cause**: `docs/nasdara-restart-checklist-2026-09-11.md` (already in this repo) documents
that this exact failure mode already happened once before on this project — *"local dev box has
the CE files registered; production never got them."* The weapon-economy fix also has a copy in
the sibling `DayZServer` repo's `types.xml`, it's unconfirmed which server is actually live
production (self-hosted/OVH per `DayZServer/README.md` vs. the Shockbyte panel apparently in
actual use), and pushing `types.xml` to the live server is a manual, credentialed, Jeremy-only step
— nothing in CI/automation performs it. **Every fix already exists correctly in git; the live
server almost certainly never received it, or the wrong box is being treated as production.**

## Next steps — this is now an operational handoff, not a code fix

No further git changes are needed on the weapons economy itself. What's left, per
`docs/nasdara-restart-checklist-2026-09-11.md` steps 0–3 (all marked **[Jeremy]** — Claude cannot
do these without SFTP/panel credentials):

1. **[Jeremy]** Confirm which server is actually live production — the self-hosted/OVH box
   described in `DayZServer/README.md`, or the Shockbyte panel. Don't assume; check which one
   players are actually connecting to.
2. **[Jeremy]** Back up that server's current live `db/types.xml` before touching anything.
3. **[Jeremy]** Upload this repo's already-validated `db/types.xml` (and `ce_nasdara/` if it's
   missing there) to that live server, replacing the stale copy.
4. **[Jeremy]** Restart the server and check its console/RPT log Errors/Warnings section for any
   `type not found` classname errors, which would mean something still doesn't match.
5. Once confirmed working: set up read-only SFTP access (checklist step 3) so a future "is the fix
   actually live" question doesn't require guessing again — that's a good follow-up for a coding
   session once credentials exist.

If a fresh session picks this up and weapons are *still* not spawning after Jeremy does 1–4 above,
that's the point to re-open investigation — and this time pull the live server's actual
`db/types.xml` over SFTP and diff it directly against this repo's copy, rather than re-auditing git
alone (git was already proven clean).
