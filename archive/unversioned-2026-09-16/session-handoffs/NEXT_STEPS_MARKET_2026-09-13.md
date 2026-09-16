# Market catalog track: next steps (prepared 2026-09-13)

**Sessions A/B done (site-chernarus#57/#59).**

Triggered by in-game notes from Jeremy: multiple same-category accessories that should be
streamlined by weapon family (pistols/rifles/shotguns/snipers), bags showing up in the wrong
trader, clothing showing up in the wrong trader, and a general "audit all items" ask. Repo is
`site-chernarus`. Rules per that repo's `docs/PLAN.md`: one session = one PR, worktree per session,
branch `agent/site-chernarus/<slug>`, `validate` must stay green, nothing here pushes to the live
server (Contract 6).

## What's confirmed so far (verified 2026-09-13, direct read of `origin/main`)

- **Misfiled items found by spot heuristic, not yet a full audit:**
  - `Market/Supplies.json` (wired only to the **BuildingSupplies** trader, alongside
    Tools/Locks/Tents/Flags) carries 35 bag/pouch classnames (`alicebag_*`, `assaultbag_*`,
    `attack2bag_*`, `mountainbag_*`, `slingbag_*`, etc.) that duplicate what `Market/Backpacks.json`
    (141 items, wired to the Clothing_Accessories trader) already exists for.
  - `Market/Holsters_And_Pouches.json` (Clothing_Accessories trader) carries 30 `mmg_*`
    ammo-pouch/mag-pouch/grenade-pouch classnames that read as weapon-attachment gear, not clothing.
  - No literal clothing found inside a weapons-trader file yet — the three weapon tiers only carry
    ammo/guns/attachments. Jeremy's "clothing in building trader" observation may map to the Supplies
    case above (bags, not clothing, in a non-weapon trader) or to something the spot-check missed —
    the full 3,249-classname catalog needs a real pass, not a sample.
  - Existing tooling (`aegis-core/sync/validate.py`'s `check_orphan_categories`) only catches
    categories no trader references at all — nothing today checks whether an item is filed in a
    category that doesn't match what it actually is.
- **Attachments today are grouped by tier, not weapon family.** `Traders/Attachments.json`'s
  `Categories` are `Magazines_T1/T2/T3`, `Optics_T1/T2/T3`, `Muzzles`, `Bayonets`, `Buttstocks`,
  `Handguards` — flat lists mixing every weapon family together within a tier. Jeremy has confirmed
  the goal: **split these into weapon-family groups** (pistol accessories, rifle accessories, shotgun
  accessories, sniper accessories) instead of tier-only groups.
- **Attachment compatibility (which muzzle/optic/mag fits which gun) is not in any Market or Trader
  JSON in this repo.** It's defined by the installed Expansion weapon configs (`@DayZ-Expansion-Weapons`,
  present locally at `E:\@DayZ-Expansion-Weapons`) via each weapon's `InventorySlots`/attachment-slot
  inheritance. The restructure lane cannot assign accessories to a weapon family from `site-chernarus`
  data alone — it has to read the installed mod's weapon configs (or the class hierarchy) to know,
  e.g., which magazines are rifle mags vs pistol mags vs shotgun shells.
- **Trader invariant (PLAN.md Contract 2) and sell-price-resolution (Contract 3) still apply**: don't
  break the T3/T4 Krasnostav buy+sell / sell-only wiring, and don't treat a classname in two
  disjoint-trader category files as an accidental duplicate without checking which traders carry it.

## Sequencing

Session B depends on Session A's actual findings (which items are misfiled, and the full per-family
item lists for the attachment split) — it is not safe to parallelize them the way the economy lanes
were. Session A first; Session B opens only after A's PR/report is in.

---

## Session A — Full market item audit (Sonnet 5, open in `_wt-chernarus-market-audit`, already set up)

Worktree already created: branch `agent/site-chernarus/market-item-audit` off `origin/main`.

```
Read only aegis-core/sync/validate.py in full (the existing check_duplicate_classnames,
check_orphan_categories and check_trader_categories_exist validators — this session extends that
tradition, it doesn't replace it), tools/economy/econ_check.py, docs/PLAN.md's Contracts section
(especially Contract 2 trader invariant and Contract 3 sell-price resolution), and
docs/nasdara-economy-comprehensive-plan.md's "Trader wiring" section. Then read every file in
server/profiles/ExpansionMod/Market/*.json (84 files) and server/profiles/ExpansionMod/Traders/*.json
(27 files) -- this is a data audit, you need the full set, not a sample.

Produce a structured audit report (new file docs/market-item-audit-2026-09-13.md) answering:
1. Which classnames are filed in a category whose trader doesn't match what the item actually is
   (e.g. bags filed under a category wired only to a non-clothing/non-backpack trader; weapon
   attachments filed under a clothing category; consumables filed under a hardware category). Use
   the classname itself plus, where genuinely ambiguous, the item's real-world/DayZ item type -- you
   may need to recognize common DayZ/Expansion/CF-pack classname conventions (mmg_, paragon_, alv_,
   a2_, expansion_ prefixes) rather than guessing blind. List each misfiled item with its current
   category file, its current trader, and the category/trader you think it belongs in instead.
2. A complete list of every accessory classname currently reachable through the Attachments trader
   (Magazines_T1/T2/T3, Optics_T1/T2/T3, Muzzles, Bayonets, Buttstocks, Handguards), grouped by which
   weapon family it is actually compatible with (pistol / rifle / shotgun / sniper rifle / universal).
   To determine compatibility, read the installed Expansion weapon mod's configs at
   E:\@DayZ-Expansion-Weapons (read-only, it's outside this repo, just a reference) for each weapon's
   attachment slot inheritance -- don't guess from classname alone, verify against the actual weapon
   config. Flag any accessory you cannot confidently assign to one family (call these "universal" or
   "unresolved" explicitly, don't force them into a bucket).
3. Any duplicate classnames beyond the 66 documented Contract-3 hub/BlackMarket differential pairs --
   cross-check against econ_check.py's own duplicate logic so you're not re-flagging the already
   understood intentional case.
4. Any category file that is empty or orphaned that isn't already one of the known 7 empty T3/T4
   tier files (those are documented as deliberate/being handled elsewhere -- don't re-litigate them).

Do not change any Market or Trader JSON file in this session -- this is audit-only, output is the
report document. Run aegis-core/sync/validate.py against this repo to confirm you haven't broken
anything (you shouldn't have touched game data at all). Branch
agent/site-chernarus/market-item-audit, one PR adding the report, and open a tracking issue titled
"Market catalog audit: misfiled items + attachment weapon-family mapping" whose body is the report's
summary section with a link to the full doc.
```

---

## Session B — Split Attachments trader by weapon family (Sonnet 5, blocked on Session A)

Not started yet; Session A's per-family classname lists are the input. Once A's report exists, this
session:
- Reads Session A's report (the weapon-family groupings and the misfile list).
- Creates new Market category files per weapon family for each attachment type that currently mixes
  families (e.g. split `Magazines_T1`/`Optics_T1`/etc. into family-specific files, or add family as a
  dimension the way tiers already are -- exact file-naming scheme is this session's call, follow the
  existing `<Type>_<Tier>.json` convention).
- Repoints `Traders/Attachments.json`'s `Categories[]` (and any other trader referencing the old
  category names) to the new family-specific files.
- Fixes the misfiled items Session A found (moves bags out of `Supplies.json` into `Backpacks.json`
  or wherever A recommends, moves the `mmg_*` pouches out of `Holsters_And_Pouches.json`), unless A's
  report flags a specific move as needing Jeremy's sign-off first (per issue #6's precedent: a change
  that empties a trader tab or measurably changes what's purchasable needs explicit confirmation, not
  a silent push).
- Verifies with `validate.py` and `econ_check.py`: zero orphan categories, zero dangling trader
  references, zero broken duplicate differentials, item counts before/after reconciled in the PR body.
- Contract 6 still applies: no `nasdarasync push`, no live restart. This stays a repo-only change
  until Jeremy pushes it.

Starter prompt to be written once Session A's report exists.

---

## Owner items (not automatable from here)

- **Review Session A's audit report** once posted — especially any misfile Session A is unsure about,
  and the "unresolved" attachment classnames it can't confidently assign to a weapon family.
- **Sign off on any trader-tab-visible change** Session B proposes, same standard as issue #6 (does
  an item become unpurchasable or a tab go empty as a side effect of the reorg).
- **Nothing here pushes to the live server** — once Session B's PR merges, it joins the existing
  Phase 3 push queue in `docs/PLAN.md` / `docs/aegis-chernarus-golive-plan.md`, not a separate push.
