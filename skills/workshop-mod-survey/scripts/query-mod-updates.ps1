<#
.SYNOPSIS
  Read-only helper for the workshop-mod-survey skill. Calls Steam's public,
  unauthenticated GetPublishedFileDetails API for a batch of DayZ Workshop
  IDs and prints title/time_updated/file_size/consumer_app_id/subscriptions.

.DESCRIPTION
  No Steam API key or credential of any kind is used or required — this is
  the same public POST endpoint documented in the memory note
  steam-workshop-research-method-2026-09-16.md. This script only ever makes
  a GET/POST read call; it never subscribes, downloads, or writes to Steam.

.PARAMETER Ids
  One or more published file IDs (Workshop item IDs) to query.

.PARAMETER OutFile
  Optional path to also write the results as JSON (for later diffing against
  a prior survey run). If omitted, results are only written to the pipeline/
  console.

.EXAMPLE
  .\query-mod-updates.ps1 -Ids 2545327648,1559212036 -OutFile snapshot.json

.NOTES
  Flags (from steam-workshop-research-method-2026-09-16.md):
  - consumer_app_id must be 221100 (DayZ) — Steam's Workshop API is shared
    across games; a non-221100 result means the ID picked up the wrong game
    and should be dropped, not silently reported.
  - Use `subscriptions`, not `views`, for popularity — `views` inflates.
  - A "banned"/"removed" flag is often a false positive; only treat a mod as
    genuinely gone when the API returns result code 9 (absence) or banned=1
    with a real ban_reason.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$Ids,

    [string]$OutFile
)

$body = @{ itemcount = $Ids.Count }
for ($i = 0; $i -lt $Ids.Count; $i++) {
    $body["publishedfileids[$i]"] = $Ids[$i]
}

$uri = 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/'
$resp = Invoke-RestMethod -Method Post -Uri $uri -Body $body

$epoch = Get-Date '1970-01-01Z'

$rows = foreach ($item in $resp.response.publishedfiledetails) {
    [pscustomobject]@{
        publishedfileid = $item.publishedfileid
        result          = $item.result
        title           = $item.title
        consumer_app_id = $item.consumer_app_id
        is_dayz         = ($item.consumer_app_id -eq 221100)
        time_updated    = $item.time_updated
        time_updated_utc = if ($item.time_updated) { $epoch.AddSeconds([double]$item.time_updated).ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
        file_size       = $item.file_size
        subscriptions   = $item.subscriptions
        banned          = $item.banned
        ban_reason      = $item.ban_reason
    }
}

$rows | Format-Table -AutoSize

if ($OutFile) {
    $rows | ConvertTo-Json -Depth 4 | Set-Content -Path $OutFile -Encoding utf8
    Write-Host "Wrote snapshot: $OutFile"
}
