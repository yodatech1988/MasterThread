# Standing human-gated merge tool for merge-authority.
# Reads a queue of QC-approved PRs grouped by tier, shows Jeremy a full summary of
# each (tier, QC verdict/verifier, authoring session, live-system warning where it
# applies) in a dialog, and merges ONLY the ones he clicks Approve then confirms.
# No typing anywhere in the decision flow (2026-09-16: Jeremy's request - a present
# human clicking deliberately satisfies the same intent a typed YES did). No batch
# auto-approve, no all-or-nothing prompt, no way for an agent session to script past
# this - it must be run by hand, on Jeremy's own PC, one Approve + one confirmed Yes
# per PR. The confirm dialog defaults to No so a reflexive Enter/Space merges nothing.
#
# Queue file format (JSON array), default path below, override with -QueuePath:
# [
#   {
#     "repo": "yodatech1988/aegis-core",
#     "pr": 123,
#     "tier": 1,
#     "qcVerdict": "PASS",
#     "qcVerifier": "github-6b via diff-reviewer",
#     "qcSummary": "One-line reason from the reviewing agent/session.",
#     "authorSession": "github-4f",
#     "mergeMethod": "squash",
#     "liveWarning": "Arms a live economy change on next server restart.",
#     "dependsOn": ["yodatech1988/MasterThread#54"]
#   }
# ]
#
# - tier defaults to 0 (shown as "untiered") if omitted.
# - mergeMethod defaults to squash if omitted.
# - liveWarning is optional; when set it's shown as a prominent banner in the approval
#   dialog AND repeated in the confirm dialog, but is expected on Tier 4 (live-system)
#   entries.
# - QC/authoring fields are free text - this tool doesn't validate them, it just
#   displays what the queue-writer put there so the click is an informed decision,
#   not a rubber stamp.
# - dependsOn is optional: a string or array of "owner/repo#pr" references (a bare
#   number means "same repo as this entry"). ENFORCED, not just displayed: before any
#   dialog is shown, every dependency is checked live via `gh pr view --json state`
#   and must be MERGED, or this entry is auto-skipped with no dialog offered at all.
#   Fails closed - a `gh` error or an unexpected response is treated as an unmet
#   dependency, never waved through.

param(
    [string]$QueuePath = "C:\Users\yoda_\GitHub\merge-queue.json"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Step($m)  { Write-Host "`n== $m" -ForegroundColor Cyan }
function Good($m)  { Write-Host "   OK  $m" -ForegroundColor Green }
function Skip($m)  { Write-Host "   SKIP $m" -ForegroundColor Yellow }
function Bad($m)   { Write-Host "   FAIL $m" -ForegroundColor Red }
function Warn($m)  { Write-Host $m -ForegroundColor Red -BackgroundColor Black }

# Resolves a "owner/repo#123" or bare "123" dependency reference against $defaultRepo,
# and returns $true only if `gh` confirms it's actually MERGED. Any failure to get a
# clean, expected answer counts as unmet - this must fail closed, never open.
function Test-DependencyMerged($ref, $defaultRepo) {
    $refRepo = $defaultRepo
    $refPr = $ref
    if ($ref -match '^(?<repo>[^#]+)#(?<pr>\d+)$') {
        $refRepo = $Matches.repo
        $refPr = $Matches.pr
    }
    try {
        $dep = gh pr view $refPr --repo $refRepo --json state 2>$null | ConvertFrom-Json
    } catch {
        return @{ Merged = $false; Ref = "$refRepo#$refPr"; State = "ERROR: $($_.Exception.Message)" }
    }
    if (-not $dep -or -not $dep.state) {
        return @{ Merged = $false; Ref = "$refRepo#$refPr"; State = "ERROR: no state returned" }
    }
    return @{ Merged = ($dep.state -eq 'MERGED'); Ref = "$refRepo#$refPr"; State = $dep.state }
}

# Per-PR dialog with the full context, and three real buttons - no typing, no default
# action wired to Enter/Space beyond focus order landing on Skip (the safe choice).
function Show-PrApprovalDialog($repo, $pr, $view, $item, $tierLabel, $method) {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Merge queue - $repo #$pr"
    $form.Size = New-Object System.Drawing.Size(620, 480)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.TopMost = $true

    $lines = @(
        "Repo:          $repo"
        "PR:             #$pr"
        "Title:          $($view.title)"
        "URL:            $($view.url)"
        "Author:         $($view.author.login)"
        "Changed:        +$($view.additions) -$($view.deletions) across $($view.changedFiles) file(s)"
        "Mergeable:      $($view.mergeable)"
        "Tier:           $tierLabel"
        "QC verdict:     $($item.qcVerdict)"
        "QC verifier:    $($item.qcVerifier)"
        "QC summary:     $($item.qcSummary)"
    )
    if ($item.authorSession) { $lines += "Authored by:    $($item.authorSession)" }
    $lines += "Merge method:   $method"
    if ($item.liveWarning) {
        $lines += ""
        $lines += "!!! LIVE SYSTEM WARNING !!!"
        $lines += $item.liveWarning
    }

    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ReadOnly = $true
    $box.ScrollBars = 'Vertical'
    $box.Font = New-Object System.Drawing.Font('Consolas', 9)
    $box.Location = New-Object System.Drawing.Point(10, 10)
    $box.Size = New-Object System.Drawing.Size(585, 360)
    $box.Text = ($lines -join "`r`n")
    if ($item.liveWarning) { $box.BackColor = [System.Drawing.Color]::MistyRose }
    $form.Controls.Add($box)

    $btnApprove = New-Object System.Windows.Forms.Button
    $btnApprove.Text = 'Approve'
    $btnApprove.Location = New-Object System.Drawing.Point(10, 390)
    $btnApprove.Size = New-Object System.Drawing.Size(180, 40)
    $btnApprove.DialogResult = [System.Windows.Forms.DialogResult]::Yes
    $form.Controls.Add($btnApprove)

    $btnSkip = New-Object System.Windows.Forms.Button
    $btnSkip.Text = 'Skip this PR'
    $btnSkip.Location = New-Object System.Drawing.Point(205, 390)
    $btnSkip.Size = New-Object System.Drawing.Size(180, 40)
    $btnSkip.DialogResult = [System.Windows.Forms.DialogResult]::No
    $form.Controls.Add($btnSkip)

    $btnStop = New-Object System.Windows.Forms.Button
    $btnStop.Text = 'Stop this pass'
    $btnStop.Location = New-Object System.Drawing.Point(400, 390)
    $btnStop.Size = New-Object System.Drawing.Size(195, 40)
    $btnStop.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($btnStop)

    # Skip is the safe default focus/accept target, not Approve - Enter alone never merges.
    $form.AcceptButton = $btnSkip
    $form.CancelButton = $btnStop
    $btnSkip.Select()

    $result = $form.ShowDialog()
    $form.Dispose()

    switch ($result) {
        'Yes'    { return 'Approve' }
        'No'     { return 'Skip' }
        default  { return 'Stop' }
    }
}

# Names the specific PR, repeats the live warning if present, and defaults to No so a
# reflexive Enter/Space confirms nothing. This is the actual merge gate.
function Show-ConfirmDialog($repo, $pr, $item) {
    $text = "Merge $repo #$pr into main now?"
    if ($item.liveWarning) {
        $text += "`n`n!!! LIVE SYSTEM WARNING !!!`n$($item.liveWarning)"
    }
    $result = [System.Windows.Forms.MessageBox]::Show(
        $text,
        "Confirm merge - $repo #$pr",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2  # Button2 = No
    )
    return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
}

if (-not (Test-Path $QueuePath)) {
    Bad "No queue file at $QueuePath"
    [System.Windows.Forms.MessageBox]::Show("No queue file at $QueuePath", "Merge queue") | Out-Null
    exit 1
}

$queue = Get-Content $QueuePath -Raw | ConvertFrom-Json
if (-not $queue -or $queue.Count -eq 0) {
    Write-Host "Queue is empty - nothing to review."
    [System.Windows.Forms.MessageBox]::Show("Queue is empty - nothing to review.", "Merge queue") | Out-Null
    exit 0
}

Write-Host "AEGIS Merge Queue - $($queue.Count) PR(s) awaiting your decision, grouped by tier."
Write-Host "Every decision is a click, not typing: Approve -> a Yes/No confirm (defaults to No),"
Write-Host "Skip, or Stop. Nothing merges without Approve AND a confirmed Yes for that specific PR."

$merged = @()
$skipped = @()
$failed = @()
$stopped = $false

$tiers = $queue | Group-Object { if ($null -ne $_.tier) { [int]$_.tier } else { 0 } } | Sort-Object Name

foreach ($tierGroup in $tiers) {
    if ($stopped) { break }

    $tierLabel = if ($tierGroup.Name -eq '0') { 'untiered' } else { "Tier $($tierGroup.Name)" }
    Write-Host "`n#################### $tierLabel - $($tierGroup.Count) PR(s) ####################" -ForegroundColor Magenta

    foreach ($item in $tierGroup.Group) {
        if ($stopped) { break }

        $repo = $item.repo
        $pr = $item.pr
        $method = if ($item.mergeMethod) { $item.mergeMethod } else { 'squash' }

        Step "$repo#$pr [$tierLabel]"

        try {
            $view = gh pr view $pr --repo $repo --json title,url,additions,deletions,changedFiles,author,mergeable | ConvertFrom-Json
        } catch {
            Bad "could not load $repo#$pr from GitHub: $($_.Exception.Message)"
            $failed += "$repo#$pr (could not load)"
            continue
        }

        Write-Host "   Title:         $($view.title)"
        Write-Host "   Tier:          $tierLabel"
        Write-Host "   QC verdict:    $($item.qcVerdict)"
        if ($item.liveWarning) { Warn "   !!! LIVE SYSTEM WARNING: $($item.liveWarning) !!!" }

        if ($view.mergeable -eq 'CONFLICTING') {
            Skip "$repo#$pr has merge conflicts - resolve before it can be merged"
            $skipped += "$repo#$pr (conflicting)"
            continue
        }

        if ($item.dependsOn) {
            $deps = @($item.dependsOn)
            $unmet = @()
            foreach ($d in $deps) {
                $result = Test-DependencyMerged $d $repo
                Write-Host "   Depends on:    $($result.Ref) - $($result.State)"
                if (-not $result.Merged) { $unmet += $result.Ref }
            }
            if ($unmet.Count -gt 0) {
                Warn "   !!! DEPENDENCY NOT MET: $($unmet -join ', ') - skipping, no dialog offered !!!"
                $skipped += "$repo#$pr (unmet dependency: $($unmet -join ', '))"
                continue
            }
        }

        $decision = Show-PrApprovalDialog $repo $pr $view $item $tierLabel $method
        Write-Host "   Dialog result: $decision"

        if ($decision -eq 'Stop') {
            Skip "$repo#$pr (stopped)"
            $skipped += "$repo#$pr (stopped)"
            $stopped = $true
            continue
        }
        if ($decision -eq 'Skip') {
            Skip "$repo#$pr"
            $skipped += "$repo#$pr"
            continue
        }

        $confirmed = Show-ConfirmDialog $repo $pr $item
        if (-not $confirmed) {
            Skip "$repo#$pr (not confirmed)"
            $skipped += "$repo#$pr (not confirmed)"
            continue
        }

        try {
            gh pr merge $pr --repo $repo "--$method" --delete-branch 2>&1 | ForEach-Object { "   $_" }
            Good "$repo#$pr merged ($method)"
            $merged += "$repo#$pr"
        } catch {
            Bad "$repo#$pr merge failed: $($_.Exception.Message)"
            $failed += "$repo#$pr (merge failed)"
        }
    }
}

$summary = "Merged:  $($merged.Count) - $($merged -join ', ')`nSkipped: $($skipped.Count) - $($skipped -join ', ')`nFailed:  $($failed.Count) - $($failed -join ', ')"
if ($stopped) { $summary += "`n`nStopped early by request - remaining entries untouched, re-run to pick up where you left off." }

Write-Host "`n== Summary =="
Write-Host $summary

[System.Windows.Forms.MessageBox]::Show($summary, "Merge queue - finished") | Out-Null
