# Session rounds (prepared 2026-09-12, third pass)

Supersedes the serial queue in `NEXT_STEPS_2026-09-12.md`. Each lane is one fresh Claude Code
conversation opened **in the repo folder or worktree named for the lane**, with the model set via
`/model`, the prompt pasted as-is, and the conversation closed once the PR is open. Rules come from
MasterThread `standards/sessions/session_plan_standard.md`: one session = one PR, at most one open
agent PR per repo, read only the Read list. Parallelism is across repos, never two sessions in one repo.

## What GitHub looks like right now (verified 2026-09-12 evening)

- **Claude CI review is off in every repo.** Green `review / review` checks (core#46, site#46/#47)
  skipped with `No ... ANTHROPIC_API_KEY ... secret configured -- skipping Claude review`. Red ones on
  older PRs are stale runs from before the secret went away. **Green means skipped.** CI spend is zero.
- core#43 (review cap), core#45 (zero-cost rule) and core#46 (auto-merge gate) are merged; the gate
  is inert until a key exists. core#42 is rebased onto core#35 and pushed.
- core#35 was blocked by a stale changes-requested review from the review bot (fixed in 4b5c4a5;
  the bot can't re-review). Dismissed 2026-09-12 evening; now CLEAN. Core's branch protection
  requires branches to be up to date, so after each merge the next PR shows BEHIND: click
  "Update branch", let `test`/`scan` rerun, merge.
- site-chernarus #3 and #30 turned CONFLICTING after today's merges; R1-2's triage list must mark
  them rebase or close.
- site-chernarus backlog: 13 open PRs (#3 #16 #18 #19 #20 #22 #29 #30 #32 #35 #37 #46 #47).
  #35 is blocked on a Krasnostav T3 design conflict with merged #39; three options are on #35.
  An unpushed merge attempt sits in `_wt-chernarus-35` at `39fcffc`.
- MasterThread#5 (donations plan, PayPal) open. handymansfield#3, jarvis#1, repo-template#4 merged.
- aegis-mods does not exist yet. `P:\AEGIS_Core`, `AEGIS_Vehicles`, `AEGIS_Aircraft`,
  `AEGIS_HelloWorld` are present.
- Local checkouts are messy (aegis-core on a stale pre-rebase branch with an untracked `assets/`;
  others on merged branches; 11 `_wt-*` and 4 `.worktrees/*` folders). Lane R1-8 cleans up.

## Model policy

| Model | Use for | Reason |
|---|---|---|
| **Sonnet 5** | Session 0 plans with a template and short Read list; sessions whose PLAN.md already spells out the Do; housekeeping | Cheapest model that reliably follows a written spec. Default. |
| **Opus 5** | Sessions that triage many PRs or design a plan from scattered sources (core, site-chernarus, aegis-mods Session 0; aegis-mods import) | A wrong merge/close list costs more than the model delta. |
| **Fable 5.1** | Only the site#35 conflict resolution | Two sessions already collided there. One correct 84-file three-way merge beats a third attempt. |
| Haiku 4.5 | Nothing | Housekeeping touches unpushed work and worktree deletion. |

## Round structure

A round = all lanes start together; it ends when Jeremy merges or closes every lane's PR in one
sitting (~15 min). If fewer terminals are available, run lanes top-to-bottom.

---

## Round 0: Jeremy only (no Claude, ~20 min). Round 1 can run at the same time.

> **Progress (2026-09-12 later):** site#32 merged. Step 5 is done: the site#35 conflict was decided
> in #39's favour and #35 is pushed and CLEAN, so R2-A is no longer needed. Merge order is now
> site#35 -> core#35 -> core#42 -> site#29. Round 1 has not started.
> **Update:** core#35 and core#42 merged. site#29 is red on 66 DUPLICATE_CLASSNAME errors from
> main (Black Market vs hub weapon pairs). Its CI is now real and the check may be right: see the
> comment on site#29. Decision needed: boot test, Black-Market-only, or drop the Black Market copies.

1. **Merge core#35, then core#42.** Site validate goes red afterwards (main has 66 duplicate
   classnames) until site#35 lands. Then **merge site#29.** This closes site#36 without a
   `CORE_READ_TOKEN`. Default decision: no token; core#42's approach.
2. **Merge or close in one pass:** core#41; site-chernarus #16 #18 #20 #22 #30 #32 #46 #47;
   MasterThread#5. All docs-only except #32 (removes BallerZ from `server/dayz.json`).
3. **Close core#39** (skin library goes to `aegis-mods` as `AEGIS_Skins`).
4. **Close site#19** (its wreck premise is false here; its four under-spawn raises and two tag
   fixes become a Round 3 lane).
5. **Pick an option on site#35.** Only Round 2 lane A waits on this.
6. **Confirm the production instance** on site#5 (evidence says `1. Yodatech`). Lane R2-B writes it
   into `core.lock`.
7. **Anthropic key.** Default: leave CI review off through Round 1 (all Round 1 PRs are docs you
   read yourself). Create one workspace-scoped key and put it **only** in `jarvis/.env` (for R2-C).
   Restore the core secret only when you want auto-merge (core#46, merged) back.
8. **aegis-mods signing key**: exists at `P:\Keys\AEGIS_Directive.biprivatekey` (used for PR #1). Back it up outside git.
9. ~~Merge aegis-mods PR #1~~ merged 2026-09-12 (a225360). Still open: the in-game check from site-chernarus#48. Default branch is `master`.

---

## Round 1: eight parallel lanes, all independent, all start now

| Lane | Repo / folder | Model | Output |
|---|---|---|---|
| R1-1 | core, worktree `_wt-core-session0` off `origin/main` | Opus 5 | `docs/PLAN.md` + `CLAUDE.md`, PR, closes #44 |
| R1-2 | site-chernarus, worktree `_wt-chernarus-session0` off `origin/main` | Opus 5 | `docs/PLAN.md` + `CLAUDE.md`, PR, closes #44; triage comment on #40 |
| R1-3 | aegis-services | Sonnet 5 | PLAN + CLAUDE, PR, closes #9 |
| R1-4 | claude-agents | Sonnet 5 | PLAN + CLAUDE, PR, closes #5 |
| R1-5 | aegis-website | Sonnet 5 | PLAN + CLAUDE, PR, closes #15 |
| R1-6 | aegis-mods (exists; PR #1 merged) | Opus 5 | PLAN, PR |
| R1-7 | handymansfield | Sonnet 5 | Session 1 PR (framework + job-intake) |
| R1-8 | `C:\Users\yoda_\GitHub` root | Sonnet 5 | no PR: close MasterThread #1 #2, prune worktrees, reset checkouts |

Worktree setup for R1-1 and R1-2 (run in the repo folder before opening the session):

```
cd C:\Users\yoda_\GitHub\aegis-core
git fetch origin; git worktree add ..\_wt-core-session0 -b agent/core/session-0-plan origin/main
cd C:\Users\yoda_\GitHub\aegis-site-chernarus
git fetch origin; git worktree add ..\_wt-chernarus-session0 -b agent/site-chernarus/session-0-plan origin/main
```

### R1-1 core Session 0 (Opus 5, open in `_wt-core-session0`)

```
Follow C:\Users\yoda_\GitHub\MasterThread\standards\sessions\session_plan_standard.md Session 0 for this repo (issue #44), using C:\Users\yoda_\GitHub\MasterThread\standards\sessions\PLAN_template.md. Read only README.md, docs/OUTSTANDING.md, the open issue and PR titles (gh issue list; gh pr list), and the docs those name. Facts to fold in: (1) the pr-review workflow currently skips on every PR because no ANTHROPIC_API_KEY secret is set, so a green review check means skipped; (2) key rotation (#5) and the vendored drift check (#35/#42) must become numbered sessions, not live only in issues; (3) #39 belongs in aegis-mods per the Workshop mod standard, recommend closing it; (4) #7 and #8 are owner-only checks. "Backlog first" must list every open PR as merge/close/rebase with one reason. Write docs/PLAN.md and a <=15-line CLAUDE.md, commit on this branch, open one PR, and tell me which MasterThread REPOS.md row to update. Don't read the source tree.
```

### R1-2 site-chernarus Session 0 (Opus 5, open in `_wt-chernarus-session0`)

```
Follow C:\Users\yoda_\GitHub\MasterThread\standards\sessions\session_plan_standard.md Session 0 for this repo (issue #44), using C:\Users\yoda_\GitHub\MasterThread\standards\sessions\PLAN_template.md. Read only README.md, STATUS.md, docs/aegis-chernarus-golive-plan.md, issues #41 and #40 (body plus last three comments each), and the 13 open PRs' titles and descriptions. Do not open server/ or any Market file. "Backlog first" must give one line per open PR: merge / close / rebase, with the reason; post that same list as a comment on #40. Known: #35 is blocked on a Krasnostav T3 design conflict with merged #39 and gets its own session; #19 is recommended close; #29 merges after core#42. Sequence the sessions from #41's phases and do not schedule Phase 1.1 before Phase 0's exit criterion. Write docs/PLAN.md and a <=15-line CLAUDE.md, commit on this branch, open one PR, and tell me which MasterThread REPOS.md row to update.
```

### R1-3 services Session 0 (Sonnet 5, open in `aegis-services`)

```
Follow C:\Users\yoda_\GitHub\MasterThread\standards\sessions\session_plan_standard.md Session 0 for this repo (issue #9), using C:\Users\yoda_\GitHub\MasterThread\standards\sessions\PLAN_template.md. Read only README.md, the open issue and PR titles, docs they reference, and the "claude-agents" and "What needs Jeremy" sections of C:\Users\yoda_\GitHub\aegis-core\docs\OUTSTANDING.md. admin-bot is the only live agent; RCON comes from the be-rcon submodule. Write docs/PLAN.md and a <=15-line CLAUDE.md, branch agent/services/session-0-plan, open one PR, and tell me which MasterThread REPOS.md row to update.
```

### R1-4 claude-agents Session 0 (Sonnet 5, open in `claude-agents`)

```
Follow C:\Users\yoda_\GitHub\MasterThread\standards\sessions\session_plan_standard.md Session 0 for this repo (issue #5), using C:\Users\yoda_\GitHub\MasterThread\standards\sessions\PLAN_template.md. Read only README.md, the open issue and PR titles, docs they reference, and the "claude-agents" section of C:\Users\yoda_\GitHub\aegis-core\docs\OUTSTANDING.md. Apply the zero-cost-first rule: no new hosted service or paid API in any session without a "You" step. Write docs/PLAN.md and a <=15-line CLAUDE.md, branch agent/claude-agents/session-0-plan, open one PR, and tell me which MasterThread REPOS.md row to update.
```

### R1-5 website Session 0 (Sonnet 5, open in `aegis-website`)

```
Follow C:\Users\yoda_\GitHub\MasterThread\standards\sessions\session_plan_standard.md Session 0 for this repo (issue #15), using C:\Users\yoda_\GitHub\MasterThread\standards\sessions\PLAN_template.md. Read only README.md, STATUS.md, issues #15 and #3, and docs they reference. Issue #3 (build.py lost; site never deployed to Cloudflare Workers) is Session 1; the Cloudflare connector is not authorized in this environment, so deployment is a "You" step. The donations plan (MasterThread docs/DONATIONS_PLAN.md, PayPal, no perks) needs a page in a later session. Write docs/PLAN.md and a <=15-line CLAUDE.md, branch agent/website/session-0-plan, open one PR, and tell me which MasterThread REPOS.md row to update.
```

### R1-6 aegis-mods Session 0 (Opus 5, open in `C:\Users\yoda_\GitHub`)

```
The repo yodatech1988/aegis-mods already exists and is cloned at C:\Users\yoda_\GitHub\aegis-mods (created 2026-09-12). PR #1 (AEGIS_Metrics) is merged; start with git checkout master; git pull. Follow C:\Users\yoda_\GitHub\MasterThread\standards\sessions\session_plan_standard.md Session 0 there. Read only C:\Users\yoda_\GitHub\MasterThread\standards\dayz\workshop_mod_standard.md (all of it, especially "Repo layout", "Contract: module.json" and "Where existing work goes"), the session plan standard and PLAN template, and the folder names under P:\ (dir P:\AEGIS_*; do not read their contents). Session 1 is the import of P:\AEGIS_Core, AEGIS_Vehicles, AEGIS_Aircraft, AEGIS_HelloWorld with junctions and a HelloWorld boot test. AEGIS_Metrics is already imported with tools/build.ps1 and tools/boot-test.ps1 (PR #1, site-chernarus#48), so reuse those tools and record Metrics as done in the plan. later sessions are one module each, including PvPGuard (from site-chernarus#43) and Skins (from core#39 / the local dayz-skin-library folder). The AEGIS signing key and the Workshop publisher account are "You" steps. Write docs/PLAN.md and a <=15-line CLAUDE.md, branch agent/aegis-mods/session-0-plan, open one PR, and tell me the MasterThread REPOS.md row to add.
```

### R1-7 handymansfield Session 1 (Sonnet 5, open in `handymansfield`)

First, in the folder: `git checkout main; git pull` (PR #3 is merged). Then:

```
Read docs/PLAN.md Session 1 only. Build the agent framework and job-intake agent, open one PR.
```

You: confirm the goal paragraph and the Rates table on the PR.

### R1-8 housekeeping (Sonnet 5, open in `C:\Users\yoda_\GitHub`)

```
Housekeeping only; open no PRs and delete nothing that is unpushed. (1) Close MasterThread issues #1 and #2 with the comment "Obsolete: predates the 2026-09-12 session plan (docs/REPOS.md)." (2) For each of aegis-core, aegis-site-chernarus, aegis-website, aegis-services, claude-agents, jarvis, MasterThread, handymansfield, repo-template: if the checked-out branch's PR is merged or the branch is behind and its work exists on origin, checkout the default branch and pull; if the branch has unpushed commits or untracked files, list them and leave the repo alone. Known: aegis-core's a8dc166 is the pre-rebase copy of core#42, superseded by origin/ci/validate-without-core-token; verify with git diff before discarding. aegis-site-chernarus has an untracked Ko-fi kit that is obsolete (donations use PayPal) and rs_tmp.yml; show me both before deleting. (3) For every worktree under C:\Users\yoda_\GitHub\_wt-* and C:\Users\yoda_\GitHub\.worktrees\*: remove it (git worktree remove, then git branch -d) only if its branch is merged into the remote default branch and has no unpushed commits; keep _wt-chernarus-35 (unpushed merge attempt for site#35). (4) Print one table: folder, branch, action taken, reason.
```

**Round 1 merge batch (Jeremy):** merge the six Session 0 PRs and handymansfield's Session 1 PR.
Update the seven REPOS.md rows in one MasterThread PR after #5 is merged (or hand it to R2-H).

---

## Round 2: after Round 0 merges and Round 1 plans are in (up to 8 lanes)

| Lane | Repo / folder | Model | Waits on | Output |
|---|---|---|---|---|
| R2-A | site-chernarus, `_wt-chernarus-35` | **Fable 5.1** | Jeremy's option on #35; core#42 + site#29 merged | #35 rebased under the chosen design, validate green, proof comment |
| R2-B | site-chernarus, new worktree | Sonnet 5 | Round 0 steps 1 and 6 | tick #41 items 0.1 and 0.7: `core.lock` set, one PR with a real `validate` run |
| R2-C | jarvis | Sonnet 5 | key in `jarvis/.env` | Session 1: three live prompts work |
| R2-D | aegis-mods | Opus 5 | R1-6 merged | Session 1: import the remaining `P:\AEGIS_*` modules, HelloWorld boot test. Metrics, `build.ps1`, `boot-test.ps1` and the signing key are already done (PR #1). |
| R2-E | website | Sonnet 5 | R1-5 merged | Session 1 per its plan (build.py rewrite) |
| R2-F | services | Sonnet 5 | R1-3 merged | Session 1 per its plan |
| R2-G | claude-agents | Sonnet 5 | R1-4 merged | Session 1 per its plan |
| R2-H | core | Sonnet 5 | R1-1 merged | Session 1 per its plan |

R2-C through R2-H use the starter prompt their own `docs/PLAN.md` gives for Session 1. Do not
invent others. handymansfield Session 2 joins Round 2 only once the rates are confirmed on the
Session 1 PR.

### R2-A site#35 conflict resolution (Fable 5.1, open in `_wt-chernarus-35`)

```
Jeremy chose option <N> on site-chernarus PR #35. Read only PR #35's last three comments, PR #39's description, the Phase 0 section of docs/aegis-chernarus-golive-plan.md, and docs/economy-data-guide.md. Bring branch merge-main-35 (existing unpushed attempt at 39fcffc) up to date with origin/main under that option: item-level three-way merge of the Market files, hand-assemble Assault_Rifles_T3, Sniper_Rifles_T3 and BlackMarket so one classname has one buy surface and one price rule, and make no other economy change. Run python validate.py; zero duplicate classnames on the result. Push to PR #35's branch, post a proof comment listing every file that differs from both parents, and update the PR description to match the 4-commit reality.
```

### R2-B pipeline trust close-out (Sonnet 5, new worktree off `origin/main`)

```
Read only issue #41 (Phase 0), issue #5, core.lock, and sync/README.md. Jeremy confirmed the production instance is "<name>" on #5. Set core.lock production_instance to it, open one PR on agent/site-chernarus/phase0-closeout, wait for the validate check, confirm from its log that validate.py actually ran (not skipped), then comment on #41 with the run link and tick 0.1 and 0.7. Close #36 if the run is real.
```

---

## Round 3 (sketch; fill in after Round 2)

- site-chernarus, one lane at a time: 1.1 re-run validate on every open site PR and fix findings;
  the "every gun to its §5b nominal" PR from #40; the `Launchers_T4.json` duplicate-spelling PR; the
  salvage of #19's four raises and two tag fixes. All Sonnet 5.
- jarvis Session 2, handymansfield Session 2/3, aegis-mods Session 2, website/services/claude-agents
  Session 2: their plans' starter prompts, Sonnet 5.
- Phase 2 decisions (four answers on #41) are Jeremy's; no lane.
- Nothing in Phase 3+ until Phase 1 exits and the `nasdarasync` credentials go to one named session.

## Deliberately not in this plan

- Restoring CI review keys in site/services/website (deferred by Jeremy).
- Buffing zombie reputation (T3 is an AI-kill gate).
- Any MasterThread PR while #5 is open; REPOS.md row updates batch after Round 1.
- Cloudflare deployment (connector not authorized here).
