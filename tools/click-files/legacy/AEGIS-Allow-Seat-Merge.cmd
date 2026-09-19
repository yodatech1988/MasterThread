@echo off
REM Adds the owner-approved merge-permission rule set to the AEGIS-Directive project's
REM Claude Code settings at C:\Users\yoda_\GitHub\.claude\settings.json.
REM
REM Authority: Ops Decision Queue card merge-seat-how-to-enforce-route-b-2026-09-18, owner
REM resolution at 2026-09-18T02:02:47.905Z, option C ("Both - the narrow rule now, and the
REM auditor as the control that actually holds"). Upstream: card
REM denial-merge-seat-blocked-by-classifier-2026-09-18, resolved 01:35Z ("Allow a session to
REM merge only where merge_authority.md route B already permits it").
REM
REM Adds exactly three entries:
REM   allow: Bash(gh pr merge --squash --match-head-commit *)
REM   deny:  Bash(gh pr merge --admin*)
REM   deny:  Bash(gh pr merge * --admin*)
REM (two deny rules on purpose - one alone does not catch both --admin call shapes; see the
REM .ps1 header for the empirical reasoning).
REM
REM Shows the current allow+deny lists, what will be added, what's already present, and a
REM diff, prints an explicit WARNING about what this does and does not protect against, then
REM asks you to type YES. Anything else cancels and changes nothing. If all three entries are
REM already present, it prints ALREADY APPLIED and exits without asking.
REM
REM This is a permission-settings change, so no Claude session runs this for real - only your
REM double-click does; a Claude session may only run it with -WhatIf. Undo: restore the
REM .bak.<timestamp> copy this script writes next to settings.json, or delete the three added
REM entries from permissions.allow / permissions.deny by hand.

echo This will add ONE allow rule (squash-merge with matching head commit) and TWO deny rules
echo (block --admin overrides, both call shapes) to .claude\settings.json.
echo.
echo WARNING: this lets a session merge PRs without asking you first, for any PR whose merge
echo command matches the allowed shape - the rule has no idea what the PR contains.
echo Nothing changes until you type YES.
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AEGIS-Allow-Seat-Merge.ps1" %*
echo.
echo Done. Press any key to close.
pause >nul
