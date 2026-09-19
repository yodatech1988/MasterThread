@echo off
REM Registers a Windows Scheduled Task, AEGIS-PmHeartbeat-Watchdog, that silently runs
REM MasterThread's tools\pm-heartbeat\Watch-PmHeartbeat.ps1 every 15 minutes forever, under
REM your own account (no stored password, no -Notify, no popups -- stdout + a log file only).
REM The task always runs the version merged to origin/main: a wrapper re-fetches it from
REM origin/main on every 15-minute tick (git show, never the working tree), so this does NOT
REM depend on what branch the local MasterThread checkout happens to be on.
REM Authorized by MasterThread PR #108 (merged 2026-09-18) and owner instruction "the pm never
REM stalls". Refuses if the watchdog script isn't found on origin/main at all.
REM
REM Shows the task name, trigger, full command line, and current state, then asks you to type
REM YES. Anything else cancels. If already registered with this exact definition, it prints
REM ALREADY REGISTERED and exits without asking (still refreshes the copied script/wrapper).
REM
REM This changes what runs on your machine in the background, so no Claude session runs this
REM for real -- only your double-click does. Undo: double-click
REM AEGIS-Unregister-PmHeartbeat-Watchdog.cmd, or run:
REM   Unregister-ScheduledTask -TaskName AEGIS-PmHeartbeat-Watchdog

echo This will register a scheduled task that checks the PM heartbeat every 15 minutes.
echo It is silent: no popups, no toasts -- a log file only.
echo Nothing changes until you type YES.
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AEGIS-Register-PmHeartbeat-Watchdog.ps1" %*
echo.
echo Done. Press any key to close.
pause >nul
