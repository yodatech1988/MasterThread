# Cost steward

**Status:** owner-directed 2026-09-22, given directly in chat to session `yoda-61`: *"you need to be
responsible for effective cost usage and instruct when things need to compact to save tokens"*, then
*"This needs to be a seat that must be filled for PM to do work, as is the merge authority seat."*
The seat and its staffing rule are the owner's words. The numeric thresholds below are **default
pending confirmation** (Decision Queue card `cost-steward-thresholds-2026-09-22`); this file takes
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

## Advice levels (default pending confirmation)

| Level | Trigger | Instruction |
|---|---|---|
| OK | context < 150K | none |
| WATCH | context >= 150K | finish the current task before starting another large one; prefer subagents for reading |
| COMPACT | context >= 250K | compact at the next natural break (after the current tool round finishes) |
| COMPACT-NOW | context >= 400K | stop starting new work; compact or rotate now |
| COMPACT-BEFORE-RESUME | context >= 150K **and** idle > 48 min | the 1-hour cache is about to expire; the next turn will re-write the whole context at 2x input price, so compact before the next substantive turn |

Why these numbers: at 250K tokens on Opus 5, every turn costs about $0.125 in cache reads alone
before it produces anything, and a cold resume costs about $2.50. Thresholds are per model family in
spirit; if the owner confirms different numbers, change the constants in the script and this table
together.

## How compaction actually happens

`/compact` is a command only the session's user can type; a session cannot compact itself, and no
peer can do it for it. So an instruction takes one of two forms:

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
