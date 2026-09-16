# Session 7 (site-chernarus): explosives removal inventory, 2026-09-14

**Status:** Phase A (read-only inventory) is done. It stopped at the coordinator's pause order (usage limit). Phase B hasn't started: no PR-wait loop, no worktree, no edits, no boot.

**Basis:** origin/main `f4a0b7b`. When the inventory was taken, `gh pr list` showed 0 open PRs. The sell-only PR from Session 1 still wasn't opened.

## How class evidence was gathered

Every `config.bin` in the installed PBOs was parsed read-only with a throwaway PBO/rap parser. The parser and its output are in the scratchpad `...\scratchpad\s7\`: `cfgdump.py`, `classes.json`, `inv.py` and `chains.py`. No mod source was copied anywhere near git.

**Mods parsed, in load order:**
- vanilla DayZServer `dta/` and `addons/`
- all Expansion folders
- Windstrides and ACO
- Arma Weapon Pack
- AI War Zones
- VPP
- Workshop cache copies of RedFalcon, ATM, SimpleTraderSigns, MMG (2663169692), Paragon (2820370970) and MiniMap
- AEGIS_Pricing

**Result:** 21,875 CfgVehicles, 574 CfgWeapons, 191 CfgMagazines and 290 CfgAmmo classes. Parse failures were only cpp-only PBOs (beards, AEGIS_Pricing, MiniMap), which don't matter here.

**Findings by mod:**
- **MMG and Paragon:** no explosives. The MK5 grenade pouches are containers, so they stay.
- **Arma Weapon Pack (`A2Weapons.pbo`):** no launchers. It defines 29 weapons (MGs, pistols, rifles, snipers).
- **AI War Zones:** no obtainable explosive items. It has only `AYSAAIWZ_bombExplosion{,2,3}` effect objects and smoke effects.

## REMOVE: classnames grouped, with the evidence for each

| Group | Classname (as used in repo) | Evidence (class chain, PBO) |
|---|---|---|
| Frag grenades | `M67Grenade` | Grenade_Base > ExplosivesBase, vanilla `weapons_explosives.pbo` |
| Frag grenades | `RGD5Grenade` | Grenade_Base > ExplosivesBase, vanilla `weapons_explosives.pbo` |
| Mines | `LandMineTrap` | Trap_Base, vanilla `gear_traps.pbo` |
| Mines | `ClaymoreMine` | ExplosivesBase, vanilla `weapons_explosives.pbo` |
| Plastic/IED | `Plastic_Explosive` | ExplosivesBase, vanilla `weapons_explosives.pbo` |
| Plastic/IED | `ImprovisedExplosive` | ExplosivesBase, vanilla `weapons_explosives.pbo` |
| Detonation-only | `RemoteDetonator` | Inventory_Base, vanilla `gear_tools.pbo` |
| Detonation-only | `RemoteDetonatorTrigger` | Inventory_Base > RemoteDetonator, vanilla `gear_tools.pbo` |
| Detonation-only | `RemoteDetonatorReceiver` | Inventory_Base > RemoteDetonator, vanilla `gear_tools.pbo` |
| Expansion explosive | `ExpansionSatchel` | ExpansionExplosive, `@DayZ-Expansion-Licensed/objects_weapons_explosives.pbo`. This is the only scope-2 Expansion explosive; there is no breaching-charge class. |
| Launcher | `ExpansionRPG7` | ExpansionRPG7Base > Rifle_Base, `@DayZ-Expansion-Weapons/objects_weapons_firearms_rpg7.pbo` |
| Launcher | `ExpansionLAW` | ExpansionLAWBase > SKS, `@DayZ-Expansion-Weapons/objects_weapons_firearms_law.pbo` |
| Launcher | `Expansion_M79` | extends M79, Expansion `objects_weapons_firearms_m79.pbo` |
| Launcher | `M79` | M79_Base, vanilla `weapons_launchers.pbo`. Expansion overrides it as deprecated (see #80). |
| Launcher (dead) | `a2m32` | **not defined in any installed PBO**; the Arma pack has no M32. Removing it cleans up a dead classname. |
| Rocket/40mm HE | `ExpansionAmmoRPG` | ammo `ExpansionRocketRPG`, rpg7 PBO |
| Rocket/40mm HE | `ExpansionAmmoLAW` | ammo `ExpansionRocketLAW`, law PBO |
| Rocket/40mm HE | `Ammo_Expansion_M203_HE` | ammo `Bullet_Expansion_M203_HE`, Expansion m79 PBO |
| Rocket/40mm HE | `Ammo_40mm_Explosive` | Ammo_40mm_Base, vanilla `weapons_ammunition.pbo` |
| Launcher mag (dead) | `m32_magazine` | **not defined in any installed PBO** |

These are defined but aren't referenced anywhere in the repo, so there's nothing to remove:
- vanilla `RPG7`, `LAW`, `M203`, `M203_Standalone`, `GP25`, `GP25_Standalone` and `UnderSlugGrenadeM4`
- `Ammo_RPG7_HE`/`_AP`, `Ammo_LAW_HE` and `Ammo_GrenadeM4`
- `*Placing` variants
- `ExpansionExplosive*` bases (scope 1)

No `expansion_m203` weapon class exists. The M203 name exists only as the round family.

## KEEP (per scope)

- **Flashbangs:** `FlashGrenade`
- **Smoke grenades:** `M18SmokeGrenade_*`, `RDG2SmokeGrenade_*`
- **Airdrop signal:** `ExpansionSupplySignal`
- **Flares:** `Roadflare`, `Ammo_Flare*`, `Expansion_Ammo_FlareSupply*`
- **Fireworks:** `FireworksLauncher`, `Anniversary_FireworksLauncher`
- **40mm smoke rounds:** `Ammo_40mm_Smoke_*`, `Ammo_Expansion_M203_Smoke_*`, `Ammo_Expansion_M203_Sticky_Smoke_*`
- **Grenade pouches:** MMG/ALV pouches (containers)

## AMBIGUOUS: list in the PR as questions, don't remove

1. **`Grenade_ChemGas` and `Ammo_40mm_ChemGas`** (vanilla): lethal contaminated gas, but not explosive. Sources: Explosives_And_Grenades, Ammo_T1, Hardline, and cfgrandompresets Xmas_Weapons_Small.
2. **`Expansion_M18SmokeGrenade_Teargas`, `Ammo_Expansion_M203_Smoke_Teargas` and `..._Sticky_Smoke_Teargas`:** smoke, but they cause a gas effect.
3. **40mm smoke/teargas rounds with no launcher left.** `Expansion_M79` and `M79` were the only 40mm launchers. Once they're removed, the kept smoke rounds (in Ammo_T1, Special's teargas overrides, and airdrops) can't be fired. Keep them as sellable junk, or remove them too?
4. **`BearTrap` and `TripwireTrap`:** traps, but not explosive (Supplies/Tools, types, Hardline, BaseBuildingSettings). Recommend keep.
5. **Decorative builder props:** `bldr_LandMineTrap` in `expansion/objects/Green_Mountain_Trader.map:68` and `bldr_Ammo_LAW_HE` ×2 in `Krasnostav_Trader.map:206-207`. These are HouseNoDestruct statics, not items. Recommend keep.
6. **AI War Zones `zoneExplosionEffectMax`** (non-zero in 5 of 6 zones, `profiles/AIWarZones/AIWarZones_Settings.json`) spawns `AYSAAIWZ_bombExplosion*`. It's unverified whether that damages players. If it does, set it to 0.
7. **`RaidSettings.json` `ExplosiveDamageWhitelist`** lists M79, RGD5, M67, FlashGrenade and the C4/RPG/LAW explosions. `EnableExplosiveWhitelist` is 0, so it's inert. Recommend leaving it as is, or pruning it as cosmetic.

## Every place an explosive is obtainable, meaning the files that must change

Paths are relative to `server/`. **P** = push-owned (`sync/ownership.json`) and **L** = pull-owned (live state, don't edit).

| File | What | Owner |
|---|---|---|
| `mpmissions/.../db/types.xml` | `M67Grenade` nom15, `RGD5Grenade` 15, `LandMineTrap` 10, `ClaymoreMine` 4, `Plastic_Explosive` 5, `RemoteDetonator` 5, `M79` 2, `Ammo_40mm_Explosive` 20. `ImprovisedExplosive`, `RemoteDetonatorTrigger` and `RemoteDetonatorReceiver` are already 0. Set nominal/min to 0, or remove the entries. | P |
| `mpmissions/.../ce_nasdara/nasdara_weapons_types.xml` | `ExpansionLAW` nom2, `ExpansionRPG7` nom2 (Military Tier4) | P |
| `mpmissions/.../cfgrandompresets.xml` | `grenades` cargo (l.234-238): `RGD5Grenade` (keep smoke/flash). `Xmas_Weapons_Small` (l.609-616): M67, RGD5, LandMineTrap, and the ambiguous ChemGas/40mm ChemGas, plus `Ammo_40mm_Explosive`. `Xmas_Fillers_Medium` (l.761-763): ClaymoreMine, Plastic_Explosive | P |
| `profiles/ExpansionMod/Market/Explosives_And_Grenades.json` | m67grenade, rgd5grenade, expansionsatchel, remotedetonator, remotedetonatortrigger. ChemGas is ambiguous. | P |
| `profiles/ExpansionMod/Market/BlackMarket_Explosives.json` | The category becomes empty: claymoremine, improvisedexplosive, landminetrap, plastic_explosive. Remove the file and its `Traders/BlackMarket.json` category reference, or leave it empty; check validate's orphan/empty rules. | P |
| `profiles/ExpansionMod/Market/BlackMarket.json` | expansionrpg7, expansionlaw, expansion_m79, a2m32 | P |
| `profiles/ExpansionMod/Market/Ammo_T1.json` | expansionammorpg, expansionammolaw, ammo_40mm_explosive, plus `ammo_expansion_m203_he` if present. ChemGas and teargas are ambiguous. | P |
| `profiles/ExpansionMod/Market/Magazines_Launcher_T1.json` | m32_magazine: the category becomes empty. Check which traders list the category. | P |
| `profiles/ExpansionMod/Market/Tools.json` | remotedetonator (keep tripwire) | P |
| `profiles/ExpansionMod/Traders/Special.json` | Item overrides: expansionrpg7, expansionlaw, expansionammorpg, expansionammolaw. Its only category is `Explosives_And_Grenades`. | P |
| `profiles/ExpansionMod/Traders/Weapons_T3.json` | Item overrides: expansion_m79, expansionrpg7, expansionlaw, a2m32, expansionammorpg, expansionammolaw | P |
| `profiles/ExpansionMod/Traders/Weapons.json`, `Weapons_T2.json` | Item overrides: expansionammorpg, expansionammolaw | P |
| `profiles/ExpansionMod/Traders/BlackMarket.json` | Category `BlackMarket_Explosives` if the file is dropped | P |
| `mpmissions/.../expansion/settings/HardlineSettings.json` `ItemRarity` | m67grenade, rgd5grenade, landminetrap, claymoremine, plastic_explosive, improvisedexplosive, remotedetonator (×3 keys), expansionsatchel, expansionrpg7, expansionlaw, expansion_m79, m79, a2m32, m32_magazine, expansionammorpg, expansionammolaw, ammo_expansion_m203_he, ammo_40mm_explosive | P |
| `profiles/ExpansionMod/Settings/AirdropSettings.json` | Loot entries: RGD5Grenade (l.1192, 5056), M67Grenade (1201, 5065), LandMineTrap (1273, 5137), M79 (4946), ExpansionRPG7 (5449), ExpansionLAW (5458), ExpansionAmmoRPG (5859). The M203 smoke rounds at 5751-5850 are ambiguous (#3). | P |
| `mpmissions/.../expansion/settings/P2PMarketSettings.json` | expansionsatchel and remotedetonator×2: a list, probably a blacklist. **Read before editing**; adding classes to a blacklist is correct, removing them isn't. | P |
| `mpmissions/.../expansion/settings/PersonalStorageSettings.json` | expansionsatchel and remotedetonator×3: probably an exclusion list. **Read before editing.** | P |
| `mpmissions/.../expansion/traderzones/{GreenMountain,Kamenka,Krasnostav}.json` | Stock cache of all the classes above | **L: don't edit.** Entries go stale harmlessly once the Market entries are gone. |
| Loadouts (`profiles/ExpansionMod/Loadouts/*`) | **None.** Only RDG2 smoke. | none |
| `AI/LootDrops`, `MissionSettings.json`, `QuestSettings.json`, `SpawnSettings.json`, AIPatrol/AILocation settings | **None.** | none |
| `cfgspawnabletypes.xml` | Not in the repo. Only `ce_nasdara/nasdara_mmg_spawnabletypes.xml` is, and it has pouches only. The live vanilla cfgspawnabletypes wasn't checked. | n/a |
| Crafting | No site-side recipe config exists. Vanilla crafting is script-side and can't be changed from site config. `ImprovisedExplosive` is already nominal 0. | n/a |

**Docs to update:**
- `docs/nasdara-economy-comprehensive-plan.md` (§7 launchers)
- `docs/aegis-reputation-bands.md` (launcher and rocket rows)
- `docs/aegis-chernarus-golive-plan.md` §5 checklist
- `docs/economy-data-guide.md` (Special RPG/LAW override mention)
- `docs/PLAN.md` (m79/expansionrpg7 mentions)
- `tools/economy/rarity_coherence.py` (hard-codes the expansion_m79/expansionlaw/expansionrpg7/m79 names; check whether it errors when they're absent)

## What's left to do

1. **Phase B wait.** Poll `gh pr list -R yodatech1988/site-chernarus --state open` until there's no agent PR. Session 1's sell-only PR is expected, and also touches Market, Traders and Hardline, so rebase on it. Then run `New-ParallelWorktrees.ps1 -Repo aegis-site-chernarus -Slugs 'session7-remove-explosives'`.
2. **Edits.** Apply the table above on fresh origin/main, read P2P/PersonalStorage semantics first, and re-grep after the sell-only merge.
3. **Validators.** Run `python sync/validate.py server`, `pytest sync/` (baseline 212), `tools/economy/econ_check.py` (compare with before) and `tools/economy/rarity_coherence.py`.
4. **Local boot.** Check `Get-Process *DayZ*` first; at inventory time only DayZLauncher was running. Reuse `scratchpad\s6\boot.ps1` with a new instanceId and port, not 2422/2442/2482/2562. Back up overwritten dev-server files first. The target is 0 Hardline errors, 0 MARKET CONFIGURATION ERROR and 0 unexplained missing classnames.
5. **Docs.** Update the docs listed above.
6. **PR.** Open one PR, not merged. Put the ambiguous questions in it, plus the note that already-held explosives stay until a wipe (optional cleanup recommendation). Report the push-owned files changed for the live push.
