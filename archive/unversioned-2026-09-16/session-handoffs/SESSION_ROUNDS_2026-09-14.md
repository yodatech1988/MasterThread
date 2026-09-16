# Session rounds (prepared 2026-09-14)

Supersedes nothing standing — `SESSION_ROUNDS_2026-09-12.md`'s rounds are all closed out; this is a
fresh round for the aegis-mods removed-mod-family replacement work. Rules from MasterThread
`standards/sessions/session_plan_standard.md`: one session = one conversation, at most one open
agent PR per repo, read only the Read list. Full detail lives in `aegis-mods` `docs/PLAN.md`; this
sheet is just the paste-ready round.

## What GitHub looks like right now (verified 2026-09-14)

- **The Terje-family purge is done and merged.** Every default branch (core, aegis-mods,
  site-chernarus, MasterThread, AEGIS-Directive) is clean of the removed mod family's name; disk
  files/junctions/Workshop content deleted; git history left alone (current-files-only, by choice).
  AEGIS-Directive was unarchived to fix it and is re-archived.
- **aegis-mods#17** (the replacement plan: `docs/PLAN.md` Sessions 1–15, function inventory,
  contracts) is **merged**. No module code exists yet.
- **MasterThread#30** refreshed the `docs/REPOS.md` aegis-mods row to match (was still pointing at
  the closed, superseded #15).
- **Research-lane issues aegis-mods#9–#14 are all open, zero comments, none started.** These are
  the actual next move — see Round A below.
- **Owner items, still open, not this round's job:**
  - Confirm the removed mod family's 4 Workshop items are unsubscribed *on Steam itself* (local
    junctions/content folders were deleted 2026-09-14, but that doesn't cancel a subscription).
  - Faction-name mapping sign-off (`site-chernarus` `docs/nasdara-factions-and-quests.md`) — needed
    before Session 10 (Start Screen), not before Session 1.

## Model policy (from aegis-mods `docs/PLAN.md`)

| Model | Use for |
|---|---|
| **Sonnet 5** | All six research lanes below; later Sessions 3–5, 7–9, 11–15 once `docs/PLAN.md` spells out the Do |
| **Opus 5** | Session 1 (`AEGIS_Core` — sets the contract everything else follows), Session 2 (sets the perk-hook pattern), Session 6 (death-path changes), Session 10 (spawn-flow interception) |

## Round A: six research lanes, run in parallel now

Each lane is **one fresh conversation opened in the `aegis-mods` repo folder** (not a worktree —
these post to a GitHub issue, they don't commit). Model: **Sonnet 5**. Paste the prompt as-is, let
the lane post its hook map and add the `hook-map-ready` label, then close the conversation.

| Lane | Issue | Starter prompt |
|---|---|---|
| H0 | [#9](https://github.com/yodatech1988/aegis-mods/issues/9) | `Read docs/PLAN.md "Clean-room rule" and "Research lanes" only. Run lane H0: post the hook map to issue #9 and label it hook-map-ready.` |
| H1 | [#10](https://github.com/yodatech1988/aegis-mods/issues/10) | `Read docs/PLAN.md "Clean-room rule" and "Research lanes" only. Run lane H1: post the hook map to issue #10 and label it hook-map-ready.` |
| H2 | [#11](https://github.com/yodatech1988/aegis-mods/issues/11) | `Read docs/PLAN.md "Clean-room rule" and "Research lanes" only. Run lane H2: post the hook map to issue #11 and label it hook-map-ready.` |
| H3 | [#12](https://github.com/yodatech1988/aegis-mods/issues/12) | `Read docs/PLAN.md "Clean-room rule" and "Research lanes" only. Run lane H3: post the hook map to issue #12 and label it hook-map-ready.` |
| H4 | [#13](https://github.com/yodatech1988/aegis-mods/issues/13) | `Read docs/PLAN.md "Clean-room rule" and "Research lanes" only. Run lane H4: post the hook map to issue #13 and label it hook-map-ready.` |
| H5 | [#14](https://github.com/yodatech1988/aegis-mods/issues/14) | `Read docs/PLAN.md "Clean-room rule" and "Research lanes" only. Run lane H5: post the hook map to issue #14 and label it hook-map-ready.` |

**Priority if not all six can run at once: H0 first.** Session 1 (`AEGIS_Core`) reads its output;
the other five feed later sessions (2–5, 6–9, 10–11) that are further out.

A round ends when every lane's hook map is posted (no PR to merge — these are pure research). Then
move to Round B.

## Round B: Session 1, once lane H0 is posted

One conversation, opened in the `aegis-mods` repo folder, model **Opus 5**:

> `Read docs/PLAN.md Session 1 only. Build AEGIS_Core.`

This is the first real module and sets the Core API contract every later session depends on —
don't start Session 2+ before this one's PR merges (rule 4: one open PR per repo).

## After that

Sessions 2 (Skills framework + Immunity/Medicine), then 3–5 (remaining skills), 6–9 (Medicine), then
10–11 (Start Screen, gated on the faction-mapping owner decision), then the pre-existing backlog
(12–15). Each has its own Read/Do/Done-when/starter prompt already written in `docs/PLAN.md` —
no new planning needed, just run them in order, one PR at a time, per rule 4.
