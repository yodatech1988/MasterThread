<#
.SYNOPSIS
  One command: opens the right console page on monitor 2 AND the matching
  paste-safe key tool, side by side, for a guided credential-rotation step.

.DESCRIPTION
  This does NOT click anything for you and never touches a credential value.
  It only:
    1. Finds Mullvad Browser (falls back to Brave if Mullvad isn't installed).
    2. Launches it pointed at the create-key page for the service you pick --
       pre-filled with the right scope where the provider's URL supports it
       (OVH's createToken page does; most don't).
    3. Moves that window onto the second monitor, maximized, if one is attached.
    4. Launches the matching *Key.ps1 paste tool (jarvis/OvhApiKey/CloudflareKey/
       DiscordKey/AdminBotKey) on the primary monitor, already focused on the
       field you'll paste into -- so the whole step is: click through on
       monitor 2, copy, alt-tab, paste, Enter.

  Claude cannot drive this browser's mouse/keyboard -- there is no screen-control
  tool wired into these sessions. The guided part of the rotation happens in the
  chat: Claude tells you what to click, in order. See the "Guided Key Rotation"
  plan artifact for the full runbook this script is meant to be used alongside.

.PARAMETER Service
  Which rotation to start: anthropic | cloudflare | ovh | discord-community | discord-admin

.EXAMPLE
  .\AEGIS-Key-Rotation-Session.ps1 -Service ovh
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('anthropic', 'cloudflare', 'ovh', 'discord-community', 'discord-admin')]
    [string]$Service
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot

# OVH's createToken page accepts repeated method=path params and pre-fills the
# rights list -- matches the "Claude Admin" app's existing scope (see
# core/tools/OvhApiKey.ps1): GET/POST/PUT/PATCH on /vps/*, no DELETE.
$ovhRights = 'GET=/vps&GET=/vps/*&POST=/vps/*&PUT=/vps/*&PATCH=/vps/*'

$urls = @{
    'anthropic'         = 'https://console.anthropic.com/settings/keys'
    'cloudflare'        = 'https://dash.cloudflare.com/profile/api-tokens'
    'ovh'               = "https://eu.api.ovh.com/createToken/index.cgi?$ovhRights"
    'discord-community' = 'https://discord.com/developers/applications'
    'discord-admin'     = 'https://discord.com/developers/applications'
}

# The paste-safe local tool to open alongside the browser, and how to launch it.
$pasteTools = @{
    'anthropic'         = @{ Path = "$Root\jarvis\tools\set-runtime-key.ps1"; Windowed = $false }
    'ovh'               = @{ Path = "$Root\core\tools\OvhApiKey.ps1"; Windowed = $true }
    'cloudflare'        = @{ Path = "$Root\core\tools\CloudflareKey.ps1"; Windowed = $true }
    'discord-community' = @{ Path = "$Root\claude-agents\scripts\DiscordKey.ps1"; Windowed = $true }
    'discord-admin'     = @{ Path = "$Root\services\admin-bot\tools\AdminBotKey.ps1"; Windowed = $true }
}

$url = $urls[$Service]
$tool = $pasteTools[$Service]

function Find-Browser {
    $candidates = @(
        "$env:LOCALAPPDATA\Mullvad Browser\mullvadbrowser.exe",
        "${env:ProgramFiles}\Mullvad Browser\mullvadbrowser.exe",
        "${env:ProgramFiles(x86)}\Mullvad Browser\mullvadbrowser.exe",
        "${env:ProgramFiles}\BraveSoftware\Brave-Browser\Application\brave.exe",
        "${env:LOCALAPPDATA}\BraveSoftware\Brave-Browser\Application\brave.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

$browser = Find-Browser
if (-not $browser) {
    Write-Host ""
    Write-Host "No de-identified browser found (Mullvad Browser or Brave)." -ForegroundColor Yellow
    Write-Host "Install Mullvad Browser first: https://mullvad.net/en/browser" -ForegroundColor Yellow
    Write-Host "(This script will not install anything for you -- that's a deliberate" -ForegroundColor Yellow
    Write-Host " click-through, same as everything else that creates or downloads new" -ForegroundColor Yellow
    Write-Host " executables.)" -ForegroundColor Yellow
    exit 1
}

# Launch with a dedicated, isolated profile directory so this never shares
# cookies/history/logins with your everyday browser.
$profileDir = Join-Path $env:LOCALAPPDATA "AEGIS\rotation-browser-profile"
New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

if ($browser -like '*mullvadbrowser.exe') {
    # Mullvad Browser resets on every launch by design -- no separate profile flag needed.
    $proc = Start-Process -FilePath $browser -ArgumentList $url -PassThru
} else {
    $proc = Start-Process -FilePath $browser -ArgumentList @("--user-data-dir=`"$profileDir`"", "--no-first-run", $url) -PassThru
}

Write-Host "Launched $([IO.Path]::GetFileName($browser)) -> $url" -ForegroundColor Green

# Open the matching paste tool right away so it's waiting when you copy the
# new value -- no hunting for the right script mid-rotation.
if ($tool -and (Test-Path $tool.Path)) {
    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if (-not $tool.Windowed) {
        # Console (Read-Host) tools close immediately when the script ends, taking
        # their "next step" instructions with them -- keep the window open so you
        # can still read what to run next.
        $psArgs += '-NoExit'
    }
    $psArgs += @('-File', "`"$($tool.Path)`"")
    Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs | Out-Null
    Write-Host "Opened paste tool: $($tool.Path)" -ForegroundColor Green
} elseif ($tool) {
    Write-Host "Paste tool not found at $($tool.Path) -- run it manually once it exists." -ForegroundColor Yellow
}

# Give the browser window a moment to exist, then move it to monitor 2 if one is present.
Start-Sleep -Seconds 2

Add-Type -AssemblyName System.Windows.Forms
$screens = [System.Windows.Forms.Screen]::AllScreens
if ($screens.Count -lt 2) {
    Write-Host "Only one monitor detected -- window left on the primary display." -ForegroundColor Yellow
    exit 0
}
$second = $screens | Where-Object { -not $_.Primary } | Select-Object -First 1

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Rotation {
    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

$hwnd = $proc.MainWindowHandle
if ($hwnd -eq [IntPtr]::Zero) {
    Start-Sleep -Seconds 2
    $proc.Refresh()
    $hwnd = $proc.MainWindowHandle
}
if ($hwnd -ne [IntPtr]::Zero) {
    $b = $second.Bounds
    [Win32Rotation]::MoveWindow($hwnd, $b.X, $b.Y, $b.Width, $b.Height, $true) | Out-Null
    [Win32Rotation]::ShowWindow($hwnd, 3) | Out-Null  # SW_MAXIMIZE
    Write-Host "Moved to monitor 2 ($($second.DeviceName)) and maximized." -ForegroundColor Green
} else {
    Write-Host "Couldn't get the window handle to reposition it -- drag it to monitor 2 manually." -ForegroundColor Yellow
}
