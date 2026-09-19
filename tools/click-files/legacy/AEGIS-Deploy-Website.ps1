<#
.SYNOPSIS
  Owner-run. Publishes aegisdirective.net (Cloudflare Worker "aegis-directive") from origin/main:
  builds a clean copy, shows exactly which live files will change, asks you to type YES, deploys,
  then verifies the live pages.

.DESCRIPTION
  LIVE PUBLIC-SITE DEPLOY. It can publish a real PayPal donate button. Read the file list before
  you type YES.

  Added by the 2026-09-19 audit (see PM_INBOX\github-d0-*-deploy-audit.md):
    * A timestamped log next to this script on EVERY terminating path (success, nothing to
      deploy, owner-cancelled, refused, unhandled exception, failed deploy). One outer
      try/catch/finally; the outcome is set immediately before every exit.
        AEGIS-Deploy-Website.<yyyyMMdd-HHmmss>.log         only a run that ATTEMPTED the deploy
        AEGIS-Deploy-Website.<yyyyMMdd-HHmmss>.dryrun.log  every run that changed nothing
      The first line says it in words: "RUN TYPE: real" or "RUN TYPE: dry run (nothing was
      changed)".
    * -WhatIf: a dry run that provably deploys nothing (proof below).
    * A named-mutex guard: a second run while one is in progress is refused (exit 2). The two
      runs used to share one build directory and the second deleted the first one's build.
    * A real-console gate: without -WhatIf, refuses unless started by a person at a real console
      (stdin not redirected), so a session piping "YES" cannot deploy.
    * The YES check is now case-sensitive ("yes" used to pass: PowerShell -ne is case-insensitive).
    * If any live page cannot be read (429, 5xx, offline) the run REFUSES instead of listing
      every file as NEW.

  EXIT CODES
    0  deployed and every live page came back OK        (or -WhatIf finished)
    1  failed (build, deploy, or unhandled exception)
    2  refused (not a real console, already running, live site unreadable, precondition)
    3  cancelled at the prompt: nothing deployed
    4  nothing to deploy: live already matches main
    5  deployed, but a live page did not come back OK   (see undo in the log)

  HOW -WhatIf PROVES IT DEPLOYS NOTHING
    1. Structural: the only line that runs "wrangler deploy" is inside Invoke-Deploy, whose first
       statement throws if $script:IsDryRun is set, and the dry-run branch exits before that
       function is reachable. A dry run never runs npx/wrangler at all.
    2. Behavioural (tests/Test-Deploy.ps1): with a recording "npx" shim first on PATH, a -WhatIf
       run must leave the shim's call log EMPTY; a confirmed real run on a test target must leave
       exactly one "wrangler deploy" line. A test that cannot fail proves nothing, so the same
       harness also asserts the real-run case sees the call.
    3. Naming: a dry run writes only *.dryrun.log, never the real-run log name.
    What -WhatIf still does: git fetch (updates remote-tracking refs in the checkout, as the real
    run does), builds into a separate *-dryrun directory under %TEMP%, and reads the live site
    with GET requests. It writes nothing to the live site.

  UNDO after a bad deploy: from the build directory shown in the log, run
    npx wrangler rollback
  (rolls the Worker back to its previous version). Not run by the audit; confirm the command with
  wrangler's own help before relying on it.

.PARAMETER WhatIf
  Dry run: everything except "wrangler deploy". Safe for a Claude session to run.

.PARAMETER Repo / Site / BuildRoot / LogDir
  Test seams. Defaults are the real values. A run whose Repo AND Site are both the real defaults
  is the "real target"; any other combination is a test target, which skips the console gate and
  uses its own mutex name so a test can never block or be blocked by the owner's real run.
#>
[CmdletBinding()]
param(
  [switch] $WhatIf,
  [string] $Repo      = 'C:\Users\yoda_\GitHub\aegis-website',
  [string] $Site      = 'https://aegisdirective.net',
  [string] $BuildRoot = $env:TEMP,
  [string] $LogDir    = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

$RealRepo = 'C:\Users\yoda_\GitHub\aegis-website'
$RealSite = 'https://aegisdirective.net'
$IsRealTarget = ($Repo -ieq $RealRepo) -and ($Site -ieq $RealSite)

$script:IsDryRun = [bool]$WhatIf
$script:IsRealAttempt = $false      # true only once the deploy command is about to run
$script:RunStartTime = Get-Date
$script:PlanLines = @()
$script:TypedAnswer = 'n/a (no prompt reached)'
$script:RunOutcome = 'UNKNOWN (script exited without setting an outcome)'
$script:RunExceptionText = ''
$script:DeployOutput = @()
$script:Sha = ''
$script:BuildDir = ''
$script:ExitCode = 1
$script:TarPath = ''

function Say($m, [string]$ForegroundColor) {
  if ($ForegroundColor) { Write-Host $m -ForegroundColor $ForegroundColor } else { Write-Host $m }
}

# One place that ends the run: sets the outcome + exit code, then exits. The finally block logs.
function Finish([int]$code, [string]$outcome) {
  $script:ExitCode = $code
  $script:RunOutcome = $outcome
  exit $code
}

function Write-RunLog {
  $suffix = if ($script:IsRealAttempt) { 'log' } else { 'dryrun.log' }
  $log = Join-Path $LogDir ("AEGIS-Deploy-Website.{0}.{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $suffix)
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("RUN TYPE: $(if ($script:IsRealAttempt) { 'real' } else { 'dry run (nothing was changed)' })")
  $lines.Add("Start time (local): $($script:RunStartTime.ToString('o'))")
  $lines.Add("End time (local):   $((Get-Date).ToString('o'))")
  $lines.Add("Target: $(if ($IsRealTarget) { 'REAL (aegisdirective.net)' } else { "TEST (Repo=$Repo Site=$Site)" })")
  $lines.Add("Mode: $(if ($script:IsDryRun) { '-WhatIf' } else { 'normal' })")
  $lines.Add("origin/main: $($script:Sha)")
  $lines.Add("Build dir: $($script:BuildDir)")
  $lines.Add('')
  $lines.Add('Resolved plan (files that differ from the live site):')
  foreach ($l in $script:PlanLines) { $lines.Add("  $l") }
  $lines.Add('')
  $lines.Add("Owner typed: $($script:TypedAnswer)")
  $lines.Add("Outcome: $($script:RunOutcome)")
  $lines.Add("Exit code: $($script:ExitCode)")
  if ($script:DeployOutput.Count -gt 0) {
    $lines.Add('')
    $lines.Add('wrangler output (last 40 lines):')
    foreach ($l in ($script:DeployOutput | Select-Object -Last 40)) { $lines.Add("  $l") }
  }
  if ($script:RunExceptionText) {
    $lines.Add('')
    $lines.Add('Exception:')
    $lines.Add($script:RunExceptionText)
  }
  try {
    $lines | Out-File -FilePath $log -Encoding utf8
    Write-Host "Log: $log"
  } catch {
    Write-Host "WARNING: could not write run log to $log`: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

# The ONLY place "wrangler deploy" is run. Tripwire: a dry run can never get here.
function Invoke-Deploy([string]$dir) {
  if ($script:IsDryRun) { throw 'BUG: Invoke-Deploy reached during a -WhatIf run' }
  # PowerShell 5.1 turns native stderr into terminating errors under 'Stop' when redirected with
  # 2>&1; wrangler writes progress to stderr. Judge success by the exit code instead.
  $ErrorActionPreference = 'Continue'
  $script:IsRealAttempt = $true
  Push-Location $dir
  try {
    npx wrangler deploy 2>&1 | ForEach-Object { $script:DeployOutput += "$_"; Say "$_" }
    if ($LASTEXITCODE -ne 0) { throw "wrangler deploy failed (exit $LASTEXITCODE) - read the lines above" }
  } finally { Pop-Location }
}

# MD5 of a byte array with CRLF collapsed to LF, so a line-ending difference between
# the built file and what the Worker serves is not reported as a content change.
function Get-NormalisedHash([byte[]]$bytes) {
  $text = [System.Text.Encoding]::UTF8.GetString($bytes) -replace "`r`n", "`n"
  # Cloudflare injects its Web Analytics beacon into HTML it serves. It is not in the
  # built file, so strip it or every page reads as changed.
  $text = [regex]::Replace($text, '(?s)\s*<script[^>]*cloudflareinsights[^>]*>.*?</script>', '')
  $norm = [System.Text.Encoding]::UTF8.GetBytes($text)
  $md5  = [System.Security.Cryptography.MD5]::Create()
  try { ($md5.ComputeHash($norm) | ForEach-Object { $_.ToString('x2') }) -join '' }
  finally { $md5.Dispose() }
}

$mutex = $null
$haveMutex = $false
try {
  # --- initiation binding: a person at a real console, never a session's tool call ---------
  if ($IsRealTarget -and -not $script:IsDryRun) {
    if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
      Say ''
      Say 'REFUSED: this publishes the live site and must be started by the owner from a real console' -ForegroundColor Red
      Say '(double-click the .cmd). A Claude session may only run it with -WhatIf.' -ForegroundColor Red
      Finish 2 'REFUSED: not an interactive console (real target, not -WhatIf).'
    }
  }

  # --- guard against running twice: one deploy at a time (real and dry runs share it) ------
  $mutexName = 'Global\AEGIS-Deploy-Website'
  if (-not $IsRealTarget) {
    $h = [BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes("$Repo|$Site|$BuildRoot"))).Replace('-', '').Substring(0, 12)
    $mutexName = "Global\AEGIS-Deploy-Website-TEST-$h"
  }
  $mutex = New-Object System.Threading.Mutex($false, $mutexName)
  try { $haveMutex = $mutex.WaitOne(0) }
  catch [System.Threading.AbandonedMutexException] { $haveMutex = $true }   # previous run died; we own it now
  if (-not $haveMutex) {
    Say 'REFUSED: another deploy (or dry run) is already in progress. Wait for it to finish.' -ForegroundColor Red
    Finish 2 'REFUSED: another AEGIS-Deploy-Website run holds the lock.'
  }

  $BuildDir = Join-Path $BuildRoot $(if ($script:IsDryRun) { 'aegis-website-deploy-dryrun' } else { 'aegis-website-deploy' })
  $script:BuildDir = $BuildDir
  $script:TarPath = Join-Path $BuildRoot $(if ($script:IsDryRun) { 'aegis-website-main-dryrun.tar' } else { 'aegis-website-main.tar' })

  Say ''
  Say $(if ($script:IsDryRun) { '=== AEGIS website deploy (DRY RUN: nothing will be published) ===' } else { '=== AEGIS website deploy ===' })
  Say ''

  # 1. Clean export of origin/main (never touches your working checkout)
  Say 'Fetching latest main from GitHub...'
  git -C $Repo fetch --quiet origin main
  if ($LASTEXITCODE -ne 0) { throw 'git fetch failed' }

  $sha = (git -C $Repo rev-parse --short origin/main).Trim()
  $subject = (git -C $Repo log -1 --pretty=%s origin/main).Trim()
  $script:Sha = "$sha  $subject"
  Say ("main is at {0}  {1}" -f $sha, $subject)

  if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }
  New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

  $tarPath = $script:TarPath
  if (Test-Path $tarPath) { Remove-Item -Force $tarPath }
  git -C $Repo archive --format=tar -o $tarPath origin/main
  if ($LASTEXITCODE -ne 0) { throw 'git archive failed' }
  tar -xf $tarPath -C $BuildDir
  if ($LASTEXITCODE -ne 0) { throw 'tar extract failed' }
  Remove-Item -Force $tarPath

  # wrangler.jsonc is gitignored (holds the real Worker config) - copy it in
  Copy-Item (Join-Path $Repo 'wrangler.jsonc') (Join-Path $BuildDir 'wrangler.jsonc') -Force

  # 2. Build
  Say ''
  Say 'Building the site...'
  Push-Location $BuildDir
  try {
    python build.py
    if ($LASTEXITCODE -ne 0) { throw 'build.py failed' }
  } finally { Pop-Location }

  $publicDir = Join-Path $BuildDir 'public'
  if (-not (Test-Path $publicDir)) { throw "build produced no public\ folder" }

  # 3. Compare what was built against what is live right now
  Say ''
  Say 'Comparing the new build against the live site...'
  $changed = New-Object System.Collections.ArrayList
  $unreadable = New-Object System.Collections.ArrayList
  $same = 0

  Get-ChildItem -Path $publicDir -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($publicDir.Length + 1).Replace('\','/')
    $url = if ($rel -match '(^|/)index\.html$') { "$Site/" + ($rel -replace 'index\.html$','') } else { "$Site/$rel" }
    # Compare raw bytes (newline-normalised). Decoding to text first would flag every
    # page as changed, because the response charset is not what PowerShell assumes.
    $localHash = Get-NormalisedHash ([System.IO.File]::ReadAllBytes($_.FullName))
    $liveHash = $null
    $state = 'ok'
    $wc = New-Object System.Net.WebClient
    try {
      $liveHash = Get-NormalisedHash ($wc.DownloadData($url))
    } catch [System.Net.WebException] {
      $resp = $_.Exception.Response
      # Only a real 404 means "not on the live site yet". Anything else (429, 5xx, no network)
      # means we cannot tell, and must not be reported as NEW.
      if ($null -ne $resp -and [int]$resp.StatusCode -eq 404) { $state = 'new' } else { $state = 'unreadable' }
    } catch { $state = 'unreadable' }
    finally { $wc.Dispose() }

    if ($state -eq 'unreadable') {
      [void]$unreadable.Add(("{0}   ({1})" -f $rel, $url))
    } elseif ($state -eq 'new') {
      [void]$changed.Add(("NEW      {0}   ({1})" -f $rel, $url))
    } elseif ($liveHash -ne $localHash) {
      [void]$changed.Add(("CHANGED  {0}   ({1})" -f $rel, $url))
    } else {
      $script:same++
    }
  }
  $same = $script:same
  $script:PlanLines = @($changed)

  Say ''
  if ($unreadable.Count -gt 0) {
    Say ("REFUSED: could not read {0} live page(s), so the change list would be wrong:" -f $unreadable.Count) -ForegroundColor Red
    $unreadable | Select-Object -First 10 | ForEach-Object { Say ("  " + $_) }
    Finish 2 ("REFUSED: {0} live page(s) unreadable (not 404); comparison unreliable." -f $unreadable.Count)
  }
  if ($changed.Count -eq 0) {
    Say ("The live site already matches main ({0} files identical). Nothing to deploy." -f $same)
    Say 'Exiting without deploying.'
    Finish 4 ("NOTHING TO DEPLOY: live matches main ({0} files identical)." -f $same)
  }

  Say ("{0} file(s) will change on the live site ({1} already identical):" -f $changed.Count, $same)
  Say ''
  $changed | ForEach-Object { Say ("  " + $_) }

  # 3b. Dry run stops here, before the confirm and before the deploy function is reachable.
  if ($script:IsDryRun) {
    Say ''
    Say 'DRY RUN: nothing was published. Re-run without -WhatIf (double-click the .cmd) to publish.'
    Finish 0 ("DRY RUN: would publish {0} file(s); nothing was published." -f $changed.Count)
  }

  # 4. Confirm
  Say ''
  Say 'This publishes those changes to the public site at aegisdirective.net.'
  $answer = Read-Host 'Type YES to deploy (anything else cancels)'
  if ($answer -cne 'YES') {
    $script:TypedAnswer = 'not YES (cancelled)'
    Say 'Cancelled. Nothing was deployed.'
    Finish 3 'CANCELLED: owner did not type YES; nothing deployed.'
  }
  $script:TypedAnswer = 'YES'

  # 5. Deploy
  Say ''
  Say 'Deploying...'
  try {
    Invoke-Deploy $BuildDir
  } catch {
    $ex = $_.Exception
    Say ''
    Say 'DEPLOY FAILED:' -ForegroundColor Red
    Say "Exception type   : $($ex.GetType().FullName)" -ForegroundColor Red
    Say "Exception message: $($ex.Message)" -ForegroundColor Red
    Say 'The live site may or may not have changed. Check https://aegisdirective.net, then read the log.' -ForegroundColor Red
    Say "Undo, if it did change: cd `"$BuildDir`" ; npx wrangler rollback" -ForegroundColor Red
    $script:RunExceptionText = "Type: $($ex.GetType().FullName)`nMessage: $($ex.Message)`n$($ex.ToString())"
    Finish 1 "FAILED: wrangler deploy: $($ex.Message)"
  }

  # 6. Verify live
  Say ''
  Say 'Verifying the live site...'
  Start-Sleep -Seconds $(if ($IsRealTarget) { 5 } else { 0 })
  $bad = 0
  foreach ($p in @('/','/start/','/fund/','/sites/','/sites/chernarus/','/sites/deer-isle/','/factions/','/directive/','/castellan/')) {
    try {
      $r = Invoke-WebRequest -Uri ($Site + $p) -UseBasicParsing -TimeoutSec 30
      Say ("  {0,-22} {1}" -f $p, $r.StatusCode)
    } catch {
      Say ("  {0,-22} FAILED" -f $p)
      $bad++
    }
  }

  Say ''
  if ($bad -gt 0) {
    Say "$bad page(s) did not come back OK. Tell Claude - it can check what happened."
    Say "Undo, if needed: cd `"$BuildDir`" ; npx wrangler rollback"
    Finish 5 "DEPLOYED BUT VERIFY FAILED: $bad live page(s) did not return OK."
  }
  Say ("Done. aegisdirective.net is now serving main ({0})." -f $sha)
  Finish 0 ("DEPLOYED: {0} file(s) published; all live pages OK." -f $changed.Count)
}
catch {
  $ex = $_.Exception
  Write-Host ''
  Write-Host 'UNEXPECTED EXCEPTION:' -ForegroundColor Red
  Write-Host "Exception type   : $($ex.GetType().FullName)" -ForegroundColor Red
  Write-Host "Exception message: $($ex.Message)" -ForegroundColor Red
  if (-not $script:RunExceptionText) {
    $script:RunExceptionText = "Type: $($ex.GetType().FullName)`nMessage: $($ex.Message)`n$($ex.ToString())"
  }
  if ($script:RunOutcome -like 'UNKNOWN*') {
    $script:RunOutcome = "FAILED: unhandled exception $($ex.GetType().FullName) - $($ex.Message)"
  }
  $script:ExitCode = 1
  exit 1
}
finally {
  if ($script:TarPath -and (Test-Path $script:TarPath)) { Remove-Item -Force $script:TarPath -ErrorAction SilentlyContinue }
  if ($mutex) { if ($haveMutex) { try { $mutex.ReleaseMutex() } catch {} } ; $mutex.Dispose() }
  Write-RunLog
}
