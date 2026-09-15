<#
.SYNOPSIS
  Read the usage state statusline.ps1 last wrote, and say whether the
  orchestrator should issue the pause order.

.DESCRIPTION
  No arguments: prints the last-known five-hour/weekly percentages and
  whether the pause flag is currently raised.

  -Acknowledge: after you've actually sent the pause order to every session,
  clear the flag file's "acknowledged" mark so this tool won't tell you to
  pause again for the SAME crossing (statusline.ps1 itself clears the flag
  entirely once usage drops back under threshold or the window resets).

  This tool makes no network calls and reads only local files written by
  statusline.ps1 -- see that script for where the data comes from and why the
  Admin API isn't an option for an individual Pro/Max seat.
#>
[CmdletBinding()]
param(
    [switch]$Acknowledge
)

$StoreDir = Join-Path $env:APPDATA 'AEGIS'
$StatePath = Join-Path $StoreDir 'claude-usage-state.json'
$FlagPath = Join-Path $StoreDir 'claude-usage-pause-flag.json'

if (-not (Test-Path $StatePath)) {
    Write-Output "No usage data yet: usage is UNKNOWN, not fine. Run usage-watch.ps1 -Once (works from VS Code) or start the usage watcher; the statusline never runs in the VS Code extension."
    exit 2
}

$state = Get-Content $StatePath -Raw | ConvertFrom-Json
$ageMin = [math]::Round(((Get-Date).ToUniversalTime() - [datetime]$state.checkedAtUtc).TotalMinutes, 1)
Write-Output "Last updated: $($state.checkedAtUtc) (${ageMin} min ago)"
if ($state.fiveHour) { Write-Output ("  5-hour window:  {0}% used, resets {1}" -f $state.fiveHour.usedPercentage, $state.fiveHour.resetsAtUtc) }
if ($state.sevenDay) { Write-Output ("  Weekly window:  {0}% used, resets {1}" -f $state.sevenDay.usedPercentage, $state.sevenDay.resetsAtUtc) }

if (Test-Path $FlagPath) {
    $flag = Get-Content $FlagPath -Raw | ConvertFrom-Json
    if ($Acknowledge) {
        $flag | Add-Member -NotePropertyName acknowledgedAtUtc -NotePropertyValue ((Get-Date).ToUniversalTime().ToString('o')) -Force
        $flag | ConvertTo-Json | Set-Content -Path $FlagPath -Encoding utf8
        Write-Output "`nPAUSE FLAG acknowledged (still on disk until usage drops or the window resets, so re-runs don't re-trigger you)."
        exit 0
    }
    if ($flag.acknowledgedAtUtc) {
        Write-Output "`nPause flag raised at $($flag.raisedAtUtc) ($($flag.usedPercentage)% of $($flag.window)) -- already acknowledged at $($flag.acknowledgedAtUtc)."
        exit 0
    }
    Write-Output "`n*** PAUSE THRESHOLD CROSSED *** $($flag.usedPercentage)% of the $($flag.window) window (threshold $($flag.threshold)%), resets $($flag.resetsAtUtc)."
    Write-Output "Issue the pause order to every session (see MasterThread standards/sessions/orchestrator_role.md 'Cost rule'), then re-run this with -Acknowledge."
    exit 1
}

Write-Output "`nUnder threshold. No action needed."
exit 0
