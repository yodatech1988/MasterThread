# One click, safe to re-run any time: finishes moving AEGIS services onto the OVH VPS.
#  1. Points the public hostnames at the VPS tunnel (aegis-vps).
#  2. Checks them, and stops the old PC copy of community-api once the VPS one answers.
#  3. Starts every remaining VPS service whose key window has been saved; lists what's still missing.
# Runbook: services repo docs/ops/VPS.md.
$ErrorActionPreference = 'Continue'
$cf   = 'C:\Program Files (x86)\cloudflared\cloudflared.exe'
$pm2  = 'C:\Users\yoda_\AppData\Local\npm-cache\_npx\88423ebea83aeef1\node_modules\pm2\bin\pm2'
$push = 'C:\Users\yoda_\GitHub\_wt-services-ovh-migration\tools\PushVpsSecrets.ps1'
$aegis = Join-Path $env:APPDATA 'AEGIS'
function Step($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
function Good($m) { Write-Host "   OK  $m" -ForegroundColor Green }
function Todo($m) { Write-Host "   TODO $m" -ForegroundColor Yellow }

Step 'Public hostnames -> VPS tunnel'
foreach ($h in 'community-api.aegisdirective.net', 'economy-api.aegisdirective.net', 'events.aegisdirective.net') {
    & $cf tunnel route dns --overwrite-dns aegis-vps $h 2>&1 | Select-String 'INF|ERR' | ForEach-Object { "   $_" }
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

Step 'VPS services waiting on key windows'
$needs = [ordered]@{
    'event-relay'       = @{ Store = 'discord-webhooks'; Window = 'the "AEGIS Discord webhooks" window (services tools\DiscordWebhooksKey.ps1)' }
    'chat-monitor'      = @{ Store = 'discord-webhooks'; Window = 'the "AEGIS Discord webhooks" window (services tools\DiscordWebhooksKey.ps1)' }
    'admin-bot'         = @{ Store = 'admin-bot';        Window = 'the "AEGIS Admin" window (services admin-bot\tools\AdminBotKey.ps1)' }
    'discord-community' = @{ Store = 'discord';          Window = 'claude-agents scripts\Setup-DiscordKey.bat' }
}
foreach ($svc in $needs.Keys) {
    if (Test-Path (Join-Path $aegis "$($needs[$svc].Store).clixml")) {
        Write-Host "   starting $svc on the VPS..."
        try { & $push $svc; Good $svc } catch { Todo "$svc failed: $($_.Exception.Message)" }
    } else {
        Todo "$svc - save $($needs[$svc].Window), then run this again"
    }
}

Read-Host "`nPress Enter to close"
