@echo off
REM Sets branch protection on six default branches to one known-good shape:
REM   MasterThread (public, first), ops-infra, ops-platform, ops-policies, claude-agents, aegis-mods.
REM Approved on Ops Decision Queue card pr81-q4-branch-protection-all-default-branches-2026-09-17.
REM
REM Each repo shows its current state and the proposed settings, then asks you to type YES.
REM Anything else skips that repo. A repo whose protection already matches is left alone; one whose
REM protection differs (e.g. requires a check that can never run there) is REPLACED if you type YES.
REM After this, nothing can be pushed straight to those branches; everything goes through a PR.
REM
REM Branch protection is a repo security setting, so no Claude session runs this - only your
REM double-click does. Undo one repo:
REM   gh api -X DELETE repos/yodatech1988/<repo>/branches/<branch>/protection

echo This will offer to protect 6 default branches, one at a time, MasterThread first.
echo Nothing changes until you type YES for a repo.
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AEGIS-Protect-Default-Branches.ps1"
echo.
echo Done. Press any key to close.
pause >nul
