@echo off
REM Narrows the permissions.allow and permissions.deny lists in
REM C:\Users\yoda_\GitHub\.claude\settings.local.json to the owner-approved, narrower set.
REM
REM Authority: Ops Decision Queue card settings-local-allow-list-wider-than-approved-2026-09-18,
REM owner resolution: "Narrow it now: drop gh secret *, replace gh api * with read-only shapes,
REM split gh pr * into the read verbs plus explicit deny on --admin."
REM
REM This replaces the current allow list (8 entries including the too-broad gh pr *, gh api *,
REM gh secret *) with a narrower one (11 entries, split and filtered), and adds two new sets of
REM deny rules for the two-shape workaround: git worktree remove --force/-f (matching both flag
REM positions), and gh pr merge --admin (same two-shape pattern as the existing
REM AEGIS-Allow-Seat-Merge.ps1).
REM
REM This is a permission-settings change, so no Claude session runs this for real - only your
REM double-click does. A session may only run it with -WhatIf. Undo: restore the .bak.<timestamp>
REM copy this script writes next to settings.local.json, or delete the changed entries by hand.

echo This will REPLACE permissions.allow and permissions.deny in
echo .claude\settings.local.json with narrower lists per the owner's decision card.
echo.
echo Drops: gh secret *. Narrows: gh api * to repos/* (read-only), gh pr * to verb-specific
echo allows. Adds deny rules for --admin on gh pr merge and --force/-f on git worktree remove,
echo using the two-shape pattern (flag-before and flag-after arguments) to close both call-shape
echo orders.
echo.
echo Nothing changes until you type YES.
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AEGIS-Narrow-Local-Allowlist.ps1" %*
echo.
echo Done. Press any key to close.
pause >nul
