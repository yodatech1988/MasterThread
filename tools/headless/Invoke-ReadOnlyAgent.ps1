<#
.SYNOPSIS
    Thin wrapper that runs a Claude Code subagent headless with the read-only permission baseline.

.DESCRIPTION
    Builds and runs the invocation recommended by
    standards/sessions/headless_agent_permissions.md: loads tools/headless/readonly.settings.json
    as a defense-in-depth deny-list, sets dontAsk + --permission-prompts none so nothing hangs
    waiting on a prompt nobody can answer, and takes an explicit -Tools allow-list (the primary
    control -- see that file for why deny-only is not enough).

    This script does not itself decide what an agent is allowed to do. The caller must pass -Tools
    scoped to what the named agent actually needs (see the Bash-usage table in the standard).

.PARAMETER AgentName
    The subagent to run, e.g. "worktree-sweep".

.PARAMETER Prompt
    The prompt to send.

.PARAMETER Tools
    Comma-separated tool allow-list passed as --tools, e.g. "Read,Grep,Bash". Required -- there is
    no safe default, since "what an agent needs" varies per agent.

.PARAMETER MaxBudgetUsd
    Passed as --max-budget-usd. Default 1.

.PARAMETER TimeoutSec
    Hard wall-clock timeout for the whole run. Default 300.

.PARAMETER SettingsPath
    Override the settings file. Default is readonly.settings.json next to this script.

.EXAMPLE
    .\Invoke-ReadOnlyAgent.ps1 -AgentName worktree-sweep -Prompt "List worktrees in MasterThread" -Tools "Bash"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$AgentName,
    [Parameter(Mandatory = $true)][string]$Prompt,
    [Parameter(Mandatory = $true)][string]$Tools,
    [double]$MaxBudgetUsd = 1,
    [int]$TimeoutSec = 300,
    [string]$SettingsPath = (Join-Path $PSScriptRoot 'readonly.settings.json'),
    [string]$Model
)

if (-not (Test-Path $SettingsPath)) {
    throw "Invoke-ReadOnlyAgent: settings file not found at $SettingsPath"
}

$claudeArgs = @(
    '--print',
    '--agent', $AgentName,
    '--settings', $SettingsPath,
    '--tools', $Tools,
    '--permission-mode', 'dontAsk',
    '--permission-prompts', 'none',
    '--strict-mcp-config',
    '--max-budget-usd', [string]$MaxBudgetUsd,
    '--output-format', 'stream-json'
)

if ($Model) {
    $claudeArgs += @('--model', $Model)
}

$claudeArgs += $Prompt

Write-Verbose "claude $($claudeArgs -join ' ')"

$stdoutFile = [System.IO.Path]::GetTempFileName()
$stderrFile = [System.IO.Path]::GetTempFileName()
$proc = Start-Process -FilePath 'claude' -ArgumentList $claudeArgs -NoNewWindow -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile

if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
    Write-Warning "Invoke-ReadOnlyAgent: '$AgentName' exceeded ${TimeoutSec}s, killing it. This is itself a finding worth reporting -- see headless_agent_permissions.md Verification section for why a run should not hang under --permission-prompts none."
    try { $proc.Kill() } catch {}
    throw "Invoke-ReadOnlyAgent: timeout after ${TimeoutSec}s running agent '$AgentName'"
}

Get-Content $stdoutFile
Get-Content $stderrFile | Write-Verbose
Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
exit $proc.ExitCode
