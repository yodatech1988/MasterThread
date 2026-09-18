<#
.SYNOPSIS
    External watchdog: is the PM's heartbeat (`Write-PmHeartbeat.ps1`) still current?

.DESCRIPTION
    Rung L1 of the headless readiness ladder (PM_PHASE_ADVISORY_2026-09-18.md section 0,
    layer D) -- verification only, never dispatches anything. It answers one question: has
    the PM's control-loop tick written a heartbeat recently, while usage still has headroom
    to run one? A stale heartbeat under headroom is the exact failure the owner reported
    2026-09-18 ~00:50Z -- a PM session showing `busy` in `ListAgents` but not dispatching.

    This script never starts, stops, or messages a session. It is meant to run as a Windows
    scheduled task (the owner's click-file registers that; see README.md in this folder) so
    the owner is told the PM stalled without having to open a session and look himself.

    Logic:
      - heartbeat file missing                          -> PM-HEARTBEAT MISSING   (exit 2)
      - heartbeat older than -StaleMinutes AND usage
        below -UsageCeiling (there was room to tick)     -> PM-HEARTBEAT STALE     (exit 1)
      - otherwise                                        -> PM-HEARTBEAT OK        (exit 0)

    A heartbeat that is old AND usage is at or above -UsageCeiling is deliberately NOT
    flagged stale: the PM may simply be correctly paused per the tier runbook
    (orchestrator_role.md), and a watchdog that pages the owner for a correct pause would
    train him to ignore it.

.PARAMETER StaleMinutes
    How old the heartbeat can be before it counts as stale. Default 30 -- double the 10-minute
    tick interval, so one missed or slow tick alone never pages the owner.

.PARAMETER UsageCeiling
    Usage percentage (5-hour window) below which a stale heartbeat is treated as a real
    stall rather than a correct pause. Default 80, matching the PREPARE tier in
    orchestrator_role.md's tier runbook.

.PARAMETER Once
    Present for symmetry with usage-watch.ps1's `-Once` and to make intent explicit in a
    scheduled-task invocation; this script always runs once and exits (it is not a loop), so
    this switch changes no behavior. It exists so a caller reading the invocation line does
    not have to guess whether this script polls.

.PARAMETER HeartbeatPath / .PARAMETER UsageStatePath
    Overrides for the two files this reads. Default
    `%APPDATA%\AEGIS\pm-heartbeat.json` and `%APPDATA%\AEGIS\claude-usage-state.json`.

.PARAMETER StatePath
    Convenience override that sets BOTH -HeartbeatPath and -UsageStatePath to files under
    the same directory (`<StatePath>\pm-heartbeat.json`, `<StatePath>\claude-usage-state.json`),
    for tests that want one switch instead of two. Explicit -HeartbeatPath/-UsageStatePath
    win if also supplied.

.OUTPUTS
    One line to stdout, and a toast notification when BurntToast is installed (falls back to
    `msg.exe` to the current console session, then to Write-Warning, so the script never
    depends on a module being present). Never reads or prints any secret -- it only reads two
    small JSON files this repo's own scripts wrote.
#>
[CmdletBinding()]
param(
    [int]    $StaleMinutes = 30,
    [int]    $UsageCeiling = 80,
    [switch] $Once,

    [string] $StatePath,
    [string] $HeartbeatPath,
    [string] $UsageStatePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$defaultDir = Join-Path $env:APPDATA 'AEGIS'
if (-not $HeartbeatPath) {
    $HeartbeatPath = if ($StatePath) { Join-Path $StatePath 'pm-heartbeat.json' } else { Join-Path $defaultDir 'pm-heartbeat.json' }
}
if (-not $UsageStatePath) {
    $UsageStatePath = if ($StatePath) { Join-Path $StatePath 'claude-usage-state.json' } else { Join-Path $defaultDir 'claude-usage-state.json' }
}

function Get-JsonProp($Object, [string] $Name) {
    # Set-StrictMode -Version Latest makes dot-access on a PSCustomObject throw
    # PropertyNotFoundException when the property is absent (found via diff-reviewer,
    # 2026-09-18: a heartbeat/usage file missing an expected field crashed this script
    # instead of hitting its own MISSING/unknown-usage branches). Every read of a field
    # parsed from JSON goes through this instead of bare dot-access.
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Send-Notice([string] $Title, [string] $Message) {
    # Best-effort, dependency-free. Never let notification delivery fail the check itself.
    try {
        if (Get-Module -ListAvailable -Name BurntToast -ErrorAction SilentlyContinue) {
            Import-Module BurntToast -ErrorAction Stop
            New-BurntToastNotification -Text $Title, $Message
            return
        }
    } catch { }
    try {
        $null = msg.exe $env:USERNAME "$Title`n$Message" 2>$null
        return
    } catch { }
    Write-Warning "$Title -- $Message"
}

if (-not (Test-Path $HeartbeatPath)) {
    $line = "PM-HEARTBEAT MISSING no heartbeat file at $HeartbeatPath -- the PM has never ticked, or the file was cleared."
    Write-Output $line
    Send-Notice 'PM heartbeat missing' $line
    exit 2
}

$hb = $null
try {
    $hb = Get-Content -Path $HeartbeatPath -Raw | ConvertFrom-Json
} catch {
    $line = "PM-HEARTBEAT MISSING heartbeat file at $HeartbeatPath is unreadable: $($_.Exception.Message)"
    Write-Output $line
    Send-Notice 'PM heartbeat unreadable' $line
    exit 2
}

$tickAtUtc = Get-JsonProp $hb 'tickAtUtc'
if (-not $tickAtUtc) {
    $line = "PM-HEARTBEAT MISSING heartbeat file at $HeartbeatPath has no tickAtUtc field."
    Write-Output $line
    Send-Notice 'PM heartbeat malformed' $line
    exit 2
}

$tickAt = [DateTime]::Parse($tickAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
$ageMinutes = [math]::Round(((Get-Date).ToUniversalTime() - $tickAt).TotalMinutes, 1)
$hbSession = Get-JsonProp $hb 'session'
$sessionName = if ($hbSession) { [string]$hbSession } else { '?' }

$usagePct = $null
if (Test-Path $UsageStatePath) {
    try {
        $usage = Get-Content -Path $UsageStatePath -Raw | ConvertFrom-Json
        $fiveHour = Get-JsonProp $usage 'fiveHour'
        $usedPct = Get-JsonProp $fiveHour 'usedPercentage'
        if ($null -ne $usedPct) { $usagePct = [double]$usedPct }
    } catch { }
}

$isStale = $ageMinutes -gt $StaleMinutes
$hasHeadroom = ($null -eq $usagePct) -or ($usagePct -lt $UsageCeiling)
# Unknown usage counts as headroom for the purpose of raising an alert: silence-on-uncertainty
# would hide exactly the stall the owner asked never to be missed again (2026-09-18 ~00:50Z).

if ($isStale -and $hasHeadroom) {
    $usageText = if ($null -ne $usagePct) { "usage=$usagePct%" } else { 'usage=unknown' }
    $line = "PM-HEARTBEAT STALE ${ageMinutes}m session=$sessionName $usageText"
    Write-Output $line
    Send-Notice 'PM heartbeat stale' "$sessionName has not ticked in ${ageMinutes} minutes ($usageText). It should be dispatching."
    exit 1
}

Write-Output "PM-HEARTBEAT OK ${ageMinutes}m session=$sessionName"
exit 0
