<#
.SYNOPSIS
  Regression tests for plan task F13's tools/headless/Render-ReviewVerdict.ps1 (the seat-side
  review-verdict renderer), TC-F13-004 through TC-F13-019 (design section 5B, T1-T15).

.DESCRIPTION
  Static only: no test here launches `claude` or spends budget, and no test makes a real `gh` or
  GitHub call -- every -Post / live-head-check case drives the script's -GhPath seam against
  tools/tests/fake-gh.ps1 (wrapped as fake-gh.cmd next to it, same pattern as
  tools/tests/fake-claude.cmd for -ClaudePath in test-invoke-subagent.ps1), logging every
  invocation's argv to a throwaway $env:FAKE_GH_LOG file so a test can assert both WHICH `gh` calls
  happened and their ORDER.

  Fixtures live under tools/tests/fixtures/headless/review-verdict/. Naming deviates from
  TEST_CASES_f13.md's proposed table in two ways, both noted in the PR body:
    - The DryRun/rendering-only cases (T1, T2, T4, T5, T6, T8, T9, T13, T14, T15) reuse
      test-verdict.json (repo yodatech1988/MasterThread, pullRequest 209, headSha
      a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0, 6 findings unsorted) and golden-body.txt, per the
      task's explicit instruction to build those two fixtures from the drafts folder, rather than
      the test-case doc's proposed verdict-valid.json (PR 1, 7 findings). The rendering behaviour
      exercised is identical either way; only the sample numbers differ.
    - The gh-dependent cases (T7, T10, T11, T12) use a second, minimal fixture
      (post-verdict.json, repo yodatech1988/MasterThread, pullRequest 1, headSha
      aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa) so its headSha matches fake-gh.ps1's documented
      $GOOD_HEAD/$STALE_HEAD constants exactly, since test-verdict.json's headSha does not.

  BUILD-LANE FIX (documented again here, and in Render-ReviewVerdict.ps1 itself): the drafts/f13
  draft of the renderer never truncated `summary` at 200 characters (only `ask` at 120), so
  golden-body.txt was regenerated from drafts/f13/test-dryrun-body.md with the summary line
  truncated to match the design's own rule (section 3 parameter table) and TC-F13-013/T9.
#>
param()

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $here)
$scriptPath = Join-Path $repoRoot 'tools\headless\Render-ReviewVerdict.ps1'
$fxDir = Join-Path $here 'fixtures\headless\review-verdict'
$realSchemasDir = Join-Path $repoRoot 'tools\headless\schemas'
$fakeGhSource = Join-Path $here 'fake-gh.ps1'

$testsPassed = 0
$testsFailed = 0

function Test-Case($caseName, $caseBlock) {
    try {
        & $caseBlock
        Write-Host "[PASS] $caseName" -ForegroundColor Green
        $script:testsPassed++
    } catch {
        Write-Host "[FAIL] $caseName`: $($_.Exception.Message)" -ForegroundColor Red
        $script:testsFailed++
    }
}

function Invoke-Renderer {
    # NOTE: deliberately a HASHTABLE splat, not an array splat -- array splatting (@arrayVar)
    # binds each element POSITIONALLY, so a literal "-Repo" element would land in whatever
    # positional slot it happened to reach rather than being recognized as the -Repo flag
    # (confirmed empirically while building this suite: `Test-Foo @("-A","x","-B","5")` tries to
    # bind "x" to -B). Hashtable splatting (@hashVar) is the one PowerShell form that maps keys to
    # named parameters, including switches (value $true) -- so every caller below passes a
    # hashtable, not a positional array.
    param([hashtable]$Params)
    $out = & $scriptPath @Params 2>&1 | Out-String -Width 8192
    return @{ Out = $out; ExitCode = $LASTEXITCODE }
}

Write-Host ""
Write-Host "== F13 regression tests: tools/headless/Render-ReviewVerdict.ps1 (review-verdict renderer)" -ForegroundColor Cyan
Write-Host ""

Test-Case "Render-ReviewVerdict.ps1 exists" {
    if (-not (Test-Path -LiteralPath $scriptPath)) { throw "File not found at $scriptPath" }
}

# --- one-line fake-gh.cmd wrapper, generated fresh per run into a throwaway dir (its own header
#     note; tools/tests/fake-gh.cmd is the repo's static copy, used here as the source payload) ---
$fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("f13-render-review-verdict-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null
Copy-Item -LiteralPath $fakeGhSource -Destination (Join-Path $fakeDir 'fake-gh.ps1') -Force
$fakeGhCmd = Join-Path $fakeDir 'fake-gh.cmd'
[System.IO.File]::WriteAllText($fakeGhCmd, "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0fake-gh.ps1`" %*`r`n", [System.Text.Encoding]::ASCII)

function New-FakeGhLog {
    $log = Join-Path $fakeDir ("log-" + [Guid]::NewGuid().ToString('N') + '.txt')
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    return $log
}

function Get-LogLines([string]$LogPath) {
    # BUILD-LANE FIX (2026-09-22): `return @(array-with-one-item)` still unwraps to a bare scalar
    # once it crosses the function's output pipeline and is captured by `$x = Get-LogLines ...` --
    # PowerShell re-collapses a single-object pipeline output back to that one object. For a log
    # with exactly one gh call, the caller then got the LINE STRING itself instead of a 1-element
    # array, so `$lines[0]` indexed into the string's first CHARACTER ('p' of "pr view ..."), not
    # the line. The unary comma operator (`,`) prevents this final unwrap by making the function
    # emit the array itself as a single pipeline object (confirmed via a minimal repro: a function
    # returning `@($one)` still hands the caller a bare string when only one line is present).
    if (-not (Test-Path -LiteralPath $LogPath)) { return , @() }
    $text = [System.IO.File]::ReadAllText($LogPath)
    if ([string]::IsNullOrEmpty($text)) { return , @() }
    return , @($text -split "`r?`n" | Where-Object { $_ -ne '' })
}

# golden-body.txt's "N more in the report: `<source-path>`" trailer names whatever -VerdictPath /
# -ReportPath was actually given, so it is necessarily different between TC-F13-004 (an absolute
# -VerdictPath under this run's fixtures dir) and TC-F13-005 (a throwaway -ReportPath under a
# per-run temp dir) -- the design's "byte-for-byte identical to golden-body.txt (same as
# TC-F13-004)" claim for T2 cannot literally hold for that one line without both tests passing an
# identical file path, which would defeat the point of exercising two different source files.
# Deviation (documented in the PR body): both this helper and golden-body.txt itself normalize
# that one line to a fixed placeholder before comparing, so the assertion is "every line is
# byte-identical except the one line that names the source file, which the design's own template
# requires to differ by source" rather than a literal whole-file byte compare.
function Get-NormalizedBody([string]$Text) {
    return ($Text -replace '1 more in the report: `[^`]*`', '1 more in the report: `<source-path>`')
}

$testVerdictPath = Join-Path $fxDir 'test-verdict.json'
$postVerdictPath = Join-Path $fxDir 'post-verdict.json'
$goldenPath = Join-Path $fxDir 'golden-body.txt'

# =================================================================================================
# TC-F13-004 (T1): valid verdict via -VerdictPath, -DryRun -> golden body byte-for-byte
# =================================================================================================
Test-Case "TC-F13-004 (T1): -VerdictPath -DryRun renders the exact golden body; no gh call" {
    $log = New-FakeGhLog
    $prior = $env:FAKE_GH_LOG
    $env:FAKE_GH_LOG = $log
    try {
        $r = Invoke-Renderer @{
            VerdictPath = $testVerdictPath; Repo = 'yodatech1988/MasterThread'; PullRequest = 209
            SchemasDir = $realSchemasDir; GhPath = $fakeGhCmd; DryRun = $true
        }
        if ($r.ExitCode -ne 0) { throw "expected exit 0, got $($r.ExitCode). Output: $($r.Out)" }
        $golden = [System.IO.File]::ReadAllText($goldenPath)
        # The renderer prints the body via Write-Output, which appends its own line ending; strip a
        # single trailing newline from each side before the byte-for-byte compare so this asserts
        # body equality, not an incidental extra blank line from the two different write paths.
        $rendered = Get-NormalizedBody ($r.Out -replace '(\r\n|\r|\n)+$', '')
        $goldenTrim = Get-NormalizedBody ($golden -replace '(\r\n|\r|\n)+$', '')
        if ($rendered -ne $goldenTrim) { throw "body did not match golden-body.txt.`n--- rendered ---`n$rendered`n--- golden ---`n$goldenTrim" }
        if ((Get-LogLines $log).Count -ne 0) { throw "expected no gh calls under -DryRun, log had: $((Get-LogLines $log) -join ' | ')" }
    } finally {
        $env:FAKE_GH_LOG = $prior
    }
}

# =================================================================================================
# TC-F13-005 (T2): same verdict wrapped as an F3 report, -ReportPath -> identical body
# =================================================================================================
Test-Case "TC-F13-005 (T2): -ReportPath (envelope.structured_output) renders the identical golden body" {
    # Build a throwaway report wrapping test-verdict.json, envelope.result deliberately NOT that JSON.
    $verdict = Get-Content -LiteralPath $testVerdictPath -Raw | ConvertFrom-Json
    $report = [ordered]@{
        envelope = [ordered]@{
            type = 'result'; subtype = 'success'; is_error = $false
            result = 'prose text, deliberately not the schema JSON -- proves envelope.result is never read'
            structured_output = $verdict
        }
        checkedAt = '2026-09-22T18:00:00Z'
        command = 'claude -p --append-system-prompt-file <agent-body> --json-schema tools/headless/schemas/diff-reviewer.json ...'
    }
    $reportPath = Join-Path $fakeDir ('report-valid-' + [Guid]::NewGuid().ToString('N') + '.json')
    ($report | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $reportPath -Encoding utf8

    $r = Invoke-Renderer @{
        ReportPath = $reportPath; Repo = 'yodatech1988/MasterThread'; PullRequest = 209
        SchemasDir = $realSchemasDir; DryRun = $true
    }
    if ($r.ExitCode -ne 0) { throw "expected exit 0, got $($r.ExitCode). Output: $($r.Out)" }
    $golden = Get-NormalizedBody ([System.IO.File]::ReadAllText($goldenPath) -replace '(\r\n|\r|\n)+$', '')
    $rendered = Get-NormalizedBody ($r.Out -replace '(\r\n|\r|\n)+$', '')
    if ($rendered -ne $golden) { throw "body did not match golden-body.txt via -ReportPath.`n--- rendered ---`n$rendered" }
}

# =================================================================================================
# TC-F13-006 (T3): report with prose result, no structured_output -> exit 8
# =================================================================================================
Test-Case "TC-F13-006 (T3): report with prose result and no structured_output fails closed at exit 8" {
    $log = New-FakeGhLog
    $prior = $env:FAKE_GH_LOG
    $env:FAKE_GH_LOG = $log
    try {
        $r = Invoke-Renderer @{
            ReportPath = (Join-Path $fxDir 'report-no-structured-output.json'); Repo = 'yodatech1988/MasterThread'
            PullRequest = 209; SchemasDir = $realSchemasDir; DryRun = $true
        }
        if ($r.ExitCode -ne 8) { throw "expected exit 8, got $($r.ExitCode). Output: $($r.Out)" }
        if ($r.Out -match 'REVIEW-VERDICT v1 agent=') { throw "a comment body must not have been rendered: $($r.Out)" }
        if ((Get-LogLines $log).Count -ne 0) { throw 'expected no gh calls' }
    } finally {
        $env:FAKE_GH_LOG = $prior
    }
}

# =================================================================================================
# TC-F13-007 (T4): invalid severity enum -> exit 2, path named
# =================================================================================================
Test-Case "TC-F13-007 (T4): invalid severity enum value is rejected with the offending path named" {
    $r = Invoke-Renderer @{
        VerdictPath = (Join-Path $fxDir 'verdict-severity-critical.json'); Repo = 'yodatech1988/MasterThread'
        PullRequest = 209; SchemasDir = $realSchemasDir; DryRun = $true
    }
    if ($r.ExitCode -ne 2) { throw "expected exit 2, got $($r.ExitCode). Output: $($r.Out)" }
    if ($r.Out -notmatch 'findings\[0\]\.severity') { throw "expected the offending path 'findings[0].severity' named in the output: $($r.Out)" }
}

# =================================================================================================
# TC-F13-008 (T5 forward): ESCALATE + escalate:null -> exit 2
# =================================================================================================
Test-Case "TC-F13-008 (T5 forward): verdict ESCALATE with escalate:null is rejected" {
    $r = Invoke-Renderer @{
        VerdictPath = (Join-Path $fxDir 'verdict-escalate-mismatch-null.json'); Repo = 'yodatech1988/MasterThread'
        PullRequest = 209; SchemasDir = $realSchemasDir; DryRun = $true
    }
    if ($r.ExitCode -ne 2) { throw "expected exit 2, got $($r.ExitCode). Output: $($r.Out)" }
    if ($r.Out -notmatch 'escalate') { throw "expected a message naming the escalate/verdict pairing rule: $($r.Out)" }
}

# =================================================================================================
# TC-F13-009 (T5 inverse): non-ESCALATE + non-null escalate -> exit 2
# =================================================================================================
Test-Case "TC-F13-009 (T5 inverse): non-ESCALATE verdict with non-null escalate is rejected" {
    $r = Invoke-Renderer @{
        VerdictPath = (Join-Path $fxDir 'verdict-escalate-mismatch-object.json'); Repo = 'yodatech1988/MasterThread'
        PullRequest = 209; SchemasDir = $realSchemasDir; DryRun = $true
    }
    if ($r.ExitCode -ne 2) { throw "expected exit 2, got $($r.ExitCode). Output: $($r.Out)" }
    if ($r.Out -notmatch 'escalate') { throw "expected a message naming the escalate/verdict pairing rule: $($r.Out)" }
}

# =================================================================================================
# TC-F13-010 (T6): repo/pullRequest mismatch -> exit 2
# =================================================================================================
Test-Case "TC-F13-010 (T6): a pullRequest mismatch between the verdict and the parameters is rejected" {
    $r = Invoke-Renderer @{
        VerdictPath = $testVerdictPath; Repo = 'yodatech1988/MasterThread'; PullRequest = 999
        SchemasDir = $realSchemasDir; DryRun = $true
    }
    if ($r.ExitCode -ne 2) { throw "expected exit 2, got $($r.ExitCode). Output: $($r.Out)" }
    if ($r.Out -notmatch 'pullRequest') { throw "expected a message naming the pullRequest mismatch: $($r.Out)" }
}

# =================================================================================================
# TC-F13-011 (T7): stale head aborts before posting
# =================================================================================================
Test-Case "TC-F13-011 (T7): a stale live head aborts at exit 3 before any post; log shows only pr view" {
    $log = New-FakeGhLog
    $prior = $env:FAKE_GH_LOG
    $priorMode = $env:FAKE_GH_MODE
    $env:FAKE_GH_LOG = $log
    $env:FAKE_GH_MODE = 'stale-head'
    try {
        $r = Invoke-Renderer @{
            VerdictPath = $postVerdictPath; Repo = 'yodatech1988/MasterThread'; PullRequest = 1
            SchemasDir = $realSchemasDir; GhPath = $fakeGhCmd
        }
        if ($r.ExitCode -ne 3) { throw "expected exit 3, got $($r.ExitCode). Output: $($r.Out)" }
        $lines = Get-LogLines $log
        if ($lines.Count -ne 1) { throw "expected exactly one gh call, got: $($lines -join ' | ')" }
        if ($lines[0] -notmatch '^pr view 1 -R yodatech1988/MasterThread --json headRefOid$') { throw "unexpected log line: $($lines[0])" }
        if ($lines -match 'pr comment') { throw 'no pr comment call should have happened' }
    } finally {
        $env:FAKE_GH_LOG = $prior
        $env:FAKE_GH_MODE = $priorMode
    }
}

# =================================================================================================
# TC-F13-012 (T8): findings in mixed severities -> capped at 5, worst first
# =================================================================================================
Test-Case "TC-F13-012 (T8): mixed-severity findings render capped at 5, worst first, with a trailer line" {
    $r = Invoke-Renderer @{
        VerdictPath = $testVerdictPath; Repo = 'yodatech1988/MasterThread'; PullRequest = 209
        SchemasDir = $realSchemasDir; DryRun = $true
    }
    if ($r.ExitCode -ne 0) { throw "expected exit 0, got $($r.ExitCode). Output: $($r.Out)" }
    if ($r.Out -notmatch 'Findings \(5 of 6 shown, worst first\):') { throw "expected the '5 of 6 shown' header line: $($r.Out)" }
    if ($r.Out -notmatch '1 more in the report:') { throw "expected the '1 more in the report' trailer line: $($r.Out)" }
    $findingLines = @(($r.Out -split "`n") | Where-Object { $_ -match '^- \*\*(blocker|major|minor|nit)\*\*' })
    if ($findingLines.Count -ne 5) { throw "expected 5 finding lines, got $($findingLines.Count)" }
    if ($findingLines[0] -notmatch '^\- \*\*blocker\*\*') { throw "expected the blocker finding first: $($findingLines[0])" }
}

# =================================================================================================
# TC-F13-013 (T9): oversized summary and ask are truncated, never refused
# =================================================================================================
Test-Case "TC-F13-013 (T9): an oversized summary and ask are truncated with a visible tag, exit 0" {
    $r = Invoke-Renderer @{
        VerdictPath = (Join-Path $fxDir 'verdict-truncation.json'); Repo = 'yodatech1988/MasterThread'
        PullRequest = 209; SchemasDir = $realSchemasDir; DryRun = $true
    }
    if ($r.ExitCode -ne 0) { throw "expected exit 0, got $($r.ExitCode). Output: $($r.Out)" }
    $v = Get-Content -LiteralPath (Join-Path $fxDir 'verdict-truncation.json') -Raw | ConvertFrom-Json
    $expectedSummary = $v.summary.Substring(0, 200) + [string][char]0x2026 + ' (truncated)'
    if ($r.Out -notmatch [regex]::Escape($expectedSummary)) { throw "summary was not truncated at 200 chars as expected. Output: $($r.Out)" }
    $expectedAsk = $v.findings[0].ask.Substring(0, 120) + [string][char]0x2026 + ' (truncated)'
    if ($r.Out -notmatch [regex]::Escape($expectedAsk)) { throw "ask was not truncated at 120 chars as expected. Output: $($r.Out)" }
}

# =================================================================================================
# TC-F13-014 (T10): -Post happy path -- exactly four gh calls, in order
# =================================================================================================
Test-Case "TC-F13-014 (T10): -Post happy path issues exactly the four documented gh calls, in order" {
    $log = New-FakeGhLog
    $prior = $env:FAKE_GH_LOG
    $priorMode = $env:FAKE_GH_MODE
    $env:FAKE_GH_LOG = $log
    $env:FAKE_GH_MODE = 'ok'
    try {
        $r = Invoke-Renderer @{
            VerdictPath = $postVerdictPath; Repo = 'yodatech1988/MasterThread'; PullRequest = 1
            SchemasDir = $realSchemasDir; GhPath = $fakeGhCmd; Post = $true
        }
        if ($r.ExitCode -ne 0) { throw "expected exit 0, got $($r.ExitCode). Output: $($r.Out)" }
        $lines = Get-LogLines $log
        if ($lines.Count -ne 4) { throw "expected exactly 4 gh calls, got $($lines.Count): $($lines -join ' | ')" }
        if ($lines[0] -notmatch '^pr view 1 -R yodatech1988/MasterThread --json headRefOid$') { throw "call 1 unexpected: $($lines[0])" }
        if ($lines[1] -notmatch '^api repos/yodatech1988/MasterThread/issues/1/comments --paginate$') { throw "call 2 unexpected: $($lines[1])" }
        if ($lines[2] -notmatch '^pr comment 1 -R yodatech1988/MasterThread --body-file ') { throw "call 3 unexpected: $($lines[2])" }
        if ($lines[3] -notmatch '^api repos/yodatech1988/MasterThread/issues/comments/\d+$') { throw "call 4 unexpected: $($lines[3])" }
        if ($lines -match '^pr review' -or $lines -match '^pr merge') { throw "pr review/pr merge must never be called: $($lines -join ' | ')" }
        if ($r.Out -notmatch 'posted and confirmed comment id=') { throw "expected the posted comment id/url to be printed: $($r.Out)" }
    } finally {
        $env:FAKE_GH_LOG = $prior
        $env:FAKE_GH_MODE = $priorMode
    }
}

# =================================================================================================
# TC-F13-015 (T11): read-back 404 -> exit 4, body left on disk
# =================================================================================================
Test-Case "TC-F13-015 (T11): a read-back 404 after posting leaves the body on disk and fails at exit 4" {
    $log = New-FakeGhLog
    $prior = $env:FAKE_GH_LOG
    $priorMode = $env:FAKE_GH_MODE
    $env:FAKE_GH_LOG = $log
    $env:FAKE_GH_MODE = 'readback-404'
    try {
        $r = Invoke-Renderer @{
            VerdictPath = $postVerdictPath; Repo = 'yodatech1988/MasterThread'; PullRequest = 1
            SchemasDir = $realSchemasDir; GhPath = $fakeGhCmd; Post = $true
        }
        if ($r.ExitCode -ne 4) { throw "expected exit 4, got $($r.ExitCode). Output: $($r.Out)" }
        $lines = Get-LogLines $log
        if ($lines.Count -lt 3) { throw "expected at least pr view, duplicate-check, pr comment before the failing read-back: $($lines -join ' | ')" }
        if ($lines[0] -notmatch '^pr view ') { throw "call 1 should be pr view: $($lines[0])" }
        $bodyFileMatch = [regex]::Match(($lines -join "`n"), '--body-file (\S+)')
        if (-not $bodyFileMatch.Success) { throw "could not find the --body-file path in the log: $($lines -join ' | ')" }
        $bodyFile = $bodyFileMatch.Groups[1].Value
        if (-not (Test-Path -LiteralPath $bodyFile)) { throw "expected the posted body to still be on disk at $bodyFile" }
        $content = Get-Content -LiteralPath $bodyFile -Raw
        if ($content -notmatch '^<!-- REVIEW-VERDICT v1 agent=diff-reviewer head=') { throw "body file content did not look like a rendered comment: $content" }
    } finally {
        $env:FAKE_GH_LOG = $prior
        $env:FAKE_GH_MODE = $priorMode
    }
}

# =================================================================================================
# TC-F13-016 (T12): duplicate on same head -> exit 6; -Force overrides
# =================================================================================================
Test-Case "TC-F13-016 (T12): a duplicate marker+head comment is refused; -Force overrides it" {
    $log = New-FakeGhLog
    $prior = $env:FAKE_GH_LOG
    $priorMode = $env:FAKE_GH_MODE
    $env:FAKE_GH_LOG = $log
    $env:FAKE_GH_MODE = 'duplicate'
    try {
        $r1 = Invoke-Renderer @{
            VerdictPath = $postVerdictPath; Repo = 'yodatech1988/MasterThread'; PullRequest = 1
            SchemasDir = $realSchemasDir; GhPath = $fakeGhCmd; Post = $true
        }
        if ($r1.ExitCode -ne 6) { throw "expected exit 6 without -Force, got $($r1.ExitCode). Output: $($r1.Out)" }
        $lines1 = Get-LogLines $log
        if ($lines1 -match '^pr comment') { throw "no pr comment call should have happened without -Force: $($lines1 -join ' | ')" }
        if ($lines1.Count -lt 2) { throw "expected at least the head check and the duplicate check: $($lines1 -join ' | ')" }

        $log2 = New-FakeGhLog
        $env:FAKE_GH_LOG = $log2
        $r2 = Invoke-Renderer @{
            VerdictPath = $postVerdictPath; Repo = 'yodatech1988/MasterThread'; PullRequest = 1
            SchemasDir = $realSchemasDir; GhPath = $fakeGhCmd; Post = $true; Force = $true
        }
        if ($r2.ExitCode -ne 0) { throw "expected exit 0 with -Force, got $($r2.ExitCode). Output: $($r2.Out)" }
        $lines2 = Get-LogLines $log2
        if (-not ($lines2 -match '^pr comment')) { throw "-Force should have caused a pr comment call: $($lines2 -join ' | ')" }
    } finally {
        $env:FAKE_GH_LOG = $prior
        $env:FAKE_GH_MODE = $priorMode
    }
}

# =================================================================================================
# TC-F13-017 (T13): first line of the body is the marker with the full SHA
# =================================================================================================
Test-Case "TC-F13-017 (T13): the rendered body's first line is the marker, carrying the full head SHA" {
    $r = Invoke-Renderer @{
        VerdictPath = $testVerdictPath; Repo = 'yodatech1988/MasterThread'; PullRequest = 209
        SchemasDir = $realSchemasDir; DryRun = $true
    }
    if ($r.ExitCode -ne 0) { throw "expected exit 0, got $($r.ExitCode). Output: $($r.Out)" }
    $firstLine = (($r.Out -split "`r?`n") | Where-Object { $_ -ne '' } | Select-Object -First 1)
    $expected = '<!-- REVIEW-VERDICT v1 agent=diff-reviewer head=a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0 -->'
    if ($firstLine -ne $expected) { throw "expected first line '$expected', got '$firstLine'" }
}

# =================================================================================================
# TC-F13-018 (T14): both -ReportPath and -VerdictPath, or neither -> exit 2, no I/O
# =================================================================================================
Test-Case "TC-F13-018 (T14): both -ReportPath and -VerdictPath, or neither, fails closed with no observable I/O" {
    $log = New-FakeGhLog
    $prior = $env:FAKE_GH_LOG
    $env:FAKE_GH_LOG = $log
    $outFile = Join-Path $fakeDir ('outfile-' + [Guid]::NewGuid().ToString('N') + '.md')
    try {
        $r1 = Invoke-Renderer @{
            VerdictPath = $testVerdictPath
            ReportPath = (Join-Path $fxDir 'report-no-structured-output.json')
            Repo = 'yodatech1988/MasterThread'; PullRequest = 209
            SchemasDir = $realSchemasDir; GhPath = $fakeGhCmd; OutFile = $outFile
        }
        if ($r1.ExitCode -ne 2) { throw "expected exit 2 with both given, got $($r1.ExitCode). Output: $($r1.Out)" }
        if ((Get-LogLines $log).Count -ne 0) { throw 'expected no gh calls when both were given' }
        if (Test-Path -LiteralPath $outFile) { throw 'expected -OutFile to never be created when both were given' }

        $r2 = Invoke-Renderer @{
            Repo = 'yodatech1988/MasterThread'; PullRequest = 209
            SchemasDir = $realSchemasDir; GhPath = $fakeGhCmd; OutFile = $outFile
        }
        if ($r2.ExitCode -ne 2) { throw "expected exit 2 with neither given, got $($r2.ExitCode). Output: $($r2.Out)" }
        if ((Get-LogLines $log).Count -ne 0) { throw 'expected no gh calls when neither was given' }
        if (Test-Path -LiteralPath $outFile) { throw 'expected -OutFile to never be created when neither was given' }
    } finally {
        $env:FAKE_GH_LOG = $prior
    }
}

# =================================================================================================
# TC-F13-019 (T15): a secret-kind finding never prints the raw token
# =================================================================================================
Test-Case "TC-F13-019 (T15): a secret-kind finding masks known token markers and never prints the raw token" {
    $r = Invoke-Renderer @{
        VerdictPath = (Join-Path $fxDir 'verdict-secret-finding.json'); Repo = 'yodatech1988/MasterThread'
        PullRequest = 209; SchemasDir = $realSchemasDir; DryRun = $true
    }
    if ($r.ExitCode -ne 0) { throw "expected exit 0, got $($r.ExitCode). Output: $($r.Out)" }
    if ($r.Out -match 'ghp_1234567890abcdefghijklmnopqrstuvwxyz') { throw "raw token leaked into the rendered body: $($r.Out)" }
    if ($r.Out -notmatch '\[REDACTED\]') { throw "expected a [REDACTED] marker in place of the token: $($r.Out)" }
    if ($r.Out -notmatch 'tools/x\.ps1:12') { throw "expected the finding's file:line to still be visible: $($r.Out)" }
}

Write-Host ""
Write-Host "== F13 test-render-review-verdict.ps1 summary: $testsPassed passed, $testsFailed failed ==" -ForegroundColor Cyan
Write-Host ""

if ($testsFailed -gt 0) { exit 1 }
exit 0
