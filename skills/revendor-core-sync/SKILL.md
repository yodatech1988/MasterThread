---
name: revendor-core-sync
description: Use when core's tools/check_vendor_drift.py (or a validate-site.yml CI run) reports that a site repo's vendored copy of core's sync/ files has drifted, to reconcile the drift and re-vendor before any CORE_READ_TOKEN / CI-gating change is touched.
---

# revendor-core-sync

## When to use this

- A drift report (from `check_vendor_drift.py`, the `vendored-validator-advisor` /
  `vendored-validator-status-reporter` agents, or a `validate-site.yml` CI run) names a site repo
  whose vendored `sync/` files no longer match `core`'s.
- Before anyone proposes setting or changing `CORE_READ_TOKEN` on a site repo — the drift must be
  reconciled first (`core:docs/ops/VENDORED-VALIDATOR.md`, "Owner / maintainer actions": setting
  the token before reconciliation turns the required `validate / validate` check red on every PR).
- Today this applies to **site-chernarus** (the only repo that calls `validate-site.yml` and has a
  `sync/` directory). `site-badlands`, `services`, and `website` have no vendored `sync/` copy and
  this skill does not apply to them.

## Procedure

1. **Re-run the drift checker — never quote an old count.** From a working directory with both a
   `core` checkout and the consumer repo's checkout on disk:

   ```sh
   python /path/to/core/tools/check_vendor_drift.py /path/to/site-chernarus
   ```

   Exit code 0 means no drift; treat any non-zero prior figure (in a PR body, an issue, or a
   teammate's message) as stale until you have run this yourself
   (`core:docs/ops/VENDORED-VALIDATOR.md`, "Read that number carefully, because it has been
   misreported twice"). The manifest checked is `VENDORED_FILES` in `core/sync/validate.py`:
   `bercon.py`, `boot_watch.py`, `nasdarasync.py`, `restart_orchestrator.py`, `transports.py`,
   `validate.py`, `test_bercon.py`, `test_boot_watch.py`, `test_nasdarasync.py`,
   `test_ownership.py`, `test_restart_orchestrator.py`, `test_validate.py`.

2. **Per drifted file, decide which way it goes before copying anything.** For each file the
   checker names, read both copies side by side and classify it as one of:
   - **Feature work to port back into core** — the site repo's copy has real functionality core
     lacks (the precedent in the doc: an `export-identity` command and `ownership.json`/
     `FORBIDDEN_PATTERNS` additions were ported this way). Port it into `core` first, in a
     separate PR to `core`, before re-vendoring the site repo from the updated `core`.
   - **A genuine, reviewed, site-specific divergence** — belongs on an allowlist, not silently
     overwritten. No allowlist file exists yet in either repo as of this writing (confirmed:
     `core/tools/` and `site-chernarus`'s tree have none) — **TODO: needs owner/maintainer input**
     on whether to create one (`--allowlist path/to/list.json`, a JSON array of file names, per
     `check_vendor_drift.py --help`) and where it should live.
   - **Neither — a design call about which side's behavior should win** (the doc's own recorded
     example: site-chernarus's `restart_orchestrator.py` gained a BattlEye-GUID feature but lost
     core's 2026-09-12 restart-safety fixes). Do not resolve this by copying either side wholesale
     — stop and follow "Stop conditions" below.
   - A file that differs only because the site repo's copy **predates** core's own
     `VENDORED_FILES`/`load_vendored` machinery (the doc's example: `validate.py`) is a plain
     re-vendor, not a design call.

3. **Copy core's authoritative files into the site repo's `sync/`** — only the files decided as
   plain re-vendors or already ported back into core in step 2:

   ```sh
   cp /path/to/core/sync/{bercon,boot_watch,nasdarasync,restart_orchestrator,transports,validate}.py sync/
   cp /path/to/core/sync/{test_bercon,test_boot_watch,test_nasdarasync,test_ownership,test_restart_orchestrator,test_validate}.py sync/
   ```

   (`core:docs/ops/VENDORED-VALIDATOR.md`, "The re-vendor command" — copy only the names actually
   drifted and resolved; don't overwrite a file still pending a step-2 decision.)

4. **Run the site repo's own test suite** before opening a PR — a byte-identical copy of core's
   files can still fail against the site repo's local, non-vendored fixtures
   (`ownership.json`, `config.example.toml`):

   ```sh
   python -m pytest sync/ -v
   ```

5. **Commit and open a PR via the `land-pr` skill**, not directly:

   ```sh
   git checkout -b revendor-core-sync-<date>
   git add sync/
   git commit -m "Re-vendor core's sync/ files"
   git push -u origin revendor-core-sync-<date>
   gh pr create ...
   ```

   Then follow `land-pr`'s procedure (re-check PR state before pushing, route review via
   `diff-reviewer` unless this touches live/credential/money/death-path scope, verify the merge
   actually lands on `origin/main`).

6. **After merge, re-run the drift checker again to confirm zero non-allowlisted drift** before
   anyone touches `CORE_READ_TOKEN` or CI gating for this repo. Setting the token, and any change
   to a repo secret or branch-protection/CI-gating setting, is an owner action — route it through
   `owner-click` (a click-file the owner runs) or an Ops Decision Queue card per this machine's
   standing instructions. This skill never sets the token itself.

## Stop conditions

- **A drifted file is a genuine "which side wins" design call** (conflicting, non-additive changes
  on both sides — not just "site added a feature") — stop before copying either side. File a
  Decision Queue card or ask the owner; don't guess which behavior is correct.
- **No allowlist file exists yet and a divergence looks deliberate** — stop and record it as
  `TODO: needs owner input` rather than inventing an allowlist location or policy.
- **`CORE_READ_TOKEN` or any repo secret/CI-gating change** — never do this from inside the skill;
  route to `owner-click` or a Decision Queue card, and only after step 6 confirms zero drift.
- **The drift checker's count doesn't match what a PR/issue/teammate claimed** — trust the checker
  you just ran, not the older figure; re-verify before acting either way.
- **`sync/` doesn't exist in the consumer repo at all** — the checker itself exits 1 and flags this
  as "nothing to compare," not silent success; treat it the same as drift, not a pass.

## Grounded in

- `core:docs/ops/VENDORED-VALIDATOR.md` — "The re-vendor command", "What must be vendored"
  (`VENDORED_FILES`), "Owner / maintainer actions", and the recorded reconciliation history
  (feature-port vs. allowlist vs. design-call examples).
- `core:tools/check_vendor_drift.py` — the drift-check script and its `--allowlist`,
  `--core-sync-dir`, `--consumer-sync-dir` flags; confirmed no allowlist file exists yet in
  `core/tools/` or `site-chernarus`.
- `core:.claude/agents/vendored-validator-advisor.md`,
  `core:.claude/agents/vendored-validator-status-reporter.md` — reference for the "detect" step;
  they only report drift/verdicts and do not re-vendor.
- `site-chernarus:sync/` (verified on `origin/main`: all twelve `VENDORED_FILES` present) and
  `site-chernarus:.github/workflows/validate.yml` (calls `core`'s `validate-site.yml@main` with
  `secrets: inherit`, confirming no `CORE_READ_TOKEN` currently set there).
- `MasterThread:skills/land-pr/SKILL.md` — PR push/merge procedure this skill defers to.
- `MasterThread:skills/owner-click/SKILL.md` — routing for the owner-only `CORE_READ_TOKEN` /
  CI-gating step.
