@echo off
title AEGIS: move all AEGIS CI onto the OVH VPS
REM Fixed 2026-09-18: the target path had a one-word typo (aegis-services -> services). The
REM RETIRED/BROKEN guard this file used to carry is gone -- the underlying logic (verify the
REM target exists, refuse cleanly if not) now lives in AEGIS-VPS-CI-All-Launcher.ps1, which also
REM adds a real-console gate, a typed YES prompt, and a log on every exit path
REM (tools/README.md), none of which the old bare pause-then-invoke shape had.
REM No Claude session runs this for real -- only your double-click does. A session may only
REM invoke the launcher with -WhatIf.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0AEGIS-VPS-CI-All-Launcher.ps1" %*
