<#
.SYNOPSIS
  Owner-run. Narrows C:\Users\yoda_\GitHub\.claude\settings.local.json's permissions.allow and
  permissions.deny to exactly the owner-approved set, replacing the current wider grant.

.DESCRIPTION
  AUTHORITY:
    Ops Decision Queue card "settings-local-allow-list-wider-than-approved-2026-09-18", owner
    resolution: "Narrow it now: drop gh secret *, replace gh api * with read-only shapes, split
    gh pr * into the read verbs plus explicit deny on --admin." Spec inputs: github-c7's analysis
    in PM_INBOX\processed\github-c7-20260918T0305Z-settings-local-allowlist.md (the card's own
    background finding -- the wide grant predates the approval and was never load-bearing for any
    merge that ran) and the owner's own follow-on instruction to also add the two-shape deny fix
    for `git worktree remove --force` (git accepts a flag before OR after the path; one deny
    pattern alone only catches one order -- same class of gap c7 found and the existing
    AEGIS-Allow-Seat-Merge.ps1 already fixes for `gh pr merge --admin`).

  Target file: C:\Users\yoda_\GitHub\.claude\settings.local.json.

  BEFORE (verified live 2026-09-18, read-only, no secrets read):
    allow: Bash(gh pr *), Bash(gh api *), Bash(gh secret *), Bash(gh run view *),
           Bash(git worktree remove *), Bash(git branch -d *),
           Bash(ssh -i ~/.ssh/aegis-vps-admin-bot * ubuntu@40.160.90.128 *),
           PowerShell(... install-vps-ci-runner.ps1 ...)
    deny:  Bash(git worktree remove --force *), Bash(git worktree remove -f *)

  AFTER (this script's exact target -- a full REPLACE of permissions.allow/deny, not a merge,
  because narrowing means removing entries too, not only adding):
    allow:
      Bash(gh pr list *)
      Bash(gh pr view *)
      Bash(gh pr diff *)
      Bash(gh pr checks *)
      Bash(gh pr merge *)
      Bash(gh run view *)
      Bash(gh api repos/*)
      Bash(git worktree remove *)
      Bash(git branch -d *)
      Bash(ssh -i ~/.ssh/aegis-vps-admin-bot * ubuntu@40.160.90.128 *)
      PowerShell(powershell -NoProfile -ExecutionPolicy Bypass -File *install-vps-ci-runner.ps1*)
    deny:
      Bash(git worktree remove --force *)
      Bash(git worktree remove -f *)
      Bash(git worktree remove * --force*)
      Bash(git worktree remove * -f*)
      Bash(gh pr merge --admin*)
      Bash(gh pr merge * --admin*)
      Bash(gh api --method*)
      Bash(gh api * --method*)

  WHAT CHANGED AND WHY, entry by entry:
    - `Bash(gh secret *)` DROPPED ENTIRELY. Secret writes (gh secret set/delete) are
      credential-tier under the estate's own secrets-handling rule; no route-B or worker task
      needs them, and the approval card this file was supposed to match explicitly excluded
      credentials.
    - `Bash(gh api *)` REPLACED with `Bash(gh api repos/*)` (allow) PLUS two new deny rules,
      `Bash(gh api --method*)` and `Bash(gh api * --method*)`. `gh api` defaults to GET with no
      `--method` flag, so any write (POST/PATCH/PUT/DELETE -- branch-protection changes, repo
      settings) requires an explicit `--method`. Denying that flag in both call-shape positions
      (mirroring the --admin fix below) makes the remaining `gh api repos/*` allow genuinely
      read-only, not merely narrower.
    - `Bash(gh pr *)` SPLIT into five verb-specific allows (list/view/diff/checks/merge) PLUS two
      new deny rules for `gh pr merge --admin` in both call-shape positions. This mirrors the
      existing, separately-approved AEGIS-Allow-Seat-Merge.ps1 pattern exactly (same empirical
      finding: `Bash(gh pr merge --admin*)` catches `gh pr merge --admin <n>`, and
      `Bash(gh pr merge * --admin*)` catches `gh pr merge <n> --admin`; one alone leaves the other
      shape open).
    - `Bash(git worktree remove --force *)` / `Bash(git worktree remove -f *)` KEPT, and TWO NEW
      deny rules added: `Bash(git worktree remove * --force*)` and `Bash(git worktree remove *
      -f*)`. c7's finding: the original two denies only match when the flag comes immediately
      after `remove`; git also accepts the flag after the path (`git worktree remove /path
      --force`), which matched neither original deny and fell through to the `git worktree
      remove *` allow. These two additions close that gap the same way the --admin fix already
      does for merge.
    - `Bash(gh run view *)`, `Bash(git branch -d *)`, the SSH entry, and the
      install-vps-ci-runner.ps1 PowerShell entry are UNCHANGED -- out of scope for this card. c7's
      analysis treats the SSH/runner-install entries as a separate question from route B/this
      card, to be justified on their own if ever revisited; the owner's instruction to this script
      did not ask for them to change, so they are carried through byte-for-byte.

  RESIDUAL LIMITATION (c7's finding, restated here per owner instruction; not fixed by this
  script because it cannot be fixed by an allow/deny list): a prefix-glob deny cannot express
  general negation. The two-shape denies above cover the two call-shape orderings this estate has
  actually observed and tested (flag-immediately-after-subcommand, and flag-after-the-remaining
  arguments) for `--admin` and `--force`/`-f`. They do NOT catch every conceivable way to smuggle
  the same effect past a literal string match (an abbreviated or aliased flag form, an
  environment-variable equivalent, etc.). The honest status, same as AEGIS-Allow-Seat-Merge.ps1
  already states for --admin: this is the rules-level guard the owner asked for, not an
  unconditional guarantee; the auto-mode classifier remains the other, independent layer.

  This is a permission-settings change (a session security setting), not a code change. No
  Claude session applies it for real; this script refuses to run unless a person started it from a
  real console (stdin not redirected) and types YES. It never runs `gh`, `git worktree`, or `ssh`
  itself -- it only edits the JSON file that governs whether a FUTURE session tool call is
  auto-allowed.

  Idempotent: if permissions.allow and permissions.deny already exactly equal the AFTER lists
  above (as sets, order-independent), it prints "ALREADY APPLIED - nothing to do", asks nothing,
  writes nothing, exits 0.

  Refuses (exit 2) if: not an interactive console (and not -WhatIf), the existing file fails to
  parse as JSON, permissions.allow/permissions.deny is present but not a JSON array, or the file
  is absent entirely (unlike the seat-merge script, this one narrows an EXISTING grant -- an
  absent file means there is nothing to narrow, and this script should not be the one to create
  settings.local.json from scratch).

  A timestamped .bak.<yyyyMMdd-HHmmss> copy of the existing file is written before the new file,
  and a timestamped .<yyyyMMdd-HHmmss>.log of the run is written next to this script on EVERY exit
  path (success, cancel, refuse, -WhatIf, exception), per MasterThread tools/README.md's "An
  owner-run click-file logs every exit path" -- one outer try/catch/finally with Write-RunLog in
  finally, an outcome variable set immediately before every exit, and the real write wrapped in
  its own try/catch that never falls through to success text it did not earn.

  Rollback: restore the .bak.<timestamp> copy over settings.local.json, or manually edit
  permissions.allow/deny back to the BEFORE lists documented above.

.PARAMETER WhatIf
  Show current allow+deny lists, the target AFTER lists, and a before/after diff. Change nothing,
  ask nothing, write nothing. Safe for a Claude session to run against the REAL settings path.

.PARAMETER SettingsPath
  Override the target settings.local.json path. Defaults to
  C:\Users\yoda_\GitHub\.claude\settings.local.json. Intended for -WhatIf and non-WhatIf TEST
  runs against a scratch copy. A Claude session may run a non-WhatIf write ONLY against a
  non-default -SettingsPath under C:\Users\yoda_\AppData\Local\Temp\claude\ -- never against the
  real default without -WhatIf. No Claude session edits the live file, ever.
#>
[CmdletBinding()]
param(
    [switch]$WhatIf,
    [string]$SettingsPath = 'C:\Users\yoda_\GitHub\.claude\settings.local.json'
)

$ErrorActionPreference = 'Stop'

$script:RunStartTime = Get-Date
$script:TypedAnswer = 'n/a (no prompt reached)'
$script:RunOutcome = 'UNKNOWN (script exited without setting an outcome)'
$script:RunExceptionText = ''
$script:ResolvedPlanLines = @()
$script:IsRealAttempt = $false
$DefaultSettingsPath = 'C:\Users\yoda_\GitHub\.claude\settings.local.json'

function Write-RunLog {
    $suffix = if ($script:IsRealAttempt) { 'log' } else { 'dryrun.log' }
    $log = Join-Path $PSScriptRoot ("AEGIS-Narrow-Local-Allowlist.{0}.{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $suffix)
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

# --- the exact target lists (AFTER, per the header doc above) ------------------------------------
$TargetAllow = @(
    'Bash(gh pr list *)',
    'Bash(gh pr view *)',
    'Bash(gh pr diff *)',
    'Bash(gh pr checks *)',
    'Bash(gh pr merge *)',
    'Bash(gh run view *)',
    'Bash(gh api repos/*)',
    'Bash(git worktree remove *)',
    'Bash(git branch -d *)',
    'Bash(ssh -i ~/.ssh/aegis-vps-admin-bot * ubuntu@40.160.90.128 *)',
    'PowerShell(powershell -NoProfile -ExecutionPolicy Bypass -File *install-vps-ci-runner.ps1*)'
)
$TargetDeny = @(
    'Bash(git worktree remove --force *)',
    'Bash(git worktree remove -f *)',
    'Bash(git worktree remove * --force*)',
    'Bash(git worktree remove * -f*)',
    'Bash(gh pr merge --admin*)',
    'Bash(gh pr merge * --admin*)',
    'Bash(gh api --method*)',
    'Bash(gh api * --method*)'
)

try {

# A session may exercise the real write path (backup/write/verify) non-interactively ONLY
# against a test fixture under Temp\claude -- never against the default/real settings path.
# This is the exemption the header doc promises; enforced here, not just documented.
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
if (-not $fileExists) {
    Write-Host "REFUSED: $SettingsPath does not exist. This script narrows an existing grant; there is nothing to narrow." -ForegroundColor Red
    $script:RunOutcome = "REFUSED: $SettingsPath does not exist."
    exit 2
}

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
if (-not $hasPermissions) {
    Write-Host "REFUSED: $SettingsPath has no top-level 'permissions' key. Nothing to narrow." -ForegroundColor Red
    $script:RunOutcome = "REFUSED: no top-level 'permissions' key."
    exit 2
}

$currentAllow = @()
if ($settingsObj.permissions.PSObject.Properties.Name -contains 'allow') {
    $rawAllow = $settingsObj.permissions.allow
    if ($rawAllow -isnot [System.Collections.IEnumerable] -or $rawAllow -is [string]) {
        Write-Host "REFUSED: permissions.allow in $SettingsPath exists but is not a JSON array. Nothing changed." -ForegroundColor Red
        $script:RunOutcome = 'REFUSED: permissions.allow exists but is not a JSON array.'
        exit 2
    }
    $currentAllow = @($rawAllow)
}

$currentDeny = @()
if ($settingsObj.permissions.PSObject.Properties.Name -contains 'deny') {
    $rawDeny = $settingsObj.permissions.deny
    if ($rawDeny -isnot [System.Collections.IEnumerable] -or $rawDeny -is [string]) {
        Write-Host "REFUSED: permissions.deny in $SettingsPath exists but is not a JSON array. Nothing changed." -ForegroundColor Red
        $script:RunOutcome = 'REFUSED: permissions.deny exists but is not a JSON array.'
        exit 2
    }
    $currentDeny = @($rawDeny)
}

Write-Host 'Current allow list:'
if ($currentAllow.Count -eq 0) { Write-Host '  (empty)' } else { $currentAllow | ForEach-Object { Write-Host "  $_" } }
Write-Host 'Current deny list:'
if ($currentDeny.Count -eq 0) { Write-Host '  (empty / absent)' } else { $currentDeny | ForEach-Object { Write-Host "  $_" } }

$allowRemoved = @($currentAllow | Where-Object { $TargetAllow -notcontains $_ })
$allowAdded = @($TargetAllow | Where-Object { $currentAllow -notcontains $_ })
$denyRemoved = @($currentDeny | Where-Object { $TargetDeny -notcontains $_ })
$denyAdded = @($TargetDeny | Where-Object { $currentDeny -notcontains $_ })

Write-Host ''
Write-Host 'Target allow list (this replaces the current one):'
$TargetAllow | ForEach-Object { Write-Host "  $_" }
Write-Host 'Target deny list (this replaces the current one):'
$TargetDeny | ForEach-Object { Write-Host "  $_" }

Write-Host ''
Write-Host 'Changes:'
if ($allowRemoved.Count -eq 0 -and $allowAdded.Count -eq 0 -and $denyRemoved.Count -eq 0 -and $denyAdded.Count -eq 0) {
    Write-Host '  (none)'
} else {
    $allowRemoved | ForEach-Object { Write-Host "  [allow] - $_" -ForegroundColor Red }
    $allowAdded   | ForEach-Object { Write-Host "  [allow] + $_" -ForegroundColor Green }
    $denyRemoved  | ForEach-Object { Write-Host "  [deny]  - $_" -ForegroundColor Red }
    $denyAdded    | ForEach-Object { Write-Host "  [deny]  + $_" -ForegroundColor Green }
}

$script:ResolvedPlanLines = @(
    "Allow removed: $($allowRemoved -join ', ')"
    "Allow added: $($allowAdded -join ', ')"
    "Deny removed: $($denyRemoved -join ', ')"
    "Deny added: $($denyAdded -join ', ')"
)

# --- idempotent short-circuit: current already equals target (as sets) -------------------------
$allowIsTarget = ($allowRemoved.Count -eq 0 -and $allowAdded.Count -eq 0)
$denyIsTarget = ($denyRemoved.Count -eq 0 -and $denyAdded.Count -eq 0)
if ($allowIsTarget -and $denyIsTarget) {
    Write-Host ''
    Write-Host 'ALREADY APPLIED - nothing to do' -ForegroundColor Green
    $script:RunOutcome = 'ALREADY APPLIED: allow and deny already match the target lists. No prompt, no write.'
    exit 0
}

# --- build proposed new content (full replace of permissions.allow / permissions.deny) ---------
$settingsObj.permissions.allow = $TargetAllow
if (-not ($settingsObj.permissions.PSObject.Properties.Name -contains 'deny')) {
    $settingsObj.permissions | Add-Member -NotePropertyName 'deny' -NotePropertyValue $TargetDeny
} else {
    $settingsObj.permissions.deny = $TargetDeny
}

$compactJson = $settingsObj | ConvertTo-Json -Depth 20 -Compress
# PowerShell 5.1's ConvertTo-Json HTML-escapes '<', '>', '&', '\'' (single quote) as < /
# > / & / ' even with -Compress. The hooks.SessionStart command in this file is a
# bash script containing '>' redirects and single-quoted jq literals -- left un-fixed, this would
# silently corrupt that command string on every write. Reverse just those four escapes (verified
# empirically 2026-09-18 against a scratch copy of the real file before ever touching the real
# path): no other \uXXXX sequence is produced by ConvertTo-Json for this file's content, so this
# is a targeted fix, not a general unicode-unescape.
$compactJson = $compactJson -replace '\\u003c', '<' -replace '\\u003e', '>' -replace '\\u0026', '&' -replace '\\u0027', "'"
$newText = ConvertTo-PrettyJson2Space -Compact $compactJson
if (-not $newText.EndsWith("`n")) { $newText += "`n" }

Write-Host ''
Write-Host '================ Diff (before / after) ================' -ForegroundColor Cyan
$beforeLines = @($originalText -replace "`r`n", "`n" -split "`n")
$afterLines = @($newText -split "`n")
foreach ($line in $beforeLines) {
    if ($afterLines -notcontains $line) { Write-Host "- $line" -ForegroundColor Red }
}
foreach ($line in $afterLines) {
    if ($beforeLines -notcontains $line) { Write-Host "+ $line" -ForegroundColor Green }
}
Write-Host '========================================================='

Write-Host ''
Write-Host '=========================== WARNING ===========================' -ForegroundColor Yellow
Write-Host 'This REPLACES permissions.allow and permissions.deny in settings.local.json with the' -ForegroundColor Yellow
Write-Host 'narrower target lists above. Anything currently allowed that is not on the target list' -ForegroundColor Yellow
Write-Host '(gh secret *, the broad gh api *, the broad gh pr *) stops being auto-allowed -- a' -ForegroundColor Yellow
Write-Host 'session will be prompted for those going forward, same as any other unlisted command.' -ForegroundColor Yellow
Write-Host '' -ForegroundColor Yellow
Write-Host 'The gh pr merge --admin and git worktree remove --force/-f denies use TWO patterns each' -ForegroundColor Yellow
Write-Host '(flag-before and flag-after the remaining arguments). This is the same fix already' -ForegroundColor Yellow
Write-Host 'applied for --admin in AEGIS-Allow-Seat-Merge.ps1, extended here to gh api --method and' -ForegroundColor Yellow
Write-Host 'worktree --force/-f. It is NOT an unconditional guarantee -- a prefix-glob deny cannot' -ForegroundColor Yellow
Write-Host 'express general negation, only the specific call shapes tested. The auto-mode classifier' -ForegroundColor Yellow
Write-Host 'remains the other, independent layer for anything this cannot catch.' -ForegroundColor Yellow
Write-Host '=================================================================' -ForegroundColor Yellow

if ($WhatIf) {
    Write-Host ''
    Write-Host '-WhatIf: no changes written.' -ForegroundColor Yellow
    $script:TypedAnswer = 'n/a (-WhatIf never prompts)'
    $script:RunOutcome = '-WhatIf: plan and diff printed, nothing written.'
    exit 0
}

Write-Host ''
$answer = Read-Host 'Type YES to write these changes to settings.local.json (anything else cancels)'
$script:TypedAnswer = if ($answer -ceq 'YES') { 'YES' } else { 'cancelled' }
if ($answer -cne 'YES') {
    Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow
    $script:RunOutcome = 'Owner did not type YES. Cancelled, nothing changed.'
    exit 0
}

$script:IsRealAttempt = ($SettingsPath -eq $DefaultSettingsPath)

$backupPath = $null
try {
    $backupPath = "$SettingsPath.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $SettingsPath -Destination $backupPath -Force
    Write-Host "Backup written: $backupPath"

    [System.IO.File]::WriteAllText($SettingsPath, $newText, [System.Text.UTF8Encoding]::new($false))

    $verifyText = Get-Content -LiteralPath $SettingsPath -Raw
    $verifyObj = $verifyText | ConvertFrom-Json
    $verifyAllow = @($verifyObj.permissions.allow)
    $verifyDeny = @($verifyObj.permissions.deny)

    Write-Host ''
    Write-Host 'Resulting allow list:' -ForegroundColor Green
    $verifyAllow | ForEach-Object { Write-Host "  $_" }
    Write-Host 'Resulting deny list:' -ForegroundColor Green
    $verifyDeny | ForEach-Object { Write-Host "  $_" }

    $missingAllow = @($TargetAllow | Where-Object { $verifyAllow -notcontains $_ })
    $extraAllow = @($verifyAllow | Where-Object { $TargetAllow -notcontains $_ })
    $missingDeny = @($TargetDeny | Where-Object { $verifyDeny -notcontains $_ })
    $extraDeny = @($verifyDeny | Where-Object { $TargetDeny -notcontains $_ })
    $mismatch = @($missingAllow) + @($extraAllow) + @($missingDeny) + @($extraDeny)
    if ($mismatch.Count -gt 0) {
        Write-Host ''
        Write-Host "FAILED to verify: written lists do not exactly match target. missing-allow=$($missingAllow -join ',') extra-allow=$($extraAllow -join ',') missing-deny=$($missingDeny -join ',') extra-deny=$($extraDeny -join ',')" -ForegroundColor Red
        $script:RunOutcome = "FAILED to verify: mismatch after write."
        exit 1
    }

    Write-Host ''
    Write-Host 'WRITE SUCCEEDED and verified.' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Rollback: restore the backup copy over settings.local.json.' -ForegroundColor Cyan
    Write-Host "Backup: $backupPath" -ForegroundColor Cyan

    $script:RunOutcome = "WRITE SUCCEEDED and verified. Allow now $($verifyAllow.Count) entries, deny now $($verifyDeny.Count) entries. Backup: $backupPath"
} catch {
    $ex = $_.Exception
    Write-Host ''
    Write-Host 'FAILED: writing or verifying settings.local.json threw an exception.' -ForegroundColor Red
    Write-Host "Exception type   : $($ex.GetType().FullName)" -ForegroundColor Red
    Write-Host "Exception message: $($ex.Message)" -ForegroundColor Red
    Write-Host ''
    Write-Host "CURRENT STATE: backup (if any) is at $(if ($backupPath) { $backupPath } else { '(none written)' })." -ForegroundColor Yellow
    Write-Host "$SettingsPath may be partially written or unchanged -- re-read it before relying on it." -ForegroundColor Yellow
    Write-Host 'UNDO: restore the backup copy over settings.local.json.' -ForegroundColor Cyan
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
