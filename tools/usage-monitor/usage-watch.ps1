<#
.SYNOPSIS
  Usage notification worker for orchestrator sessions. Polls the Claude
  subscription's usage and prints ONE line each time the 5-hour session
  window (or the weekly window) crosses 80, 90, 97, 98 or 99 percent, with
  the action that tier calls for. When several orchestrators run at once, it
  warns each of the others and, from 80%, hands every one of them off to a
  single aggregator session so usage is managed centrally.

.DESCRIPTION
  Run it under Claude Code's Monitor tool at the start of every orchestrator
  round (standards/sessions/orchestrator_role.md, "Usage watcher"). Monitor
  turns each stdout line into a notification in the session, so the
  orchestrator hears about a crossing without polling or asking Jeremy.

  Why not statusline.ps1: the statusline only runs in the terminal CLI. The
  VS Code extension never calls it, so from VS Code it produced no data at
  all (found 2026-09-15). This worker works in every surface.

  Data source: GET https://api.anthropic.com/api/oauth/usage, the endpoint
  the /usage screen reads, authenticated with the OAuth access token Claude
  Code keeps in ~/.claude/.credentials.json. It is UNDOCUMENTED and can
  change without notice, so this script fails loudly: a missing field or a
  run of failed polls prints USAGE-ERROR saying usage is UNKNOWN. The token
  is read fresh on every poll (Claude Code refreshes it), is sent only to
  api.anthropic.com, and is never printed or written anywhere.

  PARALLEL ORCHESTRATORS. The limit is shared by every session on the
  account, so each watcher registers itself in <StateDir>\orchestrators\ and
  heartbeats every poll. A registration with no heartbeat for
  3 x IntervalSeconds + 30 s is treated as gone. Every watcher computes the
  same AGGREGATOR from that registry: the earliest-started live orchestrator.
  No lock is needed because every watcher reaches the same answer from the
  same files. Below 80% the aggregator is only informational. From 80%:
    - every other orchestrator is told to write its handoff immediately to
      <HandoffRoot>\USAGE_HANDOFF_<window reset>\<Name>.md, pause its lanes,
      and stop, leaving the rest of the window to the aggregator;
    - the aggregator gets the full tier runbook, is told as each handoff file
      arrives, and at 90% is told which are still missing.
  If the aggregator's heartbeat stops, the next-earliest takes over and is
  told so. The registry is local to this PC: sessions on other machines or
  in the cloud are not seen.

  Every poll also writes the same state/pause-flag files statusline.ps1 does,
  so check-usage.ps1 keeps working.

  Output lines (one per event, nothing on a quiet poll):
    USAGE START       first reading, peers, and any tier already crossed
    USAGE PEER        another orchestrator started or went silent
    USAGE AGGREGATOR  the aggregator changed
    USAGE TIER <n>    a new threshold crossed, with this session's action
    USAGE HANDOFF     (aggregator only) a peer's handoff file arrived
    USAGE RESET       a window renewed; resume from the handoff plan
    USAGE-ERROR       data unavailable or malformed; treat usage as high
    USAGE-OK          data flowing again after an error

.PARAMETER Name
  This orchestrator's name, unique among parallel sessions and safe as a file
  name, e.g. "ops-cycle-pm". Required unless -Once.

.PARAMETER Once
  Take one reading, print a status line, exit. Exit code 0 under 80%,
  1 at or above 80%, 2 when usage could not be read. Does not register.

.PARAMETER SimulateFile
  Testing only: read the endpoint's JSON from this file instead of the
  network, re-reading it every poll, so a test can move the numbers.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Name,
    [string]$Program = '',
    [int[]]$Thresholds = @(80, 90, 97, 98, 99),
    [int]$IntervalSeconds = 120,
    [int]$FastIntervalSeconds = 45,
    [int]$FastAbovePercent = 75,
    [int]$ErrorPollsBeforeAlert = 3,
    [switch]$Once,
    [string]$SimulateFile,
    [string]$StateDir = (Join-Path $env:APPDATA 'AEGIS'),
    [string]$HandoffRoot
)

$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 leaves $PSScriptRoot empty inside param() defaults.
# tools/usage-monitor -> repo -> GitHub root, for both the checkout and a worktree.
if (-not $HandoffRoot) { $HandoffRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot)) }
if (-not $Once) {
    if (-not $Name) { throw '-Name is required (a unique name for this orchestrator, e.g. -Name ops-cycle-pm)' }
    if ($Name -notmatch '^[A-Za-z0-9._-]{1,60}$') { throw "-Name '$Name' must be 1-60 letters, digits, dot, dash or underscore" }
}
$Thresholds = $Thresholds | Sort-Object -Unique
$HandoffTier = $Thresholds[0]
$StatePath = Join-Path $StateDir 'claude-usage-state.json'
$FlagPath = Join-Path $StateDir 'claude-usage-pause-flag.json'
$RegistryDir = Join-Path $StateDir 'orchestrators'
$CredPath = Join-Path $env:USERPROFILE '.claude\.credentials.json'
$UsageUri = 'https://api.anthropic.com/api/oauth/usage'
$StaleAfter = [timespan]::FromSeconds(3 * $IntervalSeconds + 30)

$Actions = @{
    80 = 'PREPARE: dispatch no new lanes. Running lanes may finish their current step. Start drafting the session handoff file.'
    90 = 'WRAP UP: send the pause order to every lane (finish the current step, push WIP to the agent branch, write a Paused note, reply in 3 lines). Record each lane''s state in the handoff.'
    97 = 'DOCUMENT: finish SESSION_HANDOFF with the next-window plan: ordered queue, which lanes resume with what model/effort, open PRs, owner blockers.'
    98 = 'SAVE: commit and push the handoff and memory updates now. No new tool-heavy work.'
    99 = 'STOP: send Jeremy a one-line status and do nothing else until the window resets.'
}
$Labels = @{ five_hour = 'session (5-hour)'; seven_day = 'weekly' }

function Emit([string]$line) {
    [Console]::Out.WriteLine($line)
    [Console]::Out.Flush()
}

function Format-LocalTime([datetimeoffset]$dt) {
    if (-not $dt) { return '?' }
    $local = $dt.ToLocalTime()
    if ($local.Date -eq (Get-Date).Date) { return $local.ToString('HH:mm') }
    return $local.ToString('ddd HH:mm')
}

function Get-UsageJson {
    if ($SimulateFile) { return (Get-Content $SimulateFile -Raw | ConvertFrom-Json) }
    if (-not (Test-Path $CredPath)) { throw "no Claude Code credentials file at $CredPath (not logged in with a subscription?)" }
    $token = (Get-Content $CredPath -Raw | ConvertFrom-Json).claudeAiOauth.accessToken
    if (-not $token) { throw 'credentials file has no claudeAiOauth.accessToken' }
    try {
        return Invoke-RestMethod -Uri $UsageUri -TimeoutSec 20 -Headers @{
            Authorization    = "Bearer $token"
            'anthropic-beta' = 'oauth-2025-04-20'
        }
    } catch {
        $status = $_.Exception.Response.StatusCode.value__
        if ($status) { throw "usage endpoint returned HTTP $status" }
        throw "usage endpoint unreachable: $($_.Exception.Message)"
    } finally {
        $token = $null
    }
}

function Read-Window($json, [string]$key) {
    $w = $json.$key
    if ($null -eq $w) { return $null }
    if ($null -eq $w.utilization) { throw "endpoint shape changed: $key.utilization missing" }
    $resets = $null
    if ($w.resets_at) { $resets = [datetimeoffset]::Parse($w.resets_at, [Globalization.CultureInfo]::InvariantCulture) }
    return [pscustomobject]@{ Key = $key; Percent = [double]$w.utilization; ResetsAt = $resets }
}

function Write-FileAtomic([string]$path, [string]$text) {
    # Several watchers write the same state files. Write a per-process temp
    # file and swap it in; retry briefly if another watcher holds the target.
    $tmp = "$path.$PID.tmp"
    for ($i = 0; $i -lt 5; $i++) {
        try {
            [IO.File]::WriteAllText($tmp, $text, (New-Object Text.UTF8Encoding $false))
            Move-Item -Path $tmp -Destination $path -Force
            return
        } catch {
            Start-Sleep -Milliseconds (50 + (Get-Random -Maximum 150))
        }
    }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

function Write-SharedState($windows) {
    New-Item -ItemType Directory -Force $StateDir | Out-Null
    $five = $windows | Where-Object Key -eq 'five_hour'
    $week = $windows | Where-Object Key -eq 'seven_day'
    [ordered]@{
        checkedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        source       = 'usage-watch.ps1'
        fiveHour     = if ($five) { [ordered]@{ usedPercentage = $five.Percent; resetsAtUtc = (Format-LocalTime $five.ResetsAt) } } else { $null }
        sevenDay     = if ($week) { [ordered]@{ usedPercentage = $week.Percent; resetsAtUtc = (Format-LocalTime $week.ResetsAt) } } else { $null }
    } | ConvertTo-Json -Depth 4 | ForEach-Object { Write-FileAtomic $StatePath $_ }

    $worst = $windows | Sort-Object Percent -Descending | Select-Object -First 1
    if ($worst -and $worst.Percent -ge $HandoffTier) {
        if (-not (Test-Path $FlagPath)) {
            [ordered]@{
                raisedAtUtc    = (Get-Date).ToUniversalTime().ToString('o')
                window         = $worst.Key
                usedPercentage = $worst.Percent
                resetsAtUtc    = (Format-LocalTime $worst.ResetsAt)
                threshold      = $HandoffTier
            } | ConvertTo-Json | ForEach-Object { Write-FileAtomic $FlagPath $_ }
        }
    } elseif (Test-Path $FlagPath) {
        Remove-Item $FlagPath -Force -ErrorAction SilentlyContinue
    }
}

function Format-StatusLine($windows) {
    ($windows | ForEach-Object { '{0} {1}% (resets {2})' -f $Labels[$_.Key], [math]::Round($_.Percent), (Format-LocalTime $_.ResetsAt) }) -join ' | '
}

# ---- registry of parallel orchestrators ---------------------------------
$MyStarted = (Get-Date).ToUniversalTime()
$MyRegPath = Join-Path $RegistryDir "$Name.json"

function Write-Heartbeat {
    New-Item -ItemType Directory -Force $RegistryDir | Out-Null
    [ordered]@{
        name          = $Name
        program       = $Program
        pid           = $PID
        startedAtUtc  = $MyStarted.ToString('o')
        heartbeatUtc  = (Get-Date).ToUniversalTime().ToString('o')
        # Carried across a restart so a re-armed watcher neither loses its
        # aggregator seniority nor repeats tiers it already announced.
        announced     = @($announced.Keys | ForEach-Object {
            $a = $announced[$_]
            [ordered]@{ window = $_; tier = $a.Tier; resetsAt = $(if ($a.ResetsAt) { $a.ResetsAt.ToString('o') }); handoffDir = $a.HandoffDir; expected = @($a.Expected) }
        })
    } | ConvertTo-Json -Depth 5 | ForEach-Object { Write-FileAtomic $MyRegPath $_ }
}

function Get-LiveOrchestrators {
    $now = (Get-Date).ToUniversalTime()
    $live = foreach ($f in @(Get-ChildItem -Path $RegistryDir -Filter '*.json' -ErrorAction SilentlyContinue)) {
        try { $r = Get-Content $f.FullName -Raw | ConvertFrom-Json } catch { continue }
        if (-not $r.name -or -not $r.heartbeatUtc) { continue }
        if (($now - ([datetime]$r.heartbeatUtc).ToUniversalTime()) -gt $StaleAfter) { continue }
        [pscustomobject]@{ Name = [string]$r.name; Program = [string]$r.program; Started = ([datetime]$r.startedAtUtc).ToUniversalTime() }
    }
    # Earliest-started first; name breaks a tie so every watcher sorts alike.
    return @($live | Sort-Object Started, Name)
}

function Format-Peer($p) {
    $what = if ($p.Program) { " ($($p.Program))" } else { '' }
    return "$($p.Name)$what"
}

function Get-HandoffDir($window) {
    $stamp = if ($window.ResetsAt) { $window.ResetsAt.ToLocalTime().ToString('yyyy-MM-dd_HHmm') } else { (Get-Date).ToString('yyyy-MM-dd_HHmm') }
    $suffix = if ($window.Key -eq 'seven_day') { '_weekly' } else { '' }
    return Join-Path $HandoffRoot "USAGE_HANDOFF_$stamp$suffix"
}

# ---- one-shot mode ------------------------------------------------------
if ($Once) {
    try {
        $json = Get-UsageJson
        $windows = @('five_hour', 'seven_day' | ForEach-Object { Read-Window $json $_ } | Where-Object { $_ })
        if ($windows.Count -eq 0) { throw 'endpoint returned neither five_hour nor seven_day' }
    } catch {
        Emit "USAGE-ERROR usage is UNKNOWN: $($_.Exception.Message). Check /usage manually."
        exit 2
    }
    try { Write-SharedState $windows } catch { }
    $live = Get-LiveOrchestrators
    $peers = if ($live.Count) { " | orchestrators running: $(($live | ForEach-Object { Format-Peer $_ }) -join ', ')" } else { '' }
    Emit "USAGE $(Format-StatusLine $windows)$peers"
    if (($windows | Measure-Object Percent -Maximum).Maximum -ge $HandoffTier) { exit 1 } else { exit 0 }
}

# ---- watch loop -----------------------------------------------------------
# Per-window memory for THIS watcher: the highest tier already announced and
# the reset time it belongs to. Deliberately in-memory: every orchestrator
# runs its own watcher and must hear its own notifications, including tiers
# already crossed before it started.
$announced = @{}
$resumed = $false
if (Test-Path $MyRegPath) {
    $existing = $null
    try { $existing = Get-Content $MyRegPath -Raw | ConvertFrom-Json } catch { }
    if ($existing) {
        $age = (Get-Date).ToUniversalTime() - ([datetime]$existing.heartbeatUtc).ToUniversalTime()
        $proc = Get-Process -Id $existing.pid -ErrorAction SilentlyContinue
        if ($age -le $StaleAfter -and $existing.pid -ne $PID -and $proc -and $proc.ProcessName -match 'powershell|pwsh') {
            Emit "USAGE-ERROR another live watcher (pid $($existing.pid)) is already registered as '$Name'. Pick a unique -Name for this orchestrator."
            exit 3
        }
        # Same orchestrator re-arming its watcher (a Monitor watch expires after
        # 30 minutes): keep its start time and what it already announced.
        if ($age -le [timespan]::FromHours(6)) {
            try {
                $MyStarted = ([datetime]$existing.startedAtUtc).ToUniversalTime()
                foreach ($a in @($existing.announced)) {
                    if (-not $a.window) { continue }
                    $announced[[string]$a.window] = [pscustomobject]@{
                        Tier       = [int]$a.tier
                        ResetsAt   = $(if ($a.resetsAt) { [datetimeoffset]::Parse($a.resetsAt, [Globalization.CultureInfo]::InvariantCulture) })
                        HandoffDir = [string]$a.handoffDir
                        Expected   = @($a.expected | Where-Object { $_ })
                    }
                }
                $resumed = $true
            } catch { $announced = @{} }
        }
    }
}

$knownPeers = @{}
$lastAggregator = $null
$seenHandoffs = @{}
$errorStreak = 0
$errorAlerted = $false
$first = $true

try {
    while ($true) {
        try { Write-Heartbeat } catch { }
        $live = Get-LiveOrchestrators
        $peers = @($live | Where-Object Name -ne $Name)
        $aggregator = if ($live.Count) { $live[0].Name } else { $Name }
        $iAmAggregator = ($aggregator -eq $Name)

        # Peer joins / departures (not reported on the first poll; START covers it).
        $currentNames = @{}
        foreach ($p in $peers) { $currentNames[$p.Name] = $p }
        if (-not $first) {
            foreach ($n in @($currentNames.Keys)) {
                if (-not $knownPeers.ContainsKey($n)) {
                    Emit "USAGE PEER started: $(Format-Peer $currentNames[$n]). $($peers.Count + 1) orchestrators now share this account's limit; each lane you dispatch costs them too."
                }
            }
            foreach ($n in @($knownPeers.Keys)) {
                if (-not $currentNames.ContainsKey($n)) { Emit "USAGE PEER gone: $n stopped heartbeating. $($peers.Count + 1) orchestrator(s) remain." }
            }
            if ($lastAggregator -and $aggregator -ne $lastAggregator -and $peers.Count -gt 0) {
                $who = if ($iAmAggregator) { 'YOU are now the aggregator' } else { "the aggregator is now $aggregator" }
                $takeover = ''
                if ($iAmAggregator) {
                    # Taking over mid-window: adopt the open handoff and re-point
                    # the expected list at the orchestrators still live.
                    foreach ($k in @($announced.Keys)) {
                        $st = $announced[$k]
                        $st.Expected = @($peers | ForEach-Object Name)
                        $takeover += " Take over $($st.HandoffDir): read what $lastAggregator left there (AGGREGATE.md, if any, and every <name>.md), fold in your own state, and monitor usage for everyone. Expecting handoffs from: $(if ($st.Expected.Count) { $st.Expected -join ', ' } else { 'nobody else' })."
                    }
                }
                Emit "USAGE AGGREGATOR changed: $lastAggregator is no longer live, $who. Any handoff meant for $lastAggregator goes to $aggregator.$takeover"
            }
        }
        $knownPeers = $currentNames
        $lastAggregator = $aggregator

        $windows = $null
        try {
            $json = Get-UsageJson
            $windows = @('five_hour', 'seven_day' | ForEach-Object { Read-Window $json $_ } | Where-Object { $_ })
            if ($windows.Count -eq 0) { throw 'endpoint returned neither five_hour nor seven_day' }
        } catch {
            $errorStreak++
            if ($errorStreak -ge $ErrorPollsBeforeAlert -and -not $errorAlerted) {
                Emit "USAGE-ERROR $errorStreak polls failed ($($_.Exception.Message)). Usage is UNKNOWN: treat it as high, check /usage manually, and do not start new lanes until data returns."
                $errorAlerted = $true
            }
            $first = $false
            Start-Sleep -Seconds $IntervalSeconds
            continue
        }

        if ($errorAlerted) { Emit "USAGE-OK data flowing again: $(Format-StatusLine $windows)" }
        $errorStreak = 0
        $errorAlerted = $false
        try { Write-SharedState $windows } catch { }

        if ($first) {
            $peerText = if ($peers.Count) {
                " WARNING: $($peers.Count) other orchestrator(s) share this limit: $(($peers | ForEach-Object { Format-Peer $_ }) -join ', '). Aggregator from $HandoffTier% on: $aggregator$(if ($iAmAggregator) { ' (you)' })."
            } else { ' No other orchestrators running.' }
            $resumeText = if ($resumed -and $announced.Count) { " Resumed after a restart; already announced: $(($announced.Keys | ForEach-Object { "$($Labels[$_]) $($announced[$_].Tier)%" }) -join ', ')." } elseif ($resumed) { ' Resumed after a restart.' } else { '' }
            Emit "USAGE START $Name watching $(Format-StatusLine $windows). Tiers: $($Thresholds -join ', ')%.$peerText$resumeText"
        }

        foreach ($w in $windows) {
            $prev = $announced[$w.Key]
            $handoffDir = Get-HandoffDir $w

            # Window renewed: a later reset time and usage back under the tier we
            # last announced. The margin absorbs fractional-second jitter.
            if ($prev -and $w.ResetsAt -and $prev.ResetsAt -and $w.ResetsAt -gt $prev.ResetsAt.AddMinutes(1) -and $w.Percent -lt $prev.Tier) {
                $resume = if ($prev.HandoffDir -and (Test-Path $prev.HandoffDir)) { " Handoffs from the last window: $($prev.HandoffDir)." } else { '' }
                Emit ("USAGE RESET {0} window renewed: now {1}%, next reset {2}. Resume from the handoff plan.{3}" -f $Labels[$w.Key], [math]::Round($w.Percent), (Format-LocalTime $w.ResetsAt), $resume)
                $announced.Remove($w.Key)
                $prev = $null
            }

            # Aggregator: report each peer handoff file as it lands.
            if ($iAmAggregator -and $prev -and $peers.Count -and (Test-Path $handoffDir)) {
                foreach ($f in @(Get-ChildItem $handoffDir -Filter '*.md' -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -ne $Name -and $_.BaseName -ne 'AGGREGATE' })) {
                    if (-not $seenHandoffs.ContainsKey($f.FullName)) {
                        $seenHandoffs[$f.FullName] = $true
                        $got = @($seenHandoffs.Keys | Where-Object { $_ -like "$handoffDir*" }).Count
                        Emit "USAGE HANDOFF received from $($f.BaseName) ($got of $($prev.Expected.Count)): $($f.FullName). Fold it into AGGREGATE.md."
                    }
                }
            }

            $crossed = @($Thresholds | Where-Object { $w.Percent -ge $_ })
            if ($crossed.Count -eq 0) { continue }
            $top = $crossed[-1]
            if ($prev -and $prev.Tier -ge $top) { continue }

            $skipped = @($crossed | Where-Object { $_ -lt $top -and (-not $prev -or $_ -gt $prev.Tier) })
            $note = if ($skipped.Count) { " (Also passed $($skipped -join ', ')% since the last reading; do those steps too.)" } else { '' }
            $scope = if ($w.Key -eq 'seven_day') { ' WEEKLY: the reset is days away, not hours; plan against it.' } else { '' }
            $head = "USAGE TIER $top $($Labels[$w.Key]) window at $([math]::Round($w.Percent))%, resets $(Format-LocalTime $w.ResetsAt).$scope"
            $expected = if ($prev -and $prev.Expected) { $prev.Expected } else { @($peers | ForEach-Object Name) }

            if ($peers.Count -eq 0 -and $expected.Count -eq 0) {
                $action = $Actions[$top]
            } elseif ($iAmAggregator) {
                $action = "YOU ARE THE AGGREGATOR for $($expected.Count) other orchestrator(s): $($expected -join ', '). They are handing off to $handoffDir\<name>.md; write the combined state and next-window plan to $handoffDir\AGGREGATE.md and monitor usage for everyone from here. $($Actions[$top])"
                if ($top -gt $HandoffTier) {
                    $missing = @($expected | Where-Object { -not (Test-Path (Join-Path $handoffDir "$_.md")) })
                    if ($missing.Count) { $action += " STILL MISSING handoffs from: $($missing -join ', '). Message them (ListAgents, then SendMessage) or reconstruct their state from their PRs and branches." }
                    else { $action += ' All handoffs received.' }
                }
            } else {
                if ($top -eq $HandoffTier -or -not $prev) {
                    $action = "HAND OFF NOW. $($peers.Count + 1) orchestrators share this limit and $aggregator is the aggregator. Immediately: send the pause order to your lanes, write $handoffDir\$Name.md (every lane and its state, open PRs and branches, what is mid-flight, the next step for each, owner blockers), then stop dispatching and leave the rest of the window to $aggregator."
                } else {
                    $action = "You should already have handed off to $aggregator. If $handoffDir\$Name.md is not written, write it now and stop; do no further work this window."
                }
            }
            Emit "$head $action$note"
            $announced[$w.Key] = [pscustomobject]@{ Tier = $top; ResetsAt = $w.ResetsAt; HandoffDir = $handoffDir; Expected = $expected }
        }

        $first = $false
        $worstPct = ($windows | Measure-Object Percent -Maximum).Maximum
        $sleep = if ($worstPct -ge $FastAbovePercent) { $FastIntervalSeconds } else { $IntervalSeconds }
        Start-Sleep -Seconds $sleep
    }
} finally {
    # Runs on Ctrl+C / normal exit. A hard kill skips it, which the heartbeat
    # staleness rule covers.
    Remove-Item $MyRegPath -Force -ErrorAction SilentlyContinue
}
