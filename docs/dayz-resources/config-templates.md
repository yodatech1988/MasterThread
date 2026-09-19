# terrain_builder config_templates

Source: `DayZ-Resources/tools/dayz_tools/terrain_builder/config_templates/` (read-only). Everything below is what the files show; sizes in bytes.

## Directory tree

```
config_templates/
  data/
    config.cpp                     (77)  CfgPatches stub for the "data" PBO
    ce/                                  Central Economy files (mission-side db)
      areaflags.map            (2,097,176)  binary area-flag grid (see Gaps)
      cfgeconomycore.xml          (933)  CE root classes
      cfgenvironment.xml         (1901)  animal/infected territory -> behavior links
      cfgeventspawns.xml       (40,762)  event spawn positions (5 events, 642 <pos>)
      cfglimitsdefinition.xml     (943)  allowed categories/tags/tier value flags
      cfglimitsdefinitionuser.xml (1099)  combined Tier flag groups
      cfgplayerspawnpoints.xml   (3184)  fresh-spawn params + 43 <pos> bubbles
      cfgrandompresets.xml         (89)  empty <randompresets>
      cfgspawnabletypes.xml       (129)  only a global <damage min=0.3 max=0.7>
      mapclusterproto.xml     (13,631)  38 road/cluster "export" shape names
      mapgroupcluster.xml    (210,869)  2418 <group> placements of cluster names
      mapgroupdirt.xml             (69)  empty <map>
      mapgrouppos.xml        (184,849)  1415 <group> building placements (pos/rpy/a)
      mapgroupproto.xml      (721,672)  244 building loot prototypes
      db/
        economy.xml              (509)  init/load/respawn/save flags per category
        events.xml                (74)  empty <events>
        globals.xml             (1578)  26 <var> tuning values
        types.xml                 (75)  empty <types>
      env/                              8 territory files (zones with x,z,r)
        brownbear_ (1556) domestic_ (2048) north_ (6076) polarbear_ (3337)
        predator_ (4859) south_ (5687) tara_ (5224) zombie_ (10928)  *_territories.xml
  navmesh/config.cpp                (80)  CfgPatches stub for navmesh PBO
  source/
    layers.cfg                     (5100)  terrain layer list + Legend colors
    MapLegend.png                 (32652)  legend image referenced by layers.cfg
  world/config.cpp                 (5742)  CfgPatches + CfgWorlds + CfgWorldList
```

## The three config.cpp files

- `data/config.cpp`: only `CfgPatches > MyCustomMap_data`, `requiredAddons[] = {}`.
- `navmesh/config.cpp`: only `CfgPatches > MyCustomMap_navmesh`, `requiredAddons[] = {}`.
- `world/config.cpp`:
  - `CfgPatches > MyCustomMap`: `units[]`, `weapons[]`, `requiredVersion=0.1`, `requiredAddons = DZ_Data, DZ_Surfaces, DZ_Surfaces_Bliss`, `author="YourName"`, `name="MyCustomMap"`, `url="www.url.com"`.
  - `CfgWorlds`: forward-declares `DefaultLighting`, `CAWorld`, `Chernarusplus: CAWorld { class Grid; }`, then `class MyCustomMap: Chernarusplus`.
  - Key fields: `worldId=2`, `description`, `worldName="\MyCustomMap\world\MyCustomMap.wrp"`, empty `icon/pictureMap/pictureShot`, three `ocean*Material` (all `oceanold_samplemap.emat`), `plateFormat="ML$ - #####"`, `plateLetters`, `longitude=-40`, `latitude=-40`, `startTime="8:30"`, `startDate="01/05/1985"`, `startWeather/Fog`, `forecastWeather/Fog`, `seagullPos`, `centerPosition={2500,2500,300}`, `ilsPosition/ilsDirection/ilsTaxiIn/ilsTaxiOff`, `drawTaxiway`.
  - Sub-classes: `AISpawnerParams` (empty), `OutsideTerrain` (gravel satellite + Layer0), `Grid` (`offsetX=0`, `offsetY=-15360`, Zoom1 step 200, Zoom2 step 2000), `ReplaceObjects`, `Sounds`, `Animation`, `Lighting`, `Subdivision` (Fractal/WhiteNoise), `Ambient`, `Names` (mostly empty), clutter/detail distances, `minTreesInForestSquare=3`, `minRocksInRockSquare=4`.
  - `Navmesh`: `navmeshName` points at vanilla `\DZ\worlds\chernarusplus\navmesh\navmesh.nm`; the custom `\MyCustomMap\navmesh\navmesh.nm` line is commented out. `GenParams`: `tileWidth=50`, cell sizes, `seedPosition={7500,0,7500}`, `Agent` (diameter 0.6, heights, `maxSlope=60`), `Links` with 5 `ZedJump*` and 4 `Fence*` (deer/hen) link classes.
  - `CfgWorldList > class MyCustomMap` (empty).
- Placeholders to replace: every `MyCustomMap` (patch names in all three files, world class, `worldName` path, navmesh path, CfgWorldList), `author`, `name`, `url`, `description`, `worldId`, icon/picture paths, ocean materials, plate settings, lat/long, start date/time/weather, seagull/center/ILS positions, Grid offsets, `seedPosition`.

## source/layers.cfg

- `class Layers`: 25 terrain surface classes (cp_grass, cp_dirt, cp_rock, cp_concrete1/2, cp_broadleaf_dense1/2, cp_broadleaf_sparse1/2, cp_conifer_common1/2, cp_conifer_moss1/2, cp_grass_tall, cp_gravel, en_flowers1-3, en_forest_con/dec, en_grass1/2, en_soil, en_stones, en_stubble, en_tarmac_old). Each has `texture` (`DZ\surfaces\data\terrain\*_ca.paa`) and `material` (`*.rvmat`).
- `class Legend`: `picture="Everglades\source\MapLegend.png"` and `Colors`, mapping each layer name to one RGB triplet (e.g. `cp_grass[] = {{171,12,255}}`). This ties mask-image colors to layers.

## Central Economy files and relationships

- `cfgeconomycore.xml`: declares 7 `rootclass` entries (DefaultWeapon, DefaultMagazine, Inventory_Base, HouseNoDestruct, SurvivorBase and DZ_LightAI with `act="character"`, CarScript with `act="car"`). Defines which class trees CE manages.
- `cfglimitsdefinition.xml`: whitelist of `categories` (10: rifles ... bags), `tags` (9: military ... fishing), empty `usageflags`, `valueflags` Tier1-4. `cfglimitsdefinitionuser.xml` adds combined groups (Tier12, Tier23, Tier34, Tier123, Tier234); also empty `usageflags`.
- `db/types.xml`: the item spawn table; here an empty `<types>`. Items would reference the categories/tags/flags above. `cfgspawnabletypes.xml` (only a global damage range) and `cfgrandompresets.xml` (empty) are the attachment/cargo preset files.
- `db/events.xml`: empty `<events>`; `cfgeventspawns.xml` holds positions for event names: Loot (no pos), StaticMedDrop, ItemWoodenPlanks, VehicleCivilianCars, VehicleTrucks (642 `<pos x z a>` total).
- `db/globals.xml`: 26 `<var type="0">` tunables (e.g. ZombieMaxCount=1600, AnimalMaxCount=200, SpawnInitial=1200, CleanupLifetimeDefault=45).
- `db/economy.xml`: per-category `init/load/respawn/save` flags for dynamic, animals, zombies, vehicles, randoms, custom, building, player.
- `mapgroupproto.xml`: 244 building prototypes (`<group name lootmax>` with `<container>`s (387 total), `<category>`/`<tag>` filters matching cfglimitsdefinition, and `<point pos range height>` loot points). Sample: `land_ala_tower` lootmax 7, container "Ground" lootmax 3, categories tools/clothes, tags civilian/industrial. `<defaults>` set lootmax 10.
- `mapgrouppos.xml`: 1415 placements (`name`, `pos`, `rpy`, `a`) of building groups; names correspond to prototypes (e.g. `land_Mil_Barracks_Round_Polar`, `Land_Container_1Bo`).
- `mapclusterproto.xml` (38 `<export name shape>` entries, e.g. `StoneLoc01` -> `nst\ns\roads\namgrav_0 2000.p3d`) and `mapgroupcluster.xml` (2418 placements of those names, e.g. `StoneLoc06` at `3497 215 6699`): cluster (road-piece) equivalents of proto/pos. `mapgroupdirt.xml` is an empty `<map>`.
- `cfgenvironment.xml`: lists the 8 `env/*_territories.xml` files and links 9 herd types (ZombieTest, Goat, Sheep, RoeDeer, Deer, WildBoar, Wolf, BrownBear, PolarBear) to a `behavior` and a territory file. Territory files hold `<zone name smin smax dmin dmax x z r>` circles (zombie: 102 zones, `InfectedCivil`, first at x=6864.55 z=11311.8 r=150; zone counts: brownbear 14, domestic 19, north 59, polarbear 30, predator 45, south 56, tara 52).
- `cfgplayerspawnpoints.xml`: `<fresh>` with `spawn_params` (min/max distance to infected/player/static), `generator_params` (grid density/size, steepness), and `generator_posbubbles` (43 `<pos>`).
- `areaflags.map`: 2,097,176 bytes; header bytes `00 08 00 00 00 08 00 00 00 32 00 00 00 32 00 00 00 00 00 00`. Reading these as 2048, 2048, 50, 50 is inferred, not documented in the repo.

## Checklist per new map

1. Rename `MyCustomMap` everywhere in `world/config.cpp`, `data/config.cpp`, `navmesh/config.cpp` (patch classes, world class, `worldName`, navmesh path, CfgWorldList).
2. Set `worldId`, author/name/url/description, icon/picture, ocean materials, plate format, lat/long, start date/time/weather.
3. Set map-specific geometry: `centerPosition`, `seagullPos`, ILS/taxi arrays, `Grid.offsetX/offsetY`, navmesh `seedPosition`; point `navmeshName` at the custom navmesh once built.
4. Edit `source/layers.cfg`: keep only layers used; fix `Legend.picture` path (currently `Everglades\...`); replace `MapLegend.png` and matching colors.
5. Regenerate `ce/mapgroupproto/pos/cluster/clusterproto` from the new map's buildings/roads (current content has map-specific coordinates).
6. Fill `db/types.xml`, `db/events.xml` (names should match `cfgeventspawns.xml`), `cfgspawnabletypes.xml`, `cfgrandompresets.xml` as needed.
7. Replace `cfgeventspawns.xml` positions, `cfgplayerspawnpoints.xml` bubbles, and all `env/*_territories.xml` zones with coordinates inside the new map.
8. Replace `areaflags.map` with one matching the new map; review `globals.xml` and `economy.xml` values.

## Gaps / oddities

- `world/config.cpp` inherits `Chernarusplus` and defaults to the vanilla Chernarus navmesh.
- `layers.cfg` Legend picture path says `Everglades\source\MapLegend.png`, not `MyCustomMap`; a leftover from another project.
- `db/types.xml`, `db/events.xml`, `cfgrandompresets.xml`, `mapgroupdirt.xml` are empty shells; `cfgspawnabletypes.xml` has only a damage line. No items would spawn until types.xml is populated.
- `cfgeventspawns.xml` names five events but `events.xml` defines none.
- Proto/pos/cluster, territory and spawn coordinates are populated with concrete values (up to ~x 6864, z 11848) that look like a specific existing map rather than neutral placeholders.
- `usageflags` are empty in both limits files, so any usage flags used by types must be defined by the map maker.
- `cfgspawnabletypes.xml` and `db/types.xml` begin with a UTF-8 BOM (others do not appear to).
- `areaflags.map` format is not documented in these templates.
