<#
.SYNOPSIS
  Regression tests for the phase-1 per-agent --allowedTools roster overlay on
  tools/headless/Invoke-ReadOnlyAgent.ps1 (2026-09-22).

.DESCRIPTION
  headless_agent_permissions.md's "Three-layer ordering" section names a per-agent
  `--allowedTools`/`permissions.allow` overlay for layer-2 agents (the ones that keep Bash instead
  of running --restricted) as "a tracked follow-up, not done here". This is that follow-up, scoped
  to whichever agent(s) claude-agents/roster_meta.json actually carries a non-empty
  "allowedTools" array for -- as of this change, only `pr-state-sweep`.

  Follows tools/README.md's testing-seam conventions: every test here is -DryRun against a
  throwaway -RosterMetaPath fixture (never the real claude-agents/roster_meta.json), so nothing
  here spends budget or depends on `claude` being installed.
#>

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
Write-Host "== Phase-1 allowedTools roster overlay regression tests" -ForegroundColor Cyan
Write-Host ""

Test-Case "Invoke-ReadOnlyAgent.ps1 exists" {
    if (-not (Test-Path $scriptPath)) { throw "File not found at $scriptPath" }
}

# --- Fixture roster_meta.json (test seam: never the real file) ---------------------------------
$fixtureDir = Join-Path ([System.IO.Path]::GetTempPath()) ("allowedtools-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null
$fixtureRoster = Join-Path $fixtureDir 'roster_meta.json'
@'
{
  "fixture-pr-state-sweep": {"role": "R", "headless": "yes", "readonly": "instruction", "dormant": false, "allowedTools": ["Bash(gh pr list:*)", "Bash(gh pr view:*)", "Bash(gh run list:*)"]},
  "fixture-no-list-agent": {"role": "R", "headless": "yes", "readonly": "instruction", "dormant": false},
  "fixture-empty-list-agent": {"role": "R", "headless": "yes", "readonly": "instruction", "dormant": false, "allowedTools": []},
  "fixture-non-bash-agent": {"role": "R", "headless": "yes", "readonly": "instruction", "dormant": false},
  "fixture-tools-agent": {"role": "R", "headless": "yes", "readonly": "tools", "dormant": false}
}
'@ | Set-Content -Path $fixtureRoster -Encoding utf8

try {
    Test-Case "agent with a roster allowedTools list: --allowedTools is threaded through with no -AllowedTools passed" {
        $out = & $scriptPath -AgentName 'fixture-pr-state-sweep' -Prompt 'irrelevant' -Tools 'Bash,Grep' -RosterMetaPath $fixtureRoster -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        $argsLine = ($out -split "`n") | Where-Object { $_ -match '^DRYRUN ARGS:' }
        if (-not $argsLine) { throw "no DRYRUN ARGS line found. Output: $out" }
        if ($argsLine -notmatch '--allowedTools') { throw "expected --allowedTools in built args. Output: $out" }
        if ($argsLine -notmatch [regex]::Escape('Bash(gh pr list:*)')) { throw "expected the roster's first entry in built args. Output: $out" }
        if ($argsLine -notmatch [regex]::Escape('Bash(gh pr view:*)')) { throw "expected the roster's second entry in built args. Output: $out" }
        if ($argsLine -notmatch [regex]::Escape('Bash(gh run list:*)')) { throw "expected the roster's third entry in built args. Output: $out" }
    }

    Test-Case "explicit -AllowedTools on the command line wins over the roster lookup" {
        $out = & $scriptPath -AgentName 'fixture-pr-state-sweep' -Prompt 'irrelevant' -Tools 'Bash' -AllowedTools 'Bash(git status:*)' -RosterMetaPath $fixtureRoster -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        $argsLine = ($out -split "`n") | Where-Object { $_ -match '^DRYRUN ARGS:' }
        if ($argsLine -notmatch [regex]::Escape('Bash(git status:*)')) { throw "expected the explicit -AllowedTools value in built args. Output: $out" }
        if ($argsLine -match [regex]::Escape('Bash(gh pr list:*)')) { throw "explicit -AllowedTools must win over the roster's list, not merge with it. Output: $out" }
    }

    Test-Case "Bash-holding agent with NO roster allowedTools list is refused with exit 7, naming the agent" {
        & $scriptPath -AgentName 'fixture-no-list-agent' -Prompt 'irrelevant' -Tools 'Bash' -RosterMetaPath $fixtureRoster -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 7) { throw "expected exit 7, got $LASTEXITCODE" }
    }

    Test-Case "exit 7's error message names the agent and mentions allowedTools" {
        $out = & $scriptPath -AgentName 'fixture-no-list-agent' -Prompt 'irrelevant' -Tools 'Bash' -RosterMetaPath $fixtureRoster -DryRun *>&1 | Out-String -Width 4096
        if ($out -notmatch 'fixture-no-list-agent') { throw "expected the agent name in the refusal message. Output: $out" }
        if ($out -notmatch 'allowedTools') { throw "expected 'allowedTools' in the refusal message. Output: $out" }
    }

    Test-Case "Bash-holding agent with an EMPTY roster allowedTools array is also refused with exit 7" {
        & $scriptPath -AgentName 'fixture-empty-list-agent' -Prompt 'irrelevant' -Tools 'Bash' -RosterMetaPath $fixtureRoster -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 7) { throw "expected exit 7 for an empty allowedTools array, got $LASTEXITCODE" }
    }

    Test-Case "agent not listed in roster at all, Bash-holding, is refused with exit 7 (not exit 4 -- that's the -Restricted lookup's own code)" {
        & $scriptPath -AgentName 'not-in-the-fixture-at-all' -Prompt 'irrelevant' -Tools 'Bash' -Restricted:$false -RosterMetaPath $fixtureRoster -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 7) { throw "expected exit 7, got $LASTEXITCODE" }
    }

    Test-Case "missing roster_meta.json file, Bash-holding agent -> exit 7, not a crash" {
        & $scriptPath -AgentName 'fixture-no-list-agent' -Prompt 'irrelevant' -Tools 'Bash' -Restricted:$false -RosterMetaPath (Join-Path $fixtureDir 'does-not-exist.json') -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 7) { throw "expected exit 7, got $LASTEXITCODE" }
    }

    Test-Case "malformed roster_meta.json file, Bash-holding agent -> exit 7, not a crash" {
        $badRoster = Join-Path $fixtureDir 'bad-roster.json'
        Set-Content -Path $badRoster -Value '{ not valid json' -Encoding utf8
        & $scriptPath -AgentName 'fixture-no-list-agent' -Prompt 'irrelevant' -Tools 'Bash' -Restricted:$false -RosterMetaPath $badRoster -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 7) { throw "expected exit 7, got $LASTEXITCODE" }
    }

    Test-Case "a non-Bash/PowerShell -Tools agent is never gated by exit 7, even with no roster list" {
        $out = & $scriptPath -AgentName 'fixture-non-bash-agent' -Prompt 'irrelevant' -Tools 'Read,Grep' -RosterMetaPath $fixtureRoster -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0 (no Bash/PowerShell in -Tools -> exit 7 gate must not fire), got $LASTEXITCODE. Output: $out" }
        if ($out -match '--allowedTools') { throw "no --allowedTools should be added for an agent with no Bash/PowerShell in -Tools. Output: $out" }
    }

    Test-Case "a restricted agent is never gated by exit 7, even though it has no roster allowedTools list" {
        $out = & $scriptPath -AgentName 'fixture-tools-agent' -Prompt 'irrelevant' -RosterMetaPath $fixtureRoster -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0 (restricted run must never hit the allowedTools gate), got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch '--restricted') { throw "expected --restricted in built args. Output: $out" }
    }

    Test-Case "PowerShell in -Tools (not just Bash) also requires a roster allowedTools list" {
        & $scriptPath -AgentName 'fixture-no-list-agent' -Prompt 'irrelevant' -Tools 'PowerShell' -RosterMetaPath $fixtureRoster -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 7) { throw "expected exit 7, got $LASTEXITCODE" }
    }
} finally {
    Remove-Item -Recurse -Force $fixtureDir -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "== Results: $testsPassed passed, $testsFailed failed ==" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host ""

if ($testsFailed -gt 0) { exit 1 } else { exit 0 }
