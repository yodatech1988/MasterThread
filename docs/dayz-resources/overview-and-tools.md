# DayZ-Resources: overview and tools

Source: `C:\Users\yoda_\GitHub\DayZ-Resources` (read-only). Terrain Builder and Terrain Processor docs are covered elsewhere and only referenced here. All statements come from the source files named in each section.

## 1. What the repo is and its structure

Source: `README.md`.

DayZ-Resources is a documentation repo of guides and tool write-ups for DayZ modding: map creation, mod creation, and other DayZ projects. It contains no code; it is Markdown plus screenshots.

Layout (verified on disk):

- `README.md` - hub page with table of contents
- `DayZ_Resources_TODO_List.md` - pending doc tasks
- `LICENSE` (GPL-3.0 text) and `LICENSE-CC-BY-SA-4.0.md`
- `tools/<tool>/<Tool>_Overview.md` plus an `images/` folder per tool:
  - `tools/notepad_plus_plus/notepad_plus_plus.md`
  - `tools/blender/blender.md`
  - `tools/autodesk_fusion_360/Autodesk_Fusion_360_Overview.md`
  - `tools/gitbash/gitbash_overview.md`
  - `tools/dayz_tools/DayZ_Tools_Overview.md` (plus `terrain_builder/` and `terrain_processor/` subfolders, out of scope here)
  - `tools/mikero_tools/Mikero_Tools_Overview.md`
  - `tools/l3dt/L3DT_Overview.md`
  - `tools/qgis/QGIS_Overview.md` and `tools/qgis/OpenTopography_Overview.md`

## 2. Intended workflow as the README describes it

Source: `README.md`. Most sub-topics below are bullets only; the README lists them without linking to a page (see section 8).

**Required apps:** Notepad++, Blender, Autodesk Fusion (free Personal Use version), Git Bash, DayZ Tools, PBO Manager. **Optional:** Visual Studio 2022 Community, Substance Painter, World Creator 2.0, MindMeister.

**Map creation from scratch:** folder information; map signs and landmarks; special buildings and texture details; lakes and waterways; roadways ("TP").

**Map creation from satellite images:** extracting game data; QGIS and L3DT Pro for GIS terrain mapping; "Map Frame Issue" (map frames and scaling); DayZ Offline Mode for local testing before upload.

**Mod creation:** object building (DayZ Editor, Terrain Builder, Adding Objects) and 3D modeling/asset creation (sources for 3D models, asset modeling, "Dev As A Team - DayZ").

**P drive setup:** the README has a "Setting Up the P Drive" table-of-contents entry but no such section in the body. The actual steps are in `tools/dayz_tools/DayZ_Tools_Overview.md` and `tools/mikero_tools/Mikero_Tools_Overview.md` (sections 3.5 and 3.6 below).

**Implied tool order from the tool docs:** install DayZ Tools, mount the P drive, run Mikero tools (`dayz2p`), then QGIS + Game Terrain Tools with OpenTopography data, then Terrain Builder (`tools/qgis/QGIS_Overview.md`, `tools/mikero_tools/Mikero_Tools_Overview.md`).

**Contributing** (README): fork, branch, commit, push, open a PR.

## 3. Tools

### 3.1 Notepad++
Source: `tools/notepad_plus_plus/notepad_plus_plus.md`.
- Purpose: free text editor (README: for editing configuration files). Features listed: syntax highlighting, folding, multi-view, macros, regex search across files, plugins.
- Setup: download from notepad-plus-plus.org/downloads, choose 32- or 64-bit installer, run it. Windows 7 to 11; limited Wine support on Linux. Optional plugins via Plugins > Plugin Admin (NPP FTP, Compare, XML Tools).
- Gotchas: none stated. The doc is generic and has no DayZ-specific content.

### 3.2 Blender
Source: `tools/blender/blender.md`.
- Purpose: free 3D modeling, sculpting, UV mapping, animation; export FBX/OBJ for modding tools. BlenderGIS add-on suggested for importing real-world terrain data.
- Setup: download from blender.org, run installer. Recommended: 64-bit quad-core, 16 GB RAM, 4 GB VRAM GPU, 500 MB disk.
- Gotchas: none stated. Links six community YouTube tutorials (TWE4KS, AVERAGEsouls, GamingwithJC, Phlanka x2, Spurgle's Playground). The doc claims Blender terrain sculpts can be imported into Terrain Builder but gives no procedure.

### 3.3 Autodesk Fusion 360
Source: `tools/autodesk_fusion_360/Autodesk_Fusion_360_Overview.md`.
- Purpose: parametric CAD alternative to Blender for asset modeling; export `.fbx` or `.obj` for DayZ Tools; refine in Object Builder.
- Setup: autodesk.com/products/fusion-360/personal, create an Autodesk account, pick the Personal Use license, run installer. Minimum: Windows 10 64-bit or macOS 10.13+, 4 GB RAM (8 GB recommended), DirectX 11 GPU, 3 GB disk.
- Gotchas: free license is non-commercial only; commercial use needs a subscription. Cloud-based, account required. Export troubleshooting is missing (the TODO list asks for it).

### 3.4 Git Bash
Source: `tools/gitbash/gitbash_overview.md`.
- Purpose: Git plus Bash shell on Windows for cloning, committing, pushing, and branching on GitHub.
- Setup: download from gitforwindows.org, accept recommended installer settings; 4 GB RAM suggested. Covers clone/add/commit/push/pull/branch commands, aliases, SSH key setup, two external cheat-sheet gists by Ezenity.
- Gotchas: the example workflow creates branch `feature/new` but pushes `feature-new` (inconsistent). The file ends with leftover generator-style meta text ("Explanation of Each Section", "Let me know if you need any more customization!").

### 3.5 DayZ Tools (overview)
Source: `tools/dayz_tools/DayZ_Tools_Overview.md`.
- Purpose: Steam-distributed suite for building, editing, and publishing DayZ content. Components: Workbench (Enfusion core, scripting, particles, UI), Addon Builder (PBO packing; the doc recommends pboProject instead for better errors), Publisher (Steam Workshop), Terrain Builder (terrain and objects, previews in Bulldozer), Object Builder (3D models; also exports .p3d to .fbx/.obj), Economy Editor (loot/zombie/vehicle spawns; usually last step of map creation).
- Requirements: Windows 10+ only (no Mac/Linux), quad-core 3.0 GHz, 8 GB RAM (16 GB recommended), DX11 GPU 2 GB VRAM, 20 GB disk, Visual C++ Redistributable 2019.
- Install: must own DayZ (Steam app 221100). In Steam Library, set the Games filter to Tools, find DayZ Tools (app 830640), Install.
- Alternate drive: DayZ and DayZ Tools must be on the same drive; add the drive as a Steam Library Folder (Steam > Settings > Storage); set paths in DayZ Tools Settings > Configure Path; check drive Security permissions; SSD preferred.
- P drive setup: in DayZ Tools, Tools > Dismount Drive P if already mounted, then Tools > Workbench to mount; verify P: appears in File Explorer. The P drive is described as a sandbox so original game files are untouched.
- Troubleshooting listed: tools not launching (update VC++ redistributables), missing textures in Bulldozer (check paths), Bulldozer crashes (low memory; close apps or raise virtual memory), PBO conversion issues (avoid non-ASCII characters and spaces in filenames).
- Discord servers listed (links in the source file): World Design Resources (ike_0zzy), Modding Shed of Hunterz, DAYZ, DZ Academy (Big Grampa), Longtime Squad.

### 3.6 Mikero tools
Source: `tools/mikero_tools/Mikero_Tools_Overview.md`.
- Purpose: PBO/config utilities: Dayz2p (extracts game PBOs onto P:), DeRap (rap to text), MakePbo, Eliteness (view PBOs), ExtractPbo, pboProject (packs PBOs; preferred over Addon Builder for its more detailed error log), Rapify (text back to rap).
- Prerequisites: DayZ Tools installed and P: mounted; DayZ Tools shows Workdrive status `Y`.
- Setup: download the tools, run the Mikero AIO Installer, click "Check again for updates". In DayZ Tools settings set the Project Drive path and the Game Directory path (doc examples `D:\DayZ Projects` and `D:\Steam\steamapps\common\DayZ`; the doc says yours will likely be on C:), and set "Automatic mount of the Project Drive" to Startup of the Tools, then Apply. Tools install to `C:\Program Files (x86)\Mikero\DePboTools\bin`. Run `dayz2p.cmd` to populate P:.
- Gotchas: if dayz2p errors, launch the game from the DayZ Launcher for about 30 seconds and close it. If prompted "P: does not exist. Do you wish to make one? [Y,N]?" press Y; it can take up to an hour and must not be interrupted.
- The download link is a placeholder (see section 8).

### 3.7 L3DT Pro
Source: `tools/l3dt/L3DT_Overview.md`.
- Purpose: Large 3D Terrain Generator Pro, generating heightmaps, texture maps, and attribute maps.
- Setup: download the "Latest Development Build" for the Pro edition from the bundysoft.com professional downloads page. The doc gives a shared username and password for that page; they are deliberately not reproduced here.
- Exports, all saved to `MapName/source`: Attributes (satellite) map as `satmap.bmp` (BMP); Terrain Normals as `normalmap.bmp` (BMP); Heightfield as `heightmap.asc` (ASC); Design Map (no export format or filename given).
- Gotchas: contains a `TODO: Add additional youtube tutorials` marker. Only one tutorial link is given. Very thin: no install or usage steps beyond download and export naming.

### 3.8 QGIS
Source: `tools/qgis/QGIS_Overview.md`.
- Purpose: free GIS app used with the Game Terrain Tools (GTT) plugin to produce satmap, heightmap, mask, and road/shape exports for Terrain Builder.
- Setup: install the QGIS Long Term Release (example 3.34 LTR) from qgis.org. Prerequisites: DayZ Tools then Mikero tools set up first. Download `gtt.zip` from the GTT GitLab wiki (gitlab.com/Adanteh/qgis-game-terrains), then Plugins > Manage and Install Plugins > Install from ZIP.
- Configuration (GTT panel, Engine = Arma): Mark Area 4096 m; Satmap zoom 17, resolution -1 px, tiling 4096 px (unchecked); Mask OSM-based; Heightmap source srtm at 4096 px, vertical scale and "lower terrain to 0m" unchecked.
- Procedure: drag the OpenTopography `.tif` into QGIS; save the QGIS project on the P drive in a folder named `QGIS` (else later errors); Add satmap (creates `gtt_satmap` layer); rename the imported TIF layer to `gtt_heightmap`; Mark Area; export Mask, Heightmap, Satmap one at a time (only one Export box checked at a time, uncheck after); for roads, click Download in the Roads tab (creates `osm_multipolygons` and `osm_lines`), tick wanted features, export Roads and Shapes. Output lands in `QGIS > gtt_export` for use in Terrain Builder.
- Gotchas: do not exceed 20480 m map size; heightmap and satmap resolutions must match; Engine Arma versus Enfusion can throw errors on large maps; a login popup means create a free account for the elevation download; the roads export needs the other export boxes unchecked.

### 3.9 OpenTopography
Source: `tools/qgis/OpenTopography_Overview.md`.
- Purpose: source of elevation (DEM) data for heightmaps, paired with Google Earth for choosing the area (free sign-in needed for Google Earth).
- Steps: Data Catalog, search NASA, Global & Regional DEM tab; set the map to Hybrid; SELECT A REGION; choose GeoTIFF output; optionally enable hillshade and visualizations; give a job description (map name) and an email address (required to submit); Submit; download the zipped "DEM Results", unzip (WinRAR or 7-Zip) to get a `.tif` for QGIS.
- Size guidance: at least 5 km^2; Chernarus is 225 km^2 and Banov 256 km^2; the doc says larger maps "start to see issues". Include a buffer for edits.
- Tips: KML/KMZ polygon import from Google Earth; 30 m DEM is usually sufficient (10 m if available); QGIS raster calculator, merging, and smoothing; OpenStreetMap overlays for roads.
- Gotchas: the doc's ~256 km^2 guidance and the QGIS doc's 20480 m ceiling are different figures and are not reconciled.

## 4. TODO list contents

Source: `DayZ_Resources_TODO_List.md`. Pending tasks:
1. Create additional pages: a PBO Manager overview (setup and DayZ modding use, linked from General Resources and Custom Mod Creation); a guide on "TP missing Fields" (install over the standard version and where to download it).
2. Add troubleshooting sections: more detail on P drive mounting in the DayZ Tools Overview; `.fbx`/`.obj` export issues in the Fusion 360 Overview.
3. (numbered 6 in the file) Link Discord servers for help in General Resources, kept consistent across pages.

The numbering skips from 2 to 6.

## 5. License summary

Sources: `README.md`, `LICENSE`, `LICENSE-CC-BY-SA-4.0.md`.
- GPL-3.0 (file `LICENSE`, "GNU General Public License Version 3, 29 June 2007"): applies to code resources (scripts, tools, code files) per the README.
- CC BY-SA 4.0 (file `LICENSE-CC-BY-SA-4.0.md`): applies to documentation, images, and other non-code resources.
- The repo contains only Markdown and images, so effectively CC BY-SA 4.0 applies to everything present. No copyright holder or year is stated in the README.

## 6. Local link verification (README.md)

| Link | Resolves? |
|---|---|
| /tools/notepad_plus_plus/notepad_plus_plus.md | yes |
| /tools/blender/blender.md | yes |
| /tools/gitbash/gitbash_overview.md | yes |
| /tools/dayz_tools/DayZ_Tools_Overview.md | yes |
| /tools/qgis/QGIS_Overview.md | yes |
| /tools/l3dt/L3DT_Overview.md | yes |
| /tools/dayz_tools/terrain_builder/Terrain_Builder_Overview.md | yes |
| /tools/dayz_tools/terrain_builder/Add_Objects.md | yes |
| LICENSE.md | NO (file is named `LICENSE`) |
| LICENSE-CC-BY-SA-4.0.md | yes |

Links inside tool docs, checked: Mikero to DayZ Tools and back (ok); QGIS to OpenTopography, Mikero, DayZ Tools and `../dayz_tools/terrain_builder/Terrain_Builder_Overview.md` (all ok); Fusion 360 to Blender and DayZ Tools (ok). Root-absolute links (leading `/`) work on GitHub but not in a plain filesystem viewer.

## 7. Gaps / unclear / broken links

- Broken: README links `LICENSE.md`, but the file is `LICENSE`.
- README table of contents lists "Setting Up the P Drive" but there is no matching section body.
- Many README bullets have no page and no link: PBO Manager, Folder Information, Map Signs and Landmarks, Special Buildings and Texture Details, Lakes & Waterways, Roadways (TP), Extracting Game Data, Map Frame Issue, DayZ Offline Mode, DayZ Editor, Sources for 3D Models, Asset Modeling, Dev As A Team - DayZ. The "Map creation from scratch" section is therefore only a list of titles.
- README links Fusion 360 to an external Autodesk URL rather than to the local `tools/autodesk_fusion_360/` page (which exists). OpenTopography and Mikero tools have no README link.
- Mikero doc download link is a placeholder: `https://mikero/download-link-example.com`.
- L3DT doc publishes a shared username and password for a third-party download page in a public repo. Treat as exposed and possibly stale; do not copy elsewhere.
- L3DT doc has a `TODO` for more tutorials, no setup or usage detail, and no export spec for the Design Map.
- Git Bash doc contains leftover generator meta text and a branch-name inconsistency (`feature/new` versus `feature-new`).
- QGIS doc has typos and a stray "]" in the GTT line. It says Engine `Arma` is "not definitive" without guidance. Its settings show Mark Area 4096 m while the text describes a 2048 default and 20480 max; these are not reconciled.
- Blender and Notepad++ docs are generic (no DayZ-specific config, export settings, or plugin lists).
- Fusion 360 doc says `.fbx`/`.obj` are "compatible with DayZ Tools" with no import steps; the TODO acknowledges missing troubleshooting.
- Typos: README "Can you the `Personal Use` version"; TODO "versionadn". TODO numbering skips 3-5.
- Version-specific facts (QGIS 3.34 LTR, Windows 7/8.1 for Notepad++, VC++ 2019) may be dated; no version/date metadata in the docs.
- Not checked: all external URLs (including Discord invites, which may expire), whether image files referenced in tool docs exist, and the Terrain Builder/Processor docs (out of scope).
