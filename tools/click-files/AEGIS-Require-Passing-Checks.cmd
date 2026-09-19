@echo off
REM Makes named CI checks REQUIRED on ops-household main and services main, and turns on "include
REM administrators", so a merge is blocked until the check is green and you cannot click through.
REM Owner-run only. Fixed list, no options. It checks each check was green recently (on push AND on merged
REM pull requests) and refuses any repo where it was not. It saves an exact backup of each repo's current
REM protection next to this file first, then asks you to type YES per repo.
REM Undo: run AEGIS-Restore-Passing-Checks.cmd.
REM Copy all three files (this .cmd, the restore .cmd, the .ps1) to where AEGIS-Protect-Default-Branches.cmd lives.
REM NOT TESTED by a session: this wrapper, the live YES prompt, and a real apply were never run (see the .ps1 header).
echo This will offer to require passing checks on ops-household and services. Nothing changes until you type YES for a repo.
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AEGIS-Require-Passing-Checks.ps1"
echo.
echo Done. Press any key to close.
pause >nul
