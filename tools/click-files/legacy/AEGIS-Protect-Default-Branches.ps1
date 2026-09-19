<#
.SYNOPSIS
  Owner-run. Sets branch protection on six default branches to one known-good shape.

.DESCRIPTION
  Authorized by Ops Decision Queue card
  "pr81-q4-branch-protection-all-default-branches-2026-09-17" (owner answer: "Approve - prepare the
  click-file, MasterThread first, then the other five"). Design: MasterThread
  standards/sessions/merge_authority.md, "Enforcement", phase 2.

  Branch protection is a repo security setting. No Claude session applies it; this script refuses to
  run unless a person started it from a real console (stdin not redirected) and types YES per repo.

  Settings mirror what the already-protected repos use (read from aegis-poi 2026-09-17):
    - changes reach the default branch through a pull request (0 approvals required, because every
      session and the owner share one GitHub identity and an author cannot approve their own PR)
    - stale reviews dismissed on new pushes
    - admins included (enforce_admins)
    - no force-push, no branch deletion
    - a required status check ONLY where that check was confirmed to actually run on 2026-09-17
      (claude-agents "test", aegis-mods "check"). The other four get no required check: MasterThread,
      ops-platform and ops-policies have a pr-review workflow but no working runner, and ops-infra
      has no workflow at all, so requiring a check there would block every PR forever.

  Rollback for one repo:  gh api -X DELETE repos/yodatech1988/<repo>/branches/<branch>/protection

  AUDITED AND FIXED 2026-09-18 (github-de) against tools/README.md's click-file rules. One
  defect found and fixed here: the log was written only after the entire 6-repo loop
  completed, outside any try/catch/finally -- an exception partway through (a `gh api -X
  PUT` failure, a JSON conversion error, anything) would die with real changes already
  applied to some repos and NO log at all, the same failure class as the 2026-09-18 01:34Z
  heartbeat-watchdog incident, but worse here because this script can make real writes to
  MULTIPLE repos' security settings per run. Fixed: the per-repo loop and its summary now
  run inside try/finally, so whatever progress `$results` holds -- plus the exception, if
  one occurred -- is always written to the log, on every exit path. The per-repo
  confirm-then-act logic, the required-checks list, and every `gh api` call are UNCHANGED.

  Also verified this pass (no change needed): the interactive-console refusal (line ~90) is
  real code, not just documented; and the required-checks list (`test` for claude-agents,
  `check` for aegis-mods, none for the other four) still matches live reality as of
  2026-09-18 -- both named checks are confirmed passing on recent real runs, and the four
  repos with no required check still have no working runner behind their review workflow
  (MasterThread/ops-platform/ops-policies) or no workflow at all (ops-infra). One thing
  NOT acted on, flagged for a separate owner/PM call rather than silently added here:
  MasterThread gained a new `agents-roster-check` workflow since 2026-09-17 that is
  genuinely passing on every recent PR (5/5 success checked) and could be a required-check
  candidate now -- expanding what this script requires is a scope decision for whoever owns
  this card, not something to add unilaterally during an audit pass.

.PARAMETER WhatIf
  Show current and proposed state for every repo, change nothing, ask nothing.
#>
[CmdletBinding()]
param([switch]$WhatIf)

$ErrorActionPreference = 'Stop'
$Owner = 'yodatech1988'
$script:RunException = $null
$script:RunOutcome = 'UNKNOWN (script exited without setting an outcome)'
$results = @()
$log = Join-Path $PSScriptRoot ("AEGIS-Protect-Default-Branches.{0}.{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $(if ($WhatIf) { 'dryrun.log' } else { 'log' }))

# Order matters: MasterThread first (public, and it governs session behaviour).
$Targets = @(
    @{ Repo = 'MasterThread';  Branch = 'main';   Checks = @() },
    @{ Repo = 'ops-infra';     Branch = 'main';   Checks = @() },
    @{ Repo = 'ops-platform';  Branch = 'main';   Checks = @() },
    @{ Repo = 'ops-policies';  Branch = 'main';   Checks = @() },
    @{ Repo = 'claude-agents'; Branch = 'master'; Checks = @('test') },
    @{ Repo = 'aegis-mods';    Branch = 'master'; Checks = @('check') }
)

function Get-Protection($repo, $branch) {
    $out = & gh api "repos/$Owner/$repo/branches/$branch/protection" 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($out | ConvertFrom-Json)
}

function Format-Protection($p) {
    if ($null -eq $p) { return 'NOT PROTECTED' }
    $checks = if ($p.required_status_checks) { ($p.required_status_checks.contexts -join ',') } else { '' }
    $pr = if ($p.required_pull_request_reviews) { "yes ($($p.required_pull_request_reviews.required_approving_review_count) approvals)" } else { 'no' }
    return "pull-request required: $pr | required checks: [$checks] | admins included: $($p.enforce_admins.enabled) | force-push: $($p.allow_force_pushes.enabled) | deletion: $($p.allow_deletions.enabled)"
}

function New-Body($checks) {
    $rsc = $null
    if ($checks.Count -gt 0) { $rsc = @{ strict = $true; contexts = @($checks) } }
    return @{
        required_status_checks        = $rsc
        enforce_admins                = $true
        required_pull_request_reviews = @{
            dismiss_stale_reviews           = $true
            require_code_owner_reviews      = $false
            required_approving_review_count = 0
        }
        restrictions                  = $null
        allow_force_pushes            = $false
        allow_deletions               = $false
    }
}

try {

# --- initiation binding: a person at a real console, never a session's tool call ---------------
if (-not $WhatIf) {
    if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
        Write-Host 'REFUSED: this must be started by the owner from a real console window (double-click the .cmd).' -ForegroundColor Red
        Write-Host 'A Claude session may only run it with -WhatIf.' -ForegroundColor Red
        $script:RunOutcome = 'REFUSED: not an interactive console and -WhatIf was not passed.'
        exit 2
    }
}

& gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'gh is not logged in. Nothing changed.' -ForegroundColor Red
    $script:RunOutcome = 'FAILED: gh is not logged in. Nothing changed.'
    exit 1
}

foreach ($t in $Targets) {
    $repo = $t.Repo; $branch = $t.Branch
    Write-Host ''
    Write-Host "================ $Owner/$repo  ($branch) ================" -ForegroundColor Cyan

    $defaultBranch = (& gh api "repos/$Owner/$repo" --jq '.default_branch' 2>$null)
    if ($LASTEXITCODE -ne 0 -or $defaultBranch -ne $branch) {
        Write-Host "SKIPPED: expected default branch '$branch' but GitHub says '$defaultBranch'. Nothing changed." -ForegroundColor Yellow
        $results += "$repo : skipped (default branch mismatch)"; continue
    }

    $current = Get-Protection $repo $branch
    Write-Host "Current : $(Format-Protection $current)"
    if ($null -ne $current) {
        $curChecks = @(); if ($current.required_status_checks) { $curChecks = @($current.required_status_checks.contexts) }
        $same = $current.enforce_admins.enabled -and (-not $current.allow_force_pushes.enabled) -and
                (-not $current.allow_deletions.enabled) -and ($null -ne $current.required_pull_request_reviews) -and
                ((($curChecks | Sort-Object) -join ',') -eq ((@($t.Checks) | Sort-Object) -join ','))
        if ($same) {
            Write-Host 'Already matches the proposed settings. Nothing to do.' -ForegroundColor Green
            $results += "$repo : already correct"; continue
        }
        Write-Host 'This branch already has protection that DIFFERS from the proposal. Typing YES REPLACES it.' -ForegroundColor Yellow
        $unrunnable = @($curChecks | Where-Object { $t.Checks -notcontains $_ })
        if ($unrunnable.Count) { Write-Host "  Required now but not confirmed to ever pass here: [$($unrunnable -join ',')] - a required check that never reports blocks every PR." -ForegroundColor Yellow }
        if (-not $current.enforce_admins.enabled) { Write-Host '  Admins are currently exempt, so an --admin merge walks past the protection.' -ForegroundColor Yellow }
    }

    $checksText = if ($t.Checks.Count) { $t.Checks -join ',' } else { 'none (no check confirmed to run here)' }
    Write-Host "Proposed: pull-request required: yes (0 approvals) | required checks: [$checksText] | admins included: True | force-push: False | deletion: False"
    Write-Host 'Effect  : nobody, including you and every session, can push straight to this branch any more; everything goes through a PR.'

    if ($WhatIf) { $results += "$repo : would set proposed protection"; continue }

    $answer = Read-Host "Type YES to protect $repo/$branch (anything else skips)"
    if ($answer -cne 'YES') { Write-Host 'Skipped.' -ForegroundColor Yellow; $results += "$repo : skipped by owner"; continue }

    $tmp = [IO.Path]::GetTempFileName()
    try {
        (New-Body $t.Checks | ConvertTo-Json -Depth 6) | Out-File -FilePath $tmp -Encoding ascii
        & gh api -X PUT "repos/$Owner/$repo/branches/$branch/protection" --input $tmp *> $null
        $putOk = ($LASTEXITCODE -eq 0)
    } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }

    # verify by reading back, never by trusting the PUT's exit code alone
    $after = Get-Protection $repo $branch
    Write-Host "Now     : $(Format-Protection $after)"
    $ok = $putOk -and $after -and $after.enforce_admins.enabled -and
          (-not $after.allow_force_pushes.enabled) -and (-not $after.allow_deletions.enabled) -and
          ($null -ne $after.required_pull_request_reviews)
    if ($ok) { Write-Host 'PROTECTED and verified.' -ForegroundColor Green; $results += "$repo : PROTECTED (verified)" }
    else     { Write-Host 'FAILED or could not verify. Check the repo settings page.' -ForegroundColor Red; $results += "$repo : FAILED / unverified" }
}

Write-Host ''
Write-Host '================ Summary ================' -ForegroundColor Cyan
$results | ForEach-Object { Write-Host "  $_" }
$script:RunOutcome = "Completed: $($results.Count) repo(s) attempted -- $($results -join ' | ')"

}
catch {
    $script:RunException = $_.Exception
    Write-Host ''
    Write-Host 'UNEXPECTED EXCEPTION -- stopped mid-run. Whatever repos were already changed above stayed' -ForegroundColor Red
    Write-Host 'changed (this script never rolls back a prior repo on a later failure); read the per-repo' -ForegroundColor Red
    Write-Host 'results above and the log this run still writes to see exactly how far it got.' -ForegroundColor Red
    Write-Host "Exception type   : $($script:RunException.GetType().FullName)" -ForegroundColor Red
    Write-Host "Exception message: $($script:RunException.Message)" -ForegroundColor Red
    $script:RunOutcome = "FAILED: unhandled exception $($script:RunException.GetType().FullName) -- $($script:RunException.Message). $($results.Count) repo(s) attempted before this."
}
finally {
    $logLines = New-Object System.Collections.Generic.List[string]
    $logLines.Add("RUN TYPE: $(if ($WhatIf) { 'dry run (nothing was changed)' } else { 'real' })")
    $logLines.Add("Start time (local): $((Get-Date).ToString('o'))")
    $logLines.Add("Outcome: $script:RunOutcome")
    $logLines.Add('')
    $logLines.Add('Per-repo results (in order attempted; a run that stopped mid-loop shows only what it reached):')
    foreach ($r in $results) { $logLines.Add("  $r") }
    if ($script:RunException) {
        $logLines.Add('')
        $logLines.Add('STOPPED BY EXCEPTION -- remaining repos in $Targets were never attempted:')
        $logLines.Add("  Type: $($script:RunException.GetType().FullName)")
        $logLines.Add("  Message: $($script:RunException.Message)")
        $logLines.Add("  $($script:RunException.ToString())")
    }
    try {
        $logLines | Out-File -FilePath $log -Encoding utf8
        Write-Host "Log: $log"
    } catch {
        Write-Host "WARNING: could not write run log to $log`: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    if ($script:RunException) { exit 1 }
}
