<#
.SYNOPSIS
    Diffs the live session roster against the previous check and reports ONLY what changed.

.DESCRIPTION
    The PM's recurring "who is actually working" check. A session cannot poll ListAgents from a
    script -- it is a tool, not a command -- so the PM calls ListAgents itself each tick and pipes
    the raw listing in here. This script owns the part that must be deterministic: parsing the
    roster, comparing it to the last snapshot, and deciding whether anything worth a report
    actually changed.

    Deliberately NOT treated as changes (they change on nearly every tick and would drown the
    signal the PM needs):
      * "started 1h ago" -- a relative timestamp, different text every check.
      * a single busy <-> idle flip -- a session between tool calls reads as idle.

    Treated as changes:
      * JOINED     -- a session in this listing that was not in the last one.
      * DEPARTED   -- a session in the last listing that is gone from this one.
      * IDLE       -- idle for -IdleTicks consecutive checks (default 2). Reported once per idle
                      spell, not every tick, and re-armed when the session goes busy again.
      * UNREGISTERED / GHOST -- only when -RegisteredIds is supplied: live sessions with no Fleet
                      Status row, and non-wound-down rows whose session is gone. Reported when the
                      set changes, not every tick.

.PARAMETER RosterText
    The raw ListAgents output. Pass it verbatim; the parser tolerates the self line and the
    "Peer sessions (n):" header.

.PARAMETER Name
    Watcher name -- picks the snapshot file, so two PMs never share state. Default "pm".

.PARAMETER RegisteredIds
    Optional. Session ids that currently have a non-wound-down Fleet Status `sessions` row.
    Supplying it enables the registration cross-check.

.PARAMETER IdleTicks
    Consecutive idle checks before a session is reported idle. Default 2.

.PARAMETER Reset
    Write the snapshot and report nothing. Use once when arming the watcher, so the first real
    tick does not report the entire existing fleet as newly joined.

.PARAMETER StateDir
    Snapshot directory. Default %APPDATA%\AEGIS.

.OUTPUTS
    "FLEET-ROSTER NO CHANGE (n live)" when nothing changed -- the PM stays silent on this.
    "FLEET-ROSTER CHANGED" plus one line per change otherwise.
    "FLEET-ROSTER ERROR ..." when the listing could not be parsed -- never silently reports
    "no change" on unreadable input, because that is indistinguishable from a healthy quiet fleet.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [AllowEmptyString()]
    [string] $RosterText,

    [string]   $Name = 'pm',
    [string[]] $RegisteredIds,
    [int]      $IdleTicks = 2,
    [switch]   $Reset,
    [string]   $StateDir = (Join-Path $env:APPDATA 'AEGIS')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-Roster {
    param([string] $Text)

    $found = @{}
    # name [4+ hex ref], then whatever the listing puts after it. Tolerates the interpunct
    # separator surviving or not surviving the encoding round-trip.
    $rowRe  = '^\s*(?<name>[A-Za-z0-9][A-Za-z0-9._-]*)\s+\[(?<ref>[0-9a-fA-F]{4,})\]\s*(?<rest>.*)$'
    $selfRe = 'This session is\s+(?<name>[A-Za-z0-9][A-Za-z0-9._-]*)\s+\[(?<ref>[0-9a-fA-F]{4,})\]'

    foreach ($line in ($Text -split "`r?`n")) {
        $isSelf = $false
        $rest   = ''
        $m = [regex]::Match($line, $selfRe)
        if ($m.Success) {
            $isSelf = $true
        } else {
            $m = [regex]::Match($line, $rowRe)
            if (-not $m.Success) { continue }
            $rest = $m.Groups['rest'].Value
        }

        $state = 'unknown'
        if     ($isSelf)             { $state = 'self' }
        elseif ($rest -match 'busy') { $state = 'busy' }
        elseif ($rest -match 'idle') { $state = 'idle' }

        $mode = 'unknown'
        if     ($rest -match 'interactive') { $mode = 'interactive' }
        elseif ($rest -match 'headless')    { $mode = 'headless' }
        elseif ($rest -match 'cloud')       { $mode = 'cloud' }

        # A name can reappear under a new ref after a rotation; key on name but keep the ref, so
        # a same-name-new-ref swap still reads as a change rather than as continuity.
        $key = $m.Groups['name'].Value
        $found[$key] = [ordered]@{
            session = $key
            ref     = $m.Groups['ref'].Value
            state   = $state
            mode    = $mode
        }
    }
    return $found
}

function Read-Snapshot {
    param([string] $Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        $raw = Get-Content -Path $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch {
        # A corrupt snapshot must not wedge the watcher; treat it as a cold start.
        Write-Verbose ("unreadable snapshot at {0}: {1}" -f $Path, $_.Exception.Message)
        return $null
    }
}

$now      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$live     = Read-Roster -Text $RosterText
$liveKeys = @($live.Keys)

if ($liveKeys.Count -eq 0) {
    # Zero parsed rows is never a legitimate reading: the calling session is itself always in the
    # listing. Far more likely the listing was truncated, reworded, or never passed at all.
    Write-Output "FLEET-ROSTER ERROR no sessions parsed from the supplied listing -- roster not compared, snapshot unchanged."
    exit 2
}

if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
$snapPath = Join-Path $StateDir ("fleet-roster.{0}.json" -f $Name)
$prev     = Read-Snapshot -Path $snapPath

# ---- carry per-session bookkeeping forward -------------------------------------------------
$prevById = @{}
if ($null -ne $prev -and $prev.PSObject.Properties.Name -contains 'sessions') {
    foreach ($s in @($prev.sessions)) { if ($null -ne $s) { $prevById[$s.session] = $s } }
}

$records = @()
foreach ($k in ($liveKeys | Sort-Object)) {
    $cur          = $live[$k]
    $idleCount    = 0
    $idleReported = $false
    $firstSeen    = $now

    if ($prevById.ContainsKey($k) -and $prevById[$k].ref -eq $cur.ref) {
        $p         = $prevById[$k]
        $firstSeen = $p.firstSeen
        if ($cur.state -eq 'idle') {
            $idleCount    = [int]$p.idleCount + 1
            $idleReported = [bool]$p.idleReported
        } else {
            # Went busy again -- re-arm, so the next idle spell reports afresh.
            $idleCount    = 0
            $idleReported = $false
        }
    } elseif ($cur.state -eq 'idle') {
        $idleCount = 1
    }

    $records += [ordered]@{
        session      = $cur.session
        ref          = $cur.ref
        state        = $cur.state
        mode         = $cur.mode
        firstSeen    = $firstSeen
        lastSeen     = $now
        idleCount    = $idleCount
        idleReported = $idleReported
    }
}

# ---- diff ----------------------------------------------------------------------------------
$lines = @()

if ($null -eq $prev) {
    if (-not $Reset) {
        $lines += ("BASELINE established -- {0} live: {1}" -f $records.Count, (($records | ForEach-Object { $_.session }) -join ', '))
        $lines += "(no previous snapshot to compare against; later checks report changes only)"
    }
} else {
    foreach ($r in $records) {
        $wasThere = $prevById.ContainsKey($r.session) -and $prevById[$r.session].ref -eq $r.ref
        if (-not $wasThere) {
            $note = ''
            if ($prevById.ContainsKey($r.session)) { $note = ' (same name, NEW ref -- rotated session)' }
            $lines += ("JOINED    {0} [{1}] {2} {3}{4}" -f $r.session, $r.ref, $r.mode, $r.state, $note)
        }
    }

    foreach ($k in ($prevById.Keys | Sort-Object)) {
        if (-not $live.ContainsKey($k)) {
            $lines += ("DEPARTED  {0} [{1}] -- last seen {2}, first seen {3}" -f $k, $prevById[$k].ref, $prevById[$k].state, $prevById[$k].firstSeen)
        }
    }

    foreach ($r in $records) {
        if ($r.state -eq 'idle' -and $r.idleCount -ge $IdleTicks -and -not $r.idleReported) {
            $lines += ("IDLE      {0} [{1}] -- idle for {2} consecutive checks; needs a lane or a wind-down" -f $r.session, $r.ref, $r.idleCount)
            $r.idleReported = $true
        }
    }
}

# ---- Fleet Status registration cross-check -------------------------------------------------
$anomalies = @()
if ($PSBoundParameters.ContainsKey('RegisteredIds')) {
    $reg = @{}
    foreach ($id in @($RegisteredIds)) {
        if (-not [string]::IsNullOrWhiteSpace($id)) { $reg[$id.Trim()] = $true }
    }

    foreach ($r in $records) {
        if ($r.state -eq 'self') { continue }
        if (-not $reg.ContainsKey($r.session)) {
            $anomalies += ("UNREGISTERED {0} -- live with no Fleet Status row" -f $r.session)
        }
    }
    foreach ($id in ($reg.Keys | Sort-Object)) {
        if (-not $live.ContainsKey($id)) {
            $anomalies += ("GHOST ROW    {0} -- Fleet Status row is live/not-wound-down, session is gone" -f $id)
        }
    }

    $prevAnomalies = @()
    if ($null -ne $prev -and $prev.PSObject.Properties.Name -contains 'anomalies') {
        $prevAnomalies = @($prev.anomalies)
    }
    # Only surface the registration mismatch when the SET changes, so a known-stale row is not
    # re-reported every five minutes.
    $delta = @(Compare-Object -ReferenceObject @($prevAnomalies) -DifferenceObject @($anomalies))
    if ($delta.Count -gt 0 -and $anomalies.Count -gt 0) { $lines += $anomalies }
}

# ---- persist -------------------------------------------------------------------------------
$snapshot = [ordered]@{
    name      = $Name
    updatedAt = $now
    sessions  = $records
    anomalies = $anomalies
}
$snapshot | ConvertTo-Json -Depth 6 | Out-File -FilePath $snapPath -Encoding utf8

# ---- report --------------------------------------------------------------------------------
$names = ($records | ForEach-Object { $_.session }) -join ', '

if ($Reset) {
    Write-Output ("FLEET-ROSTER BASELINE written -- {0} live: {1}" -f $records.Count, $names)
    exit 0
}

if ($lines.Count -eq 0) {
    Write-Output ("FLEET-ROSTER NO CHANGE ({0} live)" -f $records.Count)
    exit 0
}

Write-Output "FLEET-ROSTER CHANGED"
$lines | ForEach-Object { Write-Output ("  " + $_) }
Write-Output ("  -- now {0} live: {1}" -f $records.Count, $names)
exit 1
