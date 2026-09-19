<#
.SYNOPSIS
  Owner-run. Removes the AEGIS-L1Pilot scheduled task registered by AEGIS-Register-L1Pilot.cmd.

.DESCRIPTION
  Undo path named in AEGIS-Register-L1Pilot.ps1's own header. Removes the Windows Scheduled Task
  named -TaskName (default AEGIS-L1Pilot). Does not touch any copied tooling under
  %APPDATA%\AEGIS\l1-pilot\ or any report file under %APPDATA%\AEGIS\reports\ -- only the
  scheduled task registration.

  This is a host scheduling change, so no Claude session runs this for real against the real
  task name; it refuses unless started by a person from a real console and YES is typed --
  UNLESS -TaskName is explicitly a scratch name (not AEGIS-L1Pilot), which a session may remove
  without the console gate, since that can never be the owner-gated real task.

  If no task by this name exists, prints "NOT REGISTERED -- nothing to do" and exits 0 without
  asking anything.

  Unlike AEGIS-Unregister-PmHeartbeat-Watchdog.ps1 (its direct precedent, which logs only on its
  success path), this script logs on EVERY exit path per tools/README.md's own rule -- fixed
  here rather than copied forward, since the precedent script's own gap is exactly the "log
  exists only on the happy path" failure the standard warns against.

.PARAMETER WhatIf
  Report whether the task exists and what would be removed. Change nothing, ask nothing.

.PARAMETER TaskName
  The scheduled task to remove. Defaults to the real task name, AEGIS-L1Pilot. A scratch name
  (anything else) skips the interactive-console gate, since it can never be the real task.
#>
[CmdletBinding()]
param(
    [switch] $WhatIf,
    [string] $TaskName = 'AEGIS-L1Pilot'
)

$ErrorActionPreference = 'Stop'
$RealTaskName = 'AEGIS-L1Pilot'

$script:RunStartTime = Get-Date
$script:TypedAnswer = 'n/a (no prompt reached)'
$script:RunOutcome = 'UNKNOWN (script exited without setting an outcome)'
$script:RunExceptionText = ''
$script:IsRealAttempt = $false

function Write-RunLog {
    $suffix = if ($script:IsRealAttempt) { 'log' } else { 'dryrun.log' }
    $log = Join-Path $PSScriptRoot ("AEGIS-Unregister-L1Pilot.{0}.{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $suffix)
    $lines = @(
        "RUN TYPE: $(if ($script:IsRealAttempt) { 'real' } else { 'dry run (nothing was changed)' })"
        "Start time (local): $($script:RunStartTime.ToString('o'))"
        "Task name: $TaskName"
        ''
        "Owner typed: $($script:TypedAnswer)"
        "Outcome: $($script:RunOutcome)"
    )
    if ($script:RunExceptionText) {
        $lines += ''
        $lines += 'Exception:'
        $lines += $script:RunExceptionText
    }
    try {
        $lines | Out-File -FilePath $log -Encoding utf8
        Write-Host "Log: $log"
    } catch {
        Write-Host "WARNING: could not write run log to $log`: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

try {

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $existing) {
    Write-Host 'NOT REGISTERED -- nothing to do.' -ForegroundColor Green
    $script:RunOutcome = "NOT REGISTERED: no task named $TaskName exists."
    exit 0
}

$action = $existing.Actions | Select-Object -First 1
Write-Host "Found task: $TaskName"
Write-Host "  Program  : $($action.Execute)"
Write-Host "  Arguments: $($action.Arguments)"

if ($WhatIf) {
    Write-Host ''
    Write-Host '-WhatIf: this task would be removed. No changes made.' -ForegroundColor Yellow
    $script:TypedAnswer = 'n/a (-WhatIf never prompts)'
    $script:RunOutcome = "-WhatIf: task $TaskName exists and would be removed; nothing changed."
    exit 0
}

$isScratchName = -not ($TaskName -ieq $RealTaskName)

if (-not $isScratchName) {
    # --- initiation binding: a person at a real console, never a session's tool call -----------
    if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
        Write-Host ''
        Write-Host 'REFUSED: this must be started by the owner from a real console window (double-click the .cmd).' -ForegroundColor Red
        Write-Host 'A Claude session may only run it with -WhatIf, or with -TaskName set to a scratch name.' -ForegroundColor Red
        $script:TypedAnswer = 'n/a (refused before any prompt)'
        $script:RunOutcome = 'REFUSED: not an interactive console and TaskName is the real task.'
        exit 2
    }

    Write-Host ''
    $answer = Read-Host 'Type YES to remove this scheduled task (anything else cancels)'
    $script:TypedAnswer = if ($answer -ceq 'YES') { 'YES' } else { 'cancelled' }
    if ($answer -cne 'YES') {
        Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow
        $script:RunOutcome = 'Owner did not type YES. Cancelled, nothing changed.'
        exit 0
    }
} else {
    $script:TypedAnswer = 'n/a (scratch task name, no prompt needed)'
}

$script:IsRealAttempt = $true
try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
} catch {
    $ex = $_.Exception
    Write-Host ''
    Write-Host "FAILED: Unregister-ScheduledTask threw $($ex.GetType().FullName): $($ex.Message)" -ForegroundColor Red
    $script:RunExceptionText = "Type: $($ex.GetType().FullName)`nMessage: $($ex.Message)`n$($ex.ToString())"
    $script:RunOutcome = "FAILED: Unregister-ScheduledTask threw $($ex.GetType().FullName). Task may still exist."
    exit 1
}

$after = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $after) {
    Write-Host 'REMOVED and verified.' -ForegroundColor Green
    $script:RunOutcome = "REMOVED and verified: $TaskName."
} else {
    Write-Host 'FAILED to verify removal.' -ForegroundColor Red
    $script:RunOutcome = "FAILED: Unregister-ScheduledTask did not throw but Get-ScheduledTask still finds $TaskName."
    exit 1
}

}
catch {
    $ex = $_.Exception
    Write-Host ''
    Write-Host "UNEXPECTED EXCEPTION: $($ex.GetType().FullName): $($ex.Message)" -ForegroundColor Red
    if (-not $script:RunExceptionText) {
        $script:RunExceptionText = "Type: $($ex.GetType().FullName)`nMessage: $($ex.Message)`n$($ex.ToString())"
    }
    if ($script:RunOutcome -eq 'UNKNOWN (script exited without setting an outcome)') {
        $script:RunOutcome = "FAILED: unhandled exception $($ex.GetType().FullName) -- $($ex.Message)"
    }
    exit 1
}
finally {
    Write-RunLog
}
