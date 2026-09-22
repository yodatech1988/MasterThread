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

.PARAMETER Model
    Optional passthrough to Invoke-ReadOnlyAgent.ps1's own -Model (--model). Default: the named
    agent's own frontmatter model:, or whatever the CLI defaults to if that is absent (currently
    claude-haiku-4-5-20251001 for this repo's agents). Relevant to the structured-output note
    below: Haiku on the standard API returns envelope.structured_output fine once the launch
    avoids `--agent` (see Invoke-ReadOnlyAgent.ps1's .NOTES) -- an agent whose schema check keeps
    hitting exit 9 more likely has -JsonSchemaPath's `--append-system-prompt-file` fallback failing
    to resolve its claude-agents/<name>.md (see -AgentsDir) than a model limitation.

.PARAMETER UseLegacyResultField
    Opt-in fallback: schema-check envelope.result (the model's own prose) instead of
    envelope.structured_output. Default off. See .NOTES for why this is off by default and exit 9.

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
    resolved for this agent and no override was supplied -- fails closed. 5 = roster_meta.json
    classifies this agent as NOT restricted (readonly != "tools") and no 'tools:' frontmatter
    value could be resolved for it in claude-agents/<name>.md -- fails closed rather than passing
    no --tools to Invoke-ReadOnlyAgent.ps1 (same meaning as that script's own exit 5). 8 = a schema
    exists for this agent and the returned envelope's schema-checked payload did not validate
    against it (schema-checked envelope failure). 9 = a schema exists for this agent (and -RunLive
    was set) but the returned envelope has no envelope.structured_output at all to check --
    distinct from 8 (a payload WAS returned and failed validation): this means the CLI never gave
    us a validated answer to check in the first place, commonly because the model/API tier does
    not support structured outputs (see -Model / -UseLegacyResultField above), not a
    schema-conformance problem with the agent's own output. Any other non-zero code is
    Invoke-ReadOnlyAgent.ps1's own exit code, propagated as-is (see that script's own .NOTES for
    what each one means).
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
    [string]$Model,
    [switch]$UseLegacyResultField,
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

# --- Resolve the agent's -Tools value from its own frontmatter's 'tools:' line (the same field
# tools/generate_agents_md.py reads to classify the roster), so a caller of this script never has
# to know or state an agent's tool list either -- same "resolves restricted vs tools ... from the
# repo's own state" promise this script's synopsis already makes. Returns $null (not 'default';
# there is no safe default tool set) if the file/frontmatter is missing or has no 'tools:' line.
function Get-AgentTools([string]$Name, [string]$AgentsDirPath) {
    $agentFile = Join-Path $AgentsDirPath "$Name.md"
    if (-not (Test-Path -LiteralPath $agentFile -PathType Leaf)) { return $null }
    $text = [System.IO.File]::ReadAllText($agentFile)
    $m = [regex]::Match($text, '(?m)^tools:\s*(.+?)\s*$')
    if (-not $m.Success) { return $null }
    $value = $m.Groups[1].Value.Trim()
    if (-not $value) { return $null }
    return $value
}

# --- Resolve the agent's roster_meta.json "readonly" classification, purely to decide whether a
# -Tools value is actually required here -- this mirrors (does not replace) Invoke-ReadOnlyAgent.ps1's
# own -Restricted default-on lookup against the exact same file/field (owner decision D3), so the
# two scripts never disagree about what "restricted by default" means. Returns $null (not 'n/a')
# when the roster file/entry can't be read at all -- that case is left to Invoke-ReadOnlyAgent.ps1's
# own default-on lookup (its exit 4), not duplicated here, since it is a different failure than
# "no tools value found for an agent that needs one" (this script's exit 5).
function Get-AgentReadonlyClass([string]$Name, [string]$RosterMetaFile) {
    if (-not (Test-Path -LiteralPath $RosterMetaFile -PathType Leaf)) { return $null }
    try {
        $roster = Get-Content -LiteralPath $RosterMetaFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $null
    }
    $entryProp = $roster.PSObject.Properties[$Name]
    if (-not $entryProp) { return $null }
    $readonlyProp = $entryProp.Value.PSObject.Properties['readonly']
    if (-not $readonlyProp) { return $null }
    return [string]$readonlyProp.Value
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

# --- Resolve -Tools the same way -MaxBudgetUsd's tier is resolved: from the agent's own
# frontmatter, with roster_meta.json consulted only to know whether a value is actually required
# (see the two functions above). Not required at all when the roster classifies this agent
# "readonly": "tools" (Invoke-ReadOnlyAgent.ps1 will run it -Restricted and ignore any -Tools
# passed anyway). When roster_meta.json can't be read or doesn't list this agent, resolve what we
# can and let Invoke-ReadOnlyAgent.ps1's own default-on lookup make (and report) that call.
$readonlyClass = Get-AgentReadonlyClass -Name $AgentName -RosterMetaFile $RosterMetaPath
$resolvedTools = Get-AgentTools -Name $AgentName -AgentsDirPath $AgentsDir
$toolsRequired = ($readonlyClass -and $readonlyClass -ne 'tools')

if ($toolsRequired -and -not $resolvedTools) {
    Write-Host "Invoke-Subagent: '$AgentName' resolved to NOT restricted (roster_meta.json readonly='$readonlyClass') but no 'tools:' frontmatter value could be resolved for it in $AgentsDir. Refusing to guess a tool set. Nothing was launched." -ForegroundColor Red
    exit 5
}

if ($DryRun) {
    Write-Host "DRYRUN AgentName=$AgentName tier=$tier resolvedBudget=$resolvedBudget hasSchema=$hasSchema schemaPath=$(if ($hasSchema) { $schemaPath } else { '(none)' }) readonlyClass=$(if ($readonlyClass) { $readonlyClass } else { '(unknown)' }) resolvedTools=$(if ($resolvedTools) { $resolvedTools } else { '(none)' }) runLive=$($RunLive.IsPresent)"
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
if ($resolvedTools -and $readonlyClass -ne 'tools') {
    # Not passed at all when the roster classifies this agent "tools" (restricted by default) --
    # Invoke-ReadOnlyAgent.ps1 would only warn and ignore it there, so there is no reason to send it.
    $innerArgs['Tools'] = $resolvedTools
}
if ($hasSchema -and $RunLive) {
    # Only threaded to the real claude invocation when the caller opted into spending budget on a
    # live run -- this is the "live acceptance for F4" case. Without -RunLive, this script proves
    # the schema resolves and is well-formed but makes no live-CLI claim (see below).
    $innerArgs['JsonSchemaPath'] = $schemaPath
}
if ($ClaudePath) { $innerArgs['ClaudePath'] = $ClaudePath }
if ($Model) { $innerArgs['Model'] = $Model }

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
    # Found by dry-tracing this path end to end (PR #197, fable/f12): Invoke-ReadOnlyAgent.ps1's
    # report is {envelope, checkedAt, command} with envelope as a NESTED OBJECT (it already parsed
    # the CLI's JSON stdout before writing the report) -- not a JSON string.
    #
    # 2026-09-22 fix (issue #212 follow-up): per code.claude.com/docs/en/headless.md "Get
    # structured output", `--output-format json` + `--json-schema` puts the SCHEMA-VALIDATED
    # payload in envelope.structured_output, not envelope.result -- envelope.result stays the
    # model's own prose even on a fully successful, schema-conforming run. The Agent SDK
    # troubleshooting page is explicit that a "success" subtype with no structured_output must be
    # treated as a failure, not a pass. Verified live 2026-09-22 against three real pr-state-sweep
    # runs (drop-folder reports 145241, 172129, 173309): all three passed --json-schema on the
    # command line, ran claude-haiku-4-5-20251001 with no --model override, and all three envelopes
    # have subtype "success" and no structured_output key at all. The actual cause is NOT the model:
    # a peer's live probes (8 Haiku runs, CLI 2.1.280, same schema) found --json-schema is silently
    # not enforced on any run launched with --agent <name> -- every non-`--agent` invocation shape
    # returned envelope.structured_output; every `--agent` invocation returned prose with no
    # structured_output key, subtype "success" regardless. Invoke-ReadOnlyAgent.ps1 now avoids
    # `--agent` whenever -JsonSchemaPath is given (see its own .NOTES), which is confirmed live to
    # restore envelope.structured_output on Haiku -- no model change needed. The block below now
    # reads envelope.structured_output by default; -UseLegacyResultField is an explicit opt-in fallback
    # to the old (wrong-for-this-purpose) envelope.result read, kept only for a caller that knows
    # it is on a code path where structured_output is genuinely never populated (e.g. no schema
    # was actually requested) and still wants some check performed. Exit 8's meaning (schema
    # exists, returned payload did not validate) is unchanged; missing structured_output is a
    # DIFFERENT failure -- exit 9 -- since "the model's answer failed validation" and "the CLI
    # never gave us a validated answer to check" are not the same finding and should not share a
    # code.
    if ($UseLegacyResultField) {
        $resultText = $reportJson.envelope.result
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
    } else {
        $structuredOutput = $reportJson.envelope.structured_output
        if ($null -eq $structuredOutput) {
            Write-Host "Invoke-Subagent: SCHEMA-VALIDATED OUTPUT MISSING for '$AgentName' -- a schema was passed (--json-schema) but the CLI envelope has no 'structured_output' field (subtype='$($reportJson.envelope.subtype)'). Per the Agent SDK docs, a 'success' subtype with no structured_output must be treated as a failure, not a pass -- this is commonly a model/API-tier limitation (e.g. Haiku on the standard API), not a schema-conformance problem. Report: $($reportFile.FullName)." -ForegroundColor Red
            exit 9
        }
        $resultParsed = $structuredOutput
    }
    $errs = Test-JsonSchemaLite -Value $resultParsed -Schema $schema
    if ($errs.Count -gt 0) {
        Write-Host "Invoke-Subagent: SCHEMA CHECK FAILED for '$AgentName' against $schemaPath -- $($errs -join '; ')" -ForegroundColor Red
        exit 8
    }
    Write-Host "Invoke-Subagent: schema check PASSED for '$AgentName' against $schemaPath (live, real claude -p --json-schema run)." -ForegroundColor Green
}

exit 0
