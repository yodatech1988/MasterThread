<#
.SYNOPSIS
  Capture GitHub account 2FA recovery codes ONCE, encrypted for this Windows
  account. Nothing here talks to GitHub -- it's just a durable, private place
  to put the recovery codes GitHub shows you exactly once when you enable 2FA,
  so they aren't lost in a screenshot or a sticky note.

.DESCRIPTION
  Run with no arguments: opens a window to paste the account login and the
  recovery codes, and to view them back later if you ever need one.

  Stored with Windows DPAPI (Export-Clixml) to %APPDATA%\AEGIS\github-2fa.clixml.
  Only this Windows user, on this machine, can decrypt it. Same design as
  DiscordKey.ps1 and RconKey.ps1 in claude-agents/scripts.

  This does NOT store a TOTP seed and cannot generate 2FA codes -- use an
  authenticator app (1Password, Authy, Google Authenticator) for day-to-day
  sign-in. This is a backup for the one-time recovery codes GitHub gives you
  when 2FA is enabled, for the case where the authenticator app/device is
  lost.
#>
[CmdletBinding(PositionalBinding = $false)]
param()

$ErrorActionPreference = 'Stop'

$StoreDir = Join-Path $env:APPDATA 'AEGIS'
$StorePath = Join-Path $StoreDir 'github-2fa.clixml'

function Get-StoredConfig {
    if (Test-Path $StorePath) { return Import-Clixml $StorePath }
    return $null
}

function Save-Config($login, [securestring]$recoveryCodes) {
    New-Item -ItemType Directory -Force $StoreDir | Out-Null
    [pscustomobject]@{
        Login         = $login
        RecoveryCodes = $recoveryCodes
        SavedAtUtc    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')
    } | Export-Clixml -Path $StorePath
}

function ConvertFrom-Secure([securestring]$s) {
    if (-not $s) { return '' }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function P([string]$xy) { $a = $xy.Split(','); New-Object System.Drawing.Point([int]$a[0], [int]$a[1]) }
function S([string]$wh) { $a = $wh.Split(','); New-Object System.Drawing.Size([int]$a[0], [int]$a[1]) }

$stored = Get-StoredConfig
$form = New-Object System.Windows.Forms.Form
$form.Text = 'GitHub 2FA recovery codes'
$form.Size = (S '620,520')
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$intro = New-Object System.Windows.Forms.Label
$intro.Location = (P '12,10'); $intro.Size = (S '580,80')
$intro.Text = "Set this once. Encrypted for your Windows account only ($StorePath).`r`n" +
    "After you enable 2FA at github.com/settings/security, GitHub shows a one-time list " +
    "of recovery codes -- paste all of them below (one per line, or however GitHub gave them " +
    "to you) before closing that page."
$form.Controls.Add($intro)

$y = 98
$loginLabel = New-Object System.Windows.Forms.Label
$loginLabel.Location = (P "12,$($y + 3)"); $loginLabel.Size = (S '190,20'); $loginLabel.Text = 'GitHub username'
$loginBox = New-Object System.Windows.Forms.TextBox
$loginBox.Location = (P "210,$y"); $loginBox.Size = (S '380,22')
$loginBox.Text = $(if ($stored) { $stored.Login } else { 'yodatech1988' })
$form.Controls.Add($loginLabel); $form.Controls.Add($loginBox)
$y += 32

$codesLabel = New-Object System.Windows.Forms.Label
$codesLabel.Location = (P "12,$y"); $codesLabel.Size = (S '400,20'); $codesLabel.Text = 'Recovery codes (paste all of them)'
$form.Controls.Add($codesLabel)
$y += 22

$codesBox = New-Object System.Windows.Forms.TextBox
$codesBox.Multiline = $true; $codesBox.ScrollBars = 'Vertical'
$codesBox.Location = (P "12,$y"); $codesBox.Size = (S '578,140')
$codesBox.Font = New-Object System.Drawing.Font('Consolas', 10)
$codesBox.UseSystemPasswordChar = $true
$form.Controls.Add($codesBox)
$y += 148

$show = New-Object System.Windows.Forms.CheckBox
$show.Location = (P "12,$y"); $show.Size = (S '300,22'); $show.Text = 'Show codes'
$show.Add_CheckedChanged({ $codesBox.UseSystemPasswordChar = -not $show.Checked })
$form.Controls.Add($show)
$y += 30

$output = New-Object System.Windows.Forms.TextBox
$output.Multiline = $true; $output.ReadOnly = $true; $output.ScrollBars = 'Vertical'
$output.Location = (P "12,$y"); $output.Size = (S '578,90')
$output.Font = New-Object System.Drawing.Font('Consolas', 9)
$output.Text = $(if ($stored) { "Codes stored for $($stored.Login) (saved $($stored.SavedAtUtc) UTC)." } else { 'No codes stored yet.' })
$form.Controls.Add($output)
$y += 100

function Write-Out($text) { $output.AppendText("`r`n" + $text); $output.ScrollToCaret(); [System.Windows.Forms.Application]::DoEvents() }

function Add-Button($text, $x, [scriptblock]$onClick) {
    $b = New-Object System.Windows.Forms.Button
    $b.Location = (P "$x,$y"); $b.Size = (S '180,32'); $b.Text = $text
    $b.Add_Click($onClick)
    $form.Controls.Add($b)
}

Add-Button 'Save' 12 {
    if (-not $loginBox.Text) { Write-Out 'Enter the GitHub username first.'; return }
    if (-not $codesBox.Text) { Write-Out 'Paste the recovery codes first.'; return }
    $secure = ConvertTo-SecureString $codesBox.Text -AsPlainText -Force
    Save-Config $loginBox.Text $secure
    $script:stored = Get-StoredConfig
    Write-Out "Saved (encrypted for $env:USERNAME) to $StorePath."
}

Add-Button 'View stored codes' 200 {
    if (-not $stored) { Write-Out 'Nothing stored yet.'; return }
    $codesBox.Text = ConvertFrom-Secure $stored.RecoveryCodes
    $show.Checked = $true
    Write-Out "Loaded codes saved $($stored.SavedAtUtc) UTC for $($stored.Login)."
}

Add-Button 'Close' 388 { $form.Close() }

[void]$form.ShowDialog()
