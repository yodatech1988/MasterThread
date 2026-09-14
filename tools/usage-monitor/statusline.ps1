<#
.SYNOPSIS
  Claude Code statusline script that also persists subscription rate-limit usage
  to a small local file, so any session (especially the orchestrator) can check
  "how close to the reset are we" without re-deriving it from chat transcripts.

.DESCRIPTION
  Claude Code invokes this script with a JSON blob on stdin every time the
  statusline needs to redraw (a new assistant message, /compact, a rate-limit
  window's resets_at passing, etc. -- see the statusline docs). On a Claude.ai
  Pro/Max subscription, that JSON carries a `rate_limits` object:
    rate_limits.five_hour.used_percentage / .resets_at
    rate_limits.seven_day.used_percentage / .resets_at
  This is the ONLY machine-readable source for subscription-seat usage. The
  Admin API's usage/cost endpoints and the Claude Code Analytics API are scoped
  to Console (API-key) workspaces and Team/Enterprise orgs -- an individual
  Pro/Max plan has no organization to query, so they report nothing here.
  (Confirmed against code.claude.com/docs/en/costs and .../statusline,
  2026-09-14 -- re-check if Anthropic changes this.)

  This script does two things:
    1. Prints a compact statusline (model, cost, context %, rate-limit %).
    2. Writes the rate_limits object (plus a computed timestamp) to
       %APPDATA%\AEGIS\claude-usage-state.json, and if either window is at or
       above $PauseThreshold, ALSO writes claude-usage-pause-flag.json. That
       second file is the actual trigger: any session can poll for it (see
       check-usage.ps1) and, on finding it, issue the pause order to peers.
       Writing a flag file is necessary because a statusline script can't call
       SendMessage/ListAgents itself -- only a live Claude Code session can.

  Runs entirely locally, writes only to two small JSON files, and makes no
  network calls of its own -- zero additional cost (matches the doc's own
  note that the statusline "runs locally and does not consume API tokens").

.NOTES
  Install by adding to ~/.claude/settings.json (merge with any existing keys):
    "statusLine": {
      "type": "command",
      "command": "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\yoda_\\GitHub\\MasterThread\\tools\\usage-monitor\\statusline.ps1"
    }
  Point at wherever this repo is checked out; the worktree copy also works.
#>
[CmdletBinding()]
param(
    [int]$PauseThreshold = 80
)

$ErrorActionPreference = 'Stop'
$StoreDir = Join-Path $env:APPDATA 'AEGIS'
$StatePath = Join-Path $StoreDir 'claude-usage-state.json'
$FlagPath = Join-Path $StoreDir 'claude-usage-pause-flag.json'

$raw = [Console]::In.ReadToEnd()
$data = $null
try { $data = $raw | ConvertFrom-Json } catch { $data = $null }

function Fmt-Reset([long]$epoch) {
    if (-not $epoch) { return '?' }
    $dt = [DateTimeOffset]::FromUnixTimeSeconds($epoch).ToLocalTime()
    return $dt.ToString('HH:mm')
}

$modelName = if ($data.model.display_name) { $data.model.display_name } else { 'claude' }
$cost = if ($null -ne $data.cost.total_cost_usd) { '${0:N2}' -f $data.cost.total_cost_usd } else { '$0.00' }
$ctxPct = if ($null -ne $data.context_window.used_percentage) { [math]::Round($data.context_window.used_percentage) } else { $null }

$fiveHour = $data.rate_limits.five_hour
$sevenDay = $data.rate_limits.seven_day

$line = "$modelName | $cost"
if ($null -ne $ctxPct) { $line += " | ctx ${ctxPct}%" }
if ($fiveHour) { $line += (" | 5h {0}% (resets {1})" -f [math]::Round($fiveHour.used_percentage), (Fmt-Reset $fiveHour.resets_at)) }
if ($sevenDay) { $line += (" | wk {0}% (resets {1})" -f [math]::Round($sevenDay.used_percentage), (Fmt-Reset $sevenDay.resets_at)) }
Write-Output $line

# ---- persist state + raise the pause flag -------------------------------
if ($fiveHour -or $sevenDay) {
    New-Item -ItemType Directory -Force $StoreDir | Out-Null
    $state = [ordered]@{
        checkedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        fiveHour     = if ($fiveHour) { [ordered]@{ usedPercentage = $fiveHour.used_percentage; resetsAtUtc = (Fmt-Reset $fiveHour.resets_at) } } else { $null }
        sevenDay     = if ($sevenDay) { [ordered]@{ usedPercentage = $sevenDay.used_percentage; resetsAtUtc = (Fmt-Reset $sevenDay.resets_at) } } else { $null }
    }
    $state | ConvertTo-Json -Depth 4 | Set-Content -Path $StatePath -Encoding utf8

    $worst = @($fiveHour, $sevenDay) | Where-Object { $_ } | Sort-Object -Property used_percentage -Descending | Select-Object -First 1
    if ($worst -and $worst.used_percentage -ge $PauseThreshold) {
        if (-not (Test-Path $FlagPath)) {
            [ordered]@{
                raisedAtUtc    = (Get-Date).ToUniversalTime().ToString('o')
                window         = if ($worst -eq $fiveHour) { 'five_hour' } else { 'seven_day' }
                usedPercentage = $worst.used_percentage
                resetsAtUtc    = (Fmt-Reset $worst.resets_at)
                threshold      = $PauseThreshold
            } | ConvertTo-Json | Set-Content -Path $FlagPath -Encoding utf8
        }
    } elseif (Test-Path $FlagPath) {
        # Usage window reset (or dropped back under threshold) -- clear the
        # flag automatically so the next crossing raises a fresh one.
        Remove-Item $FlagPath -Force
    }
}
