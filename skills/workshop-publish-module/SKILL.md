---
name: workshop-publish-module
description: Use when a `"side": "workshop"` module in aegis-mods (or aegis-poi / aegis-pricing, which share the same tooling and module.json contract) is ready to go to the Steam Workshop for the first time, or needs a version-bump republish — carries the module through boot-test, art/description review, build and staged private publish, then hands the actual visibility-changing/steamcmd-login step to the owner and finishes the post-publish bookkeeping.
---

# workshop-publish-module

## When to use this

- A workshop-side AEGIS module (`mods/AEGIS_<Name>/module.json` has `"side": "workshop"`) has
  passed its definition-of-done checklist and is ready to publish for the first time
  (`workshopId` is `null`).
- An already-published module has a new version to ship (`workshopId` is set, `CHANGELOG.md` has
  a new entry).
- Not for a `"side": "servermod"` module — those are never published
  (`docs/WORKSHOP_PUBLISHING.md`, `tools/publish.ps1` itself throws on this).

## Procedure

1. **Confirm the module is workshop-side and locate it.** Read `mods/AEGIS_<Name>/module.json`.
   If `side` is `servermod`, stop — this module is never published.

2. **Boot-test clean.** Dispatch the `mod-boot-test-runner` agent (`docs/AGENTS.md`) for
   `<Name>` — it wraps `tools/boot-test.ps1`, refuses while the owner's DayZ client is running,
   and reports PASS/FAIL from the script log. This skill does not itself run
   `boot-test.ps1`, and it is not a boot-test skill in its own right — `boot-test` was reviewed
   and explicitly **not** approved as a standalone skill (`skills/README.md` "Not approved for
   this batch"); this step exists only to gate publish readiness on an existing agent's result,
   not to reimplement it.

3. **Replace the placeholder logo.** `workshop/logo.png` is auto-generated and marked
   PLACEHOLDER for every module until replaced (`docs/WORKSHOP_PUBLISHING.md`). Confirm real art
   (512x512+, png/jpg/gif, under 1MB) is in place before continuing. If it's still the
   placeholder, stop and say so — this is not something the skill can source itself.

4. **Review `workshop/description.md` as a player would.** Read it end to end; confirm it states
   any `requires`/`optional` dependency from `module.json` in prose (Workshop has no native
   "requires" field for non-Bohemia mods — `docs/WORKSHOP_PUBLISHING.md` "Dependencies between
   Workshop items"), since that's the actual page text a subscriber sees.

5. **Run the readiness check.** Dispatch the `workshop-publish-preflight` agent (`docs/AGENTS.md`,
   also present per-repo under `.claude/agents/`) for `<Name>`. It is entirely read-only and
   never invokes `publish.ps1`/steamcmd itself — it reports module.json validity, build output,
   logo/description presence, and whether this run creates a NEW Workshop item. Do not proceed
   past a `NOT READY` verdict; fix what it flags and re-run it.

6. **Build.**
   ```
   .\tools\build.ps1 <Name>
   ```
   Packs and signs `dist\@AEGIS_<Name>\`, copying `workshop\mod.cpp` and `workshop\logo.png` into
   the package root.

7. **Stop here and hand off to the owner for the actual publish step.** `tools/publish.ps1` is
   explicitly an **owner-run** tool: `aegis-mods/CLAUDE.md` states it directly ("Publish a
   workshop-side module to Steam: ... (owner-run, needs an interactive steamcmd login)"), and
   `docs/WORKSHOP_PUBLISHING.md` says the same ("Because of step 3 [interactive steamcmd login],
   `tools/publish.ps1` is an owner-run tool - it is not something a fully unattended agent
   session can complete end to end"). No standard found anywhere in `aegis-mods`, `aegis-poi`, or
   `aegis-pricing` overrides this for any visibility level, including `private` — steamcmd's own
   login/Guard prompt is the blocker even before visibility is considered. So: prepare the exact
   command (module name, `-SteamUser`, `-Visibility private` for a first run or the current
   value for a version bump, `-ChangeNote` text pulled verbatim from the new `CHANGELOG.md`
   entry for a version bump) and hand it to the owner via the `owner-click` skill as a
   `GitHub\AEGIS-Publish-<Name>.cmd` that shows the exact command and gates on typed `YES`. Do
   not run `publish.ps1`, `SteamKey.ps1 -Run`, or `steamcmd.exe` yourself, and never read, request,
   or print a Steam password, Guard code, or the contents of
   `%APPDATA%\AEGIS\steam-publish.clixml`.

8. **First publish only: after the owner reports the run, read back (never guess) the printed
   `PublishedFileId`** from the run's own output (ask the owner to paste it, or read the `.cmd`
   run's saved console output if one exists) and set it into `module.json`'s `"workshopId"`.
   Commit this together with the `README.md`/`CHANGELOG.md` updates the definition-of-done
   checklist requires (`standards/dayz/workshop_mod_standard.md` "Definition of done for a module
   release"), through the normal PR flow (`land-pr`).

9. **Version bump only:** confirm `-ChangeNote` matched the new `CHANGELOG.md` entry text before
   the owner ran it (`module.json`'s contract: "each release adds a CHANGELOG.md entry, and that
   entry becomes the Workshop change note").

10. **Sanity-check the private listing**, then flip it public. Ask the owner to check the name,
    picture, description, and dependencies in the Steam Workshop web UI. Flipping to
    `-Visibility public` is the same owner-run `publish.ps1` step (or an edit directly in the
    Steam Workshop web UI, per `docs/WORKSHOP_PUBLISHING.md`) — route it through `owner-click`
    exactly as step 7, never run it yourself.

11. **Update the installing site's mod tracker.** For `aegis-mods`/`aegis-poi`/`aegis-pricing`
    modules installed on Chernarus, that's `site-chernarus` `docs/mods/README.md` (the site's mod
    status board; confirmed present on `origin/main`). Pin the Workshop ID and version there, as a
    separate PR in the site repo from the module PR (`workshop_mod_standard.md`'s definition of
    done: "The site repo's mod tracker pins the Workshop ID and version (a site PR, separate from
    the module PR)"). Use `dispatch-lane`/`land-pr` for that PR like any other. TODO: needs owner
    input if a module targets a site other than Chernarus — no other site's mod-tracker path was
    verified.

## Stop conditions

- `module.json` `side` is `servermod` — never publish.
- `mod-boot-test-runner` reports anything other than PASS.
- `workshop/logo.png` is still the placeholder.
- `workshop-publish-preflight` reports NOT READY.
- Any step would require running `tools/publish.ps1`, `tools/SteamKey.ps1 -Run`, or
  `steamcmd.exe` directly, at any `-Visibility` value, first publish or version bump — always
  route to `owner-click` instead.
- Any step would require reading, typing, or printing a Steam password, Guard code, or the
  contents of `%APPDATA%\AEGIS\steam-publish.clixml` — never do this; the owner's click-file
  sources its own credential inside its own process per `owner-click`'s rules.
- The `PublishedFileId` for a first publish isn't available from the owner's own report — don't
  guess or invent one.

## Grounded in

- `aegis-mods` `origin/master:docs/WORKSHOP_PUBLISHING.md` — full publishing procedure, owner-run
  rationale, one-time setup, visibility/ChangeNote rules, "Order of operations" and "Publishing
  (or updating) one module" sections.
- `aegis-mods` `origin/master:CLAUDE.md` — restates `publish.ps1` as owner-run.
- `aegis-mods` `origin/master:tools/publish.ps1`, `tools/build.ps1`, `tools/SteamKey.ps1`,
  `tools/boot-test.ps1` — confirmed real, read for exact flags/params.
- `MasterThread` `origin/main:standards/dayz/workshop_mod_standard.md` — `module.json` contract,
  repo layout, "Definition of done for a module release" (site mod-tracker PR requirement).
- `MasterThread` `origin/main:skills/land-pr/SKILL.md`, `skills/owner-click/SKILL.md`,
  `skills/dispatch-lane/SKILL.md`, `skills/README.md` (batch-1 shape, and the "Not approved for
  this batch" list confirming `boot-test` is not its own skill).
- `docs/AGENTS.md` (`~/.claude/agents/` roster, mirrored into repo `.claude/agents/`) —
  `workshop-publish-preflight` and `mod-boot-test-runner` agent definitions, read directly from
  `_wt-aegis-mods-session8-pharmacy/.claude/agents/workshop-publish-preflight.md` and
  `mod-boot-test-runner.md` to confirm their real behavior and tool restrictions.
- `site-chernarus` `origin/main:docs/mods/README.md` — confirmed as the real installing-site mod
  tracker referenced in step 11.

## Dropped from the candidate

- The candidate's step 5 ("first publish: copy printed PublishedFileId into module.json
  workshopId, commit with README/CHANGELOG") is kept, but note the printed ID can only come from
  the owner's own run (step 7 of this skill), never from the session itself — the candidate did
  not make that ordering explicit.
- No `boot-test` skill was created, per `skills/README.md`'s explicit non-approval; step 2 only
  calls the existing `mod-boot-test-runner` agent.
