<#
.SYNOPSIS
    Plan task F13 -- seat-side renderer for the `review-verdict/v1` schema
    (DESIGN_f13-review-verdict_2026-09-22.md, section 3): turns a diff-reviewer/live-reviewer
    verdict object into a scannable PR comment body, and optionally posts it. Lives next to the
    F12 wrapper family (Ask-Fable.ps1, Invoke-Lane.ps1, Invoke-Subagent.ps1) and reuses
    JsonSchemaLite.ps1 by dot-sourcing, exactly as Invoke-Subagent.ps1 does.

.DESCRIPTION
    HARD REQUIREMENT 1 (stated verbatim, PM handoff for this draft): "Assumes: schema runs launch
    WITHOUT --agent; the agent body is supplied via --append-system-prompt-file with the same
    boundary flags (#214 lane)." Until the #212 fix lands (design section 0), no live
    `-ReportPath` produced through today's `--agent <name>` launch form will ever carry
    `structured_output` at all -- every such report exits 8 below, and that is the correct,
    documented behaviour of this script, not a defect in it.

    HARD REQUIREMENT 2 (stated verbatim): "The renderer reads envelope.structured_output ONLY
    when given -ReportPath; it must never parse envelope.result as JSON anywhere, and a report
    whose envelope lacks structured_output exits 8." This script does not read, parse, quote, or
    even print `envelope.result` anywhere -- see the design's section 0 root-cause finding that
    Invoke-Subagent.ps1's existing `envelope.result` parse is exactly the bug that produced a
    false schema-check failure on a real #212 report. `.result` is prose/markdown per the CLI's
    own contract and is never assumed to carry JSON.

    Verdict source (exactly one of the two):
      -VerdictPath  a raw verdict JSON object -- the interactive live-reviewer path (Agent tool
                    output pasted into a file), or any hand-checked file. Read directly as the
                    verdict.
      -ReportPath   an F3 report `{envelope, checkedAt, command}` written by
                    `Invoke-Subagent.ps1 -RunLive` / `Invoke-ReadOnlyAgent.ps1 -Report`. The
                    verdict is `envelope.structured_output`. `envelope` is handled whether the
                    parsed report stores it as a nested object (the normal case: Invoke-
                    ReadOnlyAgent.ps1 embeds the CLI's raw stdout inline, so ConvertFrom-Json
                    parses it as a nested PSCustomObject -- see that script's own report-writing
                    comment, "envelope as a NESTED OBJECT ... not a JSON string") or, defensively,
                    as a JSON-encoded string. Missing/null/unparsable `structured_output` -> exit 8
                    in every case; nothing is rendered.

    Steps (design section 3): load verdict -> pick schema `schemas/<verdict.agent>.json` (missing
    -> exit 5) -> validate with JsonSchemaLite (errors -> exit 2) -> renderer-only rules (exit 2):
    -Repo/-PullRequest must equal the verdict's own `repo`/`pullRequest`; `escalate` must be
    non-null exactly when `verdict` is ESCALATE (not expressible in the schema subset) -> sort
    findings blocker->major->minor->nit then by file, line, and cap to -Cap -> live head check via
    `gh pr view <n> -R <repo> --json headRefOid` (mismatch -> exit 3, nothing posted; skipped
    entirely under -DryRun) -> render the body -> optional -Post -> read-back -> print the
    comment id and URL.

    What this script never does (design section 3, "What it never does"): `gh pr review` in any
    form, `gh pr merge`, a label edit, a Decision Queue card write, or a retry on another model
    when a report says refusal. A review *comment* here must never be able to trip core's
    claude-review.yml automerge gate, which keys on an APPROVED review on the head SHA.

    `gh` calls (Incident 2 remediation, standards/sessions/headless_agent_permissions.md: "Run
    each gh command on its own in a separate shell call -- never chain gh calls with &&, ||, ;"):
    every `gh` invocation below is its own `& $GhPath ...` call with `$LASTEXITCODE` checked
    immediately after it, never composed into a single string or chained. `pr view` (head check),
    `api repos/<repo>/issues/<n>/comments --paginate` (duplicate-marker check, before any post),
    `pr comment ... --body-file <tmp>` (the post itself), `api repos/<repo>/issues/comments/<id>`
    (the mandatory read-back -- a verdict is never reported as posted without it, same rule
    Incident 2 states for MERGE-VERDICT).

.PARAMETER ReportPath
    An F3 report file `{envelope, checkedAt, command}`. Mutually exclusive with -VerdictPath;
    exactly one of the two is required, checked before any file is read.

.PARAMETER VerdictPath
    A raw review-verdict JSON object. Mutually exclusive with -ReportPath.

.PARAMETER Repo
    owner/name of the PR being rendered for. Must equal the verdict's own `repo` (exit 2 on
    mismatch), so a verdict is never rendered onto the wrong PR.

.PARAMETER PullRequest
    The PR number. Must equal the verdict's own `pullRequest` (exit 2 on mismatch).

.PARAMETER Cap
    Findings shown on the face of the comment. Default 5 (mirrors the Decision Queue card
    standard's points <= 5). A verdict with more findings than this still validates; the rest are
    named as "N more in the report: <path>", never dropped from the source file.

.PARAMETER OutFile
    Write the rendered body here instead of stdout. Default: stdout (the success/output stream,
    distinct from the Write-Host status lines this script also prints).

.PARAMETER Post
    Actually post the rendered body as a PR comment. Without it, this script only renders (and,
    unless -DryRun, still performs the live head check, since a stale-head verdict is worth
    refusing to render cleanly even when nothing will be posted).

.PARAMETER Force
    Allow posting a second comment for the same marker+head. Default: an existing comment
    carrying the same `<!-- REVIEW-VERDICT v1 agent=... head=... -->` marker for this exact head
    -> exit 6, nothing posted.

.PARAMETER SchemasDir
    Test seam. Default `schemas` next to this script (resolved in the body, not in the param
    block -- see the .NOTES entry on the -File / empty-$PSScriptRoot defect this mirrors from
    Invoke-ReadOnlyAgent.ps1).

.PARAMETER GhPath
    Test seam. Default `gh`. A fake `gh` executable/script for driving this script's -Post path,
    live head check, and duplicate check without a real `gh` on PATH or a real GitHub call.

.PARAMETER DryRun
    Renders the body and prints, as informational (Write-Host) lines, exactly which `gh` calls
    would be made -- the live head check, and (with -Post) the duplicate check, the post, and the
    read-back -- without running any of them. Never resolves or invokes $GhPath. Exits 0.

.EXAMPLE
    .\Render-ReviewVerdict.ps1 -VerdictPath .\verdict.json -Repo yodatech1988/MasterThread `
        -PullRequest 209 -DryRun
    # Prints the rendered body to stdout and the gh calls that would run, without calling gh.

.EXAMPLE
    .\Render-ReviewVerdict.ps1 -ReportPath $env:APPDATA\AEGIS\reports\diff-reviewer.20260922-172129.json `
        -Repo yodatech1988/MasterThread -PullRequest 209 -Post
    # Live path: reads envelope.structured_output from the F3 report, validates, checks the live
    # head, posts one PR comment, reads it back, and prints its id and URL.

.NOTES
    Exit codes:
      0  rendered (and posted + read back when -Post was given).
      2  invalid verdict -- schema validation failed, the -Repo/-PullRequest parameters do not
         match the verdict's own repo/pullRequest, the ESCALATE/`escalate` pairing is wrong, a
         verdict/report file could not be read or parsed as JSON, or -ReportPath and -VerdictPath
         were both given or neither was given (checked before any file is read).
      3  the live head (`gh pr view --json headRefOid`) differs from the verdict's `headSha`, or
         that `gh` call itself failed. Nothing posted. Not reached under -DryRun (skipped).
      4  a -Post call failed: the duplicate-check `gh api` call errored, `gh pr comment` itself
         failed, this script could not determine the id of the comment it just posted, or the
         mandatory read-back (`gh api repos/<repo>/issues/comments/<id>`) failed or returned a
         mismatched id (Incident 2: never report a verdict as posted without a confirmed
         read-back). The rendered body is left on disk (the -Post temp file, and/or -OutFile if
         given) on every one of these paths.
      5  no schema could be resolved for this verdict: `agent` is missing/empty/unsafe, or
         `schemas/<agent>.json` does not exist or is not valid JSON.
      6  a comment carrying this exact marker (`agent`+`head`) already exists on this PR and
         -Force was not given. Nothing posted.
      8  -ReportPath was given and the envelope carries no `structured_output` object (absent,
         null, or unparsable) -- see HARD REQUIREMENT 2 above. Nothing rendered.
      1  unexpected internal error (an uncaught exception) -- distinct from every code above;
         printed with its exception type and message, per tools/README.md's "no path exits 0 on
         failure" rule and Invoke-ReadOnlyAgent.ps1's own try/catch-around-every-fallible-step
         precedent.

    -File / empty-$PSScriptRoot: mirrors the 2026-09-21 fix documented in
    Invoke-ReadOnlyAgent.ps1 -- under Windows PowerShell 5.1, a [CmdletBinding()] script invoked
    with `-File` (the way a scheduled task or another wrapper calls this script) sees an EMPTY
    $PSScriptRoot inside param() default *expressions*, so -SchemasDir's default is resolved in
    the script body instead, after $PSScriptRoot is populated.

    Windows PowerShell 5.1 only: no `??`, no ternary (`a ? b : c`), no `ConvertFrom-Json
    -AsHashtable`, no `&&`/`||` shell chaining of any `gh` call.
#>
[CmdletBinding()]
param(
    [string]$ReportPath,
    [string]$VerdictPath,
    [Parameter(Mandatory = $true)][string]$Repo,
    [Parameter(Mandatory = $true)][int]$PullRequest,
    [int]$Cap = 5,
    [string]$OutFile,
    [switch]$Post,
    [switch]$Force,
    [string]$SchemasDir,
    [string]$GhPath = 'gh',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# See .NOTES: $PSScriptRoot is empty inside param() defaults under `-File` in PS 5.1, so this
# default is resolved here, in the body, exactly as Invoke-ReadOnlyAgent.ps1 resolves -SettingsPath
# and -RosterMetaPath.
if (-not $SchemasDir) { $SchemasDir = Join-Path $PSScriptRoot 'schemas' }

# --- T14 / design section 3: "exactly one of the first two" -- checked before ANY file is read. -
$reportGiven = $PSBoundParameters.ContainsKey('ReportPath') -and $ReportPath
$verdictGiven = $PSBoundParameters.ContainsKey('VerdictPath') -and $VerdictPath
if (($reportGiven -and $verdictGiven) -or (-not $reportGiven -and -not $verdictGiven)) {
    # BUILD-LANE FIX (2026-09-22): Write-Host bypasses the success/error streams entirely, so a
    # caller capturing output via `2>&1` (the test-seam pattern used throughout tools/tests) never
    # saw this message. Write-Error -ErrorAction Continue writes to the error stream (captured by
    # 2>&1) without becoming a terminating error under this script's own $ErrorActionPreference='Stop'.
    Write-Error -Message "Render-ReviewVerdict: exactly one of -ReportPath or -VerdictPath is required. Nothing was read." -ErrorAction Continue
    exit 2
}

try {
    . (Join-Path $PSScriptRoot 'JsonSchemaLite.ps1')
} catch {
    Write-Error -Message "Render-ReviewVerdict: could not load JsonSchemaLite.ps1 next to this script: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}

# Set-StrictMode-safe property access (tools/README.md): PSObject.Properties, never a bare dotted
# read, for anything that has not yet passed schema validation (agent selection, envelope/report
# shape) -- the same pattern JsonSchemaLite.ps1 itself uses.
function Get-Prop($Obj, [string]$Name) {
    if ($Obj -isnot [System.Management.Automation.PSCustomObject]) { return $null }
    $p = $Obj.PSObject.Properties[$Name]
    if ($p) { return , $p.Value }
    return $null
}

function Exit-Fail([int]$Code, [string]$Message) {
    # BUILD-LANE FIX (2026-09-22): see the note above the first Write-Host->Write-Error conversion
    # in this file -- Write-Host is invisible to `2>&1` capture, which every gh-call test in
    # tools/tests/test-render-review-verdict.ps1 relies on to see this script's failure messages.
    Write-Error -Message "Render-ReviewVerdict: $Message" -ErrorAction Continue
    exit $Code
}

function Read-JsonFile([string]$Path, [int]$FailCode, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Exit-Fail $FailCode "$Label not found: $Path"
    }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    } catch {
        Exit-Fail $FailCode "$Label at $Path could not be read: $($_.Exception.Message)"
    }
    try {
        return $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Exit-Fail $FailCode "$Label at $Path is not valid JSON: $($_.Exception.Message)"
    }
}

function ConvertTo-ObjectIfString($Value) {
    # Defensive only: Invoke-ReadOnlyAgent.ps1 embeds the envelope as a nested JSON object, never a
    # string (its own report-writing comment: "envelope as a NESTED OBJECT ... not a JSON string"),
    # and structured_output is documented as an object. This exists only in case some other
    # producer JSON-encodes either one as a string field.
    if ($Value -is [string]) {
        try { return , ($Value | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
    }
    return , $Value
}

$ellipsis = [string][char]0x2026
$emDash = [string][char]0x2014
$midDot = [string][char]0x00B7
$bt = '`'

function Limit-Text([string]$Text, [int]$MaxLen) {
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    if ($Text.Length -le $MaxLen) { return $Text }
    return ($Text.Substring(0, $MaxLen) + $ellipsis + ' (truncated)')
}

function Protect-SecretTokens([string]$Text) {
    # Design section 8: for kind == secret, mask any substring matching the F14 token markers
    # before it ever reaches a PR comment. Applied to the `ask` text only (the schema has no other
    # free-text field on a finding), and only for kind == secret findings (see call site below).
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $pattern = '(ghp_[A-Za-z0-9]+|gho_[A-Za-z0-9]+|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9]+|xox[a-zA-Z0-9-]+|AKIA[A-Z0-9]+|-----BEGIN[^\r\n]*)'
    return [regex]::Replace($Text, $pattern, '[REDACTED]')
}

# =================================================================================================
# 1. Load the verdict -- either directly (-VerdictPath) or via an F3 report's
#    envelope.structured_output (-ReportPath). HARD REQUIREMENT 2: envelope.result is never read.
# =================================================================================================
$sourceForMoreLine = $null
$verdict = $null

if ($verdictGiven) {
    $verdict = Read-JsonFile $VerdictPath 2 'verdict file'
    $sourceForMoreLine = $VerdictPath
    if ($verdict -isnot [System.Management.Automation.PSCustomObject]) {
        Exit-Fail 2 "verdict file at $VerdictPath does not contain a JSON object"
    }
} else {
    $report = Read-JsonFile $ReportPath 2 'report file'
    $sourceForMoreLine = $ReportPath
    $envelope = ConvertTo-ObjectIfString (Get-Prop $report 'envelope')
    if ($envelope -isnot [System.Management.Automation.PSCustomObject]) {
        Exit-Fail 8 "report at $ReportPath has no usable envelope object; nothing rendered (never reads envelope.result)"
    }
    $structuredOutput = ConvertTo-ObjectIfString (Get-Prop $envelope 'structured_output')
    if ($null -eq $structuredOutput -or $structuredOutput -isnot [System.Management.Automation.PSCustomObject]) {
        Exit-Fail 8 "report at $ReportPath has no structured_output in its envelope (see design section 0 -- an --agent launch never populates it on CLI 2.1.280). Nothing rendered; envelope.result was not read."
    }
    $verdict = $structuredOutput
}

# =================================================================================================
# 2. Pick the schema from the verdict's own `agent` field (design section 3, step 1). Chicken-egg:
#    the schema itself pins `agent` with `const`, but we need `agent` BEFORE we can load that
#    schema, so this one read happens via the Set-StrictMode-safe helper, ahead of validation.
# =================================================================================================
$agentVal = Get-Prop $verdict 'agent'
if (-not $agentVal -or ($agentVal -isnot [string]) -or [string]::IsNullOrWhiteSpace([string]$agentVal)) {
    Exit-Fail 5 "verdict has no usable 'agent' field; cannot resolve a schema for it"
}
$agentName = [string]$agentVal
if ($agentName -notmatch '^[A-Za-z0-9._-]+$') {
    Exit-Fail 5 "verdict 'agent' value '$agentName' is not a safe schema file name; refusing to resolve a schema path from it"
}
$schemaPath = Join-Path $SchemasDir "$agentName.json"
$schema = Read-JsonFile $schemaPath 5 "schema for agent '$agentName'"

# =================================================================================================
# 3. JsonSchemaLite validation (design section 3, step 2).
# =================================================================================================
$schemaErrors = Test-JsonSchemaLite -Value $verdict -Schema $schema
if ($schemaErrors.Count -gt 0) {
    Exit-Fail 2 "verdict failed schema validation against $schemaPath -- $($schemaErrors -join '; ')"
}

# From here on every required field the schema lists is guaranteed present (though possibly null
# where the schema allows it), so plain dotted reads on $verdict and its required children are safe.

# =================================================================================================
# 4. Renderer-only rules the schema subset cannot express (design section 3, step 3; section 2's
#    "Design notes" on `escalate`). Both exit 2.
# =================================================================================================
if ($verdict.repo -ne $Repo) {
    Exit-Fail 2 "verdict repo '$($verdict.repo)' does not match -Repo '$Repo'"
}
if ([int]$verdict.pullRequest -ne $PullRequest) {
    Exit-Fail 2 "verdict pullRequest '$($verdict.pullRequest)' does not match -PullRequest '$PullRequest'"
}
if ($verdict.verdict -eq 'ESCALATE') {
    if ($null -eq $verdict.escalate) {
        Exit-Fail 2 'verdict is ESCALATE but escalate is null (must be paired -- design section 2)'
    }
} else {
    if ($null -ne $verdict.escalate) {
        Exit-Fail 2 "verdict is $($verdict.verdict) but escalate is non-null (must be null unless ESCALATE -- design section 2)"
    }
}

# =================================================================================================
# 5. Sort (blocker -> major -> minor -> nit, then file, then line) and cap (design section 3).
# =================================================================================================
$severityRank = @{ blocker = 0; major = 1; minor = 2; nit = 3 }
$allFindings = @($verdict.findings)
# BUILD-LANE FIX (2026-09-22): wrapped in @(...) -- Sort-Object collapses a single-element
# pipeline back to a bare scalar (the same PowerShell array-unwrapping gotcha $allFindings is
# already guarded against above), which made $sortedFindings.Count throw under StrictMode for any
# verdict with exactly one finding (e.g. tools/tests/fixtures/headless/review-verdict/post-verdict.json).
$sortedFindings = @($allFindings | Sort-Object -Property `
    @{ Expression = { $severityRank[$_.severity] } }, `
    @{ Expression = { $_.file } }, `
    @{ Expression = { if ($null -eq $_.line) { [int]::MaxValue } else { [int]$_.line } } })

# =================================================================================================
# 6. Live head check (design section 3, step 4). Skipped entirely under -DryRun -- never resolves
#    or invokes $GhPath in that mode.
# =================================================================================================
if ($DryRun) {
    Write-Host "DRYRUN GH: gh pr view $PullRequest -R $Repo --json headRefOid (skipped under -DryRun)"
} else {
    $__eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $viewOut = & $GhPath 'pr' 'view' "$PullRequest" '-R' $Repo '--json' 'headRefOid' 2>&1
    $ErrorActionPreference = $__eap
    $viewExit = $LASTEXITCODE
    if ($viewExit -ne 0) {
        Exit-Fail 3 "gh pr view $PullRequest -R $Repo --json headRefOid failed (exit $viewExit): $($viewOut -join ' ')"
    }
    try {
        $viewParsed = ($viewOut -join "`n") | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Exit-Fail 3 "gh pr view returned output that is not valid JSON: $($viewOut -join ' ')"
    }
    $liveHead = Get-Prop $viewParsed 'headRefOid'
    if (-not $liveHead -or $liveHead -ne $verdict.headSha) {
        Exit-Fail 3 "verdict headSha '$($verdict.headSha)' does not match the live head '$liveHead' for $Repo#$PullRequest -- nothing posted; a new push needs a new review"
    }
}

# =================================================================================================
# 7. Render the body (design section 3, "Comment body (fixed order, no headings...)" -- reproduced
#    verbatim in structure).
# =================================================================================================
$fullSha = [string]$verdict.headSha
$sha7 = if ($fullSha.Length -ge 7) { $fullSha.Substring(0, 7) } else { $fullSha }
$marker = "<!-- REVIEW-VERDICT v1 agent=$agentName head=$fullSha -->"

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add($marker)
# Design decision: the schema has no `model` field, so the header renders the agent name only --
# no diff-reviewer/live-reviewer -> sonnet/opus lookup or parenthetical (previously hardcoded here).
$lines.Add(('**REVIEW-VERDICT v1 {0} {1}** {2} {3} {2} head {4}{5}{4}' -f $emDash, $verdict.verdict, $midDot, $agentName, $bt, $sha7))
# BUILD-LANE FIX (2026-09-22, vs the drafts/f13 draft): the draft added `summary` to the body
# verbatim, with no Limit-Text call -- the design's parameter table and TC-F13-013/T9 both require
# `summary` to be truncated at 200 characters exactly like `ask` is at 120. Documented as a
# deviation in the PR body.
$lines.Add((Limit-Text ([string]$verdict.summary) 200))
$lines.Add('')

if ($sortedFindings.Count -eq 0) {
    $lines.Add('Findings: none')
} else {
    $shown = [Math]::Min($Cap, $sortedFindings.Count)
    $lines.Add(('Findings ({0} of {1} shown, worst first):' -f $shown, $sortedFindings.Count))
    for ($i = 0; $i -lt $shown; $i++) {
        $f = $sortedFindings[$i]
        $loc = if ($null -eq $f.line) { '{0}{1}{0}' -f $bt, $f.file } else { '{0}{1}:{2}{0}' -f $bt, $f.file, $f.line }
        $askText = [string]$f.ask
        if ($f.kind -eq 'secret') { $askText = Protect-SecretTokens $askText }
        $askText = Limit-Text $askText 120
        $lines.Add(('- **{0}** {1} {2} {3}' -f $f.severity, $loc, $emDash, $askText))
    }
    $hidden = $sortedFindings.Count - $shown
    if ($hidden -gt 0) {
        $lines.Add(('{0} more in the report: {1}{2}{1}' -f $hidden, $bt, $sourceForMoreLine))
    }
}
$lines.Add('')

$checks = @($verdict.checks)
$checksSummary = ($checks | ForEach-Object { '{0} {1}' -f $_.kind, $_.result }) -join (' ' + $midDot + ' ')
$lines.Add(('Checks: {0}' -f $checksSummary))
foreach ($c in $checks) {
    $lines.Add(('  searched: {0}' -f [string]$c.searched))
}

$couldNotCheck = @($verdict.couldNotCheck)
if ($couldNotCheck.Count -eq 0) {
    $lines.Add('Could not check: nothing')
} else {
    foreach ($cnc in $couldNotCheck) {
        $lines.Add(('Could not check: {0} {1} {2}' -f $cnc.subject, $emDash, $cnc.reason))
    }
}

$lines.Add(('Recommendation: {0}' -f [string]$verdict.recommendation))

if ($verdict.verdict -eq 'ESCALATE') {
    $lines.Add(('Escalate: {0} {1} {2}' -f $verdict.escalate.to, $emDash, $verdict.escalate.reason))
}

$lines.Add('')
$lines.Add(('_Review comment on head {0}{1}{0} only; a new push needs a new review. Not a MERGE-VERDICT and not a GitHub review; merge authority is unchanged (merge_authority.md)._' -f $bt, $sha7))

$body = $lines -join "`n"

if ($OutFile) {
    [System.IO.File]::WriteAllText($OutFile, $body, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Render-ReviewVerdict: body written to $OutFile"
} else {
    Write-Output $body
}

# =================================================================================================
# 8. Optional -Post: duplicate check -> post -> mandatory read-back (Incident 2). Never chained.
# =================================================================================================
if ($Post) {
    if ($DryRun) {
        Write-Host "DRYRUN GH: gh api repos/$Repo/issues/$PullRequest/comments --paginate (duplicate-marker check)"
        Write-Host "DRYRUN GH: gh pr comment $PullRequest -R $Repo --body-file <tmp> (the post)"
        Write-Host "DRYRUN GH: gh api repos/$Repo/issues/comments/<id> (mandatory read-back)"
    } else {
        # --- duplicate-marker check (design section 3, -Force bullet) ------------------------------
        $__eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $dupOut = & $GhPath 'api' "repos/$Repo/issues/$PullRequest/comments" '--paginate' 2>&1
        $ErrorActionPreference = $__eap
        $dupExit = $LASTEXITCODE
        if ($dupExit -ne 0) {
            Exit-Fail 4 "duplicate-marker check (gh api repos/$Repo/issues/$PullRequest/comments) failed (exit $dupExit): $($dupOut -join ' ')"
        }
        try {
            $dupList = ($dupOut -join "`n") | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Exit-Fail 4 "duplicate-marker check returned output that is not valid JSON: $($dupOut -join ' ')"
        }
        $dupFound = $false
        foreach ($c in @($dupList)) {
            $cBody = Get-Prop $c 'body'
            if ($cBody -and ([string]$cBody).Contains($marker)) { $dupFound = $true; break }
        }
        if ($dupFound -and -not $Force) {
            Exit-Fail 6 "a comment carrying marker '$marker' already exists on $Repo#$PullRequest; nothing posted (pass -Force to post anyway)"
        }

        # --- the post itself, body on disk first so a failed gh call still leaves it recoverable ---
        $tmpBodyPath = Join-Path ([System.IO.Path]::GetTempPath()) ('review-verdict-' + [Guid]::NewGuid().ToString('N') + '.md')
        [System.IO.File]::WriteAllText($tmpBodyPath, $body, [System.Text.UTF8Encoding]::new($false))

        $__eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $postOut = & $GhPath 'pr' 'comment' "$PullRequest" '-R' $Repo '--body-file' $tmpBodyPath 2>&1
        $ErrorActionPreference = $__eap
        $postExit = $LASTEXITCODE
        if ($postExit -ne 0) {
            Exit-Fail 4 "gh pr comment $PullRequest -R $Repo --body-file $tmpBodyPath failed (exit $postExit): $($postOut -join ' ') -- body left on disk at $tmpBodyPath"
        }

        $commentId = $null
        $postText = ($postOut -join "`n")
        $urlMatch = [regex]::Match($postText, 'issuecomment-(\d+)')
        if ($urlMatch.Success) { $commentId = $urlMatch.Groups[1].Value }
        if (-not $commentId) {
            # Design section 8, "Not checked": whether gh pr comment prints the comment URL on
            # stdout in the installed gh version. Fallback: re-list comments and match the marker.
            $__eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            $relistOut = & $GhPath 'api' "repos/$Repo/issues/$PullRequest/comments" '--paginate' 2>&1
            $ErrorActionPreference = $__eap
            if ($LASTEXITCODE -eq 0) {
                try {
                    $relistParsed = ($relistOut -join "`n") | ConvertFrom-Json -ErrorAction Stop
                    foreach ($c in @($relistParsed)) {
                        $cBody = Get-Prop $c 'body'
                        $cId = Get-Prop $c 'id'
                        if ($cBody -and $cId -and ([string]$cBody).Contains($marker)) { $commentId = [string]$cId }
                    }
                } catch { }
            }
        }
        if (-not $commentId) {
            Exit-Fail 4 "posted a comment on $Repo#$PullRequest but could not determine its id from gh pr comment's output or a re-list; body left on disk at $tmpBodyPath (Incident 2: never report a verdict as posted without a confirmed read-back)"
        }

        # --- mandatory read-back (Incident 2), its own separate gh call ---------------------------
        $__eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $readOut = & $GhPath 'api' "repos/$Repo/issues/comments/$commentId" 2>&1
        $ErrorActionPreference = $__eap
        $readExit = $LASTEXITCODE
        if ($readExit -ne 0) {
            Exit-Fail 4 "posted comment id=$commentId on $Repo#$PullRequest but the read-back (gh api repos/$Repo/issues/comments/$commentId) failed (exit $readExit): $($readOut -join ' ') -- body left on disk at $tmpBodyPath"
        }
        try {
            $readParsed = ($readOut -join "`n") | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Exit-Fail 4 "posted comment id=$commentId but the read-back did not return valid JSON -- body left on disk at $tmpBodyPath"
        }
        $readId = Get-Prop $readParsed 'id'
        if (-not $readId -or [string]$readId -ne [string]$commentId) {
            Exit-Fail 4 "posted comment id=$commentId but the read-back returned a mismatched or missing id ('$readId') -- body left on disk at $tmpBodyPath"
        }

        Remove-Item -LiteralPath $tmpBodyPath -ErrorAction SilentlyContinue
        # BUILD-LANE FIX (2026-09-22): Write-Output, not Write-Host -- this line is asserted on by
        # callers capturing the success stream (e.g. tools/tests/test-render-review-verdict.ps1
        # TC-F13-014), and Write-Host bypasses that stream entirely.
        Write-Output "Render-ReviewVerdict: posted and confirmed comment id=$commentId -- https://github.com/$Repo/pull/$PullRequest#issuecomment-$commentId"
    }
}

exit 0
