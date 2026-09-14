# Workshop mod standard

Every piece of AEGIS gameplay we build ships as a **self-contained Steam Workshop mod**: one
feature, one package, explicit dependencies, defaults that work on any server. A site repo
(`site-chernarus`, future sites such as Deer Isle) *installs and tunes* modules. It never contains
their code.

Modules have three homes, and only three: [`aegis-mods`](https://github.com/yodatech1988/aegis-mods)
for gameplay modules, [`aegis-poi`](https://github.com/yodatech1988/aegis-poi) for prebuilt
points of interest, and [`aegis-pricing`](https://github.com/yodatech1988/aegis-pricing) for
reputation-based trader pricing (rule 1).

The general principle behind this applies to every repo: build in self-contained packages with a
manifest and declared dependencies. For DayZ, that package is a Workshop mod.

## Why

When this standard was written (2026-09-12, morning), AEGIS mod source lived in three places and
none of them could ship:

| Where | What | Problem |
|---|---|---|
| `site-chernarus` `mods/AEGIS_PvPGuard` (PR #43, merged) | PvP damage → reputation | Mod code inside a site repo. A second site would have to copy it. |
| `core/mods/` (empty) and the skin library (core `assets/dayz-skin-library/`, PR #39 merged) | Reserved for mod source | Core is sync CLI + reusable CI. Mod releases would be tied to CI tags. |

Since then (2026-09-12): `aegis-mods` exists and holds `AEGIS_Metrics` and `AEGIS_TeddyBear`;
`aegis-poi` exists for the POI modules (rule 1, its own module home). The `P:\` sources and
`AEGIS_PvPGuard` are still where the table says.

Gameplay written as site config (Expansion JSON, `types.xml`, mission `init.c` script) only works
on the server it was written for. A module built as a Workshop mod works on every AEGIS site and can
be published.

**Where it stands (2026-09-12, evening):** `aegis-mods` exists. `AEGIS_Metrics` (PR #1) and
`AEGIS_TeddyBear` (PR #2) are merged, built, signed and boot-tested with `tools/build.ps1` and
`tools/boot-test.ps1`, so the pipeline is proven. `aegis-poi` exists with its plan merged (PR #1)
and no module code yet. The `P:\` sources are still not imported, `site-chernarus` still carries
`mods/AEGIS_PvPGuard` (site PR #43 merged it into the site repo before this standard existed) and a
stale `mods/AEGIS_TeddyBear` draft, and the skin library was merged into `core` (core PR #39). The
table under "Where existing work goes" is the migration list.

## Rules

1. **Three homes, by kind of module.**
   - Every gameplay module lives in the `aegis-mods` repo under `mods/AEGIS_<Name>/`.
   - Prebuilt points of interest (`AEGIS_POI` and every `AEGIS_POI_<Name>`: traders, black
     markets, vaults) live in the `aegis-poi` repo, with the same layout, `module.json` contract,
     tooling and signing key. The owner chose a separate repo on 2026-09-12 (aegis-poi PR #1).
   - Reputation-based trader pricing (`AEGIS_Pricing`) lives in the `aegis-pricing` repo, same
     layout, `module.json` contract, tooling and signing key. The owner chose a separate repo on
     2026-09-13 (aegis-pricing PR #1), the same call as `aegis-poi`.
   - Site repos and core hold no Enforce Script. A fourth module repo needs an owner decision,
     recorded here.
   - `P:\AEGIS_<Name>` is a directory junction into the repo checkout, so DayZ Tools keeps working
     and git keeps the history.
2. **One module = one feature = one Workshop item.** Each module has one PBO prefix `AEGIS_<Name>`,
   one `CfgPatches` class of the same name, and one `@AEGIS_<Name>` package. Features that can be
   switched on independently are separate modules.
3. **Dependencies are declared, never assumed.** A module may depend only on:
   - `AEGIS_Core` (or `AEGIS_POI`, for POI modules only; rule 4),
   - the vanilla `DZ_*` addons, and
   - third-party mods listed in its `module.json`.

   Each dependency appears in both `requiredAddons[]` and the manifest. Soft integration with an
   optional mod (for example, Expansion reputation) goes behind that mod's own preprocessor define,
   verified in its source (Expansion ships locally only as signed PBOs; check its public GitHub
   source, never memory). The module must still load without it.
4. **`AEGIS_Core` is the only network-wide shared layer:** logging, settings loading, RPC helpers
   and player data. If two modules need the same helper, it moves into Core. A module never reaches
   into another feature module's classes.
   - **Scoped exception:** `AEGIS_POI` is the shared layer *for POI modules only* (prefab loading,
     placement, role registry). `AEGIS_POI_<Name>` modules may require it and register marker
     roles with it. Non-POI modules never depend on it.
   - Until `AEGIS_Core` is imported, a module that needs a helper carries its own minimal copy
     under its own class prefix. When Core ships, a session moves those helpers onto Core and adds
     the dependency.
5. **No site data in a module.** Coordinates, prices, trader stock, quest text and tuning numbers
   live in `$profile:AEGIS/<Name>/settings.json`.
   - The module writes a file with working defaults on first run if none exists.
   - The file carries a `version` field and is migrated forward in code.
   - Site repos commit only that file, as the override.
   - A module with nothing to tune declares `"settings": null` and writes no file.
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
   - Objects a module spawns every boot use explicit persistence flags
     (`ECE_NOPERSISTENCY_WORLD` for fixed structure, `ECE_DYNAMIC_PERSISTENCY` for takeable loot)
     so they never accumulate across restarts. `ECE_NOLIFETIME` alone does not prevent saving.
9. **Only permission-clear assets.** Every asset source is recorded in the module's `CREDITS.md`.
   Third-party assets without written permission (`dayz-vehicle-sources`,
   `TrulyFreeAssets_Various`) are never packed. Every vanilla or Expansion classname and
   preprocessor define a module uses is verified against source or a config dump, never guessed.
10. **Signed builds, private key never in git.** All modules, in both repos, are signed with the one
    `AEGIS_Directive` key pair. The public `keys/AEGIS_Directive.bikey` is committed in each module
    repo, and servers copy it into their `keys/`. The `.biprivatekey` lives only on the build
    machine (`P:\Keys\AEGIS_Directive.biprivatekey`, or wherever `AEGIS_SIGN_KEY` points), backed
    up offline, handled like any other secret (`policies/security/secrets_handling.md`).
11. **Map parity.** Every AEGIS site starts equal (owner decision, 2026-09-12; see
    [`docs/REPOS.md`](../../docs/REPOS.md) "Standing decision"). A module never reads reputation,
    standing or any progression earned on another site, and never gates content on it. `AEGIS_Core`
    ships identically to every site; a site's identity is *which optional modules it installs*, not
    a harder baseline. How an annual Theme Season's mod bundle is packaged is undecided and gets a
    decision doc before anyone builds it.
12. **No player data in git.** Module profile output (metrics, ledgers, anything holding player
    names or Steam IDs) is never committed by a module repo or a site repo. Site sync tooling
    ignores it explicitly.

## Repo layout (`aegis-mods` and `aegis-poi`)

Both repos use `master` as the default branch and share this shape:

```
aegis-mods/
  CLAUDE.md  README.md  CONTRIBUTING.md
  docs/PLAN.md
  keys/AEGIS_Directive.bikey
  tools/build.ps1            # build.ps1 <Name> [-Deploy <server dir>] -> dist/@AEGIS_<Name>/ (pack + sign)
  tools/boot-test.ps1        # boot-test.ps1 <Name> [-KeepRunning] [-ConfigOnly]: builds, deploys, boots the local server
  tools/check_module.py      # validates rules 2, 3, 5, 6 statically; runs in CI (aegis-poi Session 1 writes it first, then aegis-mods copies it)
  scripts/setup-branch-protection.sh
  mods/
    AEGIS_Core/
      module.json
      config.cpp
      Scripts/3_Game/AEGIS_Core/...   (4_World, 5_Mission as needed)
      workshop/mod.cpp, logo.png, description.md
      tools/                  # module-specific helpers (texture generators, report scripts)
      README.md  CHANGELOG.md  CREDITS.md
    AEGIS_Metrics/
      ...
  dist/                      # gitignored build output
```

`<Name>` passed to the tools omits the prefix: `Metrics`, not `AEGIS_Metrics`.

## Contract: `module.json`

```json
{
  "name": "AEGIS_PvPGuard",
  "title": "AEGIS PvP Guard",
  "version": "0.1.0",
  "side": "workshop",
  "workshopId": null,
  "requires": { "AEGIS_Core": ">=0.1.0", "DayZ-Expansion-Hardline": "*" },
  "optional": { "DayZ-Expansion-Core": "reputation integration" },
  "settings": "AEGIS/PvPGuard/settings.json",
  "persistence": "none"
}
```

- `side` is `workshop` or `servermod`.
- `requires` values are semver ranges; `"*"` means any version. `optional` values are a short
  description of what the integration adds.
- `settings` is the profile path, or `null` for a module with nothing to tune (rule 5).
- `persistence` is `none`, `versioned`, or `wipe-on-remove`.
- `version` is semver. Each release adds a `CHANGELOG.md` entry, and that entry becomes the Workshop
  change note. Releases are tagged `AEGIS_<Name>-v<version>`.

## Definition of done for a module release

- [ ] `tools/check_module.py` passes (until it exists, the reviewer checks rules 2, 3, 5 and 6 by hand
      and says so in the PR).
- [ ] The module builds and signs with `tools/build.ps1`.
- [ ] Boot test on a clean vanilla mission, with `-mod=` listing only its declared `requires`: no
      script errors (`(E)`) in the RPT or script log, and `settings.json` is generated.
      `tools/boot-test.ps1 <Name>` does this; a config-only module with no script log line uses
      `-ConfigOnly` plus a throwaway `-serverMod` that spawns its classes and logs the result.
- [ ] Boot test with it removed again: the server starts, and the `persistence` claim holds. A module
      that spawns objects also shows equal object counts after two restarts, including one after a
      player has handled the spawned objects.
- [ ] README says what it does, its settings and its dependencies. CHANGELOG is updated.
- [ ] The site repo's mod tracker pins the Workshop ID and version (a site PR, separate from the
      module PR). An unpublished module is pinned by its git tag and loaded from `dist/`.

## Where existing work goes

| Today | Becomes | State (2026-09-12) |
|---|---|---|
| `P:\AEGIS_HelloWorld` | Delete | `AEGIS_Metrics` proved build + sign + load; HelloWorld has no further use |
| `P:\AEGIS_Core` (skills/perks) | `aegis-mods` `AEGIS_Core` (shared layer) + `AEGIS_Skills`, `AEGIS_Medicine`, `AEGIS_StartScreen` | Not imported and won't be: 4 of its 8 files are zeroed on disk (checked 2026-09-13). Rebuilt clean-room from the design, aegis-mods `docs/PLAN.md` Sessions 1–11 (aegis-mods #15) |
| `P:\AEGIS_Metrics` | `aegis-mods` `AEGIS_Metrics` | Done (PRs #1, #3); junction in place. Site override `server/profiles/AEGIS/Metrics/settings.json`; production install tracked in site-chernarus #48, loaded via `serverMods` (site #50) |
| `site-chernarus` `mods/AEGIS_PvPGuard` (site PR #43, merged) | `aegis-mods` `AEGIS_PvPGuard` | Not migrated. The site keeps only the override, renamed from `server/profiles/AEGIS/PvPGuardSettings.json` to `AEGIS/PvPGuard/settings.json` (rule 5) |
| `site-chernarus` `mods/AEGIS_TeddyBear` (draft) | Delete | Superseded by `aegis-mods` `AEGIS_TeddyBear` (PR #2). Go-live checklist: site-chernarus #52 |
| `P:\AEGIS_Vehicles`, `P:\AEGIS_Aircraft` | `aegis-mods` `AEGIS_Vehicles`, `AEGIS_Aircraft` | Not imported. Aircraft keeps `DESIGN.md` as its plan |
| Skin library (core PR #39, merged into `core` as `assets/dayz-skin-library/`) | `aegis-mods` `AEGIS_Skins` (asset module) | Staged in core; moves only after rule 9 is checked per texture |
| Traders, black markets, vaults as site config | `aegis-poi` `AEGIS_POI`, `_Trader`, `_BlackMarket`, `_Vault` | Plan merged (aegis-poi PR #1, Sessions 1–6); no code yet |
| Faction quests, market, reputation bands | Stay Expansion config in the site repo for now | A future `AEGIS_Factions` module owns the standing ledger if Expansion config can't express it |

## Relationship to other repos

- **core:** sync CLI, validators and reusable CI. It may host a reusable `validate-mod.yml`, but not
  mod source. `core/mods/README.md` is superseded by this standard; the skin library merged there is
  staging for `AEGIS_Skins`, not a third module home.
- **site repos:** server config, mod tracker (Workshop IDs, versions or tags), and module
  `settings.json` overrides. A site PR that adds Enforce Script is redirected to `aegis-mods` or
  `aegis-poi`.
- **aegis-poi:** POI modules only, under rule 1 (its own module home) and the rule 4 shared-layer
  exception. Shares this standard, the `module.json` contract, the tools and the signing key with
  `aegis-mods`; sites place its prefabs through `$profile:AEGIS/POI/settings.json`.
- **aegis-pricing:** `AEGIS_Pricing*` modules only, under rule 1 (its own module home). Shares
  this standard, the `module.json` contract, the tools and the signing key with `aegis-mods`; no
  rule 4 exception, since `AEGIS_Pricing` is not a shared layer for other modules. Sites tune it
  through `$profile:AEGIS/Pricing/settings.json`.
- **services / claude-agents:** talk to modules only through documented settings files, logs or
  RPC, never by editing mod code.
