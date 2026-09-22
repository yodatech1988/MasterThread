<#
.SYNOPSIS
  Regression tests for plan task F12's Invoke-Subagent.ps1.

.DESCRIPTION
  Static only via -DryRun and fixture directories -- no test here spends budget or needs `claude`
  on PATH, except the one -RunLive case at the bottom (live acceptance for the F4 schemas).
#>
param(
    [switch]$RunLive
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path (Split-Path -Parent $here) 'headless\Invoke-Subagent.ps1'
$repoRoot = Split-Path -Parent (Split-Path -Parent $here)

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
Write-Host "== F12 regression tests: Invoke-Subagent.ps1" -ForegroundColor Cyan
Write-Host ""

Test-Case "Invoke-Subagent.ps1 exists" {
    if (-not (Test-Path $scriptPath)) { throw "File not found at $scriptPath" }
}

# --- Fixtures: throwaway agents dir + budgets file, never the real repo state -------------------
$fixtureDir = Join-Path ([System.IO.Path]::GetTempPath()) ("f12-invoke-subagent-test-" + [Guid]::NewGuid().ToString('N'))
$agentsDir = Join-Path $fixtureDir 'claude-agents'
New-Item -ItemType Directory -Path $agentsDir -Force | Out-Null
'---
name: fixture-haiku-agent
model: haiku
tools: Read, Grep
---
Purpose.' | Set-Content -Path (Join-Path $agentsDir 'fixture-haiku-agent.md') -Encoding utf8
'---
name: fixture-sonnet-agent
model: sonnet
tools: Read, Grep
---
Purpose.' | Set-Content -Path (Join-Path $agentsDir 'fixture-sonnet-agent.md') -Encoding utf8

$budgetsFile = Join-Path $fixtureDir 'budgets.json'
'{"subagent":{"haiku":0.25,"sonnet":0.75,"default":0.10}}' | Set-Content -Path $budgetsFile -Encoding utf8

$schemasDir = Join-Path $fixtureDir 'schemas'
New-Item -ItemType Directory -Path $schemasDir -Force | Out-Null

try {
    Test-Case "budget resolved by model tier from agent frontmatter (haiku)" {
        $out = & $scriptPath -AgentName 'fixture-haiku-agent' -Prompt 'irrelevant' -BudgetsPath $budgetsFile -AgentsDir $agentsDir -SchemasDir $schemasDir -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch 'tier=haiku') { throw "expected tier=haiku. Output: $out" }
        if ($out -notmatch 'resolvedBudget=0.25') { throw "expected resolvedBudget=0.25. Output: $out" }
    }

    Test-Case "budget resolved by model tier from agent frontmatter (sonnet)" {
        $out = & $scriptPath -AgentName 'fixture-sonnet-agent' -Prompt 'irrelevant' -BudgetsPath $budgetsFile -AgentsDir $agentsDir -SchemasDir $schemasDir -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch 'tier=sonnet') { throw "expected tier=sonnet. Output: $out" }
        if ($out -notmatch 'resolvedBudget=0.75') { throw "expected resolvedBudget=0.75. Output: $out" }
    }

    Test-Case "unknown agent (no frontmatter file) falls back to 'default' tier" {
        $out = & $scriptPath -AgentName 'no-such-agent' -Prompt 'irrelevant' -BudgetsPath $budgetsFile -AgentsDir $agentsDir -SchemasDir $schemasDir -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch 'tier=default') { throw "expected tier=default. Output: $out" }
        if ($out -notmatch 'resolvedBudget=0.1') { throw "expected resolvedBudget=0.1. Output: $out" }
    }

    Test-Case "explicit -MaxBudgetUsd overrides the budgets.json lookup" {
        $out = & $scriptPath -AgentName 'fixture-haiku-agent' -Prompt 'irrelevant' -MaxBudgetUsd 9.99 -BudgetsPath $budgetsFile -AgentsDir $agentsDir -SchemasDir $schemasDir -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch 'resolvedBudget=9.99') { throw "expected the override to win. Output: $out" }
    }

    Test-Case "missing budgets.json with no override fails closed (exit 4), nothing launched" {
        & $scriptPath -AgentName 'fixture-haiku-agent' -Prompt 'irrelevant' -BudgetsPath (Join-Path $fixtureDir 'does-not-exist.json') -AgentsDir $agentsDir -SchemasDir $schemasDir -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 4) { throw "expected exit 4, got $LASTEXITCODE" }
    }

    Test-Case "budgets.json missing the tier and 'default' fails closed (exit 4)" {
        $noDefault = Join-Path $fixtureDir 'no-default-budgets.json'
        '{"subagent":{"opus":1.0}}' | Set-Content -Path $noDefault -Encoding utf8
        & $scriptPath -AgentName 'fixture-haiku-agent' -Prompt 'irrelevant' -BudgetsPath $noDefault -AgentsDir $agentsDir -SchemasDir $schemasDir -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 4) { throw "expected exit 4, got $LASTEXITCODE" }
    }

    Test-Case "hasSchema is False when tools/headless/schemas/<agent>.json does not exist" {
        $out = & $scriptPath -AgentName 'fixture-haiku-agent' -Prompt 'irrelevant' -BudgetsPath $budgetsFile -AgentsDir $agentsDir -SchemasDir $schemasDir -DryRun *>&1 | Out-String -Width 4096
        if ($out -notmatch 'hasSchema=False') { throw "expected hasSchema=False. Output: $out" }
    }

    Test-Case "hasSchema is True when a real F4 schema exists for the agent (against the real repo schemas dir)" {
        $realSchemasDir = Join-Path $repoRoot 'tools\headless\schemas'
        $out = & $scriptPath -AgentName 'worktree-sweep' -Prompt 'irrelevant' -BudgetsPath $budgetsFile -AgentsDir $agentsDir -SchemasDir $realSchemasDir -DryRun *>&1 | Out-String -Width 4096
        if ($out -notmatch 'hasSchema=True') { throw "expected hasSchema=True for worktree-sweep against the real schemas dir. Output: $out" }
    }

    Test-Case "regression (PR #197 QA): inner call to Invoke-ReadOnlyAgent.ps1 uses a hashtable splat, so -MaxBudgetUsd binds as a named [double] param, not positionally" {
        # Stub with the same param shape as the real Invoke-ReadOnlyAgent.ps1 (MaxBudgetUsd is its
        # only [double] parameter). Under the old List[object] array splat, PowerShell 5.1 binds
        # every splatted element positionally -- the literal string '-MaxBudgetUsd' itself would
        # land on this stub's $MaxBudgetUsd and fail with a type-conversion error before the stub
        # body ever runs, so no capture file would be written and this test would fail. Under the
        # fixed [ordered]@{} hashtable splat, values bind by name and the stub runs normally.
        $stubPath = Join-Path $fixtureDir 'stub-invoke-readonly-agent.ps1'
        @'
param(
    [Parameter(Mandatory = $true)][string]$AgentName,
    [Parameter(Mandatory = $true)][string]$Prompt,
    [string]$Tools,
    [string]$AllowedTools,
    [switch]$Restricted,
    [double]$MaxBudgetUsd = 1,
    [int]$TimeoutSec = 300,
    [string]$SettingsPath,
    [string]$JsonSchemaPath,
    [string]$RosterMetaPath,
    [string]$Model,
    [switch]$Report,
    [string]$ReportDir,
    [string]$ClaudePath,
    [switch]$DryRun
)
$capture = [ordered]@{
    AgentName        = $AgentName
    Prompt           = $Prompt
    MaxBudgetUsd     = $MaxBudgetUsd
    MaxBudgetUsdType = $MaxBudgetUsd.GetType().Name
    TimeoutSec       = $TimeoutSec
    Report           = $Report.IsPresent
    RosterMetaPath   = $RosterMetaPath
}
$capture | ConvertTo-Json | Set-Content -LiteralPath $env:F12_TEST_CAPTURE_PATH -Encoding utf8
exit 0
'@ | Set-Content -Path $stubPath -Encoding utf8

        $captureFile = Join-Path $fixtureDir 'capture.json'
        if (Test-Path $captureFile) { Remove-Item $captureFile -Force }
        $prevCapturePath = $env:F12_TEST_CAPTURE_PATH
        $env:F12_TEST_CAPTURE_PATH = $captureFile
        try {
            $out = & $scriptPath -AgentName 'fixture-haiku-agent' -Prompt 'hello' -BudgetsPath $budgetsFile -AgentsDir $agentsDir -SchemasDir $schemasDir -InvokeReadOnlyAgentPath $stubPath -RunLive *>&1 | Out-String -Width 4096
            if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
            if (-not (Test-Path $captureFile)) { throw "stub never ran / never wrote its capture file (parameter binding likely failed). Output: $out" }
            $captured = Get-Content -LiteralPath $captureFile -Raw | ConvertFrom-Json
            if ($captured.AgentName -ne 'fixture-haiku-agent') { throw "expected AgentName='fixture-haiku-agent' to bind by name, got '$($captured.AgentName)'" }
            if ($captured.Prompt -ne 'hello') { throw "expected Prompt='hello' to bind by name, got '$($captured.Prompt)'" }
            if ($captured.MaxBudgetUsdType -ne 'Double') { throw "expected MaxBudgetUsd to bind as a Double, got type '$($captured.MaxBudgetUsdType)'" }
            if ([double]$captured.MaxBudgetUsd -ne 0.25) { throw "expected MaxBudgetUsd=0.25 (haiku tier), got '$($captured.MaxBudgetUsd)'" }
            if ($captured.Report -ne $true) { throw "expected -Report to bind as a switch, got '$($captured.Report)'" }
        } finally {
            $env:F12_TEST_CAPTURE_PATH = $prevCapturePath
        }
    }

    Test-Case "without -RunLive, no budget is spent and the schema (if any) is only checked offline" {
        $realSchemasDir = Join-Path $repoRoot 'tools\headless\schemas'
        $realBudgets = Join-Path $repoRoot 'tools\headless\budgets.json'
        $out = & $scriptPath -AgentName 'worktree-sweep' -Prompt 'irrelevant' -BudgetsPath $realBudgets -AgentsDir (Join-Path $repoRoot 'claude-agents') -SchemasDir $realSchemasDir *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch 'not launching claude') { throw "expected the no-live-run notice. Output: $out" }
        if ($out -notmatch 'NOT a live') { throw "expected the explicit non-live disclosure. Output: $out" }
    }
} finally {
    Remove-Item -Recurse -Force $fixtureDir -ErrorAction SilentlyContinue
}

# --- Live acceptance for F4: a real `claude -p --json-schema` run -------------------------------
if ($RunLive) {
    Test-Case "live acceptance: claude -p --json-schema accepts pr-state-sweep.json and returns a schema-valid envelope" {
        $realSchemasDir = Join-Path $repoRoot 'tools\headless\schemas'
        $realBudgets = Join-Path $repoRoot 'tools\headless\budgets.json'
        $out = & $scriptPath -AgentName 'pr-state-sweep' -Prompt 'Report on any open PRs you can see for yodatech1988/MasterThread. If you cannot reach gh, say so in couldNotCheck.' -BudgetsPath $realBudgets -AgentsDir (Join-Path $repoRoot 'claude-agents') -SchemasDir $realSchemasDir -RunLive *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch 'schema check PASSED') { throw "expected a passing live schema check. Output: $out" }
    }
} else {
    Write-Host "[SKIP] live acceptance for F4 schemas (pass -RunLive to exercise it; spends real API budget)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "== Results: $testsPassed passed, $testsFailed failed ==" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host ""

if ($testsFailed -gt 0) { exit 1 } else { exit 0 }
