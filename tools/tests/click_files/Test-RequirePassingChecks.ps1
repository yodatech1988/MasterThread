<#
.SYNOPSIS
  Offline tests for tools/click-files/AEGIS-Require-Passing-Checks.ps1 (Windows PowerShell 5.1, no Pester).
  Windows PowerShell only, and NOT run by CI: run it by hand (powershell -File <this file>) after any change to the click-file.
  Every case copies the script into a fresh temp dir and runs it against a MOCK `gh` function. The real
  GitHub API is never called and the script is never pointed at a real repo.
  Prints PASS/FAIL per case and a final count; exits 1 if any case fails.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ScriptSrc = (Resolve-Path (Join-Path $PSScriptRoot '..\..\click-files\AEGIS-Require-Passing-Checks.ps1')).Path
$FixDir = (Resolve-Path (Join-Path $PSScriptRoot '..\fixtures\click_files')).Path
$Owner = 'yodatech1988'
$Scratch = 'srt-scratch-checks-test-1'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ---------------------------------------------------------------- mock gh
function global:gh {
    $a = @($args)
    $M = $global:GhMock
    [void]$M.Calls.Add(($a -join ' '))
    if ($a.Count -eq 0) { $global:LASTEXITCODE = 1; return }
    if ($a[0] -eq 'auth') { $global:LASTEXITCODE = 0; return }
    if ($a[0] -ne 'api') { $global:LASTEXITCODE = 1; return }
    $method = 'GET'; $path = $null; $inFile = $null; $jq = $null
    for ($i = 1; $i -lt $a.Count; $i++) {
        $t = [string]$a[$i]
        if ($t -ceq '-X') { $i++; $method = [string]$a[$i] }
        elseif ($t -ceq '--input') { $i++; $inFile = [string]$a[$i] }
        elseif ($t -ceq '--jq') { $i++; $jq = [string]$a[$i] }
        elseif (-not $path) { $path = $t }
    }
    if ($path -notmatch '^repos/yodatech1988/([^/?]+)(?:/(.*))?$') { $global:LASTEXITCODE = 1; return }
    $repoName = $Matches[1]; $rest = $Matches[2]
    if (-not $M.Repos.ContainsKey($repoName)) { $global:LASTEXITCODE = 1; return }
    $r = $M.Repos[$repoName]
    $global:LASTEXITCODE = 0
    if (-not $rest) {
        if ($jq -eq '.default_branch') { Write-Output $r.Default } else { Write-Output (@{ default_branch = $r.Default } | ConvertTo-Json -Compress) }
        return
    }
    if ($rest -match '^branches/([^/]+)/protection$') {
        if ($method -eq 'PUT') {
            $txt = [IO.File]::ReadAllText($inFile)
            $b = $txt | ConvertFrom-Json
            [void]$M.Puts.Add(@{ Repo = $repoName; Body = $b; Text = $txt })
            if ($r.PutFail) { Write-Output 'HTTP 422: mock PUT failure'; $global:LASTEXITCODE = 1; return }
            $s = $r.Raw | ConvertFrom-Json
            $base = "https://api.github.com/repos/yodatech1988/$repoName/branches/main/protection"
            if ($null -eq $b.required_status_checks) { [void]$s.PSObject.Properties.Remove('required_status_checks') }
            else {
                $chk = @(@($b.required_status_checks.checks) | ForEach-Object { [pscustomobject]@{ context = $_.context; app_id = $_.app_id } })
                $new = [pscustomobject]@{ url = "$base/required_status_checks"; strict = [bool]$b.required_status_checks.strict; checks = $chk }
                $s | Add-Member -NotePropertyName required_status_checks -NotePropertyValue $new -Force
            }
            if (-not $r.IgnoreEnforce) {
                $s | Add-Member -NotePropertyName enforce_admins -NotePropertyValue ([pscustomobject]@{ url = "$base/enforce_admins"; enabled = [bool]$b.enforce_admins }) -Force
            }
            foreach ($f in 'required_linear_history', 'allow_force_pushes', 'allow_deletions', 'block_creations', 'required_conversation_resolution', 'lock_branch', 'allow_fork_syncing') {
                $s | Add-Member -NotePropertyName $f -NotePropertyValue ([pscustomobject]@{ enabled = [bool]$b.$f }) -Force
            }
            foreach ($f in 'required_pull_request_reviews', 'restrictions') {
                if ($null -eq $b.$f) { [void]$s.PSObject.Properties.Remove($f) }
                else { $s | Add-Member -NotePropertyName $f -NotePropertyValue $b.$f -Force }
            }
            $r.Raw = ($s | ConvertTo-Json -Depth 10 -Compress)
            Write-Output '{"ok":true}'
            return
        }
        if ($null -eq $r.Raw) { $global:LASTEXITCODE = 1; return }
        Write-Output $r.Raw
        return
    }
    if ($rest -match '^commits/([^/?]+)/check-runs') {
        $sha = $Matches[1]
        $runs = @()
        if ($r.Runs.ContainsKey($sha)) {
            $runs = @($r.Runs[$sha] | ForEach-Object {
                    [pscustomobject]@{ name = $_.name; status = 'completed'; conclusion = $_.conclusion; app = [pscustomobject]@{ id = $_.app_id }; completed_at = $_.completed_at }
                })
        }
        Write-Output (ConvertTo-Json -InputObject ([pscustomobject]@{ check_runs = $runs }) -Depth 6 -Compress)
        return
    }
    if ($rest -match '^commits\?') {
        $c = @($r.Commits | ForEach-Object { [pscustomobject]@{ sha = $_ } })
        Write-Output (ConvertTo-Json -InputObject $c -Depth 4 -Compress)
        return
    }
    if ($rest -match '^pulls\?') {
        $p = @($r.Pulls | ForEach-Object { [pscustomobject]@{ number = $_.number; merged_at = $_.merged_at; head = [pscustomobject]@{ sha = $_.head_sha } } })
        Write-Output (ConvertTo-Json -InputObject $p -Depth 4 -Compress)
        return
    }
    $global:LASTEXITCODE = 1
}

# ---------------------------------------------------------------- helpers
function Read-Fixture([string]$name, [string]$toRepo) {
    $t = [IO.File]::ReadAllText((Join-Path $FixDir $name))
    if ($toRepo) { $t = $t -replace 'repos/yodatech1988/[a-z\-]+/', "repos/yodatech1988/$toRepo/" }
    return $t
}

# A repo whose named checks are green on 5 push commits and 3 merged PR heads (plus one closed, unmerged red PR).
function New-RepoMock([string]$Raw, [string[]]$Checks, [int]$App = 15368, [int]$Commits = 5) {
    $r = @{ Default = 'main'; Raw = $Raw; Commits = @(); Runs = @{}; Pulls = @(); PutFail = $false; IgnoreEnforce = $false }
    for ($i = 0; $i -lt $Commits; $i++) {
        $sha = ('c0{0}' -f $i).PadRight(40, '0'); $r.Commits += $sha
        $r.Runs[$sha] = @($Checks | ForEach-Object { @{ name = $_; conclusion = 'success'; app_id = $App; completed_at = '2026-09-10T00:00:00Z' } })
    }
    for ($i = 0; $i -lt 3; $i++) {
        $sha = ('b0{0}' -f $i).PadRight(40, '0')
        $r.Pulls += @{ number = (12 - $i); merged_at = ('2026-09-{0}T00:00:00Z' -f (15 - $i)); head_sha = $sha }
        $r.Runs[$sha] = @($Checks | ForEach-Object { @{ name = $_; conclusion = 'success'; app_id = $App; completed_at = '2026-09-10T00:00:00Z' } })
    }
    $bad = ('d00').PadRight(40, '0')
    $r.Pulls += @{ number = 99; merged_at = $null; head_sha = $bad }
    $r.Runs[$bad] = @($Checks | ForEach-Object { @{ name = $_; conclusion = 'failure'; app_id = $App; completed_at = '2026-09-10T00:00:00Z' } })
    return $r
}
function Sha([string]$p, [int]$i) { return ('{0}{1}' -f $p, $i).PadRight(40, '0') }

function New-TestEnv([hashtable]$Repos) {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("srt-cpc-test-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir | Out-Null
    $dst = Join-Path $dir 'AEGIS-Require-Passing-Checks.ps1'
    Copy-Item $ScriptSrc $dst
    $script:Dirs += $dir
    $global:GhMock = @{ Repos = $Repos; Puts = (New-Object System.Collections.ArrayList); Calls = (New-Object System.Collections.ArrayList) }
    return @{ Dir = $dir; Script = $dst }
}
function Invoke-Under($env, [hashtable]$p) {
    $global:LASTEXITCODE = 0
    $out = & $env.Script @p *>&1
    $code = $LASTEXITCODE
    return @{ Exit = $code; Out = (($out | Out-String)) }
}
function Get-Files($env) { return @(Get-ChildItem $env.Dir -File | Where-Object { $_.Name -ne 'AEGIS-Require-Passing-Checks.ps1' }) }
function Get-Backups($env) { return ,@(Get-Files $env | Where-Object { $_.Name -like '*.backup.json' }) }
function Get-DryLogs($env) { return ,@(Get-Files $env | Where-Object { $_.Name -like '*.dryrun.log' }) }
function Get-RealLogs($env) { return ,@(Get-Files $env | Where-Object { $_.Name -like '*.log' -and $_.Name -notlike '*.dryrun.log' }) }
function First-Line($f) { return (Get-Content -Path $f.FullName -TotalCount 1) }
function Put-Count { return $global:GhMock.Puts.Count }

function Add-Flat($v, $path, $acc) {
    if ($null -eq $v) { $acc.Add("$path=null"); return }
    if ($v -is [pscustomobject]) {
        foreach ($n in ($v.PSObject.Properties.Name | Sort-Object)) { if ($n -ne 'url' -and $n -ne 'contexts' -and $n -ne 'contexts_url') { Add-Flat $v.$n "$path.$n" $acc } }
        return
    }
    if ($v -is [System.Collections.IEnumerable] -and $v -isnot [string]) { $i = 0; foreach ($e in $v) { Add-Flat $e "$path[$i]" $acc; $i++ }; return }
    $acc.Add("$path=$v")
}
# canonical form of a GET protection json: url-ish keys dropped, checks sorted, absent rsc == absent
function Canon([string]$json) {
    $o = $json | ConvertFrom-Json
    if ($o.PSObject.Properties['required_status_checks']) {
        $o.required_status_checks.checks = @(@($o.required_status_checks.checks) | Sort-Object { $_.context })
    }
    $acc = New-Object System.Collections.Generic.List[string]
    Add-Flat $o 'p' $acc
    return ($acc -join "`n")
}

$script:CaseFails = @()
function Check($cond, [string]$msg) { if (-not $cond) { $script:CaseFails += $msg } }
$script:Total = 0; $script:Failed = 0; $script:Dirs = @()
function Case([string]$name, [scriptblock]$body) {
    $script:CaseFails = @(); $script:Total++
    try { & $body } catch { $script:CaseFails += "EXCEPTION: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" }
    if ($script:CaseFails.Count -eq 0) { Write-Host "PASS  $name" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "FAIL  $name" -ForegroundColor Red; foreach ($f in $script:CaseFails) { Write-Host "        - $f" -ForegroundColor Red } }
}

$ScratchArgs = @{ ScratchRepo = $Scratch; ScratchChecks = 'test'; AssumeYes = $true }
function New-OpsScratch { return New-RepoMock (Read-Fixture 'protection.ops-household.json' $Scratch) @('test') }

try {
    # ---------------------------------------------------------------- 1
    Case '1 WhatIf real manifest, all green: no PUT, no backup, dryrun log' {
        $ops = New-RepoMock (Read-Fixture 'protection.ops-household.json') @('test')
        $svc = New-RepoMock (Read-Fixture 'protection.services.json') @('admin-bot', 'gateway', 'ops-db', 'economy-db', 'economy-loot-db')
        $e = New-TestEnv @{ 'ops-household' = $ops; 'services' = $svc }
        $r = Invoke-Under $e @{ WhatIf = $true }
        Check ($r.Exit -eq 0) "exit $($r.Exit) expected 0`n$($r.Out)"
        Check ((Put-Count) -eq 0) "PUT count $(Put-Count)"
        Check ((Get-Backups $e).Count -eq 0) 'backup file written on WhatIf'
        Check ((Get-RealLogs $e).Count -eq 0) 'real log written on WhatIf'
        $d = Get-DryLogs $e
        Check ($d.Count -eq 1) "dryrun.log count $($d.Count)"
        if ($d.Count -eq 1) { Check ((First-Line $d[0]) -ceq 'RUN TYPE: dry run (nothing was changed)') "first line: $(First-Line $d[0])" }
        Check ($r.Out -match 'ops-household : -WhatIf, would apply') 'ops-household not "would apply"'
        Check ($r.Out -match 'services : -WhatIf, would apply') 'services not "would apply"'
    }

    # ---------------------------------------------------------------- 2 + 5
    $orig = Read-Fixture 'protection.ops-household.json' $Scratch
    $e2 = $null
    Case '2 apply via scratch mode' {
        $e2 = New-TestEnv @{ $Scratch = (New-OpsScratch) }
        $script:E2 = $e2
        $r = Invoke-Under $e2 $ScratchArgs
        Check ($r.Exit -eq 0) "exit $($r.Exit) expected 0`n$($r.Out)"
        Check ((Put-Count) -eq 1) "PUT count $(Put-Count) expected 1"
        if ((Put-Count) -ge 1) {
            $b = $global:GhMock.Puts[0].Body
            $fx = $orig | ConvertFrom-Json
            $c = @($b.required_status_checks.checks)
            Check ($c.Count -eq 1 -and $c[0].context -ceq 'test' -and [int]$c[0].app_id -eq 15368) 'checks not exactly [test/15368]'
            Check ($b.enforce_admins -eq $true) 'enforce_admins not true'
            $rp = $fx.required_pull_request_reviews
            foreach ($k in 'dismiss_stale_reviews', 'require_code_owner_reviews', 'require_last_push_approval', 'required_approving_review_count') {
                Check ($b.required_pull_request_reviews.$k -eq $rp.$k) "required_pull_request_reviews.$k differs"
            }
            foreach ($k in 'required_linear_history', 'allow_force_pushes', 'allow_deletions', 'block_creations', 'required_conversation_resolution', 'lock_branch', 'allow_fork_syncing') {
                Check ($b.$k -eq $fx.$k.enabled) "$k differs from fixture"
            }
            Check ($null -eq $b.restrictions) 'restrictions not null'
            Check ($b.required_status_checks.strict -eq $false) 'strict changed'
        }
        $bk = Get-Backups $e2
        Check ($bk.Count -eq 1) "backup count $($bk.Count)"
        if ($bk.Count -eq 1) {
            $want = $Utf8NoBom.GetBytes($orig)
            $got = [IO.File]::ReadAllBytes($bk[0].FullName)
            Check ((@($want) -join ',') -ceq (@($got) -join ',')) 'backup not byte-identical to raw fixture'
        }
        Check ((Get-DryLogs $e2).Count -eq 0) 'dryrun log present after real run'
        $l = Get-RealLogs $e2
        Check ($l.Count -eq 1) "real log count $($l.Count)"
        if ($l.Count -eq 1) { Check ((First-Line $l[0]) -ceq 'RUN TYPE: real') "first line: $(First-Line $l[0])" }
        Check ($r.Out -match 'DONE and verified') 'no "DONE and verified"'
    }

    Case '5 restore after case 2 restores exactly' {
        $e = $script:E2
        $global:GhMock.Puts.Clear()
        $r = Invoke-Under $e @{ Restore = $true; OnlyRepo = $Scratch; ScratchRepo = $Scratch; ScratchChecks = 'test'; AssumeYes = $true }
        Check ($r.Exit -eq 0) "exit $($r.Exit) expected 0`n$($r.Out)"
        Check ((Put-Count) -eq 1) "PUT count $(Put-Count) expected 1"
        Check ((Canon $global:GhMock.Repos[$Scratch].Raw) -ceq (Canon $orig)) 'mock state not canonical-equal to original fixture'
        $l = @(Get-Files $e | Where-Object { $_.Name -like 'AEGIS-Restore-Passing-Checks.*.log' -and $_.Name -notlike '*.dryrun.log' })
        Check ($l.Count -eq 1) "restore real log count $($l.Count)"
        if ($l.Count -eq 1) { Check ((First-Line $l[0]) -ceq 'RUN TYPE: real') "first line: $(First-Line $l[0])" }
        Check ($r.Out -match 'RESTORED verified') 'no "RESTORED verified"'
    }

    # ---------------------------------------------------------------- 3
    $guardCases = [ordered]@{
        'check absent on newest commit'          = { param($r) $r.Runs[$r.Commits[0]] = @() }
        'failure on 2nd newest commit'           = { param($r) $r.Runs[$r.Commits[1]] = @(@{ name = 'test'; conclusion = 'failure'; app_id = 15368; completed_at = '2026-09-10T00:00:00Z' }) }
        'green on push but absent on merged PRs' = { param($r) foreach ($p in $r.Pulls) { $r.Runs[$p.head_sha] = @() } }
        'no merged PRs at all'                   = { param($r) $r.Pulls = @(@{ number = 99; merged_at = $null; head_sha = (Sha 'd0' 0) }) }
        'two different app ids'                  = { param($r) $r.Runs[$r.Commits[2]] = @(@{ name = 'test'; conclusion = 'success'; app_id = 999; completed_at = '2026-09-10T00:00:00Z' }) }
        'only 2 commits'                         = { param($r) $r.Commits = @($r.Commits[0], $r.Commits[1]) }
    }
    foreach ($k in $guardCases.Keys) {
        Case "3 guard refusal: $k" {
            $repo = New-OpsScratch
            & $guardCases[$k] $repo
            $e = New-TestEnv @{ $Scratch = $repo }
            $r = Invoke-Under $e $ScratchArgs
            Check ($r.Exit -eq 3) "exit $($r.Exit) expected 3`n$($r.Out)"
            Check ((Put-Count) -eq 0) "PUT count $(Put-Count)"
            Check ((Get-Backups $e).Count -eq 0) 'backup written despite refusal'
            Check ((Get-DryLogs $e).Count -eq 1) 'dryrun.log missing'
            Check ((Get-RealLogs $e).Count -eq 0) 'real log written despite refusal'
            Check ($r.Out -match 'REFUSED \(guard\)') 'no REFUSED (guard) in output'
        }
    }
    Case '3 guard: an old failure followed by a later success counts as green (latest run wins)' {
        $repo = New-OpsScratch
        $repo.Runs[$repo.Commits[0]] = @(
            @{ name = 'test'; conclusion = 'failure'; app_id = 15368; completed_at = '2026-09-09T00:00:00Z' },
            @{ name = 'test'; conclusion = 'success'; app_id = 15368; completed_at = '2026-09-10T00:00:00Z' })
        $e = New-TestEnv @{ $Scratch = $repo }
        $r = Invoke-Under $e $ScratchArgs
        Check ($r.Exit -eq 0) "exit $($r.Exit) expected 0`n$($r.Out)"
        Check ((Put-Count) -eq 1) "PUT count $(Put-Count)"
    }

    # ---------------------------------------------------------------- 4
    foreach ($bad in 'secret-scan', 'gate / gate', 'review', 'Secret-Scan') {
        Case "4 never-require list: '$bad'" {
            $e = New-TestEnv @{ $Scratch = (New-RepoMock (Read-Fixture 'protection.ops-household.json' $Scratch) @($bad)) }
            $r = Invoke-Under $e @{ ScratchRepo = $Scratch; ScratchChecks = $bad; AssumeYes = $true }
            Check ($r.Exit -eq 4) "exit $($r.Exit) expected 4`n$($r.Out)"
            Check ((Put-Count) -eq 0) "PUT count $(Put-Count)"
            Check ((Get-Backups $e).Count -eq 0) 'backup written'
            Check ($r.Out -match 'never-require') 'output does not mention never-require list'
        }
    }

    # ---------------------------------------------------------------- 6
    Case '6 restore refuses a backup whose url names another repo' {
        $e = New-TestEnv @{ $Scratch = (New-OpsScratch) }
        # backup content still says ops-household
        [IO.File]::WriteAllText((Join-Path $e.Dir "AEGIS-Require-Checks.$Scratch.20260919-000000.backup.json"), (Read-Fixture 'protection.ops-household.json'), $Utf8NoBom)
        $r = Invoke-Under $e @{ Restore = $true; OnlyRepo = $Scratch; ScratchRepo = $Scratch; ScratchChecks = 'test'; AssumeYes = $true }
        Check ($r.Exit -eq 4) "exit $($r.Exit) expected 4`n$($r.Out)"
        Check ((Put-Count) -eq 0) "PUT count $(Put-Count)"
        Check ($r.Out -match 'different repo') 'no "different repo" message'
    }

    # ---------------------------------------------------------------- 7
    Case '7 non-interactive real run (stdin=NUL child process) is refused with exit 2' {
        $e = New-TestEnv @{}
        $stub = Join-Path $e.Dir 'stub'
        New-Item -ItemType Directory $stub | Out-Null
        Set-Content -Path (Join-Path $stub 'gh.cmd') -Value '@exit /b 1' -Encoding ascii   # any gh use in the child fails, never reaches GitHub
        $oldPath = $env:PATH
        try {
            $env:PATH = "$stub;$oldPath"
            $global:LASTEXITCODE = 0
            $cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}" < NUL' -f $e.Script
            $out = & cmd.exe /c $cmd 2>&1 | Out-String
            $code = $LASTEXITCODE
        } finally { $env:PATH = $oldPath }
        Check ($code -eq 2) "exit $code expected 2`n$out"
        Check ($out -match 'REFUSED') 'no REFUSED text'
        Check ((Get-DryLogs $e).Count -eq 1) 'dryrun.log missing'
        Check ((Get-RealLogs $e).Count -eq 0) 'real log written'
        Check ((Get-Backups $e).Count -eq 0) 'backup written'
    }

    # ---------------------------------------------------------------- 8
    Case '8 PUT fails: exit 1, real log' {
        $repo = New-OpsScratch; $repo.PutFail = $true
        $e = New-TestEnv @{ $Scratch = $repo }
        $r = Invoke-Under $e $ScratchArgs
        Check ($r.Exit -eq 1) "exit $($r.Exit) expected 1`n$($r.Out)"
        Check ((Put-Count) -eq 1) "PUT count $(Put-Count) expected 1"
        $l = Get-RealLogs $e
        Check ($l.Count -eq 1) "real log count $($l.Count)"
        if ($l.Count -eq 1) { Check ((First-Line $l[0]) -ceq 'RUN TYPE: real') "first line: $(First-Line $l[0])" }
        Check ((Get-DryLogs $e).Count -eq 0) 'dryrun log present'
    }

    # ---------------------------------------------------------------- 9
    Case '9 verify mismatch (enforce_admins ignored by GitHub): exit 1' {
        $repo = New-OpsScratch; $repo.IgnoreEnforce = $true
        $e = New-TestEnv @{ $Scratch = $repo }
        $r = Invoke-Under $e $ScratchArgs
        Check ($r.Exit -eq 1) "exit $($r.Exit) expected 1`n$($r.Out)"
        Check ((Put-Count) -eq 1) "PUT count $(Put-Count)"
        Check ($r.Out -match 'FAILED') 'no FAILED text'
    }

    # ---------------------------------------------------------------- 10
    Case '10 idempotence: check present and enforce_admins true: nothing to do' {
        $s = (Read-Fixture 'protection.ops-household.json' $Scratch) | ConvertFrom-Json
        $s | Add-Member -NotePropertyName required_status_checks -NotePropertyValue ([pscustomobject]@{ strict = $false; checks = @([pscustomobject]@{ context = 'test'; app_id = 15368 }) }) -Force
        $s.enforce_admins.enabled = $true
        $e = New-TestEnv @{ $Scratch = (New-RepoMock ($s | ConvertTo-Json -Depth 10 -Compress) @('test')) }
        $r = Invoke-Under $e $ScratchArgs
        Check ($r.Exit -eq 0) "exit $($r.Exit) expected 0`n$($r.Out)"
        Check ((Put-Count) -eq 0) "PUT count $(Put-Count)"
        Check ($r.Out -match 'Nothing to do') 'output does not say nothing to do'
        Check ((Get-Backups $e).Count -eq 0) 'backup written'
    }

    # ---------------------------------------------------------------- 11
    Case '11 existing checks kept (website): secret-scan+build kept with app 15368, strict, build_extra added' {
        $raw = Read-Fixture 'protection.website.json' $Scratch
        $e = New-TestEnv @{ $Scratch = (New-RepoMock $raw @('build_extra')) }
        $r = Invoke-Under $e @{ ScratchRepo = $Scratch; ScratchChecks = 'build_extra'; AssumeYes = $true }
        Check ($r.Exit -eq 0) "exit $($r.Exit) expected 0`n$($r.Out)"
        Check ((Put-Count) -eq 1) "PUT count $(Put-Count)"
        if ((Put-Count) -ge 1) {
            $b = $global:GhMock.Puts[0].Body
            $c = @($b.required_status_checks.checks)
            Check ($c.Count -eq 3) "checks count $($c.Count) expected 3"
            foreach ($n in 'secret-scan', 'build', 'build_extra') {
                $m = @($c | Where-Object { $_.context -ceq $n })
                Check ($m.Count -eq 1 -and [int]$m[0].app_id -eq 15368) "check $n missing or app_id != 15368"
            }
            Check ($b.required_status_checks.strict -eq $true) 'strict not kept true'
            Check ($b.enforce_admins -eq $true) 'enforce_admins not true'
            Check ($b.required_pull_request_reviews.dismiss_stale_reviews -eq $true) 'dismiss_stale_reviews not kept'
        }
    }
    Case '11b required check with app_id null in GET is sent as -1' {
        $s = (Read-Fixture 'protection.website.json' $Scratch) | ConvertFrom-Json
        $s.required_status_checks.checks[1].app_id = $null   # build
        $e = New-TestEnv @{ $Scratch = (New-RepoMock ($s | ConvertTo-Json -Depth 10 -Compress) @('build_extra')) }
        $r = Invoke-Under $e @{ ScratchRepo = $Scratch; ScratchChecks = 'build_extra'; AssumeYes = $true }
        Check ($r.Exit -eq 0) "exit $($r.Exit) expected 0`n$($r.Out)"
        if ((Put-Count) -ge 1) {
            $c = @($global:GhMock.Puts[0].Body.required_status_checks.checks)
            $m = @($c | Where-Object { $_.context -ceq 'build' })
            Check ($m.Count -eq 1 -and [int]$m[0].app_id -eq -1) 'null app_id not sent as -1'
            $m2 = @($c | Where-Object { $_.context -ceq 'secret-scan' })
            Check ($m2.Count -eq 1 -and [int]$m2[0].app_id -eq 15368) 'secret-scan app_id changed'
        } else { Check $false 'no PUT recorded' }
    }

    # ---------------------------------------------------------------- 12
    Case '12a -OnlyRepo not in manifest: exit 4' {
        $e = New-TestEnv @{}
        $r = Invoke-Under $e @{ WhatIf = $true; OnlyRepo = 'jarvis' }
        Check ($r.Exit -eq 4) "exit $($r.Exit) expected 4`n$($r.Out)"
        Check ((Put-Count) -eq 0) "PUT count $(Put-Count)"
    }
    Case '12d -BackupFile without -OnlyRepo is refused: exit 4' {
        $e = New-TestEnv @{}
        $r = Invoke-Under $e @{ Restore = $true; WhatIf = $true; BackupFile = 'C:\nowhere\x.backup.json' }
        Check ($r.Exit -eq 4) "exit $($r.Exit) expected 4`n$($r.Out)"
        Check ("$($r.Out)" -match 'REFUSED-ARG: -BackupFile needs -OnlyRepo') "refused for the wrong reason:`n$($r.Out)"
        Check ((Put-Count) -eq 0) "PUT count $(Put-Count)"
    }
    foreach ($bad in 'srt-scratch-checks-test-', 'srt-scratch-checks-test-UPPER', 'srt-scratch-checks-test-a/../b', 'srt-scratch-checks-test-x_y', 'srt-scratch-checks-test-ok ', 'Srt-scratch-checks-test-ok') {
        Case "12e scratch name '$bad' fails the whole-name pattern: exit 4, no PUT" {
            $e = New-TestEnv @{}
            $r = Invoke-Under $e @{ ScratchRepo = $bad; ScratchChecks = @('test'); AssumeYes = $true }
            Check ($r.Exit -eq 4) "exit $($r.Exit) expected 4`n$($r.Out)"
            # Exit 4 alone is not proof: a missing mock repo also exits 4 (branch mismatch). Require the pattern refusal itself.
            Check ("$($r.Out)" -match 'REFUSED-ARG: -ScratchRepo must match') "refused for the wrong reason:`n$($r.Out)"
            Check ((Put-Count) -eq 0) "PUT count $(Put-Count)"
        }
    }
    Case '12f real deny names are refused: review / review, review / automerge' {
        foreach ($n in 'review / review', 'review / automerge') {
            $e = New-TestEnv @{}
            $r = Invoke-Under $e @{ ScratchRepo = 'srt-scratch-checks-test-1'; ScratchChecks = @($n); AssumeYes = $true }
            Check ($r.Exit -eq 4) "'$n': exit $($r.Exit) expected 4`n$($r.Out)"
            Check ("$($r.Out)" -match 'never-require list') "'$n': refused for the wrong reason:`n$($r.Out)"
            Check ((Put-Count) -eq 0) "'$n': PUT count $(Put-Count)"
        }
    }
    Case '12b unprotected repo (GET protection fails): exit 4' {
        $repo = New-OpsScratch; $repo.Raw = $null
        $e = New-TestEnv @{ $Scratch = $repo }
        $r = Invoke-Under $e $ScratchArgs
        Check ($r.Exit -eq 4) "exit $($r.Exit) expected 4`n$($r.Out)"
        Check ((Put-Count) -eq 0) "PUT count $(Put-Count)"
        Check ((Get-Backups $e).Count -eq 0) 'backup written'
    }
    Case '12c default-branch mismatch: exit 4' {
        $repo = New-OpsScratch; $repo.Default = 'master'
        $e = New-TestEnv @{ $Scratch = $repo }
        $r = Invoke-Under $e $ScratchArgs
        Check ($r.Exit -eq 4) "exit $($r.Exit) expected 4`n$($r.Out)"
        Check ((Put-Count) -eq 0) "PUT count $(Put-Count)"
    }

    # ---------------------------------------------------------------- 13
    Case '13 two-repo WhatIf: ops-household guard fails, services passes -> exit 3' {
        $ops = New-RepoMock (Read-Fixture 'protection.ops-household.json') @('test')
        $ops.Runs[$ops.Commits[1]] = @(@{ name = 'test'; conclusion = 'failure'; app_id = 15368; completed_at = '2026-09-10T00:00:00Z' })
        $svc = New-RepoMock (Read-Fixture 'protection.services.json') @('admin-bot', 'gateway', 'ops-db', 'economy-db', 'economy-loot-db')
        $e = New-TestEnv @{ 'ops-household' = $ops; 'services' = $svc }
        $r = Invoke-Under $e @{ WhatIf = $true }
        Check ($r.Exit -eq 3) "exit $($r.Exit) expected 3`n$($r.Out)"
        Check ((Put-Count) -eq 0) "PUT count $(Put-Count)"
        Check ($r.Out -match 'ops-household : REFUSED \(guard\)') 'ops-household not REFUSED'
        Check ($r.Out -match 'services : -WhatIf, would apply') 'services not "would apply"'
        Check ((Get-Backups $e).Count -eq 0) 'backup written'
        $d = Get-DryLogs $e
        Check ($d.Count -eq 1) 'dryrun.log missing'
    }
}
finally {
    Remove-Item Function:\gh -ErrorAction SilentlyContinue
    Remove-Variable -Name GhMock -Scope Global -ErrorAction SilentlyContinue
    foreach ($d in $script:Dirs) { Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host ("{0} cases, {1} passed, {2} failed" -f $script:Total, ($script:Total - $script:Failed), $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
