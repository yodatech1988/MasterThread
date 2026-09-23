---
name: apply-db-migration
description: Use when a schema migration under `services/db/economy`, `services/db/community`, or `services/db/ops` has merged and needs to reach the matching live AEGIS MySQL database — checks status, routes the live apply through owner-click, then verifies with that database's own audit views.
---

# apply-db-migration

## When to use this

- A PR that added or changed a file under `services/db/economy/migrations/`,
  `services/db/community/migrations/`, or `services/db/ops/migrations/` has merged into
  `services` `main`.
- Someone asks whether a database is up to date with its migrations, or why a sync/monitor
  workflow is reporting `pending-migrations`.
- Never for anything outside these three schemas, and never to design or write the migration file
  itself — this skill only gets an already-merged migration onto the live database.

## Procedure

1. **Identify which database has the merged, unapplied migration.**
   ```
   git -C services fetch -q origin main
   git -C services show origin/main:db/economy/migrations   # ls each dir similarly
   git -C services log --oneline -5 -- db/economy/migrations db/community/migrations db/ops/migrations
   ```
   Match the new file(s) to exactly one of the three schemas — they never share migrations.

2. **Status check first (read-only, safe to run directly, no owner action needed):**
   - economy: `powershell -File db\economy\tools\EconomyDbKey.ps1 -Run src\migrate.js --status`
     (or `-Run src\check.js` for the fuller connection + audit-view read)
   - community: `powershell -File db\community\tools\CommunityDbKey.ps1 -Run apply.py --status`
   - ops: `powershell -File db\ops\tools\OpsDbKey.ps1 -Run src\migrate.js --status`

   These wrap each schema's stored DPAPI key (`%APPDATA%\AEGIS\*.clixml`) and run the check in a
   child process's environment only. **Never open, print, or read the `.clixml` file itself** —
   only ever invoke it through the `-Run` wrapper.

3. **If nothing is pending, stop here** — the migration already landed (or there is nothing to
   apply) and step 4 does not apply.

4. **The apply itself is a live production change — route it through the `owner-click` skill,
   not this session.** No standard on `origin/main` was found that authorizes a session to run
   these apply commands unattended (see "Grounded in" — the sources describe *what* the apply
   command is, never *who* may run it against the live schema, and `merge_authority.md`
   classifies "merging arms a change to a live system" as Tier 4 / owner-click route C). Use
   `owner-click` to build the `.cmd`:
   - It shows the exact pending-migration list from step 2's status output.
   - It runs, only after a typed `YES`:
     - economy: `EconomyDbKey.ps1 -Run src\migrate.js` (from a checkout of `origin/main`,
       after `npm ci --prefix db\economy`)
     - community: `CommunityDbKey.ps1 -Run apply.py` (after `pip install pymysql`)
     - ops: `OpsDbKey.ps1 -Run src\migrate.js` (after `npm ci --prefix db\ops`)
   - It never embeds the DPAPI key value — the wrapper reads it fresh from the `.clixml` store in
     its own process, per `owner-click`'s rule.
   - Hand the `.cmd` to the owner and stop. Don't proceed on the owner's behalf.

5. **After the owner runs it, verify with a read-only audit pass** (never re-attempt the apply
   yourself even if something looks wrong — report and stop, per "Stop conditions"):
   - economy: `EconomyDbKey.ps1 -Run src\check.js` — `audit_wallet_drift` and
     `audit_unbalanced_transactions` must both show 0 rows; `pending:` lines must be gone.
   - community: `CommunityDbKey.ps1 -Run apply.py --status` — no pending files listed.
   - ops: `OpsDbKey.ps1 -Run src\migrate.js --status` — no pending files listed. (`v_stale_servers`
     / `v_backup_gaps` are general health views, not migration-specific; check them only if the
     owner also asked for a health read.)

6. **For an economy migration only, confirm the sync gate cleared:**
   ```
   gh -R yodatech1988/services run list --workflow economy-catalog-sync.yml -L 1
   gh -R yodatech1988/services run view <run-id> --log | grep -i pending-migrations
   ```
   The next run should no longer refuse with `error pending-migrations`.

7. **Never edit an applied migration.** Each runner refuses a changed checksum (`db/ops/README.md`;
   `db/economy/src/check.js` reports `"<file> changed after it was applied"`;
   `db/community/README.md` states it outright). Add the next numbered file instead
   (`0002_...sql`, etc.) and go through review/merge again before repeating this procedure.

## Stop conditions

- **Always stop before running the actual apply command yourself.** Route it through
  `owner-click` — this is a live production MySQL write and no found source authorizes a session
  to run it unattended.
- Stop and ask if a migration file can't be matched to exactly one of the three schemas.
- Stop if a status/check command errors (connection failure, TLS error) — report the error text,
  don't retry against the live database repeatedly, and don't attempt to read or repair the
  `.clixml` key file.
- Stop and report (don't attempt a fix) if the post-apply audit in step 5 shows any
  `audit_wallet_drift` / `audit_unbalanced_transactions` rows, a checksum-changed warning, or any
  pending file remains after the owner ran the `.cmd`.
- Never print or read the contents of any `*.clixml` key file, and never paste a database
  password into a `.cmd`, chat, or this skill's files.

## Grounded in

- `services` `origin/main` `db/economy/MIGRATION.md` — "Automation" section: the same-day-apply
  rule, `tools/EconomyDbKey.ps1 -Run src/migrate.js`, `economy-catalog-sync.yml` refusing with
  `error pending-migrations`, and the post-apply
  `audit_wallet_drift` / `audit_unbalanced_transactions` check.
- `services` `origin/main` `db/economy/src/check.js` — read-only status/audit script; confirms the
  `AUDITS` view list and the "changed after it was applied" checksum message.
- `services` `origin/main` `db/economy/package.json` — `migrate` / `migrate:status` npm scripts.
- `services` `origin/main` `db/economy/tools/EconomyDbKey.ps1` — confirmed `-Run <script>` usage
  pattern (`-Run src/check.js`, `-Run src/migrate.js --status`).
- `services` `origin/main` `db/community/README.md` — "Applying migrations" section
  (`apply.py --status`, `apply.py`, `CommunityDbKey.ps1 -Run`) and "Never edit an applied
  migration; add the next numbered file."
- `services` `origin/main` `db/community/tools/CommunityDbKey.ps1` — confirmed `-Run` pattern.
- `services` `origin/main` `db/ops/README.md` — "Operations" (`npm run migrate:status`,
  `npm run migrate`, "Never edit an applied migration; the runner refuses a changed checksum"),
  and `v_stale_servers` / `v_backup_gaps` view descriptions.
- `services` `origin/main` `db/ops/tools/OpsDbKey.ps1` — confirmed `-Run <script>` pattern.
- `services` `origin/main` `db/ops/package.json` — `migrate` / `migrate:status` npm scripts.
- `MasterThread` `origin/main` `standards/sessions/merge_authority.md` — route C (owner) table:
  "Tier 4: merging arms a change to a live system on its next run (live economy or loot content
  ...)"; used here because no source found authorizes an unattended live apply, and this is the
  closest live-prod authority rule on file.
- `MasterThread` `origin/main` `skills/owner-click/SKILL.md` — the click-file procedure this skill
  routes the apply step through (diff/list shown first, typed `YES` gate, credential pulled fresh
  from DPAPI inside the `.cmd`'s own process, never embedded).
- `MasterThread` `origin/main` `skills/land-pr/SKILL.md` — format template only (not itself part of
  this procedure).
- `MasterThread` `origin/main` `standards/sessions/worker_role.md` — "Secrets: don't print, log or
  commit them. Credentials come from DPAPI stores ... and go into a child process's environment
  only," grounding the "never read/print the `.clixml`" rule.

**Not found / dropped from the candidate:** no `MIGRATION.md`- or `README.md`-level statement
names *who* (owner vs. session) may run the live apply command for any of the three schemas —
this was inferred from `merge_authority.md`'s Tier 4 / route C live-system class rather than a
migration-specific rule. If the owner later ratifies a standard that explicitly authorizes
sessions to run these applies unattended, step 4 should be updated to cite it directly and skip
`owner-click`.
