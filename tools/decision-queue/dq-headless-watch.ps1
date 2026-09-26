<#
.SYNOPSIS
    Headless, low-context check of specific Decision Queue cards -- wakes a human/PM only when
    one of them actually changed.

.DESCRIPTION
    Built for Decision Queue card `cost-monitor-card-watcher-headless-2026-09-26` (option 0,
    resolved 2026-09-26): move the 5-minute "did the owner answer?" check out of an interactive
    PM session's own context (SELF_IMPROVEMENT_PLAN_2026-09-26.md section R2) into a cheap
    headless run that a Windows Task Scheduler job can fire on a timer.

    Verification done before this script was written (2026-09-26, this PR): a subagent has no
    ArtifactData tool, so the open question -- can a headless `claude -p` process call it at all --
    could only be tested by actually invoking `claude -p` as a subprocess and inspecting the real
    tool_use/tool_result blocks (`--output-format stream-json`), not by asking the CLI to describe
    itself (a model can hallucinate tool success). It can: a `get` against the live artifact
    (https://claude.ai/artifact/1fMqNA1zdQKsq1FDEFvyzf, collection `decisions`) returned the real
    stored document. See the PR description for the exact commands and raw output.

    Cost finding that revises the plan's own estimate: the plan guessed about $0.01/tick because a
    scoped agent "starts at about 5K of context". Measured instead: even with -AllowedTools limited
    to exactly "ArtifactData" and one doc id, the run reads/writes on the order of 180K/48K cache
    tokens (about $0.10-0.19 per invocation on Haiku, scaling up a little per extra doc id) --
    the fixed per-invocation baseline (system prompt, connected MCP servers, skills listing) loads
    regardless of --allowedTools, and --bare (which would strip it) breaks OAuth/keychain auth this
    machine's Claude Code subscription billing relies on (`aegis-claude-code-subscription-billing`
    memory), so --bare is not usable here without a paid API key. At a 5-minute cadence that is
    roughly $1-2/hour, or about $30/day run around the clock -- far cheaper than the plan's own
    estimate of $4-14/hour for an idle interactive PM running the same check, but not the "$3/day"
    figure in SELF_IMPROVEMENT_PLAN_2026-09-26.md; whoever turns this on should re-read that number
    against real cost-monitor data after a day of real runs.

    What this script does, once per invocation:
      1. Loads last-seen {version, status} per doc id from -StateFile (a small JSON file; the first
         run has no prior state, so every doc id it finds counts as new).
      2. Runs one headless `claude -p` call, model -Model (default Haiku), -AllowedTools limited to
         exactly "ArtifactData", --permission-mode dontAsk --permission-prompts none (nothing waits
         on a prompt nobody can answer), --output-format json, and a --json-schema that forces the
         reply to be ONLY {"docs":[{doc_id, found, version, status}, ...]} -- no prose, so this
         script never has to parse free text and never has to print a card body anywhere.
      3. Diffs each returned doc against the state file. A line is appended to -LogFile ONLY for a
         doc that is new, whose version changed, or whose status changed -- doc_id plus the old and
         new version/status, never the card's other fields (summary, options, resolution text, ...).
      4. Rewrites -StateFile with the latest {version, status} for every doc id it checked.

    This script does not decide the doc id list, does not read/write anything other than
    -StateFile and -LogFile, does not resolve or edit a Decision Queue card, and does not schedule
    itself -- per the task that produced it, turning this into a real recurring job (Windows Task
    Scheduler) is a follow-up the owner or PM does after reviewing this PR, not something this
    script or its author enables.

.PARAMETER DocIds
    One or more Decision Queue doc ids to check, e.g. "cost-monitor-card-watcher-headless-2026-09-26".
    Required -- this script never lists or queries the whole collection (SELF_IMPROVEMENT_PLAN's
    own point: a full `list`/`query` is the expensive, high-context path this exists to avoid).

.PARAMETER ArtifactUrl
    The Decision Queue artifact's claude.ai URL. Default is the live page
    (https://claude.ai/artifact/1fMqNA1zdQKsq1FDEFvyzf) per
    tools/decision-queue/README.md.

.PARAMETER Collection
    The ArtifactData collection to read. Default "decisions".

.PARAMETER StateFile
    Where last-seen {version, status} per doc id is kept. Default
    "$env:APPDATA\AEGIS\dq-watch-state.json". Created if missing.

.PARAMETER LogFile
    Where one line per real change is appended. Default
    "$env:APPDATA\AEGIS\dq-changes.log". Created if missing. Never receives a full card body.

.PARAMETER Model
    Model alias passed to `claude -p --model`. Default "haiku" -- this is a version/status
    comparison, not a judgment call, and needs no larger model.

.PARAMETER TimeoutSec
    Hard wall-clock timeout for the `claude -p` call. Default 120.

.OUTPUTS
    Exit 0 on a successful check (whether or not anything changed). Exit 1 if the `claude` CLI
    could not be found. Exit 2 if the `claude -p` call itself failed (is_error true, or its stdout
    did not parse as JSON) -- the state file is left untouched on this path, so a transient failure
    does not paper over a real change. Prints one summary line to stdout either way; the caller
    (a Monitor tail -F on -LogFile, per the plan) does not need to parse this script's own stdout.

.NOTES
    Deliberately minimal: no roster entry, no agent definition, no queue/orchestration layer.
    ArtifactData is not a Bash sub-command `tools/headless/Invoke-ReadOnlyAgent.ps1`'s
    -Restricted/-AllowedTools three-layer model was built to fence in -- it is a first-class tool
    granted directly by name, and `--allowedTools "ArtifactData"` was verified (this PR) to be
    the whole grant a caller needs. Wiring this into that heavier harness (roster_meta.json entry,
    agent-automation-gatekeeper review, a schemas/*.json file) is left for whoever turns this into
    a standing agent -- this script is the thing to point that process at, not a replacement for it.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$DocIds,

    [string]$ArtifactUrl = "https://claude.ai/artifact/1fMqNA1zdQKsq1FDEFvyzf",

    [string]$Collection = "decisions",

    [string]$StateFile = "$env:APPDATA\AEGIS\dq-watch-state.json",

    [string]$LogFile = "$env:APPDATA\AEGIS\dq-changes.log",

    [string]$Model = "haiku",

    [int]$TimeoutSec = 120
)

$ErrorActionPreference = "Stop"

function Resolve-ClaudeExe {
    # Same resolution convention as tools/headless/Invoke-ReadOnlyAgent.ps1's Resolve-NativeClaudeExe
    # (issue #206 fix A): `claude` on PATH resolves ambiguously between a shebang script, claude.cmd
    # and claude.ps1, and `Start-Process -FilePath 'claude'` has been observed to pick the wrong one.
    # Resolve claude.cmd explicitly, then prefer the sibling native claude.exe (this script needs the
    # native exe anyway, since ProcessStartInfo cannot run a .cmd/.ps1 directly).
    $cmd = Get-Command claude.cmd -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return $null
    }
    $dir = Split-Path -Parent $cmd.Source
    $native = Join-Path $dir 'node_modules\@anthropic-ai\claude-code\bin\claude.exe'
    if (Test-Path $native) {
        return (Resolve-Path -LiteralPath $native).ProviderPath
    }
    return $cmd.Source
}

$claudeExe = Resolve-ClaudeExe
if (-not $claudeExe) {
    Write-Error "dq-headless-watch: claude CLI not found on PATH (looked for claude.cmd)."
    exit 1
}

# Ensure state/log directories exist.
foreach ($path in @($StateFile, $LogFile)) {
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
}

# Load prior state (doc_id -> @{ version = ...; status = ... }).
$state = @{}
if (Test-Path $StateFile) {
    try {
        $raw = Get-Content $StateFile -Raw | ConvertFrom-Json
        foreach ($prop in $raw.PSObject.Properties) {
            $state[$prop.Name] = @{
                version = $prop.Value.version
                status  = $prop.Value.status
            }
        }
    } catch {
        Write-Warning "dq-headless-watch: could not parse $StateFile, treating as empty state. $_"
        $state = @{}
    }
}

# Build the doc-id list as a JSON array for the prompt.
$docIdsJson = ($DocIds | ForEach-Object { '"' + ($_ -replace '"', '') + '"' }) -join ", "

$prompt = @"
For each doc_id in this list, call the ArtifactData tool with action=get, url=$ArtifactUrl, collection=$Collection, doc_id=<id>.
Doc ids: [$docIdsJson]
For each one, report only: doc_id, found (true/false), version (0 if not found), and the "status" field from its data (or "not found" if not found).
Do not report any other field from the document (no summary, options, resolution, rationale, or any other text). No prose, no explanation.
"@

$schema = '{"type":"object","properties":{"docs":{"type":"array","items":{"type":"object","properties":{"doc_id":{"type":"string"},"found":{"type":"boolean"},"version":{"type":"number"},"status":{"type":"string"}},"required":["doc_id","found"]}}},"required":["docs"]}'

$claudeArgs = @(
    "-p",
    "--model", $Model,
    "--allowedTools", "ArtifactData",
    "--permission-mode", "dontAsk",
    "--permission-prompts", "none",
    "--output-format", "json",
    "--json-schema", $schema
)

$stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

function ConvertTo-QuotedArg([string]$Value) {
    # Windows PowerShell 5.1's ProcessStartInfo has no .ArgumentList (that's a .NET Core-only
    # property), so the argument line has to be built and quoted by hand here. $claudeExe is a
    # real native .exe (see Resolve-ClaudeExe), not a .cmd, so standard Win32 argv quoting
    # applies: wrap in double quotes and escape embedded double quotes as \" (backslashes
    # immediately preceding a quote are doubled first, per the CommandLineToArgvW convention).
    $escaped = $Value -replace '(\\*)"', '$1$1\"'
    if ($escaped -match '(\\+)$') {
        $escaped = $escaped + $Matches[1]
    }
    return '"' + $escaped + '"'
}

try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $claudeExe
    $psi.Arguments = ($claudeArgs | ForEach-Object { ConvertTo-QuotedArg $_ }) -join ' '
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.StandardInput.Write($prompt)
    $proc.StandardInput.Close()

    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()

    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        try { $proc.Kill() } catch {}
        Write-Error "dq-headless-watch: claude -p timed out after $TimeoutSec s."
        exit 2
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
} catch {
    Write-Error "dq-headless-watch: failed to launch claude -p. $_"
    exit 2
}

if ($proc.ExitCode -ne 0) {
    Write-Error "dq-headless-watch: claude -p exited $($proc.ExitCode). stderr: $stderr"
    exit 2
}

try {
    $envelope = $stdout | ConvertFrom-Json
} catch {
    Write-Error "dq-headless-watch: claude -p stdout did not parse as JSON. $_"
    exit 2
}

if ($envelope.is_error) {
    Write-Error "dq-headless-watch: claude -p reported is_error. result: $($envelope.result)"
    exit 2
}

$docs = $null
if ($envelope.structured_output -and $envelope.structured_output.docs) {
    $docs = $envelope.structured_output.docs
} else {
    try {
        $parsedResult = $envelope.result | ConvertFrom-Json
        $docs = $parsedResult.docs
    } catch {
        Write-Error "dq-headless-watch: no structured_output.docs and result did not parse as the expected shape."
        exit 2
    }
}

if (-not $docs) {
    Write-Error "dq-headless-watch: response had no docs array."
    exit 2
}

$changed = @()
$newState = @{}

foreach ($doc in $docs) {
    $id = $doc.doc_id
    $version = if ($doc.found) { [int]$doc.version } else { 0 }
    $status = if ($doc.found) { [string]$doc.status } else { "not found" }

    $prior = $state[$id]
    $newState[$id] = @{ version = $version; status = $status }

    if (-not $prior) {
        $changed += "$stamp NEW $id version=$version status=$status"
    } elseif ($prior.version -ne $version -or $prior.status -ne $status) {
        $changed += "$stamp CHANGED $id version=$($prior.version)->$version status=$($prior.status)->$status"
    }
}

if ($changed.Count -gt 0) {
    $changed | Add-Content -Path $LogFile -Encoding utf8
}

($newState | ConvertTo-Json -Depth 5) | Set-Content -Path $StateFile -Encoding utf8

$costUsd = $envelope.total_cost_usd
Write-Output "dq-headless-watch: checked $($docs.Count) doc(s), $($changed.Count) changed, cost `$$costUsd. Log: $LogFile"
exit 0
