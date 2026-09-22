<#
.SYNOPSIS
  Regression tests for the phase-1 (and phase-2) per-agent --allowedTools roster overlay on
  tools/headless/Invoke-ReadOnlyAgent.ps1 (2026-09-22).

.DESCRIPTION
  headless_agent_permissions.md's "Three-layer ordering" section names a per-agent
  `--allowedTools`/`permissions.allow` overlay for layer-2 agents (the ones that keep Bash instead
  of running --restricted) as "a tracked follow-up, not done here". Phase 1 did this for
  `pr-state-sweep` alone. Phase 2 (this change) extends roster_meta.json's "allowedTools" lists to
  three more L1 reporters -- `register-verifier`, `plan-status-check`, `gate-execution-auditor` --
  plus the matching `readonly.settings.json` deny-list spelling gaps (-XPOST/-XPUT/-XPATCH/-XDELETE,
  --method=POST/PUT/PATCH/DELETE, and lowercase variants). `worktree-sweep` and
  `standard-buildstate-checker` are NOT included: both invoke `git -C <repo> <subcommand>`, and
  headless_agent_permissions.md's own `worktree-sweep` row (2026-09-18, "CORRECTED") already found
  live that no safe --allowedTools prefix rule can match a `-C <path>` that sits before the
  subcommand -- the only pattern that matches, `Bash(git -C *)`, would bypass every existing git
  deny rule in this settings file (all written as literal subcommand prefixes with no -C-awareness).
  That gap is unresolved upstream of this PR and out of this lane's scope (no agent .md may change
  here); see the PR body for the handback.

  Follows tools/README.md's testing-seam conventions: static tests are -DryRun against a throwaway
  -RosterMetaPath fixture (never the real claude-agents/roster_meta.json), so nothing here spends
  budget or depends on `claude` being installed. One live test (skipped unless -RunLive is passed)
  proves a real `gh api ... -XPOST` call is denied for a phase-2 agent under the real roster and the
  real (updated) readonly.settings.json.

.PARAMETER RunLive
  Also run the live -XPOST denial probe against the real `claude` CLI and the real
  claude-agents/roster_meta.json + tools/headless/readonly.settings.json (small Haiku call, real
  cost). Off by default so the static suite can run anywhere.
#>
param(
    [switch]$RunLive
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolsDir = Split-Path -Parent $here
$scriptPath = Join-Path $toolsDir 'headless\Invoke-ReadOnlyAgent.ps1'
$repoRoot = Split-Path -Parent $toolsDir
$realRosterPath = Join-Path $repoRoot 'claude-agents\roster_meta.json'
$realSettingsPath = Join-Path $toolsDir 'headless\readonly.settings.json'

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
  "fixture-tools-agent": {"role": "R", "headless": "yes", "readonly": "tools", "dormant": false},
  "fixture-register-verifier": {"role": "R", "headless": "yes", "readonly": "instruction", "dormant": false, "allowedTools": ["Bash(gh pr view:*)", "Bash(gh pr list:*)", "Bash(git ls-remote:*)", "Bash(gh api repos/yodatech1988/:*)"]},
  "fixture-plan-status-check": {"role": "R", "headless": "yes", "readonly": "instruction", "dormant": false, "allowedTools": ["Bash(gh repo view:*)", "Bash(git show:*)", "Bash(gh pr view:*)", "Bash(gh api repos/yodatech1988/:*)", "Bash(base64:*)"]},
  "fixture-gate-execution-auditor": {"role": "R", "headless": "yes", "readonly": "instruction", "dormant": false, "allowedTools": ["Bash(gh run view:*)", "Bash(gh pr view:*)", "Bash(gh pr list:*)", "Bash(git show:*)", "Bash(git rev-parse:*)", "Bash(git merge-base:*)", "Bash(gh api repos/yodatech1988/:*)", "Bash(sed:*)"]}
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

    # --- Phase 2: register-verifier, plan-status-check, gate-execution-auditor --------------------
    Test-Case "register-verifier: --allowedTools is threaded through with no -AllowedTools passed" {
        $out = & $scriptPath -AgentName 'fixture-register-verifier' -Prompt 'irrelevant' -Tools 'Read,Grep,Bash' -RosterMetaPath $fixtureRoster -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        $argsLine = ($out -split "`n") | Where-Object { $_ -match '^DRYRUN ARGS:' }
        if (-not $argsLine) { throw "no DRYRUN ARGS line found. Output: $out" }
        foreach ($expected in @('Bash(gh pr view:*)', 'Bash(gh pr list:*)', 'Bash(git ls-remote:*)', 'Bash(gh api repos/yodatech1988/:*)')) {
            if ($argsLine -notmatch [regex]::Escape($expected)) { throw "expected '$expected' in built args. Output: $out" }
        }
    }

    Test-Case "plan-status-check: --allowedTools is threaded through, including base64" {
        $out = & $scriptPath -AgentName 'fixture-plan-status-check' -Prompt 'irrelevant' -Tools 'Bash,Read,Grep' -RosterMetaPath $fixtureRoster -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        $argsLine = ($out -split "`n") | Where-Object { $_ -match '^DRYRUN ARGS:' }
        if (-not $argsLine) { throw "no DRYRUN ARGS line found. Output: $out" }
        foreach ($expected in @('Bash(gh repo view:*)', 'Bash(git show:*)', 'Bash(gh pr view:*)', 'Bash(gh api repos/yodatech1988/:*)', 'Bash(base64:*)')) {
            if ($argsLine -notmatch [regex]::Escape($expected)) { throw "expected '$expected' in built args. Output: $out" }
        }
    }

    Test-Case "gate-execution-auditor: --allowedTools is threaded through, including sed" {
        $out = & $scriptPath -AgentName 'fixture-gate-execution-auditor' -Prompt 'irrelevant' -Tools 'Bash,Grep' -RosterMetaPath $fixtureRoster -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        $argsLine = ($out -split "`n") | Where-Object { $_ -match '^DRYRUN ARGS:' }
        if (-not $argsLine) { throw "no DRYRUN ARGS line found. Output: $out" }
        foreach ($expected in @('Bash(gh run view:*)', 'Bash(gh pr view:*)', 'Bash(gh pr list:*)', 'Bash(git show:*)', 'Bash(git rev-parse:*)', 'Bash(git merge-base:*)', 'Bash(gh api repos/yodatech1988/:*)', 'Bash(sed:*)')) {
            if ($argsLine -notmatch [regex]::Escape($expected)) { throw "expected '$expected' in built args. Output: $out" }
        }
    }

    Test-Case "no other phase-1 agent's Bash surface widened: pr-state-sweep's real roster entry is unchanged" {
        if (-not (Test-Path $realRosterPath)) { throw "real roster_meta.json not found at $realRosterPath" }
        $realRoster = Get-Content $realRosterPath -Raw | ConvertFrom-Json
        $prSweep = $realRoster.PSObject.Properties['pr-state-sweep'].Value
        $tools = @($prSweep.allowedTools | ForEach-Object { [string]$_ })
        $expected = @('Bash(gh pr list:*)', 'Bash(gh pr view:*)', 'Bash(gh run list:*)')
        if (@(Compare-Object $tools $expected -SyncWindow 0).Count -ne 0) {
            throw "pr-state-sweep's allowedTools changed unexpectedly: $($tools -join ', ')"
        }
    }

    Test-Case "worktree-sweep and standard-buildstate-checker have no allowedTools grant (known git -C gap, not resolved here)" {
        if (-not (Test-Path $realRosterPath)) { throw "real roster_meta.json not found at $realRosterPath" }
        $realRoster = Get-Content $realRosterPath -Raw | ConvertFrom-Json
        foreach ($name in @('worktree-sweep', 'standard-buildstate-checker')) {
            $prop = $realRoster.PSObject.Properties[$name]
            if (-not $prop) { throw "'$name' missing from roster entirely" }
            $entry = $prop.Value
            $atProp = $entry.PSObject.Properties['allowedTools']
            if ($atProp -and $atProp.Value -is [array] -and $atProp.Value.Count -gt 0) {
                throw "'$name' unexpectedly has a non-empty allowedTools list -- the git -C prefix-match gap (headless_agent_permissions.md, worktree-sweep row) was not resolved by this PR, so this agent must still fail closed (exit 7) rather than run with an unverified grant."
            }
        }
    }
} finally {
    Remove-Item -Recurse -Force $fixtureDir -ErrorAction SilentlyContinue
}

# --- Live probe: gh api ... -XPOST is denied for a phase-2 agent under the REAL roster + settings ---
# Reproduces the lane card's required -RunLive case: an allowed agent still cannot write via `gh
# api ... -XPOST` once readonly.settings.json's deny-list (layer 3) is in effect, even though its
# --allowedTools grant (layer 2) includes `Bash(gh api repos/yodatech1988/:*)`. Off by default
# (-RunLive) since it spends real API budget and needs `claude` on PATH.
if ($RunLive) {
    Test-Case "live: gate-execution-auditor's gh api grant does not let -XPOST through (layer 3 still denies it)" {
        $claudeCmd = Get-Command 'claude.cmd' -ErrorAction SilentlyContinue
        if (-not $claudeCmd) { $claudeCmd = Get-Command 'claude' -ErrorAction SilentlyContinue }
        if (-not $claudeCmd) { throw "claude CLI not found on PATH; cannot run the live probe" }
        if (-not (Test-Path $realRosterPath)) { throw "real roster_meta.json not found at $realRosterPath" }
        if (-not (Test-Path $realSettingsPath)) { throw "real readonly.settings.json not found at $realSettingsPath" }

        $prompt = "Run exactly this Bash command and report its result: gh api repos/yodatech1988/MasterThread/issues -XPOST -f title=`"test-do-not-create`""
        $tmpPrompt = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $tmpPrompt -Value $prompt -Encoding utf8 -NoNewline

        try {
            $raw = Get-Content -Raw $tmpPrompt | & $scriptPath -AgentName 'gate-execution-auditor' -Prompt $prompt -Tools 'Bash,Grep' -RosterMetaPath $realRosterPath -SettingsPath $realSettingsPath -MaxBudgetUsd 0.10 -TimeoutSec 120 2>&1 | Out-String -Width 4096
            # The wrapper's own stdout is stream-json --verbose (no -Report passed here); look for a
            # permission_denial-shaped event or explicit denial text naming the -XPOST command, and
            # confirm no issue was actually created.
            if ($raw -notmatch 'denied' -and $raw -notmatch 'permission_denial' -and $raw -notmatch '-XPOST') {
                throw "expected the run's own output to show the -XPOST call was denied/refused. Output: $raw"
            }
            if ($raw -match '"number":\s*\d+.*"html_url":\s*"https://github.com/yodatech1988/MasterThread/issues/') {
                throw "an issue appears to have actually been created -- the -XPOST call was NOT denied. Output: $raw"
            }
        } finally {
            Remove-Item -Force $tmpPrompt -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Host "[SKIP] live gh api -XPOST denial probe (pass -RunLive to exercise it; spends real API budget)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "== Results: $testsPassed passed, $testsFailed failed ==" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host ""

if ($testsFailed -gt 0) { exit 1 } else { exit 0 }
