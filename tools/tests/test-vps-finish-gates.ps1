<#
.SYNOPSIS
  Static tests for AEGIS-VPS-Finish click-file gate logic.
  Tests that: YES gate present, -WhatIf parameter exists, undo files exist, cloudflared/pm2 are not at module level.
#>
param(
    [switch]$Verbose
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$clickFilesDir = Join-Path (Split-Path -Parent $here) 'click-files'

$testsPassed = 0
$testsFailed = 0

function Test-Case($name, $scriptBlock) {
    try {
        & $scriptBlock
        Write-Host "[PASS] $name" -ForegroundColor Green
        $global:testsPassed++
    } catch {
        Write-Host "[FAIL] $name`: $($_.Exception.Message)" -ForegroundColor Red
        $global:testsFailed++
    }
}

Write-Host ""
Write-Host "== Static tests for AEGIS-VPS-Finish gates" -ForegroundColor Cyan
Write-Host ""

# Test 1: Files exist
Test-Case "AEGIS-VPS-Finish.ps1 exists" {
    if (-not (Test-Path (Join-Path $clickFilesDir 'AEGIS-VPS-Finish.ps1'))) {
        throw "File not found"
    }
}

Test-Case "AEGIS-VPS-Finish.cmd exists" {
    if (-not (Test-Path (Join-Path $clickFilesDir 'AEGIS-VPS-Finish.cmd'))) {
        throw "File not found"
    }
}

Test-Case "zz-UNDO-AEGIS-VPS-Finish.ps1 exists" {
    if (-not (Test-Path (Join-Path $clickFilesDir 'zz-UNDO-AEGIS-VPS-Finish.ps1'))) {
        throw "File not found"
    }
}

Test-Case "zz-UNDO-AEGIS-VPS-Finish.cmd exists" {
    if (-not (Test-Path (Join-Path $clickFilesDir 'zz-UNDO-AEGIS-VPS-Finish.cmd'))) {
        throw "File not found"
    }
}

# Test 2: Undo files in same folder
Test-Case "Undo files in same click-files folder as main scripts" {
    $undoPath = (Get-ChildItem (Join-Path $clickFilesDir 'zz-UNDO-AEGIS-VPS-Finish.ps1')).FullName
    $mainPath = (Get-ChildItem (Join-Path $clickFilesDir 'AEGIS-VPS-Finish.ps1')).FullName
    if ((Split-Path -Parent $undoPath) -ne (Split-Path -Parent $mainPath)) {
        throw "Undo files not in same folder"
    }
}

# Test 3: YES gate
Test-Case "YES gate is case-sensitive (-cne) so yes/Yes are refused" {
    $content = Get-Content (Join-Path $clickFilesDir 'AEGIS-VPS-Finish.ps1') -Raw
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $clickFilesDir 'AEGIS-VPS-Finish.ps1'), [ref]$null, [ref]$null)
    $cmp = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.BinaryExpressionAst] -and $n.Left.Extent.Text -eq '$confirm' -and $n.Right.Extent.Text -eq '"YES"' }, $true)
    if (-not $cmp) { throw "No comparison of `$confirm against YES found" }
    foreach ($b in $cmp) { if ("$($b.Operator)" -ne 'Cne') { throw "Gate uses $($b.Operator); must be -cne so yes/Yes are refused" } }
}

Test-Case "YES gate has Read-Host prompt" {
    $content = Get-Content (Join-Path $clickFilesDir 'AEGIS-VPS-Finish.ps1') -Raw
    if ($content -notmatch 'Read-Host.*Type YES') {
        throw "No Read-Host prompt found for YES gate"
    }
}

Test-Case "YES gate exits on wrong input" {
    $content = Get-Content (Join-Path $clickFilesDir 'AEGIS-VPS-Finish.ps1') -Raw
    if ($content -notmatch 'exit 0') {
        throw "No exit statement found for wrong input"
    }
}

# Test 4: -WhatIf parameter defined
Test-Case "-WhatIf parameter is defined as switch" {
    $content = Get-Content (Join-Path $clickFilesDir 'AEGIS-VPS-Finish.ps1') -Raw
    if ($content -notmatch '\[switch\]\$WhatIf') {
        throw "-WhatIf switch not found in param block"
    }
}

# Test 5: Mutating calls have guard markers (not necessarily all in same guard, but pattern exists)
Test-Case "Script has if/else structure for WhatIf guard" {
    $content = Get-Content (Join-Path $clickFilesDir 'AEGIS-VPS-Finish.ps1') -Raw
    if ($content -notmatch 'if\s*\(\s*\$WhatIf\s*\)') {
        throw "No if(\$WhatIf) guard found"
    }
}

Test-Case "Cloudflared call present in script" {
    $content = Get-Content (Join-Path $clickFilesDir 'AEGIS-VPS-Finish.ps1') -Raw
    if ($content -notmatch '\$cf.*tunnel.*route.*dns') {
        throw "cloudflared tunnel route dns call not found"
    }
}

Test-Case "PM2 call present in script" {
    $content = Get-Content (Join-Path $clickFilesDir 'AEGIS-VPS-Finish.ps1') -Raw
    if ($content -notmatch 'node.*\$pm2') {
        throw "pm2 call not found"
    }
}

# Test 5b: AST check - every mutating call is inside the ELSE of `if ($WhatIf)`, never in the WhatIf branch
Test-Case "Mutating calls (cloudflared, pm2, push, Add-Content) only run when -WhatIf is off" {
    $path = Join-Path $clickFilesDir 'AEGIS-VPS-Finish.ps1'
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
    if ($errs.Count) { throw "Parse errors: $($errs[0].Message)" }
    $mutating = $ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.CommandAst] -and (
            ($n.InvocationOperator -eq 'Ampersand' -and $n.CommandElements[0].Extent.Text -match '^\$(cf|pm2|push)$') -or
            ($n.GetCommandName() -in @('node', 'Add-Content', 'Set-Content', 'Remove-Item', 'Out-File')))
    }, $true)
    if ($mutating.Count -lt 4) { throw "Expected at least 4 mutating calls, found $($mutating.Count)" }
    foreach ($m in $mutating) {
        $guarded = $false
        for ($p2 = $m.Parent; $p2; $p2 = $p2.Parent) {
            if ($p2 -is [System.Management.Automation.Language.IfStatementAst]) {
                foreach ($cl in $p2.Clauses) {
                    if ($cl.Item1.Extent.Text -match '^\$WhatIf$' -and $cl.Item2.Extent.StartOffset -le $m.Extent.StartOffset -and $m.Extent.EndOffset -le $cl.Item2.Extent.EndOffset) {
                        throw "Mutating call inside the -WhatIf branch: $($m.Extent.Text)"
                    }
                }
                if ($p2.ElseClause -and $p2.Clauses[0].Item1.Extent.Text -match '^\$WhatIf$' -and $p2.ElseClause.Extent.StartOffset -le $m.Extent.StartOffset -and $m.Extent.EndOffset -le $p2.ElseClause.Extent.EndOffset) { $guarded = $true }
                if ($p2.Clauses[0].Item1.Extent.Text -match '^-not \$WhatIf$|^!\$WhatIf$') { $guarded = $true }
            }
        }
        if (-not $guarded) { throw "Mutating call not guarded by -WhatIf: $($m.Extent.Text)" }
    }
}

# Test 5c: the YES gate comes before any mutating call
Test-Case "YES gate (exit on non-YES) precedes the first mutating call" {
    $content = Get-Content (Join-Path $clickFilesDir 'AEGIS-VPS-Finish.ps1') -Raw
    $gate = $content.IndexOf('-cne "YES"')
    $first = $content.IndexOf('--overwrite-dns')
    if ($gate -lt 0 -or $first -lt 0 -or $gate -gt $first) { throw "Gate does not precede the first mutating call" }
}
# Test 6: PushVpsSecrets path corrected
Test-Case "PushVpsSecrets.ps1 path corrected to services/tools (not dead worktree)" {
    $content = Get-Content (Join-Path $clickFilesDir 'AEGIS-VPS-Finish.ps1') -Raw
    if ($content -match '_wt-services-ovh-migration') {
        throw "Dead worktree path still in script"
    }
    if ($content -notmatch 'services\\tools\\PushVpsSecrets') {
        throw "Corrected path to services/tools not found"
    }
}

# Test: gate text names every action the single YES authorises
Test-Case "Gate text names DNS, pm2 stop and PushVpsSecrets" {
    $content = Get-Content (Join-Path $clickFilesDir 'AEGIS-VPS-Finish.ps1') -Raw
    foreach ($needle in @('Overwrites the DNS', 'stops the PC copy', 'PushVpsSecrets.ps1')) {
        if ($content -notmatch [regex]::Escape($needle)) { throw "Gate text does not mention: $needle" }
    }
}

# Test: all five files are LF-only
Test-Case "All five files use LF endings (no CR)" {
    $names = @('AEGIS-VPS-Finish.ps1', 'AEGIS-VPS-Finish.cmd', 'zz-UNDO-AEGIS-VPS-Finish.ps1', 'zz-UNDO-AEGIS-VPS-Finish.cmd')
    $paths = $names | ForEach-Object { Join-Path $clickFilesDir $_ }
    $paths += (Join-Path $here 'test-vps-finish-gates.ps1')
    foreach ($p in $paths) { if ([IO.File]::ReadAllBytes($p) -contains 13) { throw "CR found in $p" } }
}

Write-Host ""
Write-Host "== Results" -ForegroundColor Cyan
Write-Host "Passed: $testsPassed | Failed: $testsFailed"
Write-Host ""

if ($testsFailed -gt 0) {
    Write-Host "Some tests failed." -ForegroundColor Red
    exit 1
} else {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
}
