@echo off
title AEGIS: unblock merges + turn Claude PR review back on
echo.
echo   WHAT THIS FIXES
echo   THIS IS WHY YOUR MERGES ARE BLOCKED. You hit it on site-chernarus #121: the
echo   "stale-review-gate" check goes red on every PR because it demands a completed
echo   Claude review, and the runner physically cannot produce one.
echo.
echo   Two things are missing on the runner, and BOTH are needed:
echo     unzip - the review job downloads Bun as a .zip, so it dies in 8 seconds at
echo             exit 127 before Claude reads a single line of the diff.
echo     gh    - the review posts its verdict by calling 'gh pr review'. No workflow
echo             step installs it. Without gh the job would get further and still
echo             post nothing, and the gate would stay red.
echo.
echo   Worse: repos that have no review credential (site-badlands) do not go red -
echo   they print "skipping Claude review" and pass. A GREEN review check on those
echo   repos currently means nothing was reviewed at all.
echo.
echo   WHAT IT DOES
echo   Connects to your OVH VPS (40.160.90.128) and runs one command:
echo       sudo apt-get install -y unzip gh
echo.
echo   ONE HOST RUNS THIRTEEN REPOS' CI. Verified on the box, not guessed:
echo     aegis-mods, aegis-poi, aegis-pricing, claude-agents, claude-session-archive,
echo     core, gh-federation, gh-federation-selftest, repo-template, services,
echo     site-badlands, site-chernarus, website
echo   So this single command restores CI tooling across all thirteen at once.
echo   It checks each package first and installs only what is missing.
echo.
echo   RISK
echo   Low. Two small packages from Ubuntu's own repo. It touches nothing else - not
echo   Docker, not systemd, not the DayZ server, not any credential.
echo   Undo: tell Claude and it will remove them.
echo.
echo   Press a key to run it, or close this window to do nothing.
echo.
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%APPDATA%\AEGIS\fix-runner-unzip.ps1"
echo.
if errorlevel 1 (
  echo   It did not finish. Nothing was left half-done - read the lines above and tell Claude.
) else (
  echo   Finished. Tell Claude it is done and it will re-run the failed checks and report.
)
echo.
pause
