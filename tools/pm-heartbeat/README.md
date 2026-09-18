# PM heartbeat

Implements `standards/sessions/pm_role.md` "The control loop" heartbeat tick and
`PM_PHASE_ADVISORY_2026-09-18.md` section 0, layer D (the external watchdog). Owner instruction
behind this, 2026-09-18 ~00:50Z: *"the pm should be constantly monitoring usage and activating
agents and teams of agents ... as a pm not a worker"* — the PM was observed `busy` in `ListAgents`
but not dispatching, and nothing outside the session could tell a live-but-stalled PM from a
working one.

This folder is verification only. Neither script dispatches, messages a session, or changes
anything about the PM's authority — `Write-PmHeartbeat.ps1` records that a tick happened,
`Watch-PmHeartbeat.ps1` reports whether that record is current. This is rung **L1** of the headless
readiness ladder in `PM_PHASE_ADVISORY_2026-09-18.md` section 6: a reporter, never a dispatcher.

## `Write-PmHeartbeat.ps1` — the PM calls this at the end of every tick

Per `pm_role.md`'s control loop, the PM's `CronCreate "*/10 * * * *"` tick ends with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\pm-heartbeat\Write-PmHeartbeat.ps1 `
  -Name <pm session name, as ListAgents shows it> `
  -Usage5h <int, from %APPDATA%\AEGIS\claude-usage-state.json fiveHour.usedPercentage> `
  -Dispatched <count of things this tick dispatched, 0 on a quiet tick> `
  -Note "<one short line, e.g. '3 dispatchable rows, 0 idle' or 'quiet tick'>"
```

It writes `%APPDATA%\AEGIS\pm-heartbeat.json`:

```json
{ "session": "github-f8", "tickAtUtc": "2026-09-18T01:23:45.0000000Z", "usage5h": 42, "dispatched": 3, "note": "..." }
```

`tickAtUtc` always comes from `[DateTime]::UtcNow` inside the script — never typed by the caller —
so the timestamp can't be stale by construction. The write is idempotent (last write wins, atomic
swap-in) and makes no network call. **A quiet tick still calls this.** The invariant in `pm_role.md`
is "a tick never ends with dispatchable work, budget, and idle capacity" — not "only report when
something happened." A quiet tick with nothing dispatchable is a valid, correct outcome and still
needs to prove it ran.

## `Watch-PmHeartbeat.ps1` — the owner's scheduled task calls this

Reads `pm-heartbeat.json` and `claude-usage-state.json` and decides one of three things:

| Output | Meaning | Exit |
|---|---|---|
| `PM-HEARTBEAT MISSING` | No heartbeat file (or unreadable/malformed) — the PM has never ticked, or the file was cleared. | 2 |
| `PM-HEARTBEAT STALE <age>m session=<name> usage=<n>%` | Heartbeat older than `-StaleMinutes` (default 30) **and** usage below `-UsageCeiling` (default 80) — there was room to tick and it didn't. | 1 |
| `PM-HEARTBEAT OK <age>m session=<name>` | Fresh, or stale only because usage is at/above the ceiling (a correct pause per the tier runbook, not a stall). | 0 |

Unknown usage (file missing or unreadable) is treated as headroom, not as "assume fine" — silence
on uncertainty is exactly the failure mode the owner reported. On `STALE` or `MISSING` it also
raises a Windows notification: `BurntToast` if installed, else `msg.exe` to the console session,
else a plain `Write-Warning` — dependency-free by design, so the watchdog never fails silently for
lack of a module.

Register it as a Windows scheduled task (recommended: every 15 minutes) so the owner is told the
PM stalled without opening a session:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\pm-heartbeat\Watch-PmHeartbeat.ps1
```

**Registering the scheduled task is the owner's click, not something this lane creates.** Per
convention it belongs at `GitHub\AEGIS-Register-PmHeartbeat-Watchdog.cmd` — a double-click file that
shows the `schtasks`/`Register-ScheduledTask` command before running it, the same shape as every
other `AEGIS-*.cmd`. That file is intentionally **not created by this PR**; a worker lane files it
once the owner approves the mechanism (Decision Queue card, per `pm_role.md`'s "Open owner
decisions" #3 and this lane's own report).

## Testing

Both scripts take a `-StatePath` override (`Write-PmHeartbeat.ps1`'s `-StatePath` names the exact
file; `Watch-PmHeartbeat.ps1`'s `-StatePath` names a directory holding both
`pm-heartbeat.json`/`claude-usage-state.json`, or pass `-HeartbeatPath`/`-UsageStatePath`
individually) so a test never touches the real `%APPDATA%\AEGIS\` files:

```powershell
$test = "$env:TEMP\pmhb_test"
powershell -File tools\pm-heartbeat\Write-PmHeartbeat.ps1 -Name test -Usage5h 42 -Dispatched 3 -StatePath "$test\pm-heartbeat.json"
powershell -File tools\pm-heartbeat\Watch-PmHeartbeat.ps1 -StatePath $test -Once
```

## What this is not

- Not a dispatcher. It never calls `Agent`, `SendMessage`, or `CronCreate` itself.
- Not the heartbeat tick's logic. The tick's actual control loop (read usage, `ListAgents` →
  `fleet-roster-watch.ps1`, dispatch `dispatchable` register rows, own Decision Queue cards) lives
  in the PM's own cron prompt per `pm_role.md`; this folder is only the "prove it happened" and
  "tell the owner if it didn't" halves.
- Not a survival mechanism. If the PM session itself dies, nothing here restarts it — that is rung
  L3 in the headless readiness ladder (a scheduled task that launches a headless PM tick), not
  built here.
