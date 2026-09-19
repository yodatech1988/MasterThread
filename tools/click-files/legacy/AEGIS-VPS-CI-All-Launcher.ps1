<#
.SYNOPSIS
  Owner-run. Launches the tracked `services\tools\AEGIS-VPS-CI-All.ps1` (services PR #94) to
  move AEGIS CI onto the OVH VPS runners.

.DESCRIPTION
  Fixes the path typo found in PM_INBOX\github-de-20260918T0353Z-clickfile-inventory-sweep.md:
  the real script lives at `services\tools\AEGIS-VPS-CI-All.ps1`, not
  `aegis-services\tools\...` -- `aegis-services\` exists as a directory but has no `tools\`
  folder at all, so the old path was silently wrong, not merely stale.

  This is a live-VPS action script (registers runners, turns on scheduled-job timers) owned by
  the services repo, not by this file -- this launcher does not modify or duplicate its content.
  It only adds the disciplines tools/README.md requires of everything under `GitHub\AEGIS-*.cmd`:
  a real console gate, dry-run-vs-real log naming, and a log on every exit path -- none of which
  the bare `.cmd`-plus-`pause` shape it replaces had.

  WHAT A REAL RUN DOES: verifies `services\tools\AEGIS-VPS-CI-All.ps1` exists (refusing cleanly,
  not with a bare PowerShell "file not found", if it doesn't), asks the owner to type YES, then
  invokes that script for real. This launcher runs the real action ONLY when started by a person
  from a real console (stdin not redirected) and YES is typed -- a Claude session may only ever
  invoke it with -WhatIf.

.PARAMETER WhatIf
  Verify the target script exists on disk and print what would run. Writes NOTHING, asks
  nothing, invokes nothing. Writes a .dryrun.log. Safe for a Claude session to run.

.PARAMETER ServicesRepo
  Local path to the services repo checkout. Defaults to C:\Users\yoda_\GitHub\services.
#>
[CmdletBinding()]
param(
    [switch] $WhatIf,
    [string] $ServicesRepo = 'C:\Users\yoda_\GitHub\services'
)

$ErrorActionPreference = 'Stop'
$TargetScript = Join-Path $ServicesRepo 'tools\AEGIS-VPS-CI-All.ps1'

$script:RunStartTime = Get-Date
$script:TypedAnswer = 'n/a (no prompt reached)'
$script:RunOutcome = 'UNKNOWN (script exited without setting an outcome)'
$script:RunExceptionText = ''
$script:IsRealAttempt = $false

function Write-RunLog {
    $suffix = if ($script:IsRealAttempt) { 'log' } else { 'dryrun.log' }
    $log = Join-Path $PSScriptRoot ("AEGIS-VPS-CI-All.{0}.{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $suffix)
    $lines = @(
        "RUN TYPE: $(if ($script:IsRealAttempt) { 'real' } else { 'dry run (nothing was changed)' })"
        "Start time (local): $($script:RunStartTime.ToString('o'))"
        "Target script: $TargetScript"
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

$targetExists = Test-Path -LiteralPath $TargetScript
if (-not $targetExists) {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Red
    Write-Host 'RETIRED/BROKEN - target path does not exist:' -ForegroundColor Red
    Write-Host "  $TargetScript" -ForegroundColor Red
    Write-Host 'This launcher refuses rather than guess. Check whether the services repo checkout' -ForegroundColor Yellow
    Write-Host 'has moved, or whether the tracked script itself was renamed or removed upstream.' -ForegroundColor Yellow
    Write-Host '============================================================' -ForegroundColor Red
    $script:RunOutcome = "REFUSE: target script not found at $TargetScript"
    exit 2
}

Write-Host "Target script found: $TargetScript" -ForegroundColor Green
Write-Host ''
Write-Host 'This puts GitHub Actions for the private AEGIS repos on the VPS runners (no GitHub billing):'
Write-Host '  1. applies the merged runner fix (every VPS job currently fails at setup without it)'
Write-Host "  2. registers a runner for each AEGIS repo that doesn't have one yet"
Write-Host '  3. turns on the scheduled-job timers whose keys are in place'
Write-Host '  4. checks everything and re-runs failed checks'
Write-Host ''
Write-Host 'Not touched: the DayZ server, handymansfield, jarvis, finance/personal repos, public repos.'
Write-Host 'Safe to run again.'

if ($WhatIf) {
    Write-Host ''
    Write-Host '-WhatIf: target script confirmed to exist. Nothing was invoked, nothing asked.' -ForegroundColor Yellow
    $script:TypedAnswer = 'n/a (-WhatIf never prompts)'
    $script:RunOutcome = "-WhatIf: target script confirmed present at $TargetScript. Nothing invoked."
    exit 0
}

# --- initiation binding: a person at a real console, never a session's tool call ---------------
if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
    Write-Host ''
    Write-Host 'REFUSED: this must be started by the owner from a real console window (double-click the .cmd).' -ForegroundColor Red
    Write-Host 'A Claude session may only run it with -WhatIf.' -ForegroundColor Red
    $script:TypedAnswer = 'n/a (refused before any prompt)'
    $script:RunOutcome = 'REFUSED: not an interactive console.'
    exit 2
}

Write-Host ''
$answer = Read-Host 'Type YES to proceed (anything else cancels)'
$script:TypedAnswer = if ($answer -ceq 'YES') { 'YES' } else { 'cancelled' }
if ($answer -cne 'YES') {
    Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow
    $script:RunOutcome = 'Owner did not type YES. Cancelled, nothing changed.'
    exit 0
}

$script:IsRealAttempt = $true
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $TargetScript
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Target script exited with code $exitCode"
    }
} catch {
    $ex = $_.Exception
    Write-Host ''
    Write-Host "FAILED: $($ex.GetType().FullName): $($ex.Message)" -ForegroundColor Red
    $script:RunExceptionText = "Type: $($ex.GetType().FullName)`nMessage: $($ex.Message)`n$($ex.ToString())"
    $script:RunOutcome = "FAILED: target script threw or exited non-zero -- $($ex.Message)"
    exit 1
}

Write-Host ''
Write-Host 'Target script completed.' -ForegroundColor Green
$script:RunOutcome = 'Target script invoked and completed (exit 0).'

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
