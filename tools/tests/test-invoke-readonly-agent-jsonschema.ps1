<#
.SYNOPSIS
  Regression tests for plan task F12's -JsonSchemaPath addition to Invoke-ReadOnlyAgent.ps1.

.DESCRIPTION
  Static suite (-DryRun, throwaway fixtures, no `claude` needed), following
  tools/tests/test-invoke-readonly-agent-restricted.ps1's own seam conventions, PLUS a mechanism
  suite added 2026-09-22 (QA follow-up round 2 on PR #197): the static/DryRun checks alone proved
  only that ConvertTo-QuotedArg escapes a schema's content into the built $claudeArgs string -- they
  never launched anything, so they could not catch (and did not catch) that claude.cmd is a batch
  file, launched through cmd.exe, which does not honour ConvertTo-QuotedArg's backslash-escaped
  quote and cannot carry a literal newline in a single command line at all. Real JSON Schema content
  almost always has both. Confirmed live against the real CLI (2.1.278, `claude --help` plus a real
  invocation): --json-schema takes the schema's JSON inline, with no file-path or stdin input mode,
  so the value must survive on the command line intact.

  Invoke-ReadOnlyAgent.ps1 was fixed to prefer the native claude.exe (the real Windows PE binary
  claude.cmd's own body forwards to) over claude.cmd itself, whenever found -- launching it directly
  skips cmd.exe's re-tokenizing pass, so ConvertTo-QuotedArg's existing escaping (which matches
  standard Windows CommandLineToArgvW argv parsing) is correct. The mechanism tests below prove that
  fix, not just the string it produces:

    (1) a schema containing a `"` and a newline, launched via a native (non-batch) fake executable
        through the SAME Start-Process call the real script makes, arrives at the child's argv as
        one unmangled argument -- proving the escaping-plus-native-exe combination actually works;
    (2) the real (non-DryRun, non--ClaudePath) executable-resolution code path in
        Invoke-ReadOnlyAgent.ps1 itself prefers a sibling claude.exe over claude.cmd when both exist
        next to each other on PATH, using the exact relative layout the real npm install uses;
    (3) when no sibling claude.exe exists, it falls back to claude.cmd unchanged (old behaviour
        preserved) and warns when -JsonSchemaPath is in play, since that fallback path is exactly
        the one the fix exists to avoid.

  Requires csc.exe (the .NET Framework C# compiler that ships alongside Windows PowerShell 5.1,
  normally at C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe) to build a tiny native argv-
  echoing test double at run time -- nothing is checked into the repo. The mechanism tests are
  skipped, loudly, rather than failing the whole suite, if csc.exe cannot be found; the static suite
  never depends on it.
#>
param()

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path (Split-Path -Parent $here) 'headless\Invoke-ReadOnlyAgent.ps1'

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
Write-Host "== F12 regression tests: -JsonSchemaPath on Invoke-ReadOnlyAgent.ps1" -ForegroundColor Cyan
Write-Host ""

$fixtureDir = Join-Path ([System.IO.Path]::GetTempPath()) ("f12-jsonschema-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

$schemaFile = Join-Path $fixtureDir 'fixture.json'
'{"type":"object","properties":{"a":{"type":"string"}},"required":["a"],"additionalProperties":false}' | Set-Content -Path $schemaFile -Encoding utf8

# A schema with a `"` (structurally unavoidable in JSON) AND a real line break -- the exact shape
# 2026-09-22's QA round found was still unsafe after a05aa63 fixed content-vs-path. Ordinary,
# human-authored JSON Schema looks like this; a single-line fixture never exercised the cmd.exe
# newline hazard at all.
$multilineSchemaFile = Join-Path $fixtureDir 'fixture-multiline.json'
$multilineSchemaContent = "{`n  `"type`": `"object`",`n  `"properties`": {`n    `"name`": {`n      `"type`": `"string`"`n    }`n  },`n  `"required`": [`"name`"]`n}`n"
[System.IO.File]::WriteAllText($multilineSchemaFile, $multilineSchemaContent, $utf8NoBom)

try {
    Test-Case "no -JsonSchemaPath: args are byte-identical to before this parameter existed (no --json-schema)" {
        $out = & $scriptPath -AgentName 'worktree-sweep' -Prompt 'irrelevant' -Restricted -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -match '--json-schema') { throw "expected no --json-schema when -JsonSchemaPath is not passed. Output: $out" }
    }

    Test-Case "-JsonSchemaPath threads --json-schema <file CONTENT, not the path> into the built args" {
        # Bug fix (QA, PR #197 comments 2026-09-22): the CLI's --json-schema flag expects the
        # schema file's content, not its path -- a path string made the CLI fail during its own
        # argument/schema parsing before ever reaching the API. Assert the file's content is what
        # lands in the built args, and that the bare path string is NOT what is passed as the
        # flag's value.
        $out = & $scriptPath -AgentName 'worktree-sweep' -Prompt 'irrelevant' -Restricted -JsonSchemaPath $schemaFile -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch [regex]::Escape('--json-schema')) { throw "expected --json-schema in built args. Output: $out" }
        # ConvertTo-QuotedArg escapes embedded double quotes as \" before wrapping in quotes, so the
        # built args carry the escaped form, not the raw file bytes verbatim.
        $schemaContent = Get-Content -Raw -LiteralPath $schemaFile
        $escapedContent = $schemaContent -replace '"', '\"'
        if ($out -notmatch [regex]::Escape($escapedContent)) { throw "expected the schema file's CONTENT in built args. Output: $out" }
        if ($out -match [regex]::Escape($schemaFile)) { throw "did not expect the schema PATH itself in built args -- --json-schema must carry the file's content, not its path. Output: $out" }
    }

    Test-Case "-JsonSchemaPath with a quote AND a newline: built args still carry the escaped content, not the path (DryRun)" {
        $out = & $scriptPath -AgentName 'worktree-sweep' -Prompt 'irrelevant' -Restricted -JsonSchemaPath $multilineSchemaFile -DryRun *>&1 | Out-String -Width 8192
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        # Out-String normalises line breaks to CRLF on the way through the pipeline; normalise both
        # sides the same way before comparing so this is a content check, not a line-ending check.
        $outNormalized = $out -replace "`r`n", "`n"
        $escapedContent = ($multilineSchemaContent -replace '"', '\"') -replace "`r`n", "`n"
        if ($outNormalized -notmatch [regex]::Escape($escapedContent)) { throw "expected the multiline schema's escaped content in built args. Output: $out" }
        if ($out -match [regex]::Escape($multilineSchemaFile)) { throw "did not expect the schema PATH itself in built args. Output: $out" }
    }

    Test-Case "-JsonSchemaPath pointing at a missing file is refused (exit 2), nothing launched" {
        & $scriptPath -AgentName 'worktree-sweep' -Prompt 'irrelevant' -Restricted -JsonSchemaPath (Join-Path $fixtureDir 'does-not-exist.json') -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 2) { throw "expected exit 2, got $LASTEXITCODE" }
    }

    Test-Case "-JsonSchemaPath containing an unsafe character is refused (exit 2), nothing launched" {
        $unsafe = Join-Path $fixtureDir 'has"quote.json'
        & $scriptPath -AgentName 'worktree-sweep' -Prompt 'irrelevant' -Restricted -JsonSchemaPath $unsafe -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 2) { throw "expected exit 2, got $LASTEXITCODE" }
    }

    Test-Case "-JsonSchemaPath with the REAL pr-state-sweep.json (nested pre-escaped quotes): --json-schema is present and the built args are not byte-identical to the raw path string" {
        # Cheap static/DryRun smoke check only -- the precise byte-for-byte round-trip assertion for
        # this file lives in the mechanism suite below ("REAL pr-state-sweep.json round-trips..."),
        # because a string-level substring check on the ESCAPED command-line text does not actually
        # prove the fix works: round 1 of this fix (2026-09-22) looked correct at the string level
        # (assertions just like this one passed) but still corrupted the schema live, because the
        # command line is decoded by Windows' own argv rules before the CLI ever sees it -- see
        # ConvertTo-QuotedArg's own comment for the decode rule and why only an actual round-trip
        # through that decoding proves correctness.
        $repoRoot = Split-Path -Parent $here
        $realSchemaFile = Join-Path $repoRoot 'headless\schemas\pr-state-sweep.json'
        if (-not (Test-Path -LiteralPath $realSchemaFile -PathType Leaf)) {
            throw "real schema fixture not found at $realSchemaFile"
        }
        $realContent = Get-Content -Raw -LiteralPath $realSchemaFile
        if ($realContent -notmatch [regex]::Escape('\"3h\"') -or $realContent -notmatch [regex]::Escape('\"2d\"')) {
            throw "expected the real schema to contain the pre-escaped 3h/2d quote pattern this test relies on -- fixture assumption broke, update this test (and the mechanism-suite round-trip test) if pr-state-sweep.json's description text changed"
        }

        $out = & $scriptPath -AgentName 'worktree-sweep' -Prompt 'irrelevant' -Restricted -JsonSchemaPath $realSchemaFile -DryRun *>&1 | Out-String -Width 65536
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE" }
        if ($out -notmatch [regex]::Escape('--json-schema')) { throw "expected --json-schema in built args. Output: $out" }
        if ($out -match [regex]::Escape($realSchemaFile)) { throw "did not expect the schema PATH itself in built args. Output: $out" }
    }

    Test-Case "-JsonSchemaPath works alongside a non-restricted -Tools call too" {
        # -AllowedTools passed explicitly here (2026-09-22, phase 1 of the roster allowedTools
        # overlay): 'diff-reviewer' has Bash in -Tools and no roster_meta.json 'allowedTools' list
        # of its own (phase 2, not yet done), so without this the call would now be refused with
        # exit 8 before ever reaching the --json-schema logic this test actually exercises. Passing
        # -AllowedTools explicitly here isolates that -- unrelated -- concern, same as any other
        # caller that already scopes its own Bash access.
        $out = & $scriptPath -AgentName 'diff-reviewer' -Prompt 'irrelevant' -Tools 'Bash' -AllowedTools 'Bash(gh pr diff *)' -JsonSchemaPath $schemaFile -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch [regex]::Escape('--json-schema')) { throw "expected --json-schema in built args. Output: $out" }
        $schemaContent = Get-Content -Raw -LiteralPath $schemaFile
        $escapedContent = $schemaContent -replace '"', '\"'
        if ($out -notmatch [regex]::Escape($escapedContent)) { throw "expected the schema file's CONTENT (not its path) in built args. Output: $out" }
    }

    # --- Mechanism suite (2026-09-22, QA follow-up round 2): proves the fix, not just the string ---
    $csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $csc -PathType Leaf)) {
        $csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
    }
    if (-not (Test-Path -LiteralPath $csc -PathType Leaf)) {
        Write-Host "[SKIP] mechanism suite: csc.exe not found (tried Framework64 and Framework v4.0.30319) -- static suite above still covers the built-args string" -ForegroundColor Yellow
    } else {
        # A tiny native (non-batch) console app: writes each argv element it actually received,
        # Base64-encoded one per line (so an embedded newline or NUL in an argument can never be
        # confused with the line-per-argument framing), to the file named by ECHO_OUT. Standing in
        # for claude.exe: a real Windows PE binary whose own argv parsing follows the standard
        # CommandLineToArgvW convention, unlike a .cmd, which Windows launches through cmd.exe.
        $echoSrc = Join-Path $fixtureDir 'echoargs.cs'
        $echoExe = Join-Path $fixtureDir 'echoargs.exe'
        $echoCode = @'
using System;
using System.IO;
using System.Text;
class EchoArgs {
    static int Main(string[] args) {
        string outPath = Environment.GetEnvironmentVariable("ECHO_OUT");
        if (!string.IsNullOrEmpty(outPath)) {
            using (var sw = new StreamWriter(outPath, false, new UTF8Encoding(false))) {
                foreach (var a in args) {
                    sw.WriteLine(Convert.ToBase64String(Encoding.UTF8.GetBytes(a)));
                }
            }
        }
        return 0;
    }
}
'@
        [System.IO.File]::WriteAllText($echoSrc, $echoCode, $utf8NoBom)
        & $csc /nologo /out:$echoExe /target:exe $echoSrc 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $echoExe -PathType Leaf)) {
            Write-Host "[SKIP] mechanism suite: csc.exe failed to build the test double (exit $LASTEXITCODE)" -ForegroundColor Yellow
        } else {
            function Get-EchoedArgs([string]$OutFile) {
                if (-not (Test-Path -LiteralPath $OutFile)) { return @() }
                return @(Get-Content -LiteralPath $OutFile | ForEach-Object {
                    [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_))
                })
            }

            Test-Case "mechanism: a native (non-batch) exe receives a quote+newline schema as ONE unmangled argv element (-ClaudePath)" {
                # Same call site as a real run (-ClaudePath is refused unless AEGIS_TEST_SEAM=1, same
                # gate every other seam test uses), just pointed at the native echo exe instead of
                # claude.cmd -- this is exactly the launch the resolution fix now performs for real.
                $priorSeam = $env:AEGIS_TEST_SEAM
                $priorEchoOut = $env:ECHO_OUT
                $echoOut = Join-Path $fixtureDir 'echoout-claudepath.txt'
                $env:AEGIS_TEST_SEAM = '1'
                $env:ECHO_OUT = $echoOut
                try {
                    & $scriptPath -AgentName 'worktree-sweep' -Prompt 'irrelevant' -Restricted -JsonSchemaPath $multilineSchemaFile -ClaudePath $echoExe *>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE" }
                } finally {
                    $env:AEGIS_TEST_SEAM = $priorSeam
                    $env:ECHO_OUT = $priorEchoOut
                }
                $received = Get-EchoedArgs $echoOut
                $idx = [array]::IndexOf($received, '--json-schema')
                if ($idx -lt 0) { throw "--json-schema not found among received args: $($received -join ' | ')" }
                $schemaArg = $received[$idx + 1]
                if ($schemaArg -cne $multilineSchemaContent) {
                    throw "schema arg the child received does not match the raw file content byte-for-byte.`n received: [$schemaArg]`n expected: [$multilineSchemaContent]"
                }
            }

            Test-Case "mechanism: the REAL pr-state-sweep.json (nested pre-escaped quotes) round-trips byte-for-byte through actual argv decoding (-ClaudePath)" {
                # This is the test that would have caught round 1 of the 2026-09-22 fix. Round 1
                # (leave an already-odd backslash run untouched, escape only a bare/even run) passed
                # every DryRun/string-level assertion in this file, but a live -Verbose run against
                # this exact schema (this PR's own QA step 5) still failed with "JSON Parse error:
                # Expected '}'" -- because the delivered argument is decoded by Windows' own
                # backslash-before-quote argv rule, which CONSUMES a single escaping backslash
                # (`\"`, N=1 -> 0 backslashes + a literal quote) rather than preserving it. Only an
                # actual round-trip through that decoding (not a string comparison against the
                # escaped command-line text) proves the fix. See ConvertTo-QuotedArg's own comment
                # in Invoke-ReadOnlyAgent.ps1 for the (2k+1)-backslash formula this asserts.
                $repoRoot = Split-Path -Parent $here
                $realSchemaFile = Join-Path $repoRoot 'headless\schemas\pr-state-sweep.json'
                if (-not (Test-Path -LiteralPath $realSchemaFile -PathType Leaf)) {
                    throw "real schema fixture not found at $realSchemaFile"
                }
                $realContent = Get-Content -Raw -LiteralPath $realSchemaFile
                if ($realContent -notmatch [regex]::Escape('\"3h\"')) {
                    throw "expected the real schema to contain the pre-escaped 3h quote pattern this test relies on -- fixture assumption broke, update this test if pr-state-sweep.json's description text changed"
                }

                $priorSeam = $env:AEGIS_TEST_SEAM
                $priorEchoOut = $env:ECHO_OUT
                $echoOut = Join-Path $fixtureDir 'echoout-realschema.txt'
                $env:AEGIS_TEST_SEAM = '1'
                $env:ECHO_OUT = $echoOut
                try {
                    & $scriptPath -AgentName 'worktree-sweep' -Prompt 'irrelevant' -Restricted -JsonSchemaPath $realSchemaFile -ClaudePath $echoExe *>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE" }
                } finally {
                    $env:AEGIS_TEST_SEAM = $priorSeam
                    $env:ECHO_OUT = $priorEchoOut
                }
                $received = Get-EchoedArgs $echoOut
                $idx = [array]::IndexOf($received, '--json-schema')
                if ($idx -lt 0) { throw "--json-schema not found among received args: $($received -join ' | ')" }
                $schemaArg = $received[$idx + 1]
                if ($schemaArg -cne $realContent) {
                    throw "schema arg the child received does not match pr-state-sweep.json's raw bytes -- this is exactly the corruption the fix exists to prevent.`n received: [$schemaArg]`n expected: [$realContent]"
                }
                # And confirm the reconstructed argument itself still parses as valid JSON, matching
                # what the real claude.exe's own --json-schema parser must do with it.
                $null = $schemaArg | ConvertFrom-Json -ErrorAction Stop
            }

            Test-Case "resolution: the real (non-ClaudePath, non-DryRun) code path prefers a sibling claude.exe over claude.cmd" {
                # Fake npm install layout: <fakeNpm>\claude.cmd (would mangle the schema if launched)
                # plus <fakeNpm>\node_modules\@anthropic-ai\claude-code\bin\claude.exe (the echo
                # double) -- the exact relative path Invoke-ReadOnlyAgent.ps1's fix looks for, matching
                # claude.cmd's own real body ("%dp0%\node_modules\@anthropic-ai\claude-code\bin\claude.exe" %*).
                $fakeNpm = Join-Path $fixtureDir 'fakenpm-prefer-exe'
                $binDir = Join-Path $fakeNpm 'node_modules\@anthropic-ai\claude-code\bin'
                New-Item -ItemType Directory -Path $binDir -Force | Out-Null
                $fakeCmd = Join-Path $fakeNpm 'claude.cmd'
                $invokedMarker = Join-Path $fakeNpm 'cmd-was-invoked.txt'
                # This fake claude.cmd would prove it ran by writing a marker -- it must NEVER run, since
                # a sibling claude.exe exists and the fix must prefer it.
                [System.IO.File]::WriteAllText($fakeCmd, "@echo off`r`n(echo INVOKED)> `"$invokedMarker`"`r`nexit /b 0`r`n", [System.Text.Encoding]::ASCII)
                Copy-Item -LiteralPath $echoExe -Destination (Join-Path $binDir 'claude.exe') -Force

                $priorPath = $env:PATH
                $priorEchoOut = $env:ECHO_OUT
                $echoOut = Join-Path $fixtureDir 'echoout-prefer-exe.txt'
                $env:PATH = "$fakeNpm;$priorPath"
                $env:ECHO_OUT = $echoOut
                try {
                    & $scriptPath -AgentName 'worktree-sweep' -Prompt 'irrelevant' -Restricted -JsonSchemaPath $multilineSchemaFile *>&1 | Out-Null
                    $code = $LASTEXITCODE
                } finally {
                    $env:PATH = $priorPath
                    $env:ECHO_OUT = $priorEchoOut
                }
                if ($code -ne 0) { throw "expected exit 0, got $code" }
                if (Test-Path -LiteralPath $invokedMarker) { throw "claude.cmd was launched -- the fix must prefer the sibling claude.exe and never invoke the batch file at all" }
                $received = Get-EchoedArgs $echoOut
                if ($received.Count -eq 0) { throw "the native claude.exe was never launched (no argv captured) -- resolution did not prefer it" }
                $idx = [array]::IndexOf($received, '--json-schema')
                if ($idx -lt 0) { throw "--json-schema not found among received args: $($received -join ' | ')" }
                if ($received[$idx + 1] -cne $multilineSchemaContent) {
                    throw "schema arg the real resolution path launched does not match the raw file content byte-for-byte -- this is exactly the mangling the fix exists to prevent.`n received: [$($received[$idx + 1])]`n expected: [$multilineSchemaContent]"
                }
            }

            Test-Case "resolution: falls back to claude.cmd (old behaviour) and warns when no sibling claude.exe exists" {
                $fakeNpm = Join-Path $fixtureDir 'fakenpm-fallback'
                New-Item -ItemType Directory -Path $fakeNpm -Force | Out-Null
                $fakeCmd = Join-Path $fakeNpm 'claude.cmd'
                $invokedMarker = Join-Path $fakeNpm 'cmd-was-invoked.txt'
                [System.IO.File]::WriteAllText($fakeCmd, "@echo off`r`n(echo INVOKED)> `"$invokedMarker`"`r`nexit /b 0`r`n", [System.Text.Encoding]::ASCII)
                # Deliberately no node_modules\...\claude.exe next to it.

                $priorPath = $env:PATH
                $env:PATH = "$fakeNpm;$priorPath"
                try {
                    $out = & $scriptPath -AgentName 'worktree-sweep' -Prompt 'irrelevant' -Restricted -JsonSchemaPath $multilineSchemaFile *>&1 | Out-String -Width 4096
                    $code = $LASTEXITCODE
                } finally {
                    $env:PATH = $priorPath
                }
                if ($code -ne 0) { throw "expected exit 0, got $code. Output: $out" }
                if (-not (Test-Path -LiteralPath $invokedMarker)) { throw "expected claude.cmd to still run when no sibling claude.exe exists (old behaviour preserved). Output: $out" }
                if ($out -notmatch 'claude\.exe next to claude\.cmd') { throw "expected a warning naming the missing sibling claude.exe when -JsonSchemaPath is in play and only claude.cmd is found. Output: $out" }
            }
        }
    }
} finally {
    Remove-Item -Recurse -Force $fixtureDir -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "== Results: $testsPassed passed, $testsFailed failed ==" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host ""

if ($testsFailed -gt 0) { exit 1 } else { exit 0 }
