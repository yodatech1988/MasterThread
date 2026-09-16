# Next steps after token reset (prepared 2026-09-12, evening)

> **Superseded 2026-09-12 (third pass) by `SESSION_ROUNDS_2026-09-12.md`** in this folder: the
> same work re-cut into parallel rounds with a model and paste-ready prompt per lane. Item A is done.

Preliminary GitHub review, all yodatech1988 repos. Written while the token budget was near zero;
nothing below was changed on GitHub. Merge decisions are Jeremy's.

## What GitHub looks like right now

| Repo | Open PRs | Open issues | Signal |
|---|---|---|---|
| core | 5 (#35 #39 #41 #42 #45) | 4 (#44 #8 #7 #5) | Every PR's `review / review` check FAILS. Run makes zero model calls (`modelUsage: {}`, `is_error: true`, ~26 s). That is the key problem in core#5 (exhausted / org-scoped ANTHROPIC_API_KEY), not a workflow bug. `validate` and `scan` pass. |
| site-chernarus | 11 (#3 #16 #18 #19 #20 #22 #29 #30 #32 #35 #37) | 7 (#44 #41 #40 #36 #7 #6 #5) | All checks green, but green means nothing here (#36: no CORE_READ_TOKEN, validate is a no-op). Backlog down from 15 to 11; #38 #39 #42 #43 #45 merged today. |
| services / website / claude-agents | 0 | 1 each (Session 0 plan issues) + website#3 | Idle, waiting for Session 0. |
| jarvis | 0 | 0 | PR #1 merged today. Next: Session 1 needs the key in `.env`. |
| MasterThread | 0 | 2 stale (2025) | Ledger `docs/REPOS.md` is current as of today. |
| handymansfield | 1 (#3, Session 0 plan) | 0 | Waiting on Jeremy review. |
| repo-template | 0 | 0 | PR #4 merged; template is on the session standard. |

Go-live tracker site-chernarus#41: still in **Phase 0** (pipeline trust). No box is checked.
Nothing has reached a server.

## Blocked on Jeremy (do these first, they unblock everything)

1. **Fix the Anthropic key (core#5).** Create a workspace-scoped key in console.anthropic.com,
   put it in core's `ANTHROPIC_API_KEY` secret. Until then every core PR shows a red check and
   Claude review is dead. Tooling exists: `tools/rotate_secret.py --target anthropic-key`.
   Same key (or a second one) goes into `jarvis/.env` for jarvis Session 1.
2. **Confirm the production instance (site-chernarus#5)** and set `core.lock`
   `production_instance`. Evidence points to "1. Yodatech". Phase 0.1.
3. **Merge order for Phase 0:** site-chernarus#35 -> core#35 -> core#42 (after rebase, see
   Claude item A) -> site-chernarus#29. `gh pr merge` is denied to the agent; you merge.
4. **Add `CORE_READ_TOKEN`** to site-chernarus (fine-grained PAT, repo `core`, Contents: read),
   or accept core#42's approach which removes the need. Either closes #36. Pick one.
5. **Decisions with a recommendation already written:** #19 vs merged #33 (recommend close #19,
   its wreck premise is false in this repo); Phase 2 items 2.1 to 2.4 on #41; the 8 empty trader
   tabs (#6, recommend accept).
6. **Docs PRs to merge or close in one sitting:** core#41 #45; site-chernarus #16 #18 #20 #22
   #30 #32. None touch `server/` except #32 (removes BallerZ from `dayz.json`).
7. **core#39 (skin library):** the Workshop-module rule sends this to `aegis-mods` as
   `AEGIS_Skins`. Recommend close #39 and let the aegis-mods plan absorb it.

## Claude session queue (one worktree, one PR each, in this order)

A. **core: rebase #42 onto #35 and re-prove** (Phase 0.5). Small, mechanical, unblocks #36.
   Do this first when tokens reset; it is the only Phase 0 item that is Claude's.
B. **core Session 0 (#44): write `docs/PLAN.md`.** Read list: `docs/OUTSTANDING.md`, the open
   PR titles above, MasterThread session standard. Fold the key-rotation and drift-check work
   into sessions so they stop living only in issues.
C. **site-chernarus Session 0 (#44): write `docs/PLAN.md`.** First job per the ledger is the
   11-PR backlog: for each PR write one line "merge / close / rebase" with the reason, post as a
   comment on #40, and let Jeremy act on the list in one pass. Phase 1.1 (re-run validate on
   every open PR) only after Phase 0 exits.
D. **aegis-mods Session 0:** create the repo from repo-template, write `docs/PLAN.md` from the
   Workshop standard's "Where existing work goes" table. Session 1 (import `P:\AEGIS_*`) is
   the highest-value unbacked-up work in the whole estate but needs the signing key from Jeremy.
E. **services #9, claude-agents #5, website #15 Session 0s.** Cheap, independent, can run as
   parallel subagents once A to C are done.
F. **jarvis Session 1:** live-test once the key is in `.env`.

Skip until asked: adding review keys to services/site-chernarus/website (deferred by Jeremy),
buffing zombie reputation (T3 is an AI-kill gate), anything in Phase 3+ of #41.

## Housekeeping (cheap, any time)

- MasterThread issues #1 and #2 are from 2025-11 and predate the current plan. Close as obsolete.
- Nine `_wt-*` worktree folders sit in `C:\Users\yoda_\GitHub`. Prune the ones whose PR is
  merged (`_wt-core-review-cost` = core#43, `_wt-chernarus-golive-plan` = #42,
  `_wt-chernarus-pvpguard` = #43, `_wt-chernarus-questlines` = #45, `_wt-website-pr6`).
- core#8 and core#7 (RFFS folder name, HelloWorld import) are Jeremy-only checks against the
  panel and P: drive. Either do them or fold into the aegis-mods plan and close.

## First command when tokens reset

Open Claude Code in `C:\Users\yoda_\GitHub\aegis-core`, then:
"Do queue item A from NEXT_STEPS_2026-09-12.md: rebase core#42 onto core#35 in a new worktree,
re-run the proof, push." Expect one short session.

## Update after the second session (2026-09-12, late)

- **Done: item A.** core#42 rebased onto core#35 and pushed. One real fix added: the vendored drift check no longer crashes when no core token exists. Proof comment on core#42. Tests pass.
- **Merge order unchanged:** core#35, then core#42.
- **Warning before merging core#42:** site validate turns red on every PR. Main has 66 duplicate classnames, not 7.
- **Blocked: site-chernarus#35.** It contradicts merged #39 on whether Krasnostav sells T3 rifles. Three options posted on #35. Needs Jeremy's decision, then one short session.
- **Stale local checkout:** aegis-core's main folder still sits on the old core#42 commit. Reset it or leave it alone. Worktrees `_wt-core-rebase42` and `_wt-chernarus-35` are safe to prune.
