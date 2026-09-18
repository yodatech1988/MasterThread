# Tool conventions

Rules for everything under `tools/` and the owner click-files at `GitHub\AEGIS-*.cmd`. Written
after a tool fired real desktop popups during its own test run (below) — these are not style
preferences, they are the fix for things that already happened.

## Test seam is mandatory

Every tool that reads or writes state takes `-StateDir` (a directory; default the real path,
e.g. `%APPDATA%\AEGIS`) and/or `-DryRun`/`-WhatIf`. A test never points the tool at the real
path — it passes a throwaway directory or the dry-run switch. `tools/fleet-monitor/
fleet-roster-watch.ps1`'s `-StateDir` parameter (default `Join-Path $env:APPDATA 'AEGIS'`) is the
pattern: every snapshot read/write goes through that parameter, never a hardcoded path.

## Destructive and notifying paths key off the REAL path, not a flag

A notification, write, restart, SSH call or network call is attempted only when the tool is
pointed at its real default target. On any other target (a test `-StateDir`, a dry-run switch) it
prints `<ACTION> suppressed (non-default target = test)` and does nothing. **A flag a test can set
is a default, not a guard** — if `-Notify` alone turns notifications on, a test that forgets to
pass it still gets the real behavior by accident. Structure the guard the other way: the action
fires only when the resolved path *equals* the real default, so no flag combination a test uses
can accidentally hit production. This is the services PR #104 precedent (2026-09-18): it
repointed `$env:APPDATA` to a temp dir for its own process, verified the real `%APPDATA%\AEGIS`
was untouched, and left zero throwaway files behind.

## Prove it can fail before pointing it at anything real

Before a tool goes near a real path, run it on a throwaway directory and confirm: missing input,
stale input, and malformed input each produce their documented output and exit code, and the
suppressed-action path prints its `suppressed (non-default target = test)` line instead of acting.
Put the literal outputs in the PR body. Remove the throwaway directory afterward and confirm the
tool left zero files outside it.

## Test the call site, not only the guard

A test that calls the guarded function directly, with the switch passed explicitly, only proves
the guard works when used correctly — it says nothing about a caller that forgets the switch.
Exercise the path a real caller takes: the wrapper `.cmd`/`.ps1`, the scheduled-task command line,
the Monitor/cron invocation that fires unattended. Services PR #104's Opus live-review finding was
exactly this gap: its tests exercised the guarded function in isolation but never the call sites,
so they would still have passed if a caller forgot to pass the switch — the guard was fine, the
test was narrower than it read.

## No desktop UI by default

No `msg.exe`, no modal dialogs, no toasts, unless behind an explicit opt-in that is itself keyed
to the real target (see above — the opt-in cannot become the only guard). Findings go to stdout +
exit code, an append-only log, a Fleet Status `health` row, or the PM digest. This follows the
owner's own instruction after the incident below: "I don't need these notifications."

## Exit codes documented and honoured under `Set-StrictMode`

Document exit codes in the script header. Under `Set-StrictMode -Version Latest`, a property read
from parsed JSON (`$obj.property`) throws if the property is absent — go through
`$obj.PSObject.Properties['name']` (check `.Count` or use `-contains`) instead of a bare dotted
read, the same way `fleet-roster-watch.ps1` checks `$prev.PSObject.Properties.Name -contains
'sessions'` before touching it. PR #108 hit this directly.

## Timestamps from the clock

Read every timestamp from the clock at the moment of the write (`[DateTime]::UtcNow` in
PowerShell, `date -u +%Y-%m-%dT%H:%M:%SZ` in bash) — never typed from memory. Same rule as
`standards/sessions/decision_queue_standard.md`'s `createdAt`/`resolvedAt` field, and for the same
reason: a hand-typed stamp drifted 10-100 minutes on 2026-09-17 and made a live session read as
wound down.

## Incidents that made these rules

- **2026-09-18, ~01:07Z — the msg.exe popup.** The PM-process lane's test runs of a new watchdog
  (`tools/pm-heartbeat/Watch-PmHeartbeat.ps1`, open PR #108) fired `msg.exe` popups on the owner's
  desktop during testing. Owner: "I got pm heartbeat missing pop ups. I don't need these
  notifications." Fix in #108: silent by default, no `msg.exe` path, `-Notify` structurally inert
  unless `-StateDir` equals the real `%APPDATA%\AEGIS`.
- **2026-09-18 — the #104 call-site test gap.** Services PR #104's own guard was correct; its test
  suite called the guarded function directly and never the wrapper a real scheduled task invokes,
  so a caller that forgot the switch would have passed the same tests.
- **2026-09-17 — hand-typed timestamps.** Manually written UTC stamps ran ahead of the real clock
  all day, making cards look answered before they were filed and a live session read as wound
  down.
