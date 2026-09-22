<#
.SYNOPSIS
  Regression tests for plan task F12's Ask-Fable.ps1 (the Fable-seat wrapper, docs/
  FABLE_AGENT_SUBAGENT_PLAN.md section 5 "Fable seat").

.DESCRIPTION
  Static only via -DryRun, fixture budgets and throwaway directories/junctions -- no test here
  spends budget or needs `claude` on PATH. Covers: the working-directory refusal (AEGIS dir,
  *.clixml, and the junction/symlink escape probe the plan calls out explicitly), the cold-start
  vs resumed distinction and its budget tiers, and -SessionId validation.
#>
param()

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path (Split-Path -Parent $here) 'headless\Ask-Fable.ps1'

$testsPassed = 0
$testsFailed = 0

function Test-Case($name, $scriptBlock) {
    try {
        & $scriptBlock
        Write-Host "[PASS] $name" -ForegroundColor Green
        $script:testsPassed++
    } catch {
        Write-Host "[FAIL] $name`: $($_.Exception.Message)" -ForegroundColor Red
        $script:testsFailed++
    }
}

Write-Host ""
Write-Host "== F12 regression tests: Ask-Fable.ps1 (Fable seat)" -ForegroundColor Cyan
Write-Host ""

Test-Case "Ask-Fable.ps1 exists" {
    if (-not (Test-Path $scriptPath)) { throw "File not found at $scriptPath" }
}

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("f12-ask-fable-test-" + [Guid]::NewGuid().ToString('N'))
$stateDir = Join-Path $fixtureRoot 'state'
$safeWorkDir = Join-Path $fixtureRoot 'workdir'
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
New-Item -ItemType Directory -Path $safeWorkDir -Force | Out-Null
$budgetsFile = Join-Path $fixtureRoot 'budgets.json'
'{"fableSeat":{"coldUsd":0.77,"resumedUsd":0.03}}' | Set-Content -Path $budgetsFile -Encoding utf8

try {
    Test-Case "not a UUID -SessionId is refused (exit 11), nothing launched" {
        & $scriptPath -SessionId 'nope' -Question 'irrelevant' -WorkingDirectory $safeWorkDir -StateDir $stateDir -BudgetsPath $budgetsFile -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 11) { throw "expected exit 11, got $LASTEXITCODE" }
    }

    Test-Case "a fresh session id is a cold start, using the cold budget tier" {
        $sid = [Guid]::NewGuid().ToString()
        $out = & $scriptPath -SessionId $sid -Question 'irrelevant' -WorkingDirectory $safeWorkDir -StateDir $stateDir -BudgetsPath $budgetsFile -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch 'coldStart=True') { throw "expected coldStart=True. Output: $out" }
        if ($out -notmatch 'resolvedBudget=0.77') { throw "expected the cold tier budget (0.77). Output: $out" }
    }

    Test-Case "a session id already known open resolves to a resume, using the resumed budget tier" {
        $sid = [Guid]::NewGuid().ToString()
        $stateFile = Join-Path $stateDir "$sid.json"
        '{"openedUtc":"2026-01-01T00:00:00Z","lastUsedUtc":"2026-01-01T00:00:00Z"}' | Set-Content -Path $stateFile -Encoding utf8
        $out = & $scriptPath -SessionId $sid -Question 'irrelevant' -WorkingDirectory $safeWorkDir -StateDir $stateDir -BudgetsPath $budgetsFile -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch 'coldStart=False') { throw "expected coldStart=False for a known-open session. Output: $out" }
        if ($out -notmatch 'resolvedBudget=0.03') { throw "expected the resumed tier budget (0.03). Output: $out" }
    }

    Test-Case "-Fork always resolves as a cold start regardless of prior state (fork for speculation)" {
        $sid = [Guid]::NewGuid().ToString()
        $stateFile = Join-Path $stateDir "$sid.json"
        '{"openedUtc":"2026-01-01T00:00:00Z","lastUsedUtc":"2026-01-01T00:00:00Z"}' | Set-Content -Path $stateFile -Encoding utf8
        $out = & $scriptPath -SessionId $sid -Question 'irrelevant' -WorkingDirectory $safeWorkDir -Fork -StateDir $stateDir -BudgetsPath $budgetsFile -DryRun *>&1 | Out-String -Width 4096
        if ($out -notmatch 'coldStart=True') { throw "expected coldStart=True under -Fork. Output: $out" }
        if ($out -notmatch 'fork=True') { throw "expected fork=True. Output: $out" }
    }

    Test-Case "explicit -MaxBudgetUsd overrides the cold/resumed budgets.json lookup" {
        $sid = [Guid]::NewGuid().ToString()
        $out = & $scriptPath -SessionId $sid -Question 'irrelevant' -WorkingDirectory $safeWorkDir -MaxBudgetUsd 5.5 -StateDir $stateDir -BudgetsPath $budgetsFile -DryRun *>&1 | Out-String -Width 4096
        if ($out -notmatch 'resolvedBudget=5.5') { throw "expected the override to win. Output: $out" }
    }

    Test-Case "missing budgets.json with no override fails closed (exit 4)" {
        $sid = [Guid]::NewGuid().ToString()
        & $scriptPath -SessionId $sid -Question 'irrelevant' -WorkingDirectory $safeWorkDir -StateDir $stateDir -BudgetsPath (Join-Path $fixtureRoot 'does-not-exist.json') -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 4) { throw "expected exit 4, got $LASTEXITCODE" }
    }

    Test-Case "working directory under a fixture %APPDATA%-style AEGIS path is refused (exit 10)" {
        # Simulate by pointing APPDATA at a fixture root for the duration of this one call, rather
        # than touching the real %APPDATA%\AEGIS -- this test never reads or writes real AEGIS state.
        $fixtureAppData = Join-Path $fixtureRoot 'fakeappdata'
        $fixtureAegis = Join-Path $fixtureAppData 'AEGIS'
        New-Item -ItemType Directory -Path $fixtureAegis -Force | Out-Null
        $oldAppData = $env:APPDATA
        try {
            $env:APPDATA = $fixtureAppData
            $sid = [Guid]::NewGuid().ToString()
            & $scriptPath -SessionId $sid -Question 'irrelevant' -WorkingDirectory $fixtureAegis -StateDir $stateDir -BudgetsPath $budgetsFile -DryRun 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 10) { throw "expected exit 10, got $LASTEXITCODE" }
        } finally {
            $env:APPDATA = $oldAppData
        }
    }

    Test-Case "working directory containing a *.clixml file is refused (exit 10)" {
        $clixmlDir = Join-Path $fixtureRoot 'clixmldir'
        New-Item -ItemType Directory -Path $clixmlDir -Force | Out-Null
        'dummy' | Set-Content -Path (Join-Path $clixmlDir 'key.clixml') -Encoding utf8
        $sid = [Guid]::NewGuid().ToString()
        & $scriptPath -SessionId $sid -Question 'irrelevant' -WorkingDirectory $clixmlDir -StateDir $stateDir -BudgetsPath $budgetsFile -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 10) { throw "expected exit 10, got $LASTEXITCODE" }
    }

    Test-Case "junction inside the working directory pointing outside it is refused BEFORE launch (escape probe)" {
        $junctionBase = Join-Path $fixtureRoot 'junctionbase'
        $junctionOutside = Join-Path $fixtureRoot 'junctionoutside'
        New-Item -ItemType Directory -Path $junctionBase -Force | Out-Null
        New-Item -ItemType Directory -Path $junctionOutside -Force | Out-Null
        $null = cmd /c mklink /J "$junctionBase\escape" "$junctionOutside" 2>&1
        try {
            $sid = [Guid]::NewGuid().ToString()
            & $scriptPath -SessionId $sid -Question 'irrelevant' -WorkingDirectory $junctionBase -StateDir $stateDir -BudgetsPath $budgetsFile -DryRun 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 10) { throw "expected exit 10, got $LASTEXITCODE" }
        } finally {
            Remove-Item -LiteralPath "$junctionBase\escape" -Force -ErrorAction SilentlyContinue
        }
    }

    Test-Case "a plain safe working directory with no AEGIS/clixml/reparse point is allowed" {
        $sid = [Guid]::NewGuid().ToString()
        & $scriptPath -SessionId $sid -Question 'irrelevant' -WorkingDirectory $safeWorkDir -StateDir $stateDir -BudgetsPath $budgetsFile -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0 for a safe working directory, got $LASTEXITCODE" }
    }
} finally {
    Remove-Item -Recurse -Force $fixtureRoot -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "== Results: $testsPassed passed, $testsFailed failed ==" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host ""

if ($testsFailed -gt 0) { exit 1 } else { exit 0 }
