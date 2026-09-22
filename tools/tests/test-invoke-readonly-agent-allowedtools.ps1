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

  v2 (merge-seat hold on #225, head a7eea7a3): two layer-3 gaps found in review, both fixed here,
  same three-file surface:
  (1) `gh api` defaults to POST when any field parameter is present (`gh api --help`, gh 2.100.0:
  "The default HTTP request method is GET normally and POST if any parameters were added"), so
  `gh api repos/yodatech1988/MasterThread/issues -f title=x` writes with no `-X` at all and matched
  no existing deny rule (all keyed on `-X`/`--method`). Fixed by denying `-f`/`-F`/`--field`/
  `--raw-field`/`--input`, space and `=` forms, on `gh api *`. None of the three granted agents'
  documented commands use a field flag (checked live against all three `claude-agents/*.md` bodies
  again for this fix) -- nothing legitimate is lost.
  (2) `Bash(sed:*)` was a whole-program grant with no in-place-edit deny rule, so `sed -i` was an
  unrestricted local file write. Fixed by dropping `sed` from `gate-execution-auditor`'s grant
  entirely (rather than adding in-place-only deny rules) -- the agent's own body already documents a
  `jq`-only alternative for the one place it used `sed` (BOM-stripping: `sed '1s/^\xEF\xBB\xBF//'`,
  or in `jq`, `sub("^\\uFEFF";"")` -- both given in the body's own "Gotchas" section), so no
  documented capability is lost and the risk is removed rather than narrowed.

  Follows tools/README.md's testing-seam conventions: static tests are -DryRun against a throwaway
  -RosterMetaPath fixture (never the real claude-agents/roster_meta.json), so nothing here spends
  budget or depends on `claude` being installed. Live tests (skipped unless -RunLive is passed)
  prove a real `gh api ... -XPOST` call AND a real `gh api ... -f ...` (implicit-POST) call are both
  denied for a phase-2 agent under the real roster and the real (updated) readonly.settings.json.

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
  "fixture-gate-execution-auditor": {"role": "R", "headless": "yes", "readonly": "instruction", "dormant": false, "allowedTools": ["Bash(gh run view:*)", "Bash(gh pr view:*)", "Bash(gh pr list:*)", "Bash(git show:*)", "Bash(git rev-parse:*)", "Bash(git merge-base:*)", "Bash(gh api repos/yodatech1988/:*)"]}
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

    Test-Case "gate-execution-auditor: --allowedTools is threaded through, and sed is NOT granted (v2 fix)" {
        $out = & $scriptPath -AgentName 'fixture-gate-execution-auditor' -Prompt 'irrelevant' -Tools 'Bash,Grep' -RosterMetaPath $fixtureRoster -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        $argsLine = ($out -split "`n") | Where-Object { $_ -match '^DRYRUN ARGS:' }
        if (-not $argsLine) { throw "no DRYRUN ARGS line found. Output: $out" }
        foreach ($expected in @('Bash(gh run view:*)', 'Bash(gh pr view:*)', 'Bash(gh pr list:*)', 'Bash(git show:*)', 'Bash(git rev-parse:*)', 'Bash(git merge-base:*)', 'Bash(gh api repos/yodatech1988/:*)')) {
            if ($argsLine -notmatch [regex]::Escape($expected)) { throw "expected '$expected' in built args. Output: $out" }
        }
        if ($argsLine -match [regex]::Escape('Bash(sed:*)')) { throw "sed must not be granted (v2 fix: sed -i was an unrestricted local write with no in-place deny rule; dropped in favor of the agent's own documented jq alternative). Output: $out" }
    }

    Test-Case "readonly.settings.json (v2): gh api field-flag deny rules are present, space and equals forms" {
        if (-not (Test-Path $realSettingsPath)) { throw "real readonly.settings.json not found at $realSettingsPath" }
        $settingsRaw = Get-Content $realSettingsPath -Raw | ConvertFrom-Json
        $denyRules = @($settingsRaw.permissions.deny | ForEach-Object { [string]$_ })
        $expectedDenies = @(
            'Bash(gh api * -f *)', 'Bash(gh api * -f*)',
            'Bash(gh api * -F *)', 'Bash(gh api * -F*)',
            'Bash(gh api * --field *)', 'Bash(gh api * --field=*)',
            'Bash(gh api * --raw-field *)', 'Bash(gh api * --raw-field=*)',
            'Bash(gh api * --input *)', 'Bash(gh api * --input=*)'
        )
        foreach ($rule in $expectedDenies) {
            if ($denyRules -notcontains $rule) { throw "expected deny rule '$rule' in readonly.settings.json's permissions.deny list -- not found. Present rules: $($denyRules -join ', ')" }
        }
    }

    Test-Case "readonly.settings.json (v2): no existing deny rule was removed or loosened (superset of the v1/phase-1 baseline)" {
        if (-not (Test-Path $realSettingsPath)) { throw "real readonly.settings.json not found at $realSettingsPath" }
        $settingsRaw = Get-Content $realSettingsPath -Raw | ConvertFrom-Json
        $denyRules = @($settingsRaw.permissions.deny | ForEach-Object { [string]$_ })
        # The v1 baseline this branch was reviewed against (PR #225 head a7eea7a3): every rule that
        # existed there must still be present verbatim.
        $v1Baseline = @(
            'Write', 'Edit', 'NotebookEdit',
            'Bash(git push *)', 'Bash(git commit *)', 'Bash(git reset *)', 'Bash(git checkout *)',
            'Bash(git restore *)', 'Bash(git clean *)', 'Bash(git worktree remove *)',
            'Bash(git worktree prune *)', 'Bash(git branch -D *)', 'Bash(git branch -d *)',
            'Bash(git stash *)', 'Bash(git merge *)', 'Bash(git rebase *)', 'Bash(git cherry-pick *)',
            'Bash(git tag -d *)', 'Bash(git tag --delete *)', 'Bash(git rm *)', 'Bash(git gc *)',
            'Bash(git reflog expire *)', 'Bash(git filter-branch *)', 'Bash(git filter-repo *)',
            'Bash(gh pr merge *)', 'Bash(gh pr close *)', 'Bash(gh pr create *)', 'Bash(gh pr edit *)',
            'Bash(gh pr comment *)', 'Bash(gh pr review *)', 'Bash(gh pr checkout *)',
            'Bash(gh issue create *)', 'Bash(gh issue close *)', 'Bash(gh issue edit *)',
            'Bash(gh issue comment *)', 'Bash(gh repo edit *)', 'Bash(gh repo delete *)',
            'Bash(gh repo archive *)', 'Bash(gh repo rename *)', 'Bash(gh secret set *)',
            'Bash(gh secret delete *)', 'Bash(gh variable set *)', 'Bash(gh variable delete *)',
            'Bash(gh workflow run *)', 'Bash(gh workflow enable *)', 'Bash(gh workflow disable *)',
            'Bash(gh release create *)', 'Bash(gh release delete *)', 'Bash(gh release edit *)',
            'Bash(gh auth login *)', 'Bash(gh auth logout *)',
            'Bash(gh api * -X POST *)', 'Bash(gh api * -X PUT *)', 'Bash(gh api * -X PATCH *)', 'Bash(gh api * -X DELETE *)',
            'Bash(gh api * --method POST *)', 'Bash(gh api * --method PUT *)', 'Bash(gh api * --method PATCH *)', 'Bash(gh api * --method DELETE *)',
            'Bash(gh api * -XPOST *)', 'Bash(gh api * -XPUT *)', 'Bash(gh api * -XPATCH *)', 'Bash(gh api * -XDELETE *)',
            'Bash(gh api * --method=POST *)', 'Bash(gh api * --method=PUT *)', 'Bash(gh api * --method=PATCH *)', 'Bash(gh api * --method=DELETE *)',
            'Bash(gh api * -xpost *)', 'Bash(gh api * -xput *)', 'Bash(gh api * -xpatch *)', 'Bash(gh api * -xdelete *)',
            'Bash(gh api * --method post *)', 'Bash(gh api * --method put *)', 'Bash(gh api * --method patch *)', 'Bash(gh api * --method delete *)',
            'Bash(gh api * --method=post *)', 'Bash(gh api * --method=put *)', 'Bash(gh api * --method=patch *)', 'Bash(gh api * --method=delete *)',
            'Bash(rm *)', 'Bash(rmdir *)', 'Bash(del *)', 'Bash(mv *)', 'Bash(shred *)',
            'PowerShell(Remove-Item *)', 'PowerShell(Move-Item *)', 'PowerShell(Set-Content *)',
            'PowerShell(Out-File *)', 'PowerShell(Clear-Content *)', 'PowerShell(Rename-Item *)',
            'Bash(curl *)', 'Bash(wget *)', 'PowerShell(Invoke-WebRequest *)', 'PowerShell(Invoke-RestMethod *)',
            'PowerShell(iwr *)', 'PowerShell(irm *)',
            'Bash(ssh * sudo *)', 'Bash(ssh * systemctl *)', 'Bash(ssh * rm *)', 'Bash(ssh * reboot *)',
            'Bash(ssh * shutdown *)', 'Bash(ssh * passwd *)', 'Bash(ssh * useradd *)', 'Bash(ssh * usermod *)',
            'Bash(ssh * > *)', 'Bash(ssh * >> *)', 'Bash(scp *)', 'Bash(rsync *)', 'Bash(sftp *)',
            'Bash(npm install *)', 'Bash(npm i *)', 'Bash(npm publish *)', 'Bash(npm uninstall *)', 'Bash(npm ci *)',
            'Bash(pip install *)', 'Bash(pip3 install *)', 'Bash(pip uninstall *)',
            'Bash(wrangler deploy *)', 'Bash(wrangler publish *)',
            'Bash(taskkill *)', 'PowerShell(Stop-Process *)', 'PowerShell(Stop-Service *)',
            'PowerShell(Restart-Service *)', 'PowerShell(Restart-Computer *)', 'PowerShell(Stop-Computer *)',
            'PowerShell(Invoke-Expression *)', 'PowerShell(iex *)', 'Bash(eval *)', 'Bash(sudo *)',
            'Bash(chmod *)', 'Bash(chown *)',
            'Agent(claude)', 'Agent(general-purpose)'
        )
        $missing = $v1Baseline | Where-Object { $denyRules -notcontains $_ }
        if ($missing.Count -gt 0) { throw "v1 baseline deny rule(s) missing on this head (loosened or removed): $($missing -join ', ')" }
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

    # v2 addition: the merge-seat hold's blocking finding (1) is specifically the IMPLICIT-POST
    # form -- `gh api ... -f ...` with no `-X`/`--method` at all, which gh itself defaults to POST
    # (gh 2.100.0 `gh api --help`: "The default HTTP request method is GET normally and POST if any
    # parameters were added"). The -XPOST probe above only proves the explicit form is caught; this
    # probe proves the new `-f`/`-F`/`--field`/`--raw-field`/`--input` deny rules catch the implicit
    # form too.
    Test-Case "live: gate-execution-auditor's gh api grant does not let an implicit-POST -f call through (v2 fix)" {
        $claudeCmd = Get-Command 'claude.cmd' -ErrorAction SilentlyContinue
        if (-not $claudeCmd) { $claudeCmd = Get-Command 'claude' -ErrorAction SilentlyContinue }
        if (-not $claudeCmd) { throw "claude CLI not found on PATH; cannot run the live probe" }
        if (-not (Test-Path $realRosterPath)) { throw "real roster_meta.json not found at $realRosterPath" }
        if (-not (Test-Path $realSettingsPath)) { throw "real readonly.settings.json not found at $realSettingsPath" }

        $prompt = "Run exactly this Bash command and report its result: gh api repos/yodatech1988/MasterThread/issues -f title=`"test-do-not-create-implicit-post`""
        $tmpPrompt = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $tmpPrompt -Value $prompt -Encoding utf8 -NoNewline

        try {
            $raw = Get-Content -Raw $tmpPrompt | & $scriptPath -AgentName 'gate-execution-auditor' -Prompt $prompt -Tools 'Bash,Grep' -RosterMetaPath $realRosterPath -SettingsPath $realSettingsPath -MaxBudgetUsd 0.10 -TimeoutSec 120 2>&1 | Out-String -Width 4096
            if ($raw -notmatch 'denied' -and $raw -notmatch 'permission_denial' -and $raw -notmatch '-f ') {
                throw "expected the run's own output to show the implicit-POST -f call was denied/refused. Output: $raw"
            }
            if ($raw -match '"number":\s*\d+.*"html_url":\s*"https://github.com/yodatech1988/MasterThread/issues/') {
                throw "an issue appears to have actually been created -- the implicit-POST -f call was NOT denied. Output: $raw"
            }
        } finally {
            Remove-Item -Force $tmpPrompt -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Host "[SKIP] live gh api -XPOST / implicit-POST -f denial probes (pass -RunLive to exercise them; spends real API budget)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "== Results: $testsPassed passed, $testsFailed failed ==" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host ""

if ($testsFailed -gt 0) { exit 1 } else { exit 0 }
