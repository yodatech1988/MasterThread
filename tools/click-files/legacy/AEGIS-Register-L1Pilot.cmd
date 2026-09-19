@echo off
REM Registers a Windows Scheduled Task, AEGIS-L1Pilot, that silently runs two read-only
REM headless reporters (pr-state-sweep, gate-execution-auditor) via
REM MasterThread\tools\headless\Invoke-ReadOnlyAgent.ps1 every 4 hours forever, under your own
REM account (no stored password, no popups -- report JSON files + a log only). The task always
REM runs the tooling merged to origin/main: a wrapper re-fetches it on every tick, so this does
REM NOT depend on what branch the local MasterThread checkout happens to be on.
REM Authorized by Decision Queue card approve-l1-pilot-scheduled-task-2026-09-18 and
REM standards\sessions\headless_readiness_ladder.md's L1 row. Refuses if the reporter tooling
REM isn't found on origin/main at all.
REM
REM Shows the task name, cadence, full command line, and current state, then asks you to type
REM YES. Anything else cancels. If already registered with this exact definition, it prints
REM ALREADY REGISTERED and exits without asking (still refreshes the copied tooling).
REM
REM This changes what runs on your machine in the background, so no Claude session runs this
REM for real -- only your double-click does. Undo: double-click AEGIS-Unregister-L1Pilot.cmd, or
REM run: Unregister-ScheduledTask -TaskName AEGIS-L1Pilot

echo This will register a scheduled task that runs two read-only reporters every 4 hours.
echo It is silent: no popups, no toasts -- report files and a log only. Nothing writes to any
echo repo, card or merge -- read-only checks only.
echo Nothing changes until you type YES.
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AEGIS-Register-L1Pilot.ps1" %*
echo.
echo Done. Press any key to close.
pause >nul
