@echo off
REM Sets "1 required approving review" on yodatech1988/website main. Owner-run only.
REM It REFUSES (changes nothing) unless a second GitHub account with write access already exists,
REM because the sole collaborator cannot approve their own PRs and every merge would be blocked.
REM It saves an exact backup of the current protection next to this file first, then asks for YES.
REM Undo: run AEGIS-Restore-Website-Review.cmd.
REM Copy all three files (this .cmd, the restore .cmd, the .ps1) to where AEGIS-Protect-Default-Branches.cmd lives.
REM NOT TESTED by a session: this wrapper and the live YES prompt were never run; the guard-PASS path was only
REM simulated. The guard proves WRITE access, not ability to APPROVE (a bot may not count): if merges block, run Restore.
echo This will offer to require 1 approving review on website main. Nothing changes until you type YES.
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AEGIS-Require-Website-Review.ps1"
echo.
echo Done. Press any key to close.
pause >nul
