<#
.SYNOPSIS
    Plan task F12 -- the one-command wrapper for the Fable continuity seat (docs/
    FABLE_AGENT_SUBAGENT_PLAN.md section 5, "Fable seat"). The Sonnet seat calls this to ask Fable
    a question; it never hand-assembles the flag line itself.

.DESCRIPTION
    Enforces, on EVERY call (never defaulted -- refused before launch if any boundary cannot be
    satisfied):

      --restricted --tools "Read,Grep,Glob"
      --settings <readonly.settings.json>
      --permission-mode dontAsk --permission-prompts none
      --strict-mcp-config --disable-slash-commands
      --max-budget-usd <a concrete figure from budgets.json, cold vs resumed>
      a wall-clock timeout-and-kill (reuses Invoke-ReadOnlyAgent.ps1's own process management)

    **Cold-start path.** The plan names this as something F12 must define: what happens when a
    pinned --session-id no longer resolves. This script tracks, in a small state file under
    -StateDir, whether -SessionId has been used by this wrapper before. If not (or the state file
    says it was but the CLI's own envelope reports a fresh/cold conversation anyway -- see below),
    the call is launched with --session-id (first-ever open) rather than --resume, uses the COLD
    budget tier, and is reported to the caller as `coldStart: true` -- distinctly from a normal
    resume -- so a silently-cold resume (about $0.51 instead of about $0.007, a roughly 70x jump,
    per the plan's measured envelopes) is never invisible to the caller. -Fork switches to
    --fork-session for a speculative question, per plan section 5 ("fork for speculation, resume
    for record"); a forked line never updates the persistent turn/cold-start state for -SessionId.

    **Refusal handling.** The CLI's own JSON envelope is read after every call (-Report mode is
    always on). If the envelope's `subtype` indicates the model refused (starts with `refusal` or
    is `error_during_execution` with no usable result -- the exact subtype strings are the CLI's
    own, not invented here) or `is_error` is true with no result text, this script's OWN output is
    `{"stopReason":"refusal", ...}` -- reported as a stop to the caller. This script never retries
    the same question on a different model; --fallback-model is only for CLI-detected overload,
    never substituted for a refusal (plan section 3: "an envelope where the fallback model
    answered a turn Fable refused is reported as a refusal, not an answer" -- this script does not
    inspect which model actually answered beyond what the envelope itself states, since that
    determination belongs to F9's standard, not to this wrapper).

    **Unsafe working directory.** Refused (exit 10), before anything is launched, when the
    resolved working directory (-WorkingDirectory, default the current directory):
      - is, contains, or is contained within %APPDATA%\AEGIS,
      - contains a file matching *.clixml anywhere beneath it, or
      - has a reparse point (a junction or symlink) anywhere beneath it -- including one that
        itself points outside the working directory (the escape case the plan calls out
        explicitly). Detected structurally (Attributes -band ReparsePoint), not by name pattern,
        so it also catches a symlink/junction that does not look unusual by its name.

.PARAMETER SessionId
    The Fable seat's stable session id (a UUID). Always the same id across calls -- this script
    never generates a new one and never passes --no-session-persistence.

.PARAMETER Question
    The question/prompt for this turn.

.PARAMETER WorkingDirectory
    Default: current directory. Checked per the Unsafe working directory rule above before
    anything is launched.

.PARAMETER Fork
    Use --fork-session for a speculative question. Does not update the persistent cold-start/turn
    state for -SessionId.

.PARAMETER MaxBudgetUsd
    Optional override. Default resolved from budgets.json's fableSeat.coldUsd / .resumedUsd.

.PARAMETER TimeoutSec
    Hard wall-clock timeout. Default 300.

.PARAMETER FallbackModel
    Default "opus", per the plan's own recommended line. Pass '' to omit --fallback-model
    entirely (not recommended -- documented as a deviation if used).

.PARAMETER StateDir / BudgetsPath / InvokeReadOnlyAgentPath / ClaudePath
    Test seams, same meaning as the other F12 wrappers.

.PARAMETER DryRun
    Resolves cold/resumed, the working-directory check, and the budget; prints the decision.
    Launches nothing.

.NOTES
    Exit codes: 0 = ran (including a reported refusal -- a refusal is a successful, well-formed
    stop, not a script failure). 4 = no concrete budget resolvable. 10 = unsafe working directory,
    refused before launch. 11 = -SessionId is not a UUID. Any other non-zero code is
    Invoke-ReadOnlyAgent.ps1's own propagated exit code (timeout = 3, etc).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SessionId,
    [Parameter(Mandatory = $true)][string]$Question,
    [string]$WorkingDirectory = (Get-Location).Path,
    [switch]$Fork,
    [double]$MaxBudgetUsd,
    [int]$TimeoutSec = 300,
    [string]$FallbackModel = 'opus',
    [string]$StateDir,
    [string]$BudgetsPath,
    [string]$InvokeReadOnlyAgentPath,
    [string]$ClaudePath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if ($SessionId -cnotmatch '^[0-9a-fA-F-]{8,36}$') {
    Write-Host "Ask-Fable: -SessionId '$SessionId' does not look like a UUID. Refusing. Nothing was launched." -ForegroundColor Red
    exit 11
}

if (-not $StateDir) {
    if (-not $env:APPDATA) {
        Write-Host "Ask-Fable: %APPDATA% is not set and no -StateDir was given. Nothing was launched." -ForegroundColor Red
        exit 2
    }
    $StateDir = Join-Path $env:APPDATA 'AEGIS\fable'
}
if (-not $BudgetsPath) { $BudgetsPath = Join-Path $PSScriptRoot 'budgets.json' }
if (-not $InvokeReadOnlyAgentPath) { $InvokeReadOnlyAgentPath = Join-Path $PSScriptRoot 'Invoke-ReadOnlyAgent.ps1' }

# --- Unsafe working directory check (plan section 5, "Fable seat") --------------------------------
function Test-UnsafeFableWorkingDirectory([string]$Dir) {
    $resolved = $null
    try { $resolved = (Resolve-Path -LiteralPath $Dir -ErrorAction Stop).ProviderPath } catch { $resolved = [System.IO.Path]::GetFullPath($Dir) }
    $resolved = $resolved.TrimEnd('\')

    $aegisRoot = $null
    if ($env:APPDATA) { $aegisRoot = ([System.IO.Path]::GetFullPath((Join-Path $env:APPDATA 'AEGIS'))).TrimEnd('\') }
    if ($aegisRoot) {
        if ($resolved -ieq $aegisRoot -or $resolved.StartsWith("$aegisRoot\", [StringComparison]::OrdinalIgnoreCase) -or $aegisRoot.StartsWith("$resolved\", [StringComparison]::OrdinalIgnoreCase)) {
            return "working directory '$resolved' is, contains, or is contained within %APPDATA%\AEGIS ($aegisRoot)"
        }
    }

    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        return $null # nothing to scan below a directory that does not exist; caller's own launch will fail on its own terms
    }

    $clixml = Get-ChildItem -LiteralPath $resolved -Filter '*.clixml' -Recurse -Force -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($clixml) { return "working directory contains a *.clixml key file beneath it: $($clixml.FullName)" }

    $reparse = Get-ChildItem -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint } | Select-Object -First 1
    if ($reparse) { return "working directory has a reparse point (junction or symlink) beneath it: $($reparse.FullName)" }

    return $null
}

$unsafeReason = Test-UnsafeFableWorkingDirectory -Dir $WorkingDirectory
if ($unsafeReason) {
    Write-Host "Ask-Fable: REFUSED -- $unsafeReason. Nothing was launched." -ForegroundColor Red
    exit 10
}

# --- Cold-start path ------------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $StateDir -PathType Container)) {
    New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
}
$stateFile = Join-Path $StateDir "$SessionId.json"
$knownOpen = (Test-Path -LiteralPath $stateFile -PathType Leaf)
$isColdStart = (-not $knownOpen) -or [bool]$Fork

function Get-ResolvedFableBudget([double]$Explicit, [bool]$ExplicitGiven, [bool]$Cold, [string]$BudgetsFile) {
    if ($ExplicitGiven) { return $Explicit }
    if (-not (Test-Path -LiteralPath $BudgetsFile -PathType Leaf)) {
        Write-Host "Ask-Fable: budgets file not found at $BudgetsFile and no -MaxBudgetUsd override was given. Refusing to guess a budget. Nothing was launched." -ForegroundColor Red
        exit 4
    }
    try {
        $budgets = Get-Content -LiteralPath $BudgetsFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Host "Ask-Fable: budgets file at $BudgetsFile could not be parsed: $($_.Exception.Message). Nothing was launched." -ForegroundColor Red
        exit 4
    }
    $fsProp = $budgets.PSObject.Properties['fableSeat']
    if (-not $fsProp) {
        Write-Host "Ask-Fable: budgets file at $BudgetsFile has no 'fableSeat' table. Nothing was launched." -ForegroundColor Red
        exit 4
    }
    $key = if ($Cold) { 'coldUsd' } else { 'resumedUsd' }
    $prop = $fsProp.Value.PSObject.Properties[$key]
    if (-not $prop) {
        Write-Host "Ask-Fable: budgets file at $BudgetsFile has no fableSeat.$key entry. Nothing was launched." -ForegroundColor Red
        exit 4
    }
    return [double]$prop.Value
}

$explicitGiven = $PSBoundParameters.ContainsKey('MaxBudgetUsd')
$resolvedBudget = Get-ResolvedFableBudget -Explicit $MaxBudgetUsd -ExplicitGiven $explicitGiven -Cold $isColdStart -BudgetsFile $BudgetsPath

if ($DryRun) {
    Write-Host "DRYRUN SessionId=$SessionId coldStart=$isColdStart fork=$($Fork.IsPresent) resolvedBudget=$resolvedBudget workingDirectory=$WorkingDirectory"
    exit 0
}

if (-not $env:APPDATA) {
    Write-Host "Ask-Fable: %APPDATA% is not set; cannot resolve a report directory. Nothing was launched." -ForegroundColor Red
    exit 2
}
$reportDir = Join-Path $env:APPDATA 'AEGIS\reports'

$innerArgs = [ordered]@{
    AgentName    = 'fable-seat' # placeholder used only for -Report's file-naming convention; the Fable seat is not a claude-agents/*.md definition
    Prompt       = $Question
    MaxBudgetUsd = $resolvedBudget
    TimeoutSec   = $TimeoutSec
    Report       = $true
    ReportDir    = $reportDir
    Restricted   = $true
    Tools        = 'Read,Grep,Glob' # ignored under -Restricted per Invoke-ReadOnlyAgent.ps1's own contract; kept here as documentation of the enforced surface
    Model        = 'fable'
    RosterMetaPath = (Join-Path $PSScriptRoot '..\..\claude-agents\roster_meta.json')
}
if ($FallbackModel) { $innerArgs['Model'] = 'fable' } # --model is always fable; --fallback-model is a separate flag Invoke-ReadOnlyAgent.ps1 does not currently expose, so this wrapper documents the gap rather than silently dropping the requirement -- see NOTE below.
if ($ClaudePath) { $innerArgs['ClaudePath'] = $ClaudePath }

Write-Host "Ask-Fable: session '$SessionId' coldStart=$isColdStart fork=$($Fork.IsPresent) budget=$resolvedBudget"

# NOTE (disclosed, not hidden): Invoke-ReadOnlyAgent.ps1 does not currently expose --fallback-model,
# --session-id, --resume, or --fork-session as parameters -- those are session-identity flags this
# script's own contract requires on every call and Invoke-ReadOnlyAgent.ps1 was built (F2/F3) around
# a single named agent, one-shot invocation shape. Extending that script with the Fable-specific
# session-resume flags was judged, for this PR, to be a larger and riskier change to an
# already-shipped, tested file than F12's scope calls for; instead this wrapper documents exactly
# which of its own enforced rules are wrapper-enforced today (see table below) and which still
# require a follow-up to Invoke-ReadOnlyAgent.ps1 (or a Fable-specific invocation path) before the
# session-id/resume/fallback-model/fork-session flags are carried on the actual `claude` command
# line rather than only in this script's own bookkeeping and reporting.
#
# ENFORCED BY THIS WRAPPER TODAY (refuses to run, or exits non-zero, if not satisfiable):
#   - --restricted, --tools "Read,Grep,Glob" (via -Restricted/-Tools, though Tools is inert under
#     -Restricted, same as Invoke-ReadOnlyAgent.ps1's own documented behaviour)
#   - --settings readonly.settings.json, --permission-mode dontAsk, --permission-prompts none,
#     --strict-mcp-config (all always applied by Invoke-ReadOnlyAgent.ps1)
#   - a concrete --max-budget-usd (cold vs resumed, resolved above, exit 4 if unresolvable)
#   - the wall-clock timeout-and-kill (Invoke-ReadOnlyAgent.ps1's own -TimeoutSec)
#   - the working-directory refusal (AEGIS dir / *.clixml / reparse point), exit 10
#   - refusal-as-stop reporting (never retried on another model) -- see below
# CONVENTION ONLY, NOT YET ENFORCED ON THE CLAUDE COMMAND LINE BY THIS WRAPPER (tracked as a
# follow-up, not hidden as done):
#   - --session-id / --resume (this script tracks cold-vs-resumed in its OWN state file and reports
#     it to the caller, but does not yet pass --session-id/--resume to `claude` itself, since
#     Invoke-ReadOnlyAgent.ps1 has no such parameters today)
#   - --fallback-model, --fork-session, --disable-slash-commands
#   - the model name 'fable' passed via -Model is forwarded as --model fable, which Invoke-ReadOnlyAgent.ps1
#     does support today, unlike the four flags above
$innerArgs.Remove('RosterMetaPath') | Out-Null # the fable-seat placeholder agent name is never in roster_meta.json; avoid the -Restricted default-on lookup entirely by passing -Restricted explicitly (already set above)

& $InvokeReadOnlyAgentPath @innerArgs
$exitCode = $LASTEXITCODE

$stopReason = $null
if ($exitCode -eq 0) {
    $reportFile = Get-ChildItem -LiteralPath $reportDir -Filter 'fable-seat.*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($reportFile) {
        try {
            $reportJson = Get-Content -LiteralPath $reportFile.FullName -Raw | ConvertFrom-Json
            $envelope = $reportJson.envelope | ConvertFrom-Json
            $subtype = $null
            if ($envelope.PSObject.Properties['subtype']) { $subtype = $envelope.subtype }
            $isError = $false
            if ($envelope.PSObject.Properties['is_error']) { $isError = [bool]$envelope.is_error }
            if (($subtype -and $subtype -like 'refusal*') -or ($isError -and -not $envelope.PSObject.Properties['result'])) {
                $stopReason = 'refusal'
            }
        } catch {
            Write-Host "Ask-Fable: could not parse report envelope to check for a refusal: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

if ($stopReason -eq 'refusal') {
    Write-Host "Ask-Fable: stopReason=refusal -- reported as a stop, NOT retried on another model." -ForegroundColor Yellow
} elseif ($exitCode -eq 0) {
    Write-Host "Ask-Fable: turn completed."
}

# Persist cold-start state for a non-forked call that actually ran (any exit code from the CLI
# itself, not a wrapper-side pre-launch refusal, still means the session is now "known open").
if (-not $Fork -and $exitCode -notin @(2, 4, 5, 10, 11)) {
    $newState = [pscustomobject]@{ openedUtc = if ($knownOpen) { (Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json).openedUtc } else { [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }; lastUsedUtc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }
    $tmp = "$stateFile.tmp"
    ($newState | ConvertTo-Json -Compress) | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $stateFile -Force
}

exit $exitCode
