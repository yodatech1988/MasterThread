<#
.SYNOPSIS
  Regression tests for plan task F12's -JsonSchemaPath addition to Invoke-ReadOnlyAgent.ps1.

.DESCRIPTION
  Static only, following tools/tests/test-invoke-readonly-agent-restricted.ps1's own seam
  conventions (-DryRun, throwaway fixtures, no `claude` needed). Proves the new parameter is
  additive: a caller that never passes -JsonSchemaPath gets byte-identical behaviour to before this
  parameter existed, and a caller that does pass it gets --json-schema threaded through with the
  schema FILE'S CONTENT (not its path -- fixed 2026-09-22, QA/PR #197 comments: the CLI's
  --json-schema flag expects the content, and a path string made the CLI fail during its own
  argument/schema parsing before ever reaching the API), or a fail-closed refusal for a
  missing/unsafe file, before anything is launched.
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
$schemaFile = Join-Path $fixtureDir 'fixture.json'
'{"type":"object","properties":{"a":{"type":"string"}},"required":["a"],"additionalProperties":false}' | Set-Content -Path $schemaFile -Encoding utf8

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

    Test-Case "-JsonSchemaPath pointing at a missing file is refused (exit 2), nothing launched" {
        & $scriptPath -AgentName 'worktree-sweep' -Prompt 'irrelevant' -Restricted -JsonSchemaPath (Join-Path $fixtureDir 'does-not-exist.json') -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 2) { throw "expected exit 2, got $LASTEXITCODE" }
    }

    Test-Case "-JsonSchemaPath containing an unsafe character is refused (exit 2), nothing launched" {
        $unsafe = Join-Path $fixtureDir 'has"quote.json'
        & $scriptPath -AgentName 'worktree-sweep' -Prompt 'irrelevant' -Restricted -JsonSchemaPath $unsafe -DryRun 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 2) { throw "expected exit 2, got $LASTEXITCODE" }
    }

    Test-Case "-JsonSchemaPath works alongside a non-restricted -Tools call too" {
        $out = & $scriptPath -AgentName 'diff-reviewer' -Prompt 'irrelevant' -Tools 'Bash' -JsonSchemaPath $schemaFile -DryRun *>&1 | Out-String -Width 4096
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE. Output: $out" }
        if ($out -notmatch [regex]::Escape('--json-schema')) { throw "expected --json-schema in built args. Output: $out" }
        $schemaContent = Get-Content -Raw -LiteralPath $schemaFile
        $escapedContent = $schemaContent -replace '"', '\"'
        if ($out -notmatch [regex]::Escape($escapedContent)) { throw "expected the schema file's CONTENT (not its path) in built args. Output: $out" }
    }
} finally {
    Remove-Item -Recurse -Force $fixtureDir -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "== Results: $testsPassed passed, $testsFailed failed ==" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host ""

if ($testsFailed -gt 0) { exit 1 } else { exit 0 }
