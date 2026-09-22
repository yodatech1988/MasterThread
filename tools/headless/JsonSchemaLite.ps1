<#
.SYNOPSIS
    Shared subset JSON Schema validator for the tools/headless/schemas/*.json files (plan task F4),
    factored out for plan task F12 so a wrapper can self-check a returned envelope against a schema
    without depending on tools/tests/test-headless-schemas.ps1's internals.

.DESCRIPTION
    Dot-source this file, then call Test-JsonSchemaLite -Value <parsed JSON> -Schema <parsed schema>.
    Returns an array of error strings; an empty array means the value is valid against the schema.

    This is deliberately the same subset tools/tests/test-headless-schemas.ps1 checks the F4 schemas
    stay inside (type, properties, required, additionalProperties: false, items, enum, const, anyOf)
    -- structured-outputs constraints like minimum/minLength/pattern are not part of that subset and
    are not implemented here either. The logic is a straight port of that test file's Get-SchemaErrors
    function (tools/tests/test-headless-schemas.ps1), not a rewrite -- kept in one place so a schema
    bug fixed in one validator does not silently diverge from the other. Existing tests for the F4
    schemas were not touched by this file; test-headless-schemas.ps1 keeps its own copy inline and is
    unmodified by this change.

.NOTES
    Not a general-purpose JSON Schema implementation. Do not extend it with keywords the F4 schemas
    do not use without also updating test-headless-schemas.ps1's $allowedKeywords list, or the two
    validators will silently accept different things.
#>

function Test-JsonSchemaLiteHasProp($Obj, [string]$Name) {
    return [bool]($Obj -is [pscustomobject] -and $Obj.PSObject.Properties[$Name])
}

function Test-JsonSchemaLiteGetProp($Obj, [string]$Name) {
    # Set-StrictMode-safe read: $null when absent. The unary comma keeps a one-element array a real
    # array on the way out rather than being unrolled into a scalar.
    $p = $Obj.PSObject.Properties[$Name]
    if ($p) { return , $p.Value }
    return $null
}

function Test-JsonSchemaLite {
    <#
    .PARAMETER Value
        A value already parsed by ConvertFrom-Json (a [pscustomobject], array, string, etc.).
    .PARAMETER Schema
        The schema, already parsed by ConvertFrom-Json.
    .OUTPUTS
        string[] of error messages. Empty = valid.
    #>
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)]$Schema,
        [string]$Path = '$'
    )

    $errors = New-Object System.Collections.Generic.List[string]

    if (Test-JsonSchemaLiteHasProp $Schema 'anyOf') {
        $ok = $false
        foreach ($branch in (Test-JsonSchemaLiteGetProp $Schema 'anyOf')) {
            if ((Test-JsonSchemaLite -Value $Value -Schema $branch -Path $Path).Count -eq 0) { $ok = $true; break }
        }
        if (-not $ok) { $errors.Add("$Path matches no anyOf branch") }
        return , $errors
    }

    if (Test-JsonSchemaLiteHasProp $Schema 'type') {
        $type = Test-JsonSchemaLiteGetProp $Schema 'type'
        $typeOk = switch ($type) {
            'object'  { $Value -is [pscustomobject] }
            'array'   { $Value -is [array] }
            'string'  { $Value -is [string] }
            'integer' { ($Value -is [int]) -or ($Value -is [long]) }
            'number'  { ($Value -is [int]) -or ($Value -is [long]) -or ($Value -is [double]) -or ($Value -is [decimal]) }
            'boolean' { $Value -is [bool] }
            'null'    { $null -eq $Value }
            default   { throw "Test-JsonSchemaLite: unsupported type '$type' at $Path" }
        }
        if (-not $typeOk) {
            $errors.Add("$Path expected $type")
            return , $errors
        }
    }

    if (Test-JsonSchemaLiteHasProp $Schema 'const') {
        $c = Test-JsonSchemaLiteGetProp $Schema 'const'
        if (($null -eq $Value) -or ($Value.GetType() -ne $c.GetType() -and -not (($Value -is [long] -or $Value -is [int]) -and ($c -is [long] -or $c -is [int]))) -or ($Value -cne $c)) {
            $errors.Add("$Path expected const '$c'")
        }
    }

    if (Test-JsonSchemaLiteHasProp $Schema 'enum') {
        if (-not ((Test-JsonSchemaLiteGetProp $Schema 'enum') -ccontains $Value)) { $errors.Add("$Path value '$Value' not in enum") }
    }

    if ($Value -is [pscustomobject]) {
        $props = Test-JsonSchemaLiteGetProp $Schema 'properties'
        foreach ($req in (Test-JsonSchemaLiteGetProp $Schema 'required')) {
            if ($req -and -not (Test-JsonSchemaLiteHasProp $Value $req)) { $errors.Add("$Path missing required '$req'") }
        }
        if ((Test-JsonSchemaLiteHasProp $Schema 'additionalProperties') -and ((Test-JsonSchemaLiteGetProp $Schema 'additionalProperties') -eq $false)) {
            foreach ($p in $Value.PSObject.Properties) {
                if (-not ($props -and $props.PSObject.Properties[$p.Name])) { $errors.Add("$Path has unexpected property '$($p.Name)'") }
            }
        }
        if ($props) {
            foreach ($sp in $props.PSObject.Properties) {
                if (Test-JsonSchemaLiteHasProp $Value $sp.Name) {
                    foreach ($e in (Test-JsonSchemaLite -Value (Test-JsonSchemaLiteGetProp $Value $sp.Name) -Schema $sp.Value -Path "$Path.$($sp.Name)")) { $errors.Add($e) }
                }
            }
        }
    }

    if (($Value -is [array]) -and (Test-JsonSchemaLiteHasProp $Schema 'items')) {
        $i = 0
        foreach ($item in $Value) {
            foreach ($e in (Test-JsonSchemaLite -Value $item -Schema (Test-JsonSchemaLiteGetProp $Schema 'items') -Path "$Path[$i]")) { $errors.Add($e) }
            $i++
        }
    }

    return , $errors
}
