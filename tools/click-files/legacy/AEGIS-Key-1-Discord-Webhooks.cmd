@echo off
if not exist "C:\Users\yoda_\GitHub\_wt-services-ovh-migration\tools\DiscordWebhooksKey.ps1" (
  echo ============================================================
  echo RETIRED/BROKEN - target path no longer exists:
  echo   C:\Users\yoda_\GitHub\_wt-services-ovh-migration\tools\DiscordWebhooksKey.ps1
  echo This was a git worktree that has since been removed/pruned. This click-file
  echo cannot run until it is rebuilt against a durable location or retired.
  echo See PM_INBOX report github-de-20260918T0353Z-clickfile-inventory-sweep.md.
  echo ============================================================
  pause
  exit /b 1
)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\yoda_\GitHub\_wt-services-ovh-migration\tools\DiscordWebhooksKey.ps1"
