@echo off
REM Owner-run. Imports the GitHub App private key (.pem) into a DPAPI-protected store under %APPDATA%\AEGIS.
REM Type the .pem path and App ID when asked. Nothing is stored until validation passes; the .pem is only
REM deleted if you type DELETE after the stored copy is verified. Undo: run this with the word -Remove after it.
REM   AEGIS-Import-App-Key.cmd            import
REM   AEGIS-Import-App-Key.cmd -Remove    delete the stored key (exact undo)
REM   AEGIS-Import-App-Key.cmd -WhatIf    validate only, write nothing
REM Runs in this real console window (required: the script refuses piped/non-interactive runs).
REM NOT TESTED by a session: this wrapper and the live prompts were never run.
echo This will import the GitHub App key. Nothing changes until validation passes and you confirm.
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0GitHubAppKeyImport.ps1" %*
echo.
echo Done. Press any key to close.
pause >nul
