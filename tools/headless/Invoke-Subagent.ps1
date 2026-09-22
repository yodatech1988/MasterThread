<#
.SYNOPSIS
    Plan task F12 -- one-command seat-side wrapper for the L1/subagent layer (docs/
    FABLE_AGENT_SUBAGENT_PLAN.md section 5, rows 5-7): the caller passes an agent name and a
    prompt, this script resolves everything else (the concrete budget, the schema, restricted vs
    tools) from the repo's own state, and emits a schema-checked envelope.

.DESCRIPTION
    Thin layer over Invoke-ReadOnlyAgent.ps1 (F2/F3), which this script does not change the
    behaviour of for any existing caller -- everything below is additive. What this script adds:

    1. **A concrete --max-budget-usd the caller never has to know.** Looked up from
       tools/headless/budgets.json's "subagent" table by the agent's model (read from
       claude-agents/<name>.md frontmatter). No entry, and no explicit -MaxBudgetUsd override ->
       refuse to run (exit 4), matching Invoke-ReadOnlyAgent.ps1's own fail-closed convention. A
       "low seat must not compose ten-flag invocations" (plan section 2) includes not having to
       know or guess a dollar figure either.

    2. **Schema-checked envelope, live acceptance for F4.** If tools/headless/schemas/<name>.json
       exists, it is passed through as --json-schema (F12's own addition to Invoke-ReadOnlyAgent.ps1,
       -JsonSchemaPath) so the CLI's structured-output validation constrains the model's answer, and
       this script ALSO validates the returned envelope's own result payload against the same schema
       with JsonSchemaLite.ps1, so a caller gets a clear PASS/FAIL rather than having to parse the
       envelope itself. -RunLive is required to actually spend budget on this; without it, this
       script only proves the schema file resolves and is well-formed (same as the offline suite
       tools/tests/test-headless-schemas.ps1 already does) -- it does not claim a live CLI run.

    3. **Always -Report mode**, so the caller (and this script's own schema check) has the CLI's
       real JSON envelope to work from, never prose.

.PARAMETER AgentName
    The subagent to run, e.g. "worktree-sweep". Required.

.PARAMETER Prompt
    The prompt to send, on stdin (via Invoke-ReadOnlyAgent.ps1). Required.

.PARAMETER MaxBudgetUsd
    Optional override. When omitted, resolved from budgets.json by the agent's model tier.

.PARAMETER TimeoutSec
    Hard wall-clock timeout, passed straight through. Default 300 (Invoke-ReadOnlyAgent.ps1's own
    default), carrying the same wrapper-level timeout-and-kill that script already implements.

.PARAMETER ReportDir
    Passed through to Invoke-ReadOnlyAgent.ps1. Default %APPDATA%\AEGIS\reports.

.PARAMETER SkipSchemaCheck
    Skip the local JsonSchemaLite re-check of the returned envelope even when a schema exists for
    this agent. The CLI's own --json-schema constraint (when -RunLive is set) is unaffected.

.PARAMETER BudgetsPath
    Test seam. Default tools/headless/budgets.json next to this script.

.PARAMETER AgentsDir / RosterMetaPath / SchemasDir
    Test seams for the agent-definition, roster and schema directories this script reads.

.PARAMETER InvokeReadOnlyAgentPath
    Test seam: path to Invoke-ReadOnlyAgent.ps1. Default next to this script.

.PARAMETER DryRun
    Resolves the model/budget/schema lookups and prints what would be launched. Never calls
    Invoke-ReadOnlyAgent.ps1 or claude.

.PARAMETER ClaudePath
    Test seam, forwarded to Invoke-ReadOnlyAgent.ps1 unchanged (its own AEGIS_TEST_SEAM=1 gate
    still applies there).

.NOTES
    Exit codes: 0 = ran and Invoke-ReadOnlyAgent.ps1 exited 0. 4 = no concrete budget could be
    resolved for this agent and no override was supplied -- fails closed. 8 = a schema exists for
    this agent and the returned envelope's result did not validate against it (schema-checked
    envelope failure). Any other non-zero code is Invoke-ReadOnlyAgent.ps1's own exit code,
    propagated as-is (see that script's own .NOTES for what each one means).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$AgentName,
    [Parameter(Mandatory = $true)][string]$Prompt,
    [double]$MaxBudgetUsd,
    [int]$TimeoutSec = 300,
    [string]$ReportDir,
    [switch]$SkipSchemaCheck,
    [switch]$RunLive,
    [string]$BudgetsPath,
    [string]$AgentsDir,
    [string]$RosterMetaPath,
    [string]$SchemasDir,
    [string]$InvokeReadOnlyAgentPath,
    [string]$ClaudePath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if (-not $BudgetsPath) { $BudgetsPath = Join-Path $PSScriptRoot 'budgets.json' }
if (-not $AgentsDir) { $AgentsDir = Join-Path $PSScriptRoot '..\..\claude-agents' }
if (-not $RosterMetaPath) { $RosterMetaPath = Join-Path $AgentsDir 'roster_meta.json' }
if (-not $SchemasDir) { $SchemasDir = Join-Path $PSScriptRoot 'schemas' }
if (-not $InvokeReadOnlyAgentPath) { $InvokeReadOnlyAgentPath = Join-Path $PSScriptRoot 'Invoke-ReadOnlyAgent.ps1' }

# --- Resolve the agent's model from its own frontmatter, so the budget lookup does not require
# the caller to know or state it. Falls back to "default" tier if the file/frontmatter is missing
# or unparsable -- a missing agent definition is Invoke-ReadOnlyAgent.ps1's own problem to refuse
# on (roster_meta.json lookup), not this script's; this script only needs "which budget row".
function Get-AgentModelTier([string]$Name, [string]$AgentsDirPath) {
    $agentFile = Join-Path $AgentsDirPath "$Name.md"
    if (-not (Test-Path -LiteralPath $agentFile -PathType Leaf)) { return 'default' }
    $text = [System.IO.File]::ReadAllText($agentFile)
    $m = [regex]::Match($text, '(?m)^model:\s*([A-Za-z0-9._-]+)\s*$')
    if (-not $m.Success) { return 'default' }
    $model = $m.Groups[1].Value.ToLowerInvariant()
    if ($model -like 'haiku*') { return 'haiku' }
    if ($model -like 'sonnet*') { return 'sonnet' }
    if ($model -like 'opus*') { return 'opus' }
    return 'default'
}

function Get-ResolvedBudget([double]$Explicit, [bool]$ExplicitGiven, [string]$Tier, [string]$BudgetsFile) {
    if ($ExplicitGiven) { return $Explicit }
    if (-not (Test-Path -LiteralPath $BudgetsFile -PathType Leaf)) {
        Write-Host "Invoke-Subagent: budgets file not found at $BudgetsFile and no -MaxBudgetUsd override was given. Refusing to guess a budget. Nothing was launched." -ForegroundColor Red
        exit 4
    }
    try {
        $budgets = Get-Content -LiteralPath $BudgetsFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Host "Invoke-Subagent: budgets file at $BudgetsFile could not be parsed: $($_.Exception.Message). Refusing to guess a budget. Nothing was launched." -ForegroundColor Red
        exit 4
    }
    $subagentProp = $budgets.PSObject.Properties['subagent']
    if (-not $subagentProp) {
        Write-Host "Invoke-Subagent: budgets file at $BudgetsFile has no 'subagent' table. Refusing to guess a budget. Nothing was launched." -ForegroundColor Red
        exit 4
    }
    $table = $subagentProp.Value
    $tierProp = $table.PSObject.Properties[$Tier]
    if (-not $tierProp) { $tierProp = $table.PSObject.Properties['default'] }
    if (-not $tierProp) {
        Write-Host "Invoke-Subagent: no budget entry for tier '$Tier' (or 'default') in $BudgetsFile. Refusing to guess a budget. Nothing was launched." -ForegroundColor Red
        exit 4
    }
    return [double]$tierProp.Value
}

$tier = Get-AgentModelTier -Name $AgentName -AgentsDirPath $AgentsDir
$explicitGiven = $PSBoundParameters.ContainsKey('MaxBudgetUsd')
$resolvedBudget = Get-ResolvedBudget -Explicit $MaxBudgetUsd -ExplicitGiven $explicitGiven -Tier $tier -BudgetsFile $BudgetsPath

$schemaPath = Join-Path $SchemasDir "$AgentName.json"
$hasSchema = Test-Path -LiteralPath $schemaPath -PathType Leaf

if ($DryRun) {
    Write-Host "DRYRUN AgentName=$AgentName tier=$tier resolvedBudget=$resolvedBudget hasSchema=$hasSchema schemaPath=$(if ($hasSchema) { $schemaPath } else { '(none)' }) runLive=$($RunLive.IsPresent)"
    exit 0
}

if (-not $ReportDir) {
    if (-not $env:APPDATA) {
        Write-Host "Invoke-Subagent: %APPDATA% is not set and no -ReportDir was given. Nothing was launched." -ForegroundColor Red
        exit 2
    }
    $ReportDir = Join-Path $env:APPDATA 'AEGIS\reports'
}

# Hashtable splat (not an array splat) is required so PowerShell binds each value to its named
# parameter -- an array splat has no flag names in it at all, so in Windows PowerShell 5.1 every
# element (including the literal '-MaxBudgetUsd' string) binds positionally instead, landing on
# Invoke-ReadOnlyAgent.ps1's own first-declared parameter and throwing a type-conversion error.
# See PR #197 QA comment (2026-09-22) for the isolated repro. Matches Invoke-Lane.ps1's pattern.
$innerArgs = [ordered]@{
    AgentName     = $AgentName
    Prompt        = $Prompt
    MaxBudgetUsd  = $resolvedBudget
    TimeoutSec    = $TimeoutSec
    Report        = $true
    ReportDir     = $ReportDir
    RosterMetaPath = $RosterMetaPath
}
if ($hasSchema -and $RunLive) {
    # Only threaded to the real claude invocation when the caller opted into spending budget on a
    # live run -- this is the "live acceptance for F4" case. Without -RunLive, this script proves
    # the schema resolves and is well-formed but makes no live-CLI claim (see below).
    $innerArgs['JsonSchemaPath'] = $schemaPath
}
if ($ClaudePath) { $innerArgs['ClaudePath'] = $ClaudePath }

if (-not $RunLive) {
    Write-Host "Invoke-Subagent: -RunLive not set. Resolved tier=$tier budget=$resolvedBudget hasSchema=$hasSchema; not launching claude (no budget spent). Pass -RunLive to actually run '$AgentName'." -ForegroundColor Yellow
    if ($hasSchema -and -not $SkipSchemaCheck) {
        Write-Host "Invoke-Subagent: schema file exists and is checked for well-formedness only (offline) -- same guarantee tools/tests/test-headless-schemas.ps1 already gives. This is NOT a live '--json-schema' acceptance run." -ForegroundColor Yellow
        try {
            $null = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Host "Invoke-Subagent: schema at $schemaPath does not parse as JSON: $($_.Exception.Message)" -ForegroundColor Red
            exit 8
        }
    }
    exit 0
}

& $InvokeReadOnlyAgentPath @innerArgs
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Host "Invoke-Subagent: '$AgentName' did not complete cleanly (exit $exitCode). No schema check performed -- see Invoke-ReadOnlyAgent.ps1's own exit code table." -ForegroundColor Red
    exit $exitCode
}

if ($hasSchema -and -not $SkipSchemaCheck) {
    # Find the report just written: newest file in ReportDir matching AgentName.*.json.
    $reportFile = Get-ChildItem -LiteralPath $ReportDir -Filter "$AgentName.*.json" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $reportFile) {
        Write-Host "Invoke-Subagent: '$AgentName' exited 0 but no report file was found in $ReportDir to schema-check." -ForegroundColor Red
        exit 8
    }
    . (Join-Path $PSScriptRoot 'JsonSchemaLite.ps1')
    $reportJson = Get-Content -LiteralPath $reportFile.FullName -Raw | ConvertFrom-Json
    $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    $resultText = $reportJson.envelope | ConvertFrom-Json | ForEach-Object { $_.result }
    if (-not $resultText) {
        Write-Host "Invoke-Subagent: report envelope has no 'result' field to schema-check ($($reportFile.FullName))." -ForegroundColor Red
        exit 8
    }
    try {
        $resultParsed = $resultText | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Host "Invoke-Subagent: envelope.result is not valid JSON, so it cannot be schema-checked: $($_.Exception.Message)" -ForegroundColor Red
        exit 8
    }
    $errs = Test-JsonSchemaLite -Value $resultParsed -Schema $schema
    if ($errs.Count -gt 0) {
        Write-Host "Invoke-Subagent: SCHEMA CHECK FAILED for '$AgentName' against $schemaPath -- $($errs -join '; ')" -ForegroundColor Red
        exit 8
    }
    Write-Host "Invoke-Subagent: schema check PASSED for '$AgentName' against $schemaPath (live, real claude -p --json-schema run)." -ForegroundColor Green
}

exit 0
