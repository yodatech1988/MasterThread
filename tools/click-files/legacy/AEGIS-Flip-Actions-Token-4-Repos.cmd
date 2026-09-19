@echo off
REM Sets the Actions workflow token to read+write on four org-infra repos:
REM   MasterThread, ops-infra, ops-platform, ops-policies.
REM Approved on Ops Decision Queue card actions-token-flip-scope-extension-2026-09-17.
REM
REM Each repo shows its current and proposed setting, then asks you to type YES (capitals).
REM Anything else skips that repo. No personal or financial repo is touched.
REM
REM This is a repo security setting, so no Claude session runs it - only your double-click does.
REM Undo one repo:
REM   gh api -X PUT repos/yodatech1988/<repo>/actions/permissions/workflow -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false

echo This will offer to flip the Actions token to write on 4 repos, one at a time.
echo Nothing changes until you type YES for a repo.
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AEGIS-Flip-Actions-Token-4-Repos.ps1"
echo.
echo Done. Press any key to close.
pause >nul
