<#
.SYNOPSIS
  Owner-run. Sets "1 required approving review" on yodatech1988/website main (Apply), or puts the
  saved settings back exactly (-Restore). Nothing else about the protection changes.

.DESCRIPTION
  Design: PM_INBOX github-49-20260919T1930Z-website-review-design.md, Option C (precondition-guarded).
  Authorized in principle by owner card decision-website-main-require-approving-review-2026-09-19.

  APPLY (default):
    1. GET the current protection and save the raw JSON, unmodified, as an exact backup next to the
       log: AEGIS-Require-Review.<repo>.<stamp>.backup.json
    2. FAIL CLOSED: refuse unless the collaborators API lists at least one login other than the
       owner with write/maintain/admin permission. The sole collaborator authors every PR and cannot
       approve their own PR, so requiring 1 approval with enforce_admins on would block EVERY merge.
    3. Show current vs proposed, ask you to type YES, PUT the protection with ONLY
       required_approving_review_count changed to 1. Every other existing setting (required checks
       strict, enforce_admins, dismiss_stale_reviews, no force push/deletion, ...) is re-sent as read.
    4. Re-read and verify by comparing the whole normalized protection against backup+count=1.
  RESTORE (-Restore [-BackupFile path]): re-applies the backup exactly (count back to what it was),
    then re-reads and verifies against the backup.

  Branch protection is a repo security setting: no Claude session runs this for real. A real run
  refuses unless started from a real console. A session may run it only with -WhatIf (reads only,
  writes nothing on GitHub, saves no backup), or against a scratch repo whose name starts with
  'srt-scratch-review-test-' (the only non-interactive exemption; enforced in code below).

  PUT payload shape checked against GitHub REST docs "Update branch protection": required top-level
  keys required_status_checks, enforce_admins, required_pull_request_reviews, restrictions (each may
  be null); PUT replaces the whole protection, so omitted optional keys would reset to defaults --
  hence every field is re-sent. required_signatures has its own endpoint and is not touched (it is
  compared before/after only).

  LIMITS OF THE GUARD (read before running): it proves a second login has WRITE access, not that
  the login can APPROVE. A bot or GitHub App collaborator may not satisfy the review requirement,
  so a lockout is still possible after apply; if merges are blocked, run AEGIS-Restore-Website-Review.cmd.

  WHAT WAS AND WAS NOT TESTED (2026-09-19, by a session; see tools/README.md "What a session cannot test"):
    Verified for real on a private scratch repo: guard refusal with a sole collaborator; apply
      0->1 and restore 1->0 with the scratch protection carrying required checks secret-scan+build
      (strict, app_id 15368) and enforce_admins=true, raw GET identical before/after; -Restore
      refusal on a backup from another repo (exit 4); -WhatIf against the real website repo (GET only).
    Simulated only: the guard-PASS path (run in a temp copy with the guard line forced to pass,
      because no second collaborator exists).
    Never run: the .cmd wrappers, the real interactive YES prompt / interactive-console refusal
      with a live console, and any real apply against website.

  Exit codes: 0 ok / nothing to do / -WhatIf done; 1 failed or unhandled exception;
              2 refused: not an interactive console; 3 refused: no eligible second reviewer (guard);
              4 refused: unexpected protection shape / missing backup / branch or repo mismatch.
  Undo an apply: run AEGIS-Restore-Website-Review.cmd (this script with -Restore).

.PARAMETER WhatIf   Read only. Prints current, proposed and the guard verdict. Changes nothing.
.PARAMETER Restore  Re-apply a saved backup exactly.
.PARAMETER BackupFile  Backup for -Restore (default: newest backup for this repo next to this script).
.PARAMETER Repo     Default 'website'. Non-default only for scratch repos named srt-scratch-review-test-*.
.PARAMETER AssumeYes  Honoured ONLY for scratch repos (test harness); ignored for every other repo.
#>
[CmdletBinding()]
param(
    [switch]$WhatIf,
    [switch]$Restore,
    [string]$BackupFile,
    [string]$Repo = 'website',
    [string]$Branch = 'main',
    [switch]$AssumeYes
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Owner = 'yodatech1988'
$IsScratch = $Repo.StartsWith('srt-scratch-review-test-', [StringComparison]::Ordinal)
$script:Outcome = 'UNKNOWN (script exited without setting an outcome)'
$script:Exception = $null
$script:Attempted = $false      # true once a real PUT was tried (real .log vs .dryrun.log)
$script:Typed = 'n/a'
$script:Plan = @()
$script:Exit = 0
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$startIso = [DateTime]::UtcNow.ToString('o')
$Name = if ($Restore) { 'AEGIS-Restore-Website-Review' } else { 'AEGIS-Require-Website-Review' }

function Prop($o, $n) { if ($null -ne $o -and $o.PSObject.Properties[$n]) { return $o.PSObject.Properties[$n].Value } return $null }
function Flag($o, $n) { $v = Prop $o $n; if ($null -eq $v) { return $false } return [bool](Prop $v 'enabled') }
function Names($x, $k) { return @(@(Prop $x $k) | Where-Object { $_ } | ForEach-Object { if ($_ -is [string]) { $_ } elseif (Prop $_ 'login') { $_.login } else { $_.slug } }) }

# Protection object (from GET) -> the exact PUT body shape. Count override only when given.
function ConvertTo-PutBody($p, $count) {
    $rsc = $null
    $r = Prop $p 'required_status_checks'
    if ($r) {
        $checks = @()
        foreach ($c in @(Prop $r 'checks')) { if ($c) { $checks += @{ context = $c.context; app_id = $c.app_id } } }
        if ($checks.Count -eq 0) { foreach ($c in @(Prop $r 'contexts')) { if ($c) { $checks += @{ context = $c } } } }
        $rsc = @{ strict = [bool]$r.strict; checks = @($checks) }
    }
    $rp = Prop $p 'required_pull_request_reviews'
    $rpr = $null
    if ($rp) {
        $rpr = @{
            dismiss_stale_reviews           = [bool](Prop $rp 'dismiss_stale_reviews')
            require_code_owner_reviews      = [bool](Prop $rp 'require_code_owner_reviews')
            require_last_push_approval      = [bool](Prop $rp 'require_last_push_approval')
            required_approving_review_count = [int](Prop $rp 'required_approving_review_count')
        }
        if ($null -ne $count) { $rpr.required_approving_review_count = [int]$count }
        foreach ($k in 'dismissal_restrictions', 'bypass_pull_request_allowances') {
            $x = Prop $rp $k
            if ($x) { $rpr[$k] = @{ users = @(Names $x 'users'); teams = @(Names $x 'teams'); apps = @(Names $x 'apps') } }
        }
    }
    $rs = $null
    $x = Prop $p 'restrictions'
    if ($x) { $rs = @{ users = @(Names $x 'users'); teams = @(Names $x 'teams'); apps = @(Names $x 'apps') } }
    return [ordered]@{
        required_status_checks           = $rsc
        enforce_admins                   = (Flag $p 'enforce_admins')
        required_pull_request_reviews    = $rpr
        restrictions                     = $rs
        required_linear_history          = (Flag $p 'required_linear_history')
        allow_force_pushes               = (Flag $p 'allow_force_pushes')
        allow_deletions                  = (Flag $p 'allow_deletions')
        block_creations                  = (Flag $p 'block_creations')
        required_conversation_resolution = (Flag $p 'required_conversation_resolution')
        lock_branch                      = (Flag $p 'lock_branch')
        allow_fork_syncing               = (Flag $p 'allow_fork_syncing')
    }
}

function Add-Flat($v, $path, $acc) {
    if ($null -eq $v) { $acc.Add("$path=null"); return }
    if ($v -is [System.Collections.IDictionary]) { foreach ($k in ($v.Keys | Sort-Object)) { Add-Flat $v[$k] "$path.$k" $acc }; return }
    if ($v -is [System.Collections.IEnumerable] -and $v -isnot [string]) {
        $i = 0; foreach ($e in $v) { Add-Flat $e "$path[$i]" $acc; $i++ }
        if ($i -eq 0) { $acc.Add("$path=[]") }
        return
    }
    $acc.Add("$path=$v")
}
# Canonical string of everything we manage, for exact before/after comparison.
function Get-Canon($p) {
    $b = ConvertTo-PutBody $p $null
    if ($b.required_status_checks) { $b.required_status_checks.checks = @($b.required_status_checks.checks | Sort-Object { $_.context }) }
    $flat = New-Object System.Collections.Generic.List[string]
    Add-Flat $b 'p' $flat
    $flat.Add("signatures=$(Flag $p 'required_signatures')")
    return ($flat -join "`n")
}

function Read-ProtectionRaw {
    $out = & gh api "repos/$Owner/$Repo/branches/$Branch/protection" 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return (($out) -join "`n")
}
function Format-P($p) {
    if ($null -eq $p) { return 'NOT PROTECTED' }
    $rsc = Prop $p 'required_status_checks'
    $ctx = ''; $st = $false
    if ($rsc) { $ctx = (@(@(Prop $rsc 'checks') | ForEach-Object { $_.context }) -join ','); $st = [bool]$rsc.strict }
    $rp = Prop $p 'required_pull_request_reviews'
    $pr = if ($rp) { "yes ($($rp.required_approving_review_count) approvals, dismiss-stale=$($rp.dismiss_stale_reviews))" } else { 'no' }
    return "pull-request: $pr | checks: [$ctx] strict=$st | admins included: $(Flag $p 'enforce_admins') | force-push: $(Flag $p 'allow_force_pushes') | deletion: $(Flag $p 'allow_deletions')"
}
function Send-Put($body) {
    $tmp = [IO.Path]::GetTempFileName()
    try {
        ($body | ConvertTo-Json -Depth 8) | Out-File -FilePath $tmp -Encoding ascii
        $o = & gh api -X PUT "repos/$Owner/$Repo/branches/$Branch/protection" --input $tmp 2>&1
        return @{ Ok = ($LASTEXITCODE -eq 0); Text = ($o -join ' ') }
    } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
}
function Confirm-Yes($prompt) {
    if ($AssumeYes -and $IsScratch) { Write-Host "$prompt  [scratch test harness: YES supplied]"; return 'YES' }
    return (Read-Host $prompt)
}

try {
    if ($Repo -ne 'website' -and -not $IsScratch) {
        Write-Host "REFUSED: -Repo '$Repo' is not 'website' or a srt-scratch-review-test-* scratch repo." -ForegroundColor Red
        $script:Outcome = "REFUSED: repo $Repo not allowed."; $script:Exit = 4; exit 4
    }
    # Interactive guard, exemption enforced in code: non-interactive real runs only for scratch repos.
    if (-not $WhatIf -and -not $IsScratch) {
        if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
            Write-Host 'REFUSED: this must be started by the owner from a real console window (double-click the .cmd).' -ForegroundColor Red
            Write-Host 'A Claude session may only run it with -WhatIf.' -ForegroundColor Red
            $script:Outcome = 'REFUSED: not an interactive console and -WhatIf was not passed.'; $script:Exit = 2; exit 2
        }
    }
    & gh auth status *> $null
    if ($LASTEXITCODE -ne 0) { Write-Host 'gh is not logged in. Nothing changed.' -ForegroundColor Red; $script:Outcome = 'FAILED: gh not logged in.'; $script:Exit = 1; exit 1 }

    Write-Host "================ $Owner/$Repo ($Branch) ================" -ForegroundColor Cyan
    $dbr = & gh api "repos/$Owner/$Repo" --jq '.default_branch' 2>$null
    if ($LASTEXITCODE -ne 0 -or $dbr -ne $Branch) {
        Write-Host "REFUSED: expected default branch '$Branch' but GitHub says '$dbr'. Nothing changed." -ForegroundColor Yellow
        $script:Outcome = 'REFUSED: default branch mismatch.'; $script:Exit = 4; exit 4
    }
    $raw = Read-ProtectionRaw
    if ($null -eq $raw) { Write-Host 'REFUSED: branch has no readable protection. Nothing changed.' -ForegroundColor Yellow; $script:Outcome = 'REFUSED: no protection readable.'; $script:Exit = 4; exit 4 }
    $cur = $raw | ConvertFrom-Json
    Write-Host "Current : $(Format-P $cur)"

    if ($Restore) {
        if (-not $BackupFile) {
            $c = Get-ChildItem -Path $PSScriptRoot -Filter "AEGIS-Require-Review.$Repo.*.backup.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($c) { $BackupFile = $c.FullName }
        }
        if (-not $BackupFile -or -not (Test-Path $BackupFile)) { Write-Host 'REFUSED: no backup file found. Nothing changed.' -ForegroundColor Red; $script:Outcome = 'REFUSED: no backup file.'; $script:Exit = 4; exit 4 }
        $bk = Get-Content -Raw -Path $BackupFile | ConvertFrom-Json
        $wantUrl = "https://api.github.com/repos/$Owner/$Repo/branches/$Branch/protection"
        $gotUrl = [string](Prop $bk 'url')
        if ($gotUrl -cne $wantUrl) {
            Write-Host "REFUSED: backup belongs to a different repo/branch (backup url '$gotUrl', expected '$wantUrl'). Nothing changed." -ForegroundColor Red
            $script:Outcome = "REFUSED: backup url mismatch ('$gotUrl')."; $script:Exit = 4; exit 4
        }
        $body = ConvertTo-PutBody $bk $null
        $bcount = if ($body.required_pull_request_reviews) { $body.required_pull_request_reviews.required_approving_review_count } else { 'n/a' }
        Write-Host "Backup  : $BackupFile"
        Write-Host "Restore : $(Format-P $bk)"
        $script:Plan = @("restore from $BackupFile (approvals -> $bcount)")
        $expect = Get-Canon $bk
        if ((Get-Canon $cur) -eq $expect) { Write-Host 'Already identical to the backup. Nothing to do.' -ForegroundColor Green; $script:Outcome = 'Nothing to do: already matches backup.'; exit 0 }
        if ($WhatIf) { $script:Outcome = '-WhatIf: would restore the backup. Nothing changed.'; exit 0 }
        $script:Typed = Confirm-Yes "Type YES to restore $Repo/$Branch from the backup (anything else cancels)"
        if ($script:Typed -cne 'YES') { Write-Host 'Cancelled.' -ForegroundColor Yellow; $script:Outcome = 'Cancelled by owner.'; exit 0 }
    }
    else {
        $rp = Prop $cur 'required_pull_request_reviews'
        if (-not $rp) { Write-Host 'REFUSED: protection has no pull-request-review block; unexpected shape. Nothing changed.' -ForegroundColor Red; $script:Outcome = 'REFUSED: unexpected shape.'; $script:Exit = 4; exit 4 }
        $now = [int]$rp.required_approving_review_count
        $body = ConvertTo-PutBody $cur 1
        Write-Host "Proposed: same as current, but approvals required: $now -> 1 (nothing else changes)"
        $script:Plan = @("approvals $now -> 1 on $Repo/$Branch; all other settings re-sent unchanged")

        # --- fail-closed guard: a second reviewer must already exist ---
        $collab = & gh api "repos/$Owner/$Repo/collaborators?affiliation=all&per_page=100" --paginate 2>$null
        $guardOk = $false; $eligible = @(); $guardWhy = ''
        if ($LASTEXITCODE -ne 0) { $guardWhy = 'could not read the collaborators list (fail closed)' }
        else {
            $list = @((($collab) -join "`n") | ConvertFrom-Json)
            foreach ($u in $list) {
                $perm = Prop $u 'permissions'
                $canWrite = $perm -and ([bool](Prop $perm 'push') -or [bool](Prop $perm 'admin') -or [bool](Prop $perm 'maintain'))
                if ($u.login -ne $Owner -and $canWrite) { $eligible += $u.login }
            }
            $guardOk = ($eligible.Count -ge 1)
            $guardWhy = "collaborators seen: $((@($list | ForEach-Object { $_.login })) -join ', ')"
        }
        Write-Host "Guard   : $(if ($guardOk) { "PASS - second reviewer(s) with write access: $($eligible -join ', ')" } else { "FAIL - $guardWhy" })"
        if (-not $guardOk) {
            Write-Host ''
            Write-Host 'REFUSED: no collaborator other than the owner has write or admin access.' -ForegroundColor Red
            Write-Host 'The only collaborator authors every PR, and a PR author cannot approve their own PR.' -ForegroundColor Red
            Write-Host 'Requiring 1 approval now (with admins included) would block EVERY merge to this branch, yours too.' -ForegroundColor Red
            Write-Host 'Add a second GitHub account as a collaborator with write access first, then run this again. Nothing changed.' -ForegroundColor Red
            $script:Outcome = "REFUSED (guard): no second reviewer with write access. $guardWhy"; $script:Exit = 3; exit 3
        }
        if ($now -ge 1) { Write-Host "Already requires $now approval(s). Nothing to do." -ForegroundColor Green; $script:Outcome = 'Nothing to do: already >= 1.'; exit 0 }
        if ($WhatIf) { $script:Outcome = '-WhatIf: guard passed; would set approvals to 1. Nothing changed.'; exit 0 }

        # exact backup BEFORE any change; abort if it cannot be written or does not read back identical
        $bkPath = Join-Path $PSScriptRoot ("AEGIS-Require-Review.{0}.{1}.backup.json" -f $Repo, $stamp)
        [IO.File]::WriteAllText($bkPath, $raw, (New-Object System.Text.UTF8Encoding($false)))
        if ([IO.File]::ReadAllText($bkPath) -ne $raw) { Write-Host 'REFUSED: backup did not read back identical. Nothing changed.' -ForegroundColor Red; $script:Outcome = 'REFUSED: backup verify failed.'; $script:Exit = 4; exit 4 }
        Write-Host "Backup saved: $bkPath"
        Write-Host 'Effect  : every PR (yours and the sessions) now needs an approval from an account that is not its author.'
        Write-Host 'Undo    : AEGIS-Restore-Website-Review.cmd (uses the backup above).'
        $script:Typed = Confirm-Yes "Type YES to require 1 approving review on $Repo/$Branch (anything else cancels)"
        if ($script:Typed -cne 'YES') { Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow; $script:Outcome = 'Cancelled by owner (backup file was written, nothing else).'; exit 0 }
        $expectObj = $raw | ConvertFrom-Json
        $expectObj.required_pull_request_reviews.required_approving_review_count = 1
        $expect = Get-Canon $expectObj
    }

    # --- the real action ---
    $script:Attempted = $true
    try { $res = Send-Put $body }
    catch {
        Write-Host "PUT threw: $($_.Exception.GetType().FullName): $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'State unknown - check the repo settings page; restore with the Restore .cmd.' -ForegroundColor Red
        $script:Outcome = "FAILED: PUT threw $($_.Exception.Message)"; $script:Exit = 1; exit 1
    }
    $after = ((Read-ProtectionRaw) | ConvertFrom-Json)
    Write-Host "Now     : $(Format-P $after)"
    if ($res.Ok -and (Get-Canon $after) -eq $expect) {
        Write-Host 'DONE and verified against the expected full settings.' -ForegroundColor Green
        $script:Outcome = "OK verified: $(Format-P $after)"
    } else {
        Write-Host "FAILED or could not verify (PUT ok=$($res.Ok)): $($res.Text)" -ForegroundColor Red
        Write-Host 'Check the repo settings page; the Restore .cmd re-applies the backup.' -ForegroundColor Red
        $script:Outcome = "FAILED/unverified (PUT ok=$($res.Ok)): $($res.Text)"; $script:Exit = 1; exit 1
    }
}
catch {
    $script:Exception = $_.Exception
    Write-Host "UNEXPECTED EXCEPTION: $($_.Exception.GetType().FullName): $($_.Exception.Message)" -ForegroundColor Red
    $script:Outcome = "FAILED: unhandled $($_.Exception.GetType().FullName) - $($_.Exception.Message)"; $script:Exit = 1
}
finally {
    $real = $script:Attempted
    $log = Join-Path $PSScriptRoot ("{0}.{1}.{2}" -f $Name, $stamp, $(if ($real) { 'log' } else { 'dryrun.log' }))
    $l = New-Object System.Collections.Generic.List[string]
    $l.Add("RUN TYPE: $(if ($real) { 'real' } else { 'dry run (nothing was changed)' })")
    $l.Add("Start (UTC): $startIso")
    $l.Add("Repo/branch: $Owner/$Repo $Branch  Mode: $(if ($Restore) { 'restore' } else { 'apply' })  WhatIf=$($WhatIf.IsPresent)")
    $l.Add("Plan: $($script:Plan -join '; ')")
    $l.Add("Owner typed: $($script:Typed)")
    $l.Add("Outcome: $script:Outcome")
    if ($script:Exception) { $l.Add($script:Exception.ToString()) }
    try { $l | Out-File -FilePath $log -Encoding utf8; Write-Host "Log: $log" } catch { Write-Host "WARNING: could not write log: $($_.Exception.Message)" -ForegroundColor Yellow }
}
exit $script:Exit
