<#
.SYNOPSIS
  Regression tests for plan task F4: one --json-schema per L1 reporter under tools/headless/schemas/.

.DESCRIPTION
  Static only: nothing here launches `claude` or spends budget. Checks, for every schema file:

  - The set of schema files is exactly the L1 reporter agents named in
    standards/sessions/headless_readiness_ladder.md's L1 row (check_agent_sync.py is a script, not a
    `claude -p --agent` reporter, so it has no schema). A reporter added to or dropped from the ladder
    without a matching schema change fails here.
  - Each schema names a real agent (claude-agents/<name>.md exists and roster_meta.json lists it) and
    pins `agent` to that name with `const`.
  - Each schema stays inside the JSON Schema subset Claude structured outputs accepts (no minimum,
    minLength, pattern, minItems, ...; every object `additionalProperties: false`), and every object
    lists all its properties in `required` (optional values are expressed as anyOf [x, null], so the
    model always has to state them, even as null).
  - Every schema carries `findings` (the plan's findings[] contract) and `couldNotCheck`, so a run that
    could not reach something has a place to say so instead of being forced into a clean-looking answer.
  - A valid fixture per agent (tools/tests/fixtures/headless/schemas/<name>.valid.json) is ACCEPTED,
    and five deliberate mutations of it (missing required key, wrong type, extra key, bad enum value,
    missing nested required key) are each REJECTED -- the schema is neither too loose nor mismatched.

  Validation runs twice where possible: a small in-file validator for the subset above (no dependency,
  runs anywhere Windows PowerShell 5.1 does), and a cross-check with Python's `jsonschema` package
  (Draft 2020-12), skipped with [SKIP] when Python or the package is missing.

  NOT covered here: whether `claude -p --json-schema` accepts these exact files live. That needs a
  real CLI run, which this suite deliberately does not make.
#>
param()

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $here)
$schemaDir = Join-Path $repoRoot 'tools\headless\schemas'
$fixtureDir = Join-Path $here 'fixtures\headless\schemas'
$ladderPath = Join-Path $repoRoot 'standards\sessions\headless_readiness_ladder.md'
$rosterPath = Join-Path $repoRoot 'claude-agents\roster_meta.json'
$agentsDir = Join-Path $repoRoot 'claude-agents'

$testsPassed = 0
$testsFailed = 0
$testsSkipped = 0

# Parameter names deliberately differ from the loop variables below ($name, $schema, ...): the test
# script blocks are dynamically scoped, so a Test-Case parameter called $name would shadow the
# caller's $name inside every block.
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

function Read-Json([string]$Path) {
    return ([System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json)
}

function Get-Prop($Obj, [string]$Name) {
    # Set-StrictMode-safe read (tools/README.md): $null when absent. The unary comma returns an array
    # value as ONE object, so a one-element array is not unrolled into a scalar on the way out; call
    # sites therefore never wrap the result in @().
    $p = $Obj.PSObject.Properties[$Name]
    if ($p) { return , $p.Value }
    return $null
}

function Test-HasProp($Obj, [string]$Name) {
    return [bool]($Obj -is [pscustomobject] -and $Obj.PSObject.Properties[$Name])
}

# --- Subset validator -----------------------------------------------------------------------------
# Implements exactly the keywords the schemas use: type, properties, required, additionalProperties
# (false only), items, enum, const, anyOf. Returns a list of error strings; empty = valid.
function Get-SchemaErrors($Value, $Schema, [string]$Path = '$') {
    $errors = New-Object System.Collections.Generic.List[string]

    if (Test-HasProp $Schema 'anyOf') {
        $ok = $false
        foreach ($branch in (Get-Prop $Schema 'anyOf')) {
            if ((Get-SchemaErrors $Value $branch $Path).Count -eq 0) { $ok = $true; break }
        }
        if (-not $ok) { $errors.Add("$Path matches no anyOf branch") }
        return , $errors
    }

    if (Test-HasProp $Schema 'type') {
        $type = Get-Prop $Schema 'type'
        $typeOk = switch ($type) {
            'object'  { $Value -is [pscustomobject] }
            'array'   { $Value -is [array] }
            'string'  { $Value -is [string] }
            'integer' { ($Value -is [int]) -or ($Value -is [long]) }
            'number'  { ($Value -is [int]) -or ($Value -is [long]) -or ($Value -is [double]) -or ($Value -is [decimal]) }
            'boolean' { $Value -is [bool] }
            'null'    { $null -eq $Value }
            default   { throw "validator: unsupported type '$type' at $Path" }
        }
        if (-not $typeOk) {
            $errors.Add("$Path expected $type")
            return , $errors
        }
    }

    if (Test-HasProp $Schema 'const') {
        $c = Get-Prop $Schema 'const'
        if (($null -eq $Value) -or ($Value.GetType() -ne $c.GetType() -and -not (($Value -is [long] -or $Value -is [int]) -and ($c -is [long] -or $c -is [int]))) -or ($Value -cne $c)) {
            $errors.Add("$Path expected const '$c'")
        }
    }

    if (Test-HasProp $Schema 'enum') {
        if (-not ((Get-Prop $Schema 'enum') -ccontains $Value)) { $errors.Add("$Path value '$Value' not in enum") }
    }

    if ($Value -is [pscustomobject]) {
        $props = Get-Prop $Schema 'properties'
        foreach ($req in (Get-Prop $Schema 'required')) {
            if ($req -and -not (Test-HasProp $Value $req)) { $errors.Add("$Path missing required '$req'") }
        }
        if ((Test-HasProp $Schema 'additionalProperties') -and ((Get-Prop $Schema 'additionalProperties') -eq $false)) {
            foreach ($p in $Value.PSObject.Properties) {
                if (-not ($props -and $props.PSObject.Properties[$p.Name])) { $errors.Add("$Path has unexpected property '$($p.Name)'") }
            }
        }
        if ($props) {
            foreach ($sp in $props.PSObject.Properties) {
                if (Test-HasProp $Value $sp.Name) {
                    foreach ($e in (Get-SchemaErrors (Get-Prop $Value $sp.Name) $sp.Value "$Path.$($sp.Name)")) { $errors.Add($e) }
                }
            }
        }
    }

    if (($Value -is [array]) -and (Test-HasProp $Schema 'items')) {
        $i = 0
        foreach ($item in $Value) {
            foreach ($e in (Get-SchemaErrors $item (Get-Prop $Schema 'items') "$Path[$i]")) { $errors.Add($e) }
            $i++
        }
    }

    return , $errors
}

# Keywords the schemas may use. Everything here is inside the structured-outputs subset; the notable
# exclusions are numeric/string/array constraints (minimum, minLength, minItems, pattern, ...), which
# structured outputs does not enforce.
$allowedKeywords = @('title', 'description', 'type', 'properties', 'required', 'additionalProperties', 'items', 'enum', 'const', 'anyOf')

function Get-SchemaStructureErrors($Node, [string]$Path) {
    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($p in $Node.PSObject.Properties) {
        if ($allowedKeywords -cnotcontains $p.Name) { $errors.Add("$Path uses keyword '$($p.Name)' outside the allowed subset") }
    }
    if ((Get-Prop $Node 'type') -eq 'object') {
        if ((Get-Prop $Node 'additionalProperties') -ne $false -or -not (Test-HasProp $Node 'additionalProperties')) {
            $errors.Add("$Path object lacks additionalProperties: false")
        }
        $names = @()
        $props = Get-Prop $Node 'properties'
        if ($props) { $names = @($props.PSObject.Properties | ForEach-Object { $_.Name }) }
        $req = (Get-Prop $Node 'required')
        foreach ($n in $names) { if ($req -cnotcontains $n) { $errors.Add("$Path property '$n' is not in required") } }
        foreach ($r in $req) { if ($r -and $names -cnotcontains $r) { $errors.Add("$Path requires undeclared '$r'") } }
        if ($props) {
            foreach ($sp in $props.PSObject.Properties) { foreach ($e in (Get-SchemaStructureErrors $sp.Value "$Path.$($sp.Name)")) { $errors.Add($e) } }
        }
    }
    if (Test-HasProp $Node 'items') { foreach ($e in (Get-SchemaStructureErrors (Get-Prop $Node 'items') "$Path[]")) { $errors.Add($e) } }
    if (Test-HasProp $Node 'anyOf') {
        $k = 0
        foreach ($b in (Get-Prop $Node 'anyOf')) { foreach ($e in (Get-SchemaStructureErrors $b "$Path.anyOf[$k]")) { $errors.Add($e) }; $k++ }
    }
    return , $errors
}

# The five mutations. Each returns a freshly parsed, mutated copy of the fixture text.
function New-Mutations([string]$FixtureText) {
    $m = [ordered]@{}

    $o = $FixtureText | ConvertFrom-Json
    $o.PSObject.Properties.Remove('findings')
    $m['missing required root key (findings)'] = $o

    $o = $FixtureText | ConvertFrom-Json
    $o.findings = 'none'
    $m['wrong type (findings is a string, not an array)'] = $o

    $o = $FixtureText | ConvertFrom-Json
    $o | Add-Member -NotePropertyName 'verdict' -NotePropertyValue 'looks fine'
    $m['extra root key (verdict)'] = $o

    $o = $FixtureText | ConvertFrom-Json
    $o.findings = @([pscustomobject]@{ kind = 'not-a-real-kind'; subject = 'x'; detail = 'y' })
    $m['bad enum value (findings[0].kind)'] = $o

    $o = $FixtureText | ConvertFrom-Json
    $o.findings = @([pscustomobject]@{ kind = (Get-Prop $o 'findings')[0].kind; subject = 'x' })
    $m['missing nested required key (findings[0].detail)'] = $o

    return $m
}

Write-Host ""
Write-Host "== F4 regression tests: tools/headless/schemas (one --json-schema per L1 reporter)" -ForegroundColor Cyan
Write-Host ""

# --- Validator self-checks (so a validator bug cannot make every schema test pass) ----------------
Test-Case "validator self-check: rejects wrong type, missing key, extra key, bad enum, bad const; accepts anyOf null" {
    $s = '{"type":"object","properties":{"a":{"type":"integer"},"b":{"anyOf":[{"type":"string"},{"type":"null"}]},"c":{"type":"string","enum":["x","y"]},"d":{"type":"string","const":"k"}},"required":["a","b","c","d"],"additionalProperties":false}' | ConvertFrom-Json
    if ((Get-SchemaErrors ('{"a":1,"b":null,"c":"x","d":"k"}' | ConvertFrom-Json) $s).Count -ne 0) { throw 'valid object rejected' }
    if ((Get-SchemaErrors ('{"a":1,"b":"s","c":"y","d":"k"}' | ConvertFrom-Json) $s).Count -ne 0) { throw 'valid object (b as string) rejected' }
    $bad = @(
        '{"a":"1","b":null,"c":"x","d":"k"}',
        '{"a":1.5,"b":null,"c":"x","d":"k"}',
        '{"b":null,"c":"x","d":"k"}',
        '{"a":1,"b":null,"c":"x","d":"k","e":1}',
        '{"a":1,"b":null,"c":"z","d":"k"}',
        '{"a":1,"b":null,"c":"X","d":"k"}',
        '{"a":1,"b":null,"c":"x","d":"K"}',
        '{"a":1,"b":5,"c":"x","d":"k"}'
    )
    foreach ($t in $bad) {
        if ((Get-SchemaErrors ($t | ConvertFrom-Json) $s).Count -eq 0) { throw "invalid object accepted: $t" }
    }
}

# --- JsonSchemaLite.ps1 regression (issue #206, Fix B) --------------------------------------------
# tools/headless/JsonSchemaLite.ps1 is the shared module Invoke-Subagent.ps1:297-349 dot-sources and
# calls Test-JsonSchemaLite against (this test file's Get-SchemaErrors above is a separate, unrelated
# in-file copy used only for the F4 schema regressions and is not touched by Fix B). Before Fix B,
# Test-JsonSchemaLite's -Value parameter was [Parameter(Mandatory = $true)] with no [AllowNull()], so
# a JSON `null` value -- legal wherever a schema says "type":"null" or a property is nullable --
# failed PowerShell parameter binding (a terminating error, or an interactive prompt) instead of
# reaching the 'null' branch of the type switch. These tests dot-source the REAL module (not the
# in-file copy above) so a fix here is evidence for what Invoke-Subagent.ps1 actually calls.
. (Join-Path $repoRoot 'tools\headless\JsonSchemaLite.ps1')

Test-Case "JsonSchemaLite: top-level null against type null is VALID (no exception, no errors)" {
    $schema = '{"type":"null"}' | ConvertFrom-Json
    $errs = Test-JsonSchemaLite -Value $null -Schema $schema
    if ($errs.Count -ne 0) { throw "expected zero errors, got: $($errs -join '; ')" }
}

Test-Case "JsonSchemaLite: top-level null against type string is INVALID (error message, not an exception)" {
    $schema = '{"type":"string"}' | ConvertFrom-Json
    $errs = Test-JsonSchemaLite -Value $null -Schema $schema
    if ($errs.Count -eq 0) { throw 'expected a type-mismatch error, got none' }
    if ($errs[0] -notmatch 'expected string') { throw "expected an 'expected string' message, got: $($errs[0])" }
}

Test-Case "JsonSchemaLite: nested null property (anyOf [string, null], value null) is VALID" {
    $schema = '{"type":"object","properties":{"a":{"anyOf":[{"type":"string"},{"type":"null"}]}},"required":["a"],"additionalProperties":false}' | ConvertFrom-Json
    $value = '{"a":null}' | ConvertFrom-Json
    $errs = Test-JsonSchemaLite -Value $value -Schema $schema
    if ($errs.Count -ne 0) { throw "expected zero errors, got: $($errs -join '; ')" }
}

Test-Case "JsonSchemaLite: nested null property against a non-nullable string type is INVALID (no exception)" {
    $schema = '{"type":"object","properties":{"a":{"type":"string"}},"required":["a"],"additionalProperties":false}' | ConvertFrom-Json
    $value = '{"a":null}' | ConvertFrom-Json
    $errs = Test-JsonSchemaLite -Value $value -Schema $schema
    if ($errs.Count -eq 0) { throw 'expected a type-mismatch error for the null property, got none' }
    if ($errs[0] -notmatch '\$\.a expected string') { throw "expected a '`$.a expected string' message, got: $($errs[0])" }
}

Test-Case "schemas directory exists" {
    if (-not (Test-Path -LiteralPath $schemaDir -PathType Container)) { throw "not found: $schemaDir" }
}

$schemaFiles = @()
if (Test-Path -LiteralPath $schemaDir) { $schemaFiles = @(Get-ChildItem -LiteralPath $schemaDir -Filter '*.json' | Sort-Object Name) }
$schemaNames = @($schemaFiles | ForEach-Object { $_.BaseName })

Test-Case "schema set == the L1 reporter agents named in headless_readiness_ladder.md" {
    $ladder = [System.IO.File]::ReadAllText($ladderPath)
    $row = ($ladder -split "`n") | Where-Object { $_ -like '| **L1 Reporters**|*' -or $_ -like '| **L1 Reporters** |*' } | Select-Object -First 1
    if (-not $row) { throw "L1 Reporters row not found in $ladderPath" }
    $inParens = [regex]::Match($row, 'Read-only Haiku reporters \(([^)]*)\)')
    if (-not $inParens.Success) { throw "could not find the reporter list '(...)' in the L1 row" }
    $named = @([regex]::Matches($inParens.Groups[1].Value, '`([^`]+)`') | ForEach-Object { $_.Groups[1].Value })
    $agents = @($named | Where-Object { $_ -notmatch '\.(py|ps1)$' } | Sort-Object)
    if ($agents.Count -lt 1) { throw 'no agents parsed from the L1 row' }
    $diff = Compare-Object -ReferenceObject $agents -DifferenceObject @($schemaNames | Sort-Object)
    if ($diff) { throw "mismatch (<= ladder only, => schema only): $(($diff | ForEach-Object { "$($_.SideIndicator)$($_.InputObject)" }) -join ', ')" }
}

$roster = Read-Json $rosterPath

foreach ($file in $schemaFiles) {
    $name = $file.BaseName
    $schema = $null

    Test-Case "[$name] parses as JSON" {
        $script:schema = Read-Json $file.FullName
        if (-not ($script:schema -is [pscustomobject])) { throw 'root is not an object' }
    }
    $schema = $script:schema
    if (-not $schema) { continue }

    Test-Case "[$name] names a real agent: claude-agents/$name.md exists and roster_meta.json lists it; agent is const '$name'" {
        if (-not (Test-Path -LiteralPath (Join-Path $agentsDir "$name.md"))) { throw "claude-agents/$name.md not found" }
        if (-not $roster.PSObject.Properties[$name]) { throw "roster_meta.json has no '$name' entry" }
        $agentProp = Get-Prop (Get-Prop $schema 'properties') 'agent'
        if (-not $agentProp -or (Get-Prop $agentProp 'const') -cne $name) { throw "properties.agent.const is not '$name'" }
    }

    Test-Case "[$name] stays in the structured-outputs subset; every object is closed and fully required" {
        $errs = Get-SchemaStructureErrors $schema '$'
        if ($errs.Count -gt 0) { throw ($errs -join '; ') }
        if ((Get-Prop $schema 'type') -ne 'object') { throw 'root type is not object' }
    }

    Test-Case "[$name] carries findings[] and couldNotCheck[] at the root" {
        $props = Get-Prop $schema 'properties'
        foreach ($k in @('findings', 'couldNotCheck')) {
            $p = Get-Prop $props $k
            if (-not $p -or (Get-Prop $p 'type') -ne 'array') { throw "root '$k' missing or not an array" }
        }
        $kinds = Get-Prop (Get-Prop (Get-Prop (Get-Prop $props 'findings') 'items') 'properties') 'kind'
        if (-not $kinds -or (Get-Prop $kinds 'enum').Count -lt 1) { throw 'findings[].kind has no enum' }
    }

    $fixturePath = Join-Path $fixtureDir "$name.valid.json"
    Test-Case "[$name] valid fixture is ACCEPTED" {
        if (-not (Test-Path -LiteralPath $fixturePath)) { throw "fixture not found: $fixturePath" }
        $errs = Get-SchemaErrors (Read-Json $fixturePath) $schema
        if ($errs.Count -gt 0) { throw ($errs -join '; ') }
    }

    if (Test-Path -LiteralPath $fixturePath) {
        $fixtureText = [System.IO.File]::ReadAllText($fixturePath)
        $mutations = New-Mutations $fixtureText
        foreach ($label in $mutations.Keys) {
            $mutated = $mutations[$label]
            Test-Case "[$name] mutation REJECTED: $label" {
                if ((Get-SchemaErrors $mutated $schema).Count -eq 0) { throw 'mutated copy was accepted' }
            }
        }
    }
}

# --- Cross-check with Python jsonschema (independent implementation) -------------------------------
$python = Get-Command 'python' -ErrorAction SilentlyContinue
$haveJsonschema = $false
if ($python) {
    & $python.Source -c 'import jsonschema' 2>$null
    $haveJsonschema = ($LASTEXITCODE -eq 0)
}
if ($haveJsonschema) {
    Test-Case "python jsonschema (Draft 2020-12): every schema is a valid schema, every fixture accepted, the same five mutations rejected" {
        $py = @'
import copy, glob, json, os, sys
import jsonschema
schema_dir, fixture_dir = sys.argv[1], sys.argv[2]
bad = []
for path in sorted(glob.glob(os.path.join(schema_dir, "*.json"))):
    name = os.path.basename(path)[:-5]
    schema = json.load(open(path, encoding="utf-8"))
    jsonschema.Draft202012Validator.check_schema(schema)
    v = jsonschema.Draft202012Validator(schema)
    fx = json.load(open(os.path.join(fixture_dir, name + ".valid.json"), encoding="utf-8"))
    errs = list(v.iter_errors(fx))
    if errs:
        bad.append(name + ": valid fixture rejected: " + errs[0].message)
    kind = schema["properties"]["findings"]["items"]["properties"]["kind"]["enum"][0]
    muts = []
    m = copy.deepcopy(fx); del m["findings"]; muts.append(("missing findings", m))
    m = copy.deepcopy(fx); m["findings"] = "none"; muts.append(("wrong type", m))
    m = copy.deepcopy(fx); m["verdict"] = "looks fine"; muts.append(("extra key", m))
    m = copy.deepcopy(fx); m["findings"] = [{"kind": "not-a-real-kind", "subject": "x", "detail": "y"}]; muts.append(("bad enum", m))
    m = copy.deepcopy(fx); m["findings"] = [{"kind": kind, "subject": "x"}]; muts.append(("missing nested", m))
    for label, mm in muts:
        if v.is_valid(mm):
            bad.append(name + ": mutation accepted: " + label)
print("\n".join(bad) if bad else "OK")
sys.exit(1 if bad else 0)
'@
        $pyFile = Join-Path ([System.IO.Path]::GetTempPath()) ("f4-schema-check-" + [Guid]::NewGuid().ToString('N') + '.py')
        [System.IO.File]::WriteAllText($pyFile, $py, [System.Text.UTF8Encoding]::new($false))
        try {
            $out = & $python.Source $pyFile $schemaDir $fixtureDir 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) { throw "python check failed: $out" }
        } finally {
            Remove-Item -LiteralPath $pyFile -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Host "[SKIP] python jsonschema cross-check (python or the jsonschema package is not installed)" -ForegroundColor Yellow
    $testsSkipped++
}

Write-Host ""
Write-Host "== Results: $testsPassed passed, $testsFailed failed, $testsSkipped skipped ==" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host ""

if ($testsFailed -gt 0) { exit 1 } else { exit 0 }
