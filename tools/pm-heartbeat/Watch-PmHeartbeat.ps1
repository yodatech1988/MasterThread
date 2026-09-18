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
    scheduled task (the owner's click-file registers that; see README.md in this folder).

    SILENT BY DEFAULT (owner instruction, 2026-09-18 01:07Z, direct: "I got pm heartbeat
    missing pop ups. I don't need these notifications."): a scheduled run produced modal
    `msg.exe` popups on his desktop during testing. This script now only ever writes a
    stdout line, an exit code, and -- if `-LogPath` is given -- an appended log line. It
    raises a desktop notification only when the caller explicitly passes `-Notify`, and
    that path is BurntToast-only: no `msg.exe`, no other modal or UI fallback of any kind.
    If `-Notify` is passed and BurntToast isn't installed, it prints one stdout line saying
    so instead of trying another notification mechanism.

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

.PARAMETER StateDir
    Directory holding the two files this reads: `<StateDir>\pm-heartbeat.json` and
    `<StateDir>\claude-usage-state.json`. Defaults to `%APPDATA%\AEGIS`. Matches
    `Write-PmHeartbeat.ps1`'s `-StateDir` -- tests pass the same scratch directory to both
    scripts. (Previously this took a `-StatePath` that was treated as a directory while
    `Write-PmHeartbeat.ps1`'s same-named param was a file path; that mismatch caused a real
    run to write nothing where expected. `-StateDir` on both scripts replaces it.)

.PARAMETER Notify
    Opt-in only. Without it, this script never raises any desktop notification -- stdout
    and exit code only, per the owner's 2026-09-18 instruction (see DESCRIPTION). With it,
    a STALE or MISSING result raises a BurntToast notification if the BurntToast module is
    installed; if it is not, one stdout line says so. No other notification mechanism is
    used under any circumstance -- in particular, never `msg.exe` or any other modal popup.

.PARAMETER LogPath
    Optional. When given, appends the single result line (with a UTC timestamp) to this
    file. Purely additive; never required, never printed to any UI.

.OUTPUTS
    One line to stdout, always. A line appended to `-LogPath` if given. A BurntToast
    notification only if `-Notify` is passed and the result is STALE or MISSING. Never
    reads or prints any secret -- it only reads two small JSON files this repo's own
    scripts wrote.
#>
[CmdletBinding()]
param(
    [int]    $StaleMinutes = 30,
    [int]    $UsageCeiling = 80,
    [switch] $Once,
    [switch] $Notify,
    [string] $LogPath,

    [string] $StateDir = (Join-Path $env:APPDATA 'AEGIS')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$HeartbeatPath = Join-Path $StateDir 'pm-heartbeat.json'
$UsageStatePath = Join-Path $StateDir 'claude-usage-state.json'

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

function Write-Result([string] $Line) {
    # The only stdout/log surface. No UI here -- see Send-Notice for the opt-in-only
    # BurntToast path, which is invoked separately, only when -Notify is set.
    Write-Output $Line
    if ($LogPath) {
        try {
            $stamp = [DateTime]::UtcNow.ToString('o')
            Add-Content -Path $LogPath -Value "$stamp $Line" -Encoding utf8
        } catch { }
    }
}

function Send-Notice([string] $Title, [string] $Message) {
    # Opt-in only (-Notify). Owner instruction 2026-09-18 01:07Z: no popups by default, and
    # no modal fallback of any kind -- BurntToast or nothing. A missing module prints one
    # stdout line via Write-Result instead of trying msg.exe or any other mechanism.
    if (-not $Notify) { return }
    try {
        if (Get-Module -ListAvailable -Name BurntToast -ErrorAction SilentlyContinue) {
            Import-Module BurntToast -ErrorAction Stop
            New-BurntToastNotification -Text $Title, $Message
            return
        }
    } catch { }
    Write-Result "PM-HEARTBEAT NOTIFY-SKIPPED BurntToast is not installed; no other notification mechanism is used."
}

if (-not (Test-Path $HeartbeatPath)) {
    $line = "PM-HEARTBEAT MISSING no heartbeat file at $HeartbeatPath -- the PM has never ticked, or the file was cleared."
    Write-Result $line
    Send-Notice 'PM heartbeat missing' $line
    exit 2
}

$hb = $null
try {
    $hb = Get-Content -Path $HeartbeatPath -Raw | ConvertFrom-Json
} catch {
    $line = "PM-HEARTBEAT MISSING heartbeat file at $HeartbeatPath is unreadable: $($_.Exception.Message)"
    Write-Result $line
    Send-Notice 'PM heartbeat unreadable' $line
    exit 2
}

$tickAtUtc = Get-JsonProp $hb 'tickAtUtc'
if (-not $tickAtUtc) {
    $line = "PM-HEARTBEAT MISSING heartbeat file at $HeartbeatPath has no tickAtUtc field."
    Write-Result $line
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
    Write-Result $line
    Send-Notice 'PM heartbeat stale' "$sessionName has not ticked in ${ageMinutes} minutes ($usageText). It should be dispatching."
    exit 1
}

Write-Result "PM-HEARTBEAT OK ${ageMinutes}m session=$sessionName"
exit 0
