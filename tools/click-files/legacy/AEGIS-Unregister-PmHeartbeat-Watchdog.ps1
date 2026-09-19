<#
.SYNOPSIS
  Owner-run. Removes the AEGIS-PmHeartbeat-Watchdog scheduled task registered by
  AEGIS-Register-PmHeartbeat-Watchdog.cmd.

.DESCRIPTION
  Undo path named in AEGIS-Register-PmHeartbeat-Watchdog.ps1's own header. Removes the
  Windows Scheduled Task AEGIS-PmHeartbeat-Watchdog. Does not touch
  MasterThread\tools\pm-heartbeat\Watch-PmHeartbeat.ps1 or any log file it wrote; only the
  scheduled task registration.

  This is a host scheduling change, so no Claude session runs this for real; it refuses
  unless started by a person from a real console and YES is typed. A Claude session may
  only ever invoke it with -WhatIf.

  If no task by this name exists, prints "NOT REGISTERED -- nothing to do" and exits 0
  without asking anything.

.PARAMETER WhatIf
  Report whether the task exists and what would be removed. Change nothing, ask nothing.
#>
[CmdletBinding()]
param([switch] $WhatIf)

$ErrorActionPreference = 'Stop'
$TaskName = 'AEGIS-PmHeartbeat-Watchdog'

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $existing) {
    Write-Host 'NOT REGISTERED -- nothing to do.' -ForegroundColor Green
    exit 0
}

$action = $existing.Actions | Select-Object -First 1
Write-Host "Found task: $TaskName"
Write-Host "  Program  : $($action.Execute)"
Write-Host "  Arguments: $($action.Arguments)"

if ($WhatIf) {
    Write-Host ''
    Write-Host '-WhatIf: this task would be removed. No changes made.' -ForegroundColor Yellow
    exit 0
}

# --- initiation binding: a person at a real console, never a session's tool call ---------------
if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
    Write-Host ''
    Write-Host 'REFUSED: this must be started by the owner from a real console window (double-click the .cmd).' -ForegroundColor Red
    Write-Host 'A Claude session may only run it with -WhatIf.' -ForegroundColor Red
    exit 2
}

Write-Host ''
$answer = Read-Host 'Type YES to remove this scheduled task (anything else cancels)'
if ($answer -cne 'YES') {
    Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow
    exit 0
}

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
$after = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $after) {
    Write-Host 'REMOVED and verified.' -ForegroundColor Green
} else {
    Write-Host 'FAILED to verify removal.' -ForegroundColor Red
    exit 1
}

$log = Join-Path $PSScriptRoot ("AEGIS-Unregister-PmHeartbeat-Watchdog.{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
"Removed task: $TaskName" | Out-File -FilePath $log -Encoding utf8
Write-Host "Log: $log"
