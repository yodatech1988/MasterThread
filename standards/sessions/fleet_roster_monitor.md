# Fleet roster monitor (PM)

**Status:** owner-directed, 2026-09-17 — *"The active PM needs to have a recurring session monitor
verifying who is working. This only needs to report if there is a change from the previous state.
This way it knows when something has joined and can monitor usage accordingly."*

The PM runs one recurring check that answers *who is actually live right now*, and reports only the
difference from the previous check. Companion to the usage watcher in `orchestrator_role.md`: that
one watches how much the fleet is spending, this one watches who is spending it.

## The gap this closes

`pm_role.md` makes the PM accountable for staffing every live workstream and for aggregating usage
across every session that handed off. Both depend on the PM knowing the fleet's actual membership.
Until now it had two sources and neither is a roster:

- **Fleet Status `sessions`** is self-reported. A session that never writes its row is invisible,
  and a row is only as current as the session's last write — a wound-down-looking row can belong to
  a session that is still live and spending.
- **`ListAgents`** is live and complete, but it is a point-in-time listing with no memory. Reading
  it tells the PM who is here, never who *arrived* or *left* since it last looked.

Measured on 2026-09-17, with seven sessions live: five had no `sessions` row at all, and one row
marked `done` / wound-down belonged to a session that was still live and busy. The PM was at that
moment running a fleet status round by messaging sessions one at a time and waiting for replies —
the manual version of this check, costing a round-trip per session and catching only the sessions it
already knew to ask.

## What it reports

Reports only on change. A quiet tick prints `FLEET-ROSTER NO CHANGE (n live)` and the PM says
nothing — no message to the owner, no Fleet Status write.

| Signal | Meaning | What the PM does |
|---|---|---|
| `JOINED` | A session present now that was absent last check. | Intake per `pm_role.md`: assign, adopt, or say there is nothing. Add it to the usage aggregate. |
| `JOINED … (same name, NEW ref)` | A name reappeared under a new ref — a rotation. | Treat as a new session: the handoff file is the context, the old row is stale. |
| `DEPARTED` | A session that was here last check is gone. | Confirm a handoff file exists; if its workstream is unfinished, restaff or mark it `unstaffed`. Stop counting it in usage. |
| `IDLE` | Idle for N consecutive checks (default 2). | `fleet_structure.md`: no worker is ever idle. Give it the workstream's `next` card, or wind it down. |
| `UNREGISTERED` | Live, but with no Fleet Status `sessions` row. | It is spending unattributed. Ask it to self-report, or write the row on its behalf noting `writtenBy`. |
| `GHOST ROW` | A `sessions` row that is live/not-wound-down for a session that no longer exists. | Mark it wound down, so the board stops showing work nobody is doing. |

## What it deliberately does not report

Both of these change on nearly every tick and would bury the signal:

- **Relative start times.** `started 1h ago` becomes `started 2h ago` with nothing having happened.
- **A single busy↔idle flip.** A session between tool calls reads as idle. Only idleness sustained
  across `-IdleTicks` consecutive checks is reported, once per idle spell, re-armed when the session
  goes busy again.

An unreadable or empty listing reports `FLEET-ROSTER ERROR` and leaves the snapshot untouched. It is
never reported as "no change", because a silent watcher and a quiet fleet must not look alike.

## Arming it

`ListAgents` is a tool, not a command, so a script cannot poll it. The PM calls `ListAgents` itself
each tick and pipes the listing into
[`tools/fleet-monitor/fleet-roster-watch.ps1`](../../tools/fleet-monitor/fleet-roster-watch.ps1),
which owns everything that must be deterministic: parsing, diffing, and deciding whether anything
changed. The PM does not eyeball the roster — that is what drifts.

**At PM takeover, once**, establish the baseline so the first tick does not report the whole
existing fleet as newly joined:

```powershell
# $roster = the ListAgents output, verbatim
$roster | C:\Users\yoda_\GitHub\MasterThread\tools\fleet-monitor\fleet-roster-watch.ps1 -Name <pm-session-name> -Reset
```

Then arm the recurring check with `CronCreate`, cron `3,13,23,33,43,53 * * * *` (every 10 minutes,
off the :00/:30 marks per the scheduler's guidance), with this prompt:

> Fleet roster check. Call `ListAgents`, pass its full output verbatim as `-RosterText` to
> `C:\Users\yoda_\GitHub\MasterThread\tools\fleet-monitor\fleet-roster-watch.ps1` with
> `-Name <pm-session-name>`. Roughly every third run, also read the Fleet Status `sessions`
> collection with `ArtifactData` and pass the non-wound-down session ids as `-RegisteredIds`.
> If the output is `FLEET-ROSTER NO CHANGE`, say nothing and do nothing. Otherwise act on each
> line per `standards/sessions/fleet_roster_monitor.md`, and report to the owner only what needs
> him.

Ten minutes, not five: a join waiting ten minutes for a lane costs little, and this check is
additive to the 5-minute Decision Queue card watcher the owner already requires. The
`-RegisteredIds` cross-check is every third run because it costs an extra `ArtifactData` read and
registration drift is slow-moving.

## Rotation

`CronCreate` jobs are session-only — they die with the PM session and auto-expire after 7 days. **A
new PM re-arms this at takeover**, with `-Reset` first and `-Name` set to its own session name
(the snapshot file is per-name, so two PMs never corrupt each other's state). A PM handoff file
says whether the outgoing PM had it armed.

This is the same structural weakness `fleet_status_standard.md` flags for the `queue` panel: a
monitor that exists only because one session chose to run it freezes silently when that seat goes
away. The difference is that this one is written down as part of takeover rather than left as
tribal knowledge.
