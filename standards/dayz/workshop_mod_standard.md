# Workshop mod standard

Every piece of AEGIS gameplay we build ships as a **self-contained Steam Workshop mod**: one
feature, one package, explicit dependencies, defaults that work on any server. A site repo
(`site-chernarus`, future Deer Isle, Nasdara…) *installs and tunes* modules. It never contains
their code.

The general principle behind this applies to every repo: build in self-contained packages with a
manifest and declared dependencies. For DayZ, that package is a Workshop mod.

## Why

As of 2026-09-12, AEGIS mod source lives in three places, and none of them can ship:

| Where | What | Problem |
|---|---|---|
| `P:\AEGIS_Core`, `AEGIS_Vehicles`, `AEGIS_Aircraft`, `AEGIS_HelloWorld` | Skills/perks, vehicle, aircraft, pipeline test | Not in git. One disk failure loses it. |
| `site-chernarus` `mods/AEGIS_PvPGuard` (PR #43, merged) | PvP damage → reputation | Mod code inside a site repo. A second site would have to copy it. |
| `core/mods/` (empty) and the skin library (core `assets/dayz-skin-library/`, PR #39 merged) | Reserved for mod source | Core is sync CLI + reusable CI. Mod releases would be tied to CI tags. |

Since then (2026-09-12): `aegis-mods` exists and holds `AEGIS_Metrics` and `AEGIS_TeddyBear`;
`aegis-poi` exists for the POI modules (rules 1 and 4 exceptions). The `P:\` sources and
`AEGIS_PvPGuard` are still where the table says.

Gameplay written as site config (Expansion JSON, `types.xml`, mission `init.c` script) only works
on the server it was written for. A module built as a Workshop mod works on every AEGIS site and can
be published.

## Rules

1. **One home: the `aegis-mods` repo.** Every AEGIS mod lives there under `mods/AEGIS_<Name>/`.
   Site repos and core hold no Enforce Script. `P:\AEGIS_<Name>` is a directory junction into the
   repo checkout, so DayZ Tools keeps working and git keeps the history.
   - *Scoped exception (owner-approved 2026-09-12):* prebuilt point-of-interest modules
     (`AEGIS_POI` and `AEGIS_POI_*`) live in the `aegis-poi` repo, with the same layout,
     `module.json` contract, tooling and signing key as `aegis-mods`. Nothing else goes there.
2. **One module = one feature = one Workshop item.** Each module has one PBO prefix `AEGIS_<Name>`,
   one `CfgPatches` class of the same name, and one `@AEGIS_<Name>` package. Features that can be
   switched on independently are separate modules.
3. **Dependencies are declared, never assumed.** A module may depend only on:
   - `AEGIS_Core`,
   - the vanilla `DZ_*` addons, and
   - third-party mods listed in its `module.json`.

   Each dependency appears in both `requiredAddons[]` and the manifest. Soft integration with an
   optional mod (for example, Expansion reputation) goes behind that mod's own preprocessor define,
   verified in its source. The module must still load without it.
4. **`AEGIS_Core` is the only shared layer:** logging, settings loading, RPC helpers and player
   data. If two modules need the same helper, it moves into Core. A module never reaches into another
   feature module's classes.
   - *Scoped exception (owner-approved 2026-09-12):* `AEGIS_POI` is the shared layer *for POI
     modules only*. `AEGIS_POI_*` modules may require it and register marker roles with it.
     Non-POI modules never depend on it. Until `AEGIS_Core` exists in `aegis-mods`, `AEGIS_POI`
     carries its own minimal logging and settings loading under `AEGIS_POI_*` names; when Core
     ships, a session moves those helpers onto Core and adds the dependency.
5. **No site data in a module.** Coordinates, prices, trader stock, quest text and tuning numbers
   live in `$profile:AEGIS/<Name>/settings.json`.
   - The module writes a file with working defaults on first run if none exists.
   - The file carries a `version` field and is migrated forward in code.
   - Site repos commit only that file, as the override.
6. **Namespaced everything:** classes `AEGIS_<Name>_*` (or `Aegis<Name>*`, matching the module),
   RPC IDs registered through Core, and profile paths under `AEGIS/<Name>/`. Use `modded class` only
   for the vanilla class a module's feature actually changes, and always call `super`.
7. **Client/server split is deliberate.**
   - Anything the client must load (UI, items, models, synced state) ships on the Workshop.
   - Server authority that players should not be able to read goes in a separate
     `AEGIS_<Name>_Server` module, loaded with `-servermod` and never published.
   - Damage, rewards and economy are always decided server-side.
8. **Removal is safe or documented.**
   - Changes to entity persistence (`OnStoreSave`/`OnStoreLoad`) are version-gated.
   - A module that writes entity storage states in its README what happens to a server that drops
     it: no effect, or a required wipe.
9. **Only permission-clear assets.** Every asset source is recorded in the module's `CREDITS.md`.
   Third-party assets without written permission (`dayz-vehicle-sources`,
   `TrulyFreeAssets_Various`) are never packed.
10. **Signed builds, private key never in git.** All modules are signed with one `AEGIS` key pair.
    The `.bikey` is committed under `keys/`. The `.biprivatekey` lives only on the build machine,
    backed up offline, handled like any other secret (`policies/security/secrets_handling.md`).

## Repo layout (`aegis-mods`)

```
aegis-mods/
  CLAUDE.md
  docs/PLAN.md
  keys/AEGIS.bikey
  tools/build.ps1            # build.ps1 <Name> → dist/@AEGIS_<Name>/ (pack + sign)
  tools/check_module.py      # validates rules 2, 3, 5, 6 statically; runs in CI
  mods/
    AEGIS_Core/
      module.json
      config.cpp
      Scripts/3_Game/AEGIS_Core/…   (4_World, 5_Mission as needed)
      workshop/mod.cpp, logo.png, description.md
      README.md  CHANGELOG.md  CREDITS.md
    AEGIS_PvPGuard/
      …
  dist/                      # gitignored build output
```

## Contract: `module.json`

```json
{
  "name": "AEGIS_PvPGuard",
  "title": "AEGIS PvP Guard",
  "version": "0.1.0",
  "side": "workshop",
  "workshopId": null,
  "requires": { "AEGIS_Core": ">=0.1.0" },
  "optional": { "DayZ-Expansion-Core": "reputation integration" },
  "settings": "AEGIS/PvPGuard/settings.json",
  "persistence": "none"
}
```

- `side` is `workshop` or `servermod`.
- `persistence` is `none`, `versioned`, or `wipe-on-remove`.
- `version` is semver. Each release adds a `CHANGELOG.md` entry, and that entry becomes the Workshop
  change note.

## Definition of done for a module release

- [ ] `tools/check_module.py` passes.
- [ ] The module builds and signs with `tools/build.ps1`.
- [ ] Boot test on a clean vanilla mission, with `-mod=` listing only its declared `requires`: no
      script errors in the RPT or script log, and `settings.json` is generated.
- [ ] Boot test with it removed again: the server starts, and the `persistence` claim holds.
- [ ] README says what it does, its settings and its dependencies. CHANGELOG is updated.
- [ ] The site repo's mod tracker pins the Workshop ID and version (a site PR, separate from the
      module PR).

## Where existing work goes

| Today | Becomes | Note |
|---|---|---|
| `P:\AEGIS_HelloWorld` | Import as the pipeline test, then delete after Core boots | Proves build + sign + load |
| `P:\AEGIS_Core` (skills/perks) | `AEGIS_Core` (shared layer) + `AEGIS_Skills` | Split the skill system out of Core (rule 4) |
| `site-chernarus/mods/AEGIS_PvPGuard` (PR #43 merged before this standard) | `aegis-mods/mods/AEGIS_PvPGuard` | An aegis-mods session moves it; the site keeps only `profiles/AEGIS/PvPGuard/settings.json` |
| `P:\AEGIS_Vehicles`, `P:\AEGIS_Aircraft` | `AEGIS_Vehicles`, `AEGIS_Aircraft` | Aircraft keeps `DESIGN.md` as its plan |
| Skin library (core `assets/dayz-skin-library/`, PR #39 merged) | `AEGIS_Skins` (asset module) | Only after rule 9 is checked per texture |
| `AEGIS_Metrics`, `AEGIS_TeddyBear` | Already in `aegis-mods` (PRs #1, #2) | Metrics is loaded on site-chernarus production via `serverMods` (site #50); the upload is tracked in site #48 |
| Vaults, black markets, traders as prefabs | `aegis-poi`: `AEGIS_POI`, `_Trader`, `_BlackMarket`, `_Vault` | Rule 1/4 exception; plan in aegis-poi `docs/PLAN.md` |
| Faction quests, market, reputation bands | Stay Expansion config in the site repo for now | A future `AEGIS_Factions` module owns the standing ledger if Expansion config can't express it |

## Relationship to other repos

- **core:** sync CLI, validators and reusable CI. It may host a reusable `validate-mod.yml`, but not
  mod source. `core/mods/README.md` is superseded by this standard.
- **aegis-poi:** the POI modules only, under the rule 1 and rule 4 exceptions. Same layout, tooling
  and signing key as `aegis-mods`; sites place its prefabs through `$profile:AEGIS/POI/settings.json`.
- **site repos:** server config, mod tracker (Workshop IDs + versions), and module `settings.json`
  overrides.
- **services / claude-agents:** talk to modules only through documented settings files, logs or
  RPC, never by editing mod code.
