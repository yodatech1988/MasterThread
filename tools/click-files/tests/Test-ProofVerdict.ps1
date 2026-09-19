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

# Get-BranchCount: ok flag, raw text (gh api output shape: JSON body then "gh: <msg> (HTTP nnn)" on errors)
Check 'branches: 200 []'                  (Get-BranchCount $true '[]') 0
Check 'branches: 200 one branch'          (Get-BranchCount $true '[{"name":"main"}]') 1
Check 'branches: 409 empty'               (Get-BranchCount $false '{"message":"Git Repository is empty.","status":"409"}gh: Git Repository is empty. (HTTP 409)') 0
Check 'branches: 404 -> unknown'          ($null -eq (Get-BranchCount $false 'gh: Not Found (HTTP 404)')) $true
Check 'branches: 409 not-empty text'      ($null -eq (Get-BranchCount $false 'gh: Conflict (HTTP 409)')) $true
Check 'branches: 200 bad json -> unknown' ($null -eq (Get-BranchCount $true 'not json')) $true
# Test-Is404
Check 'protection probe 404 Branch not found' (Test-Is404 $false '{"message":"Branch not found","status":"404"}gh: Branch not found (HTTP 404)') $true
Check 'protection probe 404 Branch not protected' (Test-Is404 $false 'gh: Branch not protected (HTTP 404)') $true
Check 'protection probe 200 = protected'  (Test-Is404 $true '{"url":"x"}') $false
Check 'protection probe 403 not 404'      (Test-Is404 $false 'gh: Forbidden (HTTP 403)') $false
# Get-DefaultBranch (never assume main)
Check 'default branch main'               (Get-DefaultBranch ([pscustomobject]@{ default_branch = 'main' })) 'main'
Check 'default branch master'             (Get-DefaultBranch ([pscustomobject]@{ default_branch = 'master' })) 'master'
Check 'default branch missing -> null'    ($null -eq (Get-DefaultBranch ([pscustomobject]@{ name = 'x' }))) $true
Check 'default branch null repo -> null'  ($null -eq (Get-DefaultBranch $null)) $true
Check 'default branch weird chars -> null' ($null -eq (Get-DefaultBranch ([pscustomobject]@{ default_branch = 'a b;rm' }))) $true

Write-Host "PASS=$($script:pass) FAIL=$($script:fail)"
exit $script:fail
