@echo off
REM Puts website main's branch protection back exactly as saved by AEGIS-Require-Website-Review
REM (newest AEGIS-Require-Review.website.*.backup.json next to this file). Owner-run only. Asks for YES.
echo This will offer to restore website main protection from the saved backup.
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AEGIS-Require-Website-Review.ps1" -Restore
echo.
echo Done. Press any key to close.
pause >nul
