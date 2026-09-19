<#
  Owner-run: turn on the economy catalog sync on the OVH VPS. Launched by AEGIS-VPS-Economy-Sync.cmd.
  services docs/ops/VPS.md: the sync needs /srv/aegis/site-chernarus, cloned with its own read-only
  deploy key (~aegis/.ssh/deploy_site-chernarus, Host alias github-site-chernarus). Idempotent.
#>
$ErrorActionPreference = 'Stop'
$Admin = 'ubuntu@40.160.90.128'
$Key = Join-Path $env:USERPROFILE '.ssh\aegis-vps-admin-bot'
$Repo = 'yodatech1988/site-chernarus'
$Log = Join-Path $PSScriptRoot ("AEGIS-VPS-Economy-Sync-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
Start-Transcript -Path $Log | Out-Null
function Step($t) { Write-Host "`n=== $t" -ForegroundColor Cyan }
# Script text goes over stdin (CR stripped remotely) so nothing needs shell-quoting through PowerShell.
function VpsScript([string]$runAs, [string]$script) {
    $sudo = if ($runAs -eq 'root') { 'sudo bash -s' } else { "sudo -iu $runAs bash -s" }
    $script | & ssh -i $Key -o BatchMode=yes -o ConnectTimeout=15 $Admin "tr -d '\r' | $sudo"
    if ($LASTEXITCODE -ne 0) { throw "VPS step failed (exit $LASTEXITCODE)" }
}

try {
    Step 'Preflight'
    & gh auth status *> $null; if ($LASTEXITCODE -ne 0) { throw 'gh is not logged in' }
    & ssh -i $Key -o BatchMode=yes -o ConnectTimeout=15 $Admin hostname
    if ($LASTEXITCODE -ne 0) { throw 'cannot reach the VPS' }

    Write-Host "`nThis will: add a read-only site-chernarus deploy key, clone it on the VPS, enable the"
    Write-Host 'economy catalog sync timer, and run one sync now. It does NOT touch the DayZ server.'
    if ((Read-Host 'Type YES to proceed').Trim() -cne 'YES') { Write-Host 'Cancelled. Nothing changed.'; exit 1 }

    Step 'Deploy key on the VPS (created once)'
    $pub = @'
set -e
k=~/.ssh/deploy_site-chernarus
[ -f "$k" ] || ssh-keygen -q -t ed25519 -N "" -C "aegis-vps site-chernarus read-only" -f "$k"
grep -q "^Host github-site-chernarus$" ~/.ssh/config 2>/dev/null || printf "Host github-site-chernarus\n  HostName github.com\n  User git\n  IdentityFile ~/.ssh/deploy_site-chernarus\n  IdentitiesOnly yes\n" >> ~/.ssh/config
chmod 600 ~/.ssh/config
cat "$k.pub"
'@ | & ssh -i $Key -o BatchMode=yes $Admin "tr -d '\r' | sudo -iu aegis bash -s"
    if ($LASTEXITCODE -ne 0 -or -not $pub) { throw 'could not create the deploy key on the VPS' }
    $pubLine = ($pub | Select-Object -Last 1).Trim()
    $keyBody = ($pubLine -split ' ')[0..1] -join ' '

    Step 'Register it on GitHub (read-only)'
    $existing = (& gh api "repos/$Repo/keys" | ConvertFrom-Json) | Where-Object { $_.key -eq $keyBody }
    if ($existing) { Write-Host "  already registered (id $($existing.id))" }
    else {
        $tmp = New-TemporaryFile
        Set-Content -Path $tmp -Value $pubLine -Encoding ascii -NoNewline
        & gh repo deploy-key add $tmp --repo $Repo --title ("aegis-vps site-chernarus (read-only, " + (Get-Date -Format 'yyyy-MM-dd') + ")")
        $code = $LASTEXITCODE; Remove-Item $tmp
        if ($code -ne 0) { throw 'gh repo deploy-key add failed' }
    }

    Step 'Clone / update /srv/aegis/site-chernarus'
    VpsScript 'aegis' @'
set -e
if [ -d /srv/aegis/site-chernarus/.git ]; then git -C /srv/aegis/site-chernarus pull -q --ff-only
else git clone -q github-site-chernarus:yodatech1988/site-chernarus.git /srv/aegis/site-chernarus; fi
git -C /srv/aegis/site-chernarus log --oneline -1
'@

    Step 'Enable timers (auto)'
    VpsScript 'root' @'
set -e
bash /srv/aegis/services/ops/vps/install-scheduled-timers.sh --enable auto
systemctl list-timers --all "aegis-*" --no-pager
'@

    Step 'Run one catalog sync now'
    VpsScript 'root' @'
systemctl start aegis-economy-catalog-sync.service
echo "exit: $(systemctl show aegis-economy-catalog-sync.service -p Result --value)"
journalctl -u aegis-economy-catalog-sync.service -n 25 --no-pager -o cat
'@
    Write-Host "`nDone. Tell Claude - it will check the result. Log: $Log" -ForegroundColor Green
}
catch {
    Write-Host "`nFAILED: $($_.Exception.Message)  Tell Claude; the log is $Log" -ForegroundColor Red
    exit 1
}
finally { Stop-Transcript | Out-Null }
