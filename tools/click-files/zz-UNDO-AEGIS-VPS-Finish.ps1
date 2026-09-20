<#
.SYNOPSIS
  Undo guide for AEGIS-VPS-Finish.ps1. Prints the manual steps; changes nothing itself.

.DESCRIPTION
  AEGIS-VPS-Finish runs `cloudflared tunnel route dns --overwrite-dns aegis-vps <host>` for three
  hostnames, which REPLACES whatever DNS record each hostname had. This script cannot restore the old
  records automatically: it makes no Cloudflare call and holds no credential.
  Before applying, AEGIS-VPS-Finish saves the hostnames' prior DNS answers next to itself as
  AEGIS-VPS-Finish.<stamp>.prior-dns.txt (a local DNS lookup, read-only). Use that file to see what to restore.
#>
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "== UNDO GUIDE for AEGIS-VPS-Finish (prints steps only, changes nothing)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Saved prior-DNS files next to this script:" -ForegroundColor Yellow
$saved = Get-ChildItem -Path $here -Filter 'AEGIS-VPS-Finish.*.prior-dns.txt' -ErrorAction SilentlyContinue
if ($saved) { $saved | ForEach-Object { Write-Host "   $($_.FullName)" } } else { Write-Host "   (none found - the apply was never run from this folder)" }
Write-Host ""
Write-Host "To put the old routing back:" -ForegroundColor Yellow
Write-Host "  1. Cloudflare dashboard > aegisdirective.net > DNS > Records."
Write-Host "  2. For community-api, economy-api and events: edit each record back to the target in the prior-dns file."
Write-Host "  3. If community-api was stopped on this PC, restart it: pm2 start community-api cloudflared-community-api"
Write-Host ""
Read-Host "Press Enter to close" | Out-Null
