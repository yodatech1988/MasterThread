<#
.SYNOPSIS
    Sweeps open PRs and CI state across a configurable list of repos via `gh`, writes a
    pr-digest.json snapshot, and appends one line per state transition to a change log a
    `Monitor tail -F` can watch.

.DESCRIPTION
    PC-local, read-only half of the cost-monitor PR/CI digest (Decision Queue card
    cost-monitor-pr-digest-vps-federated-2026-09-26, option 0; see
    PM_INBOX\cost-monitor\SELF_IMPROVEMENT_PLAN_2026-09-26.md section R3). Uses whatever `gh auth
    status` already provides on this machine -- no new token, no VPS, no federated credential. The
    VPS deployment named in that card is a separate, owner-gated follow-up; this script never
    attempts any VPS or credential work.

    For each open PR in each configured repo, records state, draft, mergeStateStatus, checks
    rollup, head sha and age, then applies the SAME flag rules `claude-agents\pr-state-sweep.md`
    already defines (read there before changing these, so the two stay in lockstep):
      * stuck    -- checks pending/in_progress on the same run for longer than `stuck_hours`
                    (default 2) by createdAt, OR statusCheckRollup includes FAILURE/ERROR, OR no
                    run at all exists for the head branch.
      * ciFailure     -- statusCheckRollup includes FAILURE/ERROR (subset of stuck, called out on
                    its own per this task's "CI FAILURE" flag).
      * noCiRun       -- no run at all for the head branch.
      * rule4Violation -- more than one open `agent/`-prefixed PR in the same repo
                    (session_plan_standard.md rule 4).

    Change log: compares this run's (state, isDraft, mergeStateStatus, headRefOid) tuple per PR
    against the previous run's snapshot (kept in -StateDir) and appends WATCHING/CHANGED lines,
    the same shape `tools\owner-wait-watch.sh` already uses for the same purpose. A key with no
    prior value is "now watching", not a change, so the first run does not read as N transitions.

    Per tools\README.md conventions: -StateDir is the mandatory test seam (never hardcode
    %APPDATA%\AEGIS), no desktop popups ever, timestamps come from the clock, and PSObject.Properties
    checks guard every parsed-JSON field read under Set-StrictMode.

.PARAMETER ConfigPath
    Path to config.json (repos list, stuck_hours). Default: config.json next to this script.

.PARAMETER Repos
    Optional override for the repo list in ConfigPath (owner/repo; bare name assumes yodatech1988).

.PARAMETER StateDir
    Where pr-digest.json, the previous-snapshot file and the change log live. Default
    %APPDATA%\AEGIS\pr-digest. Tests MUST pass a throwaway directory here -- never the default.

.PARAMETER Once
    Run a single pass and exit (the default). Without a scheduler this is the only mode that runs
    unattended right now; -IntervalSeconds is kept for a future `Monitor` loop, not wired to any
    scheduled task or cron by this change.

.PARAMETER IntervalSeconds
    Loop interval when -Once is not passed. Default 600 (10 minutes, per the R3 plan). Only takes
    effect with -Loop.

.PARAMETER Loop
    Run repeatedly every -IntervalSeconds instead of a single pass. Still nothing registers this
    anywhere; it only affects this process's own lifetime.

.PARAMETER Reset
    Write the snapshot and report no transitions. Use once when arming a fresh -StateDir so the
    first real pass does not read every existing open PR as a brand-new transition.

.OUTPUTS
    <StateDir>\pr-digest.json           -- full current snapshot (schema below).
    <StateDir>\pr-digest-changelog.log  -- append-only, one line per transition, ISO-8601 UTC
                                            timestamp first column.
    Exit 0  -- ran to completion (individual repos/PRs that could not be read are still recorded
               under couldNotCheck in the JSON; that is not a script failure).
    Exit 1  -- config could not be read/parsed, or `gh` itself is not available/authenticated.
#>
[CmdletBinding()]
param(
    [string]   $ConfigPath = (Join-Path $PSScriptRoot 'config.json'),
    [string[]] $Repos,
    [string]   $StateDir = (Join-Path $env:APPDATA 'AEGIS\pr-digest'),
    [switch]   $Once,
    [int]      $IntervalSeconds = 600,
    [switch]   $Loop,
    [switch]   $Reset
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PropOrDefault {
    param($Obj, [string]$Name, $Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj.PSObject.Properties.Name -contains $Name) { return $Obj.$Name }
    return $Default
}

function Write-Log {
    param([string]$Path, [string]$Line)
    $ts = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    Add-Content -LiteralPath $Path -Value "$ts  $Line" -Encoding utf8
}

function Invoke-Gh {
    param([string[]]$GhArgs)
    $out = & gh @GhArgs 2>&1
    $code = $LASTEXITCODE
    return @{ Output = ($out -join "`n"); ExitCode = $code }
}

# `@(<pipeline> | ConvertFrom-Json)` is unsafe on this PS 5.1 setup: when the pipeline already
# yields a JSON array as ONE pipeline object, wrapping it in @() nests it (Count=1, containing the
# real array), instead of flattening it (verified empirically 2026-09-26, matches the class of bug
# in the "PS 5.1 @($list) yields empty" memory). Always go through this helper instead of piping
# straight into `@(... | ConvertFrom-Json)`.
function ConvertFrom-JsonArray {
    param([string]$Json)
    if ([string]::IsNullOrWhiteSpace($Json)) { return @() }
    $parsed = $Json | ConvertFrom-Json
    if ($null -eq $parsed) { return @() }
    if ($parsed -is [System.Array]) { return $parsed }
    return ,$parsed
}

function Get-AgeString {
    param([string]$CreatedAt)
    try {
        $created = [DateTime]::Parse($CreatedAt, [System.Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()
    } catch {
        return 'unknown'
    }
    $span = [DateTime]::UtcNow - $created
    if ($span.TotalDays -ge 1) { return "{0:N0}d" -f $span.TotalDays }
    if ($span.TotalHours -ge 1) { return "{0:N0}h" -f $span.TotalHours }
    return "{0:N0}m" -f $span.TotalMinutes
}

function Resolve-Repo {
    param([string]$Name)
    if ($Name -match '/') { return $Name }
    return "yodatech1988/$Name"
}

# --- gh availability -------------------------------------------------------
$ghCheck = Invoke-Gh -GhArgs @('auth', 'status')
if ($ghCheck.ExitCode -ne 0) {
    Write-Error "gh is not available or not authenticated: $($ghCheck.Output)"
    exit 1
}

# --- config -----------------------------------------------------------------
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Error "Config not found: $ConfigPath"
    exit 1
}
try {
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
} catch {
    Write-Error "Config at $ConfigPath is not valid JSON: $($_.Exception.Message)"
    exit 1
}
$repoList = if ($Repos -and $Repos.Count -gt 0) { $Repos } else { Get-PropOrDefault $config 'repos' @() }
$repoList = @($repoList | ForEach-Object { Resolve-Repo $_ })
if ($repoList.Count -eq 0) {
    Write-Error "No repos configured (ConfigPath=$ConfigPath, -Repos not supplied)."
    exit 1
}
$stuckHours = [double](Get-PropOrDefault $config 'stuck_hours' 2)

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
$digestPath    = Join-Path $StateDir 'pr-digest.json'
$snapshotPath  = Join-Path $StateDir 'pr-digest-snapshot.json'
$changelogPath = Join-Path $StateDir 'pr-digest-changelog.log'
if (-not (Test-Path -LiteralPath $changelogPath)) { New-Item -ItemType File -Path $changelogPath | Out-Null }

function Invoke-DigestPass {
    param([string[]]$RepoList, [double]$StuckHours, [string]$SnapshotPath, [string]$ChangelogPath, [bool]$IsReset)

    $prevSnapshot = @{}
    if (Test-Path -LiteralPath $SnapshotPath) {
        try {
            $prevRaw = Get-Content -LiteralPath $SnapshotPath -Raw | ConvertFrom-Json
            if ($null -ne $prevRaw) {
                foreach ($p in $prevRaw.PSObject.Properties) { $prevSnapshot[$p.Name] = $p.Value }
            }
        } catch {
            # Unreadable prior snapshot: treat as no prior state rather than fail the whole pass.
        }
    }

    $reposOut       = New-Object System.Collections.Generic.List[object]
    $findings       = New-Object System.Collections.Generic.List[object]
    $couldNotCheck  = New-Object System.Collections.Generic.List[object]
    $rule4          = New-Object System.Collections.Generic.List[object]
    $noCiRun        = New-Object System.Collections.Generic.List[object]
    $ciFailure      = New-Object System.Collections.Generic.List[object]
    $newSnapshot    = @{}

    foreach ($repo in $RepoList) {
        $listRes = Invoke-Gh -GhArgs @('pr', 'list', '-R', $repo, '--state', 'open', '--json',
            'number,title,headRefName,createdAt,updatedAt,isDraft,mergeStateStatus,headRefOid,statusCheckRollup')
        if ($listRes.ExitCode -ne 0) {
            $couldNotCheck.Add([pscustomobject]@{ subject = $repo; reason = "gh pr list failed: $($listRes.Output)" })
            continue
        }
        try {
            $prs = $listRes.Output | ConvertFrom-Json
        } catch {
            $couldNotCheck.Add([pscustomobject]@{ subject = $repo; reason = "gh pr list returned unparseable JSON: $($_.Exception.Message)" })
            continue
        }
        if ($null -eq $prs) { $prs = @() }

        $agentPrNumbers = New-Object System.Collections.Generic.List[int]
        $prEntries = New-Object System.Collections.Generic.List[object]

        foreach ($pr in $prs) {
            $number  = $pr.number
            $title   = $pr.title
            $branch  = $pr.headRefName
            $created = $pr.createdAt
            $headSha = Get-PropOrDefault $pr 'headRefOid' ''
            $mss     = Get-PropOrDefault $pr 'mergeStateStatus' 'UNKNOWN'
            $draft   = [bool](Get-PropOrDefault $pr 'isDraft' $false)
            $rollup  = Get-PropOrDefault $pr 'statusCheckRollup' @()
            if ($null -eq $rollup) { $rollup = @() }

            if ($branch -like 'agent/*') { $agentPrNumbers.Add($number) }

            # Latest run(s) on the head branch -- matches pr-state-sweep.md step 3.
            $runRes = Invoke-Gh -GhArgs @('run', 'list', '-R', $repo, '-b', $branch, '-L', '3', '--json',
                'status,conclusion,createdAt,name')
            $runs = @()
            $runReadable = $true
            if ($runRes.ExitCode -eq 0) {
                try { $runs = ConvertFrom-JsonArray $runRes.Output } catch { $runReadable = $false }
            } else {
                $runReadable = $false
            }
            if (-not $runReadable) {
                $couldNotCheck.Add([pscustomobject]@{ subject = "$repo#$number"; reason = "gh run list failed: $($runRes.Output)" })
            }

            $hasFailureRollup = @($rollup | Where-Object {
                $conclusion = Get-PropOrDefault $_ 'conclusion' ''
                $conclusion -match '^(FAILURE|ERROR)$'
            }).Count -gt 0

            $noRunAtAll = ($runs.Count -eq 0) -and $runReadable

            $pendingTooLong = $false
            $pendingReason = $null
            foreach ($run in $runs) {
                $status = Get-PropOrDefault $run 'status' ''
                if ($status -in @('pending', 'in_progress', 'queued')) {
                    try {
                        $runCreated = [DateTime]::Parse((Get-PropOrDefault $run 'createdAt' ''), [System.Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()
                        $age = ([DateTime]::UtcNow - $runCreated).TotalHours
                        if ($age -gt $StuckHours) {
                            $pendingTooLong = $true
                            $pendingReason = "run '{0}' {1} for {2:N1}h (limit {3}h)" -f (Get-PropOrDefault $run 'name' 'unknown'), $status, $age, $StuckHours
                        }
                    } catch { }
                }
            }

            $stuck = $false
            $stuckReason = $null
            if ($pendingTooLong) { $stuck = $true; $stuckReason = $pendingReason }
            elseif ($hasFailureRollup) { $stuck = $true; $stuckReason = 'statusCheckRollup includes FAILURE/ERROR' }
            elseif ($noRunAtAll) { $stuck = $true; $stuckReason = 'no CI run exists for this head branch' }

            $checkState = 'missing'
            if ($rollup.Count -eq 0 -and $noRunAtAll) { $checkState = 'missing' }
            elseif ($hasFailureRollup) { $checkState = 'fail' }
            elseif (@($rollup | Where-Object { (Get-PropOrDefault $_ 'status' '') -ne 'COMPLETED' }).Count -gt 0) { $checkState = 'pending' }
            elseif ($rollup.Count -gt 0) { $checkState = 'pass' }

            $entry = [pscustomobject]@{
                number           = $number
                title            = $title
                branch           = $branch
                state            = 'OPEN'
                isDraft          = $draft
                mergeStateStatus = $mss
                checkState       = $checkState
                headSha          = $headSha
                age              = Get-AgeString $created
                stuck            = $stuck
                stuckReason      = $stuckReason
                noCiRun          = $noRunAtAll
                ciFailure        = $hasFailureRollup
            }
            $prEntries.Add($entry)

            if ($noRunAtAll) { $noCiRun.Add([pscustomobject]@{ repo = $repo; number = $number }) }
            if ($hasFailureRollup) { $ciFailure.Add([pscustomobject]@{ repo = $repo; number = $number }) }
            if ($stuck) {
                $findings.Add([pscustomobject]@{ kind = 'stuck'; subject = "$repo#$number"; detail = $stuckReason })
            }

            # Change log: compare (state,isDraft,mergeStateStatus,headSha) against prior snapshot.
            $key = "$repo#$number"
            $nowVal = "OPEN draft=$draft $mss head=$($headSha.Substring(0, [Math]::Min(7,$headSha.Length)))"
            $newSnapshot[$key] = $nowVal
            if (-not $IsReset) {
                if ($prevSnapshot.ContainsKey($key)) {
                    if ($prevSnapshot[$key] -ne $nowVal) {
                        Write-Log -Path $ChangelogPath -Line "CHANGED   $key => $nowVal   (was: $($prevSnapshot[$key]))"
                    }
                } else {
                    Write-Log -Path $ChangelogPath -Line "WATCHING  $key => $nowVal"
                }
            }
        }

        # PRs that closed/merged since last pass no longer appear in `gh pr list --state open`;
        # record their disappearance as a transition too.
        if (-not $IsReset) {
            foreach ($prevKey in $prevSnapshot.Keys) {
                if ($prevKey -like "$repo#*" -and -not $newSnapshot.ContainsKey($prevKey)) {
                    Write-Log -Path $ChangelogPath -Line "CHANGED   $prevKey => CLOSED-OR-MERGED (no longer open)   (was: $($prevSnapshot[$prevKey]))"
                }
            }
        }

        if ($agentPrNumbers.Count -gt 1) {
            $rule4.Add([pscustomobject]@{ repo = $repo; prNumbers = $agentPrNumbers.ToArray() })
            $findings.Add([pscustomobject]@{
                kind    = 'rule-4-violation'
                subject = $repo
                detail  = "more than one open agent/ PR: #$(($agentPrNumbers -join ', #'))"
            })
        }

        $reposOut.Add([pscustomobject]@{ repo = $repo; prs = $prEntries.ToArray() })
    }

    $digest = [pscustomobject]@{
        generatedAt   = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        agent         = 'pr-digest'
        repos         = $reposOut.ToArray()
        flags         = [pscustomobject]@{
            rule4Violations = $rule4.ToArray()
            noCiRun         = $noCiRun.ToArray()
            ciFailure       = $ciFailure.ToArray()
        }
        findings      = $findings.ToArray()
        couldNotCheck = $couldNotCheck.ToArray()
    }

    $digest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $digestPath -Encoding utf8
    $newSnapshot | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $SnapshotPath -Encoding utf8

    return $digest
}

if ($Reset) {
    Invoke-DigestPass -RepoList $repoList -StuckHours $stuckHours -SnapshotPath $snapshotPath -ChangelogPath $changelogPath -IsReset $true | Out-Null
    Write-Output "PR-DIGEST RESET ($($repoList.Count) repos watched, snapshot written, no transitions logged)"
    exit 0
}

if ($Loop -and -not $Once) {
    while ($true) {
        $d = Invoke-DigestPass -RepoList $repoList -StuckHours $stuckHours -SnapshotPath $snapshotPath -ChangelogPath $changelogPath -IsReset $false
        Write-Output "PR-DIGEST pass complete: $($d.findings.Count) findings, $($d.couldNotCheck.Count) unreadable"
        Start-Sleep -Seconds $IntervalSeconds
    }
} else {
    $d = Invoke-DigestPass -RepoList $repoList -StuckHours $stuckHours -SnapshotPath $snapshotPath -ChangelogPath $changelogPath -IsReset $false
    Write-Output "PR-DIGEST pass complete: $($d.findings.Count) findings, $($d.couldNotCheck.Count) unreadable"
    Write-Output "  digest:    $digestPath"
    Write-Output "  changelog: $changelogPath"
    exit 0
}
