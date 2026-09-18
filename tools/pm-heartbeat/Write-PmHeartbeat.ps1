<#
.SYNOPSIS
    Records that the PM's heartbeat tick ran, for `Watch-PmHeartbeat.ps1` to check.

.DESCRIPTION
    The PM heartbeat (standards/sessions/pm_role.md, "The control loop") is a
    `CronCreate "*/10 * * * *"` tick whose prompt IS the control loop: read usage, check
    ListAgents/roster, dispatch dispatchable work, own its Decision Queue cards, write its
    Fleet Status `sessions` row. The last step of every tick, quiet or not, is calling this
    script so an external watchdog can tell a live-but-stalled PM from a dead one.

    Writes exactly one JSON file. Idempotent (last write wins), no network call, no read of
    any other file. A quiet tick (nothing dispatchable) still calls this -- the invariant in
    pm_role.md is "a tick never ends with dispatchable work, budget, and idle capacity", not
    "a tick only reports when it did something."

.PARAMETER Name
    The PM session's name, exactly as `ListAgents` shows it (not the "ops-cycle-pm" role
    label). Required.

.PARAMETER Usage5h
    The 5-hour window's used percentage at the time of this tick, as an integer 0-100. Read
    it from claude-usage-state.json (fiveHour.usedPercentage) -- this script does not read
    that file itself, so a bad or stale number here is the caller's mistake, not this
    script's.

.PARAMETER Dispatched
    Count of things this tick dispatched (Agent calls, cards it owned via `get`, register
    rows it moved). 0 on a quiet tick.

.PARAMETER Note
    Optional one-line free-text note, e.g. "3 dispatchable rows, 0 idle" or
    "quiet tick, nothing dispatchable". Kept short; this is a heartbeat, not a report.

.PARAMETER StateDir
    Directory the heartbeat file is written into, as `<StateDir>\pm-heartbeat.json`.
    Defaults to `%APPDATA%\AEGIS`. Tests should always pass a scratch directory here so
    they never touch the real file. (Matches `Watch-PmHeartbeat.ps1`'s `-StateDir` --
    the two scripts used to take differently-shaped `-StatePath` params, one a file and
    one a directory, which was confusing enough to be a bug in practice.)

.OUTPUTS
    Writes the file and prints one confirmation line. No exit-code signaling beyond normal
    PowerShell error propagation -- this script either writes the file or throws.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Name,

    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 100)]
    [int] $Usage5h,

    [Parameter(Mandatory = $true)]
    [ValidateRange(0, [int]::MaxValue)]
    [int] $Dispatched,

    [string] $Note = '',

    [string] $StateDir = (Join-Path $env:APPDATA 'AEGIS')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StatePath = Join-Path $StateDir 'pm-heartbeat.json'
if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }

$record = [ordered]@{
    session     = $Name
    tickAtUtc   = [DateTime]::UtcNow.ToString('o')
    usage5h     = $Usage5h
    dispatched  = $Dispatched
    note        = $Note
}

# Write via a per-process temp file and swap in, same pattern as usage-watch.ps1's
# Write-FileAtomic, so a heartbeat write never collides with a watchdog read mid-write.
$tmp = "$StatePath.$PID.tmp"
for ($i = 0; $i -lt 5; $i++) {
    try {
        ($record | ConvertTo-Json -Depth 4) | Out-File -FilePath $tmp -Encoding utf8
        Move-Item -Path $tmp -Destination $StatePath -Force
        Write-Output ("PM-HEARTBEAT written: session={0} usage5h={1}% dispatched={2} at={3}" -f $Name, $Usage5h, $Dispatched, $record.tickAtUtc)
        return
    } catch {
        Start-Sleep -Milliseconds (50 + (Get-Random -Maximum 150))
    }
}
Remove-Item $tmp -Force -ErrorAction SilentlyContinue
throw "could not write heartbeat file at $StatePath after 5 attempts"
