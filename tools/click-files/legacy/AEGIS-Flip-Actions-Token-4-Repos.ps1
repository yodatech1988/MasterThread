<#
.SYNOPSIS
  Owner-run. Sets the Actions workflow token to read+write on four org-infra repos.

.DESCRIPTION
  Authorized by Ops Decision Queue card "actions-token-flip-scope-extension-2026-09-17" (owner
  answer: flip only MasterThread, ops-infra, ops-platform, ops-policies). Target shape mirrors the
  repos already flipped (core, aegis-mods, read 2026-09-17):
    default_workflow_permissions = write, can_approve_pull_request_reviews = true

  This is a repo security setting. No Claude session applies it; the script refuses to run unless a
  person started it from a real console and types YES per repo.

  Rollback for one repo:
    gh api -X PUT repos/yodatech1988/<repo>/actions/permissions/workflow -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false

.PARAMETER WhatIf
  Show current and proposed state for every repo, change nothing, ask nothing.
#>
[CmdletBinding()]
param([switch]$WhatIf)

$ErrorActionPreference = 'Stop'
$Owner = 'yodatech1988'
$Repos = @('MasterThread', 'ops-infra', 'ops-platform', 'ops-policies')

if (-not $WhatIf) {
    if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
        Write-Host 'REFUSED: this must be started by the owner from a real console window (double-click the .cmd).' -ForegroundColor Red
        Write-Host 'A Claude session may only run it with -WhatIf.' -ForegroundColor Red
        exit 2
    }
}

& gh auth status *> $null
if ($LASTEXITCODE -ne 0) { Write-Host 'gh is not logged in. Nothing changed.' -ForegroundColor Red; exit 1 }

function Get-Perm($repo) {
    $out = & gh api "repos/$Owner/$repo/actions/permissions/workflow" 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($out | ConvertFrom-Json)
}
function Format-Perm($p) {
    if ($null -eq $p) { return 'COULD NOT READ' }
    return "workflow token: $($p.default_workflow_permissions) | workflows may approve PRs: $($p.can_approve_pull_request_reviews)"
}

$results = @()
foreach ($repo in $Repos) {
    Write-Host ''
    Write-Host "================ $Owner/$repo ================" -ForegroundColor Cyan
    $current = Get-Perm $repo
    Write-Host "Current : $(Format-Perm $current)"
    if ($null -eq $current) { Write-Host 'SKIPPED: could not read the current setting.' -ForegroundColor Yellow; $results += "$repo : skipped (unreadable)"; continue }
    if ($current.default_workflow_permissions -eq 'write' -and $current.can_approve_pull_request_reviews) {
        Write-Host 'Already matches. Nothing to do.' -ForegroundColor Green
        $results += "$repo : already correct"; continue
    }
    Write-Host 'Proposed: workflow token: write | workflows may approve PRs: True'
    Write-Host 'Effect  : the pr-review workflow stops dying at startup_failure in this repo. It still needs a runner to actually run.'

    if ($WhatIf) { $results += "$repo : would flip to write"; continue }

    $answer = Read-Host "Type YES to flip $repo (anything else skips)"
    if ($answer -cne 'YES') { Write-Host 'Skipped.' -ForegroundColor Yellow; $results += "$repo : skipped by owner"; continue }

    & gh api -X PUT "repos/$Owner/$repo/actions/permissions/workflow" -f default_workflow_permissions=write -F can_approve_pull_request_reviews=true *> $null
    $putOk = ($LASTEXITCODE -eq 0)

    $after = Get-Perm $repo
    Write-Host "Now     : $(Format-Perm $after)"
    if ($putOk -and $after -and $after.default_workflow_permissions -eq 'write' -and $after.can_approve_pull_request_reviews) {
        Write-Host 'FLIPPED and verified.' -ForegroundColor Green; $results += "$repo : FLIPPED (verified)"
    } else {
        Write-Host 'FAILED or could not verify. Check Settings > Actions > General on the repo.' -ForegroundColor Red; $results += "$repo : FAILED / unverified"
    }
}

Write-Host ''
Write-Host '================ Summary ================' -ForegroundColor Cyan
$results | ForEach-Object { Write-Host "  $_" }
$log = Join-Path $PSScriptRoot ("AEGIS-Flip-Actions-Token-4-Repos.{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
if (-not $WhatIf) { $results | Out-File -FilePath $log -Encoding utf8; Write-Host "Log: $log" }
