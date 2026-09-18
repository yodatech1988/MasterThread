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
    no safe default, since "what an agent needs" varies per agent. NOTE (2026-09-18, see -AllowedTools
    below): --tools only grants or withholds a whole tool category -- verified against `claude
    --help`, it cannot narrow to a specific Bash sub-command. Under --permission-mode dontAsk, a bare
    "Bash" grant here is NOT enough for an agent to run a specific command that isn't in Claude
    Code's small built-in read-only set -- see headless_agent_permissions.md's own verification log,
    which found exactly this failure (a harmless `git --version` denied with -Tools "Bash" alone),
    and this tool's first real headless run reproduced it live (worktree-sweep's own `git worktree
    list` denied the same way). Use -AllowedTools for the specific commands an agent actually needs.

.PARAMETER AllowedTools
    Added 2026-09-18, after the defect above was found and reproduced. Comma or space-separated
    fine-grained permission-rule entries passed as --allowedTools, e.g. "Bash(git worktree
    list:*),Bash(git status:*)" -- the ONLY flag (per `claude --help`) that accepts this specifier
    syntax; --tools cannot. Optional; defaults to nothing, so a caller that does not pass this
    parameter gets byte-identical behaviour to before this parameter existed -- confirmed by the
    tests in this PR. Pass exactly the commands the named agent's own definition demonstrably uses,
    nothing wider; this parameter does not decide that scope, the caller does (same division of
    responsibility as -Tools, per this script's own long-standing rule that it "does not itself
    decide what an agent is allowed to do").

.PARAMETER MaxBudgetUsd
    Passed as --max-budget-usd. Default 1.

.PARAMETER TimeoutSec
    Hard wall-clock timeout for the whole run. Default 300.

.PARAMETER SettingsPath
    Override the settings file. Default is readonly.settings.json next to this script.

.EXAMPLE
    .\Invoke-ReadOnlyAgent.ps1 -AgentName worktree-sweep -Prompt "List worktrees in MasterThread" -Tools "Bash"

.NOTES
    Exit codes (fixed 2026-09-18, see below): 0 = the `claude` process ran and exited 0.
    Any other integer = the `claude` process's own real exit code, propagated as-is. 2 = this
    wrapper itself failed to resolve or launch `claude` (never reached the subprocess at all).
    3 = the run timed out and was killed. A non-zero exit here is always paired with an error
    written to the report output -- never a silent fallthrough.

    2026-09-18 fix, two defects found the same night this script's first real headless run was
    attempted (PM_INBOX github-43-20260918T0403Z-l1pilot-build-and-crosslinks.md):

    1. `Start-Process -FilePath 'claude'` resolved to the WRONG file. On this machine `claude` is
       installed by npm as three files in the same directory: a bare `claude` (a `#!/bin/sh`
       shebang script for git-bash/WSL, no extension), `claude.cmd` (the Windows wrapper), and
       `claude.ps1`. `Start-Process`'s exact-name match finds the bare `claude` file BEFORE
       PATHEXT-suffixed resolution ever tries `claude.cmd` -- and Windows cannot execute a shell
       script directly, so `Start-Process` failed with "%1 is not a valid Win32 application" on
       every call. Verified live: `Start-Process -FilePath 'claude'` fails this way;
       `Start-Process -FilePath 'claude.cmd'` succeeds and returns real output (`claude --version`
       -> "2.1.273 (Claude Code)"). Fix: resolve `claude.cmd` explicitly via `Get-Command`, never
       the bare ambiguous name.
    2. The failure was swallowed, not propagated. This script had no `$ErrorActionPreference`
       set, so `Start-Process`'s failure was a non-terminating error: execution continued to
       `$proc.WaitForExit(...)` with `$proc` still `$null`, which itself errors non-terminating
       under the default preference, and execution continued AGAIN to the final line,
       `exit $proc.ExitCode` -- with `$proc` null, `$proc.ExitCode` is `$null`, and `exit $null`
       in PowerShell exits 0. So a run that never launched `claude` at all reported success.
       Fix: `$ErrorActionPreference = 'Stop'` plus an outer try/catch around every step that can
       fail, each catch printing the exception and exiting a documented non-zero code -- no path
       reaches `exit` with an unset or null value.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$AgentName,
    [Parameter(Mandatory = $true)][string]$Prompt,
    [Parameter(Mandatory = $true)][string]$Tools,
    [string]$AllowedTools,
    [double]$MaxBudgetUsd = 1,
    [int]$TimeoutSec = 300,
    [string]$SettingsPath = (Join-Path $PSScriptRoot 'readonly.settings.json'),
    [string]$Model
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $SettingsPath)) {
    # NOTE: Write-Error is itself a terminating error under $ErrorActionPreference = 'Stop' and
    # would skip the explicit `exit 2` below, falling through to PowerShell's own default exit 1
    # for an unhandled error -- verified empirically 2026-09-18. Write-Host + explicit exit
    # guarantees the documented code regardless of preference, same convention the estate's other
    # click-files use for a controlled, known-cause exit.
    Write-Host "Invoke-ReadOnlyAgent: settings file not found at $SettingsPath" -ForegroundColor Red
    exit 2
}

# Resolve the real Windows executable explicitly -- never the bare 'claude' name, which an
# exact-match lookup can resolve to a non-Windows shebang shim installed alongside it (see .NOTES
# above). Prefer claude.cmd (the documented Windows wrapper); fall back to the bare name only if
# no .cmd exists at all (e.g. a non-Windows host), which is itself worth knowing about.
$claudeCmd = Get-Command 'claude.cmd' -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Warning "Invoke-ReadOnlyAgent: 'claude.cmd' not found on PATH; falling back to the bare 'claude' name, which is known to resolve incorrectly on a Windows host with an npm-installed CLI (see .NOTES)."
    $claudeCmd = Get-Command 'claude' -ErrorAction SilentlyContinue
}
if (-not $claudeCmd) {
    Write-Host "Invoke-ReadOnlyAgent: could not resolve a 'claude' executable on PATH at all (tried claude.cmd, then claude)." -ForegroundColor Red
    exit 2
}
$claudeExe = $claudeCmd.Source

# Added 2026-09-18, found while proving -AllowedTools: Start-Process -ArgumentList does NOT quote
# array elements containing spaces -- it joins the whole array with bare spaces, so a value like
# "Bash(git -C * worktree list:*)" arrives at the child process as five separate argv tokens, one
# of which ('-C') gets misparsed by claude's own CLI as an unrelated top-level flag ('error: unknown
# option -C', reproduced live). A prompt containing the literal text '--version' hit the same defect
# from the other direction: split into tokens, '--version' alone was interpreted as the CLI's own
# --version flag, and the whole invocation printed only the version string. Every value that could
# contain a space must be wrapped in an embedded double quote so the resulting command-line string
# carries it as one token, the same way a person would quote it by hand at a real prompt.
function ConvertTo-QuotedArg([string]$Value) {
    return '"' + ($Value -replace '"', '\"') + '"'
}

$claudeArgs = @(
    '--print',
    '--agent', $AgentName,
    '--settings', (ConvertTo-QuotedArg $SettingsPath),
    '--tools', (ConvertTo-QuotedArg $Tools),
    '--permission-mode', 'dontAsk',
    '--permission-prompts', 'none',
    '--strict-mcp-config',
    '--max-budget-usd', [string]$MaxBudgetUsd,
    '--output-format', 'stream-json',
    # 2026-09-18 fix, second real-invocation defect found the same night as the claude-resolution
    # bug: `claude --print --output-format stream-json` refuses to run at all without --verbose
    # ("Error: When using --print, --output-format=stream-json requires --verbose"), printed to
    # STDERR only. Without this flag every single invocation failed before doing any work -- the
    # error was invisible in normal output because stderr only reaches Write-Verbose below.
    '--verbose'
)

# Added 2026-09-18: --allowedTools is the only flag that accepts fine-grained Bash(cmd) specifiers
# (verified against `claude --help`; --tools above is whole-category only). Omitted entirely when
# not passed, so a caller that never sets -AllowedTools gets the exact same $claudeArgs as before
# this parameter existed -- no default value, no behaviour change when unused.
if ($AllowedTools) {
    $claudeArgs += @('--allowedTools', (ConvertTo-QuotedArg $AllowedTools))
}

if ($Model) {
    $claudeArgs += @('--model', $Model)
}

# Added 2026-09-18, second defect found proving -AllowedTools: --allowedTools is variadic, so a
# trailing positional prompt is swallowed into it -- exactly the gap headless_agent_permissions.md's
# own verification log already names ("a prompt passed as a trailing positional argument is
# swallowed by it and the CLI exits 1 with 'Input must be provided'. Pass the prompt on stdin, or
# put it before the flags."), reproduced live here. Fixed by following that same standard's own
# tested pattern: when -AllowedTools is used, the prompt goes on stdin instead of as a positional
# argument. When -AllowedTools is NOT used, behaviour is unchanged from before this parameter
# existed -- the positional prompt stays exactly as it was.
$promptFile = $null
if ($AllowedTools) {
    $promptFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($promptFile, $Prompt, [System.Text.UTF8Encoding]::new($false))
} else {
    $claudeArgs += $Prompt
}

Write-Verbose "$claudeExe $($claudeArgs -join ' ')$(if ($promptFile) { ' (prompt on stdin)' })"

$stdoutFile = [System.IO.Path]::GetTempFileName()
$stderrFile = [System.IO.Path]::GetTempFileName()
$proc = $null
try {
    if ($promptFile) {
        $proc = Start-Process -FilePath $claudeExe -ArgumentList $claudeArgs -NoNewWindow -PassThru -RedirectStandardInput $promptFile -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
    } else {
        $proc = Start-Process -FilePath $claudeExe -ArgumentList $claudeArgs -NoNewWindow -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
    }
} catch {
    # Write-Host, not Write-Error -- see the note above the settings-file check: Write-Error is
    # itself terminating under $ErrorActionPreference = 'Stop' and would skip the exit code below.
    Write-Host "Invoke-ReadOnlyAgent: failed to launch '$claudeExe': $($_.Exception.GetType().FullName): $($_.Exception.Message)" -ForegroundColor Red
    if ($promptFile) { Remove-Item $promptFile -ErrorAction SilentlyContinue }
    Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
    exit 2
}

try {
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        Write-Warning "Invoke-ReadOnlyAgent: '$AgentName' exceeded ${TimeoutSec}s, killing it. This is itself a finding worth reporting -- see headless_agent_permissions.md Verification section for why a run should not hang under --permission-prompts none."
        try { $proc.Kill() } catch {}
        Write-Host "Invoke-ReadOnlyAgent: timeout after ${TimeoutSec}s running agent '$AgentName'" -ForegroundColor Red
        Get-Content $stdoutFile -ErrorAction SilentlyContinue
        Get-Content $stderrFile -ErrorAction SilentlyContinue | Write-Verbose
        if ($promptFile) { Remove-Item $promptFile -ErrorAction SilentlyContinue }
    Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
        exit 3
    }
} catch {
    Write-Host "Invoke-ReadOnlyAgent: error waiting on '$AgentName': $($_.Exception.GetType().FullName): $($_.Exception.Message)" -ForegroundColor Red
    if ($promptFile) { Remove-Item $promptFile -ErrorAction SilentlyContinue }
    Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
    exit 2
}

Get-Content $stdoutFile
Get-Content $stderrFile | Write-Verbose
if ($promptFile) { Remove-Item $promptFile -ErrorAction SilentlyContinue }
Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
exit $proc.ExitCode
