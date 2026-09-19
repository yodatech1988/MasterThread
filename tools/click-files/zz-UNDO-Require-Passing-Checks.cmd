@echo off
REM Puts ops-household main and services main branch protection back exactly as saved by
REM AEGIS-Require-Passing-Checks (newest AEGIS-Require-Checks.<repo>.*.backup.json next to this file).
REM Owner-run only. Asks for YES per repo.
echo This will offer to restore branch protection from the saved backups. Nothing changes until you type YES for a repo.
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AEGIS-Require-Passing-Checks.ps1" -Restore
echo.
echo Done. Press any key to close.
pause >nul
