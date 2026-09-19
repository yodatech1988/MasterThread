<#
.SYNOPSIS
  Owner-run. Adds a fixed, owner-approved merge-permission rule set to
  C:\Users\yoda_\GitHub\.claude\settings.json (project settings) -- one allow rule that lets a
  session merge a PR by squash only when its local view matches the PR's real head commit, and
  two deny rules that block any `--admin` override of branch protection.

.DESCRIPTION
  AUTHORITY:
    - Ops Decision Queue card "merge-seat-how-to-enforce-route-b-2026-09-18", owner resolution at
      2026-09-18T02:02:47.905Z: "C: Both - the narrow rule now, and the auditor as the control
      that actually holds." This script is "the narrow rule now" half of that decision. The
      other half -- gate-execution-auditor's merge-route mode acting as the detective control
      that reports an out-of-route merge after the fact -- is a separate piece of work, not
      built by this script.
    - Upstream: Ops Decision Queue card "denial-merge-seat-blocked-by-classifier-2026-09-18",
      resolved 01:35Z: "Allow a session to merge only where merge_authority.md route B already
      permits it." Route B is squash-merge with the local view matching the PR's real head
      commit -- never an admin override of a failing/blocked check.

  Target file: C:\Users\yoda_\GitHub\.claude\settings.json. This file now EXISTS (written by the
  01:06Z AEGIS-Allow-PM-Seat-Tools.ps1 run) with 14 entries in permissions.allow and no
  permissions.deny key. This script merges into the EXISTING permissions.allow array and creates
  permissions.deny (currently absent) with the two entries below, preserving every other key and
  entry byte-for-byte as far as JSON round-tripping allows (2-space indent). It never touches
  hooks or any other top-level key, and never touches settings.local.json.

  THE EXACT RULES ADDED, AND NO OTHERS (a superset is a violation of the approved card):
    permissions.allow  += "Bash(gh pr merge --squash --match-head-commit *)"
    permissions.deny   += "Bash(gh pr merge --admin*)"
    permissions.deny   += "Bash(gh pr merge * --admin*)"

  WHY TWO DENY RULES, NOT ONE (verified empirically 2026-09-18, put here so the next person does
  not "tidy" this into one rule): a Claude Code permission deny pattern of the shape
  `Bash(x * --flag*)` matches the flag token only when something precedes it after the leading
  literal -- it does NOT match a command where the flag sits immediately after the subcommand
  with nothing between (e.g. `gh pr merge --admin 123` has no token between `merge` and
  `--admin` for the `*` in `Bash(gh pr merge * --admin*)` to consume). Tested tonight against
  both call shapes (`gh pr merge --admin <n>` and `gh pr merge <n> --admin`): only
  `Bash(gh pr merge --admin*)` catches the first shape and only `Bash(gh pr merge * --admin*)`
  catches the second. One rule alone leaves the other call shape's override open, which defeats
  the entire point of denying `--admin`. Both rules stay, permanently.

  This is a permission-settings change (a repo/session security setting), not a code change. No
  Claude session applies it; this script refuses to run unless a person started it from a real
  console (stdin not redirected) and types YES. This script never runs `gh pr merge` in any form
  itself -- it only edits the JSON file that governs whether a FUTURE session may.

  Idempotent: if the allow entry and both deny entries are already present, it prints
  "ALREADY APPLIED - nothing to do", asks nothing, writes nothing, and exits 0.

  Refuses (exit 2) if: not an interactive console (and not -WhatIf), the existing file fails to
  parse as JSON, or permissions.allow/permissions.deny is present but not a JSON array.

  A timestamped .bak.<yyyyMMdd-HHmmss> copy of the existing file is written before the new file,
  and a timestamped .<yyyyMMdd-HHmmss>.log of the run is written next to this script on EVERY
  exit path (success, cancel, refuse, -WhatIf, exception), per MasterThread tools/README.md's
  "An owner-run click-file logs every exit path" -- one outer try/catch/finally with
  Write-RunLog in finally, an outcome variable set immediately before every exit, and the real
  write wrapped in its own try/catch that never falls through to success text it did not earn.

  Rollback: restore the .bak.<timestamp> copy over settings.json, or manually remove the three
  entries listed above from permissions.allow / permissions.deny.

.PARAMETER WhatIf
  Show current allow+deny lists, the entries that would be added/skipped, and a before/after
  diff. Change nothing, ask nothing, write nothing. Safe for a Claude session to run against the
  REAL settings path.

.PARAMETER SettingsPath
  Override the target settings.json path. Defaults to
  C:\Users\yoda_\GitHub\.claude\settings.json. Intended for -WhatIf testing against a temp
  fixture; a real (non-WhatIf) run should use the default. A Claude session may run a
  non-WhatIf write ONLY against a non-default -SettingsPath under
  C:\Users\yoda_\AppData\Local\Temp\claude\ -- never against the real default without -WhatIf.
#>
[CmdletBinding()]
param(
    [switch]$WhatIf,
    [string]$SettingsPath = 'C:\Users\yoda_\GitHub\.claude\settings.json'
)

$ErrorActionPreference = 'Stop'

# --- run-log bookkeeping: a timestamped .log next to this script is written on EVERY
# terminating path (success, cancel, refuse, -WhatIf, exception) -- tools/README.md, "An
# owner-run click-file logs every exit path", fixed after the 2026-09-18 01:34Z incident where a
# script died mid-run with no trace. -------------------------------------------------------------
$script:RunStartTime = Get-Date
$script:TypedAnswer = 'n/a (no prompt reached)'
$script:RunOutcome = 'UNKNOWN (script exited without setting an outcome)'
$script:RunExceptionText = ''
$script:ResolvedPlanLines = @()
# Real vs dry run (tools/README.md "An owner-run click-file logs every exit path" sub-point,
# added after a 2026-09-18 blocked-work sweep had to read every log's body to tell them apart):
# stays $false for -WhatIf, a non-default -SettingsPath (test fixture), a refused precondition,
# or a cancel at the YES prompt -- becomes $true only right before the real write is attempted,
# so a real attempt that then throws still logs as real, never dry.
$script:IsRealAttempt = $false
$DefaultSettingsPath = 'C:\Users\yoda_\GitHub\.claude\settings.json'

function Write-RunLog {
    $suffix = if ($script:IsRealAttempt) { 'log' } else { 'dryrun.log' }
    $log = Join-Path $PSScriptRoot ("AEGIS-Allow-Seat-Merge.{0}.{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $suffix)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("RUN TYPE: $(if ($script:IsRealAttempt) { 'real' } else { 'dry run (nothing was changed)' })")
    $lines.Add("Start time (local): $($script:RunStartTime.ToString('o'))")
    $lines.Add("Target settings file: $SettingsPath")
    $lines.Add("WhatIf: $($WhatIf.IsPresent)")
    $lines.Add('')
    $lines.Add('Resolved plan:')
    foreach ($l in $script:ResolvedPlanLines) { $lines.Add("  $l") }
    $lines.Add('')
    $lines.Add("Owner typed: $($script:TypedAnswer)")
    $lines.Add("Outcome: $($script:RunOutcome)")
    if ($script:RunExceptionText) {
        $lines.Add('')
        $lines.Add('Exception:')
        $lines.Add($script:RunExceptionText)
    }
    try {
        $lines | Out-File -FilePath $log -Encoding utf8
        Write-Host "Log: $log"
    } catch {
        Write-Host "WARNING: could not write run log to $log`: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function ConvertTo-PrettyJson2Space {
    # PowerShell's own ConvertTo-Json indentation is inconsistent (e.g. brackets aligned to
    # the value's column). Re-indent a compact JSON string to a plain, stable 2-space style
    # so the diff and the written file are readable and match this repo's convention.
    param([Parameter(Mandatory)][string]$Compact)

    $sb = [System.Text.StringBuilder]::new()
    $indent = 0
    $inString = $false
    $escape = $false
    $len = $Compact.Length
    $i = 0
    while ($i -lt $len) {
        $ch = $Compact[$i]
        if ($inString) {
            [void]$sb.Append($ch)
            if ($escape) { $escape = $false }
            elseif ($ch -eq '\') { $escape = $true }
            elseif ($ch -eq '"') { $inString = $false }
            $i++
            continue
        }
        switch ($ch) {
            '"' { [void]$sb.Append($ch); $inString = $true; $i++ }
            '{' {
                $next = if ($i + 1 -lt $len) { $Compact[$i + 1] } else { '' }
                if ($next -eq '}') { [void]$sb.Append('{}'); $i += 2 }
                else { [void]$sb.Append("{`n"); $indent++; [void]$sb.Append(' ' * ($indent * 2)); $i++ }
            }
            '[' {
                $next = if ($i + 1 -lt $len) { $Compact[$i + 1] } else { '' }
                if ($next -eq ']') { [void]$sb.Append('[]'); $i += 2 }
                else { [void]$sb.Append("[`n"); $indent++; [void]$sb.Append(' ' * ($indent * 2)); $i++ }
            }
            '}' { $indent--; [void]$sb.Append("`n"); [void]$sb.Append(' ' * ($indent * 2)); [void]$sb.Append('}'); $i++ }
            ']' { $indent--; [void]$sb.Append("`n"); [void]$sb.Append(' ' * ($indent * 2)); [void]$sb.Append(']'); $i++ }
            ',' { [void]$sb.Append(",`n"); [void]$sb.Append(' ' * ($indent * 2)); $i++ }
            ':' { [void]$sb.Append(': '); $i++ }
            default { [void]$sb.Append($ch); $i++ }
        }
    }
    return $sb.ToString()
}

$ApprovedAllow = @(
    'Bash(gh pr merge --squash --match-head-commit *)'
)
$ApprovedDeny = @(
    'Bash(gh pr merge --admin*)',
    'Bash(gh pr merge * --admin*)'
)

try {

# --- initiation binding: a person at a real console, never a session's tool call ---------------
# A session may exercise the real write path (backup/write/verify) non-interactively ONLY against
# a test fixture under Temp\claude -- never against the default/real settings path. This is the
# exemption the header doc already promised; fixed 2026-09-18 to actually enforce it (found via
# the same doc/code mismatch in the sibling AEGIS-Narrow-Local-Allowlist.ps1, which previously
# refused every non-WhatIf run regardless of -SettingsPath, blocking the "prove it can fail"
# testing tools/README.md requires).
$isTestFixturePath = $SettingsPath.StartsWith('C:\Users\yoda_\AppData\Local\Temp\claude\', [StringComparison]::OrdinalIgnoreCase)
if (-not $WhatIf -and -not $isTestFixturePath) {
    if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
        Write-Host 'REFUSED: this must be started by the owner from a real console window (double-click the .cmd).' -ForegroundColor Red
        Write-Host 'A Claude session may only run it with -WhatIf, or with -SettingsPath pointed under' -ForegroundColor Red
        Write-Host 'C:\Users\yoda_\AppData\Local\Temp\claude\ -- never a non-WhatIf run against the real settings path.' -ForegroundColor Red
        $script:TypedAnswer = 'n/a (refused before any prompt)'
        $script:RunOutcome = 'REFUSED: not an interactive console and -WhatIf was not passed, and -SettingsPath is not a Temp\claude test fixture.'
        exit 2
    }
}

Write-Host "Target settings file: $SettingsPath"

$fileExists = Test-Path -LiteralPath $SettingsPath
$originalText = $null
$settingsObj = $null
$currentAllow = @()
$currentDeny = @()

if (-not $fileExists) {
    Write-Host 'Current allow list: file absent'
    Write-Host 'Current deny list: file absent'
} else {
    $originalText = Get-Content -LiteralPath $SettingsPath -Raw
    try {
        $settingsObj = $originalText | ConvertFrom-Json
    } catch {
        Write-Host "REFUSED: $SettingsPath exists but does not parse as valid JSON. Nothing changed." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        $script:RunOutcome = "REFUSED: $SettingsPath does not parse as valid JSON."
        $script:RunExceptionText = $_.Exception.Message
        exit 2
    }

    $hasPermissions = $settingsObj.PSObject.Properties.Name -contains 'permissions'

    if ($hasPermissions -and ($settingsObj.permissions.PSObject.Properties.Name -contains 'allow')) {
        $rawAllow = $settingsObj.permissions.allow
        if ($rawAllow -isnot [System.Collections.IEnumerable] -or $rawAllow -is [string]) {
            Write-Host "REFUSED: permissions.allow in $SettingsPath exists but is not a JSON array. Nothing changed." -ForegroundColor Red
            $script:RunOutcome = 'REFUSED: permissions.allow exists but is not a JSON array.'
            exit 2
        }
        $currentAllow = @($rawAllow)
    }

    if ($hasPermissions -and ($settingsObj.permissions.PSObject.Properties.Name -contains 'deny')) {
        $rawDeny = $settingsObj.permissions.deny
        if ($rawDeny -isnot [System.Collections.IEnumerable] -or $rawDeny -is [string]) {
            Write-Host "REFUSED: permissions.deny in $SettingsPath exists but is not a JSON array. Nothing changed." -ForegroundColor Red
            $script:RunOutcome = 'REFUSED: permissions.deny exists but is not a JSON array.'
            exit 2
        }
        $currentDeny = @($rawDeny)
    }

    Write-Host 'Current allow list:'
    if ($currentAllow.Count -eq 0) { Write-Host '  (empty)' }
    else { $currentAllow | ForEach-Object { Write-Host "  $_" } }

    Write-Host 'Current deny list:'
    if ($currentDeny.Count -eq 0) { Write-Host '  (empty / absent)' }
    else { $currentDeny | ForEach-Object { Write-Host "  $_" } }
}

$allowToAdd = @($ApprovedAllow | Where-Object { $currentAllow -notcontains $_ })
$allowAlready = @($ApprovedAllow | Where-Object { $currentAllow -contains $_ })
$denyToAdd = @($ApprovedDeny | Where-Object { $currentDeny -notcontains $_ })
$denyAlready = @($ApprovedDeny | Where-Object { $currentDeny -contains $_ })

Write-Host ''
Write-Host 'Approved entries already present (skipped):'
$already = @($allowAlready) + @($denyAlready)
if ($already.Count -eq 0) { Write-Host '  (none)' }
else { $already | ForEach-Object { Write-Host "  $_" } }

Write-Host ''
Write-Host 'Approved entries that will be added:'
$toAdd = @($allowToAdd) + @($denyToAdd)
if ($toAdd.Count -eq 0) { Write-Host '  (none)' }
else {
    $allowToAdd | ForEach-Object { Write-Host "  [allow] $_" }
    $denyToAdd | ForEach-Object { Write-Host "  [deny]  $_" }
}

$script:ResolvedPlanLines = @(
    "Allow to add: $($allowToAdd -join ', ')"
    "Deny to add: $($denyToAdd -join ', ')"
    "Already present: $($already -join ', ')"
)

# --- idempotent short-circuit: all three entries already present -> nothing to do --------------
if ($toAdd.Count -eq 0) {
    Write-Host ''
    Write-Host 'ALREADY APPLIED - nothing to do' -ForegroundColor Green
    $script:RunOutcome = 'ALREADY APPLIED: allow entry and both deny entries already present. No prompt, no write.'
    exit 0
}

# --- build proposed new content -----------------------------------------------------------------
if ($null -eq $settingsObj) {
    $newAllow = @($ApprovedAllow)
    $newDeny = @($ApprovedDeny)
    $newObj = [ordered]@{
        permissions = [ordered]@{
            allow = $newAllow
            deny  = $newDeny
        }
    }
} else {
    $newAllow = @($currentAllow) + @($allowToAdd)
    $newDeny = @($currentDeny) + @($denyToAdd)

    if (-not ($settingsObj.PSObject.Properties.Name -contains 'permissions')) {
        $settingsObj | Add-Member -NotePropertyName 'permissions' -NotePropertyValue ([ordered]@{ allow = $newAllow; deny = $newDeny })
    } else {
        if (-not ($settingsObj.permissions.PSObject.Properties.Name -contains 'allow')) {
            $settingsObj.permissions | Add-Member -NotePropertyName 'allow' -NotePropertyValue $newAllow
        } else {
            $settingsObj.permissions.allow = $newAllow
        }
        if (-not ($settingsObj.permissions.PSObject.Properties.Name -contains 'deny')) {
            $settingsObj.permissions | Add-Member -NotePropertyName 'deny' -NotePropertyValue $newDeny
        } else {
            $settingsObj.permissions.deny = $newDeny
        }
    }
    $newObj = $settingsObj
}

$compactJson = $newObj | ConvertTo-Json -Depth 20 -Compress
$newText = ConvertTo-PrettyJson2Space -Compact $compactJson
if (-not $newText.EndsWith("`n")) { $newText += "`n" }

Write-Host ''
Write-Host '================ Diff (before / after) ================' -ForegroundColor Cyan
$beforeLines = @(if ($null -ne $originalText) { $originalText -replace "`r`n", "`n" -split "`n" })
$afterLines = @($newText -split "`n")
if ($beforeLines.Count -eq 0) {
    Write-Host '(file was absent - entire new file is added)'
    $afterLines | ForEach-Object { Write-Host "+ $_" -ForegroundColor Green }
} else {
    foreach ($line in $beforeLines) {
        if ($afterLines -notcontains $line) { Write-Host "- $line" -ForegroundColor Red }
    }
    foreach ($line in $afterLines) {
        if ($beforeLines -notcontains $line) { Write-Host "+ $line" -ForegroundColor Green }
    }
}
Write-Host '========================================================='

Write-Host ''
Write-Host '=========================== WARNING ===========================' -ForegroundColor Yellow
Write-Host 'This lets a Claude Code session merge pull requests in this repo without asking you first' -ForegroundColor Yellow
Write-Host '-- but ONLY a squash merge where the session''s local view matches the PR''s real, current' -ForegroundColor Yellow
Write-Host 'head commit (gh pr merge --squash --match-head-commit).' -ForegroundColor Yellow
Write-Host ''
Write-Host 'The rule cannot express "only routine PRs." It has no idea what the PR contains -- it also' -ForegroundColor Yellow
Write-Host 'permits merging a PR that should have gone to you first, as long as the merge command' -ForegroundColor Yellow
Write-Host 'shape matches. There is no content judgment here at all.' -ForegroundColor Yellow
Write-Host ''
Write-Host 'The two deny rules block ONLY an --admin override (bypassing failing/blocked branch' -ForegroundColor Yellow
Write-Host 'protection checks). They do not block, limit, or review anything else about what gets' -ForegroundColor Yellow
Write-Host 'merged under the allow rule above.' -ForegroundColor Yellow
Write-Host ''
Write-Host 'This script is only the PREVENTIVE half of the owner''s decision (card' -ForegroundColor Yellow
Write-Host 'merge-seat-how-to-enforce-route-b-2026-09-18, option C). The DETECTIVE half -- the control' -ForegroundColor Yellow
Write-Host 'that actually catches a merge that happened outside route B -- is gate-execution-auditor''s' -ForegroundColor Yellow
Write-Host 'merge-route mode, which reports an out-of-route merge AFTER it happens. This rule alone' -ForegroundColor Yellow
Write-Host 'does not stop a wrong merge from being made; the auditor is what tells you it happened.' -ForegroundColor Yellow
Write-Host '=================================================================' -ForegroundColor Yellow

if ($WhatIf) {
    Write-Host ''
    Write-Host '-WhatIf: no changes written.' -ForegroundColor Yellow
    $script:TypedAnswer = 'n/a (-WhatIf never prompts)'
    $script:RunOutcome = '-WhatIf: plan and diff printed, nothing written.'
    exit 0
}

Write-Host ''
$answer = Read-Host 'Type YES to write these changes to settings.json (anything else cancels)'
$script:TypedAnswer = if ($answer -ceq 'YES') { 'YES' } else { 'cancelled' }
if ($answer -cne 'YES') {
    Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow
    $script:RunOutcome = 'Owner did not type YES. Cancelled, nothing changed.'
    exit 0
}

$script:IsRealAttempt = ($SettingsPath -eq $DefaultSettingsPath)

$backupPath = $null
try {
    if ($fileExists) {
        $backupPath = "$SettingsPath.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $SettingsPath -Destination $backupPath -Force
        Write-Host "Backup written: $backupPath"
    } else {
        $parentDir = Split-Path -Parent $SettingsPath
        if (-not (Test-Path -LiteralPath $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }
    }

    # UTF-8 WITHOUT a BOM: PowerShell 5.1's `-Encoding utf8` prefixes a BOM, and a BOM-prefixed
    # settings.json can fail JSON parsing in the Node-based reader. WriteAllText with
    # UTF8Encoding($false) writes plain UTF-8.
    [System.IO.File]::WriteAllText($SettingsPath, $newText, [System.Text.UTF8Encoding]::new($false))

    # re-read and verify
    $verifyText = Get-Content -LiteralPath $SettingsPath -Raw
    $verifyObj = $verifyText | ConvertFrom-Json
    $verifyAllow = @($verifyObj.permissions.allow)
    $verifyDeny = @($verifyObj.permissions.deny)

    Write-Host ''
    Write-Host 'Resulting allow list:' -ForegroundColor Green
    $verifyAllow | ForEach-Object { Write-Host "  $_" }
    Write-Host 'Resulting deny list:' -ForegroundColor Green
    $verifyDeny | ForEach-Object { Write-Host "  $_" }

    $missingAllow = @($ApprovedAllow | Where-Object { $verifyAllow -notcontains $_ })
    $missingDeny = @($ApprovedDeny | Where-Object { $verifyDeny -notcontains $_ })
    $missing = @($missingAllow) + @($missingDeny)
    if ($missing.Count -gt 0) {
        Write-Host ''
        Write-Host "FAILED to verify: missing after write: $($missing -join ', ')" -ForegroundColor Red
        $script:RunOutcome = "FAILED to verify: missing after write: $($missing -join ', ')"
        exit 1
    }

    Write-Host ''
    Write-Host 'WRITE SUCCEEDED and verified.' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Rollback: restore the backup copy over settings.json, or delete these three entries' -ForegroundColor Cyan
    Write-Host 'from permissions.allow / permissions.deny:' -ForegroundColor Cyan
    Write-Host "  allow: $($ApprovedAllow -join ', ')" -ForegroundColor Cyan
    Write-Host "  deny:  $($ApprovedDeny -join ', ')" -ForegroundColor Cyan
    Write-Host "Backup: $(if ($backupPath) { $backupPath } else { '(none - file did not exist before this run)' })" -ForegroundColor Cyan

    $script:RunOutcome = "WRITE SUCCEEDED and verified. Added: $($toAdd -join ', '). Backup: $(if ($backupPath) { $backupPath } else { '(none)' })"
} catch {
    $ex = $_.Exception
    Write-Host ''
    Write-Host 'FAILED: writing or verifying settings.json threw an exception.' -ForegroundColor Red
    Write-Host "Exception type   : $($ex.GetType().FullName)" -ForegroundColor Red
    Write-Host "Exception message: $($ex.Message)" -ForegroundColor Red
    Write-Host ''
    Write-Host "CURRENT STATE: backup (if any) is at $(if ($backupPath) { $backupPath } else { '(none written)' })." -ForegroundColor Yellow
    Write-Host "$SettingsPath may be partially written or unchanged -- re-read it before relying on it." -ForegroundColor Yellow
    Write-Host 'UNDO: restore the backup copy over settings.json.' -ForegroundColor Cyan
    $script:RunExceptionText = "Type: $($ex.GetType().FullName)`nMessage: $($ex.Message)`n$($ex.ToString())"
    $script:RunOutcome = "FAILED: write/verify threw $($ex.GetType().FullName). Backup: $(if ($backupPath) { $backupPath } else { '(none)' })"
    exit 1
}

}
catch {
    $ex = $_.Exception
    Write-Host ''
    Write-Host 'UNEXPECTED EXCEPTION:' -ForegroundColor Red
    Write-Host "Exception type   : $($ex.GetType().FullName)" -ForegroundColor Red
    Write-Host "Exception message: $($ex.Message)" -ForegroundColor Red
    if (-not $script:RunExceptionText) {
        $script:RunExceptionText = "Type: $($ex.GetType().FullName)`nMessage: $($ex.Message)`n$($ex.ToString())"
    }
    if ($script:RunOutcome -eq 'UNKNOWN (script exited without setting an outcome)') {
        $script:RunOutcome = "FAILED: unhandled exception $($ex.GetType().FullName) -- $($ex.Message)"
    }
    exit 1
}
finally {
    Write-RunLog
}
