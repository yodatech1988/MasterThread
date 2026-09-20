# Economy automation: review + next steps (prepared 2026-09-14)

> **Status update 2026-09-14 ~03:15 UTC: Lanes C and S are both done (same session). Their PRs are open and need your merge.**
> - **core#67.** The deploy key now goes to `gh secret set` on stdin, not argv, with a new test. First real rotation done: key `163203992` replaced `163195099`, verified by a green sync ([run 34801423222](https://github.com/yodatech1988/services/actions/runs/34801423222)). §8 table has next-due 2026-12-14. A Google Calendar reminder is set for 2026-12-14.
> - **services#63.** What changed:
>   - `${{ }}` values now reach the shell as env vars.
>   - Fixed the `| tee` bug that showed a failed sync as a green step.
>   - Check stderr is captured.
>   - `test_alert` input on both workflows.
>   - Sync runs every 6h; Node 22.
>   - MIGRATION.md fixed: exact fail-vs-info list, `stuck_pending` decision, same-day migration rule, corrected loot note.
>
>   Both workflows ran green from the PR branch against live data with `test_alert` on.
> - **Still open:** Round 0 step 1 (the Discord webhook secret — alerts reach nobody until then), and #58 (waits for the first green *scheduled* run of each workflow; none by 03:10 UTC). After you add the webhook: Actions → run each workflow with `test_alert` checked, and confirm both `[test]` posts arrive.
> - **Remaining lanes:** none. Only the "Later" list at the bottom remains.

Hands off the 2026-09-13/14 session that automated the `dayz_economy` catalog import, added a
health monitor, and built a deploy-key rotation tool. Each lane below is one fresh Claude Code
conversation: model set via `/model`, prompt pasted as-is, conversation closed once the PR is open.
Rules come from MasterThread `standards/sessions/session_plan_standard.md`: one session = one PR, at
most one open agent PR per repo, and read only the Read list.

## What things look like right now (verified 2026-09-14 ~03:00 UTC against live GitHub + DB)

**Shipped and merged:**

| PR | What |
|---|---|
| services#53 | Re-verified the M3 catalog import against post-restructure data: 3,248 rows, 105 files, 97 categories, 0 warnings |
| services#54 | `economy-catalog-sync.yml`, `economy-monitor.yml`, `db/economy/tools/sync-catalog.js`, a balance snapshot in `src/check.js`, `db/economy/docs/AUTOADJUST-CONTRACT.md` (M9) |
| core#59, services#60 | Corrected stale "ECON_DB_PASSWORD overdue" claims; documented deploy keys (`docs/ops/SECRET-ROTATION.md` §8) |
| core#61, core#63 | `tools/rotate_deploy_key.py` (generate → secret → deploy key → wipe local files), plus the fix for the nonexistent `gh secret set --body-file` flag |
| services#61 | Recorded M2 and migrations 0004–0010 as applied live |
| services#59 (another session) | Moved the owner steps into issues #55/#56/#58 |

**Live state:**
- `dayz_economy` has migrations 0001–0010 applied. All four `audit_*` views are at 0.
  `shop_catalog` has 3,248 rows, all `is_available = FALSE`. The loot tables exist but are **empty**.
- Deploy key id `163195099` (`aegis-services-ci-economy-catalog-sync`, read-only) is on
  site-chernarus. Its private half is the `SITE_CHERNARUS_DEPLOY_KEY` secret on services.
- `ECONOMY_CATALOG_SYNC_ENABLED` and `ECONOMY_MONITOR_ENABLED` are both `true`.
- Both workflows have green `workflow_dispatch` runs (sync [34794714668](https://github.com/yodatech1988/services/actions/runs/34794714668),
  monitor [34794715866](https://github.com/yodatech1988/services/actions/runs/34794715866)). The sync
  log confirms the quiet no-op path (`applied inserted=0 updated=0 unchanged=3248`).
- `<USER_HOME>\.claude\settings.json` now allows `Bash(ssh-keygen:*)`, so agent sessions can run
  `rotate_deploy_key.py`.
- **No open PRs** in services or core. site-chernarus#64 is open (not from this track).

## Review findings: defects in the shipped work

1. **No alert can reach anyone.** `DISCORD_WEBHOOK_OPS` isn't set on services — the only secrets are
   `ECON_DB_PASSWORD`, `OPS_DB_PASSWORD`, and `SITE_CHERNARUS_DEPLOY_KEY`. Both new workflows, and
   `ops-scheduled.yml`'s alerts, only print to the Actions log. A monitor failure today is just a red
   run nobody is paged about.
2. **The alert paths have never run.** Only healthy and no-op runs have happened. The monitor's
   failure branch and the sync's skipped-warnings/error branches have never posted to a real webhook.
3. **No scheduled run of either new workflow has fired yet.** Every run so far is
   `workflow_dispatch`. GitHub's cron is heavily throttled on this account: "hourly"
   `ops-scheduled.yml` actually fired at 07:25, 13:16, 17:22, 20:42, 23:05, and 00:59. Expect gaps of
   hours, and confirm a real `event=schedule` run before trusting the cadence.
4. **The monitor docs overclaim.** `src/check.js` exits non-zero only for `audit_wallet_drift` rows,
   `audit_unbalanced_transactions` rows, or a changed migration checksum. `audit_stuck_pending`,
   `audit_orders_awaiting_delivery`, and *pending* migrations are informational only. The workflow
   header and MIGRATION.md's "Automation" section say all four views hard-fail.
5. **services#61's loot note is framed wrong.** Folding `dayz_loot` into `dayz_economy` was the
   deliberate services#51 decision (the 3-database rule), not a mismatch to reconcile.
   `NEXT_STEPS_LOOT_2026-09-12.md` is simply stale; its Sessions 4/5 (`LootDbKey.ps1`, a new database)
   are moot.
6. **Stale owner-step text after #59.** MIGRATION.md's Automation section still says "(hourly)",
   tells people to use the nonexistent `--body-file` flag, says key generation must be click-through,
   and calls #58 "blocked" — but the switches are already on. Issue #58 is still open.
   `SECRET-ROTATION.md` §8's deploy-key table still says "Pending — key not yet generated".
7. **Injection-prone `${{ }}` interpolation inside `run:` scripts:**
   `echo "${{ secrets.SITE_CHERNARUS_DEPLOY_KEY }}"` and `RESULT="${{ steps.sync.outputs.SYNC_RESULT }}"`
   in sync, and `BODY="${{ steps.check.outputs.OUTPUT }}"` in monitor. Also,
   `OUTPUT=$(node src/check.js)` captures stdout only, so a connection error's message never reaches
   the alert.
8. **`rotate_deploy_key.py` passes the private key as an argv string** (`--body <key>`), which is
   visible in the process list while `gh` runs. Feeding exact bytes on stdin via
   `subprocess.run(..., input=...)` avoids that. The stdin newline bug recorded in memory is specific
   to PowerShell pipelines; the code comment misapplies it.
9. **Rotation is documented but not scheduled.** `--rotate-title` has never run live, and nothing
   reminds anyone at the quarterly mark (due 2026-12-14).
10. **Actions minutes (zero-cost rule).** Services is private, under a User account (2,000 free
    min/month shared by all private repos, billed per job, rounded up). Throttling keeps real
    cadence well below the cron (see 3), so the actual burn is unmeasured, not ~1,700 min/month. The
    billing API needs a `user` scope this CLI doesn't have. Hourly sync still isn't justified: rows
    land switched off, so latency doesn't matter.
11. **Migration gate coupling.** Any migration merged to `db/economy` stops catalog-sync until it's
    applied live. The gate is correct, but nothing documents the same-day-apply rule, and with no
    webhook nobody notices the stall.
12. **Minor.** `node-version: 20` in both workflows triggers the Node 20 deprecation annotation;
    `sync-catalog.js` has no CI test.
13. **Process mistake.** The session ran `git worktree remove --force` on `aegis-core/_wt-core-pr39`
    without checking it first. The branch was intact (PR #39 already merged) and the worktree has
    been recreated, but any uncommitted changes in it were lost. Don't force-remove worktrees.

## Model policy

| Model | Use for |
|---|---|
| **Sonnet 5** | Both lanes. Each has a concrete file list, a written Do, and a Done-when. |

---

## Round 0: owner only (GitHub/Discord clicks, no Claude). Round 1 can run at the same time.

1. **Create the alert webhook (fixes findings 1–2, and ops-scheduled's alerts too).** In Discord:
   pick an ops channel → Edit Channel → Integrations → Webhooks → New Webhook → Copy Webhook URL.
   Then in GitHub: `services` → Settings → Secrets and variables → Actions → New repository secret →
   name `DISCORD_WEBHOOK_OPS`, paste the URL, Add secret. Don't paste the URL into chat.
2. **Check Actions usage (finding 10):** GitHub → your avatar → Settings → Billing and plans → Usage.
3. *Optional:* narrow `"Bash(ssh-keygen:*)"` by moving it from `<USER_HOME>\.claude\settings.json`
   (applies everywhere, and also allows things like `ssh-keygen -R`) to
   `<USER_HOME>\GitHub\aegis-core\.claude\settings.local.json` (only where the tool lives).

---

## Round 1: run Lane C and Lane S in parallel (different repos, no open PRs in either)

### Lane C — core: deploy-key tool hardening + first real rotation (Sonnet 5)

Open a fresh worktree off `origin/main` in `aegis-core`.

- **Read:** `tools/rotate_deploy_key.py`, `tools/test_rotate_deploy_key.py`,
  `docs/ops/SECRET-ROTATION.md` (§8 only).
- **Do:**
  - **(a) Stop passing the key on argv.** Pass the private key to `gh secret set` via
    `subprocess.run([...], input=key_bytes)` instead of `--body`. Correct the code comment (the
    newline bug was PowerShell-pipeline-specific). Add a test that mocks `subprocess.run` and asserts
    no argv element contains key material. Keep the existing order: secret first, then deploy key,
    then remove the old key, then wipe.
  - **(b) Refresh §8.** Fill in the deploy-key table: added 2026-09-14, next rotation due 2026-12-14.
    Replace "owner must run key generation" with the current state: `Bash(ssh-keygen:*)` is granted,
    so a session can run the tool, but a session still can't grant itself that permission.
  - **(c) Live verification: do a real rotation.** Run
    `python tools/rotate_deploy_key.py --target-repo yodatech1988/site-chernarus --consuming-repo yodatech1988/services --secret-name SITE_CHERNARUS_DEPLOY_KEY --title aegis-services-ci-economy-catalog-sync-2026-09 --rotate-title aegis-services-ci-economy-catalog-sync`.
    Then run `gh workflow run economy-catalog-sync.yml --repo yodatech1988/services`, watch it to
    completion, and confirm the "Fetch site-chernarus Market data" step is green. If it fails, rerun
    the tool (there's no data risk, only a key swap). Record the new key id in the §8 table. This is
    the first live use of `--rotate-title`.
  - **(d) Add a calendar reminder.** Create a Google Calendar event on 2026-12-14 titled
    "Rotate SITE_CHERNARUS_DEPLOY_KEY", with the exact command from (c) (next title
    `…-2026-12`, `--rotate-title` = the current title) in its description.
- **Done when:** `pytest tools/test_rotate_deploy_key.py` passes, the rotation is verified by a green
  sync run, one PR is open in core, and the calendar event exists.
- **Starter prompt:**
  > Read `NEXT_STEPS_ECONOMY_AUTOMATION_2026-09-14.md` at the GitHub root, "Lane C" section only,
  > plus its Read list. Do (a)–(d) in order. One PR in core.

### Lane S — services: workflow hardening, honest docs, close #58 (Sonnet 5)

Open a fresh worktree off `origin/main` in `aegis-services`. **Don't use or remove
`_wt-services-economy-automation`** — another session reused it.

- **Read:** `.github/workflows/economy-catalog-sync.yml`, `.github/workflows/economy-monitor.yml`,
  `db/economy/src/check.js`, `db/economy/MIGRATION.md` (from "## Steps" to "## Commands"),
  `db/economy/docs/AUTOADJUST-CONTRACT.md`, and issue #58.
- **Do:**
  - **(a)** Move the three `${{ }}` interpolations from finding 7 into step `env:` and reference them
    as `$VAR`. Capture check output with `2>&1`.
  - **(b)** Change the sync cron to `22 */6 * * *` and keep `workflow_dispatch`.
  - **(c)** Set `node-version: 22` in both workflows.
  - **(d)** Add a `workflow_dispatch` boolean input `test_alert` to both workflows that forces a
    clearly-labelled `[test]` Discord post, so the alert path can be exercised on demand.
  - **(e)** Fix finding 4. Make the workflow header and MIGRATION.md say exactly what fails and what's
    informational. Add one written decision: whether `audit_stuck_pending` becomes a failure once M6
    is live (recommended: yes). Don't change `check.js` behaviour in this PR unless that decision
    says now.
  - **(f)** Fix findings 5 and 6. Rewrite the loot note to cite services#51 as the decision and state
    that the loot tables are live but empty. Rewrite the Automation owner-steps block to reflect
    reality: #55/#56 done, switches on since 2026-09-14, key made with `tools/rotate_deploy_key.py`,
    no `--body-file`, cadence per (b).
  - **(g)** Add a MIGRATION.md rule: merging a `db/economy` migration means applying it live the same
    day (`EconomyDbKey.ps1 -Run src/migrate.js`); otherwise catalog-sync stalls on its migration gate.
  - **(h)** #58: check `gh run list --workflow=<file> --json event,conclusion` for each workflow. Its
    own gate requires a green **`schedule`-triggered** run of each, not `workflow_dispatch` (see its
    2026-09-14 comment). If both exist, comment with those two run links and close #58. If not, leave
    #58 open and say so in the PR body — don't close it on the manual runs.
- **Done when:** both workflow files parse as YAML, the PR is open, and #58 is either closed with
  schedule-run links or explicitly left open. **After merge:** once Round 0 step 1 is done, dispatch
  both workflows with `test_alert=true` and confirm the Discord posts arrive. Comment the results on
  services#19 (the M1–M8 tracker).
- **Starter prompt:**
  > Read `NEXT_STEPS_ECONOMY_AUTOMATION_2026-09-14.md` at the GitHub root, "Lane S" section only,
  > plus its Read list. Do (a)–(h). One PR in services.

---

## Later (not scheduled yet)

- **CI test for `sync-catalog.js`**: add it to `services-ci.yml`'s `economy-db` job, using a small
  fixture Market dir that includes one deliberately dirty file (to prove the skip-on-warnings path).
- **Loot track**: run `node src/import/loot.js --apply` against live `dayz_economy`, then decide the
  XML generate/deploy path. Belongs in services `docs/PLAN.md`, not this doc.
- **M9 actuator** stays blocked on M6 (bridge hosted) and M7 (cutover). `AUTOADJUST-CONTRACT.md` is
  the spec.
- **services#57**: the services repo has no working Claude credential, so `@claude` on its issues
  gets no reply. That's a separate track.
- **MasterThread `docs/REPOS.md`**: the services row is stale ("`dayz_economy`: `0001` live"). A
  small ledger PR, whenever MasterThread has no open agent PR.
