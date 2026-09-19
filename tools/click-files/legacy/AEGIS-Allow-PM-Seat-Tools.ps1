<#
.SYNOPSIS
  Owner-run. Adds a fixed, owner-approved set of permission entries to the AEGIS-Directive
  project's Claude Code settings.json allow list (PM seat tools).

.DESCRIPTION
  Authorized by Ops Decision Queue card "pm-seat-permission-allowlist-2026-09-18", owner
  resolution "B: Approve the read-only set AND git worktree add / New-ParallelWorktrees.ps1",
  resolvedAt 2026-09-18T00:58:24.413Z (page-written).

  Target file: C:\Users\yoda_\GitHub\.claude\settings.json (project settings). This file
  currently does not exist. If absent, this script creates it as
  {"permissions":{"allow":[...]}}. If present, it merges the 14 approved entries into
  permissions.allow, preserving everything else in the file byte-for-byte as far as JSON
  round-tripping allows (2-space indent), and never touches deny, hooks, or any other key.
  It never touches settings.local.json.

  The 14 approved entries (exactly these, no more):
    ArtifactData
    SendMessage
    Agent
    CronCreate
    CronList
    CronDelete
    Bash(gh pr list *)
    Bash(gh pr view *)
    Bash(gh api repos/*)
    Bash(git fetch *)
    Bash(git show *)
    Bash(git worktree list)
    Bash(git worktree add *)
    PowerShell(powershell -NoProfile -ExecutionPolicy Bypass -File *New-ParallelWorktrees.ps1*)

  The last entry's form matches the one existing PowerShell rule already in
  settings.local.json (PowerShell(powershell -NoProfile -ExecutionPolicy Bypass -File
  *install-vps-ci-runner.ps1*)), rather than inventing a new shape for this repo.

  This is a permission-settings change (a repo/session security setting), not a code change.
  No Claude session applies it; this script refuses to run unless a person started it from a
  real console (stdin not redirected) and types YES.

  Idempotent: if all 14 entries are already present, it prints "ALREADY APPLIED - nothing to
  do", asks nothing, writes nothing, and exits 0.

  Refuses (exit 2) if: not an interactive console, the existing file fails to parse as JSON,
  or permissions.allow exists but is not an array. Never removes or rewrites an existing
  entry, never touches deny/hooks/settings.local.json.

  A timestamped .bak.<yyyyMMdd-HHmmss> copy of the existing file (if any) is written before
  the new file, and a .<yyyyMMdd-HHmmss>.log of the run is written next to this script.

  Rollback: restore the .bak.<timestamp> copy over settings.json, or manually delete the 14
  entries listed above from permissions.allow.

.PARAMETER WhatIf
  Show current allow list (or "file absent"), the entries that would be added/skipped, and a
  before/after diff. Change nothing, ask nothing, write nothing.

.PARAMETER SettingsPath
  Override the target settings.json path. Defaults to
  C:\Users\yoda_\GitHub\.claude\settings.json. Intended for -WhatIf testing against a temp
  fixture; a real (non-WhatIf) run should use the default.
#>
[CmdletBinding()]
param(
    [switch]$WhatIf,
    [string]$SettingsPath = 'C:\Users\yoda_\GitHub\.claude\settings.json'
)

$ErrorActionPreference = 'Stop'

# --- run-log bookkeeping: a timestamped log next to this script is written on EVERY
# terminating path (success, cancel, refuse, -WhatIf, exception), per MasterThread
# tools/README.md's "An owner-run click-file logs every exit path". The filename itself says
# whether the real action was attempted -- fixed after a 2026-09-18 blocked-work sweep had to
# read every log's body to tell a dry run from a real one. -------------------------------------
$script:RunStartTime = Get-Date
$script:TypedAnswer = 'n/a (no prompt reached)'
$script:RunOutcome = 'UNKNOWN (script exited without setting an outcome)'
$script:RunExceptionText = ''
# Stays $false for -WhatIf, a non-default -SettingsPath (test fixture), a refused precondition,
# or a cancel at the YES prompt -- becomes $true only right before the real write is attempted,
# so a real attempt that then throws still logs as real, never dry.
$script:IsRealAttempt = $false
$DefaultSettingsPath = 'C:\Users\yoda_\GitHub\.claude\settings.json'

function Write-RunLog {
    $suffix = if ($script:IsRealAttempt) { 'log' } else { 'dryrun.log' }
    $log = Join-Path $PSScriptRoot ("AEGIS-Allow-PM-Seat-Tools.{0}.{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $suffix)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("RUN TYPE: $(if ($script:IsRealAttempt) { 'real' } else { 'dry run (nothing was changed)' })")
    $lines.Add("Start time (local): $($script:RunStartTime.ToString('o'))")
    $lines.Add("Target settings file: $SettingsPath")
    $lines.Add("WhatIf: $($WhatIf.IsPresent)")
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

$ApprovedEntries = @(
    'ArtifactData',
    'SendMessage',
    'Agent',
    'CronCreate',
    'CronList',
    'CronDelete',
    'Bash(gh pr list *)',
    'Bash(gh pr view *)',
    'Bash(gh api repos/*)',
    'Bash(git fetch *)',
    'Bash(git show *)',
    'Bash(git worktree list)',
    'Bash(git worktree add *)',
    'PowerShell(powershell -NoProfile -ExecutionPolicy Bypass -File *New-ParallelWorktrees.ps1*)'
)

try {

# --- initiation binding: a person at a real console, never a session's tool call ---------------
if (-not $WhatIf) {
    if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
        Write-Host 'REFUSED: this must be started by the owner from a real console window (double-click the .cmd).' -ForegroundColor Red
        Write-Host 'A Claude session may only run it with -WhatIf.' -ForegroundColor Red
        $script:TypedAnswer = 'n/a (refused before any prompt)'
        $script:RunOutcome = 'REFUSED: not an interactive console and -WhatIf was not passed.'
        exit 2
    }
}

Write-Host "Target settings file: $SettingsPath"

$fileExists = Test-Path -LiteralPath $SettingsPath
$originalText = $null
$settingsObj = $null
$currentAllow = @()

if (-not $fileExists) {
    Write-Host 'Current allow list: file absent'
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

    if ($settingsObj.PSObject.Properties.Name -contains 'permissions' -and
        $settingsObj.permissions.PSObject.Properties.Name -contains 'allow') {
        $rawAllow = $settingsObj.permissions.allow
        if ($rawAllow -isnot [System.Collections.IEnumerable] -or $rawAllow -is [string]) {
            Write-Host "REFUSED: permissions.allow in $SettingsPath exists but is not a JSON array. Nothing changed." -ForegroundColor Red
            $script:RunOutcome = 'REFUSED: permissions.allow exists but is not a JSON array.'
            exit 2
        }
        $currentAllow = @($rawAllow)
    }
    Write-Host 'Current allow list:'
    if ($currentAllow.Count -eq 0) { Write-Host '  (empty)' }
    else { $currentAllow | ForEach-Object { Write-Host "  $_" } }
}

$toAdd = @($ApprovedEntries | Where-Object { $currentAllow -notcontains $_ })
$alreadyPresent = @($ApprovedEntries | Where-Object { $currentAllow -contains $_ })

Write-Host ''
Write-Host 'Approved entries already present (skipped):'
if ($alreadyPresent.Count -eq 0) { Write-Host '  (none)' }
else { $alreadyPresent | ForEach-Object { Write-Host "  $_" } }

Write-Host ''
Write-Host 'Approved entries that will be added:'
if ($toAdd.Count -eq 0) { Write-Host '  (none)' }
else { $toAdd | ForEach-Object { Write-Host "  $_" } }

# --- idempotent short-circuit (constraint 4): all 14 present, nothing to do --------------------
if ($toAdd.Count -eq 0) {
    Write-Host ''
    Write-Host 'ALREADY APPLIED - nothing to do' -ForegroundColor Green
    $script:RunOutcome = 'ALREADY APPLIED: all 14 entries already present. No prompt, no write.'
    exit 0
}

# --- build proposed new content -----------------------------------------------------------------
if ($null -eq $settingsObj) {
    $newAllow = @($ApprovedEntries)
    $newObj = [ordered]@{
        permissions = [ordered]@{
            allow = $newAllow
        }
    }
} else {
    $newAllow = @($currentAllow) + @($toAdd)
    if (-not ($settingsObj.PSObject.Properties.Name -contains 'permissions')) {
        $settingsObj | Add-Member -NotePropertyName 'permissions' -NotePropertyValue ([ordered]@{ allow = $newAllow })
    } elseif (-not ($settingsObj.permissions.PSObject.Properties.Name -contains 'allow')) {
        $settingsObj.permissions | Add-Member -NotePropertyName 'allow' -NotePropertyValue $newAllow
    } else {
        $settingsObj.permissions.allow = $newAllow
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
Write-Host 'INFO: settings.local.json in the same folder already allows Bash(gh pr *) and Bash(gh api *)' -ForegroundColor Yellow
Write-Host '      unrestricted, which is wider than what this card approved. This script does not' -ForegroundColor Yellow
Write-Host '      change settings.local.json.' -ForegroundColor Yellow

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

# Real action begins here -- even if the write or verify below throws, this run attempted the
# real action and its log must never be named .dryrun.log.
$script:IsRealAttempt = ($SettingsPath -eq $DefaultSettingsPath)

$backupPath = $null
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

Write-Host ''
Write-Host 'Resulting allow list:' -ForegroundColor Green
$verifyAllow | ForEach-Object { Write-Host "  $_" }

$missing = @($ApprovedEntries | Where-Object { $verifyAllow -notcontains $_ })
if ($missing.Count -gt 0) {
    Write-Host ''
    Write-Host "FAILED to verify: missing after write: $($missing -join ', ')" -ForegroundColor Red
    $script:RunOutcome = "FAILED to verify: missing after write: $($missing -join ', ')"
    exit 1
}

Write-Host ''
Write-Host 'WRITE SUCCEEDED and verified.' -ForegroundColor Green
Write-Host ''
Write-Host 'Rollback: restore the backup copy over settings.json, or delete the 14 entries listed' -ForegroundColor Cyan
Write-Host "above from permissions.allow. Backup: $(if ($backupPath) { $backupPath } else { '(none - file did not exist before this run)' })" -ForegroundColor Cyan

$script:RunOutcome = "WRITE SUCCEEDED and verified. Added: $($toAdd -join ', '). Backup: $(if ($backupPath) { $backupPath } else { '(none)' })"

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
