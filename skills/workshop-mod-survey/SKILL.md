---
name: workshop-mod-survey
description: Use when a session needs the update status (title, last-updated time, file size) of a batch of DayZ Steam Workshop mod IDs — replaces hand-rolling the same GetPublishedFileDetails curl/POST call every research pass, since scraping the Workshop page itself is rate-limited/blocked.
---

# workshop-mod-survey

## When to use this

- Before a research or "what changed" pass across the AEGIS mod stack, instead of re-deriving the
  `GetPublishedFileDetails` call from scratch or attempting to fetch `steamcommunity.com/sharedfiles/
  filedetails` pages (client-side rate-limited — this is exactly the stall pattern
  `steam-workshop-research-method-2026-09-16.md` documents).
- When someone asks "has mod X updated since we last checked" for one or more Workshop IDs.
- As a fact-gathering input to a separate decision about whether to actually update an installed
  mod — this skill only reports what Steam says; it never decides to update, and never touches a
  live site.

**Not for:** reviewing a brand-new mod/content idea for implementation (build-vs-adopt, item-count
budget, server impact) — that is the *mod-review* protocol, scoped in `aegis-mods`
`docs/MOD_REVIEW_PROTOCOL.md` and explicitly **not approved** as a Tier-1 skill
(`skills/README.md` "Not approved for this batch"). This skill is narrower and different in kind:
it reports a timestamp/size diff on IDs that already exist, never a content-direction judgment.

## Procedure

1. **Get the ID list.** There is no single consolidated cross-site mod-ID list in this estate.
   Default source: `site-chernarus` `docs/mods/README.md`'s "Installed" table (read from
   `origin/main`, last reconciled 2026-09-11 there) — 20 currently installed Workshop IDs with names (a 21st row, BallerZ Teddys `3027721512`, is marked Cut 2026-09-11; exclude it), e.g. Dabs
   Framework `2545327648`, CF `1559212036`. If the survey is for a different site (badlands, a
   planned/not-yet-installed tier, etc.), use that site's own mod-tracker doc or an explicit
   ID list the caller supplies — do not reuse Chernarus's list for another site.
   **TODO: needs owner input** — whether/where a single cross-site canonical ID list should live
   (e.g. a shared doc or Fleet Status collection) so this step stops depending on picking the right
   site doc by hand.

2. **Query Steam's public API — no key, no login.** One read-only POST per batch (Steam accepts
   many IDs in one call):

   ```
   curl -s -X POST https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/ \
     -d itemcount=<N> -d publishedfileids[0]=<id0> -d publishedfileids[1]=<id1> ...
   ```

   Or use the bundled helper for the same call plus parsing:

   ```
   powershell -File scripts\query-mod-updates.ps1 -Ids 2545327648,1559212036 -OutFile snapshot.json
   ```

   Verified live during this build: both fields and endpoint respond correctly with no
   authentication. Never add a Steam API key or any credential to this call or the script.

3. **Parse per `steam-workshop-research-method-2026-09-16.md`'s three traps:**
   - Read `subscriptions`, not `views`, for popularity.
   - Confirm `consumer_app_id == 221100` (DayZ) for every ID — a generic Workshop ID can belong to
     a different game. Drop/flag any result where it isn't.
   - Treat a "removed"/`banned` flag as a false positive unless paired with a stronger signal
     (explicit creator-only visibility, or the API returning `result` code 9 for genuine absence).

4. **Diff against the last survey.** Save this run's parsed rows (the helper's `-OutFile`) to a
   dated snapshot; if a prior snapshot for the same ID set exists, compare `time_updated` per ID
   and report which IDs moved forward since then. If no prior snapshot can be found, say so
   explicitly and report this run as the new baseline — never claim "no updates" when there was
   nothing to diff against. Where to persist snapshots long-term (a repo path vs. a Fleet Status
   collection) is unscoped here — **TODO: needs owner input**; until then, keep snapshots in the
   calling session's own working area and name the exact path used in the report.

5. **Optional context pass.** For situational awareness only (a DayZ patch can explain a cluster
   of mod updates), one read-only call:

   ```
   curl -s "https://api.steampowered.com/ISteamNews/GetNewsForApp/v0002/?appid=221100&count=5&format=json"
   ```

   Verified live during this build, no key required. Never treat this as a substitute for the
   per-mod check in step 2.

6. **Report.** A table of mod name / ID / previous `time_updated` (if any) / current `time_updated`
   / changed? / `is_dayz` flag / any traps hit. Flag anything that looks like it needs a real
   decision (update it? re-run mod-review on what changed?) rather than making that call here.

## Stop conditions

- Stop and ask before treating any ID as resolved if `consumer_app_id` isn't `221100` — don't
  silently drop or silently include it.
- Stop and ask the owner (or check the target site's own doc) if no authoritative ID list exists
  for the site being surveyed — never invent an ID list.
- Never scrape or fetch a `steamcommunity.com` Workshop page directly — that's the blocked/
  rate-limited path this skill exists to avoid.
- Never subscribe to, download, mount, or extract a mod as part of this survey — the API call is
  the entire interaction with Steam.
- Never decide to update an installed mod from this skill's output — that's a separate action, and
  if it touches a live site it goes through `owner-click`, not this skill.
- Never add a Steam Web API key or any credential to the helper script or any call it documents.

## Grounded in

- `steam-workshop-research-method-2026-09-16.md` (session memory) — the API method and its three
  parsing traps.
- `site-chernarus` `docs/mods/README.md` (origin/main) — the Installed-mods table used as the
  default ID source; also documents that no single cross-site list exists.
- `aegis-mods` `docs/MOD_REVIEW_PROTOCOL.md` (origin/master) — confirms *mod-review* is a distinct,
  not-approved skill for reviewing new content proposals, not this skill's scope.
- `MasterThread` `skills/README.md` (origin/main) "Not approved for this batch" — lists `mod-review`
  as not approved; this skill is a different procedure and does not reopen that decision.
- `MasterThread` `docs/AGENTS.md` (origin/main) — `workshop-mod-inventory` agent entry, confirmed
  to cover only the org's own `module.json` files under `aegis-mods`/`aegis-poi`, not third-party
  Workshop update status.
- Live verification during this build (read-only, no key): `GetPublishedFileDetails` on
  `2545327648`/`1559212036` returned `title`, `time_updated`, `file_size`, `consumer_app_id`,
  `subscriptions`; `GetNewsForApp` for appid `221100` returned recent news items.
- `skills/land-pr/SKILL.md`, `skills/owner-click/SKILL.md` (origin/main) — format/structure
  reference for this skill file.
