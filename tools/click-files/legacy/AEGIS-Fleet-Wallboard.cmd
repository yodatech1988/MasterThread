@echo off
title AEGIS Fleet Wallboard
echo Opening the Fleet Status dashboard in display mode...
echo First time: drag the window to your second monitor and maximize it (Win+Shift+Left/Right
echo then maximize). Windows will usually remember the position after that.
echo.
set URL=https://claude.ai/artifact/AAiVG3MxK1r3yNgm8tzMmf?wallboard=1
set CHROME="%ProgramFiles%\Google\Chrome\Application\chrome.exe"
set CHROME_X86="%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
set EDGE="%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"

if exist %CHROME% (
  start "" %CHROME% --app=%URL% --start-maximized
) else if exist %CHROME_X86% (
  start "" %CHROME_X86% --app=%URL% --start-maximized
) else if exist %EDGE% (
  start "" %EDGE% --app=%URL% --start-maximized
) else (
  echo Could not find Chrome or Edge in their usual install locations.
  echo Opening in your default browser instead - no app-window mode, but the page still works.
  start "" %URL%
)
