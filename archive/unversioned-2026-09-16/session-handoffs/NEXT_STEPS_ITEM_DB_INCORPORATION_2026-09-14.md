# Incorporating the POI/clothing/weapons/vehicles research into `dayz_economy`, mindful of total loot pool (prepared 2026-09-14)

Covers how the four draft content proposals (aegis-poi#6, aegis-mods#18/#19/#20) actually land in
the database, once each is approved per `aegis-mods/docs/MOD_REVIEW_PROTOCOL.md` (aegis-mods#21).
Nothing here authorizes merging any of those four PRs — this is the plumbing plan for *after* the
owner approves a given proposal, not a request to approve them now.

## Ground truth, verified against `origin/main` (services), not memory or a stale local branch

- **One database, not two.** `dayz_loot` was folded into `dayz_economy` on 2026-09-13
  (services#51) — there is no separate loot database. The `loot_*` tables
  (`loot_types`, `loot_events`, `loot_random_presets`, `loot_spawnable_types`, etc.) live inside
  `dayz_economy`, migrations `0004`-`0010`, alongside the money tables (`wallets`,
  `ledger_transactions`, `shop_catalog`, `vehicle_entitlements`). `db/economy/README.md`'s "Loot
  config" section is the current source of truth — some other local docs/branches still describe
  the pre-fold `db/loot` shape; don't trust those.
- **The live database has the schema but is empty of loot data.** Migrations 0001-0010 are applied
  live (verified 2026-09-14), but per `NEXT_STEPS_ECONOMY_AUTOMATION_2026-09-14.md`: "the loot
  tables exist but are empty." The import/export code (`db/economy/src/import/loot.js`,
  `src/export/loot.js`) is built and round-trip-verified against the real site-chernarus files
  (2,043 `loot_types` rows: 1,970 vanilla/Expansion `db/types.xml` + 73 AEGIS-modded
  `ce_nasdara/nasdara_weapons_types.xml`), but has only ever run against a throwaway local MySQL
  container, never the live one.
- **`EconomyDbKey.ps1` doesn't wire up loot import/export yet.** It handles migrate + catalog
  sync; running the loot importer against the real live DB today means a manual
  `node src/import/loot.js --apply` with `ECON_DB_*` env vars set, which isn't the
  no-typed-passwords-outside-a-key-tool pattern this network otherwise holds to.
- **`shop_catalog` (Castellan Scrip real-money shop) is a separate concern from `loot_types`
  (what spawns naturally in the world).** The weapons/vehicles proposals' "trader-tier gating by
  reputation" refers to the in-game Expansion Market AI traders (JSON config in
  `aegis-site-chernarus`, priced by `aegis-pricing`'s Hardline reputation curve) — **not**
  `shop_catalog`, which is the real-money donation shop and has no reputation column at all.
  Don't conflate the two when writing DB changes for those two proposals.

## Prerequisite (blocks everything below): seed the live baseline before adding anything new

Adding new rows to an empty live `loot_types` table and then exporting would generate a
`types.xml` missing all 2,043 existing entries — a live-breaking deploy. Before any of the four
proposals' items go in:

1. **Session 0 (build) — done, [services#78](https://github.com/yodatech1988/services/pull/78),
   merged 2026-09-14:** added an "Import loot (baseline)" button to `EconomyDbKey.ps1` — dry run
   against site-chernarus `origin/main`'s mission folder (git-archived) and the local
   `DayZServer` checkout, a confirmation showing counts, `--apply`, then an automatic
   `export --verify-against` round-trip check.
2. **Session 0 (owner click) — not yet done.** Once #78 is merged: open `EconomyDbKey.ps1`,
   click **Import loot (baseline)**, confirm both dialogs, and confirm the verify step reports
   PASS on all 7 files. This seeds the 2,043-row baseline and is the *only* point where nothing
   new is being added — pure verification that DB-as-source-of-truth reproduces today's live
   config byte-for-byte before it's trusted with anything new.

Everything below assumes this baseline is live and verified.

## Total loot pool budget — the constraint driving every design choice below

DayZ's CE loot system dilutes: every `loot_types` row that shares a tag competes for the same
finite set of tagged loot points, so adding distinct spawnable classnames doesn't just cost server
CPU/memory (already covered per-proposal in the mod-review protocol's server-impact step) — it
measurably reduces how often *everything else with that tag* spawns. The 2,043-row baseline is the
number every addition should be weighed against, not zero.

**Default policy: prefer trader-only (no `loot_types` row at all) over adding to the natural spawn
pool.** An item can exist in the game — sellable, ownable, usable — without ever being a
`loot_types` row, if it's trader/reward-exclusive. This is the cheapest possible option against the
pool budget: literally zero rows added, zero dilution, and it's consistent with the item-count
ceiling already agreed in aegis-mods#18/#19 (prefer gating/reuse over adding).

## Per-lane plan

### Clothing (aegis-mods#18) — the only lane that adds real new classnames

- 9 new classnames (3 slots x 3 rarity tiers), confirmed net-new in the PR's item-budget addendum.
- **Recommended default: trader-only, zero new `loot_types` rows.** These are reskins gated by
  reputation tier already (Elite/Veteran) — there's no design reason for them to also spawn
  naturally in the world; making them trader/reward-exclusive keeps this lane's pool-budget impact
  at exactly zero.
- If the owner instead wants some tiers to spawn naturally (e.g. the base civilian tier, to feel
  less exclusive than the rep-gated tiers): each such classname needs one `loot_types` row
  (nominal/lifetime/min/category), plus `loot_type_tags` rows matching a sensible existing tag set
  (reuse an existing vest/clothing tag rather than inventing one), and a `loot_file_sources` row
  pointing at whichever file AEGIS-original items live in (mirroring how `ce_nasdara_weapons` has
  its own `source_key`, e.g. `ce_aegis_clothing`). Cap this at the base tier only, not all 9,
  to keep pool growth to single digits.
- No `shop_catalog` row is needed unless these are also sold for Castellan Scrip (real-money shop)
  — that's a separate owner decision from trader-visibility-by-reputation, which is Expansion
  Market config, not this database.

### Weapons (aegis-mods#19) — zero new classnames, zero `loot_types` changes

- v1 gates existing `DayZ-Expansion-Weapons` classnames' trader/loot **visibility** by reputation
  tier — it does not mint new classnames, per the PR's item-budget addendum. No new `loot_types`
  rows needed at all.
- The rep-tier gating itself is Expansion Market trader-zone config (JSON files in
  `aegis-site-chernarus`), not a database change — nothing in `dayz_economy` represents "which rep
  tier can buy this," and this plan doesn't propose adding one; that logic already lives in
  `aegis-pricing`'s Hardline curve read at the trader.
- Only DB-relevant action: none, unless the owner later asks for existing weapon nominal/lifetime
  values to be retuned — that's an edit to existing rows once the baseline is live, not new rows,
  and doesn't touch the pool-size budget.

### Vehicles (aegis-mods#20) — zero new classnames, existing rows only

- v1 reuses the existing Expansion/vanilla vehicle roster. Same as weapons: no new `loot_types`
  rows.
- If the owner wants to raise how often a given vehicle spawns as a natural wreck/find (distinct
  from trader stock, which again is Expansion Market config, not this DB), that's a `nominal`/
  `min`/`restock` edit to that vehicle's *existing* `loot_types` row once the baseline import has
  run — never a new row, so it doesn't move the pool-budget needle.
- The proposed ~60-90 simultaneous-vehicle spawn budget (shared with the future aircraft module)
  is a runtime/CE spawn-count concern, separate from the `loot_types` row count discussed here —
  don't conflate "how many vehicles can exist at once" with "how many distinct vehicle classnames
  are in the loot table." Track the spawn-count budget in the vehicles module's own settings, not
  the database.

### POI (aegis-poi#6) — new `loot_events`/`loot_random_presets` rows, but no new classnames

- Concepts like Bunker, Crash Site and Supply Drop want their own loot tables (which items, how
  much, how it resets) — these are `loot_events` + `loot_event_children` rows (or
  `loot_random_presets`/`loot_random_preset_items` for cargo-style rolls), referencing **existing**
  classnames from the already-imported baseline. Zero new `loot_types` rows for POI itself.
  Confirm every classname a POI event references already exists in the baseline before inserting a
  row that references it (a dangling reference is a bad row, not a schema violation the DB will
  catch — `loot_event_children.child_type` is a plain string, not a foreign key).
- This does add to a *different* pool than `loot_types` — dynamic-event budget — but that's already
  the subject of the POI PR's own server-impact section (restart/persistence,
  `ECE_NOPERSISTENCY_WORLD` vs `ECE_DYNAMIC_PERSISTENCY`), not a new concern this plan introduces.
- Sequence POI loot-table rows after whichever prefab/spawn-mechanics work the aegis-poi
  `session2-api-research` branch resolves — a loot table for a POI that doesn't have its spawn
  mechanism finished yet is dead data.

## Sequencing (do in this order, one PR/session each)

1. **Session 0** (above): wire + run the baseline loot import against the live DB. Blocks
   everything else. Technical/infra, fine under the standing automerge policy.
2. **Owner approves whichever of the four content PRs they want to proceed with**, per
   `MOD_REVIEW_PROTOCOL.md` — this plan does not do that approval.
3. **The approved module's code merges and ships live first** (aegis-mods/aegis-poi PR, actual
   `config.cpp` classnames exist in a loaded mod) — a DB row for a classname nothing defines yet is
   harmless but meaningless; don't add loot-table rows for content that isn't live.
4. **Add the DB rows** per the lane's plan above, as its own small PR against `db/economy`
   (direct INSERT via a migration-adjacent seed script, not a schema migration, since these are
   config rows the "loot config is meant to be edited directly as tuning changes" README note
   already covers).
5. **Regenerate XML** via `export/loot.js --apply` against the real `aegis-site-chernarus`
   checkout, verified with `--verify-against` before it's trusted.
6. **Deploy** through the site's existing sync/restart tooling.

Every content-adding row (step 4) is still a content decision, not a technical one — same
ground rule as `MOD_REVIEW_PROTOCOL.md`: propose via PR, owner decides, no auto-merge for content
even though the surrounding plumbing (steps 1, 5) is technical and fine to automerge.
