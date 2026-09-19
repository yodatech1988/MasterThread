@echo off
title AEGIS: merge-authority queue
echo Reviews QC-approved PRs one at a time, grouped by tier, in a dialog on THIS
echo screen. Nothing merges without you clicking Approve, then confirming Yes on
echo a dialog defaulted to No. You can stop after any tier or any PR.
echo.
echo This must be started by you, from this window. The script itself refuses to
echo run if it detects it was launched programmatically instead of from a real
echo console (2026-09-16, after an earlier incident where a session's dry run
echo rendered live merge dialogs on this desktop).
echo.
echo Queue file: C:\Users\yoda_\GitHub\merge-queue.json
echo.
pause
rem Drop a fresh, single-use marker proving a human just pressed a real key on
rem this real console, seconds ago. The .ps1 requires this (or a typed
rem -OwnerInitiated flag) on top of its own interactive-console check, consumes
rem the marker on read, and refuses to run without it - see its header comment.
powershell -NoProfile -Command "Get-Date | Out-File -FilePath 'C:\Users\yoda_\GitHub\.merge-queue-owner-start' -Encoding utf8 -Force"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0AEGIS-Merge-Queue.ps1"
echo.
if errorlevel 1 (echo Something failed - read the lines above. Claude can read the log.) else (echo Done.)
pause
