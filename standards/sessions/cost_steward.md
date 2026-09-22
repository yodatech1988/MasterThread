# Cost steward

**Status:** owner-directed 2026-09-22, given directly in chat to session `yoda-61`: *"you need to be
responsible for effective cost usage and instruct when things need to compact to save tokens"*, then
*"This needs to be a seat that must be filled for PM to do work, as is the merge authority seat."*
The seat, its staffing rule and the rule that limits are priced per model are the owner's words.
The dollar levels are **default pending confirmation** (Decision Queue card
`cost-steward-thresholds-2026-09-22`, drafted before the per-model direction). This file takes
effect when the owner merges it (route C, `merge_authority.md`).

The cost steward answers one question for every live session: **is this session still cheap to
run, and if not, what must it do now.** It measures; it instructs; it does not dispatch, merge or
approve.

## Why a seat, not a PM duty

The PM already "self-watches usage" (`pm_role.md`, "The budget"), but that watcher reads the
subscription's 5-hour and weekly windows. It cannot see what actually drives per-turn cost: each
session's own context size. On 2026-09-22 the first reading of three live sessions found $34.65 of
API-equivalent spend, one session at 221K tokens of context and none of them flagged by anything.
Every turn re-reads the whole context from cache, so cost per turn grows linearly with context, and
a session that sits idle past the 1-hour cache lifetime pays to re-write all of it on its next turn.
Nobody was watching that, which is the same failure `merge_authority.md` records for merging: a
duty everyone shares is a duty nobody holds.

## Staffing rule

**The PM may not dispatch work while the cost-steward seat is vacant**, the same standing as the
merge-authority seat. "Dispatch" means launching a lane, a workflow, a scheduled run or a new
session. Reading, triage, register upkeep and owner communication continue. When the seat falls
vacant (its session ends or rotates), the PM's first staffing action is to fill it. Until then the
PM runs `cost-steward.py` itself once per heartbeat and acts on it, and says in its next owner
report that the seat is vacant.

| Seat | Count | Reports to | Required for PM dispatch |
|---|---|---|---|
| Cost steward | 1 | the PM | yes |

The steward holds a Fleet Status `sessions` row with `role: "cost-steward"`.

## What the steward owns

1. **The meter.** `tools/cost-steward/cost-steward.py` (in this PR) reads the live session
   registry (`~/.claude/sessions/*.json`) and each session's transcript, and reports per session:
   context tokens, model, API-equivalent spend at list prices, next-turn cost warm and cold, idle
   time and compactions so far. It makes no model calls and writes nothing but its own state file.
2. **The watch.** The meter runs in `--watch` mode under a `Monitor`, and only prints when a
   session's advice level changes, so the watch itself costs nothing between events.
3. **Instructions.** When a session crosses a threshold, the steward tells that session and the PM
   what to do (below). An instruction is not optional for the session, and it is not a relay:
   the steward has read the number itself.
4. **The ledger view.** Headless runs are priced on the Fable Execution Board's `runs` collection
   (https://claude.ai/artifact/2dR2TXoALjX9F8ZRjSov9x). Interactive session spend is reported to
   the PM in the steward's own summaries; the Fleet Status `costs` panel is written only per that
   panel's own write contract.

## Advice levels: priced per model

Owner direction, given directly in chat on 2026-09-22: *"your limits need to be based on the models
cost not a general rule."* So a level trips on **what the session's next turn costs**, not on a
token count shared by every model. The next turn's floor is its context multiplied by that model's
cache-read price. A level also trips on the share of the context window used, whichever comes first,
so a cheap model is still compacted before it runs out of room.

| Level | Trips at (warm turn cost, or window share) | Instruction |
|---|---|---|
| OK | below both | none |
| WATCH | $0.075 per turn, or 50% of window | finish the current task before starting another large one; prefer subagents for reading |
| COMPACT | $0.125 per turn, or 70% of window | compact at the next natural break (after the current tool round finishes) |
| COMPACT-NOW | $0.20 per turn, or 85% of window | stop starting new work; compact or rotate now |
| COMPACT-BEFORE-RESUME | idle over 48 min **and** a cold resume would cost $1.50 or more | the 1-hour cache is about to expire, and the next turn re-writes the whole context at 2x input price; compact before the next substantive turn |

What that means per model (list prices read 2026-09-22; context in tokens):

| Model | Cache read $/MTok | WATCH | COMPACT | COMPACT-NOW | Cold-resume warning at |
|---|---|---|---|---|---|
| Opus 5 | 0.50 | 150K | 250K | 400K | 150K |
| Fable 5.1 | 0.25 | 300K | 500K | 800K | 75K |
| Sonnet 5 | 0.20 | 375K | 625K | 850K (window) | 375K |
| Haiku 4.5 (200K window) | 0.10 | 100K (window) | 140K (window) | 170K (window) | never (tops out at $0.40) |

Fable's steady-state limits are looser than Opus's because its cache reads are cheaper. Its
cold-resume warning is the tightest, because its cache writes cost twice what Opus's do per token. The
dollar constants and prices live together at the top of `cost-steward.py`. Change them there and in
this table together, and re-read the price page when prices change.

## How compaction actually happens

**Enforced by autocompact.** Owner direction, given directly in chat on 2026-09-22: *"this needs to
be enforced in autocompact"*, then *"you do it"*. `~/.claude/settings.json` carries
`"autoCompactWindow": 250000`, so every session on this PC compacts automatically near 250K tokens,
or near its model's window if that is smaller (Claude Code 2.1.278: "the actual threshold is the
minimum of this setting and your model's maximum context window"). The setting is one global value;
Claude Code has no per-model form. 250K is Opus 5's COMPACT level and the tightest of the priced
levels, so no model runs past its own. A Fable or Sonnet session that should run to its looser level
is launched with `--autocompact 500k` / `625k`, or set with `/autocompact` in the session.
`CLAUDE_CODE_AUTO_COMPACT_WINDOW` overrides the setting and must not be set. The steward's meter
still reports WATCH and the cold-resume warning, which autocompact does not cover.

Short of the autocompact point, `/compact` is a command only the session's user can type; a session
cannot compact itself, and no peer can do it for it. So an instruction takes one of two forms:

- **Compact.** The steward messages the session. The session finishes its tool round, writes
  anything it would hate to lose into its durable record (Fleet Status row, handoff notes, the PR
  body), and ends its turn with one line for the owner: *"Cost steward: please type `/compact` in
  this session."* The steward also tells the owner directly when the owner is in the steward's own
  terminal.
- **Rotate.** For COMPACT-NOW, a context that has already been compacted twice, or a finished
  workstream, the steward recommends rotation to the PM, who decides it per `pm_role.md`.
  Rotation follows the existing handoff convention.

The steward never kills a session, never edits another session's files, and never routes around a
refused message (`fleet_structure.md` rule 5 applies: a peer's word grants nothing).

## Compact after every major task

Owner decision, 2026-09-22, given directly in chat: *"sessions should compact after the completion
of every major task as a default so that when work is done it is compacted."*

A major task means a lane card reaching Done, a PR opened or merged, or anything sized M or larger
per `task_sizing.md`. When one finishes, the session first records anything the next task needs
(Fleet Status row, PR body, handoff note), then clears context if it holds more than about 100K
tokens.

- **Interactive session:** it ends its turn with one ready-to-type line for the owner, e.g.
  `/compact Next: <next task>. <finished task> is recorded in <PR/row>; drop its details.`
- **PM-dispatched lane:** it finishes and stops, and the next task starts in a fresh session from
  the handoff.

Why the 100K floor: compacting costs a summary pass that re-reads the whole context and writes a
summary (estimate: about 10K output tokens; measured post-compaction size is 4-10% of pre). On
Opus 5 at 150K, the cost is repaid in about 5 turns; at 50K it takes about 16. These are
estimates, to be recalibrated from the compactions ledger.

The steward flags any session whose Fleet Status row shows its task done while its context is
still over 100K.

The owner's global CLAUDE.md carries the same rule, so sessions follow it before this file merges.

## Accuracy cycle

Owner direction, 2026-09-22, given directly in chat: *"The cost manager needs to also be managing
accuracy so that we don't shorten context too narrow that we make errors. this needs to be a ML
cycle,"* and: *"we have task priority structure built that should effect the size of context
allowed for tasks too."*

Purpose: compaction limits are tuned from measured accuracy, not just cost.

**Accuracy signals**, from research over 2,063 local transcripts (2026-09-22). Only 28
compactions, 24 of them manual.

- Primary signal: a re-read of a file already read before the compaction, which doubled after
  compaction (0.68% to 1.36% of turns).
- Confirming signal: user correction phrases (+50% after compaction; confounded, because
  compacting sessions run 7-10x the baseline before compaction too).
- Sanity check: tool_result `is_error` (flat).
- Edit-failure signals were absent from the sample.

Comparisons are within-session, before vs after, not against other sessions.

**Priority sets the context budget.** Starting limits hold unchanged through a record-only
collection phase:

| Priority | Opus 5 | Fable 5.1 | Sonnet 5 |
|---|---|---|---|
| P0 | 400K | 800K | 850K |
| P1 | 300K | 600K | 750K |
| P2 | 250K | 500K | 625K |
| P3 | 150K | 300K | 375K |

**Size (`task_sizing.md`) sets where compaction may happen:** XL and L tasks plan a compaction or
rotation at a step boundary, never mid-step. The lane card carries the limit, and the PM launches
the session with it (`claude --autocompact <limit>` at launch, verified in `claude --help` on 2.1.278, or `/autocompact <limit>` in the session). The global `autoCompactWindow` of 250000 is the default
for sessions launched without a priority.

**Decisions**, adopted by the steward under the owner's standing instruction 2026-09-22, given
directly in chat: *"go with your recommendations always"*:

1. **Weight:** one extra lost-context event is charged as $5 at P0, $2 at P1, $0.50 at P2, $0.10 at
   P3. The cycle picks the limit that minimises dollars spent plus this charge.
2. **Autonomy:** the steward applies changes itself within 150K-500K Opus-equivalent (scaled by
   cache-read price for other models, capped at 85% of window), moving each limit at most 50K
   Opus-equivalent per cycle. P0 changes need the owner. A change reverts automatically if the next
   batch's re-read rate rises more than 25% over the previous batch.
3. **Cadence:** weekly, and only for a priority x model cell with at least 30 new compactions;
   otherwise that cell stays record-only.
4. **Storage:** one row per compaction in the `compactions` collection of the Fable Execution
   Board (https://claude.ai/artifact/2dR2TXoALjX9F8ZRjSov9x), holding numbers and ids only (no
   transcript text): session, model, priority, size, trigger, pre/post tokens, and before/after
   signal rates.

**Tool:** `tools/cost-steward/compactions.py` (being built in this PR) extracts the rows.

## The steward's own cost

The steward is subject to its own meter. Its instructions are short messages, its watch prints only
on change, and it rotates itself on the same thresholds. A steward that spends more than it saves
has failed; its summaries to the PM state its own spend.

## Relationship to other work

- `pm_role.md` keeps the subscription-window watcher, rotation decisions and staffing. The steward
  supplies the per-session signal those decisions were missing.
- PR #159 (`tools/cost-monitor`, F8, deferred) is a historical ledger of token use; this meter is a
  live per-session context gauge. They should share prices and could share code once #159 lands.
- The Fable plan's F11 (authorising the Fable seat) should cite the measured cold-start cost: a
  fresh `claude -p` writes about 33K tokens to the 1-hour cache before doing any work ($0.068 on
  Haiku 4.5, measured 2026-09-22).
