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
    (a) the report's envelope is character-for-character the CLI's stdout (nothing trimmed);
    (b) checkedAt is the wrapper's clock at write time, differs run to run, and appears nowhere
        inside the envelope;
    (c) a populated permission_denials array arrives in the report unmodified;
    (d) empty / malformed / non-envelope CLI output, or a non-zero CLI exit, fails loudly (exit 6)
        and writes NO file.
  The report is exactly {envelope, checkedAt, command} (plan:617), and the prompt is never stored.
  Plus the PR #176 review fixes: the prompt always goes on stdin (a prompt containing " & % cannot
  reach cmd.exe as shell syntax), unsafe -AgentName/-Model/-Tools/-AllowedTools/-SettingsPath values
  (including a trailing backslash) are refused before launch, -ClaudePath needs AEGIS_TEST_SEAM=1 and
  may never write into the real drop folder, lenient-only JSON is rejected, and a timeout kills the
  whole process tree.

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

# -ClaudePath is refused without this opt-in (PR #176 review). Set for this process only, restored
# in the finally block at the end.
$priorTestSeam = $env:AEGIS_TEST_SEAM
$env:AEGIS_TEST_SEAM = '1'

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

# A fake CLI that records what it received: its command-line arguments (as cmd.exe expanded them) to
# args.txt and its stdin to stdin.txt, then prints the fixture envelope. Used to prove where the
# prompt travels and that nothing in it is run by cmd.exe.
function New-RecordingClaude([string]$Name) {
    $dir = Join-Path $root $Name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $dir 'out.txt'), $fixtureRaw, $utf8)
    $cmd = Join-Path $dir 'fake-claude.cmd'
    $body = "@echo off`r`n(echo ARGS=%*)> `"%~dp0args.txt`"`r`nfindstr `"^`" > `"%~dp0stdin.txt`"`r`ntype `"%~dp0out.txt`"`r`nexit /b 0`r`n"
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

    Test-Case "prompt never appears on the command line; it goes on stdin (PR #176 review HIGH)" {
        $out = & $scriptPath -AgentName 'fixture-reporter' -Prompt 'run git --version now' -Restricted -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        $argsLine = ($out -split "`n") | Where-Object { $_ -match '^DRYRUN ARGS:' }
        if ($argsLine -match 'run git') { throw "prompt text is on the command line. Args: $argsLine" }
        if ($argsLine -notmatch '\(prompt on stdin\)') { throw "expected '(prompt on stdin)'. Args: $argsLine" }
    }

    Test-Case "call site: a prompt with double quotes, &, | and %VAR% reaches the CLI on stdin, verbatim, and runs nothing" {
        $fake = New-RecordingClaude 'inject'
        $rd = New-ReportDir 'inject'
        $evil = 'hello " & echo INJECTED-BY-PROMPT & rem " | %PATH% ^ > x.txt'
        $out = & $scriptPath -AgentName 'fixture-reporter' -Prompt $evil -Restricted -ReportDir $rd -ClaudePath $fake *>&1 | Out-String -Width 8192
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -match '(?m)^INJECTED-BY-PROMPT') { throw "cmd.exe ran text from the prompt. Output: $out" }
        $fakeDir = Split-Path -Parent $fake
        if (Test-Path (Join-Path $fakeDir 'x.txt')) { throw "a redirect in the prompt created a file" }
        $argsTxt = [System.IO.File]::ReadAllText((Join-Path $fakeDir 'args.txt'))
        if ($argsTxt -match 'INJECTED|hello') { throw "prompt reached the command line: $argsTxt" }
        $stdinTxt = [System.IO.File]::ReadAllText((Join-Path $fakeDir 'stdin.txt'), $utf8).TrimEnd("`r", "`n")
        if ($stdinTxt -cne $evil) { throw "stdin did not carry the prompt verbatim. Got: [$stdinTxt]" }
    }

    Test-Case "-AgentName with cmd.exe metacharacters is refused (exit 2) and nothing is launched" {
        $fake = New-RecordingClaude 'badagent'
        $out = & $scriptPath -AgentName 'x & echo PWNED' -Prompt 'irrelevant' -Restricted -ClaudePath $fake *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 2) { throw "expected exit 2, got $LASTEXITCODE. Output: $out" }
        if (Test-Path (Join-Path (Split-Path -Parent $fake) 'args.txt')) { throw "the CLI was launched" }
        & $scriptPath -AgentName "ok-name`n" -Prompt 'irrelevant' -Restricted -DryRun *>&1 | Out-Null
        if ($LASTEXITCODE -ne 2) { throw "a trailing newline in -AgentName must be refused, got $LASTEXITCODE" }
    }

    Test-Case "-Model outside its character set is refused (exit 2)" {
        & $scriptPath @common -Model 'haiku & echo PWNED' -DryRun *>&1 | Out-Null
        if ($LASTEXITCODE -ne 2) { throw "expected exit 2, got $LASTEXITCODE" }
        & $scriptPath @common -Model 'claude-opus-4-1[1m]' -DryRun *>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "a normal model id must still be accepted, got $LASTEXITCODE" }
    }

    Test-Case "-Tools / -AllowedTools / -SettingsPath with a double quote or % are refused (exit 2)" {
        & $scriptPath -AgentName 'fixture-reporter' -Prompt 'x' -Restricted:$false -Tools 'Read" & echo PWNED & rem "' -DryRun *>&1 | Out-Null
        if ($LASTEXITCODE -ne 2) { throw "-Tools: expected exit 2, got $LASTEXITCODE" }
        & $scriptPath -AgentName 'fixture-reporter' -Prompt 'x' -Restricted:$false -Tools 'Bash' -AllowedTools 'Bash(echo %PATH%)' -DryRun *>&1 | Out-Null
        if ($LASTEXITCODE -ne 2) { throw "-AllowedTools: expected exit 2, got $LASTEXITCODE" }
        & $scriptPath @common -SettingsPath 'C:\x"y.json' -DryRun *>&1 | Out-Null
        if ($LASTEXITCODE -ne 2) { throw "-SettingsPath: expected exit 2, got $LASTEXITCODE" }
        & $scriptPath -AgentName 'fixture-reporter' -Prompt 'x' -Restricted:$false -Tools 'Bash' -AllowedTools 'Bash(git worktree list:*),Bash(git status:*)' -DryRun *>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "a normal -AllowedTools value must still be accepted, got $LASTEXITCODE" }
    }

    Test-Case "a trailing backslash in -SettingsPath / -Tools / -AllowedTools is refused (exit 2); a directory is not a settings file" {
        # "C:\dir\" would become "C:\dir\" on the command line, and the CLI's argv parser reads the
        # trailing \" as an escaped quote, swallowing --restricted/--tools/--permission-mode after it.
        $dirWithSlash = $root + '\'
        $out = & $scriptPath @common -SettingsPath $dirWithSlash -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 2) { throw "-SettingsPath ending in \: expected exit 2, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch 'backslash') { throw "error should name the trailing backslash. Output: $out" }
        & $scriptPath -AgentName 'fixture-reporter' -Prompt 'x' -Restricted:$false -Tools 'Bash\' -DryRun *>&1 | Out-Null
        if ($LASTEXITCODE -ne 2) { throw "-Tools ending in \: expected exit 2, got $LASTEXITCODE" }
        & $scriptPath -AgentName 'fixture-reporter' -Prompt 'x' -Restricted:$false -Tools 'Bash' -AllowedTools 'Bash(dir C:\x\)\' -DryRun *>&1 | Out-Null
        if ($LASTEXITCODE -ne 2) { throw "-AllowedTools ending in \: expected exit 2, got $LASTEXITCODE" }
        # A directory without the trailing backslash passes the character check but is not a file.
        $out = & $scriptPath @common -SettingsPath $root -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 2) { throw "-SettingsPath pointing at a directory: expected exit 2, got $LASTEXITCODE. Output: $out" }
    }

    Test-Case "-ClaudePath is refused without AEGIS_TEST_SEAM=1 (exit 2, nothing launched, no report)" {
        $fake = New-RecordingClaude 'noseam'
        $rd = New-ReportDir 'noseam'
        $env:AEGIS_TEST_SEAM = $null
        try {
            $out = & $scriptPath @common -ReportDir $rd -ClaudePath $fake *>&1 | Out-String -Width 4096
            $code = $LASTEXITCODE
        } finally { $env:AEGIS_TEST_SEAM = '1' }
        if ($code -ne 2) { throw "expected exit 2, got $code. Output: $out" }
        if ($out -notmatch 'AEGIS_TEST_SEAM') { throw "error should name the opt-in. Output: $out" }
        if (Test-Path (Join-Path (Split-Path -Parent $fake) 'args.txt')) { throw "the fake CLI was launched" }
        if ((Get-Reports $rd).Count -ne 0) { throw "a report was written" }
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
        if (($r.Keys -join ',') -ne 'envelope,checkedAt,command') { throw "expected exactly the keys envelope,checkedAt,command in that order (plan:617); got $($r.Keys -join ',')" }
        # (a) byte-identical: exactly the characters the CLI printed, trailing newline included.
        if ($r.Envelope -cne $fixtureRaw) { throw "envelope is not byte-identical to the CLI stdout" }
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
        foreach ($frag in @('--agent fixture-reporter', '--restricted', '--output-format json')) {
            if (-not $r.Parsed.command.Contains($frag)) { throw "command missing '$frag': $($r.Parsed.command)" }
        }
        if ($r.Parsed.command.Contains('stream-json')) { throw "command still carries stream-json: $($r.Parsed.command)" }
        # Exactly the launched command line: the executable, then the same args DryRun prints.
        $dry = & $scriptPath @common -ReportDir $rd -DryRun *>&1 | Out-String -Width 8192
        $dryArgs = ((($dry -split "`n") | Where-Object { $_ -match '^DRYRUN ARGS:' }) -replace '^DRYRUN ARGS: ', '' -replace ' \(prompt on stdin\)\s*$', '').Trim()
        if ($r.Parsed.command -cne "$fake $dryArgs") { throw "command is not exactly the launched command line.`n got:      $($r.Parsed.command)`n expected: $fake $dryArgs" }
    }

    Test-Case "the prompt is never stored in the report (it goes on stdin; reports are kept indefinitely, D6)" {
        $fake = New-FakeClaude 'noprompt' $fixtureRaw 0
        $rd = New-ReportDir 'noprompt'
        $secretish = 'token=abc123-DO-NOT-STORE'
        & $scriptPath -AgentName 'fixture-reporter' -Prompt $secretish -Restricted -ReportDir $rd -ClaudePath $fake *>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE" }
        $files = Get-Reports $rd
        if ($files.Count -ne 1) { throw "expected 1 report, got $($files.Count)" }
        $text = [System.IO.File]::ReadAllText($files[0].FullName, $utf8)
        if ($text.Contains('abc123')) { throw "prompt text leaked into the report: $text" }
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

    Test-Case "complete envelope with a non-zero CLI exit -> exit 6, NO file written, loud error, envelope still echoed (F3 brief section 6)" {
        $errEnv = '{"type":"result","subtype":"error_max_budget_usd","is_error":true,"num_turns":3,"total_cost_usd":0.051,"permission_denials":[],"usage":{"input_tokens":1,"output_tokens":2}}'
        $fake = New-FakeClaude 'nonzero-valid' ($errEnv + "`n") 1
        $rd = New-ReportDir 'nonzero-valid'
        $out = & $scriptPath @common -ReportDir $rd -ClaudePath $fake *>&1 | Out-String -Width 8192
        if ($LASTEXITCODE -ne 6) { throw "expected exit 6, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch 'NO REPORT WRITTEN' -or $out -notmatch 'exit code 1') { throw "expected a loud NO REPORT WRITTEN error naming the CLI exit code. Output: $out" }
        if (-not $out.Contains('error_max_budget_usd')) { throw "the CLI's stdout should still be echoed. Output: $out" }
        $files = Get-Reports $rd
        if ($files.Count -ne 0) { throw "expected no files, found: $($files.Name -join ', ')" }
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
        @{ Name = 'permission_denials not an array'; Out = '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0,"permission_denials":"none","usage":{}}'; Exit = 0 },
        @{ Name = 'lenient-only JSON (single-quoted keys; PS 5.1 ConvertFrom-Json accepts it)'; Out = "{'type':'result','subtype':'success','is_error':false,'num_turns':1,'total_cost_usd':0,'permission_denials':[],'usage':{}}"; Exit = 0 }
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

    Test-Case "-Report alone resolves %APPDATA%\AEGIS\reports; the test seam can never write there (APPDATA repointed to a temp dir)" {
        $realAppData = $env:APPDATA
        $fakeAppData = Join-Path $root 'appdata'
        New-Item -ItemType Directory -Path $fakeAppData -Force | Out-Null
        try {
            $env:APPDATA = $fakeAppData
            $defaultDir = Join-Path $fakeAppData 'AEGIS\reports'
            $dry = & $scriptPath @common -Report -DryRun *>&1 | Out-String -Width 4096
            if ($LASTEXITCODE -ne 0) { throw "DryRun -Report: expected exit 0, got $LASTEXITCODE. Output: $dry" }
            if (-not $dry.Contains("DRYRUN REPORT dir=$defaultDir")) { throw "expected default dir $defaultDir. Output: $dry" }
            $fake = New-FakeClaude 'default-dir' $fixtureRaw 0
            & $scriptPath @common -ClaudePath $fake *>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "no-report run: expected exit 0, got $LASTEXITCODE" }
            if (Test-Path (Join-Path $fakeAppData 'AEGIS')) { throw "a run without -Report created $fakeAppData\AEGIS" }
            $out = & $scriptPath @common -Report -ClaudePath $fake *>&1 | Out-String -Width 4096
            if ($LASTEXITCODE -ne 2) { throw "seam + -Report with no -ReportDir: expected exit 2, got $LASTEXITCODE. Output: $out" }
            & $scriptPath @common -ReportDir ($defaultDir + '\') -ClaudePath $fake *>&1 | Out-Null
            if ($LASTEXITCODE -ne 2) { throw "seam + -ReportDir = the real drop folder: expected exit 2, got $LASTEXITCODE" }
            & $scriptPath @common -ReportDir $defaultDir.ToUpperInvariant() -ClaudePath $fake *>&1 | Out-Null
            if ($LASTEXITCODE -ne 2) { throw "seam + -ReportDir = the real drop folder (other case): expected exit 2, got $LASTEXITCODE" }
            if (Test-Path (Join-Path $fakeAppData 'AEGIS')) { throw "the seam wrote into the real drop folder" }
        } finally {
            $env:APPDATA = $realAppData
        }
    }

    Test-Case "timeout kills the whole process tree, not only cmd.exe (exit 3, no child left running)" {
        $marker = 'f3-timeout-' + [Guid]::NewGuid().ToString('N')
        $dir = Join-Path $root 'timeout'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $cmd = Join-Path $dir 'fake-claude.cmd'
        # The fake CLI starts a long-lived child (as claude.cmd starts node), tagged with a marker.
        $body = "@echo off`r`npowershell.exe -NoProfile -Command `"Start-Sleep -Seconds 60; '$marker'`"`r`nexit /b 0`r`n"
        [System.IO.File]::WriteAllText($cmd, $body, [System.Text.Encoding]::ASCII)
        $out = & $scriptPath @common -TimeoutSec 3 -ClaudePath $cmd *>&1 | Out-String -Width 4096
        $code = $LASTEXITCODE
        Start-Sleep -Milliseconds 500
        $left = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($marker) })
        if ($code -ne 3) { throw "expected exit 3, got $code. Output: $out" }
        if ($left.Count -ne 0) { throw "the CLI's child process is still running after the timeout (PID $($left[0].ProcessId))" }
    }

    Test-Case "no temp files left behind in any report folder" {
        $leftovers = @(Get-ChildItem -LiteralPath $root -Recurse -Force -File -Filter '*.tmp')
        if ($leftovers.Count -ne 0) { throw "found temp files: $($leftovers.FullName -join ', ')" }
    }

    # --- Live checks (real CLI, Haiku only) -----------------------------------------------------
    if ($RunLive) {
        # A real L1 reporter doing its real job (F3 brief section 6: "a real L1 reporter
        # invocation"): worktree-sweep (roster_meta.json role R, headless yes, readonly
        # "instruction", so the wrapper's own roster lookup resolves it to NOT restricted) sweeps a
        # throwaway two-worktree repo, with -AllowedTools scoped to the git commands its definition
        # uses. Not --restricted: under --restricted the CLI does not load ~/.claude/agents at all
        # (the #174 interaction reported on the PR), so no user-level reporter can run restricted yet.
        Test-Case "live: a real L1 reporter (worktree-sweep, Haiku) through the wrapper writes exactly {envelope, checkedAt, command}, envelope byte-identical to what the CLI printed" {
            $rd = New-ReportDir 'live1'
            $repo = Join-Path $root 'sweep-repo'
            New-Item -ItemType Directory -Path $repo -Force | Out-Null
            & git -C $repo init -q 2>&1 | Out-Null
            & git -C $repo -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init 2>&1 | Out-Null
            & git -C $repo worktree add -q (Join-Path $root 'sweep-repo-wt') -b sweep-branch 2>&1 | Out-Null
            $repoFwd = $repo -replace '\\', '/'
            $prompt = "Sweep the git worktrees of the repo at $repoFwd. It is a local test repo with no GitHub remote, so skip every PR lookup and do not run gh. Report each worktree's path, branch and whether it is clean."
            $lines = & $scriptPath -AgentName 'worktree-sweep' -Prompt $prompt -Tools 'Bash' -AllowedTools 'Bash(git -C * worktree list:*),Bash(git -C * status:*)' -Model haiku -MaxBudgetUsd 0.5 -ReportDir $rd 2>&1
            $code = $LASTEXITCODE
            $out = $lines | Out-String -Width 8192
            if ($code -ne 0) { throw "expected exit 0, got $code. Output: $out" }
            $files = Get-Reports $rd
            if ($files.Count -ne 1) { throw "expected 1 report, got $($files.Count). Output: $out" }
            $r = Read-Report $files[0].FullName
            $printed = @($lines | ForEach-Object { "$_" } | Where-Object { $_.StartsWith('{') -and $_.Contains('"type":"result"') })
            if ($printed.Count -ne 1) { throw "expected the wrapper to echo exactly one envelope line, got $($printed.Count)" }
            if ($r.Envelope.TrimEnd("`r", "`n") -cne $printed[0]) { throw "report envelope differs from the envelope the CLI printed" }
            foreach ($k in @('subtype', 'is_error', 'num_turns', 'total_cost_usd', 'permission_denials', 'usage')) {
                if (-not $r.Parsed.envelope.PSObject.Properties[$k]) { throw "live envelope missing $k" }
            }
            if (($r.Keys -join ',') -ne 'envelope,checkedAt,command') { throw "a real run's report must be exactly envelope,checkedAt,command; got $($r.Keys -join ',')" }
            if ($r.Envelope.Contains($r.Parsed.checkedAt)) { throw "checkedAt appears inside the envelope" }
            if ($r.Text.Contains('local test repo with no GitHub remote')) { throw "the prompt was stored in the report" }
            if (-not $r.Parsed.command.Contains('--agent worktree-sweep')) { throw "command does not name the reporter: $($r.Parsed.command)" }
            Write-Host "       live report: $($files[0].Name) cost=`$$($r.Parsed.envelope.total_cost_usd) subtype=$($r.Parsed.envelope.subtype) turns=$($r.Parsed.envelope.num_turns) denials=$(@($r.Parsed.envelope.permission_denials).Count)" -ForegroundColor DarkGray
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
            if (($r.Keys -join ',') -ne 'envelope,checkedAt,command') { throw "a real run's report must be exactly envelope,checkedAt,command; got $($r.Keys -join ',')" }
            if (($d | ConvertTo-Json -Depth 10 -Compress) -ne ($fromCli | ConvertTo-Json -Depth 10 -Compress)) { throw "denials differ between CLI stdout and report" }
            Write-Host "       live denial: $($d[0].tool_name) '$($d[0].tool_input.command)' cost=`$$($r.Parsed.envelope.total_cost_usd)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "[SKIP] live report checks (pass -RunLive to exercise them; spends real API budget, Haiku only)" -ForegroundColor Yellow
    }
} finally {
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
    $env:AEGIS_TEST_SEAM = $priorTestSeam
}

Write-Host ""
Write-Host "== Results: $testsPassed passed, $testsFailed failed ==" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host ""

if ($testsFailed -gt 0) { exit 1 } else { exit 0 }
