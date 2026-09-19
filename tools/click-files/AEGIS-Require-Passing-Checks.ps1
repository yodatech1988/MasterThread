<#
.SYNOPSIS
  Owner-run. Makes named CI checks REQUIRED on the default branch of two repos (ops-household,
  services) so a merge is blocked until the check is green, and turns on "include administrators"
  so the owner's own click cannot bypass that. -Restore puts the saved settings back exactly.

.DESCRIPTION
  Design: PM request 2026-09-19 (owner wish: "I don't want to be able to merge before tests pass"),
  pattern of tools/click-files/AEGIS-Require-Website-Review.ps1 (MasterThread #137).

  FIXED MANIFEST (edit this file to change it; there is no parameter that adds a repo or a check):
    ops-household (main): require `test`; enforce_admins false -> true.
    services      (main): require admin-bot, gateway, ops-db, economy-db, economy-loot-db;
                          enforce_admins is already true and is left as is.
  NEVER in the manifest (checked in code, the script refuses to start if one appears):
    `gate / gate`, `secret-scan`, `review`, `review / review`, `review / automerge`. Those fail on recent
    PRs or are not tests; requiring them would freeze merges.
  Repos deliberately NOT here: jarvis, payments, MasterThread, ops-business (a required check would
  freeze them today), and repos with no CI. See the PM_INBOX note for what each would need.

  APPLY (default), one repo at a time:
    1. GET the current protection; save the raw JSON, unmodified, next to this script as
       AEGIS-Require-Checks.<repo>.<stamp>.backup.json and read it back; refuse the repo if it differs.
    2. FAIL CLOSED guard, per check to be added: the check must exist and be green (latest run per
       commit) on the 3 newest default-branch commits AND on the head commit of the 3 newest merged
       PRs (proof it runs on pull requests, not just on push), and one single GitHub App must own it.
       Anything else: that repo is refused and nothing about it changes.
    3. Show current vs proposed and what a red or pending check will now block, then ask you to type
       YES (capital letters, exactly). Anything else skips that repo.
    4. PUT the protection. Every field is re-sent as read; existing required checks are kept (their
       app_id preserved); only the manifest's new checks are added, and enforce_admins is set.
       required_signatures has its own endpoint and is compared before/after only.
    5. Re-read and compare the whole normalized protection against the expected result. A mismatch
       is reported as FAILED and the run stops (later repos are not touched).
  RESTORE (-Restore [-OnlyRepo r] [-BackupFile path]): re-applies each saved backup exactly, then
    re-reads and verifies against the backup. Undo of an apply.
  SECOND UNDO PATH (if this script or gh will not run): GitHub website > the repo > Settings >
    Branches > edit the rule for main > untick the added required checks and, on ops-household,
    "Do not allow bypassing the above settings"; save. The backup .json shows what it was before.

  AFTER APPLY ON ops-household: administrators are included, so direct pushes to main stop and every
    change goes through a pull request whose `test` check is green. Cleaner long term: move that
    repo's `test` to the VPS runner first (the org rule for private repos), then require it.

  Branch protection is a repo security setting: no Claude session runs this for real. A real run
  refuses unless started from a real console. A session may run it only with -WhatIf (reads only,
  writes nothing on GitHub, saves no backup), or against a scratch repo whose name starts with
  'srt-scratch-checks-test-' (the only non-interactive exemption; enforced in code below).

  WHAT A RED OR PENDING CHECK NOW BLOCKS (also printed per repo before you type YES):
    ops-household: a PR cannot be merged, by anyone, until `test` (the Python unit tests, run on a
      GitHub-hosted runner) reports success on the PR's head commit. Red, still running, or never
      reported all block. The owner can no longer click through: administrators are now included.
      If GitHub-hosted runners stop running (for example a billing problem), `test` never reports and
      merges are blocked until you run the Restore file.
    services: same, for each of the five jobs. They run on the single OVH VPS runner, one job at a
      time, so a PR waits for five jobs in turn; branches must also be up to date (already the
      case). If the VPS runner is offline the jobs stay pending and merges are blocked.

  LIMITS OF THE GUARD: it proves the check was green recently on push and on merged PRs, not that it
  will be green on the next PR, and not that the runner will be up. A lockout is still possible
  after apply; the Restore file undoes it.

  Exit codes: 0 ok / nothing to do / -WhatIf done; 1 failed or unhandled exception;
              2 refused: not an interactive console; 3 refused by the guard for at least one repo;
              4 refused: unexpected protection shape / missing backup / branch or repo mismatch.
              (Highest concern wins when several happen: 1, then 4, then 3.)

.PARAMETER WhatIf        Read only. Prints current, proposed and the guard verdict. Changes nothing.
.PARAMETER Restore       Re-apply saved backups exactly.
.PARAMETER OnlyRepo      Limit to one manifest repo.
.PARAMETER BackupFile    Backup for -Restore. Requires -OnlyRepo (one backup file belongs to one repo; refused otherwise). Without it, each repo uses its newest AEGIS-Require-Checks.<repo>.*.backup.json next to this script.
.PARAMETER ScratchRepo   Test harness only: replaces the manifest with this one repo; name must match ^srt-scratch-checks-test-[a-z0-9-]+$ (case-sensitive).
.PARAMETER ScratchChecks Test harness only: the checks to require on the scratch repo.
.PARAMETER AssumeYes     Honoured ONLY for scratch repos (test harness); ignored for every other repo.
#>
[CmdletBinding()]
param(
    [switch]$WhatIf,
    [switch]$Restore,
    [string]$OnlyRepo,
    [string]$BackupFile,
    [string]$ScratchRepo,
    [string[]]$ScratchChecks,
    [switch]$AssumeYes
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Owner = 'yodatech1988'
$ScratchPrefix = 'srt-scratch-checks-test-'
$DenyChecks = @('gate / gate', 'secret-scan', 'review', 'review / review', 'review / automerge')

$Manifest = @(
    [pscustomobject]@{
        Repo = 'ops-household'; Branch = 'main'
        Checks = @('test'); EnforceAdmins = $true
        Effect = "A PR (yours included) cannot merge until check 'test' is green on its head commit. Red, pending or never-reported all block, and administrators are now included, so you cannot click through, and direct pushes to main stop: every change goes through a pull request. If GitHub-hosted runners stop working, merges stay blocked until you run the Restore file."
    }
    [pscustomobject]@{
        Repo = 'services'; Branch = 'main'
        Checks = @('admin-bot', 'gateway', 'ops-db', 'economy-db', 'economy-loot-db'); EnforceAdmins = $true
        Effect = "A PR cannot merge until all five checks are green on its head commit. They run on the single OVH VPS runner, one job at a time, so a PR waits for five jobs in turn. If that runner is offline the jobs stay pending and merges stay blocked (administrators are already included)."
    }
)
$IsScratch = $false
# Test harness only. The exemption is a whole-name pattern, not a prefix, so path-like or upper-case names are refused.
if ($ScratchRepo) {
    if (($ScratchRepo -cnotmatch '^srt-scratch-checks-test-[a-z0-9-]+\z') -or -not $ScratchChecks) {
        $Manifest = @()   # refused below
    } else {
        $IsScratch = $true
        $Manifest = @([pscustomobject]@{ Repo = $ScratchRepo; Branch = 'main'; Checks = @($ScratchChecks); EnforceAdmins = $true
                Effect = 'Scratch repo: a PR cannot merge until the named checks are green.' })
    }
}

$script:Outcome = 'UNKNOWN (script exited without setting an outcome)'
$script:Exception = $null
$script:Attempted = $false
$script:Typed = New-Object System.Collections.Generic.List[string]
$script:Plan = New-Object System.Collections.Generic.List[string]
$script:Results = New-Object System.Collections.Generic.List[string]
$script:Worst = 0
$script:Exit = 0
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$startIso = [DateTime]::UtcNow.ToString('o')
$Name = if ($Restore) { 'AEGIS-Restore-Passing-Checks' } else { 'AEGIS-Require-Passing-Checks' }

function Prop($o, $n) { if ($null -ne $o -and $o.PSObject.Properties[$n]) { return $o.PSObject.Properties[$n].Value } return $null }
function Flag($o, $n) { $v = Prop $o $n; if ($null -eq $v) { return $false } return [bool](Prop $v 'enabled') }
function Names($x, $k) { return @(@(Prop $x $k) | Where-Object { $_ } | ForEach-Object { if ($_ -is [string]) { $_ } elseif (Prop $_ 'login') { $_.login } else { $_.slug } }) }
function AppIdOut($v) { if ($null -eq $v) { return -1 } return [int]$v }   # -1 = "any app", GitHub's documented value

# Escalate the exit code: 1 (failed) beats 4 (shape) beats 3 (guard) beats 0.
function Set-Worst([int]$code) {
    $rank = @{ 0 = 0; 3 = 1; 4 = 2; 1 = 3 }
    if ($rank[$code] -gt $rank[[int]$script:Worst]) { $script:Worst = $code }
}

# Protection object (from GET) -> the exact PUT body shape. $extra: @{context; app_id} to add.
# $forceEnforce: $true/$false to override enforce_admins, $null to keep it as read.
function ConvertTo-PutBody($p, $extra, $forceEnforce) {
    $rsc = $null
    $r = Prop $p 'required_status_checks'
    $checks = @()
    if ($r) {
        foreach ($c in @(Prop $r 'checks')) { if ($c) { $checks += @{ context = $c.context; app_id = (AppIdOut (Prop $c 'app_id')) } } }
        if ($checks.Count -eq 0) { foreach ($c in @(Prop $r 'contexts')) { if ($c) { $checks += @{ context = $c; app_id = -1 } } } }
    }
    foreach ($e in @($extra)) {
        if ($e -and -not (@($checks | Where-Object { $_.context -ceq $e.context }).Count)) { $checks += @{ context = $e.context; app_id = [int]$e.app_id } }
    }
    if ($r -or $checks.Count -gt 0) { $rsc = @{ strict = $(if ($r) { [bool]$r.strict } else { $false }); checks = @($checks) } }
    $rp = Prop $p 'required_pull_request_reviews'
    $rpr = $null
    if ($rp) {
        $rpr = @{
            dismiss_stale_reviews           = [bool](Prop $rp 'dismiss_stale_reviews')
            require_code_owner_reviews      = [bool](Prop $rp 'require_code_owner_reviews')
            require_last_push_approval      = [bool](Prop $rp 'require_last_push_approval')
            required_approving_review_count = [int](Prop $rp 'required_approving_review_count')
        }
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
        enforce_admins                   = $(if ($null -ne $forceEnforce) { [bool]$forceEnforce } else { Flag $p 'enforce_admins' })
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
function Get-CanonFromBody($b, $signatures) {
    if ($b.required_status_checks) { $b.required_status_checks.checks = @($b.required_status_checks.checks | Sort-Object { $_.context }) }
    $flat = New-Object System.Collections.Generic.List[string]
    Add-Flat $b 'p' $flat
    $flat.Add("signatures=$signatures")
    return ($flat -join "`n")
}
function Get-Canon($p) { return (Get-CanonFromBody (ConvertTo-PutBody $p $null $null) (Flag $p 'required_signatures')) }

function Invoke-GhJson([string]$Path) {
    $out = & gh api $Path 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $txt = ($out) -join "`n"
    if ([string]::IsNullOrWhiteSpace($txt)) { return $null }
    return ($txt | ConvertFrom-Json)
}
function Read-ProtectionRaw([string]$repo, [string]$branch) {
    $out = & gh api "repos/$Owner/$repo/branches/$branch/protection" 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return (($out) -join "`n")
}
function Format-P($p) {
    if ($null -eq $p) { return 'NOT PROTECTED' }
    $rsc = Prop $p 'required_status_checks'
    $ctx = ''; $st = $false
    if ($rsc) { $ctx = (@(@(Prop $rsc 'checks') | ForEach-Object { $_.context }) -join ','); $st = [bool]$rsc.strict }
    $rp = Prop $p 'required_pull_request_reviews'
    $pr = if ($rp) { "yes ($($rp.required_approving_review_count) approvals)" } else { 'no' }
    return "required checks: [$ctx] strict=$st | pull-request review: $pr | admins included: $(Flag $p 'enforce_admins') | force-push: $(Flag $p 'allow_force_pushes') | deletion: $(Flag $p 'allow_deletions')"
}
function Send-Put([string]$repo, [string]$branch, $body) {
    $tmp = [IO.Path]::GetTempFileName()
    try {
        ($body | ConvertTo-Json -Depth 8) | Out-File -FilePath $tmp -Encoding ascii
        $o = & gh api -X PUT "repos/$Owner/$repo/branches/$branch/protection" --input $tmp 2>&1
        return @{ Ok = ($LASTEXITCODE -eq 0); Text = ($o -join ' ') }
    } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
}
function Confirm-Yes($prompt) {
    if ($AssumeYes -and $IsScratch) { Write-Host "$prompt  [scratch test harness: YES supplied]"; return 'YES' }
    return (Read-Host $prompt)
}

# Latest run (by completion time) of one check name on one commit; $null if the check never ran there.
function Get-LatestRun([string]$repo, [string]$sha, [string]$check) {
    $cr = Invoke-GhJson "repos/$Owner/$repo/commits/$sha/check-runs?per_page=100"
    if ($null -eq $cr) { return $null }
    $best = $null
    foreach ($run in @(Prop $cr 'check_runs')) {
        if ($null -eq $run -or (Prop $run 'name') -cne $check) { continue }
        $t = [string](Prop $run 'completed_at'); if (-not $t) { $t = [string](Prop $run 'started_at') }
        if ($null -eq $best -or $t -gt $best.T) { $best = @{ T = $t; Run = $run } }
    }
    if ($null -eq $best) { return $null }
    return $best.Run
}
# Fail-closed proof that requiring $check on $branch will not freeze merges today.
function Test-CheckGuard([string]$repo, [string]$branch, [string]$check) {
    $why = New-Object System.Collections.Generic.List[string]
    $apps = @{}
    $commits = @(Invoke-GhJson "repos/$Owner/$repo/commits?sha=$branch&per_page=5")
    if ($commits.Count -lt 3) { return @{ Ok = $false; Why = "fewer than 3 recent commits readable on $branch"; AppId = $null } }
    $ok = $true
    foreach ($c in $commits[0..2]) {
        $sha7 = ([string]$c.sha).Substring(0, 7)
        $run = Get-LatestRun $repo $c.sha $check
        if ($null -eq $run) { $ok = $false; $why.Add("'$check' never ran on $branch commit $sha7"); continue }
        $con = [string](Prop $run 'conclusion')
        if ($con -cne 'success') { $ok = $false; $why.Add("'$check' on $branch commit ${sha7}: $(if ($con) { $con } else { [string](Prop $run 'status') })"); continue }
        $app = Prop $run 'app'; if ($app) { $apps[[string](Prop $app 'id')] = $true }
        $why.Add("$branch $sha7 success")
    }
    $prs = @(Invoke-GhJson "repos/$Owner/$repo/pulls?state=closed&base=$branch&per_page=15") | Where-Object { $_ -and (Prop $_ 'merged_at') } | Sort-Object { [string]$_.merged_at } -Descending | Select-Object -First 3
    if (@($prs).Count -lt 1) { $ok = $false; $why.Add('no merged PR to prove the check runs on pull requests') }
    foreach ($pr in @($prs)) {
        $sha7 = ([string]$pr.head.sha).Substring(0, 7)
        $run = Get-LatestRun $repo $pr.head.sha $check
        if ($null -eq $run) { $ok = $false; $why.Add("'$check' never ran on merged PR #$($pr.number) head $sha7"); continue }
        $con = [string](Prop $run 'conclusion')
        if ($con -cne 'success') { $ok = $false; $why.Add("'$check' on merged PR #$($pr.number) head ${sha7}: $(if ($con) { $con } else { 'not finished' })"); continue }
        $app = Prop $run 'app'; if ($app) { $apps[[string](Prop $app 'id')] = $true }
        $why.Add("PR #$($pr.number) $sha7 success")
    }
    if ($apps.Count -ne 1) { $ok = $false; $why.Add("expected exactly one GitHub App to own '$check', saw $($apps.Count)") }
    $appId = if ($apps.Count -eq 1) { [int]@($apps.Keys)[0] } else { $null }
    return @{ Ok = $ok; Why = ($why -join '; '); AppId = $appId }
}

function Assert-Manifest {
    if ($ScratchRepo -and -not $IsScratch) { throw "REFUSED-ARG: -ScratchRepo must match ^${ScratchPrefix}[a-z0-9-]+`$ and -ScratchChecks must be given." }
    if ($BackupFile -and -not $OnlyRepo) { throw 'REFUSED-ARG: -BackupFile needs -OnlyRepo, because one backup file belongs to one repo.' }
    $seen = @{}
    foreach ($m in $Manifest) {
        if ($seen[$m.Repo]) { throw "REFUSED-ARG: manifest lists $($m.Repo) twice" }
        $seen[$m.Repo] = $true
        foreach ($c in $m.Checks) {
            if ($DenyChecks -contains $c.ToLowerInvariant()) { throw "REFUSED-ARG: manifest asks for '$c' on $($m.Repo), which is on the never-require list ($($DenyChecks -join ', '))" }
        }
    }
    if ($OnlyRepo -and -not $seen[$OnlyRepo]) { throw "REFUSED-ARG: -OnlyRepo '$OnlyRepo' is not in the manifest." }
}

function Add-Result([string]$line) { $script:Results.Add($line); Write-Host $line }

function Invoke-ApplyRepo($m) {
    $repo = $m.Repo; $branch = $m.Branch
    Write-Host ''
    Write-Host "================ $Owner/$repo ($branch) ================" -ForegroundColor Cyan
    $dbr = & gh api "repos/$Owner/$repo" --jq '.default_branch' 2>$null
    if ($LASTEXITCODE -ne 0 -or $dbr -ne $branch) {
        Write-Host "REFUSED: expected default branch '$branch' but GitHub says '$dbr'. Nothing changed." -ForegroundColor Yellow
        Add-Result "$repo : REFUSED (default branch mismatch)"; Set-Worst 4; return
    }
    $raw = Read-ProtectionRaw $repo $branch
    if ($null -eq $raw) { Write-Host 'REFUSED: branch has no readable protection. This tool only edits an existing protection. Nothing changed.' -ForegroundColor Yellow; Add-Result "$repo : REFUSED (no readable protection)"; Set-Worst 4; return }
    $cur = $raw | ConvertFrom-Json
    Write-Host "Current : $(Format-P $cur)"

    $have = @()
    $rsc = Prop $cur 'required_status_checks'
    if ($rsc) { $have = @(@(Prop $rsc 'checks') | Where-Object { $_ } | ForEach-Object { $_.context }); if ($have.Count -eq 0) { $have = @(@(Prop $rsc 'contexts') | Where-Object { $_ }) } }
    $toAdd = @($m.Checks | Where-Object { $have -cnotcontains $_ })
    $enfNow = Flag $cur 'enforce_admins'
    $enfChange = ($enfNow -ne [bool]$m.EnforceAdmins)
    if ($toAdd.Count -eq 0 -and -not $enfChange) { Write-Host 'Already has every manifest check and the admin setting. Nothing to do.' -ForegroundColor Green; Add-Result "$repo : nothing to do"; return }

    $extra = @()
    $guardOk = $true
    foreach ($c in $toAdd) {
        $g = Test-CheckGuard $repo $branch $c
        Write-Host ("Guard   : '{0}' -> {1}  [{2}]" -f $c, $(if ($g.Ok) { 'PASS' } else { 'FAIL' }), $g.Why)
        if ($g.Ok) { $extra += @{ context = $c; app_id = $g.AppId } } else { $guardOk = $false }
    }
    $proposed = ConvertTo-PutBody $cur $extra $m.EnforceAdmins
    # required_status_checks is $null when there are no existing checks and the guard rejected every new one.
    $prsc = $proposed.required_status_checks
    $newCtx = if ($prsc) { (@($prsc.checks | ForEach-Object { $_.context }) -join ',') } else { '' }
    $newStrict = if ($prsc) { $prsc.strict } else { $false }
    Write-Host "Proposed: required checks: [$newCtx] strict=$newStrict | admins included: $($proposed.enforce_admins) | everything else re-sent unchanged"
    $script:Plan.Add("$repo/$branch : add [$($toAdd -join ',')], admins included $enfNow -> $($m.EnforceAdmins)")
    if (-not $guardOk) {
        Write-Host ''
        Write-Host "REFUSED (guard): at least one check is not proven green on push AND on merged pull requests. Requiring it now could block every merge. Nothing changed for $repo." -ForegroundColor Red
        Add-Result "$repo : REFUSED (guard)"; Set-Worst 3; return
    }
    if ($WhatIf) { Write-Host '-WhatIf: guard passed; would apply the change above. Nothing changed.' -ForegroundColor Green; Add-Result "$repo : -WhatIf, would apply"; return }

    # exact backup BEFORE any change; abort this repo if it cannot be written or does not read back identical
    $bkPath = Join-Path $PSScriptRoot ("AEGIS-Require-Checks.{0}.{1}.backup.json" -f $repo, $stamp)
    [IO.File]::WriteAllText($bkPath, $raw, (New-Object System.Text.UTF8Encoding($false)))
    if ([IO.File]::ReadAllText($bkPath) -ne $raw) { Write-Host 'REFUSED: backup did not read back identical. Nothing changed.' -ForegroundColor Red; Add-Result "$repo : REFUSED (backup verify failed)"; Set-Worst 4; return }
    Write-Host "Backup saved: $bkPath"
    Write-Host "What a red or pending check now blocks: $($m.Effect)" -ForegroundColor Yellow
    Write-Host 'Undo    : AEGIS-Restore-Passing-Checks.cmd (uses the backup above).'
    $typed = Confirm-Yes "Type YES to require [$($toAdd -join ', ')] on $repo/$branch and set admins included (anything else skips this repo)"
    $script:Typed.Add("$repo=$(if ($typed -ceq 'YES') { 'YES' } else { 'not YES' })")
    if ($typed -cne 'YES') { Write-Host "Skipped $repo. Nothing changed (the backup file was written, nothing else)." -ForegroundColor Yellow; Add-Result "$repo : skipped by owner"; return }

    $script:Attempted = $true
    try { $res = Send-Put $repo $branch $proposed }
    catch {
        Write-Host "PUT threw: $($_.Exception.GetType().FullName): $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'State unknown - check the repo settings page; restore with AEGIS-Restore-Passing-Checks.cmd.' -ForegroundColor Red
        Add-Result "$repo : FAILED (PUT threw $($_.Exception.Message))"; Set-Worst 1; return
    }
    $afterRaw = Read-ProtectionRaw $repo $branch
    $after = if ($afterRaw) { $afterRaw | ConvertFrom-Json } else { $null }
    $expect = Get-CanonFromBody (ConvertTo-PutBody $cur $extra $m.EnforceAdmins) (Flag $cur 'required_signatures')
    if ($after) { Write-Host "Now     : $(Format-P $after)" }
    if ($res.Ok -and $after -and (Get-Canon $after) -ceq $expect) {
        Write-Host 'DONE and verified against the expected full settings.' -ForegroundColor Green
        Add-Result "$repo : OK verified ($(Format-P $after))"
    } else {
        Write-Host "FAILED or could not verify (PUT ok=$($res.Ok)): $($res.Text)" -ForegroundColor Red
        Write-Host 'Check the repo settings page; the Restore file re-applies the backup.' -ForegroundColor Red
        Add-Result "$repo : FAILED/unverified (PUT ok=$($res.Ok)): $($res.Text)"; Set-Worst 1
    }
}

function Invoke-RestoreRepo($m) {
    $repo = $m.Repo; $branch = $m.Branch
    Write-Host ''
    Write-Host "================ $Owner/$repo ($branch) : restore ================" -ForegroundColor Cyan
    $file = $null
    if ($BackupFile) { $file = $BackupFile }
    else {
        $c = Get-ChildItem -Path $PSScriptRoot -Filter "AEGIS-Require-Checks.$repo.*.backup.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($c) { $file = $c.FullName }
    }
    if (-not $file -or -not (Test-Path $file)) { Write-Host 'No backup file found for this repo (this tool never changed it, or the file was moved). Nothing changed.' -ForegroundColor Yellow; Add-Result "$repo : no backup, skipped"; Set-Worst 4; return }
    $bk = Get-Content -Raw -Path $file | ConvertFrom-Json
    $wantUrl = "https://api.github.com/repos/$Owner/$repo/branches/$branch/protection"
    $gotUrl = [string](Prop $bk 'url')
    if ($gotUrl -cne $wantUrl) {
        Write-Host "REFUSED: backup belongs to a different repo/branch (backup url '$gotUrl', expected '$wantUrl'). Nothing changed." -ForegroundColor Red
        Add-Result "$repo : REFUSED (backup url mismatch)"; Set-Worst 4; return
    }
    $raw = Read-ProtectionRaw $repo $branch
    if ($null -eq $raw) { Write-Host 'REFUSED: branch has no readable protection. Nothing changed.' -ForegroundColor Red; Add-Result "$repo : REFUSED (no readable protection)"; Set-Worst 4; return }
    $cur = $raw | ConvertFrom-Json
    Write-Host "Current : $(Format-P $cur)"
    Write-Host "Backup  : $file"
    Write-Host "Restore : $(Format-P $bk)"
    $script:Plan.Add("restore $repo/$branch from $file")
    $expect = Get-Canon $bk
    if ((Get-Canon $cur) -ceq $expect) { Write-Host 'Already identical to the backup. Nothing to do.' -ForegroundColor Green; Add-Result "$repo : nothing to do (matches backup)"; return }
    if ($WhatIf) { Write-Host '-WhatIf: would restore the backup. Nothing changed.' -ForegroundColor Green; Add-Result "$repo : -WhatIf, would restore"; return }
    $typed = Confirm-Yes "Type YES to restore $repo/$branch from the backup (anything else skips this repo)"
    $script:Typed.Add("$repo=$(if ($typed -ceq 'YES') { 'YES' } else { 'not YES' })")
    if ($typed -cne 'YES') { Write-Host "Skipped $repo." -ForegroundColor Yellow; Add-Result "$repo : skipped by owner"; return }
    $script:Attempted = $true
    try { $res = Send-Put $repo $branch (ConvertTo-PutBody $bk $null $null) }
    catch { Write-Host "PUT threw: $($_.Exception.Message)" -ForegroundColor Red; Add-Result "$repo : FAILED (PUT threw $($_.Exception.Message))"; Set-Worst 1; return }
    $afterRaw = Read-ProtectionRaw $repo $branch
    $after = if ($afterRaw) { $afterRaw | ConvertFrom-Json } else { $null }
    if ($after) { Write-Host "Now     : $(Format-P $after)" }
    if ($res.Ok -and $after -and (Get-Canon $after) -ceq $expect) { Write-Host 'RESTORED and verified against the backup.' -ForegroundColor Green; Add-Result "$repo : RESTORED verified" }
    else { Write-Host "FAILED or could not verify (PUT ok=$($res.Ok)): $($res.Text)" -ForegroundColor Red; Add-Result "$repo : FAILED/unverified (PUT ok=$($res.Ok)): $($res.Text)"; Set-Worst 1 }
}

try {
    Assert-Manifest
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

    $targets = @($Manifest | Where-Object { -not $OnlyRepo -or $_.Repo -ceq $OnlyRepo })
    foreach ($m in $targets) {
        if ($Restore) { Invoke-RestoreRepo $m } else { Invoke-ApplyRepo $m }
        if ($script:Worst -eq 1) { Write-Host 'Stopping: a repo failed, later repos are not touched.' -ForegroundColor Red; break }
    }
    $script:Exit = $script:Worst
    $script:Outcome = "exit $($script:Exit): " + ($script:Results -join ' | ')
}
catch {
    $script:Exception = $_.Exception
    Write-Host "UNEXPECTED EXCEPTION: $($_.Exception.GetType().FullName): $($_.Exception.Message)" -ForegroundColor Red
    $script:Exit = if ($_.Exception.Message.StartsWith('REFUSED-ARG')) { 4 } else { 1 }
    $script:Outcome = "FAILED: unhandled $($_.Exception.GetType().FullName) - $($_.Exception.Message)"
}
finally {
    $real = $script:Attempted
    $log = Join-Path $PSScriptRoot ("{0}.{1}.{2}" -f $Name, $stamp, $(if ($real) { 'log' } else { 'dryrun.log' }))
    $l = New-Object System.Collections.Generic.List[string]
    $l.Add("RUN TYPE: $(if ($real) { 'real' } else { 'dry run (nothing was changed)' })")
    $l.Add("Start (UTC): $startIso")
    $l.Add("Owner: $Owner  Mode: $(if ($Restore) { 'restore' } else { 'apply' })  WhatIf=$($WhatIf.IsPresent)  OnlyRepo=$OnlyRepo")
    $l.Add("Plan: $($script:Plan -join '; ')")
    $l.Add("Owner typed: $(if ($script:Typed.Count) { $script:Typed -join ', ' } else { 'n/a' })")
    $l.Add("Outcome: $script:Outcome")
    if ($script:Exception) { $l.Add($script:Exception.ToString()) }
    try { $l | Out-File -FilePath $log -Encoding utf8; Write-Host "Log: $log" } catch { Write-Host "WARNING: could not write log: $($_.Exception.Message)" -ForegroundColor Yellow }
}
exit $script:Exit
