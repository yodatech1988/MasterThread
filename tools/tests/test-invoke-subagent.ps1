<#
.SYNOPSIS
  Regression tests for plan task F12's Invoke-Subagent.ps1.

.DESCRIPTION
  Static only via -DryRun and fixture directories -- no test here spends budget or needs `claude`
  on PATH, except the one -RunLive case at the bottom (live acceptance for the F4 schemas). One
  test drives the REAL Invoke-ReadOnlyAgent.ps1 (not stubbed) with its own -ClaudePath test seam
  pointed at a fake CLI, per tools/README.md's testing-seam convention -- this exercises the full
  -RunLive path (parameter binding, exit code, report file, schema check) without ever launching a
  real `claude` process or spending budget.
#>
param(
    [switch]$RunLive
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path (Split-Path -Parent $here) 'headless\Invoke-Subagent.ps1'
$repoRoot = Split-Path -Parent (Split-Path -Parent $here)
$fixtureEnvelopePath = Join-Path $here 'fixtures\headless\envelope-with-denial.json'
$fixtureProseResultPath = Join-Path $here 'fixtures\headless\envelope-prose-result-issue212.json'
$fixtureNoStructuredOutputPath = Join-Path $here 'fixtures\headless\envelope-success-no-structured-output.json'

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

# --- Fixtures for -Tools resolution regression tests (PR #197 second QA finding): three agents
# covering readonly:"instruction" (needs -Tools, has it), readonly:"tools" (restricted, does not
# need -Tools even with none in frontmatter), and readonly:"instruction" with no 'tools:' line at
# all (must fail closed, matching Invoke-ReadOnlyAgent.ps1's own exit 5 meaning).
'---
name: fixture-instruction-agent
model: haiku
tools: Bash, Grep
---
Purpose.' | Set-Content -Path (Join-Path $agentsDir 'fixture-instruction-agent.md') -Encoding utf8
'---
name: fixture-restricted-agent
model: sonnet
---
Purpose.' | Set-Content -Path (Join-Path $agentsDir 'fixture-restricted-agent.md') -Encoding utf8
'---
name: fixture-instruction-no-tools-agent
model: haiku
---
Purpose.' | Set-Content -Path (Join-Path $agentsDir 'fixture-instruction-no-tools-agent.md') -Encoding utf8

$rosterMetaFile = Join-Path $agentsDir 'roster_meta.json'
(@{
    'fixture-instruction-agent'          = @{ readonly = 'instruction' }
    'fixture-restricted-agent'           = @{ readonly = 'tools' }
    'fixture-instruction-no-tools-agent' = @{ readonly = 'instruction' }
} | ConvertTo-Json) | Set-Content -Path $rosterMetaFile -Encoding utf8

# Stub with the same param shape as the real Invoke-ReadOnlyAgent.ps1, capturing -Tools too (used
# by the -Tools resolution tests below as well as the splat regression test above).
$toolsStubPath = Join-Path $fixtureDir 'stub-invoke-readonly-agent-tools.ps1'
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
    AgentName = $AgentName
    Tools     = $Tools
    ToolsSet  = $PSBoundParameters.ContainsKey('Tools')
}
$capture | ConvertTo-Json | Set-Content -LiteralPath $env:F12_TEST_CAPTURE_PATH -Encoding utf8
exit 0
'@ | Set-Content -Path $toolsStubPath -Encoding utf8

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

    Test-Case "regression (PR #197 QA, 2nd finding): readonly:'instruction' agent resolves -Tools from its own frontmatter and forwards it" {
        $captureFile = Join-Path $fixtureDir 'capture-tools-instruction.json'
        if (Test-Path $captureFile) { Remove-Item $captureFile -Force }
        $prevCapturePath = $env:F12_TEST_CAPTURE_PATH
        $env:F12_TEST_CAPTURE_PATH = $captureFile
        try {
            $out = & $scriptPath -AgentName 'fixture-instruction-agent' -Prompt 'hello' -BudgetsPath $budgetsFile -AgentsDir $agentsDir -SchemasDir $schemasDir -InvokeReadOnlyAgentPath $toolsStubPath -RunLive *>&1 | Out-String -Width 4096
            if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
            if (-not (Test-Path $captureFile)) { throw "stub never ran. Output: $out" }
            $captured = Get-Content -LiteralPath $captureFile -Raw | ConvertFrom-Json
            if (-not $captured.ToolsSet) { throw "expected -Tools to be forwarded to Invoke-ReadOnlyAgent.ps1 for a readonly:'instruction' agent, but it was never bound" }
            if ($captured.Tools -ne 'Bash, Grep') { throw "expected Tools='Bash, Grep' (from frontmatter), got '$($captured.Tools)'" }
        } finally {
            $env:F12_TEST_CAPTURE_PATH = $prevCapturePath
        }
    }

    Test-Case "readonly:'tools' (restricted) agent does not require -Tools, and none is forwarded even with no 'tools:' frontmatter" {
        $captureFile = Join-Path $fixtureDir 'capture-tools-restricted.json'
        if (Test-Path $captureFile) { Remove-Item $captureFile -Force }
        $prevCapturePath = $env:F12_TEST_CAPTURE_PATH
        $env:F12_TEST_CAPTURE_PATH = $captureFile
        try {
            $out = & $scriptPath -AgentName 'fixture-restricted-agent' -Prompt 'hello' -BudgetsPath $budgetsFile -AgentsDir $agentsDir -SchemasDir $schemasDir -InvokeReadOnlyAgentPath $toolsStubPath -RunLive *>&1 | Out-String -Width 4096
            if ($LASTEXITCODE -ne 0) { throw "expected exit 0 (restricted agents don't need -Tools), got $LASTEXITCODE. Output: $out" }
            if (-not (Test-Path $captureFile)) { throw "stub never ran. Output: $out" }
            $captured = Get-Content -LiteralPath $captureFile -Raw | ConvertFrom-Json
            if ($captured.ToolsSet) { throw "expected -Tools NOT to be forwarded for a readonly:'tools' (restricted) agent, but it was bound as '$($captured.Tools)'" }
        } finally {
            $env:F12_TEST_CAPTURE_PATH = $prevCapturePath
        }
    }

    Test-Case "fail-closed (PR #197 QA, 2nd finding): readonly:'instruction' agent with no 'tools:' frontmatter refuses (exit 5), nothing launched" {
        $captureFile = Join-Path $fixtureDir 'capture-tools-fail-closed.json'
        if (Test-Path $captureFile) { Remove-Item $captureFile -Force }
        $prevCapturePath = $env:F12_TEST_CAPTURE_PATH
        $env:F12_TEST_CAPTURE_PATH = $captureFile
        try {
            & $scriptPath -AgentName 'fixture-instruction-no-tools-agent' -Prompt 'hello' -BudgetsPath $budgetsFile -AgentsDir $agentsDir -SchemasDir $schemasDir -InvokeReadOnlyAgentPath $toolsStubPath -RunLive 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 5) { throw "expected exit 5, got $LASTEXITCODE" }
            if (Test-Path $captureFile) { throw "Invoke-ReadOnlyAgent.ps1 (stub) should never have been launched, but it wrote a capture file" }
        } finally {
            $env:F12_TEST_CAPTURE_PATH = $prevCapturePath
        }
    }

    Test-Case "regression (PR #197 QA, 3rd finding): full -RunLive F4 path against a fake CLI -- schema check reads envelope.result correctly and PASSES" {
        # Third bug found dry-tracing the whole -RunLive path end to end before this fix: the
        # schema-check block did `$reportJson.envelope | ConvertFrom-Json`, but
        # Invoke-ReadOnlyAgent.ps1's report already stores 'envelope' as a parsed OBJECT (not a JSON
        # string) -- re-parsing a PSCustomObject threw "Invalid JSON primitive" on every real run,
        # so a schema check could never pass, only ever error out before this fix.
        #
        # Agent under test is 'pr-state-sweep', not 'worktree-sweep' (2026-09-22, phase 1 of the
        # allowedTools roster overlay): Invoke-ReadOnlyAgent.ps1 now refuses (exit 7) to launch any
        # Bash-holding, non-restricted agent with no roster 'allowedTools' list, and Invoke-Subagent.ps1
        # has no -AllowedTools passthrough of its own to give one -- pr-state-sweep is the only agent
        # roster_meta.json carries a list for as of phase 1, so it is the only one this full-path
        # regression test can still exercise live without expanding this PR into phase 2 scope.
        $priorTestSeam = $env:AEGIS_TEST_SEAM
        $env:AEGIS_TEST_SEAM = '1'
        $fakeDir = Join-Path $fixtureDir 'fake-claude-e2e'
        New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null
        $reportDir = Join-Path $fixtureDir 'reports-e2e'
        try {
            $envelope = Get-Content -LiteralPath $fixtureEnvelopePath -Raw | ConvertFrom-Json
            $resultObj = [ordered]@{
                agent = 'pr-state-sweep'
                repos = @()
                flags = [ordered]@{ rule4Violations = @(); noCiRun = @() }
                findings = @()
                couldNotCheck = @()
            }
            $envelope.result = ($resultObj | ConvertTo-Json -Compress -Depth 10)
            # 2026-09-22 (coordinator finding): the real CLI puts the schema-validated payload in
            # envelope.structured_output (an object), not envelope.result (its own JSON-text
            # echo) -- added here so this fixture matches the real shape and this test still
            # exercises the DEFAULT (structured_output-reading) path, not the legacy fallback.
            $envelope | Add-Member -NotePropertyName 'structured_output' -NotePropertyValue $resultObj -Force
            $envelope.permission_denials = @()
            $utf8 = [System.Text.UTF8Encoding]::new($false)
            [System.IO.File]::WriteAllText((Join-Path $fakeDir 'out.txt'), ($envelope | ConvertTo-Json -Depth 20 -Compress), $utf8)
            $fakeCmd = Join-Path $fakeDir 'fake-claude.cmd'
            [System.IO.File]::WriteAllText($fakeCmd, "@echo off`r`nif exist `"%~dp0out.txt`" type `"%~dp0out.txt`"`r`nexit /b 0`r`n", [System.Text.Encoding]::ASCII)

            $realSchemasDir = Join-Path $repoRoot 'tools\headless\schemas'
            $realBudgets = Join-Path $repoRoot 'tools\headless\budgets.json'
            $out = & $scriptPath -AgentName 'pr-state-sweep' -Prompt 'irrelevant' -BudgetsPath $realBudgets -AgentsDir (Join-Path $repoRoot 'claude-agents') -SchemasDir $realSchemasDir -ClaudePath $fakeCmd -ReportDir $reportDir -RunLive *>&1 | Out-String -Width 8192
            if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
            if ($out -notmatch 'schema check PASSED') { throw "expected the schema check to pass against the fake envelope. Output: $out" }
            $reportFiles = Get-ChildItem -LiteralPath $reportDir -Filter 'pr-state-sweep.*.json' -ErrorAction SilentlyContinue
            if (-not $reportFiles) { throw "expected a report file to have been written to $reportDir" }
        } finally {
            $env:AEGIS_TEST_SEAM = $priorTestSeam
        }
    }

    Test-Case "regression (issue #212, now exercised via -UseLegacyResultField): a prose (non-JSON) final message fails the LEGACY schema check with exit 8, not a silent pass" {
        # Captured from a real live run (%APPDATA%\AEGIS\reports\pr-state-sweep.20260922-172129.json)
        # where the old '## Output' section told pr-state-sweep to produce a markdown table plus a
        # 'Flags' section, so under --json-schema the final message came back as prose ("Now let me
        # compile the results into a table...") instead of the schema JSON object, and
        # Invoke-Subagent.ps1 exited 8 because envelope.result was not valid JSON. This fixture
        # (fixtures\headless\envelope-prose-result-issue212.json) reproduces that shape offline
        # against a fake CLI, so the exit-8 path stays covered without spending live budget.
        #
        # 2026-09-22 update: the default schema check no longer reads envelope.result at all (see
        # the structured_output tests below) -- this fixture also has no structured_output field,
        # so under the DEFAULT path it now correctly fails with exit 9, not 8 (a different, more
        # specific finding: "the CLI never gave us a validated answer", not "the answer we got was
        # not JSON"). -UseLegacyResultField is what still exercises the original envelope.result /
        # exit-8 path this test was written to cover.
        $priorTestSeam = $env:AEGIS_TEST_SEAM
        $env:AEGIS_TEST_SEAM = '1'
        $fakeDir = Join-Path $fixtureDir 'fake-claude-issue212'
        New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null
        $reportDir = Join-Path $fixtureDir 'reports-issue212'
        try {
            $envelope = Get-Content -LiteralPath $fixtureProseResultPath -Raw | ConvertFrom-Json
            $utf8 = [System.Text.UTF8Encoding]::new($false)
            [System.IO.File]::WriteAllText((Join-Path $fakeDir 'out.txt'), ($envelope | ConvertTo-Json -Depth 20 -Compress), $utf8)
            $fakeCmd = Join-Path $fakeDir 'fake-claude.cmd'
            [System.IO.File]::WriteAllText($fakeCmd, "@echo off`r`nif exist `"%~dp0out.txt`" type `"%~dp0out.txt`"`r`nexit /b 0`r`n", [System.Text.Encoding]::ASCII)

            $realSchemasDir = Join-Path $repoRoot 'tools\headless\schemas'
            $realBudgets = Join-Path $repoRoot 'tools\headless\budgets.json'
            $out = & $scriptPath -AgentName 'pr-state-sweep' -Prompt 'irrelevant' -BudgetsPath $realBudgets -AgentsDir (Join-Path $repoRoot 'claude-agents') -SchemasDir $realSchemasDir -ClaudePath $fakeCmd -ReportDir $reportDir -RunLive -UseLegacyResultField *>&1 | Out-String -Width 8192
            if ($LASTEXITCODE -ne 8) { throw "expected exit 8 (schema check failure), got $LASTEXITCODE. Output: $out" }
            if ($out -notmatch 'envelope.result is not valid JSON') { throw "expected the 'not valid JSON' diagnostic. Output: $out" }
        } finally {
            $env:AEGIS_TEST_SEAM = $priorTestSeam
        }
    }

    Test-Case "regression (issue #212): the SAME prose fixture, under the DEFAULT (non-legacy) path, fails with exit 9 (structured_output missing), not exit 8" {
        $priorTestSeam = $env:AEGIS_TEST_SEAM
        $env:AEGIS_TEST_SEAM = '1'
        $fakeDir = Join-Path $fixtureDir 'fake-claude-issue212-default'
        New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null
        $reportDir = Join-Path $fixtureDir 'reports-issue212-default'
        try {
            $envelope = Get-Content -LiteralPath $fixtureProseResultPath -Raw | ConvertFrom-Json
            $utf8 = [System.Text.UTF8Encoding]::new($false)
            [System.IO.File]::WriteAllText((Join-Path $fakeDir 'out.txt'), ($envelope | ConvertTo-Json -Depth 20 -Compress), $utf8)
            $fakeCmd = Join-Path $fakeDir 'fake-claude.cmd'
            [System.IO.File]::WriteAllText($fakeCmd, "@echo off`r`nif exist `"%~dp0out.txt`" type `"%~dp0out.txt`"`r`nexit /b 0`r`n", [System.Text.Encoding]::ASCII)

            $realSchemasDir = Join-Path $repoRoot 'tools\headless\schemas'
            $realBudgets = Join-Path $repoRoot 'tools\headless\budgets.json'
            $out = & $scriptPath -AgentName 'pr-state-sweep' -Prompt 'irrelevant' -BudgetsPath $realBudgets -AgentsDir (Join-Path $repoRoot 'claude-agents') -SchemasDir $realSchemasDir -ClaudePath $fakeCmd -ReportDir $reportDir -RunLive *>&1 | Out-String -Width 8192
            if ($LASTEXITCODE -ne 9) { throw "expected exit 9 (structured_output missing) under the default path, got $LASTEXITCODE. Output: $out" }
            if ($out -notmatch 'SCHEMA-VALIDATED OUTPUT MISSING') { throw "expected the structured_output-missing diagnostic. Output: $out" }
        } finally {
            $env:AEGIS_TEST_SEAM = $priorTestSeam
        }
    }

    Test-Case "regression (coordinator finding, 2026-09-22): subtype 'success' but envelope.structured_output absent fails closed with exit 9, not a silent pass, even when envelope.result happens to parse as schema-valid JSON" {
        # Platform docs (code.claude.com/docs/en/headless.md 'Get structured output') say the
        # --json-schema-validated payload lands in envelope.structured_output, not envelope.result;
        # the Agent SDK troubleshooting page says subtype 'success' with no structured_output must
        # be treated as a failure. This fixture's envelope.result happens to be schema-valid JSON
        # (unlike the issue-#212 prose fixture above) precisely to prove the new default check does
        # NOT fall back to reading envelope.result and pass just because it looks right -- it must
        # fail on the missing structured_output field itself, with a distinct exit code (9, not 8).
        $priorTestSeam = $env:AEGIS_TEST_SEAM
        $env:AEGIS_TEST_SEAM = '1'
        $fakeDir = Join-Path $fixtureDir 'fake-claude-no-structured-output'
        New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null
        $reportDir = Join-Path $fixtureDir 'reports-no-structured-output'
        try {
            $envelope = Get-Content -LiteralPath $fixtureNoStructuredOutputPath -Raw | ConvertFrom-Json
            $utf8 = [System.Text.UTF8Encoding]::new($false)
            [System.IO.File]::WriteAllText((Join-Path $fakeDir 'out.txt'), ($envelope | ConvertTo-Json -Depth 20 -Compress), $utf8)
            $fakeCmd = Join-Path $fakeDir 'fake-claude.cmd'
            [System.IO.File]::WriteAllText($fakeCmd, "@echo off`r`nif exist `"%~dp0out.txt`" type `"%~dp0out.txt`"`r`nexit /b 0`r`n", [System.Text.Encoding]::ASCII)

            $realSchemasDir = Join-Path $repoRoot 'tools\headless\schemas'
            $realBudgets = Join-Path $repoRoot 'tools\headless\budgets.json'
            $out = & $scriptPath -AgentName 'pr-state-sweep' -Prompt 'irrelevant' -BudgetsPath $realBudgets -AgentsDir (Join-Path $repoRoot 'claude-agents') -SchemasDir $realSchemasDir -ClaudePath $fakeCmd -ReportDir $reportDir -RunLive *>&1 | Out-String -Width 8192
            if ($LASTEXITCODE -ne 9) { throw "expected exit 9 (structured_output missing), got $LASTEXITCODE. Output: $out" }
            if ($out -notmatch 'SCHEMA-VALIDATED OUTPUT MISSING') { throw "expected the structured_output-missing diagnostic. Output: $out" }
        } finally {
            $env:AEGIS_TEST_SEAM = $priorTestSeam
        }
    }

    Test-Case "-UseLegacyResultField opts back into reading envelope.result, and PASSES against the same fixture (proving the default check's exit 9 is a real behavioural difference, not a fixture artifact)" {
        $priorTestSeam = $env:AEGIS_TEST_SEAM
        $env:AEGIS_TEST_SEAM = '1'
        $fakeDir = Join-Path $fixtureDir 'fake-claude-legacy-fallback'
        New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null
        $reportDir = Join-Path $fixtureDir 'reports-legacy-fallback'
        try {
            $envelope = Get-Content -LiteralPath $fixtureNoStructuredOutputPath -Raw | ConvertFrom-Json
            $utf8 = [System.Text.UTF8Encoding]::new($false)
            [System.IO.File]::WriteAllText((Join-Path $fakeDir 'out.txt'), ($envelope | ConvertTo-Json -Depth 20 -Compress), $utf8)
            $fakeCmd = Join-Path $fakeDir 'fake-claude.cmd'
            [System.IO.File]::WriteAllText($fakeCmd, "@echo off`r`nif exist `"%~dp0out.txt`" type `"%~dp0out.txt`"`r`nexit /b 0`r`n", [System.Text.Encoding]::ASCII)

            $realSchemasDir = Join-Path $repoRoot 'tools\headless\schemas'
            $realBudgets = Join-Path $repoRoot 'tools\headless\budgets.json'
            $out = & $scriptPath -AgentName 'pr-state-sweep' -Prompt 'irrelevant' -BudgetsPath $realBudgets -AgentsDir (Join-Path $repoRoot 'claude-agents') -SchemasDir $realSchemasDir -ClaudePath $fakeCmd -ReportDir $reportDir -RunLive -UseLegacyResultField *>&1 | Out-String -Width 8192
            if ($LASTEXITCODE -ne 0) { throw "expected exit 0 (legacy field is schema-valid JSON in this fixture), got $LASTEXITCODE. Output: $out" }
            if ($out -notmatch 'schema check PASSED') { throw "expected the legacy path to pass. Output: $out" }
        } finally {
            $env:AEGIS_TEST_SEAM = $priorTestSeam
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
