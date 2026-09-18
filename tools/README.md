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

## An owner-run click-file logs every exit path

A timestamped log next to the `.cmd`, written on EVERY terminating path — success, owner-cancelled,
refused precondition, `-WhatIf`, and unhandled exception — each paired with its check:

- Structure the script as one outer `try { ... } catch { ... } finally { Write-RunLog }`, with a
  script-scoped outcome variable set immediately before every `exit`. **Check:** `finally` runs even
  when the `try` calls `exit` (verified empirically 2026-09-18, both `powershell -Command` and
  `powershell -File`, exit code preserved) — see `AEGIS-Register-PmHeartbeat-Watchdog.ps1`'s
  `Write-RunLog` (~line 143), outer `try` (~181) and `catch`/`finally` (~505-522).
- The log records: start time from the clock (not typed), the resolved plan, what the owner typed
  (YES / cancelled — never any other console input, never a secret), the outcome, and the full
  exception text when one occurred.
- The real action gets its own `try/catch` that prints exception type, message and inner exception,
  states the machine's resulting state, gives the exact undo, and exits non-zero — it never falls
  through to success text it did not earn. See the `Register-ScheduledTask` handler (~449).
- After the action, re-read live state and verify it happened (`Get-ScheduledTask`, re-parse the
  written file) — a cmdlet that throws nothing is not proof.
- The `.cmd` wrapper `pause`s after the PowerShell call so a thrown error stays on screen.
- **Check that fails if ignored:** a run that produces no log is itself the finding — the same rule
  `fleet_roster_monitor.md` states for watchers and `headless_readiness_ladder.md` restates for
  headless runs ("a silent watcher and a quiet fleet must not look alike"). Cite it by name: the
  2026-09-18 01:34Z incident, where the owner double-clicked
  `AEGIS-Register-PmHeartbeat-Watchdog.cmd`, typed YES, the script wrote its two files, then
  `Register-ScheduledTask` threw under `$ErrorActionPreference='Stop'` and died before its old
  end-of-script-only logging step — no task, files on disk, NO log, indistinguishable from "never
  ran" until a session compared file mtimes against the card's claim time.
- A run that changed nothing writes its log under a distinct name, never the real-run name:
  `AEGIS-<name>.<timestamp>.dryrun.log` for `-WhatIf`, a test/non-default target path, or a refused
  precondition; only a run that actually attempted the real action writes
  `AEGIS-<name>.<timestamp>.log` — including an attempt that then failed, which is a real run, not a
  dry run. The log's first line states it in words too: `RUN TYPE: dry run (nothing was changed)` or
  `RUN TYPE: real`.
- **Check that fails if ignored:** "a log exists" must never be mistakable for "it ran". If deciding
  whether an action happened requires opening the log and interpreting its body, the naming has
  already failed. Cite the 2026-09-18 blocked-work sweep that had to read every log's body to tell
  dry runs from real ones, and found two click-files — the seat-merge permission grant and the
  PM-heartbeat watchdog registration — whose only logs on disk were dry runs.

## What a session cannot test, it says so — on the card and in the file

Some click-file paths cannot be exercised by a session at all, because exercising them *is* the
owner-gated action (registering a scheduled task, applying a permission change, touching a live
host). Those are code-reviewed, never "tested", and the card's `executabilityCheck`
(`decision_queue_standard.md`) says which branch was reasoned about rather than run.

- A verification step blocked by the permission classifier is reported as a gap, never retried
  through another tool or a modified copy. Worked example: a 2026-09-18 subagent asked to exercise
  the `Register-ScheduledTask` failure branch, by editing a throwaway COPY of the script to loosen
  its real-vs-test guard, was refused ("Unauthorized Persistence") — it stopped and reported the gap
  rather than routing around it, per `session_bootstrap.md` item 6 and CLAUDE.md's standing rule.
- **Check:** an `executabilityCheck` that claims a branch was verified, for a branch only the owner
  can reach, is false on its face.

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
- **2026-09-18, 01:34Z — the click-file that died silently.** `Register-ScheduledTask` threw under
  `$ErrorActionPreference='Stop'` after the owner typed YES and the files were written; the process
  died before its old end-of-script-only logging step, leaving no task, files on disk, and no log.
  Fix: one outer `try/catch/finally` with `Write-RunLog` in `finally`, set on every exit path.
- **2026-09-18 — the dry-run log that read as done.** A blocked-work sweep had to open the body of
  every click-file log to tell a `-WhatIf`/test-fixture run from a real one, because both wrote the
  identical name shape; two click-files (seat-merge grant, PM-heartbeat watchdog) had only dry-run
  logs on disk. Fix: dry runs write `...dryrun.log` and a `RUN TYPE:` first line.
- **2026-09-18 — the refused failure-branch exercise.** A subagent asked to exercise the
  `Register-ScheduledTask` throw path by loosening a throwaway copy's real-vs-test guard was refused
  by the permission classifier ("Unauthorized Persistence"). It stopped and reported the gap instead
  of routing around it; that branch remains code-reviewed, not executed.
