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
on uncertainty is exactly the failure mode the owner reported.

**Silent by default** (owner instruction, 2026-09-18 01:07Z, direct: *"I got pm heartbeat missing
pop ups. I don't need these notifications."* — a test run's `msg.exe` fallback put a modal popup on
his desktop). Out of the box this script only ever writes one stdout line and sets an exit code.
`-LogPath <file>` appends that same line, timestamped, to a log — no UI involved. A desktop
notification is raised **only** when the caller explicitly passes `-Notify`, and that path is
**BurntToast-only**: if the module isn't installed, it prints one line saying so instead of trying
anything else. There is no `msg.exe` fallback and no other modal or UI mechanism anywhere in this
script, under any flag combination.

**`-Notify` is structurally disarmed off the real default `-StateDir`, not just off by default.**
A flag a test can set is a default, not a guard — so `-Notify` firing was never made to depend on
the flag alone. It fires only when `-StateDir` *also* resolves to the real
`%APPDATA%\AEGIS` at the moment of the call (checked fresh against `$env:APPDATA`, not a cached
value); any other `-StateDir` — a test's scratch directory — prints
`NOTIFY suppressed (non-default StateDir = test)` and never calls BurntToast, regardless of
whether `-Notify` was passed. A test pointed at a throwaway directory cannot page the owner's
desktop no matter what flags it passes.

Register it as a Windows scheduled task (recommended: every 15 minutes), silent (the default —
append to a log if you want a record):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\pm-heartbeat\Watch-PmHeartbeat.ps1 -LogPath C:\Users\yoda_\GitHub\pm-heartbeat-watch.log
```

Add `-Notify` only if the owner asks for a desktop alert back — it did not ship on by default
after the 2026-09-18 feedback above, and should not be turned on without him asking for it.

**Registering the scheduled task is the owner's click, not something this lane creates.** Per
convention it belongs at `GitHub\AEGIS-Register-PmHeartbeat-Watchdog.cmd` — a double-click file that
shows the `schtasks`/`Register-ScheduledTask` command before running it, the same shape as every
other `AEGIS-*.cmd`. That file is intentionally **not created by this PR**; a worker lane files it
once the owner approves the mechanism (Decision Queue card, per `pm_role.md`'s "Open owner
decisions" #3 and this lane's own report).

## Testing this tool without touching the owner's environment

**Rule adopted 2026-09-18, after this exact tool broke it once:** a tool under test must not be
able to reach the owner's real environment at all — not "shouldn't," structurally can't. Test runs
go to a throwaway `-StateDir` (or, for a stronger isolation pass, a temp directory with `$env:APPDATA`
itself repointed for the test process only); the tool proves it can FAIL correctly there — missing
file, stale heartbeat, malformed input — before it is ever pointed at the real path; and the test
leaves zero files behind in the owner's real state directory.

**The incident that made it a rule:** 2026-09-18 ~01:07Z, this PM-process lane's own test runs of
`Watch-PmHeartbeat.ps1` fired `msg.exe` popups on the owner's desktop. Owner: *"I don't need these
notifications."* The blast radius that time was a popup. The same miss in a tool that writes,
restarts a service, or SSHes into a host is an incident, not an annoyance — which is why `-Notify`
above is now structurally gated on the real `-StateDir`, not just left off by default (see above).

**Precedent this follows:** the services no-silent-mint lane (2026-09-18) repointed `$env:APPDATA`
to a temp directory for its own process, verified `%APPDATA%\AEGIS` was untouched afterward, and
left zero throwaway files anywhere real. Same shape here:

Both scripts take the same `-StateDir` (a directory holding `pm-heartbeat.json` and
`claude-usage-state.json`), so a test points both at one scratch directory and never touches the
real `%APPDATA%\AEGIS\` files:

```powershell
$test = "$env:TEMP\pmhb_test"
powershell -File tools\pm-heartbeat\Write-PmHeartbeat.ps1 -Name test -Usage5h 42 -Dispatched 3 -StateDir $test
powershell -File tools\pm-heartbeat\Watch-PmHeartbeat.ps1 -StateDir $test -Once
```

`-Notify` is safe to pass in a test now (it will print `NOTIFY suppressed (non-default StateDir =
test)` and never call BurntToast, since `$test` is not the real default), but there is still no
reason to pass it in a test — proving the silent path is the point. Clean up `$test` afterward so
no throwaway files linger, even in `%TEMP%`.

## What this is not

- Not a dispatcher. It never calls `Agent`, `SendMessage`, or `CronCreate` itself.
- Not the heartbeat tick's logic. The tick's actual control loop (read usage, `ListAgents` →
  `fleet-roster-watch.ps1`, dispatch `dispatchable` register rows, own Decision Queue cards) lives
  in the PM's own cron prompt per `pm_role.md`; this folder is only the "prove it happened" and
  "tell the owner if it didn't" halves.
- Not a survival mechanism. If the PM session itself dies, nothing here restarts it — that is rung
  L3 in the headless readiness ladder (a scheduled task that launches a headless PM tick), not
  built here.
