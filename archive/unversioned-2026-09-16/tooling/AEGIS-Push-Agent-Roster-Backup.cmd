@echo off
setlocal enabledelayedexpansion
title AEGIS: push the agent-roster git-backup branch to GitHub
echo This pushes ONE branch to GitHub. It does not touch main, does not touch anything live,
echo and does not open a pull request.
echo.
echo   Repo:   MasterThread
echo   Expected commit: 8c4da85fd79001410a2c95f06414bc813617b571
echo                     "Back the 70 global Claude Code agent definitions into git"
echo   Adds:   claude-agents/*.md (70 files, verbatim copy of everything in
echo           %%USERPROFILE%%\.claude\agents) + a sync note + a generator script.
echo           docs/AGENTS.md is deliberately NOT touched by this commit.
echo.
echo Why this needs your click: Claude's own auto-mode classifier denied the push
echo ("Out-of-Place Publication") when Claude tried it directly, both before and after
echo being asked again. This script runs the exact same push from a terminal you started,
echo so it needs YOU to confirm it, not Claude.
echo.
echo What happens after: this only pushes the branch. Opening the pull request is a
echo separate, later step -- MasterThread already has one open agent PR (#52), and the
echo project's own rule caps that at one per repo. Once #52 is merged or closed, the PM
echo session (or Claude, next time you ask) opens the PR for this branch. You do not need
echo to do anything else right now.
echo.

set "WORKTREE=C:\Users\yoda_\GitHub\_wt-MasterThread-agent-roster-git-backup"
set "EXPECTED_COMMIT=8c4da85fd79001410a2c95f06414bc813617b571"

REM --- Preflight: verify there is actually something real to push before asking for a YES. ---
REM 2026-09-16 incident: this script used to jump straight to git push on whatever branch was
REM checked out. That worktree's checked-out branch turned out to be an unborn empty ref, a
REM case-mismatched sibling of the branch that actually held the commit, so the push would have
REM either failed outright or silently done nothing while the script still printed Done -- false
REM assurance that 70 agent definitions were backed up. Every check below must fail LOUDLY, with
REM visible error text and a non-zero exit code, rather than let that happen again.

if not exist "%WORKTREE%\.git" (
    echo ============================================================
    echo ERROR: worktree not found at
    echo   %WORKTREE%
    echo Nothing was pushed. Tell Claude this path is missing or moved.
    echo ============================================================
    pause
    exit /b 1
)

cd /d "%WORKTREE%"

set "CURRENT_BRANCH="
for /f "delims=" %%b in ('git symbolic-ref --short -q HEAD 2^>nul') do set "CURRENT_BRANCH=%%b"
if not defined CURRENT_BRANCH (
    echo ============================================================
    echo ERROR: could not determine the current branch in
    echo   %WORKTREE%
    echo This usually means the worktree itself is broken. Nothing was pushed.
    echo Tell Claude what git said above, if anything.
    echo ============================================================
    pause
    exit /b 1
)

for /f "delims=" %%h in ('git rev-parse --verify -q HEAD 2^>nul') do set "CURRENT_COMMIT=%%h"
if not defined CURRENT_COMMIT (
    echo ============================================================
    echo ERROR: branch "%CURRENT_BRANCH%" has NO commits -- an unborn HEAD.
    echo There is nothing to push -- the backup was never actually committed
    echo on this branch, even if files are staged or present on disk.
    echo Nothing was pushed. Tell Claude this branch is empty; the real
    echo commit may exist under a different, possibly differently-cased,
    echo branch name in the same repo -- do not assume it's lost.
    echo ============================================================
    pause
    exit /b 1
)

if /i not "%CURRENT_COMMIT%"=="%EXPECTED_COMMIT%" (
    echo ============================================================
    echo ERROR: branch "%CURRENT_BRANCH%" HEAD is
    echo   %CURRENT_COMMIT%
    echo but this script expects
    echo   %EXPECTED_COMMIT%
    echo Pushing this would send the WRONG content under this branch name.
    echo This exact mismatch has happened before via a branch-name casing
    echo mixup, e.g. agent/MasterThread/... vs agent/masterthread/... -- check
    echo git branch --all --contains %EXPECTED_COMMIT% for a sibling
    echo branch that actually has the expected commit before doing anything
    echo else. Nothing was pushed.
    echo ============================================================
    pause
    exit /b 1
)

echo Preflight passed: branch "%CURRENT_BRANCH%" HEAD matches the expected commit.
echo.
echo You must type YES to proceed. Anything else cancels.
echo.
set /p CONFIRM="Type YES to push this branch: "
if /i not "%CONFIRM%"=="YES" (
    echo.
    echo Cancelled. Nothing was pushed.
    pause
    exit /b 1
)

echo.
echo Pushing "%CURRENT_BRANCH%"...
git push -u origin "%CURRENT_BRANCH%"
set "PUSH_RESULT=%ERRORLEVEL%"
if not "%PUSH_RESULT%"=="0" (
    echo ============================================================
    echo ERROR: git push failed or was rejected -- exit code %PUSH_RESULT%.
    echo Read the git output above. Nothing is confirmed pushed -- do not
    echo tell anyone this succeeded. Tell Claude exactly what git printed.
    echo ============================================================
    pause
    exit /b %PUSH_RESULT%
)

REM Belt-and-suspenders: don't just trust a zero exit code, confirm the remote actually has it.
for /f "delims=" %%r in ('git ls-remote origin "refs/heads/%CURRENT_BRANCH%" 2^>nul') do set "REMOTE_LINE=%%r"
echo %REMOTE_LINE% | findstr /i "%CURRENT_COMMIT%" >nul
if errorlevel 1 (
    echo ============================================================
    echo ERROR: push reported success, but origin's ref for
    echo   %CURRENT_BRANCH%
    echo does not show commit %CURRENT_COMMIT% when queried directly.
    echo Treat this as NOT confirmed pushed. Tell Claude exactly what
    echo `git ls-remote origin refs/heads/%CURRENT_BRANCH%` shows.
    echo ============================================================
    pause
    exit /b 1
)

echo.
echo Done and verified: origin/%CURRENT_BRANCH% now points at %CURRENT_COMMIT%.
echo Tell the PM session (or Claude) it's pushed -- it'll open the PR once #52 clears.
echo.
pause
exit /b 0
