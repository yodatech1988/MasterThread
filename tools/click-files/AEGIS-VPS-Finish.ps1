<#
.SYNOPSIS
  Owner-run. One click, safe to re-run any time: finishes moving AEGIS services onto the OVH VPS.
  - Points public hostnames at the VPS tunnel (aegis-vps).
  - Checks them, stops the old PC copy of community-api once the VPS one answers.
  - Starts every remaining VPS service whose key window has been saved.
  Gates: typed YES per target, -WhatIf to show DNS changes without applying.
  Undo: run zz-UNDO-AEGIS-VPS-Finish.ps1.

.PARAMETER WhatIf
  Show the tunnel route dns calls without executing them. Also shows the current hostnames.

.EXAMPLE
  .\AEGIS-VPS-Finish.ps1              # Apply the routing changes
  .\AEGIS-VPS-Finish.ps1 -WhatIf      # Show what will happen, read-only
#>
param(
    [switch]$WhatIf
)

$ErrorActionPreference = 'Continue'
$cf   = 'C:\Program Files (x86)\cloudflared\cloudflared.exe'
$pm2  = 'C:\Users\yoda_\AppData\Local\npm-cache\_npx\88423ebea83aeef1\node_modules\pm2\bin\pm2'
# Fixed path: PushVpsSecrets.ps1 is in services/tools, not a deleted worktree
$push = 'C:\Users\yoda_\GitHub\services\tools\PushVpsSecrets.ps1'
$aegis = Join-Path $env:APPDATA 'AEGIS'

function Step($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
function Good($m) { Write-Host "   OK  $m" -ForegroundColor Green }
function Todo($m) { Write-Host "   TODO $m" -ForegroundColor Yellow }
function Warn($m) { Write-Host "   WARN $m" -ForegroundColor Yellow }

if ($WhatIf) {
    Write-Host "Running in read-only mode (-WhatIf). No changes will be made." -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "== GATE: Confirm before routing public hostnames to the VPS tunnel" -ForegroundColor Red
    Write-Host "This action points community-api, economy-api, and events at the VPS tunnel." -ForegroundColor Yellow
    Write-Host "It cannot be undone by running this script; use zz-UNDO-AEGIS-VPS-Finish.ps1 instead." -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "Type YES (capital letters) to confirm, or anything else to cancel"
    if ($confirm -ne "YES") {
        Write-Host "Cancelled. No changes made." -ForegroundColor Green
        exit 0
    }
}

Step 'Public hostnames -> VPS tunnel'
$hostnames = @('community-api.aegisdirective.net', 'economy-api.aegisdirective.net', 'events.aegisdirective.net')

if ($WhatIf) {
    Write-Host "Current hostnames (would be changed if -WhatIf is removed):" -ForegroundColor Yellow
    foreach ($h in $hostnames) {
        Write-Host "   $h" -ForegroundColor Yellow
    }
    Write-Host "Would route each to: aegis-vps tunnel" -ForegroundColor Yellow
} else {
    $priorFile = Join-Path $PSScriptRoot ("AEGIS-VPS-Finish.{0}.prior-dns.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    foreach ($h in $hostnames) {
        $prior = try { (Resolve-DnsName $h -ErrorAction Stop | Out-String).Trim() } catch { "lookup failed: $($_.Exception.Message)" }
        Add-Content -Path $priorFile -Value "== $h`r`n$prior`r`n"
    }
    Write-Host "   Prior DNS answers saved to $priorFile"
    foreach ($h in $hostnames) {
        & $cf tunnel route dns --overwrite-dns aegis-vps $h 2>&1 | Select-String 'INF|ERR' | ForEach-Object { "   $_" }
    }
    Good "Hostnames routed to VPS tunnel"
}

Step 'Checking the public endpoints (DNS can take a minute)'
function Probe($url, $method = 'GET') {
    foreach ($i in 1..12) {
        try {
            $r = Invoke-WebRequest $url -Method $method -UseBasicParsing -TimeoutSec 10
            return [int]$r.StatusCode
        } catch {
            if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
            Start-Sleep 10
        }
    }
    return 0
}

if ($WhatIf) {
    Write-Host "Would probe endpoints (skipped in -WhatIf mode)" -ForegroundColor Yellow
} else {
    $community = Probe 'https://community-api.aegisdirective.net/v1/health'
    if ($community -eq 200) { Good 'community-api 200' } else { Todo "community-api returned $community" }
    $economy = Probe 'https://economy-api.aegisdirective.net/v1/health'
    if ($economy -eq 200) { Good 'economy-api 200' } else { Todo "economy-api returned $economy" }
    $events = Probe 'https://events.aegisdirective.net/events' 'POST'
    if ($events -eq 401) { Good 'event-relay 401 without a secret (correct)' } else { Todo "event-relay returned $events" }

    if ($community -eq 200) {
        Step 'Stopping the old PC copy of community-api'
        & node $pm2 stop community-api cloudflared-community-api 2>&1 | Out-Null
        & node $pm2 save 2>&1 | Out-Null
        Good 'PC community-api + its tunnel stopped (pm2 start community-api cloudflared-community-api to undo)'
    }
}

Step 'VPS services waiting on key windows'
$needs = [ordered]@{
    'event-relay'       = @{ Store = 'discord-webhooks'; Window = 'the "AEGIS Discord webhooks" window (services tools\DiscordWebhooksKey.ps1)' }
    'chat-monitor'      = @{ Store = 'discord-webhooks'; Window = 'the "AEGIS Discord webhooks" window (services tools\DiscordWebhooksKey.ps1)' }
    'admin-bot'         = @{ Store = 'admin-bot';        Window = 'the "AEGIS Admin" window (services admin-bot\tools\AdminBotKey.ps1)' }
    'discord-community' = @{ Store = 'discord';          Window = 'claude-agents scripts\Setup-DiscordKey.bat' }
}

if ($WhatIf) {
    Write-Host "Would start services from the DPAPI stores (skipped in -WhatIf mode)" -ForegroundColor Yellow
} else {
    foreach ($svc in $needs.Keys) {
        if (Test-Path (Join-Path $aegis "$($needs[$svc].Store).clixml")) {
            Write-Host "   starting $svc on the VPS..."
            try { & $push $svc; Good $svc } catch { Todo "$svc failed: $($_.Exception.Message)" }
        } else {
            Todo "$svc - save $($needs[$svc].Window), then run this again"
        }
    }
}

if (-not $WhatIf) {
    Write-Host "`n== Done. Press Enter to close" -ForegroundColor Cyan
    Read-Host "" > $null
}
