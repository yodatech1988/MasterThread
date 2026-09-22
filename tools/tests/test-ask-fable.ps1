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
$invokeReadOnlyAgentScriptPath = Join-Path (Split-Path -Parent $here) 'headless\Invoke-ReadOnlyAgent.ps1'

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

    # --- gh198: --session-id/--resume/--fallback-model/--fork-session reach the real argv ----------
    # Direct DryRun assertions against Invoke-ReadOnlyAgent.ps1 itself -- the flags appear on the
    # argv line Start-Process would launch, not merely in this script's own bookkeeping.
    Test-Case "gh198: -SessionId alone (no -Resume) produces --session-id, never --resume" {
        $out = & $invokeReadOnlyAgentScriptPath -AgentName 'fable-seat' -Prompt 'x' -Restricted -SessionId 'abc123' -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch '--session-id abc123') { throw "expected --session-id abc123. Output: $out" }
        if ($out -match '--resume') { throw "must not also carry --resume. Output: $out" }
    }

    Test-Case "gh198: -SessionId with -Resume produces --resume, never --session-id (mutual exclusion, fails closed structurally)" {
        $out = & $invokeReadOnlyAgentScriptPath -AgentName 'fable-seat' -Prompt 'x' -Restricted -SessionId 'abc123' -Resume -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch '--resume abc123') { throw "expected --resume abc123. Output: $out" }
        if ($out -match '--session-id') { throw "the built argv must NEVER carry both --session-id and --resume on one call -- found --session-id alongside --resume. Output: $out" }
    }

    Test-Case "gh198: -Resume without -SessionId is refused (exit 2), nothing launched -- there is no id to resume" {
        & $invokeReadOnlyAgentScriptPath -AgentName 'fable-seat' -Prompt 'x' -Restricted -Resume -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 2) { throw "expected exit 2, got $LASTEXITCODE" }
    }

    Test-Case "gh198: -ForkSession combines with -SessionId (--session-id AND --fork-session, never --resume)" {
        $out = & $invokeReadOnlyAgentScriptPath -AgentName 'fable-seat' -Prompt 'x' -Restricted -SessionId 'abc123' -ForkSession -DryRun *>&1 | Out-String -Width 4096
        if ($out -notmatch '--session-id abc123') { throw "expected --session-id abc123. Output: $out" }
        if ($out -notmatch '--fork-session') { throw "expected --fork-session. Output: $out" }
        if ($out -match '--resume') { throw "must not also carry --resume. Output: $out" }
    }

    Test-Case "gh198: -FallbackModel '' omits --fallback-model entirely" {
        $out = & $invokeReadOnlyAgentScriptPath -AgentName 'fable-seat' -Prompt 'x' -Restricted -FallbackModel '' -DryRun *>&1 | Out-String -Width 4096
        if ($out -match '--fallback-model') { throw "empty -FallbackModel must omit the flag. Output: $out" }
    }

    Test-Case "gh198: -FallbackModel 'opus' produces --fallback-model opus" {
        $out = & $invokeReadOnlyAgentScriptPath -AgentName 'fable-seat' -Prompt 'x' -Restricted -FallbackModel 'opus' -DryRun *>&1 | Out-String -Width 4096
        if ($out -notmatch '--fallback-model opus') { throw "expected --fallback-model opus. Output: $out" }
    }

    Test-Case "gh198: a caller passing none of the four new parameters gets byte-identical argv to before this change" {
        $out = & $invokeReadOnlyAgentScriptPath -AgentName 'fable-seat' -Prompt 'x' -Restricted -DryRun *>&1 | Out-String -Width 4096
        $expected = 'DRYRUN ARGS: --print --agent fable-seat --settings "' + (Join-Path (Split-Path -Parent $invokeReadOnlyAgentScriptPath) 'readonly.settings.json') + '" --restricted --permission-mode dontAsk --permission-prompts none --strict-mcp-config --max-budget-usd 1 --output-format stream-json --verbose (prompt on stdin)'
        $argsLine = (($out -split "`r?`n") | Where-Object { $_ -match '^DRYRUN ARGS:' } | Select-Object -First 1).Trim()
        if ($argsLine -ne $expected) { throw "expected byte-identical argv line for a caller passing none of the new parameters.`nExpected: $expected`nActual:   $argsLine" }
    }

    # --- gh198: Ask-Fable.ps1's own $innerArgs actually carries the flags through, end to end -------
    # Uses the -InvokeReadOnlyAgentPath test seam to point at a throwaway capture fixture (written
    # here, never committed) that records exactly which parameters it was invoked with, instead of
    # the real Invoke-ReadOnlyAgent.ps1 -- so these assertions spend no budget and need no `claude`
    # on PATH, while still proving Ask-Fable.ps1's own wiring, not just Invoke-ReadOnlyAgent.ps1's.
    $captureScript = Join-Path $fixtureRoot 'capture-invoke-readonly-agent.ps1'
    @'
[CmdletBinding()]
param(
    [string]$AgentName, [string]$Prompt, [double]$MaxBudgetUsd, [int]$TimeoutSec,
    [switch]$Report, [string]$ReportDir, [switch]$Restricted, [string]$Tools, [string]$Model,
    [string]$SessionId, [switch]$Resume, [string]$FallbackModel, [switch]$ForkSession,
    [string]$ClaudePath, [string]$RosterMetaPath
)
$captured = [ordered]@{
    SessionIdGiven      = $PSBoundParameters.ContainsKey('SessionId')
    SessionId           = $SessionId
    ResumeGiven         = $PSBoundParameters.ContainsKey('Resume')
    Resume              = [bool]$Resume
    FallbackModelGiven  = $PSBoundParameters.ContainsKey('FallbackModel')
    FallbackModel       = $FallbackModel
    ForkSessionGiven    = $PSBoundParameters.ContainsKey('ForkSession')
    ForkSession         = [bool]$ForkSession
}
($captured | ConvertTo-Json -Compress) | Set-Content -LiteralPath $env:AEGIS_TEST_CAPTURE_PATH -Encoding utf8
exit 0
'@ | Set-Content -Path $captureScript -Encoding utf8

    Test-Case "gh198 end-to-end: a cold Ask-Fable call passes -SessionId, not -Resume, to Invoke-ReadOnlyAgent.ps1" {
        $sid = [Guid]::NewGuid().ToString()
        $capturePath = Join-Path $fixtureRoot ("capture-" + [Guid]::NewGuid().ToString('N') + '.json')
        $oldCapture = $env:AEGIS_TEST_CAPTURE_PATH
        try {
            $env:AEGIS_TEST_CAPTURE_PATH = $capturePath
            & $scriptPath -SessionId $sid -Question 'irrelevant' -WorkingDirectory $safeWorkDir -StateDir $stateDir -BudgetsPath $budgetsFile -InvokeReadOnlyAgentPath $captureScript 2>&1 | Out-Null
        } finally {
            $env:AEGIS_TEST_CAPTURE_PATH = $oldCapture
        }
        if (-not (Test-Path $capturePath)) { throw "capture file was not written" }
        $captured = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json
        if (-not $captured.SessionIdGiven -or $captured.SessionId -ne $sid) { throw "expected -SessionId $sid to reach Invoke-ReadOnlyAgent.ps1. Captured: $($captured | ConvertTo-Json -Compress)" }
        if ($captured.ResumeGiven) { throw "a cold call must not pass -Resume. Captured: $($captured | ConvertTo-Json -Compress)" }
    }

    Test-Case "gh198 end-to-end: a resumed Ask-Fable call (known-open session) passes -Resume to Invoke-ReadOnlyAgent.ps1" {
        $sid = [Guid]::NewGuid().ToString()
        $stateFile = Join-Path $stateDir "$sid.json"
        '{"openedUtc":"2026-01-01T00:00:00Z","lastUsedUtc":"2026-01-01T00:00:00Z"}' | Set-Content -Path $stateFile -Encoding utf8
        $capturePath = Join-Path $fixtureRoot ("capture-" + [Guid]::NewGuid().ToString('N') + '.json')
        $oldCapture = $env:AEGIS_TEST_CAPTURE_PATH
        try {
            $env:AEGIS_TEST_CAPTURE_PATH = $capturePath
            & $scriptPath -SessionId $sid -Question 'irrelevant' -WorkingDirectory $safeWorkDir -StateDir $stateDir -BudgetsPath $budgetsFile -InvokeReadOnlyAgentPath $captureScript 2>&1 | Out-Null
        } finally {
            $env:AEGIS_TEST_CAPTURE_PATH = $oldCapture
        }
        $captured = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json
        if (-not $captured.ResumeGiven -or -not $captured.Resume) { throw "expected -Resume to reach Invoke-ReadOnlyAgent.ps1 for a known-open session. Captured: $($captured | ConvertTo-Json -Compress)" }
        if (-not $captured.SessionIdGiven -or $captured.SessionId -ne $sid) { throw "-SessionId must still be passed (it is the id -Resume resumes). Captured: $($captured | ConvertTo-Json -Compress)" }
    }

    Test-Case "gh198 end-to-end: a -Fork call passes -ForkSession, never -Resume, and does not update persistent cold-start state" {
        $sid = [Guid]::NewGuid().ToString()
        $stateFile = Join-Path $stateDir "$sid.json"
        '{"openedUtc":"2026-01-01T00:00:00Z","lastUsedUtc":"2026-01-01T00:00:00Z"}' | Set-Content -Path $stateFile -Encoding utf8
        $beforeContent = Get-Content -LiteralPath $stateFile -Raw
        $capturePath = Join-Path $fixtureRoot ("capture-" + [Guid]::NewGuid().ToString('N') + '.json')
        $oldCapture = $env:AEGIS_TEST_CAPTURE_PATH
        try {
            $env:AEGIS_TEST_CAPTURE_PATH = $capturePath
            & $scriptPath -SessionId $sid -Question 'irrelevant' -Fork -WorkingDirectory $safeWorkDir -StateDir $stateDir -BudgetsPath $budgetsFile -InvokeReadOnlyAgentPath $captureScript 2>&1 | Out-Null
        } finally {
            $env:AEGIS_TEST_CAPTURE_PATH = $oldCapture
        }
        $captured = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json
        if (-not $captured.ForkSessionGiven -or -not $captured.ForkSession) { throw "expected -ForkSession to reach Invoke-ReadOnlyAgent.ps1 under -Fork. Captured: $($captured | ConvertTo-Json -Compress)" }
        if ($captured.ResumeGiven) { throw "a -Fork call must never pass -Resume. Captured: $($captured | ConvertTo-Json -Compress)" }
        $afterContent = Get-Content -LiteralPath $stateFile -Raw
        if ($afterContent -ne $beforeContent) { throw "a -Fork call must not update the persistent cold-start/turn state file" }
    }

    Test-Case "gh198 end-to-end: -FallbackModel '' (the documented opt-out) omits -FallbackModel from innerArgs" {
        $sid = [Guid]::NewGuid().ToString()
        $capturePath = Join-Path $fixtureRoot ("capture-" + [Guid]::NewGuid().ToString('N') + '.json')
        $oldCapture = $env:AEGIS_TEST_CAPTURE_PATH
        try {
            $env:AEGIS_TEST_CAPTURE_PATH = $capturePath
            & $scriptPath -SessionId $sid -Question 'irrelevant' -FallbackModel '' -WorkingDirectory $safeWorkDir -StateDir $stateDir -BudgetsPath $budgetsFile -InvokeReadOnlyAgentPath $captureScript 2>&1 | Out-Null
        } finally {
            $env:AEGIS_TEST_CAPTURE_PATH = $oldCapture
        }
        $captured = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json
        if ($captured.FallbackModelGiven) { throw "-FallbackModel '' must not be passed through to Invoke-ReadOnlyAgent.ps1 at all. Captured: $($captured | ConvertTo-Json -Compress)" }
    }
} finally {
    Remove-Item -Recurse -Force $fixtureRoot -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "== Results: $testsPassed passed, $testsFailed failed ==" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host ""

if ($testsFailed -gt 0) { exit 1 } else { exit 0 }
