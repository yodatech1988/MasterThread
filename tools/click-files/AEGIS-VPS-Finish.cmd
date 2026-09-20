@echo off
REM Routes public hostnames to the OVH VPS tunnel. Gated: type YES before applying.
REM Undo: run zz-UNDO-AEGIS-VPS-Finish.cmd
REM Copy all four files (this .cmd, the undo .cmd, both .ps1s) to the GitHub root when ready.
REM
REM Usage:
REM   AEGIS-VPS-Finish.cmd         -- Routes hostnames (requires YES gate)
REM   AEGIS-VPS-Finish.cmd -WhatIf -- Shows what would happen (read-only)
REM
echo This will overwrite DNS for community-api, economy-api and events to the OVH VPS tunnel, may stop the PC community-api, and starts VPS services.
echo Confirm with YES when prompted. To undo, run zz-UNDO-AEGIS-VPS-Finish.cmd.
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AEGIS-VPS-Finish.ps1" %*
echo.
echo Done. Press any key to close.
pause >nul
