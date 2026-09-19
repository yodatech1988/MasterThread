@echo off
title AEGIS: turn on the economy catalog sync on the VPS
echo Turns on the every-6-hours sync of trader prices (site-chernarus Market files) into the economy DB:
echo   1. creates a read-only site-chernarus key on the VPS and registers it on GitHub
echo   2. clones site-chernarus onto the VPS
echo   3. enables the sync timer and runs one sync now
echo.
echo Does NOT touch the DayZ server. Safe to run again. You must type YES to proceed.
echo.
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0AEGIS-VPS-Economy-Sync.ps1"
pause
