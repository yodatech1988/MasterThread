@echo off
REM Removes the AEGIS-L1Pilot scheduled task registered by AEGIS-Register-L1Pilot.cmd. Does not
REM touch any copied tooling or report files, only the scheduled task itself.
REM No Claude session runs this for real against the real task -- only your double-click does.

echo This will remove the AEGIS-L1Pilot scheduled task, if one exists.
echo Report files and copied tooling are left in place.
echo Nothing changes until you type YES.
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AEGIS-Unregister-L1Pilot.ps1" %*
echo.
echo Done. Press any key to close.
pause >nul
