<#
.SYNOPSIS
  Owner-run. Answers ONE question on a THROWAWAY private repo: does an approving review submitted by
  the GitHub App count toward required_approving_review_count on a user-owned private repo?

.DESCRIPTION
  Design: PM_INBOX github-49-20260919T2000Z-website-reviewer-identity-design.md (App path, item 3).
  Needs the App key stored first by core tools/GitHubAppKeyImport.ps1. NEVER touches the 'website' repo.

  FLOW (real run, interactive console only):
    1. You type the throwaway repo name at a prompt. HARD REFUSALS, checked before anything else:
       the name 'website' (any case) and any name that does not start with 'proof'. The repo must be
       private. If it does not exist the script offers to create it (private, with a README) after YES.
    2. Loads the App key from the DPAPI store, builds an RS256 JWT (pure .NET, no modules), verifies its
       signature locally against the key's own public half, then uses the JWT to (a) confirm the App is
       installed on that repo (if not: prints the install link and stops) and (b) mint a 1-hour
       installation token. The token lives only in a script variable used in an HTTPS Authorization header:
       never on a command line, never in an environment variable, never logged; cleared in finally.
    3. As your gh session (yodatech1988): sets branch protection on the throwaway repo's main = 1 required
       approving review, enforce_admins true; creates a branch + commit + PR.
    4. As the App (token above): POST an APPROVE review on the PR head commit.
    5. Reads reviewDecision and mergeStateStatus (polls a few seconds for GitHub to compute them) and prints
       a verdict with the raw fields:
         COUNTS         reviewDecision=APPROVED after the App's APPROVE was accepted AND mergeStateStatus is a real
                        value that is not BLOCKED, UNKNOWN or empty (otherwise INCONCLUSIVE)
         DOES NOT COUNT App's APPROVE was accepted but reviewDecision=REVIEW_REQUIRED and mergeStateStatus=BLOCKED
         INCONCLUSIVE   anything else (API error, protection not settable on this plan, state still UNKNOWN)
       It NEVER merges.
    6. Prints exact cleanup steps. It deletes the throwaway repo only if gh already has the delete_repo scope
       and you type YES AND this run created the repo itself; a pre-existing repo is never deleted by the script
       (manual cleanup steps are printed instead).
  -WhatIf (allowed from a session): reads only and creates nothing. Loads the key, builds and locally verifies
  the JWT, reads gh state for the named repo, prints the plan. App API calls (installation lookup, token) are
  read-only but are made ONLY when -StateDir is the real default; with a test -StateDir they print
  "suppressed (non-default target = test)".

  Test seam (tools/README.md): -StateDir (default %APPDATA%\AEGIS). Non-interactive non-WhatIf runs are
  refused in code; there is no exemption, because every write path here is a live GitHub write.

  WHAT WAS AND WAS NOT TESTED (worker-reported 2026-09-19; a session cannot create the App):
    Tested locally with a throwaway RSA key in a scratch StateDir: key load from DPAPI store, JWT structure,
      RS256 signature verification, hard refusal of 'website' and non-'proof' names, interactive-console
      refusal, -WhatIf writes nothing, log written on every path, no key/JWT/token text in logs.
    NOT RUN (needs a real App): installation lookup, token exchange, protection PUT, PR creation, the App's
      APPROVE, the verdict logic against real GitHub responses, cleanup/delete, the .cmd wrapper, the live
      YES prompts. The verdict rules are code-reviewed only.
  What you will see on a real run: prompts, then "App installed: yes", "Protection set", "PR #N opened",
  "App review accepted: APPROVED", a raw-fields block, and a one-line VERDICT.

  Exit codes: 0 verdict printed (any of the three) / cancelled / -WhatIf done; 1 failed or unhandled;
              2 refused: not an interactive console; 3 refused: repo name; 4 refused: other precondition
              (no stored key, App not installed, repo not private, gh not logged in).
.PARAMETER StateDir  DPAPI store directory (default %APPDATA%\AEGIS).
.PARAMETER WhatIf    Read only; creates nothing.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$StateDir = (Join-Path $env:APPDATA 'AEGIS'),
    [switch]$WhatIf
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Owner = 'yodatech1988'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$startIso = [DateTime]::UtcNow.ToString('o')
$StorePath = Join-Path $StateDir 'github-app-website-reviewer.clixml'
$AppIdPath = Join-Path $StateDir 'github-app-website-reviewer.appid.txt'
$realDefault = [IO.Path]::GetFullPath((Join-Path $env:APPDATA 'AEGIS'))
$IsRealTarget = ([IO.Path]::GetFullPath($StateDir)).TrimEnd('\') -ieq $realDefault.TrimEnd('\')
$script:Outcome = 'UNKNOWN (script exited without setting an outcome)'
$script:Exception = $null
$script:Attempted = $false      # true once a write to GitHub was tried (real .log vs .dryrun.log)
$script:Facts = New-Object System.Collections.Generic.List[string]
$script:Exit = 0
$script:Verdict = 'n/a'
$createdHere = $false   # true ONLY when THIS run created the repo; the sole condition under which delete is offered
$script:Token = $null
$script:Jwt = $null

function Add-Fact([string]$s) { $script:Facts.Add($s) }

# ---- DER / PEM -> RSAParameters (same parser as core tools/GitHubAppKeyImport.ps1; duplicated on purpose so this file stands alone) ----
function Get-Der([byte[]]$b, [int]$pos) {
    if ($pos + 2 -gt $b.Length) { throw 'DER: truncated' }
    $tag = $b[$pos]; $l = [int]$b[$pos + 1]; $hdr = 2
    if ($l -ge 0x80) {
        $n = $l - 0x80
        if ($n -lt 1 -or $n -gt 4 -or $pos + 2 + $n -gt $b.Length) { throw 'DER: bad length' }
        $l = 0; for ($i = 0; $i -lt $n; $i++) { $l = $l * 256 + $b[$pos + 2 + $i] }
        $hdr = 2 + $n
    }
    if ($pos + $hdr + $l -gt $b.Length) { throw 'DER: length beyond data' }
    return @{ Tag = $tag; Start = $pos + $hdr; Len = $l; End = $pos + $hdr + $l }
}
function Get-DerInt([byte[]]$b, [int]$pos) {
    $e = Get-Der $b $pos
    if ($e.Tag -ne 0x02) { throw 'DER: expected INTEGER' }
    $s = $e.Start; $n = $e.Len
    while ($n -gt 1 -and $b[$s] -eq 0) { $s++; $n-- }
    $v = New-Object byte[] $n; [Array]::Copy($b, $s, $v, 0, $n)
    return @{ Value = $v; End = $e.End }
}
function Set-Len([byte[]]$v, [int]$len) {
    if ($v.Length -gt $len) { throw 'DER: integer longer than expected' }
    $o = New-Object byte[] $len; [Array]::Copy($v, 0, $o, $len - $v.Length, $v.Length); return $o
}
function ConvertFrom-RsaDer([byte[]]$der) {
    $seq = Get-Der $der 0
    if ($seq.Tag -ne 0x30) { throw 'DER: not a SEQUENCE' }
    $ver = Get-DerInt $der $seq.Start
    $pos = $ver.End
    $peek = Get-Der $der $pos
    if ($peek.Tag -eq 0x30) {
        $oct = Get-Der $der $peek.End
        if ($oct.Tag -ne 0x04) { throw 'DER: PKCS#8 missing OCTET STRING' }
        $inner = New-Object byte[] $oct.Len; [Array]::Copy($der, $oct.Start, $inner, 0, $oct.Len)
        return ConvertFrom-RsaDer $inner
    }
    $vals = @(); $p = $pos
    for ($i = 0; $i -lt 8; $i++) { $r = Get-DerInt $der $p; $vals += , $r.Value; $p = $r.End }
    $nl = $vals[0].Length
    $rp = New-Object System.Security.Cryptography.RSAParameters
    $rp.Modulus = $vals[0]; $rp.Exponent = $vals[1]; $rp.D = Set-Len $vals[2] $nl
    $rp.P = Set-Len $vals[3] ([int]($nl / 2)); $rp.Q = Set-Len $vals[4] ([int]($nl / 2))
    $rp.DP = Set-Len $vals[5] ([int]($nl / 2)); $rp.DQ = Set-Len $vals[6] ([int]($nl / 2))
    $rp.InverseQ = Set-Len $vals[7] ([int]($nl / 2))
    return $rp
}
function ConvertFrom-Secure([securestring]$s) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
function ConvertTo-B64Url([byte[]]$b) { return ([Convert]::ToBase64String($b)).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
function ConvertFrom-B64Url([string]$s) {
    $t = $s.Replace('-', '+').Replace('_', '/'); switch ($t.Length % 4) { 2 { $t += '==' } 3 { $t += '=' } }
    return [Convert]::FromBase64String($t)
}
# Returns @{ Jwt; Verified; HeaderJson; PayloadJson }. RS256 = RSASSA-PKCS1-v1_5 with SHA-256.
function New-AppJwt([string]$pem, [string]$appId) {
    $b64 = [regex]::Match($pem, '-----BEGIN [A-Z0-9 ]+-----(.*?)-----END [A-Z0-9 ]+-----', 'Singleline').Groups[1].Value -replace '\s', ''
    $rp = ConvertFrom-RsaDer ([Convert]::FromBase64String($b64))
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $h = '{"alg":"RS256","typ":"JWT"}'
    $p = '{"iat":' + ($now - 60) + ',"exp":' + ($now + 540) + ',"iss":"' + $appId + '"}'
    $signingInput = (ConvertTo-B64Url ([Text.Encoding]::UTF8.GetBytes($h))) + '.' + (ConvertTo-B64Url ([Text.Encoding]::UTF8.GetBytes($p)))
    $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
    try {
        $rsa.ImportParameters($rp)
        $sig = $rsa.SignData([Text.Encoding]::ASCII.GetBytes($signingInput), 'SHA256')
        # local verification against the PUBLIC half only
        $pub = New-Object System.Security.Cryptography.RSACryptoServiceProvider
        $pubP = New-Object System.Security.Cryptography.RSAParameters; $pubP.Modulus = $rp.Modulus; $pubP.Exponent = $rp.Exponent
        $pub.ImportParameters($pubP)
        $ok = $pub.VerifyData([Text.Encoding]::ASCII.GetBytes($signingInput), 'SHA256', $sig); $pub.Dispose()
    } finally { $rsa.Dispose() }
    return @{ Jwt = ($signingInput + '.' + (ConvertTo-B64Url $sig)); Verified = $ok; HeaderJson = $h; PayloadJson = $p }
}
function Invoke-GhApi([string]$method, [string]$path, $bodyObj) {
    # authenticated as the owner's gh session; body via temp file (no secrets in it), never on the command line
    $tmp = $null
    $ErrorActionPreference = 'Continue'   # gh writes HTTP errors to stderr; do not turn them into terminating errors
    try {
        if ($null -ne $bodyObj) {
            $tmp = [IO.Path]::GetTempFileName()
            ($bodyObj | ConvertTo-Json -Depth 8) | Out-File -FilePath $tmp -Encoding ascii
            $o = & gh api -X $method $path --input $tmp 2>&1
        } else { $o = & gh api -X $method $path 2>&1 }
        return @{ Ok = ($LASTEXITCODE -eq 0); Text = (($o) -join "`n") }
    } finally { if ($tmp) { Remove-Item $tmp -ErrorAction SilentlyContinue } }
}
function Invoke-AppApi([string]$method, [string]$uri, [string]$bearer, $bodyObj) {
    $hdr = @{ Authorization = "Bearer $bearer"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28'; 'User-Agent' = 'aegis-app-review-proof' }
    try {
        if ($null -ne $bodyObj) { $r = Invoke-RestMethod -Method $method -Uri $uri -Headers $hdr -Body ($bodyObj | ConvertTo-Json -Depth 6) -ContentType 'application/json' }
        else { $r = Invoke-RestMethod -Method $method -Uri $uri -Headers $hdr }
        return @{ Ok = $true; Data = $r; Status = 200; Msg = '' }
    } catch {
        $code = 0; $msg = ''
        try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        try { $msg = ([IO.StreamReader]::new($_.Exception.Response.GetResponseStream()).ReadToEnd() | ConvertFrom-Json).message } catch { }
        return @{ Ok = $false; Data = $null; Status = $code; Msg = $msg }
    }
}
function Test-RepoNameAllowed([string]$n) {
    if ($n -match '^(?i)website$' -or $n -match '/') { return $false }
    if ($n -notmatch '^(?i)proof[A-Za-z0-9._-]*$') { return $false }
    return $true
}

function Get-ProofVerdict($appState, $decision, $mss) {
    if ($appState -eq 'APPROVED' -and $decision -eq 'APPROVED' -and $mss -and $mss -notin @('BLOCKED', 'UNKNOWN')) { return 'COUNTS' }
    if ($appState -eq 'APPROVED' -and $decision -eq 'REVIEW_REQUIRED' -and $mss -eq 'BLOCKED') { return 'DOES NOT COUNT' }
    return 'INCONCLUSIVE'
}
# Dot-sourced (test harness): functions only, nothing runs.
if ($MyInvocation.InvocationName -eq '.') { return }

try {
    if (-not $WhatIf) {
        if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
            Write-Host 'REFUSED: start this from a real console window (double-click the .cmd). A session may only use -WhatIf.' -ForegroundColor Red
            $script:Outcome = 'REFUSED: not an interactive console and -WhatIf was not passed.'; $script:Exit = 2; exit 2
        }
    }
    Add-Fact "StateDir: $([IO.Path]::GetFullPath($StateDir)) (real target: $IsRealTarget)"

    Write-Host 'Throwaway-repo proof: does a GitHub App approval satisfy required_approving_review_count?' -ForegroundColor Cyan
    $Repo = (Read-Host "Name of the THROWAWAY private repo under $Owner (must start with 'proof'; NEVER website)").Trim()
    if (-not (Test-RepoNameAllowed $Repo)) {
        Write-Host "REFUSED: '$Repo' is not allowed. The name must start with 'proof' and must not be 'website'." -ForegroundColor Red
        $script:Outcome = "REFUSED: repo name '$Repo' not allowed."; $script:Exit = 3; exit 3
    }
    Add-Fact "repo: $Owner/$Repo"

    & gh auth status *> $null
    if ($LASTEXITCODE -ne 0) { Write-Host 'gh is not logged in.' -ForegroundColor Red; $script:Outcome = 'REFUSED: gh not logged in.'; $script:Exit = 4; exit 4 }
    if (-not (Test-Path $StorePath) -or -not (Test-Path $AppIdPath)) {
        Write-Host "REFUSED: no stored App key under $StateDir. Run GitHubAppKeyImport.ps1 first." -ForegroundColor Red
        $script:Outcome = 'REFUSED: no stored App key/App ID.'; $script:Exit = 4; exit 4
    }
    $appId = (Get-Content -Raw $AppIdPath).Trim()
    if ($appId -notmatch '^\d{1,12}$') { $script:Outcome = 'REFUSED: stored App ID malformed.'; $script:Exit = 4; exit 4 }
    $pem = ConvertFrom-Secure ((Import-Clixml $StorePath).Pem)
    $j = New-AppJwt $pem $appId
    $pem = $null
    $script:Jwt = $j.Jwt
    Add-Fact "app id: $appId"; Add-Fact "JWT header: $($j.HeaderJson)"; Add-Fact "JWT payload: $($j.PayloadJson)"
    Add-Fact "JWT RS256 signature verified locally against the key's public half: $($j.Verified)"
    Write-Host "JWT built; local RS256 signature check: $($j.Verified)"
    if (-not $j.Verified) { $script:Outcome = 'FAILED: JWT did not verify locally.'; $script:Exit = 1; exit 1 }

    # repo state (owner's gh session, read only)
    $rv = Invoke-GhApi 'GET' "repos/$Owner/$Repo" $null
    $exists = $rv.Ok
    if ($exists) {
        $ri = $rv.Text | ConvertFrom-Json
        if (-not $ri.private) { Write-Host 'REFUSED: that repo is public. Nothing changed.' -ForegroundColor Red; $script:Outcome = 'REFUSED: repo not private.'; $script:Exit = 4; exit 4 }
        Add-Fact "repo exists: yes, private, default branch $($ri.default_branch)"
    } else { Add-Fact 'repo exists: no' }
    Write-Host "Repo $Owner/$Repo exists: $exists"

    $canAppCalls = $IsRealTarget
    $installed = $null
    if ($canAppCalls -and $exists) {
        $inst = Invoke-AppApi 'GET' "https://api.github.com/repos/$Owner/$Repo/installation" $script:Jwt $null
        $installed = $inst.Ok
        Add-Fact "App installed on repo: $installed (HTTP $($inst.Status) $($inst.Msg))"
        Write-Host "App installed on repo: $installed"
    } else { Add-Fact 'App installation lookup: suppressed (non-default target = test) or repo not created yet'; Write-Host 'App installation lookup: suppressed / repo not created yet.' }

    if ($WhatIf) {
        Write-Host 'PLAN (nothing created): create repo if missing; require App installed; protect main (1 approval, enforce_admins); open PR; App APPROVE; read reviewDecision/mergeStateStatus; print verdict; never merge.'
        $script:Outcome = '-WhatIf: read-only checks done. Nothing created or changed.'; exit 0
    }

    # ---- real run ----
    if (-not $exists) {
        $t = Read-Host "Repo does not exist. Type YES to create PRIVATE repo $Owner/$Repo with a README (anything else cancels)"
        if ($t -cne 'YES') { $script:Outcome = 'Cancelled by owner before creating the repo.'; exit 0 }
        $script:Attempted = $true
        & gh repo create "$Owner/$Repo" --private --add-readme --description 'throwaway: GitHub App review proof, safe to delete' *> $null
        if ($LASTEXITCODE -ne 0) { $script:Outcome = 'FAILED: gh repo create failed.'; $script:Exit = 1; exit 1 }
        $createdHere = $true
        Add-Fact 'repo created by this script'; Write-Host "Created $Owner/$Repo." -ForegroundColor Green
    }
    $inst = Invoke-AppApi 'GET' "https://api.github.com/repos/$Owner/$Repo/installation" $script:Jwt $null
    Add-Fact "App installed on repo: $($inst.Ok) (HTTP $($inst.Status) $($inst.Msg))"
    if (-not $inst.Ok) {
        Write-Host 'The App is NOT installed on this repo (or the JWT was rejected).' -ForegroundColor Yellow
        Write-Host 'Install it: GitHub > Settings > Applications > Installed GitHub Apps > (the App) > Configure > add repository' -ForegroundColor Yellow
        Write-Host "  https://github.com/settings/installations  then choose $Repo and Save. Then run this again with the same repo name."
        Write-Host "Cleanup if you stop here: gh repo delete $Owner/$Repo --yes" -ForegroundColor Yellow
        $script:Outcome = "REFUSED: App not installed on $Repo (HTTP $($inst.Status) $($inst.Msg)). Repo left in place."; $script:Exit = 4; exit 4
    }
    $instId = $inst.Data.id
    $tok = Invoke-AppApi 'POST' "https://api.github.com/app/installations/$instId/access_tokens" $script:Jwt @{ repositories = @($Repo); permissions = @{ pull_requests = 'write'; contents = 'read' } }
    if (-not $tok.Ok) { $script:Outcome = "FAILED: installation token exchange (HTTP $($tok.Status) $($tok.Msg))."; $script:Exit = 1; exit 1 }
    $script:Token = $tok.Data.token
    Add-Fact "installation token minted (1h, repo-scoped); expires_at $($tok.Data.expires_at); token value NOT logged"
    $script:Jwt = $null

    $script:Attempted = $true
    $prot = Invoke-GhApi 'PUT' "repos/$Owner/$Repo/branches/main/protection" @{
        required_status_checks = $null; enforce_admins = $true; restrictions = $null
        required_pull_request_reviews = @{ required_approving_review_count = 1; dismiss_stale_reviews = $false }
    }
    Add-Fact "protection PUT ok: $($prot.Ok)"
    if (-not $prot.Ok) {
        Write-Host "Could not set branch protection: $($prot.Text)" -ForegroundColor Yellow
        $script:Verdict = 'INCONCLUSIVE'; $script:Outcome = 'INCONCLUSIVE: branch protection could not be set on the throwaway repo (private-repo protection may need a paid plan). Hint: try a PUBLIC throwaway repo (the script creates private ones only; create a public proof-* repo yourself, then it must be deleted by hand since the script only deletes repos it created).'
        Add-Fact "protection error: $($prot.Text)"; exit 0
    }
    Write-Host 'Protection set: 1 required approving review, enforce_admins true.'
    $mainSha = (Invoke-GhApi 'GET' "repos/$Owner/$Repo/git/ref/heads/main" $null).Text | ConvertFrom-Json
    $branch = "proof-$stamp"
    $r1 = Invoke-GhApi 'POST' "repos/$Owner/$Repo/git/refs" @{ ref = "refs/heads/$branch"; sha = $mainSha.object.sha }
    $r2 = Invoke-GhApi 'PUT' "repos/$Owner/$Repo/contents/proof-$stamp.txt" @{ message = 'proof commit'; content = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("proof $stamp")); branch = $branch }
    $r3 = Invoke-GhApi 'POST' "repos/$Owner/$Repo/pulls" @{ title = 'Proof PR (never merge)'; head = $branch; base = 'main'; body = 'Throwaway proof of GitHub App review counting. Do not merge.' }
    if (-not ($r1.Ok -and $r2.Ok -and $r3.Ok)) { Add-Fact "branch/commit/PR ok: $($r1.Ok)/$($r2.Ok)/$($r3.Ok)"; $script:Verdict = 'INCONCLUSIVE'; $script:Outcome = 'INCONCLUSIVE: could not create the proof branch/commit/PR.'; exit 0 }
    $pr = $r3.Text | ConvertFrom-Json
    Add-Fact "PR: #$($pr.number) head $($pr.head.sha)"; Write-Host "PR #$($pr.number) opened: $($pr.html_url)"

    $rev = Invoke-AppApi 'POST' "https://api.github.com/repos/$Owner/$Repo/pulls/$($pr.number)/reviews" $script:Token @{ event = 'APPROVE'; commit_id = $pr.head.sha; body = 'App approval proof' }
    $script:Token = $null
    Add-Fact "App APPROVE accepted: $($rev.Ok) (HTTP $($rev.Status) $($rev.Msg)); review state $(if ($rev.Ok) { $rev.Data.state })"
    if (-not $rev.Ok) { $script:Verdict = 'INCONCLUSIVE'; $script:Outcome = "INCONCLUSIVE: the App's review was rejected by the API (HTTP $($rev.Status) $($rev.Msg))."; Write-Host $script:Outcome -ForegroundColor Yellow; exit 0 }
    Write-Host "App review accepted: $($rev.Data.state)"

    $decision = $null; $mss = $null
    for ($i = 0; $i -lt 8; $i++) {
        Start-Sleep -Seconds 3
        $o = & gh pr view $pr.number -R "$Owner/$Repo" --json reviewDecision,mergeStateStatus,mergeable 2>$null
        if ($LASTEXITCODE -eq 0) { $v = ($o -join '') | ConvertFrom-Json; $decision = $v.reviewDecision; $mss = $v.mergeStateStatus; if ($mss -and $mss -ne 'UNKNOWN') { break } }
    }
    Write-Host "RAW: reviewDecision='$decision'  mergeStateStatus='$mss'  (App review state: $($rev.Data.state))"
    Add-Fact "raw reviewDecision=$decision mergeStateStatus=$mss"
    $script:Verdict = Get-ProofVerdict $rev.Data.state $decision $mss
    Write-Host "VERDICT: $($script:Verdict)" -ForegroundColor Cyan
    $script:Outcome = "VERDICT $($script:Verdict): reviewDecision=$decision mergeStateStatus=$mss. Never merged."

    Write-Host ''
    Write-Host 'CLEANUP (throwaway repo; nothing was merged):' -ForegroundColor Cyan
    $scopes = (& gh auth status 2>&1 | Out-String)
    if (-not $createdHere) {
        Write-Host "  This run did not create $Owner/$Repo, so the script will NOT delete it. Delete it yourself if it is throwaway:"
        Write-Host "  gh auth refresh -h github.com -s delete_repo ; gh repo delete $Owner/$Repo --yes"
    } elseif ($scopes -match 'delete_repo') {
        $d = Read-Host "gh has delete_repo. Type YES to DELETE $Owner/$Repo now (anything else keeps it)"
        if ($d -ceq 'YES' -and $createdHere -and (Test-RepoNameAllowed $Repo)) {
            & gh repo delete "$Owner/$Repo" --yes *> $null
            Add-Fact "repo delete exit code: $LASTEXITCODE"; Write-Host "Delete exit code: $LASTEXITCODE"
        } else { Write-Host "Kept. Delete later: gh repo delete $Owner/$Repo --yes" }
    } else {
        Write-Host '  1. gh auth refresh -h github.com -s delete_repo   (approve in the browser)'
        Write-Host "  2. gh repo delete $Owner/$Repo --yes"
        Write-Host "  Or in the browser: https://github.com/$Owner/$Repo/settings > Danger Zone > Delete this repository."
    }
    Write-Host '  Then: GitHub > Settings > Applications > Installed GitHub Apps > (the App) > Configure: confirm the deleted repo is gone from the list.'
}
catch {
    $script:Exception = $_.Exception
    Write-Host "UNEXPECTED EXCEPTION: $($_.Exception.GetType().FullName)" -ForegroundColor Red
    $script:Outcome = "FAILED: unhandled $($_.Exception.GetType().FullName)"; $script:Exit = 1
}
finally {
    $script:Token = $null; $script:Jwt = $null; $pem = $null
    try {
        $log = Join-Path $PSScriptRoot ("AEGIS-Prove-App-Review.{0}.{1}" -f $stamp, $(if ($script:Attempted) { 'log' } else { 'dryrun.log' }))
        $l = New-Object System.Collections.Generic.List[string]
        $l.Add("RUN TYPE: $(if ($script:Attempted) { 'real (wrote to GitHub)' } else { 'dry run / refused (nothing was written to GitHub)' })")
        $l.Add("Start (UTC): $startIso  WhatIf=$($WhatIf.IsPresent)")
        foreach ($f in $script:Facts) { $l.Add($f) }
        $l.Add("Verdict: $script:Verdict"); $l.Add("Outcome: $script:Outcome")
        if ($script:Exception) { $l.Add("Exception type: $($script:Exception.GetType().FullName)") }
        $l | Out-File -FilePath $log -Encoding utf8; Write-Host "Log: $log"
    } catch { Write-Host "WARNING: could not write log: $($_.Exception.GetType().Name)" -ForegroundColor Yellow }
}
exit $script:Exit
