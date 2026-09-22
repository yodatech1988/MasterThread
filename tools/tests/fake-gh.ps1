<#
.SYNOPSIS
  Test double for `gh`, for the future tools/tests/test-render-review-verdict.ps1's -GhPath seam
  (F13 design, DESIGN_f13-review-verdict_2026-09-22.md section 5B). Modeled directly on
  tools/tests/test-invoke-subagent.ps1's -ClaudePath fake-CLI pattern (its inline `fake-claude.cmd`,
  built for the PR #197 QA regression case): a tiny script that logs every invocation's argv to a
  file and returns canned output per verb, so Render-ReviewVerdict.ps1 can be driven through -Post,
  the live head check, and the read-back without a real `gh` on PATH or a real GitHub call.

.DESCRIPTION
  Reads $env:FAKE_GH_MODE to select the canned-response table: ok | stale-head | readback-404 |
  duplicate (default: ok). Every invocation appends ONE line -- the full argv, space-joined, exactly
  as received -- to $env:FAKE_GH_LOG (if set), so a test can assert both the RESPONSE and the
  ORDER/CONTENT of calls (test-render-review-verdict.ps1's T7, T10, T11, T12, T14).

  Canonical fixture SHAs this fake assumes tests will use (so its canned `pr view` answers are
  predictable without reading a fixture file itself):
    GOOD head (matches tools/tests/fixtures/headless/review-verdict/verdict-valid.json's headSha):
      aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    STALE head (returned by `pr view` when FAKE_GH_MODE=stale-head, deliberately different):
      bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

  Verbs handled:

    pr view <n> -R <repo> --json headRefOid
        -> {"headRefOid":"<sha>"}. Returns the STALE sha when FAKE_GH_MODE=stale-head, the GOOD sha
           otherwise. This is Render-ReviewVerdict.ps1's live head check (design section 3).

    pr comment <n> -R <repo> --body-file <path>
        -> prints a comment URL on stdout and exits 0. Never called in 'stale-head' mode if the
           renderer correctly aborts at the head check first (T7 asserts this via the log, not via
           this fake refusing the call -- the fake will happily answer it if asked, precisely so a
           renderer bug that calls it anyway is visible in the log rather than swallowed).

    api repos/<repo>/issues/<n>/comments
        -> the duplicate-check listing. 'duplicate' mode returns one existing comment whose body
           carries the REVIEW-VERDICT marker for the GOOD head above; every other mode returns [].
           CONFIRMED (merge seat, 2026-09-22, against real `gh` 2.100.0, read-only): both
           `gh api repos/<repo>/issues/<n>/comments` (this fake's duplicate-check verb) and
           `gh api repos/<repo>/issues/comments/<id>` (the read-back verb below) are the correct
           GitHub REST forms; no longer an open assumption.

    api repos/<repo>/issues/comments/<id>
        -> the read-back call. 'readback-404' mode exits 1 with a 404-shaped message on stderr;
           every other mode echoes the comment object `pr comment` implied it had created.

    pr review *
        -> ALWAYS exits 1 with a message naming why. Render-ReviewVerdict.ps1 must never call this
           (design section 3, "What it never does": an APPROVED review is what core's automerge
           gate keys on). A stub that quietly succeeded here would hide exactly the bug this
           renderer exists to prevent -- so this fake fails loudly instead.

    pr merge *
        -> ALWAYS exits 1, same reason.

    anything else
        -> exits 1 with "fake-gh: unhandled verb" on stderr, so an unexpected call fails loudly
           instead of returning an empty success that a test might misread as "nothing happened".

.NOTES
  Windows PowerShell 5.1. This file is a .ps1, not directly executable the way
  test-invoke-subagent.ps1's inline `fake-claude.cmd` is (a real `.cmd` is what a `-ClaudePath`/
  `-GhPath` parameter shells out to). If Render-ReviewVerdict.ps1's -GhPath shells out via
  `& $GhPath @args` the same way -ClaudePath does, the test suite must generate a one-line wrapper
  next to this file:

      @echo off
      powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fake-gh.ps1" %*

  and pass THAT .cmd's path as -GhPath, exactly as test-invoke-subagent.ps1 writes fake-claude.cmd
  into its own throwaway fixture directory. This file is the payload; the wrapper is the seam's
  actual executable.
#>

param()

$ErrorActionPreference = 'Stop'

$GOOD_HEAD = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$STALE_HEAD = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'

$mode = $env:FAKE_GH_MODE
if (-not $mode) { $mode = 'ok' }

$logPath = $env:FAKE_GH_LOG
if ($logPath) {
    # BUILD-LANE FIX (2026-09-22): `Add-Content -Encoding utf8` writes a fresh UTF-8 BOM on EVERY
    # call in Windows PowerShell 5.1, not just the first -- so a multi-call test (T7/T10/T11/T12,
    # each `gh` invocation a separate process) produced a log with an embedded BOM character before
    # every line after the first. [System.IO.File]::ReadAllText only strips a LEADING BOM, so those
    # later BOM bytes surfaced as invisible U+FEFF characters at the start of line 2+, breaking any
    # `^...` anchored regex match against them in the test suite. AppendAllText with a no-BOM
    # UTF8Encoding avoids writing a BOM at all.
    $noBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::AppendAllText($logPath, ($args -join ' ') + "`r`n", $noBom)
}

$verb1 = if ($args.Count -gt 0) { [string]$args[0] } else { '' }
$verb2 = if ($args.Count -gt 1) { [string]$args[1] } else { '' }

if ($verb1 -eq 'pr' -and $verb2 -eq 'view') {
    $sha = if ($mode -eq 'stale-head') { $STALE_HEAD } else { $GOOD_HEAD }
    Write-Output ('{{"headRefOid":"{0}"}}' -f $sha)
    exit 0
}

if ($verb1 -eq 'pr' -and $verb2 -eq 'comment') {
    Write-Output 'https://github.com/yodatech1988/MasterThread/pull/1#issuecomment-9990001'
    exit 0
}

if ($verb1 -eq 'pr' -and $verb2 -eq 'review') {
    Write-Error 'fake-gh: pr review must NEVER be called by Render-ReviewVerdict.ps1 (design section 3, "What it never does")'
    exit 1
}

if ($verb1 -eq 'pr' -and $verb2 -eq 'merge') {
    Write-Error 'fake-gh: pr merge must NEVER be called by Render-ReviewVerdict.ps1 (design section 3, "What it never does")'
    exit 1
}

if ($verb1 -eq 'api') {
    $apiPath = $verb2
    if ($apiPath -like '*/issues/comments/*') {
        if ($mode -eq 'readback-404') {
            Write-Error 'fake-gh: 404 Not Found (readback-404 mode)'
            exit 1
        }
        Write-Output '{"id":9990001,"html_url":"https://github.com/yodatech1988/MasterThread/pull/1#issuecomment-9990001"}'
        exit 0
    }
    if ($apiPath -like '*/issues/*/comments') {
        if ($mode -eq 'duplicate') {
            $marker = "<!-- REVIEW-VERDICT v1 agent=diff-reviewer head=$GOOD_HEAD -->"
            $body = ($marker + '\n**REVIEW-VERDICT v1 -- CHANGES_REQUESTED**')
            Write-Output ('[{{"id":8880000,"body":"{0}"}}]' -f $body)
        } else {
            Write-Output '[]'
        }
        exit 0
    }
}

Write-Error "fake-gh: unhandled verb '$verb1 $verb2' (full args: $($args -join ' '))"
exit 1
