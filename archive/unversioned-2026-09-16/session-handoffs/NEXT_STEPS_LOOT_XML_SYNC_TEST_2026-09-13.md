# Plan: test the dayz_loot DB ↔ live Shockbyte XML connection (prepared 2026-09-13)

## Why this needs a plan instead of just "run a test"

There is no live connection to test yet. Two independent pieces both have to exist first:

1. **DB → XML generator** (`dayz_loot` → `types.xml`/`events.xml`/etc.) — not built. Session 1
   (schema) is merged (`aegis-services` #38). Session 2 (XML→DB import) is in progress, uncommitted,
   in worktree `_wt-services-loot-import`. Session 3 (the generator that reverses that direction) has
   never been started.
2. **Repo → Shockbyte transport** (`nasdarasync`) — built and unit-tested (82 tests, `aegis-core`
   `sync/`), but only against an in-memory fake server. It has never spoken to the real Shockbyte
   panel. Phase 0 of `docs/nasdara-shockbyte-sync-plan.md` (pick SFTP vs. Pterodactyl API, get
   credentials) was never done — default transport is `null` and refuses every server-touching
   command on purpose.

Testing "the connection" before both exist would just be testing nothing. The plan below finishes
each piece as its own session, then does a real end-to-end test — on the local dev DayZServer first,
matching the already-decided "nothing reaches production untested" rule, before ever touching the
live Shockbyte box.

## Phase A — Finish Session 2: XML → DB import (aegis-services)

- Land the in-progress worktree (`_wt-services-loot-import`, branch
  `agent/services/dayz-loot-import`) as a PR: import `db/types.xml`, `db/events.xml`,
  `cfgrandompresets.xml`, `cfgspawnabletypes.xml`, `db/globals.xml`, `cfglimitsdefinition.xml`, and
  `ce_nasdara/nasdara_weapons_types.xml` from `aegis-site-chernarus` into the `dayz_loot` tables.
  Includes the three uncommitted migrations already sitting there (`0002_spawnable_types_normalize`,
  `0003_loot_globals_var_type`, `0004_loot_types_category_nullable`).
- Preserve the known untagged-Nasdara-weapons gap as-is (don't silently add `shelves` tags during
  import).
- **Done when:** import runs clean against a throwaway local MySQL, row counts match the source XML
  element counts, PR merged.

## Phase B — Session 3: DB → XML generator (aegis-services)

- New script (`db/loot/src/generate/` or similar) that reads `dayz_loot` and writes
  `types.xml`/`events.xml`/`cfgrandompresets.xml`/`cfgspawnabletypes.xml`/`globals.xml` back out,
  split across `db/` vs. `ce_nasdara/` per `loot_file_sources` — mirroring how
  `cfgeconomycore.xml` already partitions files.
- **Round-trip check as the acceptance test for this session, not a separate one:** generate from
  the just-imported data and diff byte-for-byte (or semantically, if whitespace/attribute-order
  differs) against the original XML that seeded it. Any unexplained diff is a bug in Session 2 or 3,
  found here instead of live.
- **Done when:** round-trip diff is clean (or every diff is explained and accepted), output validates
  under `xmllint`, PR merged.

## Phase C — Phase 0 transport discovery for `nasdarasync` (needs Jeremy, ~30 min)

- At the Shockbyte panel: check for API credentials → subusers → SFTP, per the ladder in
  `aegis-core/docs/nasdara-shockbyte-sync-plan.md` §2 (Pterodactyl client API key preferred, subuser
  SFTP second, main-account SFTP third).
- Confirm the largest file (`db/types.xml`, ~860 KB) reads and writes cleanly over whichever
  transport wins — this is the one open risk called out in that plan (§6.2).
- Put the resulting credential in the local, non-committed transport config (`config.example.toml` →
  real `config.toml`), same handling as every other AEGIS credential — I never see or store it.
- **Done when:** `nasdarasync status` runs against the live server (read-only) and returns a real
  three-way diff instead of the `null`-transport refusal.

## Phase D — End-to-end test, local dev first

Per `nasdara-shockbyte-sync-plan.md` §4 (already-decided change process — nothing reaches production
untested):

1. Make one deliberately small, reversible change in `dayz_loot` (e.g. nudge one test item's
   `nominal` by a small amount).
2. Run the Phase B generator → produces updated `types.xml`.
3. `nasdarasync deploy --target local` onto the local dev `DayZServer`, boot it, confirm:
   - `[CE][Hive] :: Init sequence finished.` + `Player connect enabled`
   - zero new `MARKET CONFIGURATION ERROR` / `Unknown category`
   - the changed item's nominal actually reflects the DB edit (spawn-check or file read)
4. Only after that passes: `nasdarasync push` the same change to live Shockbyte in a maintenance
   window, then `nasdarasync verify` (re-reads the server, hash-compares), then restart if needed,
   and paste the live boot signature — closing the loop the sync plan already designed.

**Done when:** a DB row edit has been shown, with evidence (boot signature + verify hash match), to
reach the live Shockbyte server as the correct XML content, end to end.

## Sequencing note

A and B are `aegis-services` sessions and can run independently of C, which is `aegis-core` /
Jeremy's panel access. C can happen in parallel with A/B — it doesn't depend on the loot generator
existing, since it's exercised first with `status`/`pull` against whatever's live today. D is the
only phase that needs A, B, and C all done.

## Out of scope here

- Deciding whether `dayz_loot` becomes the permanently-edited source (that's already the stated
  direction in `db/loot/README.md`) — this plan is just proving the pipe works, not a policy change.
- The nightly drift check (`nasdara-shockbyte-sync-plan.md` §5) — that's downstream of C and D
  working, not a prerequisite for them.

---

## Session status (2026-09-13, end of session)

**Phase A — done, ahead of this doc.** `aegis-services` PR #39 (`dayz_loot Session 2: XML import
script + 5 schema corrections from real data`) is merged to `main`. The doc above still describes
it as "in progress, uncommitted, in worktree `_wt-services-loot-import`" — that's stale; the
worktree directory left on disk (`_wt-services-loot-import`) is no longer even a git repo
(pruned). Ignore it.

**Phase B — done, resolved itself.** Two sessions independently built the Session 3 generator at
the same time without knowing about each other (see the collision described above) — both
converged on the same real bug (`chance` attribute can be absent on a spawnable-type `<item>`,
migration `0007`), which is a good sign both were right. The `_wt-services-loot-generate` pile won
the race: it shipped as `aegis-services` PR #43 (`dayz_loot Session 3: DB-to-XML generator,
verified round trip, CI coverage`), merged 2026-09-13T14:20:48Z, and is now on `main` as
`db/loot/src/export/{xml.js,run.js}` plus `db/loot/test/roundtrip.test.js` and a `loot-db` CI job.
The other pile (directly on `aegis-services` `main`, never a worktree — a process mistake, not
just a naming collision) was abandoned in favor of the merged one; its work is sitting in
`git stash list` on that checkout (`"loot generator session 3 wip"`) purely as scratch, superseded,
safe to drop whenever convenient. **No reconciliation session is needed** — ignore the old startup
prompt #2 below, it was written before the race resolved.

**Phase C — in progress, blocked on Jeremy's ~30 min at the panel.** Walked the transport ladder
live this session:
- Rung 1 (Pterodactyl API credentials): **not available** — no such section in Shockbyte's panel.
- Rung 2 (subuser SFTP): **available but blocked** — the panel requires an invite email for a
  subuser, and Jeremy doesn't want to use an untested `aegisdirective.net` mailbox for it yet.
  Deferred; revisit once that mailbox is tested (see `docs/DEPLOY.md` / domain-email work, not
  tracked in this doc).
- Rung 3 (main-account SFTP): **selected.** Host/port confirmed to match the plan's placeholder
  (`sftp.shockbyte.was1.shockbyte.host:2222`); username confirmed as Jeremy's Shockbyte account
  email.

Built this session, both on `jeremy-gaming` (this machine), neither committed (correctly — one's
gitignored, the other's genuinely new and small enough to commit alongside whatever PR closes this
phase):
- `aegis-core/sync/config.toml` — real, gitignored, `kind = "sftp"` with the confirmed host/port/
  username. No password in it; `password_env = "NASDARASYNC_SFTP_PASSWORD"`.
- `aegis-core/sync/phase0_write_test.py` — untracked, not secret, safe to commit. Reads the live
  `db/types.xml` (860 KB), writes those exact bytes back (no-op), re-reads, hash-compares. Proves
  the write path on the largest file without changing any content.

**Still needed from Jeremy**, in his own terminal (not through the session, so the panel password
never appears in a transcript):
```powershell
cd C:\Users\yoda_\GitHub\aegis-core
$env:NASDARASYNC_SFTP_PASSWORD = "<Shockbyte panel password>"
python sync\nasdarasync.py status
python sync\phase0_write_test.py
```
`paramiko` is already installed on this machine — no setup step needed first.

**Phase D — not started, but the ground was checked and it's simpler than Phase D's original text
implies.** Two corrections to the phase as originally written:

1. **`nasdarasync deploy --target local` does not exist.** It was aspirational language from this
   plan's first draft (before `nasdarasync` itself existed). The real CLI (`aegis-core/sync/
   nasdarasync.py`) only talks to the one transport in `config.toml` — Shockbyte, over SFTP. There
   is a `[deploy] local_target = ""` field already reserved in `config.toml` for a future local-
   deploy feature (`nasdara-shockbyte-sync-plan.md`'s Phase 6, "Local test target"), but it isn't
   built. Getting generated XML onto a local dev server today means copying the files there
   directly — no tool does it for you yet.
2. **A bootable local dev DayZ server already exists on this machine**, separate from the plain
   `DayZServer` git checkout used only as an XML *source* (`cfgspawnabletypes.xml`) for the
   import/generator. It's at `E:\SteamLibrary\steamapps\common\DayZServer`, mission folder
   `mpmissions\Nasdara.ChernarusPlus` (not the vanilla `dayzOffline.chernarusplus` alongside it —
   that one's stock). This is the same server other AEGIS modules were boot-tested against before
   going live (`profile_aegis_metrics_test`, `profile_aegis_teddybear_test`,
   `profile_aegis_pvpguard_test`, etc. sitting next to it, and `start_nasdara_server_test.bat`) —
   follow that same test-profile pattern rather than overwriting the live dev mission in place.

So Phase D step 3 (local boot test) needs no new tooling and no live Shockbyte credentials at
all — it only needs the merged generator (done) and a throwaway `dayz_loot` MySQL container (same
pattern already proven for the generator's own verification). Only step 4 (the real Shockbyte
push) needs Phase C's credential.

**Phase C's actual remaining gap, restated precisely:** transport *discovery* (which rung of the
ladder to use) was already decided as SFTP back on 2026-09-11 and is documented in `aegis-core/
sync/README.md` — that part is not still open. What's still open is that `sync/config.toml` is
gitignored (correctly), so it doesn't travel with a fresh checkout, and the version rebuilt this
session has never actually been exercised against the live Shockbyte account with real credentials
in hand. The "Still needed from Jeremy" commands below are that one remaining check, not a
from-scratch Phase 0.

---

## Startup prompts for the next sessions

Two of the original three follow-ups are done or moot (Phase B resolved itself — see above). Two
sessions remain, and they don't depend on each other — Phase D's local half (2a) can start
immediately; the Shockbyte credential check (2b) only gates Phase D's live half (step 4).

### 1. Phase D, local half — no credentials, no click-through needed, can run right now

```
Repo: aegis-services (generator) + this machine's local DayZ dev server (E:\SteamLibrary\steamapps\
common\DayZServer)
Read NEXT_STEPS_LOOT_XML_SYNC_TEST_2026-09-13.md Phase D at the GitHub root in full, including the
"corrections" note — nasdarasync has no --target local, so this is a manual file copy, not a CLI
command. Steps:
1. Bring up a throwaway MySQL container (same pattern db/loot/README.md's "Generate" section
   already documents), migrate, import the real aegis-site-chernarus XML with db/loot/src/import,
   make one small reversible edit (nudge one test item's nominal), then run
   db/loot/src/export/run.js to generate XML into a scratch directory.
2. Copy the generated files into a NEW test copy of the mission folder — duplicate
   E:\SteamLibrary\steamapps\common\DayZServer\mpmissions\Nasdara.ChernarusPlus to something like
   ...\Nasdara.ChernarusPlus_loot_test (do not edit the live dev mission in place), following the
   same test-profile pattern already used for AEGIS_Metrics/TeddyBear/PvPGuard
   (profile_aegis_*_test folders, start_nasdara_server_test.bat) — check those for the exact
   boot-test script/config pattern before improvising your own.
3. Boot it, tail the RPT log, confirm: "Init sequence finished", "Player connect enabled", zero new
   "MARKET CONFIGURATION ERROR" / "Unknown category", and that the edited item's nominal actually
   changed in the generated types.xml.
4. Record the result in NEXT_STEPS_LOOT_XML_SYNC_TEST_2026-09-13.md (Phase D status) and clean up
   the test mission copy and throwaway MySQL container afterward.
This whole session needs nothing from Jeremy — everything it touches is local and disposable.
```

### 2. Confirm the live Shockbyte transport, click-through for Jeremy (only gates Phase D step 4)

```
Repo: aegis-core, sync/
Read NEXT_STEPS_LOOT_XML_SYNC_TEST_2026-09-13.md "Session status" and the corrected Phase C note at
the GitHub root first — transport discovery itself (SFTP, main account) was already decided
2026-09-11 and is documented in aegis-core/sync/README.md; what's actually unverified is this
machine's current sync/config.toml (gitignored, already filled in with host/username, no password)
against the real Shockbyte account. Confirm config.toml and phase0_write_test.py are still present,
then walk Jeremy through, in HIS OWN terminal window (never have him paste the password into chat):
  cd C:\Users\yoda_\GitHub\aegis-core
  $env:NASDARASYNC_SFTP_PASSWORD = "<Shockbyte panel password, typed only in his terminal>"
  python sync\nasdarasync.py status
  python sync\phase0_write_test.py
Tell him exactly what to expect before he runs each one (a three-way diff printout for the first,
a "wrote/re-read/hashes match" style confirmation for the second) so he can tell success from
failure without reading the code. Interpret the results:
- Both pass: mark Phase C fully confirmed in the NEXT_STEPS doc, commit phase0_write_test.py (not
  secret), and note Phase D's live-push half (step 4) is now unblocked — still needs a maintenance
  window and Jeremy confirming zero players online before anything pushes.
- `status` fails to connect: host/port may not match what the panel shows today — read the FTP File
  Access page with him and correct the non-secret fields in sync/config.toml together.
- phase0_write_test.py fails its hash comparison: stop, do not proceed to Phase D step 4, and report
  it — this is the one open risk in nasdara-shockbyte-sync-plan.md §6.2 (the largest file, ~860 KB,
  over this transport) and needs Jeremy's input on next steps (subuser SFTP, once the
  aegisdirective.net mailbox is tested, is the natural fallback — don't re-attempt it without him
  confirming that's ready).
```
