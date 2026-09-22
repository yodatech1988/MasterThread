<#
.SYNOPSIS
    Plan task F12 -- one-command seat-side wrapper for a dispatched lane (a multi-turn worker
    session, plan section 5), enforcing maxTurns and a concrete per-call budget (owner decision E7,
    issue #187 comment 5770413629: "maxTurns and budget enforcement fold into F12").

.DESCRIPTION
    `claude -p` has no native per-process turn-count flag (confirmed against `claude --help` on
    the installed 2.1.278 build: no `--max-turns` or equivalent exists for --print). A lane's
    maxTurns is therefore enforced HERE, externally, as this wrapper's own bookkeeping, not by the
    CLI:

    - Each call is one `claude -p [--session-id <id> | --resume <id>]` invocation -- one turn, in
      this wrapper's accounting.
    - A small state file under -StateDir (default %APPDATA%\AEGIS\lanes) tracks how many turns a
      given -SessionId has used. The first call for a session id creates it (turn 1, launched with
      --session-id); every later call for the same id is a --resume (turn N+1).
    - Once the counter reaches -MaxTurns, a further call for that session id is REFUSED before
      anything is launched (exit 9) -- this is the enforcement E7 asks for. There is no way to run
      an (N+1)th turn against a lane already at its cap without raising -MaxTurns explicitly.

    Known limitation, stated rather than hidden (see the F12 issue's Risks section): this counter
    is this wrapper's own bookkeeping, not a CLI-enforced limit. If the state file is deleted, or
    the same --session-id is resumed by some other caller outside this wrapper, the count is lost
    or bypassed. It closes the "nothing enforces maxTurns" gap for every caller that goes through
    this script; it is not a boundary against a caller that does not.

    Every call also carries the same wall-clock timeout-and-kill Invoke-ReadOnlyAgent.ps1
    implements (reused directly -- this script shells out to it, it does not reimplement the
    process-management logic), and a concrete --max-budget-usd resolved from
    tools/headless/budgets.json's "lane" table (per call, not per lane lifetime -- see that file's
    own comment).

.PARAMETER SessionId
    The lane's stable session id (a UUID). Required.

.PARAMETER Prompt
    This turn's prompt. Required.

.PARAMETER MaxTurns
    The lane's turn cap. Required -- there is no safe default (a lane with no stated cap is
    exactly what E7 exists to stop).

.PARAMETER AgentName
    Optional: run a named agent definition rather than a bare model session (passed to
    Invoke-ReadOnlyAgent.ps1 as -AgentName). Most lanes are not a single named agent; when omitted,
    this script calls the underlying CLI directly with -Restricted:$false semantics is NOT assumed
    -- a lane without -AgentName must pass -Tools explicitly (same fail-closed rule as
    Invoke-ReadOnlyAgent.ps1), because there is no safe default tool set for an arbitrary lane.

.PARAMETER Tools
    Required when -AgentName is not given. Forwarded to Invoke-ReadOnlyAgent.ps1's -Tools.

.PARAMETER Model
    Optional model override, forwarded through.

.PARAMETER MaxBudgetUsd
    Optional override of the per-call budget. Default resolved from budgets.json's "lane" table
    by -Model's tier (sonnet/opus), falling back to "default".

.PARAMETER TimeoutSec
    Hard wall-clock timeout per call. Default 300, same as Invoke-ReadOnlyAgent.ps1.

.PARAMETER StateDir
    Where the per-session-id turn-count file lives. Default %APPDATA%\AEGIS\lanes. Test seam.

.PARAMETER BudgetsPath / InvokeReadOnlyAgentPath / ClaudePath
    Test seams, same meaning as in Invoke-Subagent.ps1.

.PARAMETER DryRun
    Resolves the turn count and budget, prints what would be launched (or the refusal), launches
    nothing.

.NOTES
    Exit codes: 0 = the call ran and Invoke-ReadOnlyAgent.ps1 exited 0. 4 = no concrete budget
    could be resolved and no override was given. 5 = neither -AgentName nor -Tools was given (no
    safe default tool set for a lane). 9 = -MaxTurns already reached for this -SessionId; refused
    before launch, turn counter NOT incremented. Any other non-zero code is
    Invoke-ReadOnlyAgent.ps1's own propagated exit code.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SessionId,
    [Parameter(Mandatory = $true)][string]$Prompt,
    [Parameter(Mandatory = $true)][int]$MaxTurns,
    [string]$AgentName,
    [string]$Tools,
    [string]$Model,
    [double]$MaxBudgetUsd,
    [int]$TimeoutSec = 300,
    [string]$StateDir,
    [string]$BudgetsPath,
    [string]$InvokeReadOnlyAgentPath,
    [string]$ClaudePath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if ($SessionId -cnotmatch '^[0-9a-fA-F-]{8,36}$') {
    Write-Host "Invoke-Lane: -SessionId '$SessionId' does not look like a UUID. Refusing. Nothing was launched." -ForegroundColor Red
    exit 2
}
if (-not $AgentName -and -not $Tools) {
    Write-Host "Invoke-Lane: -Tools is required when -AgentName is not given -- there is no safe default tool set for a lane. Nothing was launched." -ForegroundColor Red
    exit 5
}

if (-not $StateDir) {
    if (-not $env:APPDATA) {
        Write-Host "Invoke-Lane: %APPDATA% is not set and no -StateDir was given. Nothing was launched." -ForegroundColor Red
        exit 2
    }
    $StateDir = Join-Path $env:APPDATA 'AEGIS\lanes'
}
if (-not $BudgetsPath) { $BudgetsPath = Join-Path $PSScriptRoot 'budgets.json' }
if (-not $InvokeReadOnlyAgentPath) { $InvokeReadOnlyAgentPath = Join-Path $PSScriptRoot 'Invoke-ReadOnlyAgent.ps1' }

function Get-LaneTier([string]$ModelName) {
    if (-not $ModelName) { return 'default' }
    $m = $ModelName.ToLowerInvariant()
    if ($m -like 'opus*') { return 'opus' }
    if ($m -like 'sonnet*') { return 'sonnet' }
    return 'default'
}

function Get-ResolvedLaneBudget([double]$Explicit, [bool]$ExplicitGiven, [string]$Tier, [string]$BudgetsFile) {
    if ($ExplicitGiven) { return $Explicit }
    if (-not (Test-Path -LiteralPath $BudgetsFile -PathType Leaf)) {
        Write-Host "Invoke-Lane: budgets file not found at $BudgetsFile and no -MaxBudgetUsd override was given. Refusing to guess a budget. Nothing was launched." -ForegroundColor Red
        exit 4
    }
    try {
        $budgets = Get-Content -LiteralPath $BudgetsFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Host "Invoke-Lane: budgets file at $BudgetsFile could not be parsed: $($_.Exception.Message). Nothing was launched." -ForegroundColor Red
        exit 4
    }
    $laneProp = $budgets.PSObject.Properties['lane']
    if (-not $laneProp) {
        Write-Host "Invoke-Lane: budgets file at $BudgetsFile has no 'lane' table. Nothing was launched." -ForegroundColor Red
        exit 4
    }
    $table = $laneProp.Value
    $tierProp = $table.PSObject.Properties[$Tier]
    if (-not $tierProp) { $tierProp = $table.PSObject.Properties['default'] }
    if (-not $tierProp) {
        Write-Host "Invoke-Lane: no lane budget entry for tier '$Tier' (or 'default') in $BudgetsFile. Nothing was launched." -ForegroundColor Red
        exit 4
    }
    return [double]$tierProp.Value
}

# --- Turn-counter state (this wrapper's own bookkeeping -- see .DESCRIPTION's Known limitation) ---
if (-not (Test-Path -LiteralPath $StateDir -PathType Container)) {
    New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
}
$stateFile = Join-Path $StateDir "$SessionId.turns.json"
$turnsUsed = 0
if (Test-Path -LiteralPath $stateFile -PathType Leaf) {
    try {
        $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json -ErrorAction Stop
        if ($state.PSObject.Properties['turnsUsed']) { $turnsUsed = [int]$state.turnsUsed }
    } catch {
        Write-Host "Invoke-Lane: state file $stateFile could not be parsed; treating as 0 turns used so far, but this is a finding worth reporting." -ForegroundColor Yellow
    }
}

$isFirstTurn = ($turnsUsed -eq 0)
$nextTurn = $turnsUsed + 1

if ($nextTurn -gt $MaxTurns) {
    Write-Host "Invoke-Lane: session '$SessionId' has already used $turnsUsed of $MaxTurns turns. REFUSED -- not launching turn $nextTurn. Raise -MaxTurns explicitly to continue this lane. Nothing was launched." -ForegroundColor Red
    exit 9
}

$tier = Get-LaneTier -ModelName $Model
$explicitGiven = $PSBoundParameters.ContainsKey('MaxBudgetUsd')
$resolvedBudget = Get-ResolvedLaneBudget -Explicit $MaxBudgetUsd -ExplicitGiven $explicitGiven -Tier $tier -BudgetsFile $BudgetsPath

if ($DryRun) {
    Write-Host "DRYRUN SessionId=$SessionId turn=$nextTurn/$MaxTurns isFirstTurn=$isFirstTurn tier=$tier resolvedBudget=$resolvedBudget"
    exit 0
}

# Hashtable splat (not an array splat) is required to pass -Restricted as an explicit named
# boolean -- an array splat has no way to bind `-Switch:$false` distinctly from a bare `-Switch`.
$innerArgs = [ordered]@{
    AgentName   = $(if ($AgentName) { $AgentName } else { 'lane-worker' }) # placeholder name, used only for Invoke-ReadOnlyAgent.ps1's report file naming when no named agent is given
    Prompt      = $Prompt
    MaxBudgetUsd = $resolvedBudget
    TimeoutSec  = $TimeoutSec
    Report      = $true
    # -Restricted:$false is explicit here (never the roster_meta.json default-on lookup) because a
    # lane is, by definition, a session that needs real work tools -- Invoke-ReadOnlyAgent.ps1's
    # own -Restricted default-on lookup is for the L1 read-only reporter roster, not for lanes.
    Restricted  = $false
}
if ($Tools) { $innerArgs['Tools'] = $Tools }
if ($Model) { $innerArgs['Model'] = $Model }
if ($ClaudePath) { $innerArgs['ClaudePath'] = $ClaudePath }

Write-Host "Invoke-Lane: session '$SessionId' turn $nextTurn/$MaxTurns (tier=$tier, budget=$resolvedBudget)"
& $InvokeReadOnlyAgentPath @innerArgs
$exitCode = $LASTEXITCODE

# Only record the turn as used if the call actually ran (exit 0) or ran and failed on the CLI's
# own terms (non-wrapper-refusal codes) -- a wrapper-side refusal before launch (2, 4, 5) should
# not consume a turn since nothing happened. Invoke-ReadOnlyAgent.ps1's own codes: 2/4/5 = refused
# before launch; 3 = timed out (still consumes a turn -- the process did run); other = the CLI's
# own exit code (consumes a turn).
if ($exitCode -notin @(2, 4, 5)) {
    $newState = [pscustomobject]@{ turnsUsed = $nextTurn; lastUpdatedUtc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }
    $tmp = "$stateFile.tmp"
    ($newState | ConvertTo-Json -Compress) | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $stateFile -Force
}

exit $exitCode
