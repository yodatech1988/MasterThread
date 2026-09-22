<#
.SYNOPSIS
  Regression tests for plan task F2: -Restricted on tools/headless/Invoke-ReadOnlyAgent.ps1.

.DESCRIPTION
  Follows tools/README.md's testing-seam conventions: static tests use -DryRun and a throwaway
  -RosterMetaPath fixture (never the real claude-agents/roster_meta.json), so no test here spends
  budget or depends on `claude` being installed. One live test (skipped unless -RunLive is passed,
  since it spends real API budget and requires the `claude` CLI on PATH) reproduces the plan's own
  §1a / F3 probe: a --restricted run has NO Bash tool on its surface at all, not merely denied.

.PARAMETER RunLive
  Also run the live --restricted probe against the real `claude` CLI (small Haiku call, real
  cost). Off by default so the static suite can run anywhere.
#>
param(
    [switch]$RunLive
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path (Split-Path -Parent $here) 'headless\Invoke-ReadOnlyAgent.ps1'

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
Write-Host "== F2 regression tests: -Restricted on Invoke-ReadOnlyAgent.ps1" -ForegroundColor Cyan
Write-Host ""

Test-Case "Invoke-ReadOnlyAgent.ps1 exists" {
    if (-not (Test-Path $scriptPath)) { throw "File not found at $scriptPath" }
}

# --- Fixture roster_meta.json (test seam: never the real file) ---------------------------------
$fixtureDir = Join-Path ([System.IO.Path]::GetTempPath()) ("f2-restricted-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null
$fixtureRoster = Join-Path $fixtureDir 'roster_meta.json'
@'
{
  "fixture-tools-agent": {"role": "R", "headless": "yes", "readonly": "tools", "dormant": false},
  "fixture-instruction-agent": {"role": "R", "headless": "yes", "readonly": "instruction", "dormant": false},
  "fixture-na-agent": {"role": "R", "headless": "yes", "readonly": "n/a", "dormant": false}
}
'@ | Set-Content -Path $fixtureRoster -Encoding utf8

try {
    Test-Case "readonly:'tools' agent defaults to --restricted (no -Restricted passed)" {
        $out = & $scriptPath -AgentName 'fixture-tools-agent' -Prompt 'irrelevant' -RosterMetaPath $fixtureRoster -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch 'Restricted=True') { throw "expected Restricted=True in dry-run output. Output: $out" }
        if ($out -notmatch '--restricted') { throw "expected --restricted in built args. Output: $out" }
        if ($out -match '--tools ') { throw "restricted run must not also carry --tools. Output: $out" }
    }

    Test-Case "readonly:'instruction' agent defaults to NOT restricted and still requires -Tools" {
        $out = & $scriptPath -AgentName 'fixture-instruction-agent' -Prompt 'irrelevant' -RosterMetaPath $fixtureRoster -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 5) { throw "expected exit 5 (missing -Tools, not restricted), got $LASTEXITCODE. Output: $out" }
    }

    Test-Case "readonly:'instruction' agent with -Tools produces byte-identical pre-F2 shape (no --restricted)" {
        $out = & $scriptPath -AgentName 'fixture-instruction-agent' -Prompt 'irrelevant' -Tools 'Read,Grep' -RosterMetaPath $fixtureRoster -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -match '--restricted') { throw "instruction agent must never get --restricted by default. Output: $out" }
        if ($out -notmatch '--tools "Read,Grep"') { throw "expected --tools `"Read,Grep`" unchanged. Output: $out" }
    }

    Test-Case "readonly:'n/a' agent defaults to NOT restricted" {
        $out = & $scriptPath -AgentName 'fixture-na-agent' -Prompt 'irrelevant' -Tools 'Read' -RosterMetaPath $fixtureRoster -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -match '--restricted') { throw "n/a agent must never get --restricted by default. Output: $out" }
    }

    Test-Case "explicit -Restricted:`$false wins over a readonly:'tools' default" {
        $out = & $scriptPath -AgentName 'fixture-tools-agent' -Prompt 'irrelevant' -Tools 'Read' -Restricted:$false -RosterMetaPath $fixtureRoster -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -match '--restricted') { throw "explicit -Restricted:`$false must win over the roster_meta.json default. Output: $out" }
        if ($out -notmatch 'Restricted=False \(explicit=True\)') { throw "expected explicit=True recorded. Output: $out" }
    }

    Test-Case "explicit -Restricted wins over a readonly:'instruction' default (no roster needed at all)" {
        $out = & $scriptPath -AgentName 'fixture-instruction-agent' -Prompt 'irrelevant' -Restricted -RosterMetaPath (Join-Path $fixtureDir 'does-not-exist.json') -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0 (explicit -Restricted skips the roster_meta.json lookup entirely), got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch '--restricted') { throw "expected --restricted. Output: $out" }
    }

    Test-Case "missing roster_meta.json fails closed (exit 4), not silently unrestricted" {
        & $scriptPath -AgentName 'fixture-tools-agent' -Prompt 'irrelevant' -Tools 'Read' -RosterMetaPath (Join-Path $fixtureDir 'does-not-exist.json') -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 4) { throw "expected exit 4, got $LASTEXITCODE" }
    }

    Test-Case "agent not listed in roster_meta.json fails closed (exit 4), not silently unrestricted" {
        & $scriptPath -AgentName 'not-in-the-fixture-at-all' -Prompt 'irrelevant' -Tools 'Read' -RosterMetaPath $fixtureRoster -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 4) { throw "expected exit 4, got $LASTEXITCODE" }
    }

    Test-Case "malformed roster_meta.json fails closed (exit 4), not silently unrestricted" {
        $badRoster = Join-Path $fixtureDir 'bad-roster.json'
        Set-Content -Path $badRoster -Value '{ not valid json' -Encoding utf8
        & $scriptPath -AgentName 'fixture-tools-agent' -Prompt 'irrelevant' -Tools 'Read' -RosterMetaPath $badRoster -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 4) { throw "expected exit 4, got $LASTEXITCODE" }
    }

    Test-Case "-Tools/-AllowedTools passed alongside a restricted default are ignored, not merged in" {
        $out = & $scriptPath -AgentName 'fixture-tools-agent' -Prompt 'irrelevant' -Tools 'Bash' -AllowedTools 'Bash(git status:*)' -RosterMetaPath $fixtureRoster -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        $argsLine = ($out -split "`n") | Where-Object { $_ -match '^DRYRUN ARGS:' }
        if (-not $argsLine) { throw "no DRYRUN ARGS line found. Output: $out" }
        if ($argsLine -match '--tools') { throw "restricted run must ignore -Tools, not thread it in. Output: $out" }
        if ($argsLine -match '--allowedTools') { throw "restricted run must ignore -AllowedTools, not thread it in. Output: $out" }
        if ($argsLine -notmatch '--restricted') { throw "expected --restricted. Output: $out" }
    }
} finally {
    Remove-Item -Recurse -Force $fixtureDir -ErrorAction SilentlyContinue
}

# --- Live probe (proves the tool is ABSENT, not merely denied) ---------------------------------
# Reproduces docs/FABLE_AGENT_SUBAGENT_PLAN.md's §1a / F3 probe: a --restricted Haiku run asked to
# run a trivial Bash command must report the tool as absent from its surface, not "permission
# denied". Off by default (-RunLive) since it spends real API budget and needs `claude` on PATH.
if ($RunLive) {
    Test-Case "live --restricted probe: Bash/PowerShell/WebFetch are structurally absent from the tool surface" {
        $claudeCmd = Get-Command 'claude.cmd' -ErrorAction SilentlyContinue
        if (-not $claudeCmd) { $claudeCmd = Get-Command 'claude' -ErrorAction SilentlyContinue }
        if (-not $claudeCmd) { throw "claude CLI not found on PATH; cannot run the live probe" }

        # Deterministic, not text-matching: the CLI's own system/init event lists exactly the
        # tools loaded into this run's surface. Under --restricted, Bash/PowerShell/REPL/WebFetch
        # must not appear in it at all -- proving the tool is ABSENT, not merely denied at call
        # time (the distinction docs/FABLE_AGENT_SUBAGENT_PLAN.md's F3 finding rests on). Relying
        # on the model's own prose (tried first) was flaky across runs -- Haiku's phrasing of "I
        # don't have Bash" versus a generic safety refusal varied run to run for the same prompt;
        # the init event's tool list does not.
        $args = @(
            '--print', '--model', 'haiku', '--restricted',
            '--permission-mode', 'dontAsk', '--permission-prompts', 'none',
            '--strict-mcp-config', '--max-budget-usd', '0.05',
            '--output-format', 'json', '--verbose',
            'Say OK.'
        )
        $raw = & $claudeCmd.Source @args 2>$null | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "claude exited $LASTEXITCODE. Output: $raw" }
        $events = $raw | ConvertFrom-Json
        $init = $events | Where-Object { $_.type -eq 'system' -and $_.subtype -eq 'init' } | Select-Object -First 1
        if (-not $init) { throw "no system/init event found in output. Output: $raw" }
        $toolNames = $init.tools
        foreach ($forbidden in @('Bash', 'PowerShell', 'REPL', 'WebFetch')) {
            if ($toolNames -contains $forbidden) {
                throw "expected '$forbidden' to be ABSENT from the --restricted tool surface; found it in: $($toolNames -join ', ')"
            }
        }
        $result = $events | Where-Object { $_.type -eq 'result' } | Select-Object -First 1
        if ($result -and $result.permission_denials.Count -ne 0) {
            throw "expected zero permission_denials (tool absence, not a denial); got $($result.permission_denials.Count)"
        }
    }
} else {
    Write-Host "[SKIP] live --restricted probe (pass -RunLive to exercise it; spends real API budget)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "== Results: $testsPassed passed, $testsFailed failed ==" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host ""

if ($testsFailed -gt 0) { exit 1 } else { exit 0 }
