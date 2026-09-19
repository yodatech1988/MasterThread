@echo off
REM Removes the AEGIS-PmHeartbeat-Watchdog scheduled task registered by
REM AEGIS-Register-PmHeartbeat-Watchdog.cmd. Does not touch the watchdog script or its log.
REM
REM Shows the current task definition, then asks you to type YES. Anything else cancels.
REM If no such task exists, prints NOT REGISTERED and exits without asking.

echo This will remove the AEGIS-PmHeartbeat-Watchdog scheduled task.
echo Nothing changes until you type YES.
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AEGIS-Unregister-PmHeartbeat-Watchdog.ps1" %*
echo.
echo Done. Press any key to close.
pause >nul
