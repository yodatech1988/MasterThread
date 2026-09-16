# Loot/economy-config DB track: next steps (prepared 2026-09-12, updated 2026-09-13)

**Superseded 2026-09-14:** services#51 folded `dayz_loot` into `dayz_economy` (3-database plan) —
there is no separate `dayz_loot` database, no `db/loot/` package, and Sessions 4/5 below (standing
up a new DB) are moot. Migrations `0004`–`0010` are live in `dayz_economy`; the loot tables exist but
are empty. See `NEXT_STEPS_ECONOMY_AUTOMATION_2026-09-14.md` for current state.

**Status: all three planned build sessions done and merged.** `dayz_loot` schema, importer, and
generator all exist, are round-trip-verified against the real live files, and have CI coverage.
**Two sessions remain, both about actually standing up a live database** — Session 4 (build a
guided setup tool, Claude-only) and Session 5 (a short, mostly-clicking session where you and a
Claude session actually create it). See "What's left" below for exact starter prompts.

## What's done

| Session | PR | What it did |
|---|---|---|
| 1 — schema | [services#38](https://github.com/yodatech1988/services/pull/38) | 15 tables: `loot_types`, `loot_events`, `loot_random_presets`, `loot_spawnable_types`, `loot_globals`, plus junctions and reference lists (categories/tags/usages/values), seeded from the live `cfglimitsdefinition.xml` (8/3/17/5). |
| 2 — import | [services#39](https://github.com/yodatech1988/services/pull/39) | `db/loot/src/import/{xml.js,run.js}`: parses the real `db/types.xml`, `db/events.xml`, `cfgrandompresets.xml`, `cfgspawnabletypes.xml`, `db/globals.xml`, `cfglimitsdefinition.xml`, `ce_nasdara/nasdara_weapons_types.xml`, upserts them. 5 schema corrections (0002–0006) found by running against real data. |
| 3 — generator | [services#43](https://github.com/yodatech1988/services/pull/43) | `db/loot/src/export/{xml.js,run.js}`: the reverse — reads `dayz_loot`, writes the XML back out. `--verify-against` re-parses original and generated files and deep-compares the data (not a text diff). 2 more corrections (0007, and a lookup-table sync bug found while writing tests). Added `test/roundtrip.test.js` and a `loot-db` CI job. |

**Verified, as of 2026-09-13:** importing the real `aegis-site-chernarus`/`DayZServer` files,
exporting them back out, and re-parsing both sides for a semantic diff gives **`PASS` on all 7
files** — 2,043 `loot_types`, 60 events/245 children, 78 presets/600 items, 564 spawnable
types/892 cargo blocks/710 attachment blocks, 30 globals. All of this has only ever run against a
**throwaway local MySQL container** — no live `dayz_loot` database exists yet.

`db/loot/README.md` is the durable reference for the schema, the import/export scripts, and the
full list of 7 real schema corrections (0002–0007) with why each one was wrong — read it before
touching this database again, in preference to the historical planning notes further down this file.

## Known, deliberately-not-yet-fixed finding

`ce_nasdara/nasdara_weapons_types.xml`'s 73 modded firearms have **no `<tag>` element** at all
(unlike vanilla weapons, almost always tagged `shelves`), so they only spawn at the small subset of
loot points with no tag requirement — likely why they barely spawn despite reasonable nominal/min
values. Confirmed still true through the real import (`source_key = 'ce_nasdara_weapons'` → 0 rows
in `loot_type_tags`, always). Not fixed anywhere in this track on purpose, so it stays visible and
queryable. Fixing it for real (probably `<tag name="shelves"/>` added to that XML file, or the
equivalent DB row once live) is a candidate for its own small session whenever you want it — not
blocking anything here.

## What's left

Two sessions, run in order. Session 4 has no owner-facing clicking in it at all; Session 5 is
almost entirely clicking, guided step by step.

### Session 4 — build a guided setup tool (Claude-only, no clicking from you)

Every other database on this network (`dayz_economy`, `dayz_community`, `dayz_ops`) has a
PowerShell tool — `EconomyDbKey.ps1`, `CommunityDbKey.ps1`, `OpsDbKey.ps1` — that's the *only*
place a password ever gets typed: it opens a small window with Generate/Test/Save/Apply-pending
buttons, stores the key with Windows DPAPI (`%APPDATA%\AEGIS\...`), and never touches git, `.env`,
or chat. `dayz_loot` doesn't have one yet. This session builds `db/loot/tools/LootDbKey.ps1`
mirroring that exact pattern, wired to `db/loot`'s own scripts (`npm run migrate`, `node
src/import/run.js --apply`, `node src/export/run.js --verify-against`) instead of Node ones — read
`db/economy/tools/EconomyDbKey.ps1` for the exact structure to copy (it's a WinForms script, not
huge). Its "Apply pending" button should run `migrate` then `import/run.js --apply` against a real
`aegis-site-chernarus` checkout path (a `-SiteCheckout` parameter, same idea as `EconomyDbKey.ps1`'s),
then `export/run.js --verify-against` that same checkout as a self-check, and report PASS/FAIL.

- **Read:** `db/economy/tools/EconomyDbKey.ps1` in full (the pattern to mirror), `db/loot/README.md`
  (current scope, scripts, env var names `LOOT_DB_*`), `db/loot/src/config.js` (required env vars),
  `db/loot/src/import/run.js` and `db/loot/src/export/run.js` (the exact CLI flags `--site-dir`,
  `--dayzserver-dir`, `--apply`, `--out-dir`, `--verify-against`).
- **Do:** Create `db/loot/tools/LootDbKey.ps1`. Generate/Test/Save/Apply-pending, DPAPI storage at
  `%APPDATA%\AEGIS\loot-db.clixml`, a `-Run` passthrough flag like economy's. Since `dayz_loot`
  doesn't exist yet (unlike economy's rotation-only tool), the window's intro text should say so
  explicitly and point at Session 5's Shockbyte panel steps rather than assume a database is
  already there. Test the Generate/Test/Save flow against a throwaway local MySQL (same Docker
  pattern used in every other session this track) standing in for the not-yet-real Shockbyte one —
  you don't need a real Shockbyte database to verify this session's own work.
- **Out of scope:** actually creating anything on Shockbyte, touching `dayz_economy`/`dayz_community`
  tooling, deciding whether `dayz_loot` shares a physical server with them (see "Open questions").
- **Done when:** `LootDbKey.ps1` opens, its Generate/Test/Save flow works against a throwaway local
  MySQL, one PR open against `aegis-services`.
- **Starter prompt:**
  > Read `NEXT_STEPS_LOOT_2026-09-12.md` at the GitHub root, "Session 4" section, in full — also
  > read `db/loot/README.md` and `db/economy/tools/EconomyDbKey.ps1`. Build
  > `db/loot/tools/LootDbKey.ps1` mirroring that economy tool's Generate/Test/Save/Apply-pending
  > pattern, wired to `db/loot`'s own npm scripts and CLI flags. Verify the Generate/Test/Save flow
  > against a throwaway local MySQL Docker container. Don't touch `dayz_economy` or
  > `dayz_community`. One PR.

### Session 5 — actually create the database (mostly clicking, guided)

This is the session where something real gets created. Open it **after Session 4 merges**. Unlike
a coding session, most of the work here is you clicking through the Shockbyte panel while Claude
tells you exactly what to click, then running the new tool together.

- **Starter prompt:**
  > Read `NEXT_STEPS_LOOT_2026-09-12.md` at the GitHub root, "Session 5" section. Walk me through
  > creating the live `dayz_loot` database step by step: first the Shockbyte panel (MySQL
  > Databases — create a new database, create a new user, add the user to the database, note the
  > generated names), then launch `db/loot/tools/LootDbKey.ps1` and walk me through
  > Generate → paste into the panel → Test → Save → Apply pending. Tell me exactly what to click at
  > each step and wait for me to confirm before moving on. Don't type or ask me to paste the
  > password anywhere except the tool's own window and the Shockbyte panel.
- **What this session should do, roughly** (the opened session will have the exact live panel in
  front of it, so treat this as a checklist, not a script):
  1. Shockbyte panel → MySQL Databases → create a new database and a new user, add the user to the
     database with full privileges (same shape as the existing `a54c4d0b96-economy` /
     `f3ff781782-community` names — Shockbyte prefixes them).
  2. Launch `LootDbKey.ps1`, fill in the real Host/Port/User/Database it just generated.
  3. **Generate** a password → paste it into the Shockbyte panel's password field for that user →
     Save it there.
  4. Back in the tool: **Test** (should succeed now that the panel and the tool agree), then
     **Save** (encrypts it for your Windows account only).
  5. **Apply pending** — runs `migrate`, then `import/run.js --apply` against a real
     `aegis-site-chernarus` checkout, then a `--verify-against` self-check. Should report every
     migration applied and round-trip PASS.
  6. Add the new credential to `aegis-core/docs/ops/SECRET-ROTATION.md`'s list (same as every other
     DB), same pattern as `db/economy/README.md`'s security checklist.
- **Done when:** `dayz_loot` is live on Shockbyte, seeded from the real mission files, and
  `LootDbKey.ps1 -Run` works for future sessions without you re-entering the password.

## Open questions for later (not sessions yet)

- Whether `dayz_loot` should live on the same physical Shockbyte MySQL server as `dayz_economy`/
  `dayz_community` (cheaper, one server to patch — likely default) or its own instance. Doesn't
  block Session 4; only matters when Session 5 actually creates it, and it's the kind of small call
  a Session 5 can make itself rather than needing to be decided here first.
- Whether the generator should become a one-shot script run manually before each deploy, or get
  wired into `aegis-site-chernarus`'s existing `sync/` push tooling as a pre-push step. Decide once
  Session 5's round-trip has been verified once for real, not just against a throwaway container.
- Fixing the `ce_nasdara` untagged-weapons gap (see "Known, deliberately-not-yet-fixed finding"
  above) — worth its own small session once you want those guns to actually spawn, not urgent.

## Deliberately not in this plan

- Any change to `dayz_economy` or `dayz_community` schemas, scope, or tooling.
- Hosting/credentials work beyond Session 5's own scope — no automated backups, no CI secret wiring
  for `dayz_loot` yet (the existing `ops-backup.yml` nightly job would need `LOOT_DB_PASSWORD`
  added once this is live; that's a natural Session 6 once Session 5 is done, not written yet).

---

<details>
<summary>Historical planning notes from before Sessions 1–3 started (2026-09-12) — kept for
context, superseded by <code>db/loot/README.md</code> for anything about the actual schema</summary>

### Decided in the original planning chat (2026-09-12)

- **New sibling database, `dayz_loot`** — not `dayz_economy`. `dayz_economy`'s own
  `0001_dayz_economy_core.sql` header explicitly scopes it to virtual currency/ledger only and
  excludes physical items/state. Loot-config rows aren't currency, so they got their own database —
  matches the existing one-database-per-domain pattern (`dayz_economy`, `dayz_community`, `dayz_ops`).
- **Direction: DB is source of truth, XML is generated output.** Confirmed correct by Session 3's
  round-trip verification.
- **Conventions matched:** `db/loot/migrations/000N_*.sql` numbering, plain `mysql2` (no ORM), a
  `migrate.js` runner matching `db/economy/src/migrate.js`, UTC `DATETIME(3)` columns. Home repo:
  `aegis-services`, alongside `db/economy` and `db/community`.

### Original schema shape (superseded — see `db/loot/README.md`'s actual table list)

The originally discussed shape assumed `loot_spawnable_types` could hold one scalar
cargo/attachments preset+chance per classname, and that several fields (`category_name`, `min ≤
nominal`, event `min ≤ max`, item `chance`) were always present or always ordered a certain way.
Real data proved all of these wrong — see `db/loot/README.md`'s "Schema corrections" section
(migrations 0002–0007) for exactly what changed and why.

</details>
