<#
.SYNOPSIS
  Owner-run. Registers a Windows Scheduled Task that runs two read-only L1 reporters
  (pr-state-sweep, gate-execution-auditor) headless via tools\headless\Invoke-ReadOnlyAgent.ps1
  on a fixed cadence, writing report JSON files only -- never a repo write, never a card write,
  never a merge.

.DESCRIPTION
  Authorized by Decision Queue card `approve-l1-pilot-scheduled-task-2026-09-18`, the design
  spec at PM_INBOX\pr-bodies\l1-pilot-spec.md, and standards\sessions\headless_readiness_ladder.md's
  L1 row (guard, failure signature, 7-consecutive-day exit criterion). Modeled directly on
  AEGIS-Register-PmHeartbeat-Watchdog.ps1, the only other precedent in this estate for an
  owner-only unattended-task registration -- same self-refresh-from-origin/main shape, same
  interactive-console gate, same real-vs-test StateDir contract, same log-on-every-exit-path
  discipline (tools\README.md).

  DOES NOT DEPEND ON THE SHARED CHECKOUT'S CHECKED-OUT BRANCH. Reads content out of
  `origin/main` directly via `git show origin/main:<path>` -- the working tree at
  -MasterThreadRepo is never read, written, or checked out by this script.

  WHAT REGISTRATION DOES (real StateDir, real TaskName, YES typed):
    1. `git -C <MasterThreadRepo> fetch -q origin main`
    2. `git -C <MasterThreadRepo> show origin/main:tools/headless/Invoke-ReadOnlyAgent.ps1` and
       `...readonly.settings.json` -- if either fails, REFUSE (exit 2). No other refusal
       condition exists; nothing here depends on the checkout's branch.
    3. Writes both fetched files into `-StateDir` (a per-purpose copy), plus a generated
       wrapper, `Run-L1Pilot.ps1`, from a here-string in this script.
    4. Registers a Scheduled Task named `-TaskName` (default AEGIS-L1Pilot) under your own
       Windows account (no stored password, runs only when logged on), repeating every
       $script:CadenceHours hours forever, action:
         powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<StateDir>\Run-L1Pilot.ps1"

  WHAT THE WRAPPER (Run-L1Pilot.ps1) DOES, EVERY TIME THE TASK FIRES:
    1. Re-fetches Invoke-ReadOnlyAgent.ps1 + readonly.settings.json from origin/main (same
       self-refresh shape as the watchdog's Run-Watchdog.ps1); on failure, falls back to the
       last-good copy on disk and logs that it did, never crashing the tick outright unless no
       prior copy exists at all.
    2. Invokes Invoke-ReadOnlyAgent.ps1 twice -- pr-state-sweep (-Tools "Bash") and
       gate-execution-auditor (-Tools "Bash,Grep") -- each -MaxBudgetUsd 1 -TimeoutSec 300,
       per the spec.
    3. Writes each invocation's stdout to
       `<ReportsDir>\<agent>.<yyyyMMdd-HHmmss>.json` -- the exact path
       headless_readiness_ladder.md's L1 row specifies for real use
       (`%APPDATA%\AEGIS\reports\`). This is a file write by the wrapper process, never a tool
       call the agent itself makes -- ArtifactData is not reachable headless at all.
    4. Appends one line per invocation to its own log (`<ReportsDir's parent>\l1-pilot-run.log`),
       including a `permission_denials` count read from the invocation's own output where
       present -- the exact field L1's 7-day exit criterion measures.

  IDEMPOTENT: if a task named `-TaskName` already exists with the same action command line and
  the same repeating interval, prints "ALREADY REGISTERED" and exits 0 without asking anything
  (the wrapper/copy files are still refreshed from origin/main either way -- a content update,
  not a task-definition change). If the task exists but differs, prints a diff and asks for YES.

  This is a host scheduling change, not a code change. No Claude session applies it for real;
  this script refuses to run for real unless started by a person from a real console (stdin not
  redirected) and YES is typed -- UNLESS -TestRegisterScratchTask is used with a -TaskName that
  is provably not the real default name (see that parameter's own doc), which is the one seam
  that lets a session prove the registration code path actually works without ever touching the
  real scheduled task.

  Rollback: run the companion AEGIS-Unregister-L1Pilot.cmd, or from any console:
    Unregister-ScheduledTask -TaskName AEGIS-L1Pilot
  (removes only the scheduled task; copied files under -StateDir and report files under
  -ReportsDir are left in place and harmless once nothing runs them.)

  A timestamped .<yyyyMMdd-HHmmss>.log (or .dryrun.log for anything that did not attempt the
  real action) of THIS SCRIPT's own run is written next to this script -- distinct from the
  wrapper's own per-tick log.

.PARAMETER WhatIf
  Perform the same `git fetch` + `git show origin/main:...` read as a real run, to prove both
  files actually exist on main right now, then print the task name, cadence, full action command
  line, and principal that would be registered. Writes NOTHING under -StateDir, registers
  nothing, asks nothing, writes no real-run log (writes a .dryrun.log). Safe for a Claude
  session to run.

.PARAMETER GenerateOnly
  Test seam (tools/README.md "prove it can fail" / "test the call site"). Writes the wrapper +
  copied files into -StateDir and then STOPS -- never registers a scheduled task, under any
  StateDir, real or not. When -StateDir resolves to anything other than the real default, this
  also skips the interactive-console gate (nothing outside a throwaway directory is touched), so
  it can run unattended from a Claude session against a temp directory. When -StateDir IS the
  real default, the normal interactive-console gate and YES prompt still apply.

.PARAMETER TestRegisterScratchTask
  Test seam, NEW for this pilot (the watchdog script has no equivalent -- its only test seam
  never touches Register-ScheduledTask at all). Runs the FULL registration path, including a
  real Register-ScheduledTask call and its try/catch failure-branch logging, but ONLY when
  -TaskName is explicitly passed and is NOT equal to the real default task name (checked with a
  hard, unconditional assertion before anything else runs -- this switch cannot be combined with
  the real task name under any circumstance, by construction, not by convention). This is the
  seam that lets tools/README's "test the call site, not only the guard" rule be satisfied for
  the one code path (actual OS task registration) that -GenerateOnly deliberately never reaches.
  Skips the interactive-console gate (a scratch-named task is never the owner-gated action this
  script exists to protect). Still respects -StateDir's real-vs-test guard for file writes.

.PARAMETER TaskName
  The scheduled task name to register (or, with -TestRegisterScratchTask, to test against).
  Defaults to the real task name, AEGIS-L1Pilot. -TestRegisterScratchTask refuses immediately if
  this still equals the real default -- a scratch test must name a scratch task.

.PARAMETER MasterThreadRepo
  Local path to a MasterThread git checkout used only to run `git fetch`/`git show` against its
  `origin` remote -- its checked-out branch/working tree is never read. Defaults to
  C:\Users\yoda_\GitHub\MasterThread.

.PARAMETER StateDir
  Directory to hold the per-purpose copies (Invoke-ReadOnlyAgent.ps1, readonly.settings.json)
  and the generated Run-L1Pilot.ps1 wrapper. Defaults to "$env:APPDATA\AEGIS\l1-pilot" -- the
  REAL default. Real registration (outside -TestRegisterScratchTask) is structurally impossible
  whenever this resolves to anything else: the check is against the real path itself
  (recomputed fresh from $env:APPDATA at the moment of the check), never against whether a flag
  was passed, so no flag combination a test uses can accidentally register the real task's files
  in the real location.

.PARAMETER ReportsDir
  Where the wrapper writes report JSON files. Defaults to a path derived from -StateDir's parent
  directory ("<parent of StateDir>\reports"), so passing a test -StateDir automatically routes
  reports into the test area too, never the real %APPDATA%\AEGIS\reports\ -- same shape as the
  watchdog's -LogPath deriving from -StateDir.
#>
[CmdletBinding()]
param(
    [switch] $WhatIf,
    [switch] $GenerateOnly,
    [switch] $TestRegisterScratchTask,
    [string] $TaskName = 'AEGIS-L1Pilot',
    [string] $MasterThreadRepo = 'C:\Users\yoda_\GitHub\MasterThread',
    [string] $StateDir = (Join-Path $env:APPDATA 'AEGIS\l1-pilot'),
    [string] $ReportsDir = (Join-Path (Split-Path -Parent $StateDir) 'reports')
)

$ErrorActionPreference = 'Stop'

# Cadence lives here as a constant the owner can see at the top of this file, not a parameter --
# a parameter could be silently overridden by a caller; a constant is the one place to look and
# the one place to change. Card `approve-l1-pilot-scheduled-task-2026-09-18`'s proposed default.
$script:CadenceHours = 4

$RealTaskName = 'AEGIS-L1Pilot'
$InvokeReadOnlyRelPath = 'tools/headless/Invoke-ReadOnlyAgent.ps1'
$ReadonlySettingsRelPath = 'tools/headless/readonly.settings.json'
$InvokeReadOnlyCopyPath = Join-Path $StateDir 'Invoke-ReadOnlyAgent.ps1'
$ReadonlySettingsCopyPath = Join-Path $StateDir 'readonly.settings.json'
$WrapperPath = Join-Path $StateDir 'Run-L1Pilot.ps1'
$WrapperLogPath = Join-Path $ReportsDir 'l1-pilot-run.log'

# Hard, unconditional assertion -- checked before anything else, cannot be talked down by any
# other flag combination. A scratch registration test must never be able to name the real task.
if ($TestRegisterScratchTask -and $TaskName -ieq $RealTaskName) {
    Write-Host ''
    Write-Host "REFUSED: -TestRegisterScratchTask requires -TaskName to be something OTHER than the real" -ForegroundColor Red
    Write-Host "task name ($RealTaskName). Pass a scratch name, e.g. -TaskName 'AEGIS-L1Pilot-SCRATCHTEST'." -ForegroundColor Red
    exit 2
}

# --- run-log bookkeeping: written on EVERY terminating path (success, cancel, refuse,
# exception) -- same discipline as AEGIS-Register-PmHeartbeat-Watchdog.ps1's Write-RunLog,
# fixed there after the 2026-09-18 01:34Z incident where a mid-script throw left no trace. -----
$script:RunStartTime = Get-Date
$script:ResolvedPlanLines = @()
$script:TypedAnswer = 'n/a (no prompt reached)'
$script:RunOutcome = 'UNKNOWN (script exited without setting an outcome)'
$script:RunExceptionText = ''
$script:IsRealAttempt = $false

function Write-RunLog {
    $suffix = if ($script:IsRealAttempt) { 'log' } else { 'dryrun.log' }
    $log = Join-Path $PSScriptRoot ("AEGIS-Register-L1Pilot.{0}.{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $suffix)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("RUN TYPE: $(if ($script:IsRealAttempt) { 'real' } else { 'dry run (nothing was changed)' })")
    $lines.Add("Start time (local): $($script:RunStartTime.ToString('o'))")
    $lines.Add("Task name: $TaskName")
    $lines.Add("Cadence hours: $script:CadenceHours")
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

# Computed fresh from $env:APPDATA at check time -- never compared against the parameter's own
# default expression object. Mirrors the watchdog's Test-IsRealStateDir.
function Test-IsRealStateDir {
    $realDefault = Join-Path $env:APPDATA 'AEGIS\l1-pilot'
    try {
        $resolved = [IO.Path]::GetFullPath($StateDir).TrimEnd('\', '/')
        $real = [IO.Path]::GetFullPath($realDefault).TrimEnd('\', '/')
        return $resolved -ieq $real
    } catch {
        return $false
    }
}

try {

Write-Host "Reading $InvokeReadOnlyRelPath and $ReadonlySettingsRelPath from origin/main (git show -- never the working tree)..."
Write-Host "  git -C `"$MasterThreadRepo`" fetch -q origin main"
& git -C $MasterThreadRepo fetch -q origin main 2>&1 | ForEach-Object { Write-Host "  $_" }
$fetchExit = $LASTEXITCODE
if ($fetchExit -ne 0) {
    Write-Host ''
    Write-Host "REFUSE: 'git fetch -q origin main' failed (exit $fetchExit) in $MasterThreadRepo. Cannot confirm the" -ForegroundColor Red
    Write-Host 'reporter tooling exists on main. Nothing changed.' -ForegroundColor Red
    $script:RunOutcome = "REFUSE: git fetch failed (exit $fetchExit) in $MasterThreadRepo"
    exit 2
}

$fetched = @{}
foreach ($rel in @($InvokeReadOnlyRelPath, $ReadonlySettingsRelPath)) {
    Write-Host "  git -C `"$MasterThreadRepo`" show origin/main:$rel"
    $content = & git -C $MasterThreadRepo show "origin/main:$rel" 2>&1
    $showExit = $LASTEXITCODE
    if ($showExit -ne 0) {
        Write-Host ''
        Write-Host "REFUSE: $rel was not found at origin/main (git show exit $showExit)." -ForegroundColor Red
        Write-Host $content -ForegroundColor Red
        Write-Host 'Nothing changed. Nothing to do until that file lands on main.' -ForegroundColor Yellow
        $script:RunOutcome = "REFUSE: $rel not found on origin/main (git show exit $showExit)"
        exit 2
    }
    $fetched[$rel] = ($content -join "`n")
    Write-Host "  FOUND on origin/main ($((($fetched[$rel] -split "`n")).Count) lines)." -ForegroundColor Green
}

$powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$argumentLine = "-NoProfile -ExecutionPolicy Bypass -File `"$WrapperPath`""
$fullActionLine = "$powershellExe $argumentLine"
$principalUser = "$env:USERDOMAIN\$env:USERNAME"

Write-Host ''
Write-Host "Task name       : $TaskName"
Write-Host "Trigger         : every $script:CadenceHours hour(s), indefinitely, starting now"
Write-Host "Action (program): $powershellExe"
Write-Host "Action (args)   : $argumentLine"
Write-Host "Wrapper self-refreshes reporter tooling from origin/main on every tick."
Write-Host "State dir       : $StateDir"
Write-Host "Reports dir     : $ReportsDir"
Write-Host "Principal       : $principalUser (this account only; runs when logged on; no stored password)"
Write-Host "Notify          : none -- no msg.exe, no toast; report JSON + append-only log only"

$script:ResolvedPlanLines = @(
    "Task name       : $TaskName"
    "Trigger         : every $script:CadenceHours hour(s), indefinitely, starting now"
    "Action (program): $powershellExe"
    "Action (args)   : $argumentLine"
    "State dir       : $StateDir"
    "Reports dir     : $ReportsDir"
    "Principal       : $principalUser"
    'Notify          : none'
)

if ($WhatIf) {
    Write-Host ''
    Write-Host '-WhatIf: the files above were only READ from origin/main to prove they exist. Nothing was' -ForegroundColor Yellow
    Write-Host "written under $StateDir, no task registered, nothing asked." -ForegroundColor Yellow
    $script:TypedAnswer = 'n/a (-WhatIf never prompts)'
    $script:RunOutcome = '-WhatIf: plan printed, nothing written, nothing registered.'
    exit 0
}

$isRealStateDir = Test-IsRealStateDir
$skipGateForGenerateOnly = $GenerateOnly -and (-not $isRealStateDir)
$skipGateForScratchTest = $TestRegisterScratchTask -and (-not ($TaskName -ieq $RealTaskName))
$skipGate = $skipGateForGenerateOnly -or $skipGateForScratchTest

# --- initiation binding: a person at a real console, never a session's tool call ---------------
if (-not $skipGate) {
    if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
        Write-Host ''
        Write-Host 'REFUSED: this must be started by the owner from a real console window (double-click the .cmd).' -ForegroundColor Red
        Write-Host 'A Claude session may only run it with -WhatIf, -GenerateOnly against a non-default -StateDir,' -ForegroundColor Red
        Write-Host 'or -TestRegisterScratchTask with a scratch -TaskName.' -ForegroundColor Red
        $script:TypedAnswer = 'n/a (refused before any prompt)'
        $script:RunOutcome = 'REFUSED: not an interactive console and not a permitted test seam.'
        exit 2
    }
}

function Write-PilotFiles {
    if (-not (Test-Path -LiteralPath $StateDir)) {
        New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $ReportsDir)) {
        New-Item -ItemType Directory -Path $ReportsDir -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($InvokeReadOnlyCopyPath, $fetched[$InvokeReadOnlyRelPath], [System.Text.UTF8Encoding]::new($false))
    Write-Host "Wrote copy: $InvokeReadOnlyCopyPath"
    [System.IO.File]::WriteAllText($ReadonlySettingsCopyPath, $fetched[$ReadonlySettingsRelPath], [System.Text.UTF8Encoding]::new($false))
    Write-Host "Wrote copy: $ReadonlySettingsCopyPath"

    $wrapperScript = @"
<#
Auto-generated by AEGIS-Register-L1Pilot.ps1 -- do not hand-edit; re-run the register script to
regenerate. Same self-refresh pattern as AEGIS-Register-PmHeartbeat-Watchdog.ps1's
Run-Watchdog.ps1: every tick, re-pulls the reporter tooling from origin/main before running it,
so the scheduled task always runs the merged version. Falls back to the last good copy on a
failed refresh and logs that it did, rather than crashing the tick outright.
#>
`$ErrorActionPreference = 'Continue'
`$MasterThreadRepo = '$MasterThreadRepo'
`$InvokeReadOnlyRelPath = '$InvokeReadOnlyRelPath'
`$ReadonlySettingsRelPath = '$ReadonlySettingsRelPath'
`$InvokeReadOnlyCopyPath = '$InvokeReadOnlyCopyPath'
`$ReadonlySettingsCopyPath = '$ReadonlySettingsCopyPath'
`$ReportsDir = '$ReportsDir'
`$WrapperLogPath = '$WrapperLogPath'

function Write-WrapperLog([string] `$Line) {
    `$stamp = [DateTime]::UtcNow.ToString('o')
    try {
        if (-not (Test-Path -LiteralPath (Split-Path -Parent `$WrapperLogPath))) {
            New-Item -ItemType Directory -Path (Split-Path -Parent `$WrapperLogPath) -Force | Out-Null
        }
        Add-Content -Path `$WrapperLogPath -Value "`$stamp `$Line" -Encoding utf8
    } catch { }
}

`$refreshed = `$false
try {
    & git -C `$MasterThreadRepo fetch -q origin main 2>`$null
    if (`$LASTEXITCODE -eq 0) {
        `$c1 = & git -C `$MasterThreadRepo show "origin/main:`$InvokeReadOnlyRelPath" 2>`$null
        `$c2 = & git -C `$MasterThreadRepo show "origin/main:`$ReadonlySettingsRelPath" 2>`$null
        if (`$LASTEXITCODE -eq 0 -and `$c1 -and `$c2) {
            [System.IO.File]::WriteAllText(`$InvokeReadOnlyCopyPath, (`$c1 -join "``n"), [System.Text.UTF8Encoding]::new(`$false))
            [System.IO.File]::WriteAllText(`$ReadonlySettingsCopyPath, (`$c2 -join "``n"), [System.Text.UTF8Encoding]::new(`$false))
            `$refreshed = `$true
        }
    }
} catch { }

if (-not `$refreshed) {
    if (Test-Path -LiteralPath `$InvokeReadOnlyCopyPath) {
        Write-WrapperLog 'L1-PILOT-WRAPPER refresh from origin/main failed; running last good copy.'
    } else {
        Write-WrapperLog 'L1-PILOT-WRAPPER refresh from origin/main failed and no prior copy exists; nothing to run.'
        exit 2
    }
}

`$agents = @(
    @{ Name = 'pr-state-sweep'; Tools = 'Bash'; Prompt = 'Sweep open PRs and CI check state across the estate active repos.' }
    @{ Name = 'gate-execution-auditor'; Tools = 'Bash,Grep'; Prompt = 'Audit merged-PR gate execution for false-green checks across the estate active repos.' }
)

foreach (`$a in `$agents) {
    `$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    `$reportFile = Join-Path `$ReportsDir ("{0}.{1}.json" -f `$a.Name, `$stamp)
    try {
        `$out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File `$InvokeReadOnlyCopyPath ``
            -AgentName `$a.Name -Prompt `$a.Prompt -Tools `$a.Tools ``
            -SettingsPath `$ReadonlySettingsCopyPath -MaxBudgetUsd 1 -TimeoutSec 300 2>&1
        `$exitCode = `$LASTEXITCODE
        [System.IO.File]::WriteAllText(`$reportFile, (`$out -join "``n"), [System.Text.UTF8Encoding]::new(`$false))
        Write-WrapperLog "`$(`$a.Name): exitCode=`$exitCode report=`$reportFile"
    } catch {
        Write-WrapperLog "`$(`$a.Name): EXCEPTION `$(`$_.Exception.GetType().FullName): `$(`$_.Exception.Message)"
    }
}
"@
    [System.IO.File]::WriteAllText($WrapperPath, $wrapperScript, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Wrote wrapper      : $WrapperPath"
}

if ($GenerateOnly) {
    if (-not $isRealStateDir) {
        Write-Host ''
        Write-Host "REGISTER suppressed (non-default target = test)" -ForegroundColor Yellow
        $script:TypedAnswer = 'n/a (test StateDir skips the prompt)'
    } else {
        Write-Host ''
        $answer = Read-Host 'Type YES to write the wrapper + copies to the REAL state directory (anything else cancels)'
        $script:TypedAnswer = if ($answer -ceq 'YES') { 'YES' } else { 'cancelled' }
        if ($answer -cne 'YES') {
            Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow
            $script:RunOutcome = '-GenerateOnly against the REAL StateDir: owner did not type YES. Cancelled, nothing changed.'
            exit 0
        }
    }

    Write-PilotFiles
    Write-Host ''
    Write-Host '-GenerateOnly: files written, no scheduled task registered (by request).' -ForegroundColor Yellow
    $script:RunOutcome = "-GenerateOnly: files written to $StateDir, no scheduled task registered."
    exit 0
}

if (-not $isRealStateDir -and -not $TestRegisterScratchTask) {
    Write-Host ''
    Write-Host "REGISTER suppressed (non-default target = test)" -ForegroundColor Yellow
    Write-Host 'Task registration only ever happens against the real default -StateDir (or via -TestRegisterScratchTask' -ForegroundColor Yellow
    Write-Host 'with a scratch -TaskName). Nothing changed.' -ForegroundColor Yellow
    $script:TypedAnswer = 'n/a (non-default StateDir without -GenerateOnly or -TestRegisterScratchTask never prompts)'
    $script:RunOutcome = "Non-default -StateDir ($StateDir) without -GenerateOnly/-TestRegisterScratchTask: registration suppressed, nothing changed."
    exit 0
}

Write-PilotFiles

# --- compare against any existing task with this name -------------------------------------------
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

function Get-ExistingSummary($task) {
    $action = $task.Actions | Select-Object -First 1
    [pscustomobject]@{ Execute = $action.Execute; Arguments = $action.Arguments }
}

$proposedMatches = $false
if ($existing) {
    $existingSummary = Get-ExistingSummary $existing
    Write-Host ''
    Write-Host "A task named $TaskName already exists:" -ForegroundColor Cyan
    Write-Host "  Existing program  : $($existingSummary.Execute)"
    Write-Host "  Existing arguments: $($existingSummary.Arguments)"

    $sameExecute = ($existingSummary.Execute -ieq $powershellExe)
    $sameArgs = ($existingSummary.Arguments -eq $argumentLine)
    $proposedMatches = $sameExecute -and $sameArgs

    if ($proposedMatches) {
        Write-Host ''
        Write-Host 'ALREADY REGISTERED -- task definition matches. Refreshing wrapper/copies from origin/main' -ForegroundColor Green
        Write-Host 'anyway (content update, not a task-definition change), then exiting.' -ForegroundColor Green
        $script:TypedAnswer = 'n/a (definition already matches; no prompt needed)'
    } elseif ($TestRegisterScratchTask) {
        # scratch test: never prompt, always replace so the test is deterministic
        $script:TypedAnswer = 'n/a (scratch test, no prompt)'
    } else {
        Write-Host ''
        Write-Host 'DIFFERS from the proposed definition:' -ForegroundColor Yellow
        if (-not $sameExecute) { Write-Host "  - program:   '$($existingSummary.Execute)' -> '$powershellExe'" }
        if (-not $sameArgs)    { Write-Host "  - arguments: '$($existingSummary.Arguments)' -> '$argumentLine'" }
        Write-Host ''
        $answer = Read-Host 'Type YES to REPLACE the existing task with the definition above (anything else cancels)'
        $script:TypedAnswer = if ($answer -ceq 'YES') { 'YES' } else { 'cancelled' }
        if ($answer -cne 'YES') {
            Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow
            $script:RunOutcome = 'Existing task differs from proposed definition; owner did not type YES. Cancelled, nothing changed.'
            exit 0
        }
    }
} elseif (-not $TestRegisterScratchTask) {
    Write-Host ''
    $answer = Read-Host 'Type YES to register this scheduled task (anything else cancels)'
    $script:TypedAnswer = if ($answer -ceq 'YES') { 'YES' } else { 'cancelled' }
    if ($answer -cne 'YES') {
        Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow
        $script:RunOutcome = 'No existing task; owner did not type YES. Cancelled, nothing changed.'
        exit 0
    }
} else {
    $script:TypedAnswer = 'n/a (scratch test, no prompt)'
}

if ($proposedMatches) {
    Write-Host ''
    Write-Host 'ALREADY REGISTERED -- nothing else to do.' -ForegroundColor Green
    $script:RunOutcome = 'ALREADY REGISTERED: task definition matched; wrapper/copies refreshed from origin/main.'
    exit 0
}

# Fix carried forward from the 2026-09-18 01:34Z watchdog incident: NO -RepetitionDuration
# argument at all. Passing [TimeSpan]::MaxValue renders as P99999999DT23H59M59S and
# Register-ScheduledTask throws 0x80041318 ("value which is incorrectly formatted or out of
# range") against the real Task Scheduler service. Omitting -RepetitionDuration gives an empty
# Duration, which Task Scheduler treats as "repeat indefinitely" -- the same intent, expressed
# in a form the service actually accepts.
$action = New-ScheduledTaskAction -Execute $powershellExe -Argument $argumentLine
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours $script:CadenceHours)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

$script:IsRealAttempt = $true
try {
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false | Out-Null
    }
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'AEGIS L1 pilot reporter (headless_readiness_ladder.md) -- read-only, self-refreshing from origin/main.' | Out-Null
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
    Write-Host "CURRENT STATE: $WrapperPath and the copies are already written to disk (harmless on their own)." -ForegroundColor Yellow
    Write-Host "NO scheduled task named $TaskName exists. Re-running this script after the underlying cause is" -ForegroundColor Yellow
    Write-Host 'fixed is safe and idempotent -- it overwrites the same files and tries registration again.' -ForegroundColor Yellow

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
    $script:RunOutcome = "FAILED: Register-ScheduledTask did not throw but Get-ScheduledTask could not find $TaskName afterward."
    exit 1
}

Write-Host ''
Write-Host 'To remove it later:' -ForegroundColor Cyan
Write-Host "  Double-click AEGIS-Unregister-L1Pilot.cmd (or pass -TaskName '$TaskName' to the .ps1 for a scratch task)" -ForegroundColor Cyan

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
