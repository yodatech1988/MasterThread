@echo off
title AEGIS: publish aegisdirective.net
echo Publishes the website at aegisdirective.net from what is merged on main.
echo.
echo The live site is behind. Merging on GitHub does NOT deploy this site -
echo this is the step that does.
echo.
echo Waiting to go live:
echo   - The REAL PayPal donate button on /fund/, plus the monthly cost table
echo     and the "funded through October 2, 2026" line. This is a live payment
echo     button, so read the file list before you type YES.
echo   - The server-connect widget on /start/ (copy-address button and a
echo     "Connect via Steam" link).
echo.
echo You will see the exact list of files that will change BEFORE anything is
echo published, and you must type YES (capitals) to go ahead. It should be three
echo files: styles.css, fund/index.html and start/index.html. Nothing is touched
echo if you don't type YES.
echo.
echo A log of this run is saved next to this file (AEGIS-Deploy-Website.*.log).
echo Only one deploy can run at a time.
echo.
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0AEGIS-Deploy-Website.ps1" %*
set RC=%errorlevel%
echo.
if %RC% EQU 0 (echo DONE. The site was published and the live pages checked out. Tell Claude and it will verify the live site. & goto :end)
if %RC% EQU 1 (echo FAILED. Nothing may have been published, or it may be half done. Read the lines above and the log; Claude can check it. & goto :end)
if %RC% EQU 2 (echo REFUSED. Nothing was published. Read the lines above; the log has the reason. & goto :end)
if %RC% EQU 3 (echo CANCELLED. Nothing was published. & goto :end)
if %RC% EQU 4 (echo NOTHING TO PUBLISH. The live site already matches main. & goto :end)
if %RC% EQU 5 (echo PUBLISHED, BUT A LIVE PAGE DID NOT COME BACK OK. Tell Claude now; the log has the undo. & goto :end)
echo UNEXPECTED exit code %RC%. Read the lines above and the log.
:end
pause
exit /b %RC%
