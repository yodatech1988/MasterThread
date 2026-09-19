@echo off
REM Owner-run. Proves (or disproves) that a GitHub App approval satisfies "required approving reviews" on a user-owned
REM private repo, using a THROWAWAY repo you name (must start with 'proof'; 'website' is hard-refused).
REM TWO RUNS ARE NEEDED: run 1 creates the empty proof-* repo and stops; you install the App on it; run 2 (same name) does the proof.
REM Needs the App key imported first (core tools\GitHubAppKeyImport.ps1). Never merges. Prints cleanup steps at the end.
REM Copy this .cmd and the .ps1 to where AEGIS-Protect-Default-Branches.cmd lives.
REM NOT TESTED by a session: this wrapper, the live prompts, and everything that needs a real App (see the .ps1 header).
echo This will create/use a throwaway private repo and open a proof PR. It never touches website and never merges.
echo.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AEGIS-Prove-App-Review.ps1"
echo.
echo Done. Press any key to close.
pause >nul
