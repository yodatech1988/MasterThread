# Tests for the decision functions in AEGIS-Prove-App-Review.ps1 (dot-sourced; nothing else runs).
# Run:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\click-files\tests\Test-ProofVerdict.ps1
# Exit code = number of failures. (tools/tests holds pytest files; these are PowerShell functions, so PowerShell tests.)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\AEGIS-Prove-App-Review.ps1')
$ErrorActionPreference = 'Continue'
$script:pass = 0; $script:fail = 0
function Check($label, $got, $want) { if ($got -ceq $want) { $script:pass++; Write-Host "ok   $label" } else { $script:fail++; Write-Host "FAIL $label got='$got' want='$want'" } }

# Get-ProofVerdict: app review state, reviewDecision, mergeStateStatus
Check 'APPROVED/APPROVED/CLEAN'            (Get-ProofVerdict 'APPROVED' 'APPROVED' 'CLEAN') 'COUNTS'
Check 'APPROVED/APPROVED/UNSTABLE'         (Get-ProofVerdict 'APPROVED' 'APPROVED' 'UNSTABLE') 'COUNTS'
Check 'APPROVED/APPROVED/BLOCKED'          (Get-ProofVerdict 'APPROVED' 'APPROVED' 'BLOCKED') 'INCONCLUSIVE'
Check 'APPROVED/APPROVED/UNKNOWN'          (Get-ProofVerdict 'APPROVED' 'APPROVED' 'UNKNOWN') 'INCONCLUSIVE'
Check 'APPROVED/APPROVED/null'             (Get-ProofVerdict 'APPROVED' 'APPROVED' $null) 'INCONCLUSIVE'
Check 'APPROVED/APPROVED/empty'            (Get-ProofVerdict 'APPROVED' 'APPROVED' '') 'INCONCLUSIVE'
Check 'APPROVED/REVIEW_REQUIRED/BLOCKED'   (Get-ProofVerdict 'APPROVED' 'REVIEW_REQUIRED' 'BLOCKED') 'DOES NOT COUNT'
Check 'APPROVED/REVIEW_REQUIRED/CLEAN'     (Get-ProofVerdict 'APPROVED' 'REVIEW_REQUIRED' 'CLEAN') 'INCONCLUSIVE'
Check 'COMMENTED/APPROVED/CLEAN'           (Get-ProofVerdict 'COMMENTED' 'APPROVED' 'CLEAN') 'INCONCLUSIVE'
Check 'error result (null/null/null)'      (Get-ProofVerdict $null $null $null) 'INCONCLUSIVE'
Check 'APPROVED/null decision/BLOCKED'     (Get-ProofVerdict 'APPROVED' $null 'BLOCKED') 'INCONCLUSIVE'

# Test-ExistingRepoAllowed: description, isPrivate, branchCount, protection404
$m = "throwaway ($Marker)"
Check 'existing: allowed case'             (Test-ExistingRepoAllowed $m $true 0 $true).Allowed $true
Check 'existing: marker missing'           (Test-ExistingRepoAllowed 'my real repo' $true 0 $true).Allowed $false
Check 'existing: description null'         (Test-ExistingRepoAllowed $null $true 0 $true).Allowed $false
Check 'existing: public'                   (Test-ExistingRepoAllowed $m $false 0 $true).Allowed $false
Check 'existing: non-empty (1 branch)'     (Test-ExistingRepoAllowed $m $true 1 $true).Allowed $false
Check 'existing: branches unreadable'      (Test-ExistingRepoAllowed $m $true $null $true).Allowed $false
Check 'existing: protected / not 404'      (Test-ExistingRepoAllowed $m $true 0 $false).Allowed $false
Check 'existing: marker but public+full'   (Test-ExistingRepoAllowed $m $false 3 $false).Allowed $false
Check 'existing: reason names marker'      ((Test-ExistingRepoAllowed 'x' $true 0 $true).Reason -like '*marker*') $true

Write-Host "PASS=$($script:pass) FAIL=$($script:fail)"
exit $script:fail
