<#
.SYNOPSIS
  Create one isolated git worktree per parallel research/session lane, so concurrent Claude Code
  agents targeting the same repo never share a working directory and can't collide.

.DESCRIPTION
  Root cause of the 2026-09-14 collisions (aegis-mods research-terrain PR picking up
  research-economy's and research-environment's commits, several other lanes self-healing mid-run):
  multiple parallel agents were each told to "clone/fetch <repo>" and left to decide their own
  working directory. Some correctly followed MasterThread's session_plan_standard.md rule 9 (work
  in a worktree, never the shared checkout); some didn't, and ended up in the shared checkout at
  the same time as another lane, racing on branch/HEAD state.

  This script removes the ambiguity: the ORCHESTRATING session runs this once, before dispatching
  any agent, and hands each agent its own already-created, already-isolated path. No agent ever
  has to decide whether or where to create a worktree.

  Matches session_plan_standard.md rule 9's exact convention:
    git worktree add ../_wt-<repo>-<slug> -b agent/<repo>/<slug> origin/<default>

.PARAMETER Repo
  Repo folder name under this GitHub root (e.g. aegis-mods). Must already be checked out here.

.PARAMETER Slugs
  One or more short slugs, one per parallel lane (e.g. research-character, research-economy).
  Each becomes worktree `_wt-<repo>-<slug>` on branch `agent/<repo>/<slug>`.

.PARAMETER DefaultBranch
  Override the detected default branch (master/main) if auto-detection is wrong.

.EXAMPLE
  & .\New-ParallelWorktrees.ps1 -Repo aegis-mods -Slugs 'research-character','research-economy'

  Call it directly (dot-and-ampersand, or dot-source) from an existing PowerShell session -- do
  NOT spawn a nested `powershell -File ...` process for this. A comma-separated -Slugs argument
  passed across a process boundary to a brand-new powershell.exe does not reliably bind as an
  array (observed: the second element got bound to -DefaultBranch instead) -- call the script
  in-process instead. If the calling shell has never bypassed the execution policy for this
  session, run `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force` first.

  Prints one block per lane, ready to paste into that lane's agent prompt as its "work only here"
  instruction.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string[]]$Slugs,
    [string]$DefaultBranch
)

# Native git commands below are never stderr-redirected -- on Windows PowerShell 5.1, redirecting
# a native command's stderr wraps it in a terminating-feeling ErrorRecord even on a normal,
# expected non-zero exit (e.g. "branch doesn't exist yet"). Check $LASTEXITCODE explicitly instead.
$ErrorActionPreference = 'Continue'
$RepoDir = Join-Path $PSScriptRoot $Repo
if (-not (Test-Path (Join-Path $RepoDir '.git'))) {
    throw "Not a git checkout: $RepoDir -- run this from the GitHub root with the repo already cloned."
}

Write-Host "Fetching $Repo..."
& git -C $RepoDir fetch origin --quiet
if ($LASTEXITCODE -ne 0) { throw "git fetch failed for $Repo" }

if (-not $DefaultBranch) {
    $head = & git -C $RepoDir symbolic-ref refs/remotes/origin/HEAD
    if ($LASTEXITCODE -eq 0 -and $head) {
        $DefaultBranch = ($head.Trim() -replace '^refs/remotes/origin/', '')
    } else {
        foreach ($candidate in @('main', 'master')) {
            & git -C $RepoDir rev-parse --verify "origin/$candidate" | Out-Null
            if ($LASTEXITCODE -eq 0) { $DefaultBranch = $candidate; break }
        }
    }
    if (-not $DefaultBranch) { throw "Could not detect default branch for $Repo -- pass -DefaultBranch explicitly." }
}
Write-Host "Default branch: $DefaultBranch"

# Duplicate-slug guard: two lanes sharing a worktree defeats the entire point of this script.
$dupes = $Slugs | Group-Object | Where-Object { $_.Count -gt 1 }
if ($dupes) { throw "Duplicate slug(s): $($dupes.Name -join ', ') -- every lane needs its own slug." }

$results = @()
foreach ($slug in $Slugs) {
    $wtName = "_wt-$Repo-$slug"
    $wtPath = Join-Path $PSScriptRoot $wtName
    $branch = "agent/$Repo/$slug"

    if (Test-Path $wtPath) {
        Write-Warning "$wtName already exists -- leaving it as-is (another lane may already be using it; verify before reusing)."
        $results += [pscustomobject]@{ Slug = $slug; Path = $wtPath; Branch = $branch; Status = 'existed' }
        continue
    }

    & git -C $RepoDir rev-parse --verify "refs/heads/$branch" | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Warning "Branch $branch already exists locally -- adding the worktree onto it instead of creating fresh."
        & git -C $RepoDir worktree add $wtPath $branch
    } else {
        & git -C $RepoDir worktree add $wtPath -b $branch "origin/$DefaultBranch"
    }
    if ($LASTEXITCODE -ne 0) { throw "git worktree add failed for slug '$slug'" }

    $results += [pscustomobject]@{ Slug = $slug; Path = $wtPath; Branch = $branch; Status = 'created' }
}

Write-Host "`n===== Paste one block per lane into that lane's agent prompt =====`n"
foreach ($r in $results) {
    Write-Host "--- $($r.Slug) ($($r.Status)) ---"
    Write-Host "Your worktree is already created at $($r.Path) on branch $($r.Branch)."
    Write-Host "Work ONLY there. Do not use $RepoDir (the shared checkout) or any other lane's" -NoNewline
    Write-Host " worktree -- other sessions may be using them concurrently."
    Write-Host ''
}

Write-Host "When a lane's PR merges, prune its worktree:"
Write-Host "  git -C `"$RepoDir`" worktree remove <path>"
Write-Host "(check git status and PR merge state first -- never --force; see aegis-worktree-remove-no-force memory.)"
