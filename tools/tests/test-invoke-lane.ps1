<#
.SYNOPSIS
  Regression tests for plan task F12's Invoke-Lane.ps1 (owner decision E7: maxTurns and budget
  enforcement fold into F12).

.DESCRIPTION
  Static only via -DryRun and fixture state/budgets directories -- no test here spends budget or
  needs `claude` on PATH.
#>
param()

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path (Split-Path -Parent $here) 'headless\Invoke-Lane.ps1'

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
Write-Host "== F12 regression tests: Invoke-Lane.ps1 (maxTurns + budget enforcement)" -ForegroundColor Cyan
Write-Host ""

Test-Case "Invoke-Lane.ps1 exists" {
    if (-not (Test-Path $scriptPath)) { throw "File not found at $scriptPath" }
}

$fixtureDir = Join-Path ([System.IO.Path]::GetTempPath()) ("f12-invoke-lane-test-" + [Guid]::NewGuid().ToString('N'))
$stateDir = Join-Path $fixtureDir 'lanes'
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
$budgetsFile = Join-Path $fixtureDir 'budgets.json'
'{"lane":{"sonnet":1.23,"opus":4.56,"default":0.50}}' | Set-Content -Path $budgetsFile -Encoding utf8

try {
    Test-Case "neither -AgentName nor -Tools given: fails closed (exit 5), nothing launched" {
        $sid = [Guid]::NewGuid().ToString()
        & $scriptPath -SessionId $sid -Prompt 'irrelevant' -MaxTurns 5 -StateDir $stateDir -BudgetsPath $budgetsFile -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 5) { throw "expected exit 5, got $LASTEXITCODE" }
    }

    Test-Case "not a UUID -SessionId is refused (exit 2), nothing launched" {
        & $scriptPath -SessionId 'not-a-uuid!' -Prompt 'irrelevant' -MaxTurns 5 -Tools 'Read' -StateDir $stateDir -BudgetsPath $budgetsFile -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 2) { throw "expected exit 2, got $LASTEXITCODE" }
    }

    Test-Case "first call for a fresh session id is turn 1, isFirstTurn=True" {
        $sid = [Guid]::NewGuid().ToString()
        $out = & $scriptPath -SessionId $sid -Prompt 'irrelevant' -MaxTurns 5 -Tools 'Read' -Model sonnet -StateDir $stateDir -BudgetsPath $budgetsFile -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch 'turn=1/5') { throw "expected turn=1/5. Output: $out" }
        if ($out -notmatch 'isFirstTurn=True') { throw "expected isFirstTurn=True. Output: $out" }
    }

    Test-Case "budget resolved from budgets.json by model tier (sonnet)" {
        $sid = [Guid]::NewGuid().ToString()
        $out = & $scriptPath -SessionId $sid -Prompt 'irrelevant' -MaxTurns 5 -Tools 'Read' -Model sonnet -StateDir $stateDir -BudgetsPath $budgetsFile -DryRun *>&1 | Out-String -Width 4096
        if ($out -notmatch 'resolvedBudget=1.23') { throw "expected resolvedBudget=1.23. Output: $out" }
    }

    Test-Case "budget resolved from budgets.json by model tier (opus)" {
        $sid = [Guid]::NewGuid().ToString()
        $out = & $scriptPath -SessionId $sid -Prompt 'irrelevant' -MaxTurns 5 -Tools 'Read' -Model opus -StateDir $stateDir -BudgetsPath $budgetsFile -DryRun *>&1 | Out-String -Width 4096
        if ($out -notmatch 'resolvedBudget=4.56') { throw "expected resolvedBudget=4.56. Output: $out" }
    }

    Test-Case "no model given falls back to 'default' tier budget" {
        $sid = [Guid]::NewGuid().ToString()
        $out = & $scriptPath -SessionId $sid -Prompt 'irrelevant' -MaxTurns 5 -Tools 'Read' -StateDir $stateDir -BudgetsPath $budgetsFile -DryRun *>&1 | Out-String -Width 4096
        if ($out -notmatch 'resolvedBudget=0.5') { throw "expected resolvedBudget=0.5. Output: $out" }
    }

    Test-Case "MaxTurns enforcement: a session already at its cap is REFUSED (exit 9) before launch, counter unchanged" {
        $sid = [Guid]::NewGuid().ToString()
        $stateFile = Join-Path $stateDir "$sid.turns.json"
        '{"turnsUsed":3,"lastUpdatedUtc":"2026-01-01T00:00:00Z"}' | Set-Content -Path $stateFile -Encoding utf8
        & $scriptPath -SessionId $sid -Prompt 'irrelevant' -MaxTurns 3 -Tools 'Read' -StateDir $stateDir -BudgetsPath $budgetsFile -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 9) { throw "expected exit 9, got $LASTEXITCODE" }
        $stillThree = (Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json).turnsUsed
        if ($stillThree -ne 3) { throw "expected the pre-launch refusal to leave the counter unchanged at 3, got $stillThree" }
    }

    Test-Case "MaxTurns enforcement: one turn below the cap is allowed (turn N/N)" {
        $sid = [Guid]::NewGuid().ToString()
        $stateFile = Join-Path $stateDir "$sid.turns.json"
        '{"turnsUsed":2,"lastUpdatedUtc":"2026-01-01T00:00:00Z"}' | Set-Content -Path $stateFile -Encoding utf8
        $out = & $scriptPath -SessionId $sid -Prompt 'irrelevant' -MaxTurns 3 -Tools 'Read' -StateDir $stateDir -BudgetsPath $budgetsFile -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch 'turn=3/3') { throw "expected turn=3/3. Output: $out" }
    }

    Test-Case "missing budgets.json with no override fails closed (exit 4)" {
        $sid = [Guid]::NewGuid().ToString()
        & $scriptPath -SessionId $sid -Prompt 'irrelevant' -MaxTurns 5 -Tools 'Read' -StateDir $stateDir -BudgetsPath (Join-Path $fixtureDir 'does-not-exist.json') -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 4) { throw "expected exit 4, got $LASTEXITCODE" }
    }
} finally {
    Remove-Item -Recurse -Force $fixtureDir -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "== Results: $testsPassed passed, $testsFailed failed ==" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host ""

if ($testsFailed -gt 0) { exit 1 } else { exit 0 }
