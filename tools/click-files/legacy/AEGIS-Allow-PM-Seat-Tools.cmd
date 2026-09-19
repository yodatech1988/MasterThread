@echo off
REM Adds the owner-approved PM-seat permission entries to the AEGIS-Directive project's
REM Claude Code settings at C:\Users\yoda_\GitHub\.claude\settings.json (creates the file if
REM it does not exist yet).
REM Approved on Ops Decision Queue card pm-seat-permission-allowlist-2026-09-18, owner
REM resolution B (read-only set plus git worktree add / New-ParallelWorktrees.ps1).
REM
REM Shows the current allow list, what will be added, what's already present, and a diff,
REM then asks you to type YES. Anything else cancels and changes nothing.
REM If all 14 entries are already present, it prints ALREADY APPLIED and exits without asking.
REM
REM This is a permission-settings change, so no Claude session runs this - only your
REM double-click does. Undo: restore the .bak.<timestamp> copy this script writes next to
REM settings.json, or delete the added entries from permissions.allow by hand.

echo This will add up to 14 approved permission entries to .claude\settings.json.
echo Nothing changes until you type YES.
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AEGIS-Allow-PM-Seat-Tools.ps1" %*
echo.
echo Done. Press any key to close.
pause >nul
