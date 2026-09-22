@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fake-gh.ps1" %*
