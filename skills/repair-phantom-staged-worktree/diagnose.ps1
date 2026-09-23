<#
.SYNOPSIS
  Diagnose-only helper for the repair-phantom-staged-worktree skill.
  Read-only: never runs git update-ref, git commit, or git reset.
  Prints the exact git update-ref command for a session to run itself,
  AFTER it has confirmed (per the skill's step 3) whether this is a
  session-created _wt-* worktree or the owner's own checkout.

.PARAMETER WorktreePath
  Path to the worktree to diagnose.

.PARAMETER Owner
  GitHub org/owner for the repo (e.g. yodatech1988).

.PARAMETER Repo
  Repo name (e.g. MasterThread).

.EXAMPLE
  powershell -File diagnose.ps1 -WorktreePath C:\Users\yoda_\GitHub\_wt-MasterThread-buildstate-paths -Owner yodatech1988 -Repo MasterThread
#>
param(
    [Parameter(Mandatory=$true)][string]$WorktreePath,
    [Parameter(Mandatory=$true)][string]$Owner,
    [Parameter(Mandatory=$true)][string]$Repo
)

function Write-Section($title) {
    Write-Host ""
    Write-Host "== $title ==" -ForegroundColor Cyan
}

if (-not (Test-Path $WorktreePath)) {
    Write-Host "ERROR: worktree path does not exist: $WorktreePath" -ForegroundColor Red
    exit 1
}

Write-Section "Step 1: branch and ref check"
$branchRef = git -C $WorktreePath symbolic-ref HEAD 2>&1
Write-Host "symbolic-ref HEAD: $branchRef"

if ($branchRef -match '^refs/heads/') {
    $branch = $branchRef -replace '^refs/heads/', ''
} else {
    Write-Host "Could not parse a branch name from symbolic-ref output. Stopping (read-only)." -ForegroundColor Yellow
    exit 1
}

$refCheck = git -C $WorktreePath show-ref --verify "refs/heads/$branch" 2>&1
$refExists = $LASTEXITCODE -eq 0
Write-Host "show-ref --verify refs/heads/$branch : $refCheck"

if ($refExists) {
    Write-Host ""
    Write-Host "Ref exists. This does NOT match the phantom-staged-worktree symptom." -ForegroundColor Yellow
    Write-Host "Stop condition met per SKILL.md step 1 — do not proceed with this skill." -ForegroundColor Yellow
    exit 0
}

Write-Section "Step 2: staged/tracked count comparison"
$lsFilesCount = (git -C $WorktreePath ls-files 2>$null | Measure-Object -Line).Lines
$statusCount = (git -C $WorktreePath status --porcelain 2>$null | Measure-Object -Line).Lines
Write-Host "ls-files count:          $lsFilesCount"
Write-Host "status --porcelain count: $statusCount"

if ($lsFilesCount -eq 0) {
    Write-Host "ls-files returned 0 — cannot confirm the artifact pattern. Stopping (read-only)." -ForegroundColor Yellow
    exit 1
}

$ratio = if ($lsFilesCount -gt 0) { [math]::Abs($lsFilesCount - $statusCount) / $lsFilesCount } else { 1 }
if ($ratio -gt 0.05) {
    Write-Host ""
    Write-Host "Counts do not closely match (>5% difference). This may be real staged work." -ForegroundColor Yellow
    Write-Host "Stop condition met per SKILL.md step 2 — get a human to look before repairing." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Counts match closely — consistent with the phantom-staged-worktree pattern." -ForegroundColor Green

Write-Section "Step 3: whose worktree is this? (session-created vs owner's own)"
$leaf = Split-Path -Path $WorktreePath -Leaf
if ($leaf -like '_wt-*') {
    Write-Host "Path '$leaf' matches the session-created '_wt-*' convention."
    Write-Host "A session may proceed to the update-ref command below on its own authority."
} else {
    Write-Host "Path '$leaf' does NOT match the '_wt-*' convention." -ForegroundColor Yellow
    Write-Host "This looks like it could be the owner's own checkout." -ForegroundColor Yellow
    Write-Host "SKILL.md step 3: ASK THE OWNER FIRST before running update-ref on this worktree." -ForegroundColor Red
    Write-Host "(File a Decision Queue card or ask directly if the owner is present — do not assume.)" -ForegroundColor Red
}

Write-Section "Step 4: matching merged PR for branch '$branch'"
$prJson = gh pr list -R "$Owner/$Repo" --state merged --head $branch --json number,headRefOid,mergedAt 2>&1
Write-Host $prJson

try {
    $prs = $prJson | ConvertFrom-Json
} catch {
    Write-Host "Could not parse gh pr list output as JSON. Stopping (read-only)." -ForegroundColor Yellow
    exit 1
}

if (-not $prs -or $prs.Count -eq 0) {
    Write-Host ""
    Write-Host "No merged PR found for branch '$branch'. No known-good SHA to reattach to." -ForegroundColor Yellow
    Write-Host "Stop condition met per SKILL.md step 4 — do not guess, ask instead." -ForegroundColor Yellow
    exit 0
}

if ($prs.Count -gt 1) {
    Write-Host ""
    Write-Host "More than one merged PR matches branch '$branch':" -ForegroundColor Yellow
    $prs | ForEach-Object { Write-Host ("  PR #{0}  headRefOid={1}  mergedAt={2}" -f $_.number, $_.headRefOid, $_.mergedAt) }
    Write-Host "Stop condition met per SKILL.md step 4 — this is underdetermined, ask rather than guess." -ForegroundColor Yellow
    exit 0
}

$sha = $prs[0].headRefOid
$prNum = $prs[0].number

Write-Section "Diagnosis complete"
Write-Host "Branch:        $branch"
Write-Host "Matching PR:   #$prNum"
Write-Host "Target SHA:    $sha"
Write-Host ""
Write-Host "This script has NOT run any write command." -ForegroundColor Green
Write-Host "If (and only if) step 3 above confirms this is a session-created '_wt-*' worktree" -ForegroundColor Green
Write-Host "(or the owner has explicitly said to proceed on their own checkout), run:" -ForegroundColor Green
Write-Host ""
Write-Host "  git -C `"$WorktreePath`" update-ref refs/heads/$branch $sha" -ForegroundColor White
Write-Host ""
Write-Host "Then re-verify with:" -ForegroundColor Green
Write-Host "  git -C `"$WorktreePath`" log --oneline -3"
Write-Host "  git -C `"$WorktreePath`" status --porcelain | Measure-Object -Line"
