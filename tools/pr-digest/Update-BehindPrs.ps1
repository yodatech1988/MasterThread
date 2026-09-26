<#
.SYNOPSIS
    Updates the branch on open PRs that are BEHIND their base AND already automerge-eligible,
    and reports (never resolves) any real merge conflict. Read-only unless -Execute is passed.

.DESCRIPTION
    PC-local half of Decision Queue card cost-monitor-behind-pr-updater-writes-2026-09-26
    (option 0). Uses whatever `gh auth status` already provides locally -- no new token.

    "Automerge-eligible" here means the SAME gates
    core/.github/workflows/claude-review.yml's own `automerge` job checks before it would merge a
    PR itself (read there before changing this, so the two never drift):
      1. Repo is not in owner_only_repos (config.json; personal/financial repos are excluded
         entirely, regardless of what any single PR looks like -- aegis-automerge-policy).
      2. The PR carries no `owner-review` or `do-not-merge` label.
      3. The most recent review from `github-actions[bot]` on the PR's CURRENT head commit is
         `APPROVED` and its body matches `AUTOMERGE: eligible` (case-insensitive) -- the same
         verdict line claude-review.yml's review job posts and its own automerge job parses.
    This script does NOT re-check size limits, sensitive words or fork/author trust -- those were
    already Claude's job when it posted the AUTOMERGE: eligible verdict on this commit. Updating a
    branch is also a strictly safer action than merging: GitHub's update-branch endpoint only
    merges the base INTO the PR branch (or rebases it), it can never land the PR's own content
    anywhere, and a would-be conflict there simply refuses the update (422) instead of touching
    anything.

    Only PRs with `mergeStateStatus == BEHIND` are candidates. On a real merge conflict (HTTP 422
    from the update-branch call), this reports it as a finding and takes no further action --
    conflict resolution is explicitly out of scope (owner decision, card option 0).

.PARAMETER ConfigPath
    Path to config.json (repos list, owner_only_repos). Default: config.json next to this script.

.PARAMETER Repos
    Optional override for the repo list (owner/repo; bare name assumes yodatech1988).

.PARAMETER Execute
    Actually call the update-branch API. Without this switch the script ALWAYS runs as a dry run
    and prints exactly what it would have called -- this is the default and is the only mode this
    change has been tested against a real PR in. Per the task that produced this script, no run
    against a real PR has been made with -Execute; that verification is left to whoever reviews
    and adopts this script for real use.

.OUTPUTS
    One JSON object to stdout: { candidates, updated, conflicts, skipped, couldNotCheck }.
    `updated` is only ever non-empty when -Execute was passed.
    Exit 0 on a completed pass (individual repo/PR read failures land in couldNotCheck, not a
    non-zero exit). Exit 1 if config or `gh` itself is unusable.
#>
[CmdletBinding()]
param(
    [string]   $ConfigPath = (Join-Path $PSScriptRoot 'config.json'),
    [string[]] $Repos,
    [switch]   $Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PropOrDefault {
    param($Obj, [string]$Name, $Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj.PSObject.Properties.Name -contains $Name) { return $Obj.$Name }
    return $Default
}

function Invoke-Gh {
    param([string[]]$GhArgs)
    $out = & gh @GhArgs 2>&1
    $code = $LASTEXITCODE
    return @{ Output = ($out -join "`n"); ExitCode = $code }
}

# `@(<pipeline> | ConvertFrom-Json)` is unsafe on this PS 5.1 setup: when the pipeline already
# yields a JSON array as ONE pipeline object, wrapping it in @() nests it (Count=1, containing the
# real array) instead of flattening it (verified empirically 2026-09-26, matches the class of bug
# in the "PS 5.1 @($list) yields empty" memory). Always go through this helper.
function ConvertFrom-JsonArray {
    param([string]$Json)
    if ([string]::IsNullOrWhiteSpace($Json)) { return @() }
    $parsed = $Json | ConvertFrom-Json
    if ($null -eq $parsed) { return @() }
    if ($parsed -is [System.Array]) { return $parsed }
    return ,$parsed
}

function Resolve-Repo {
    param([string]$Name)
    if ($Name -match '/') { return $Name }
    return "yodatech1988/$Name"
}

$ghCheck = Invoke-Gh -GhArgs @('auth', 'status')
if ($ghCheck.ExitCode -ne 0) {
    Write-Error "gh is not available or not authenticated: $($ghCheck.Output)"
    exit 1
}

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
$ownerOnly = @(Get-PropOrDefault $config 'owner_only_repos' @() | ForEach-Object { $_.ToString().ToLowerInvariant() })

$candidates    = New-Object System.Collections.Generic.List[object]
$updated       = New-Object System.Collections.Generic.List[object]
$conflicts     = New-Object System.Collections.Generic.List[object]
$skipped       = New-Object System.Collections.Generic.List[object]
$couldNotCheck = New-Object System.Collections.Generic.List[object]

foreach ($repo in $repoList) {
    $repoName = ($repo -split '/')[-1].ToLowerInvariant()
    if ($ownerOnly -contains $repoName) {
        $skipped.Add([pscustomobject]@{ repo = $repo; reason = 'repo is in owner_only_repos (personal/financial) -- never touched' })
        continue
    }

    $listRes = Invoke-Gh -GhArgs @('pr', 'list', '-R', $repo, '--state', 'open', '--json', 'number,title,headRefName,mergeStateStatus,labels')
    if ($listRes.ExitCode -ne 0) {
        $couldNotCheck.Add([pscustomobject]@{ subject = $repo; reason = "gh pr list failed: $($listRes.Output)" })
        continue
    }
    try { $prs = ConvertFrom-JsonArray $listRes.Output } catch {
        $couldNotCheck.Add([pscustomobject]@{ subject = $repo; reason = "gh pr list returned unparseable JSON: $($_.Exception.Message)" })
        continue
    }

    foreach ($pr in $prs) {
        $number = $pr.number
        $mss    = Get-PropOrDefault $pr 'mergeStateStatus' 'UNKNOWN'
        if ($mss -ne 'BEHIND') { continue }

        $subject = "$repo#$number"
        $labels = @(Get-PropOrDefault $pr 'labels' @() | ForEach-Object { (Get-PropOrDefault $_ 'name' '').ToLowerInvariant() })
        if (($labels -contains 'owner-review') -or ($labels -contains 'do-not-merge')) {
            $skipped.Add([pscustomobject]@{ repo = $repo; number = $number; reason = "labelled $(($labels | Where-Object {$_ -in @('owner-review','do-not-merge')}) -join ', ')" })
            continue
        }

        $viewRes = Invoke-Gh -GhArgs @('pr', 'view', $number, '-R', $repo, '--json', 'headRefOid')
        if ($viewRes.ExitCode -ne 0) {
            $couldNotCheck.Add([pscustomobject]@{ subject = $subject; reason = "gh pr view failed: $($viewRes.Output)" })
            continue
        }
        try { $headSha = ($viewRes.Output | ConvertFrom-Json).headRefOid } catch {
            $couldNotCheck.Add([pscustomobject]@{ subject = $subject; reason = "gh pr view returned unparseable JSON: $($_.Exception.Message)" })
            continue
        }

        $reviewsRes = Invoke-Gh -GhArgs @('api', "repos/$repo/pulls/$number/reviews", '--paginate')
        if ($reviewsRes.ExitCode -ne 0) {
            $couldNotCheck.Add([pscustomobject]@{ subject = $subject; reason = "gh api reviews failed: $($reviewsRes.Output)" })
            continue
        }
        try { $reviews = ConvertFrom-JsonArray $reviewsRes.Output } catch {
            $couldNotCheck.Add([pscustomobject]@{ subject = $subject; reason = "reviews response unparseable: $($_.Exception.Message)" })
            continue
        }

        $verdictReview = $reviews | Where-Object {
            (Get-PropOrDefault $_ 'commit_id' '') -eq $headSha -and
            (Get-PropOrDefault (Get-PropOrDefault $_ 'user' $null) 'login' '') -eq 'github-actions[bot]'
        } | Select-Object -Last 1

        if ($null -eq $verdictReview) {
            $skipped.Add([pscustomobject]@{ repo = $repo; number = $number; reason = "no github-actions[bot] review found on head commit $($headSha.Substring(0,7))" })
            continue
        }
        $state = Get-PropOrDefault $verdictReview 'state' 'none'
        $body  = (Get-PropOrDefault $verdictReview 'body' '') -replace '[\r\*_`]', ''
        if ($state -ne 'APPROVED') {
            $skipped.Add([pscustomobject]@{ repo = $repo; number = $number; reason = "latest bot review on this commit is $state, not APPROVED" })
            continue
        }
        if ($body -notmatch '(?im)^\s*AUTOMERGE:\s*eligible\b') {
            $skipped.Add([pscustomobject]@{ repo = $repo; number = $number; reason = 'bot review does not carry AUTOMERGE: eligible on this commit' })
            continue
        }

        $candidates.Add([pscustomobject]@{ repo = $repo; number = $number; title = $pr.title; headSha = $headSha })

        if (-not $Execute) {
            Write-Output "[DRY RUN] would call: gh api -X PUT repos/$repo/pulls/$number/update-branch (expected_head_sha=$headSha)"
            continue
        }

        $updateRes = Invoke-Gh -GhArgs @('api', '-X', 'PUT', "repos/$repo/pulls/$number/update-branch", '-f', "expected_head_sha=$headSha")
        if ($updateRes.ExitCode -eq 0) {
            $updated.Add([pscustomobject]@{ repo = $repo; number = $number; headSha = $headSha })
        } elseif ($updateRes.Output -match '422') {
            $conflicts.Add([pscustomobject]@{ repo = $repo; number = $number; detail = $updateRes.Output })
        } else {
            $couldNotCheck.Add([pscustomobject]@{ subject = $subject; reason = "update-branch call failed: $($updateRes.Output)" })
        }
    }
}

$result = [pscustomobject]@{
    dryRun        = -not $Execute
    candidates    = $candidates.ToArray()
    updated       = $updated.ToArray()
    conflicts     = $conflicts.ToArray()
    skipped       = $skipped.ToArray()
    couldNotCheck = $couldNotCheck.ToArray()
}
$result | ConvertTo-Json -Depth 10
exit 0
