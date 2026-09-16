# DayZ server work plan: parallel session rounds (2026-09-14, afternoon)

## Context

Jeremy asked for a complete GitHub review and a plan for continuing the AEGIS DayZ server work, as
parallel worker sessions with a model and effort for each. `SESSION_ROUNDS_2026-09-14b.md` is now
out of date. Overnight and this morning a lot of it landed:
- site-chernarus #62–#77
- aegis-mods Sessions 1–2 (#31–#33)
- aegis-pricing Sessions 0–2
- the gh-federation Worker deploy

This plan replaces 14b for DayZ work only. handymansfield, jarvis and the finance repos are left
out. On approval it gets saved as `GitHub\SESSION_ROUNDS_2026-09-14c.md`, with 14b marked
superseded.

### Live GitHub state (checked 2026-09-14 ~11:40Z, read from origin)

**Open PRs:** only drafts. aegis-mods #18–#30 (13 research/protocol PRs, never triaged) and aegis-poi #6.

**site-chernarus**
- Everything from last night is merged.
- **`LOOT_DEPLOY_ENABLED` is unset.** Both deploy-loot runs failed on that guard.
- **#77 MiniMap is merged but not deployed.** `dayz.json` isn't in deploy-loot's paths, and the
  folder name still needs confirming on the panel.
- **The vendored `sync/restart_orchestrator.py` is missing core#51's safety fixes:**
  - it swallows TransportError
  - it doesn't abort before `#shutdown`
  - it rolls back on timeout
  - This is a live-restart risk.
- **No Sessions 6+ go-live plan exists.** `docs/aegis-chernarus-golive-plan.md` and `STATUS.md`
  contradict the owner's #41 decisions: production instance, local-then-live, reputation wipe.
- The Status table is stale: Session 3 (#69) is merged.

**aegis-mods**
- Sessions 1 and 2 are merged.
- Lanes H1–H5 are all hook-map-ready.
- Session 3 is next (Sonnet per the plan). Sessions 4 and 6 are unblocked once their order allows.
- The 13 open drafts break the one-open-PR rule.

**aegis-pricing**
- Sessions 0–2 are merged, and the module is live on production.
- Session 3 (in-game verification) hasn't been done. There's no results table and no tags, not even
  v0.1.0.
- Every Status row is wrong.

**aegis-poi:** Session 2 (the POI framework) hasn't started and can now build on AEGIS_Core. Its
Status table is stale.

**core**
- Session 3 branch `agent/core/session3-secret-rotation` is pushed with **no PR**. #5's body cites
  §9/§10, which don't exist on main.
- Sessions 4 and 5 haven't started.
- `serverDZ.cfg` isn't excluded from sync, so rotating a password would get it committed.

**services**
- `ECONOMY_CATALOG_SYNC_ENABLED` is still false, even after the #74 fix. No scheduled run has
  happened yet.
- #78's loot baseline button is merged, but Jeremy hasn't clicked it.
- Stats-api NS1 is unblocked, but Jeremy said "hold off" on website metrics.
- The gateway needs 3 owner steps.
- E5 isn't blocked by the VPS any more; what's left is issuing the Chernarus server token.
- Docs are stale: DATABASES.md, the db/community README, V2–V4 rows, the E5 row, and the item-DB
  next-steps doc.

**claude-agents #14:** the GUID formula, the chat-line format and whether `say` is private all
still need Jeremy in game.

**gh-federation:** deployed at `gh-federation.jeremybergerai.workers.dev`. The selftest repo passed
its pull and ack.

**website:** #3 is done but still open. Session 5 (connect widget) is unblocked. Session 4 waits on
stats-api.

**MasterThread REPOS.md:** the "Do first" table and most Active rows are stale.

**Local:** there are about 100 `_wt-*` worktrees, many of them for merged PRs.

## Rules for every lane

These come from MasterThread's session standard and memory:
- One fresh conversation per lane, opened in the named repo.
- Jeremy runs `GitHub\New-ParallelWorktrees.ps1` for same-repo lanes. A lane never picks its own
  folder.
- At most one open agent PR per repo. Run `gh pr view --json state` before any follow-up push.
- Every lane fixes its repo's `docs/PLAN.md` Status table first, from origin, not the local checkout.
- Live pushes and restarts are Jeremy's clicks, because the auto-mode classifier blocks them. Before
  asking him to rotate anything, check the live state or the `.clixml` mtime.
- Never force-remove a worktree. Zero cost first. Discord stays parked.

**Model and effort key**
| Model | Effort | Used for |
|---|---|---|
| Opus 5 | high | Live production, credentials, contract-setting engine code (xhigh if it misses the done-when bar) |
| Sonnet 5 | high | Big data edits where the invariants matter |
| Sonnet 5 | medium | Normal plan sessions, verification |
| Sonnet 5 | low | Doc-only work |

---

## Round 0: Jeremy (~20 min), in unblock order

1. **Pick a live window.** Be in game on Chernarus. R1-2 and R1-3 share it, and R1-1's MiniMap
   restart can go right before it.
2. **Triage decision (default applied):** `LOOT_DEPLOY_ENABLED` gets flipped to `true` by R1-1 only
   after the orchestrator re-vendor merges. Merging a loot PR then pushes it live.
3. **Click "Import loot (baseline)"** in `EconomyDbKey.ps1` (services#78) and confirm PASS on all 7
   files. This unblocks the item-DB track.
4. **services#57:** run `/install-github-app` for services so PR review actually runs.
5. **Gateway owner steps** (services PLAN gateway track), optional this round:
   - add the ssh and wrangler allow rules to `~/.claude/settings.json`
   - run `PushEnqueueSecrets.ps1`
   - run `PushVpsSecrets.ps1 gateway`
   - run the DNS route
6. **Steam:** confirm you're unsubscribed from the removed mod family's Workshop items.
7. **Say whether the stats/metrics "hold off" is lifted.** The default is still on hold, so R2-6 is
   skipped.

## Round 0.5: worktree cleanup (run alone, before Round 1)

| ID | Open in | Model | Effort |
|---|---|---|---|
| R0-W | `GitHub\` | Sonnet 5 | medium |

> List every git worktree under C:\Users\yoda_\GitHub (_wt-*, _worktrees\*, core-tmp-pr69, aegis-mods-mechanics-wt). For each: git status, unpushed commits, PR state via `gh pr list --head <branch> --state all`. Remove only clean, fully pushed worktrees whose PR is merged/closed, with `git worktree remove` from the owning repo — never --force, never rm, never a main checkout. Keep core's `agent/core/session3-secret-rotation`. Output one table (folder, repo, branch, PR state, kept-why), then `git worktree prune` per repo.

---

## Round 1: parallel now (one lane per repo)

| ID | Repo | Work | Model | Effort |
|---|---|---|---|---|
| R1-1 | site-chernarus | Re-vendor `restart_orchestrator.py` from core, then deploy MiniMap (#77) with Jeremy | Opus 5 | high |
| R1-2 | aegis-pricing | Session 3: in-game price verification with Jeremy, tags v0.1.0/v0.2.0 | Opus 5 | high |
| R1-3 | claude-agents | #14 GUID/chat live confirmation, same in-game window | Sonnet 5 | medium |
| R1-4 | aegis-mods | Session 3: Skills (Metabolism, Athletics, Strength) | Sonnet 5 | high |
| R1-4t | aegis-mods | Triage of drafts #18–#30 and aegis-poi#6 (comments only, **no PR**) | Sonnet 5 | medium |
| R1-5 | aegis-poi | Session 2: `AEGIS_POI` framework on top of AEGIS_Core | Opus 5 | high |
| R1-6 | core | Session 3: finish the pushed secret-rotation branch as a PR | Sonnet 5 | medium |
| R1-7 | services | #58 re-enable catalog sync + stale-docs sweep | Sonnet 5 | medium |
| R1-8 | website | Close #3, then Session 5 connect widget | Sonnet 5 | medium |

R1-4 is Sonnet 5 per plan. Effort is raised to high because the perk hooks set contracts that
Sessions 4–15 consume.

**Why R1-1 comes first on site-chernarus:** every restart, including the MiniMap one and every
go-live push, goes through the vendored orchestrator. Right now it can mistake an old boot log for
success.

**Lane prompts**

**R1-1:**
> Read core's `tools/restart_orchestrator.py` (origin/main, core#51) and site-chernarus `sync/restart_orchestrator.py`. Re-vendor core's version: keep the TransportError-on-boot-log-listing abort before `#shutdown`, rollback only on a real boot failure. Check whether `sync/deploy_loot.py` shares the code path and port its retry/resume if not. Tests. Fix the PLAN Status table (Session 3 = #69 merged; list off-plan #62–#77). One PR. After it merges: walk me through confirming the Workshop 2979165671 folder name on the Shockbyte panel, the restart (players off), and verifying both `.bikey`s landed in `keys/`. Then add MiniMap to `AEGIS-Join-Chernarus.cmd`, and tell me to set `LOOT_DEPLOY_ENABLED=true`.

**R1-2:**
> Read docs/PLAN.md Session 3 only. The module is live on production (site-chernarus#67), not a local server. Step 1: confirm the newest RPT is clean (no (E), no MARKET CONFIGURATION ERROR) via RCON 20196. Stop if not. Step 2: walk me through the verification table in game with `logTrades: 1`, capturing menu price vs charged price. Fix failures. Step 3: fix the Status table (0=#1, 1=#3, 2=#4), record results, tag `AEGIS_Pricing-v0.1.0` at #4's merge and v0.2.0 after. One PR.

**R1-3:**
> Read issue #14 only. I'm in game on Chernarus now (sharing the window with aegis-pricing Session 3). Run `.\scripts\RconKey.ps1 -Run owner-chat-reader`. Confirm OWNER_ONLINE (GUID formula), the chat-line format (OWNER_CHAT vs OWNER_UNPARSED), and whether `say` to a player is private; tell me when to type. If the parser is wrong, fix `packages/chat-ai/src/chatLine.js` citing the captured line. Fill in the LIVE-CONFIRMATION-CHECKLIST GUID section, tick #14, update its stale PR list, fix the Status table (1=#15, 7's #12 merged). PR only if code/docs changed.

**R1-4:**
> Read docs/PLAN.md "Clean-room rule", Session 3, and issues #10/#11 hook maps only. Fix the Status table first (H1–H5 hook-map-ready; Session 2 = #33 merged). Build Session 3 on AEGIS_Core (RPC 19420 sub-dispatch). `boot-test.ps1` must pass with no .mdmp. One PR.

**R1-4t:**
> Read docs/MOD_REVIEW_PROTOCOL.md (from draft #21) and the aegis-mods item-count-budget policy. For each of aegis-mods drafts #18–#30 and aegis-poi#6, produce one row: recommendation (merge as doc / close / keep for a later session), the protocol checklist result, item-count impact, and which PLAN session it would feed. Post the table as a comment on aegis-mods#21 and a one-line pointer comment on each draft. Do not merge, close, or push anything. Then give me the table to decide.

**R1-5:**
> Read docs/PLAN.md Session 2 only. Fix the Status table (1 = #4 merged). Build `AEGIS_POI` on AEGIS_Core from aegis-mods (the plan's "Core isn't imported yet" note is now false; import it). Confirm `P:\Keys\AEGIS_Directive.biprivatekey` exists before building. Done-when per plan: clean vanilla boot, DemoCamp placement correct, object counts stable across restarts, clean removal boot, tag `AEGIS_POI-v0.1.0`. One PR.

**R1-6:**
> Read docs/PLAN.md Session 3 and issue #5 only. Resume the pushed branch `agent/core/session3-secret-rotation` in your worktree (rebase on main). The Anthropic key is done — record it, don't redo it. Complete SECRET-ROTATION.md including the §9/§10 that #5 already cites: VPPAdminTools (`rotate_secret.py --target vpp-admin`), BattlEye admin, DayZ join, and "no service still uses the old value". Check each against live/.clixml mtime before calling it overdue. Flag that `serverDZ.cfg` isn't sync-excluded as a site-chernarus issue (file it). Fix the Status table (0=#50, 2=#58). One PR.

**R1-7:**
> Read issue #58 and docs/PLAN.md "Track: dayz_economy" only. #74 fixed the orphan rows. Ask me to approve `ECONOMY_CATALOG_SYNC_ENABLED=true`, trigger one run, and confirm no orphan inserts. Post run links on #58, and note that the first comment's "both true" is superseded and that alerting is a no-op (Discord parked). Then one docs PR fixing: DATABASES.md and db/community README (VPS live), V2–V4 rows (#69/#70), the E5 row (now "issue Chernarus server token"), and the item-DB next-steps line (#78 merged).

**R1-8:**
> Read docs/PLAN.md Session 5 only. Close #3 with a comment (build.py rewrite + deploy live 2026-09-13). Fix the Status table (2 = #21). Build Session 5. Merges don't deploy; tell me the exact `wrangler deploy` to approve. One PR.

**Round 1 close-out:** R1-Z, MasterThread, Sonnet 5 / medium.
> Rebuild docs/REPOS.md Active rows and "Do first" from live GitHub + origin PLAN.md files only. Mark Do-first 3 done and 8 as "flip METRICS_DEPLOY_ENABLED + restart". Add the Discord-parked note. Mark `SESSION_ROUNDS_2026-09-14b` superseded by 14c. One PR.

---

## Round 2: as each Round 1 lane merges

| ID | Repo | Work | Waits on | Model | Effort |
|---|---|---|---|---|---|
| R2-1 | site-chernarus | Session 4: economy defects (launcher spellings, ammo sell rate, #40 design calls) + reconcile golive doc/STATUS.md with the #41 decisions | R1-1 | Sonnet 5 | high |
| R2-2 | aegis-mods | Session 4 (per plan, H2/H3) | R1-4 | per plan | high |
| R2-3 | aegis-pricing | Session 4: standing label in trader menu | R1-2 | Sonnet 5 | medium |
| R2-4 | core | Session 4: `VENDORED-VALIDATOR.md`, including a CI drift check for vendored `restart_orchestrator.py` | R1-6 | Sonnet 5 | medium |
| R2-5 | aegis-poi | Session 3 (per plan) | R1-5 | per plan | high |
| R2-6 | services | NS1: build stats-api. **Only if Jeremy lifted the hold** | R1-7 | Sonnet 5 | medium |
| — | Jeremy | Decide R1-4t's triage table (merge #21; close or keep the rest) | R1-4t | — | — |

R2-4's effort goes from low to medium because it has to stop the drift R1-1 just fixed from coming
back.

Prompts: use each session's starter prompt from the repo's `docs/PLAN.md`. Add the extra scope
listed in the table above for R2-1 and R2-4.

## Round 3: go-live prep

| ID | Repo | Work | Waits on | Model | Effort |
|---|---|---|---|---|---|
| R3-1 | site-chernarus | Session 5: rarity ↔ price coherence in `HardlineSettings.json` | R2-1 | Opus 5 | high |
| R3-2 | aegis-mods | Session 5, then Session 6 (Opus per plan) | R2-2 | per plan | high |
| R3-3 | core | Session 5: tag `v0.1.0` + a pin issue per consuming repo | R2-4 | Sonnet 5 | low |
| R3-4 | aegis-pricing | Session 5: economy/services integration issues | R2-3 | Sonnet 5 | medium |
| R3-5 | services | E5: issue the Chernarus server token for economy-api (credential) | R1-7 | Opus 5 | high |
| R3-6 | services / website | NS2 deploy stats-api → website Session 4 `status.html` | R2-6 | Sonnet 5 | medium |

R3-6 runs only if the hold is lifted.

## Round 4: Chernarus go-live

| ID | Repo | Work | Waits on | Model | Effort |
|---|---|---|---|---|---|
| R4-1 | site-chernarus | Write Sessions 6+ go-live plan into docs/PLAN.md (no server actions) | R3-1 | Opus 5 | high |
| R4-2+ | site-chernarus | Execute Sessions 6+ one at a time, Jeremy clicking pushes and restarts | R4-1 | Opus 5 | high (xhigh on the push session) |

**R4-1 prompt.** It must cover:
- boot-testing the full `server/` tree on the local E: dev server, with a clean log read
- the AEGIS_Pricing outcome from R1-2 (keep or pull)
- the `@AEGIS_Metrics` install (#48 / `METRICS_DEPLOY_ENABLED`)
- the recruit-trap test (`CanRecruitFriendly`)
- the reputation wipe
- the push sequence: snapshot → whole-tree push through the fixed orchestrator → one quiet-window
  restart → `nasdarasync verify` → `core.lock verified`
- auto-deploy coverage for trader `.map` files, markers and `dayz.json`, to close the #59→#66
  "merged but never pushed" loss pattern
- the announcement, drafted for Jeremy to post by hand
- §6 two-week measurement and tuning PR
- the #6 three-file market push
- which steps are Jeremy's clicks

**After go-live, in order:**
- site-badlands Session 1: 1.29 items into Chernarus, PR in site-chernarus, Sonnet 5 / medium.
- Item-DB rows for approved research modules, per `NEXT_STEPS_ITEM_DB_INCORPORATION`, Sonnet 5 / high.
- site-badlands Session 3, in the Oct 1–5 Shockbyte window, Opus 5 / high.
- aegis-mods Sessions 7–15 and aegis-poi Sessions 4–6, as their plans specify.

## Parked (no sessions)

| What | Why |
|---|---|
| All Discord work (claude-agents 2/7/8/9, gh-federation 4, admin-bot, V3 admin half, V5, EV3) | Discord parked |
| gh-federation Session 5 / bug-report two-hop | Needs Anthropic WIF setup; not DayZ-critical |
| PC pm2 community-api shutdown | One approval, whenever a services lane asks |
| services O5 | Needs an `.ADM` sample |
| Nightly DB backups | Needs `age-keygen` |
| #52 teddy | Waits on Workshop publish |
| gh-federation-selftest repo | Keep until Jeremy says delete (then remove its allow-list entry + redeploy) |
| DayZServer | Archive candidate, Jeremy's call |

## Verification of this plan

- Every "merged / not started" claim above came from `gh` against origin on 2026-09-14 ~11:40Z.
  Each lane still re-checks its own repo's PR list and origin PLAN.md before it starts, because
  parallel sessions landed PRs during this very review (#33, #77).
- A round is done when each lane's PR is merged, its Status row is correct on origin, and any live
  step has a clean RPT read posted to the relevant issue.
- R1-Z's ledger refresh is the checkpoint that confirms Round 1 before Round 2 starts.
