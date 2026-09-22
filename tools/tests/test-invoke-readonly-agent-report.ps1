<#
.SYNOPSIS
  Regression tests for plan task F3: L1 report mode (-Report / -ReportDir) on
  tools/headless/Invoke-ReadOnlyAgent.ps1.

.DESCRIPTION
  Follows tools/README.md's testing-seam conventions. The static suite drives the REAL call site
  (the wrapper script itself, not a helper in isolation) with -ClaudePath pointed at a throwaway
  fake CLI (.cmd) that prints a fixture envelope, and -ReportDir pointed at a throwaway folder --
  never %APPDATA%\AEGIS\reports. The one default-folder test repoints $env:APPDATA at a temp dir
  for this process first (services PR #104 precedent) and restores it afterwards.

  The fixture tools/tests/fixtures/headless/envelope-with-denial.json is a real, unedited
  `claude --print --model haiku --tools Bash --permission-mode dontAsk --output-format json` stdout
  captured 2026-09-21 (CLI 2.1.278), with one live permission_denials entry (git --version denied
  under dontAsk, the same failure headless_agent_permissions.md documents).

  What these tests prove (the F3 build brief's four required checks):
    (a) the report's envelope is byte-identical to the CLI's stdout (trailing newline trimmed);
    (b) checkedAt is the wrapper's clock at write time, differs run to run, and appears nowhere
        inside the envelope;
    (c) a populated permission_denials array arrives in the report unmodified;
    (d) empty / malformed / non-envelope CLI output fails loudly (exit 6) and writes NO file.

.PARAMETER RunLive
  Also run two live checks against the real `claude` CLI through the wrapper (Haiku, small real
  cost; Sonnet is deliberately not used). Off by default so the static suite runs anywhere.
#>
param(
    [switch]$RunLive
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path (Split-Path -Parent $here) 'headless\Invoke-ReadOnlyAgent.ps1'
$fixtureEnvelopePath = Join-Path $here 'fixtures\headless\envelope-with-denial.json'
$utf8 = [System.Text.UTF8Encoding]::new($false)

$testsPassed = 0
$testsFailed = 0

function Test-Case($name, $scriptBlock) {
    try {
        & $scriptBlock
        Write-Host "[PASS] $name" -ForegroundColor Green
        $script:testsPassed++
    } catch {
        Write-Host "[FAIL] $name`: $($_.Exception.Message)" -ForegroundColor Red
        $script:testsFailed++
    }
}

Write-Host ""
Write-Host "== F3 regression tests: -Report on Invoke-ReadOnlyAgent.ps1" -ForegroundColor Cyan
Write-Host ""

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("f3-report-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null

# A fake CLI: prints the given stdout bytes verbatim and exits with the given code. Every test gets
# its own folder so no fixture leaks between cases.
function New-FakeClaude([string]$Name, [string]$Stdout, [int]$ExitCode = 0) {
    $dir = Join-Path $root $Name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $dir 'out.txt'), $Stdout, $utf8)
    $cmd = Join-Path $dir 'fake-claude.cmd'
    $body = "@echo off`r`nif exist `"%~dp0out.txt`" type `"%~dp0out.txt`"`r`nexit /b $ExitCode`r`n"
    [System.IO.File]::WriteAllText($cmd, $body, [System.Text.Encoding]::ASCII)
    return $cmd
}

function New-ReportDir([string]$Name) {
    return (Join-Path $root "reports-$Name")   # deliberately NOT created: the wrapper must create it
}

function Get-Reports([string]$Dir) {
    if (-not (Test-Path $Dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $Dir -Force -File)
}

# Split a report file into its envelope text and the parsed wrapper fields, without re-serialising
# the envelope (the whole point is that nothing re-serialised it on the way in either).
function Read-Report([string]$Path) {
    $text = [System.IO.File]::ReadAllText($Path, $utf8)
    $prefix = '{"envelope":'
    if (-not $text.StartsWith($prefix)) { throw "report does not start with $prefix : $text" }
    $idx = $text.LastIndexOf(',"checkedAt":')
    if ($idx -lt 0) { throw "report has no checkedAt key: $text" }
    $parsed = $text | ConvertFrom-Json
    $keys = @($parsed.PSObject.Properties | ForEach-Object { $_.Name })
    return [pscustomobject]@{
        Text     = $text
        Envelope = $text.Substring($prefix.Length, $idx - $prefix.Length)
        Parsed   = $parsed
        Keys     = $keys
    }
}

$fixtureRaw = [System.IO.File]::ReadAllText($fixtureEnvelopePath, $utf8)
$fixtureTrimmed = $fixtureRaw.Trim()
$fixtureObj = $fixtureTrimmed | ConvertFrom-Json

# Common args: explicit -Restricted skips the roster lookup, so these tests never depend on the
# real claude-agents/roster_meta.json.
$common = @{ AgentName = 'fixture-reporter'; Prompt = 'irrelevant'; Restricted = $true }

try {
    Test-Case "fixture is a real envelope with one permission_denials entry" {
        if ($fixtureObj.type -ne 'result') { throw "fixture type is '$($fixtureObj.type)'" }
        if (@($fixtureObj.permission_denials).Count -ne 1) { throw "expected 1 denial in fixture" }
    }

    Test-Case "DryRun without -Report: unchanged stream-json --verbose shape, nothing about reports" {
        $out = & $scriptPath @common -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch '--output-format stream-json --verbose') { throw "expected pre-F3 stream-json --verbose. Output: $out" }
        if ($out -match 'DRYRUN REPORT') { throw "report mode must be off by default. Output: $out" }
    }

    Test-Case "multi-word prompt containing '--version' is passed as ONE quoted token (was split; live-found)" {
        $out = & $scriptPath -AgentName 'fixture-reporter' -Prompt 'run git --version now' -Restricted -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        $argsLine = ($out -split "`n") | Where-Object { $_ -match '^DRYRUN ARGS:' }
        if (-not $argsLine.TrimEnd().EndsWith('"run git --version now"')) { throw "prompt not passed as one quoted trailing token. Args: $argsLine" }
    }

    Test-Case "powershell.exe -File invocation (how a scheduled task calls it) resolves its default paths (was a param-binding crash)" {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -AgentName 'fixture-reporter' -Prompt 'irrelevant' -Restricted -DryRun 2>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch 'readonly\.settings\.json') { throw "expected the default --settings path in the args. Output: $out" }
    }

    Test-Case "DryRun with -ReportDir: --output-format json, no --verbose, no stream-json, nothing written" {
        $rd = New-ReportDir 'dryrun'
        $out = & $scriptPath @common -ReportDir $rd -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        $argsLine = ($out -split "`n") | Where-Object { $_ -match '^DRYRUN ARGS:' }
        if ($argsLine -notmatch '--output-format json') { throw "expected --output-format json. Output: $out" }
        if ($argsLine -match 'stream-json' -or $argsLine -match '--verbose') { throw "report mode must not use stream-json/--verbose. Output: $out" }
        if ($out -notmatch 'DRYRUN REPORT') { throw "expected DRYRUN REPORT line. Output: $out" }
        if (Test-Path $rd) { throw "DryRun must not create the report folder" }
    }

    Test-Case "(a)(b)(c) valid envelope: exactly {envelope, checkedAt, command}; envelope byte-identical; denials unmodified" {
        $fake = New-FakeClaude 'valid' $fixtureRaw 0
        $rd = New-ReportDir 'valid'
        $before = [DateTime]::UtcNow.AddSeconds(-1)
        $out = & $scriptPath @common -ReportDir $rd -ClaudePath $fake *>&1 | Out-String -Width 8192
        $after = [DateTime]::UtcNow.AddSeconds(1)
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        $files = Get-Reports $rd
        if ($files.Count -ne 1) { throw "expected exactly 1 file in report dir, got $($files.Count): $($files.Name -join ', ')" }
        if ($files[0].Name -notmatch '^fixture-reporter\.\d{8}-\d{6}\.json$') { throw "unexpected file name $($files[0].Name)" }
        if ($out -notmatch [regex]::Escape("report written to $($files[0].FullName)")) { throw "wrapper did not print the report path. Output: $out" }
        $r = Read-Report $files[0].FullName
        if (($r.Keys -join ',') -ne 'envelope,checkedAt,command') { throw "expected keys envelope,checkedAt,command in that order; got $($r.Keys -join ',')" }
        # (a) byte-identical: the exact bytes the CLI printed, trailing newline trimmed.
        if ($r.Envelope -cne $fixtureTrimmed) { throw "envelope is not byte-identical to the CLI stdout" }
        # (b) clock at write time, ISO-8601 UTC, not present anywhere in the envelope.
        if ($r.Parsed.checkedAt -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') { throw "checkedAt '$($r.Parsed.checkedAt)' is not yyyy-MM-ddTHH:mm:ssZ" }
        $ts = [DateTime]::ParseExact($r.Parsed.checkedAt, "yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]'AssumeUniversal,AdjustToUniversal')
        if ($ts -lt $before -or $ts -gt $after) { throw "checkedAt $ts is outside the run window $before .. $after" }
        if ($r.Envelope.Contains($r.Parsed.checkedAt)) { throw "checkedAt value appears inside the envelope" }
        # (c) permission_denials unmodified.
        $d = @($r.Parsed.envelope.permission_denials)
        if ($d.Count -ne 1) { throw "expected 1 denial, got $($d.Count)" }
        if ($d[0].tool_use_id -ne 'toolu_01KhsD6BSCoHf6MmSbjMKF7s' -or $d[0].tool_input.command -ne 'git --version') { throw "denial entry was altered" }
        # command: the exact invocation, including the executable and report-mode flags.
        if (-not $r.Parsed.command.StartsWith($fake)) { throw "command does not start with the launched executable: $($r.Parsed.command)" }
        foreach ($frag in @('--agent fixture-reporter', '--restricted', '--output-format json', 'irrelevant')) {
            if (-not $r.Parsed.command.Contains($frag)) { throw "command missing '$frag': $($r.Parsed.command)" }
        }
        if ($r.Parsed.command.Contains('stream-json')) { throw "command still carries stream-json: $($r.Parsed.command)" }
    }

    Test-Case "(b) checkedAt is taken per run: a second run a second later gets a later stamp and its own file" {
        $fake = New-FakeClaude 'tworuns' $fixtureRaw 0
        $rd = New-ReportDir 'tworuns'
        & $scriptPath @common -ReportDir $rd -ClaudePath $fake *>&1 | Out-Null
        Start-Sleep -Milliseconds 1100
        & $scriptPath @common -ReportDir $rd -ClaudePath $fake *>&1 | Out-Null
        $files = @(Get-Reports $rd | Sort-Object Name)
        if ($files.Count -ne 2) { throw "expected 2 report files, got $($files.Count)" }
        $a = (Read-Report $files[0].FullName).Parsed.checkedAt
        $b = (Read-Report $files[1].FullName).Parsed.checkedAt
        if ($a -eq $b) { throw "checkedAt identical across runs ($a) -- not read from the clock per write" }
    }

    Test-Case "same agent, same second: second report gets a -2 suffix, first is not overwritten" {
        $fake = New-FakeClaude 'collide' $fixtureRaw 0
        $rd = New-ReportDir 'collide'
        New-Item -ItemType Directory -Path $rd -Force | Out-Null
        # Pre-seed every name the next few seconds could produce, so the run is forced onto a suffix.
        $seeded = @()
        for ($i = 0; $i -lt 5; $i++) {
            $n = Join-Path $rd ("fixture-reporter." + [DateTime]::UtcNow.AddSeconds($i).ToString('yyyyMMdd-HHmmss') + '.json')
            [System.IO.File]::WriteAllText($n, 'SEED', $utf8); $seeded += $n
        }
        & $scriptPath @common -ReportDir $rd -ClaudePath $fake *>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE" }
        foreach ($s in $seeded) { if ([System.IO.File]::ReadAllText($s) -ne 'SEED') { throw "seeded file $s was overwritten" } }
        $new = @(Get-Reports $rd | Where-Object { $_.Name -match '-2\.json$' })
        if ($new.Count -ne 1) { throw "expected one -2 suffixed report, got: $((Get-Reports $rd).Name -join ', ')" }
    }

    Test-Case "complete envelope with a non-zero CLI exit: report IS written (whole evidence), CLI exit code propagated" {
        $errEnv = '{"type":"result","subtype":"error_max_budget_usd","is_error":true,"num_turns":3,"total_cost_usd":0.051,"permission_denials":[],"usage":{"input_tokens":1,"output_tokens":2}}'
        $fake = New-FakeClaude 'nonzero-valid' ($errEnv + "`n") 1
        $rd = New-ReportDir 'nonzero-valid'
        & $scriptPath @common -ReportDir $rd -ClaudePath $fake *>&1 | Out-Null
        if ($LASTEXITCODE -ne 1) { throw "expected the CLI's own exit 1 propagated, got $LASTEXITCODE" }
        $files = Get-Reports $rd
        if ($files.Count -ne 1) { throw "expected 1 report, got $($files.Count)" }
        if ((Read-Report $files[0].FullName).Envelope -cne $errEnv) { throw "error envelope not byte-identical" }
    }

    Test-Case "fast-exiting CLI's non-zero exit is propagated without -Report too (Start-Process Handle fix; was exit 0)" {
        $fake = New-FakeClaude 'fast-nonzero' 'Error: bad flag' 9
        & $scriptPath @common -ClaudePath $fake *>&1 | Out-Null
        if ($LASTEXITCODE -ne 9) { throw "expected the CLI's own exit 9, got $LASTEXITCODE" }
    }

    $badCases = @(
        @{ Name = 'empty stdout, exit 0';            Out = '';                                     Exit = 0 },
        @{ Name = 'empty stdout, non-zero exit';     Out = '';                                     Exit = 1 },
        @{ Name = 'whitespace only';                 Out = "  `r`n";                              Exit = 0 },
        @{ Name = 'truncated JSON';                  Out = $fixtureTrimmed.Substring(0, 400);      Exit = 0 },
        @{ Name = 'plain text error';                Out = 'Error: something went wrong';          Exit = 1 },
        @{ Name = 'stream-json event array';         Out = '[{"type":"system","subtype":"init"},{"type":"result","subtype":"success"}]'; Exit = 0 },
        @{ Name = 'object missing permission_denials'; Out = '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01,"usage":{}}'; Exit = 0 },
        @{ Name = 'object with type != result';      Out = '{"type":"assistant","subtype":"x","is_error":false,"num_turns":1,"total_cost_usd":0,"permission_denials":[],"usage":{}}'; Exit = 0 },
        @{ Name = 'permission_denials not an array'; Out = '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0,"permission_denials":"none","usage":{}}'; Exit = 0 }
    )
    $i = 0
    foreach ($bc in $badCases) {
        $i++
        $caseName = $bc.Name; $caseOut = $bc.Out; $caseExit = $bc.Exit; $caseIdx = $i
        Test-Case "(d) $caseName -> exit 6, NO file written, loud error" {
            $fake = New-FakeClaude "bad$caseIdx" $caseOut $caseExit
            $rd = New-ReportDir "bad$caseIdx"
            $out = & $scriptPath @common -ReportDir $rd -ClaudePath $fake *>&1 | Out-String -Width 4096
            if ($LASTEXITCODE -ne 6) { throw "expected exit 6, got $LASTEXITCODE. Output: $out" }
            if ($out -notmatch 'NO REPORT WRITTEN') { throw "expected a loud NO REPORT WRITTEN error. Output: $out" }
            $files = Get-Reports $rd
            if ($files.Count -ne 0) { throw "expected no files, found: $($files.Name -join ', ')" }
        }
    }

    Test-Case "report folder that cannot be created -> exit 7, loud error" {
        $fake = New-FakeClaude 'unwritable' $fixtureRaw 0
        $blocker = Join-Path $root 'a-file-not-a-dir'
        [System.IO.File]::WriteAllText($blocker, 'x', $utf8)
        $rd = Join-Path $blocker 'reports'   # parent is a file, so the folder cannot exist
        $out = & $scriptPath @common -ReportDir $rd -ClaudePath $fake *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 7) { throw "expected exit 7, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch 'NO REPORT WRITTEN') { throw "expected loud error. Output: $out" }
    }

    Test-Case "-ClaudePath that does not exist -> exit 2" {
        & $scriptPath @common -ReportDir (New-ReportDir 'noexe') -ClaudePath (Join-Path $root 'nope.cmd') *>&1 | Out-Null
        if ($LASTEXITCODE -ne 2) { throw "expected exit 2, got $LASTEXITCODE" }
    }

    Test-Case "call site: -Report alone uses %APPDATA%\AEGIS\reports (APPDATA repointed to a temp dir); no -Report writes nothing" {
        $realAppData = $env:APPDATA
        $fakeAppData = Join-Path $root 'appdata'
        New-Item -ItemType Directory -Path $fakeAppData -Force | Out-Null
        try {
            $env:APPDATA = $fakeAppData
            $fake = New-FakeClaude 'default-dir' $fixtureRaw 0
            & $scriptPath @common -ClaudePath $fake *>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "no-report run: expected exit 0, got $LASTEXITCODE" }
            if (Test-Path (Join-Path $fakeAppData 'AEGIS')) { throw "a run without -Report created $fakeAppData\AEGIS" }
            & $scriptPath @common -Report -ClaudePath $fake *>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "-Report run: expected exit 0, got $LASTEXITCODE" }
            $files = Get-Reports (Join-Path $fakeAppData 'AEGIS\reports')
            if ($files.Count -ne 1) { throw "expected 1 report under the (repointed) default folder, got $($files.Count)" }
        } finally {
            $env:APPDATA = $realAppData
        }
    }

    Test-Case "no temp files left behind in any report folder" {
        $leftovers = @(Get-ChildItem -LiteralPath $root -Recurse -Force -File -Filter '*.tmp')
        if ($leftovers.Count -ne 0) { throw "found temp files: $($leftovers.FullName -join ', ')" }
    }

    # --- Live checks (real CLI, Haiku only) -----------------------------------------------------
    if ($RunLive) {
        # Uses the CLI's built-in 'general-purpose' agent, not a user-level roster agent: under
        # --restricted the CLI does not load ~/.claude/agents at all (verified 2026-09-21, CLI
        # 2.1.278: `--restricted --agent data-classification-tagger` exits 1 with "--agent
        # 'data-classification-tagger' not found. Available agents: claude, Explore,
        # general-purpose, Plan, statusline-setup"). That is an F2 interaction, reported on the PR;
        # this check is about the report path under --restricted, which a built-in agent exercises.
        Test-Case "live: real restricted Haiku run through the wrapper writes an envelope byte-identical to what the CLI printed" {
            $rd = New-ReportDir 'live1'
            $lines = & $scriptPath -AgentName 'general-purpose' -Prompt 'Reply with exactly the word OK and nothing else. Do not use any tools.' -Restricted -Model haiku -MaxBudgetUsd 0.25 -ReportDir $rd 2>&1
            $code = $LASTEXITCODE
            $out = $lines | Out-String -Width 8192
            if ($code -ne 0) { throw "expected exit 0, got $code. Output: $out" }
            $files = Get-Reports $rd
            if ($files.Count -ne 1) { throw "expected 1 report, got $($files.Count). Output: $out" }
            $r = Read-Report $files[0].FullName
            $printed = @($lines | ForEach-Object { "$_" } | Where-Object { $_.StartsWith('{') -and $_.Contains('"type":"result"') })
            if ($printed.Count -ne 1) { throw "expected the wrapper to echo exactly one envelope line, got $($printed.Count)" }
            if ($r.Envelope -cne $printed[0].Trim()) { throw "report envelope differs from the envelope the CLI printed" }
            foreach ($k in @('subtype', 'is_error', 'num_turns', 'total_cost_usd', 'permission_denials', 'usage')) {
                if (-not $r.Parsed.envelope.PSObject.Properties[$k]) { throw "live envelope missing $k" }
            }
            if (@($r.Parsed.envelope.permission_denials).Count -ne 0) { throw "restricted no-tool run should have zero denials" }
            if ($r.Envelope.Contains($r.Parsed.checkedAt)) { throw "checkedAt appears inside the envelope" }
            Write-Host "       live report: $($files[0].Name) cost=`$$($r.Parsed.envelope.total_cost_usd) subtype=$($r.Parsed.envelope.subtype)" -ForegroundColor DarkGray
        }

        # Through `powershell.exe -File`, the way a scheduled task would call it (call site, not only
        # the in-process `&` path), with a real L1 reporter from the roster. worktree-sweep is
        # "readonly": "instruction" in roster_meta.json, so the wrapper's own default lookup (the
        # real roster file, read only) resolves it to NOT restricted -- no -Restricted:$false,
        # which -File cannot pass as a switch value anyway.
        Test-Case "live: a real permission denial arrives in the report unmodified (via powershell.exe -File)" {
            $rd = New-ReportDir 'live2'
            $lines = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -AgentName 'worktree-sweep' -Prompt 'Use the Bash tool to run exactly this command: git --version . Then report its output.' -Tools 'Bash' -Model haiku -MaxBudgetUsd 0.25 -ReportDir $rd 2>&1
            $code = $LASTEXITCODE
            $out = $lines | Out-String -Width 8192
            $files = Get-Reports $rd
            if ($files.Count -ne 1) { throw "expected 1 report (exit $code), got $($files.Count). Output: $out" }
            $r = Read-Report $files[0].FullName
            $printed = @($lines | ForEach-Object { "$_" } | Where-Object { $_.StartsWith('{') -and $_.Contains('"type":"result"') })
            # No byte comparison here: across a powershell.exe -File boundary the echoed line passes
            # through the child console's code page, so any non-ASCII character in the model's
            # prose (a dash, a curly quote) arrives re-encoded even though the report file itself is
            # UTF-8 exact. Byte identity is proven in-process by the check above and by the static
            # suite; this check is about the denial and the -File call site.
            if ($printed.Count -ne 1) { throw "expected the wrapper to echo exactly one envelope line, got $($printed.Count)" }
            $d = @($r.Parsed.envelope.permission_denials)
            $fromCli = @(($printed[0] | ConvertFrom-Json).permission_denials)
            if ($d.Count -lt 1) { throw "expected at least one permission denial (Bash under dontAsk without an allow rule). Envelope: $($r.Envelope)" }
            if (($d | ConvertTo-Json -Depth 10 -Compress) -ne ($fromCli | ConvertTo-Json -Depth 10 -Compress)) { throw "denials differ between CLI stdout and report" }
            Write-Host "       live denial: $($d[0].tool_name) '$($d[0].tool_input.command)' cost=`$$($r.Parsed.envelope.total_cost_usd)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "[SKIP] live report checks (pass -RunLive to exercise them; spends real API budget, Haiku only)" -ForegroundColor Yellow
    }
} finally {
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "== Results: $testsPassed passed, $testsFailed failed ==" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host ""

if ($testsFailed -gt 0) { exit 1 } else { exit 0 }
