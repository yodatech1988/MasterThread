<#
.SYNOPSIS
  Owner-run. Registers a Windows Scheduled Task that runs the PM heartbeat watchdog
  (`Watch-PmHeartbeat.ps1`, pulled fresh from origin/main every run) every 15 minutes,
  indefinitely, silently.

.DESCRIPTION
  Authorized by: MasterThread PR #108 (merged 2026-09-18T01:17:39Z), which added
  `standards/sessions/pm_role.md`'s heartbeat control-loop step and
  `tools/pm-heartbeat/{Write-PmHeartbeat.ps1,Watch-PmHeartbeat.ps1,README.md}`; owner
  instruction 2026-09-18 "the pm never stalls"; and PR #108's own README, which says in
  its registration section that registering the scheduled task is the owner's click,
  filed at this exact path once approved.

  DOES NOT DEPEND ON THE SHARED CHECKOUT'S CHECKED-OUT BRANCH. The MasterThread checkout
  at C:\Users\yoda_\GitHub\MasterThread is carded as a landmine (782 files staged on an
  unrelated agent branch) -- nobody is moving it to main just for this. Everything here
  reads content out of `origin/main` directly via `git show origin/main:<path>` (a
  read of the remote-tracking ref's tree, unaffected by whatever branch/worktree state
  happens to be checked out) -- the exact pattern this estate already uses for the
  usage-watch Monitor line in ~/.claude/CLAUDE.md. The working tree itself is never read,
  written, or checked out by this script.

  WHAT REGISTRATION DOES:
    1. `git -C C:\Users\yoda_\GitHub\MasterThread fetch -q origin main`
    2. `git -C C:\Users\yoda_\GitHub\MasterThread show origin/main:tools/pm-heartbeat/Watch-PmHeartbeat.ps1`
       -- if this fails (file not on main), REFUSE (exit 2). This is the only refusal
       condition; there is no more "stale branch" warning because nothing here depends on
       the checkout's branch any more.
    3. Writes that content to `%APPDATA%\AEGIS\pm-heartbeat\Watch-PmHeartbeat.ps1` (a
       per-purpose copy, same idea as usage-watch.ps1's `%APPDATA%\AEGIS\usage-watch.<N>.ps1`).
    4. Writes a tiny wrapper, `%APPDATA%\AEGIS\pm-heartbeat\Run-Watchdog.ps1`, from a
       here-string in this script (see below).
    5. Registers a Scheduled Task named AEGIS-PmHeartbeat-Watchdog under your own Windows
       account (no stored password; runs only when logged on -- "runs whether logged on
       or not" was not requested), triggered every 15 minutes forever, action:
         powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%APPDATA%\AEGIS\pm-heartbeat\Run-Watchdog.ps1"
       (the literal APPDATA path, resolved to this account's real APPDATA at registration
       time, not a %APPDATA% token left for Task Scheduler to expand).

  WHAT THE WRAPPER (Run-Watchdog.ps1) DOES, EVERY TIME THE TASK FIRES -- this is the
  "always run the merged version" self-refresh, the same shape as the usage-watch Monitor
  line re-pulling its script from origin/main every arm:
    1. `git -C <MasterThreadRepo> fetch -q origin main`
    2. `git -C <MasterThreadRepo> show origin/main:tools/pm-heartbeat/Watch-PmHeartbeat.ps1`
       and overwrite its own copy of Watch-PmHeartbeat.ps1 if that succeeds.
    3. If the refresh fails (network down, ref missing, whatever) it does NOT stop: it
       runs whatever copy it already has on disk from the last successful refresh, and
       appends one line to the log noting the refresh failed and the last-good copy was
       used. If there has never been a successful refresh (no copy exists at all yet),
       it appends one line saying so and exits without running anything.
    4. Invokes the (possibly just-refreshed) Watch-PmHeartbeat.ps1 with
       `-Once -LogPath "<resolved APPDATA>\AEGIS\pm-heartbeat-watch.log"`. No `-Notify` is
       ever passed -- Watch-PmHeartbeat.ps1 is silent by default (stdout + exit code +
       append-only log only; see its own header, "silent by default", added after a real
       msg.exe popup incident on 2026-09-18). Nothing here adds a notification path.

  IDEMPOTENT: if a task named AEGIS-PmHeartbeat-Watchdog already exists with the same
  action command line and the same 15-minute repeating trigger, this prints
  "ALREADY REGISTERED" and exits 0 without asking anything (the wrapper and copied script
  are still refreshed from origin/main either way, since that's a content update, not a
  task-definition change). If the task exists but its action/trigger differ, it prints a
  diff of old vs proposed and asks you to type YES to replace it.

  This is a host scheduling change (a persistent background task on your machine), not a
  code change. No Claude session applies it; this script refuses to run for real unless
  started by a person from a real console (stdin not redirected) and YES is typed. A
  Claude session may only ever invoke it with -WhatIf.

  Rollback: run the companion AEGIS-Unregister-PmHeartbeat-Watchdog.cmd, or from any
  console:
    Unregister-ScheduledTask -TaskName AEGIS-PmHeartbeat-Watchdog
  (this removes only the scheduled task; the copied files under
  %APPDATA%\AEGIS\pm-heartbeat\ are left in place and harmless once nothing runs them.)

  A timestamped .<yyyyMMdd-HHmmss>.log of the run is written next to this script.

.PARAMETER WhatIf
  Perform the same `git fetch` + `git show origin/main:...` read as a real run, to prove
  the watchdog script actually exists on main right now, then print the task name,
  trigger, full action command line, and principal that would be registered. Writes
  NOTHING to %APPDATA%\AEGIS\pm-heartbeat\ (no copy, no wrapper), registers nothing, asks
  nothing, writes no run-log. Safe for a Claude session to run.

.PARAMETER MasterThreadRepo
  Local path to a MasterThread git checkout used only to run `git fetch`/`git show`
  against its `origin` remote -- its checked-out branch/working tree is never read.
  Defaults to C:\Users\yoda_\GitHub\MasterThread.

.PARAMETER StateDir
  Directory to hold the per-purpose copy of Watch-PmHeartbeat.ps1 and the Run-Watchdog.ps1
  wrapper. Defaults to "$env:APPDATA\AEGIS\pm-heartbeat" -- the REAL default. Task
  registration is structurally impossible whenever this resolves to anything else: the
  check is against the real path itself (recomputed fresh from $env:APPDATA at the moment
  of the check), not against whether a flag was passed, so no flag combination a test uses
  can accidentally register a real task. Same shape as Watch-PmHeartbeat.ps1's own
  -Notify-vs-real-StateDir guard.

.PARAMETER LogPath
  The log file the watchdog itself appends its one-line results to (Watch-PmHeartbeat.ps1's
  own -LogPath, baked into the wrapper). Defaults to a path derived from -StateDir's parent
  directory ("<parent of StateDir>\pm-heartbeat-watch.log"), so passing a test -StateDir
  automatically routes the watchdog's own log into the test area too, never the real
  %APPDATA%\AEGIS\pm-heartbeat-watch.log.

.PARAMETER GenerateOnly
  Test seam (tools/README.md "test the call site" / "prove it can fail"). Writes the
  watchdog copy + wrapper into -StateDir and then STOPS -- it never registers a scheduled
  task, under any StateDir, real or not. When -StateDir resolves to anything other than
  the real default, this also skips the interactive-console gate and the typed-YES prompt
  (there is nothing for the owner to approve: nothing outside a throwaway directory is
  touched), so it can run unattended from a Claude session against a temp directory. When
  -StateDir IS the real default, the normal interactive-console gate and YES prompt still
  apply even with -GenerateOnly, because that path writes real files under the owner's
  real %APPDATA%\AEGIS\pm-heartbeat\.
#>
[CmdletBinding()]
param(
    [switch] $WhatIf,
    [switch] $GenerateOnly,
    [string] $MasterThreadRepo = 'C:\Users\yoda_\GitHub\MasterThread',
    [string] $StateDir = (Join-Path $env:APPDATA 'AEGIS\pm-heartbeat'),
    [string] $LogPath = (Join-Path (Split-Path -Parent $StateDir) 'pm-heartbeat-watch.log')
)

$ErrorActionPreference = 'Stop'
$TaskName = 'AEGIS-PmHeartbeat-Watchdog'
$RelPath = 'tools/pm-heartbeat/Watch-PmHeartbeat.ps1'
$WatchdogCopyPath = Join-Path $StateDir 'Watch-PmHeartbeat.ps1'
$WrapperPath = Join-Path $StateDir 'Run-Watchdog.ps1'

# --- run-log bookkeeping: a timestamped .log next to this script is written on EVERY
# terminating path (success, cancel, refuse, exception) -- fixed 2026-09-18 after the
# 01:34Z incident where Register-ScheduledTask threw under $ErrorActionPreference='Stop'
# and the script died before ever reaching its old end-of-script-only logging step, so
# nothing on disk recorded that the owner had typed YES or that registration failed. -----
$script:RunStartTime = Get-Date
$script:ResolvedPlanLines = @()
$script:TypedAnswer = 'n/a (no prompt reached)'
$script:RunOutcome = 'UNKNOWN (script exited without setting an outcome)'
$script:RunExceptionText = ''
# Real vs dry run (tools/README.md "An owner-run click-file logs every exit path" sub-point,
# added after a 2026-09-18 blocked-work sweep had to read every log's body to tell them apart):
# stays $false for -WhatIf, -GenerateOnly, a non-default -StateDir (test fixture), a refused
# precondition, or a cancel at a YES prompt -- becomes $true only right before the real
# Register-ScheduledTask attempt, so a real attempt that then throws still logs as real.
$script:IsRealAttempt = $false

function Write-RunLog {
    $suffix = if ($script:IsRealAttempt) { 'log' } else { 'dryrun.log' }
    $log = Join-Path $PSScriptRoot ("AEGIS-Register-PmHeartbeat-Watchdog.{0}.{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $suffix)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("RUN TYPE: $(if ($script:IsRealAttempt) { 'real' } else { 'dry run (nothing was changed)' })")
    $lines.Add("Start time (local): $($script:RunStartTime.ToString('o'))")
    $lines.Add("Task name: $TaskName")
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

# Computed fresh from $env:APPDATA at check time -- never compared against the parameter's
# own default expression object, so a test StateDir can't "look like" the real default by
# construction. Mirrors Watch-PmHeartbeat.ps1's Test-IsRealDefaultStateDir.
function Test-IsRealStateDir {
    $realDefault = Join-Path $env:APPDATA 'AEGIS\pm-heartbeat'
    try {
        $resolved = [IO.Path]::GetFullPath($StateDir).TrimEnd('\', '/')
        $real = [IO.Path]::GetFullPath($realDefault).TrimEnd('\', '/')
        return $resolved -ieq $real
    } catch {
        return $false
    }
}

try {

Write-Host "Reading $RelPath from origin/main (git show -- never the working tree)..."
Write-Host "  git -C `"$MasterThreadRepo`" fetch -q origin main"
& git -C $MasterThreadRepo fetch -q origin main 2>&1 | ForEach-Object { Write-Host "  $_" }
$fetchExit = $LASTEXITCODE
if ($fetchExit -ne 0) {
    Write-Host ''
    Write-Host "REFUSE: 'git fetch -q origin main' failed (exit $fetchExit) in $MasterThreadRepo. Cannot confirm the" -ForegroundColor Red
    Write-Host 'watchdog script exists on main. Nothing changed.' -ForegroundColor Red
    $script:RunOutcome = "REFUSE: git fetch failed (exit $fetchExit) in $MasterThreadRepo"
    exit 2
}

Write-Host "  git -C `"$MasterThreadRepo`" show origin/main:$RelPath"
$watchdogContent = & git -C $MasterThreadRepo show "origin/main:$RelPath" 2>&1
$showExit = $LASTEXITCODE
if ($showExit -ne 0) {
    Write-Host ''
    Write-Host "REFUSE: $RelPath was not found at origin/main (git show exit $showExit)." -ForegroundColor Red
    Write-Host $watchdogContent -ForegroundColor Red
    Write-Host 'Nothing changed. Nothing to do until that file lands on main.' -ForegroundColor Yellow
    $script:RunOutcome = "REFUSE: $RelPath not found on origin/main (git show exit $showExit)"
    exit 2
}
$watchdogText = ($watchdogContent -join "`n")
Write-Host "  FOUND on origin/main ($((($watchdogText -split "`n")).Count) lines)." -ForegroundColor Green

$powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$argumentLine = "-NoProfile -ExecutionPolicy Bypass -File `"$WrapperPath`""
$fullActionLine = "$powershellExe $argumentLine"
$principalUser = "$env:USERDOMAIN\$env:USERNAME"

Write-Host ''
Write-Host "Task name       : $TaskName"
Write-Host "Trigger         : every 15 minutes, indefinitely, starting now"
Write-Host "Action (program): $powershellExe"
Write-Host "Action (args)   : $argumentLine"
Write-Host "Wrapper self-refreshes from origin/main on every 15-minute tick (fetch + git show)."
Write-Host "Watchdog copy   : $WatchdogCopyPath"
Write-Host "Watchdog log    : $LogPath"
Write-Host "Principal       : $principalUser (this account only; runs when logged on; no stored password)"
Write-Host "Notify          : none -- -Notify is never passed; watchdog is silent by design"

$script:ResolvedPlanLines = @(
    "Task name       : $TaskName"
    'Trigger         : every 15 minutes, indefinitely, starting now'
    "Action (program): $powershellExe"
    "Action (args)   : $argumentLine"
    "Watchdog copy   : $WatchdogCopyPath"
    "Watchdog log    : $LogPath"
    "Principal       : $principalUser"
    'Notify          : none'
)

if ($WhatIf) {
    Write-Host ''
    Write-Host '-WhatIf: the file above was only READ from origin/main to prove it exists. Nothing was' -ForegroundColor Yellow
    Write-Host "written under $StateDir, no task registered, nothing asked." -ForegroundColor Yellow
    $script:TypedAnswer = 'n/a (-WhatIf never prompts)'
    $script:RunOutcome = '-WhatIf: plan printed, nothing written, nothing registered.'
    exit 0
}

$isRealStateDir = Test-IsRealStateDir
$skipGate = $GenerateOnly -and (-not $isRealStateDir)

# --- initiation binding: a person at a real console, never a session's tool call ---------------
# Skipped ONLY for -GenerateOnly against a non-default (test) StateDir -- keyed to the real
# path via Test-IsRealStateDir, not to the -GenerateOnly flag alone, so no flag combination
# can talk this gate down while pointed at the owner's real state directory.
if (-not $skipGate) {
    if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
        Write-Host ''
        Write-Host 'REFUSED: this must be started by the owner from a real console window (double-click the .cmd).' -ForegroundColor Red
        Write-Host 'A Claude session may only run it with -WhatIf, or -GenerateOnly against a non-default -StateDir.' -ForegroundColor Red
        $script:TypedAnswer = 'n/a (refused before any prompt)'
        $script:RunOutcome = 'REFUSED: not an interactive console and not a permitted test seam.'
        exit 2
    }
}

function Write-WatchdogFiles {
    if (-not (Test-Path -LiteralPath $StateDir)) {
        New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    }
    $logDir = Split-Path -Parent $LogPath
    if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    # the per-purpose copy actually fetched above
    [System.IO.File]::WriteAllText($WatchdogCopyPath, $watchdogText, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Wrote watchdog copy: $WatchdogCopyPath"

    # the self-refreshing wrapper the scheduled task actually invokes
    $wrapperScript = @"
<#
Auto-generated by AEGIS-Register-PmHeartbeat-Watchdog.ps1 -- do not hand-edit; re-run the
register script to regenerate. Same self-refresh pattern as ~/.claude/CLAUDE.md's
usage-watch Monitor line: every tick, re-pulls Watch-PmHeartbeat.ps1 from origin/main
before running it, so the scheduled task always runs the merged version. If the refresh
fails, it falls back to the last good copy on disk and logs that it did so.
#>
`$ErrorActionPreference = 'Continue'
`$MasterThreadRepo = '$MasterThreadRepo'
`$RelPath = '$RelPath'
`$WatchdogCopyPath = '$WatchdogCopyPath'
`$LogPath = '$LogPath'

function Write-WrapperLog([string] `$Line) {
    `$stamp = [DateTime]::UtcNow.ToString('o')
    try { Add-Content -Path `$LogPath -Value "`$stamp `$Line" -Encoding utf8 } catch { }
}

`$refreshed = `$false
try {
    & git -C `$MasterThreadRepo fetch -q origin main 2>`$null
    if (`$LASTEXITCODE -eq 0) {
        `$content = & git -C `$MasterThreadRepo show "origin/main:`$RelPath" 2>`$null
        if (`$LASTEXITCODE -eq 0 -and `$content) {
            [System.IO.File]::WriteAllText(`$WatchdogCopyPath, (`$content -join "``n"), [System.Text.UTF8Encoding]::new(`$false))
            `$refreshed = `$true
        }
    }
} catch { }

if (-not `$refreshed) {
    if (Test-Path -LiteralPath `$WatchdogCopyPath) {
        Write-WrapperLog 'PM-HEARTBEAT-WRAPPER refresh from origin/main failed; running last good copy.'
    } else {
        Write-WrapperLog 'PM-HEARTBEAT-WRAPPER refresh from origin/main failed and no prior copy exists; nothing to run.'
        exit 2
    }
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File `$WatchdogCopyPath -Once -LogPath `$LogPath
exit `$LASTEXITCODE
"@
    [System.IO.File]::WriteAllText($WrapperPath, $wrapperScript, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Wrote wrapper      : $WrapperPath"
}

if ($GenerateOnly) {
    if (-not $isRealStateDir) {
        Write-Host ''
        Write-Host "REGISTER suppressed (non-default StateDir = test)" -ForegroundColor Yellow
        $script:TypedAnswer = 'n/a (test StateDir skips the prompt)'
    } else {
        Write-Host ''
        $answer = Read-Host 'Type YES to write the watchdog copy + wrapper to the REAL state directory (anything else cancels)'
        $script:TypedAnswer = if ($answer -ceq 'YES') { 'YES' } else { 'cancelled' }
        if ($answer -cne 'YES') {
            Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow
            $script:RunOutcome = '-GenerateOnly against the REAL StateDir: owner did not type YES. Cancelled, nothing changed.'
            exit 0
        }
    }

    Write-WatchdogFiles
    Write-Host ''
    Write-Host '-GenerateOnly: files written, no scheduled task registered (by request).' -ForegroundColor Yellow
    $script:RunOutcome = "-GenerateOnly: files written to $StateDir, no scheduled task registered."
    exit 0
}

if (-not $isRealStateDir) {
    Write-Host ''
    Write-Host "REGISTER suppressed (non-default StateDir = test)" -ForegroundColor Yellow
    Write-Host 'Task registration only ever happens against the real default -StateDir. Nothing changed.' -ForegroundColor Yellow
    $script:TypedAnswer = 'n/a (non-default StateDir without -GenerateOnly never prompts)'
    $script:RunOutcome = "Non-default -StateDir ($StateDir) without -GenerateOnly: registration suppressed, nothing changed."
    exit 0
}

# --- compare against any existing task with this name -------------------------------------------
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

function Get-ExistingSummary($task) {
    $action = $task.Actions | Select-Object -First 1
    $trigger = $task.Triggers | Select-Object -First 1
    $repeatMinutes = $null
    if ($trigger -and $trigger.Repetition -and $trigger.Repetition.Interval) {
        try { $repeatMinutes = ([TimeSpan]::Parse(($trigger.Repetition.Interval -replace '^P', '' -replace 'T', ''))).TotalMinutes } catch { $repeatMinutes = $trigger.Repetition.Interval }
    }
    [pscustomobject]@{
        Execute       = $action.Execute
        Arguments     = $action.Arguments
        RepeatMinutes = $repeatMinutes
    }
}

$proposedMatches = $false
if ($existing) {
    $existingSummary = Get-ExistingSummary $existing
    Write-Host ''
    Write-Host 'A task named AEGIS-PmHeartbeat-Watchdog already exists:' -ForegroundColor Cyan
    Write-Host "  Existing program  : $($existingSummary.Execute)"
    Write-Host "  Existing arguments: $($existingSummary.Arguments)"
    Write-Host "  Existing repeat   : every $($existingSummary.RepeatMinutes) minute(s)"

    $sameExecute = ($existingSummary.Execute -ieq $powershellExe)
    $sameArgs = ($existingSummary.Arguments -eq $argumentLine)
    $sameRepeat = ($existingSummary.RepeatMinutes -eq 15)
    $proposedMatches = $sameExecute -and $sameArgs -and $sameRepeat

    if ($proposedMatches) {
        Write-Host ''
        Write-Host 'ALREADY REGISTERED -- task definition matches. Refreshing the copied script/wrapper from' -ForegroundColor Green
        Write-Host 'origin/main anyway (content update, not a task-definition change), then exiting.' -ForegroundColor Green
        $script:TypedAnswer = 'n/a (definition already matches; no prompt needed)'
    } else {
        Write-Host ''
        Write-Host 'DIFFERS from the proposed definition:' -ForegroundColor Yellow
        if (-not $sameExecute) { Write-Host "  - program:   '$($existingSummary.Execute)' -> '$powershellExe'" }
        if (-not $sameArgs)    { Write-Host "  - arguments: '$($existingSummary.Arguments)' -> '$argumentLine'" }
        if (-not $sameRepeat)  { Write-Host "  - repeat:    every $($existingSummary.RepeatMinutes) min -> every 15 min" }
        Write-Host ''
        $answer = Read-Host 'Type YES to REPLACE the existing task with the definition above (anything else cancels)'
        $script:TypedAnswer = if ($answer -ceq 'YES') { 'YES' } else { 'cancelled' }
        if ($answer -cne 'YES') {
            Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow
            $script:RunOutcome = 'Existing task differs from proposed definition; owner did not type YES. Cancelled, nothing changed.'
            exit 0
        }
    }
} else {
    Write-Host ''
    $answer = Read-Host 'Type YES to register this scheduled task (anything else cancels)'
    $script:TypedAnswer = if ($answer -ceq 'YES') { 'YES' } else { 'cancelled' }
    if ($answer -cne 'YES') {
        Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow
        $script:RunOutcome = 'No existing task; owner did not type YES. Cancelled, nothing changed.'
        exit 0
    }
}

Write-WatchdogFiles

if ($proposedMatches) {
    Write-Host ''
    Write-Host 'ALREADY REGISTERED -- nothing else to do.' -ForegroundColor Green
    $script:RunOutcome = 'ALREADY REGISTERED: task definition matched; watchdog copy/wrapper refreshed from origin/main.'
    exit 0
}

# Fix 2026-09-18 (owner double-click at 01:34Z incident): the trigger used to also pass
# -RepetitionDuration ([TimeSpan]::MaxValue), which New-ScheduledTaskTrigger renders as
# duration P99999999DT23H59M59S. Verified in memory that Register-ScheduledTask then
# throws (0x80041318, "value which is incorrectly formatted or out of range") against the
# real Task Scheduler service -- the files were already written (Write-WatchdogFiles runs
# before this point) but the task itself never got created, and because this ran under
# $ErrorActionPreference='Stop' with no try/catch, the script died right here, before ever
# reaching its old end-of-script logging step, leaving no trace of what happened. Omitting
# -RepetitionDuration gives an empty Duration, which Task Scheduler treats as "repeat
# indefinitely" -- the same intent, expressed in a form the service actually accepts.
$action = New-ScheduledTaskAction -Execute $powershellExe -Argument $argumentLine
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

# Fix 2026-09-18: Register-ScheduledTask (and the Unregister that precedes it when
# replacing) never fails silently again. Any thrown exception is caught, reported in full
# (message, exception type, inner exception), and the script exits 1 -- it does NOT fall
# through to "REGISTERED" text it never earned. The files Write-WatchdogFiles just wrote
# stay on disk either way (harmless, and re-running this script after the underlying cause
# is fixed is safe and idempotent -- it will overwrite the same files and try registration
# again).
$script:IsRealAttempt = $true
try {
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false | Out-Null
    }
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'AEGIS PM heartbeat watchdog (PR #108) -- silent, self-refreshing from origin/main, every 15 minutes.' | Out-Null
} catch {
    $ex = $_.Exception
    $exTypeName = $ex.GetType().FullName
    $inner = $ex.InnerException
    Write-Host ''
    Write-Host 'FAILED: Register-ScheduledTask (or the Unregister preceding it) threw an exception.' -ForegroundColor Red
    Write-Host "Exception type   : $exTypeName" -ForegroundColor Red
    Write-Host "Exception message: $($ex.Message)" -ForegroundColor Red
    if ($inner) {
        Write-Host "Inner exception  : $($inner.GetType().FullName): $($inner.Message)" -ForegroundColor Red
    } else {
        Write-Host 'Inner exception  : (none)' -ForegroundColor Red
    }
    Write-Host ''
    Write-Host "CURRENT STATE: $WatchdogCopyPath and $WrapperPath are already written to disk (harmless on their" -ForegroundColor Yellow
    Write-Host "own). NO scheduled task named $TaskName exists. Re-running this script after the underlying cause" -ForegroundColor Yellow
    Write-Host 'is fixed is safe and idempotent -- it overwrites the same two files and tries registration again.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'UNDO (nothing to undo for the task itself, since none was created; to remove the written files):' -ForegroundColor Cyan
    Write-Host "  Remove-Item -LiteralPath `"$StateDir`" -Recurse -Force" -ForegroundColor Cyan

    $exceptionLines = New-Object System.Collections.Generic.List[string]
    $exceptionLines.Add("Type: $exTypeName")
    $exceptionLines.Add("Message: $($ex.Message)")
    if ($inner) { $exceptionLines.Add("Inner: $($inner.GetType().FullName): $($inner.Message)") }
    $exceptionLines.Add($ex.ToString())
    $script:RunExceptionText = ($exceptionLines -join "`n")
    $script:RunOutcome = "FAILED: Register-ScheduledTask threw $exTypeName. No task registered. Files already written to $StateDir (safe to re-run)."
    exit 1
}

$after = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($after) {
    Write-Host ''
    Write-Host "REGISTERED and verified: $TaskName" -ForegroundColor Green
    $script:RunOutcome = "REGISTERED and verified: $TaskName (replaced existing: $([bool]$existing))"
} else {
    Write-Host ''
    Write-Host 'FAILED to verify registration.' -ForegroundColor Red
    Write-Host "CURRENT STATE: $WatchdogCopyPath and $WrapperPath are already written to disk (harmless). No" -ForegroundColor Yellow
    Write-Host 'scheduled task is confirmed to exist. Re-running this script is safe and idempotent.' -ForegroundColor Yellow
    $script:RunOutcome = "FAILED: Register-ScheduledTask did not throw but Get-ScheduledTask could not find $TaskName afterward."
    exit 1
}

Write-Host ''
Write-Host 'To remove it later:' -ForegroundColor Cyan
Write-Host '  Double-click AEGIS-Unregister-PmHeartbeat-Watchdog.cmd' -ForegroundColor Cyan
Write-Host '  or from any console: Unregister-ScheduledTask -TaskName AEGIS-PmHeartbeat-Watchdog' -ForegroundColor Cyan

}
catch {
    $ex = $_.Exception
    $exTypeName = $ex.GetType().FullName
    Write-Host ''
    Write-Host 'UNEXPECTED EXCEPTION (not the Register-ScheduledTask call, which has its own handler above):' -ForegroundColor Red
    Write-Host "Exception type   : $exTypeName" -ForegroundColor Red
    Write-Host "Exception message: $($ex.Message)" -ForegroundColor Red
    if (-not $script:RunExceptionText) {
        $script:RunExceptionText = "Type: $exTypeName`nMessage: $($ex.Message)`n$($ex.ToString())"
    }
    if ($script:RunOutcome -eq 'UNKNOWN (script exited without setting an outcome)') {
        $script:RunOutcome = "FAILED: unhandled exception $exTypeName -- $($ex.Message)"
    }
    exit 1
}
finally {
    Write-RunLog
}
