<#
.SYNOPSIS
    Thin wrapper that runs a Claude Code subagent headless with the read-only permission baseline.

.DESCRIPTION
    Builds and runs the invocation recommended by
    standards/sessions/headless_agent_permissions.md: loads tools/headless/readonly.settings.json
    as a defense-in-depth deny-list (layer 3), sets dontAsk + --permission-prompts none so nothing
    hangs waiting on a prompt nobody can answer, and either passes --restricted (layer 1 -- the
    agent has no tool-running builtins at all, see -Restricted below) or an explicit -Tools/
    -AllowedTools allow-list (layer 2, for agents that genuinely need Bash).

    This script does not itself decide what an agent is allowed to do beyond the -Restricted
    default-on rule below. When an agent is not running restricted, the caller must pass -Tools
    scoped to what the named agent actually needs (see the Bash-usage table in the standard).

.PARAMETER AgentName
    The subagent to run, e.g. "worktree-sweep".

.PARAMETER Prompt
    The prompt to send.

.PARAMETER Tools
    Comma-separated tool allow-list passed as --tools, e.g. "Read,Grep,Bash". Required when the
    run is NOT restricted (see -Restricted) -- there is no safe default, since "what an agent
    needs" varies per agent. Ignored (with a warning) when the run IS restricted: F2's own
    invocation shape (docs/FABLE_AGENT_SUBAGENT_PLAN.md §5) uses --restricted INSTEAD OF
    --tools/--allowedTools, never alongside -- composing both would let a --tools grant quietly
    reopen the exact "tool present but denied" gap --restricted exists to close by removing the
    tool from the surface entirely. NOTE (2026-09-18, see -AllowedTools below): --tools only
    grants or withholds a whole tool category -- verified against `claude --help`, it cannot
    narrow to a specific Bash sub-command. Under --permission-mode dontAsk, a bare "Bash" grant
    here is NOT enough for an agent to run a specific command that isn't in Claude Code's small
    built-in read-only set -- see headless_agent_permissions.md's own verification log, which
    found exactly this failure (a harmless `git --version` denied with -Tools "Bash" alone), and
    this tool's first real headless run reproduced it live (worktree-sweep's own `git worktree
    list` denied the same way). Use -AllowedTools for the specific commands an agent actually needs.

.PARAMETER AllowedTools
    Added 2026-09-18, after the defect above was found and reproduced. Comma or space-separated
    fine-grained permission-rule entries passed as --allowedTools, e.g. "Bash(git worktree
    list:*),Bash(git status:*)" -- the ONLY flag (per `claude --help`) that accepts this specifier
    syntax; --tools cannot. Optional; defaults to nothing, so a caller that does not pass this
    parameter (and is not restricted) gets byte-identical behaviour to before this parameter
    existed -- confirmed by the tests in this PR. Ignored (with a warning) when the run IS
    restricted, for the same reason as -Tools above. Pass exactly the commands the named agent's
    own definition demonstrably uses, nothing wider; this parameter does not decide that scope,
    the caller does (same division of responsibility as -Tools, per this script's own long-standing
    rule that it "does not itself decide what an agent is allowed to do").

.PARAMETER Restricted
    Added for plan task F2 (docs/FABLE_AGENT_SUBAGENT_PLAN.md:616). Passes --restricted, which
    (per Claude Code's own docs, quoted in that plan's F3 finding) "removes the built-in tools
    that run commands or code (Bash, PowerShell, REPL and the other code-running tools) and
    WebFetch unless --tools names them, and ignores user, project and local settings files" --
    the tool is absent from the model's surface, not merely denied at call time, which is a
    structural boundary a pattern-matched deny rule (readonly.settings.json, layer 3) cannot
    offer (see that file's own documented gaps: `bash -c '...'`, an absolute path, or reordered
    flags all walk past a deny rule; nothing walks past a tool that was never in the surface).

    Explicit -Restricted / -Restricted:$false ALWAYS wins over the default-on lookup below --
    the caller's stated intent is authoritative.

    When NOT passed explicitly, this script looks up the named agent in roster_meta.json
    (-RosterMetaPath) and defaults -Restricted to $true when that agent's "readonly" field is
    exactly "tools", and to $false otherwise (including "instruction", "n/a", or a value this
    script does not recognise -- default-on is opt-in to the one classification the plan names,
    not opt-out of everything else). This is owner decision D3 (2026-09-22, in chat): --restricted
    is ON BY DEFAULT for read-only agents whose roster_meta.json classifies them "readonly":
    "tools". Per this script's own fail-closed convention (see .NOTES), the default-on LOOKUP
    itself fails closed -- exit 4 -- if roster_meta.json is missing, unparsable, or does not list
    the named agent, rather than silently assuming unrestricted for an agent this script cannot
    classify. Pass -Restricted or -Restricted:$false explicitly to bypass the lookup entirely
    (e.g. for an agent intentionally not yet listed in roster_meta.json).

    Agents classified "readonly": "instruction" or "n/a" are unaffected by this parameter's
    default: they still require -Tools exactly as before this parameter existed, and the
    resulting $claudeArgs construction is byte-identical to the pre-F2 script once the lookup
    itself succeeds.

.PARAMETER RosterMetaPath
    Override the roster_meta.json path used for the -Restricted default-on lookup. Default is
    claude-agents/roster_meta.json resolved relative to this script (repo root's claude-agents/
    directory). Exists as this tool's test seam (tools/README.md: "Test seam is mandatory") --
    a test points this at a throwaway fixture file instead of the real roster.

.PARAMETER MaxBudgetUsd
    Passed as --max-budget-usd. Default 1.

.PARAMETER TimeoutSec
    Hard wall-clock timeout for the whole run. Default 300.

.PARAMETER SettingsPath
    Override the settings file. Default is readonly.settings.json next to this script.

.PARAMETER DryRun
    Test seam (tools/README.md: "Test seam is mandatory"). Resolves -Restricted (explicit or via
    the roster_meta.json default-on lookup), builds the full $claudeArgs the run would use, prints
    them, and exits 0 without resolving a `claude` executable or launching anything. Lets a test
    assert which flags a given -AgentName/-Restricted/-Tools combination produces without spending
    any budget or requiring `claude` to be installed at all.

.EXAMPLE
    .\Invoke-ReadOnlyAgent.ps1 -AgentName worktree-sweep -Prompt "List worktrees in MasterThread" -Tools "Bash"

.EXAMPLE
    .\Invoke-ReadOnlyAgent.ps1 -AgentName handoff-drift-reviewer -Prompt "Check the last handoff" -Restricted

.NOTES
    Exit codes (fixed 2026-09-18, extended 2026-09-22 for F2): 0 = the `claude` process ran and
    exited 0. Any other integer = the `claude` process's own real exit code, propagated as-is.
    2 = this wrapper itself failed to resolve or launch `claude` (never reached the subprocess at
    all). 3 = the run timed out and was killed. 4 = -Restricted was not passed explicitly and the
    default-on lookup against roster_meta.json could not be completed (file missing, unparsable,
    or the named agent is not listed) -- fails closed rather than assuming unrestricted. 5 = the
    run resolved to NOT restricted (either -Restricted:$false was passed, or the roster_meta.json
    lookup found "readonly" was not "tools") and no -Tools was supplied -- there is no safe
    default tool set, so this fails closed rather than passing an empty/absent --tools to `claude`.
    A non-zero exit here is always paired with an error written to the report output -- never a
    silent fallthrough.

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

    2026-09-22 addition (plan task F2, owner decision D3): -Restricted / --restricted, defaulting
    on for roster_meta.json "readonly": "tools" agents. See standards/sessions/
    headless_agent_permissions.md's "three-layer ordering" section for how this composes with
    -Tools/-AllowedTools and readonly.settings.json.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$AgentName,
    [Parameter(Mandatory = $true)][string]$Prompt,
    [string]$Tools,
    [string]$AllowedTools,
    [switch]$Restricted,
    [double]$MaxBudgetUsd = 1,
    [int]$TimeoutSec = 300,
    [string]$SettingsPath = (Join-Path $PSScriptRoot 'readonly.settings.json'),
    [string]$RosterMetaPath = (Join-Path $PSScriptRoot '..\..\claude-agents\roster_meta.json'),
    [string]$Model,
    [switch]$DryRun
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

# --- F2: resolve whether this run is -Restricted -----------------------------------------------
# Explicit -Restricted (true or false) always wins -- the caller's stated intent is authoritative.
# Only when the caller did not pass it at all do we consult roster_meta.json's "readonly"
# classification for AgentName, per owner decision D3 (2026-09-22): --restricted is ON BY DEFAULT
# for agents classified "readonly": "tools".
$restrictedExplicit = $PSBoundParameters.ContainsKey('Restricted')
$effectiveRestricted = $false

if ($restrictedExplicit) {
    $effectiveRestricted = [bool]$Restricted
} else {
    if (-not (Test-Path $RosterMetaPath)) {
        Write-Host "Invoke-ReadOnlyAgent: -Restricted was not specified and roster_meta.json was not found at $RosterMetaPath -- cannot determine the default-on classification for '$AgentName'. Failing closed rather than assuming unrestricted. Pass -Restricted or -Restricted:`$false explicitly, or fix -RosterMetaPath." -ForegroundColor Red
        exit 4
    }
    try {
        $rosterRaw = Get-Content $RosterMetaPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Host "Invoke-ReadOnlyAgent: roster_meta.json at $RosterMetaPath could not be read/parsed as JSON: $($_.Exception.GetType().FullName): $($_.Exception.Message). Failing closed rather than assuming unrestricted for '$AgentName'." -ForegroundColor Red
        exit 4
    }
    # Set-StrictMode-safe property access (tools/README.md convention): a bare $rosterRaw.$AgentName
    # would throw under Set-StrictMode for a missing key; go through PSObject.Properties instead.
    $agentEntryProp = $rosterRaw.PSObject.Properties[$AgentName]
    if (-not $agentEntryProp) {
        Write-Host "Invoke-ReadOnlyAgent: agent '$AgentName' is not listed in roster_meta.json at $RosterMetaPath -- cannot determine the -Restricted default. Failing closed rather than assuming unrestricted. Pass -Restricted or -Restricted:`$false explicitly if this agent is intentionally unlisted." -ForegroundColor Red
        exit 4
    }
    $agentEntry = $agentEntryProp.Value
    $readonlyProp = $agentEntry.PSObject.Properties['readonly']
    $readonlyValue = if ($readonlyProp) { $readonlyProp.Value } else { $null }
    $effectiveRestricted = ($readonlyValue -eq 'tools')
}

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
    '--settings', (ConvertTo-QuotedArg $SettingsPath)
)

# --- F2: --restricted (layer 1) INSTEAD OF --tools/--allowedTools (layer 2) --------------------
# Per docs/FABLE_AGENT_SUBAGENT_PLAN.md §5's own two invocation shapes: a subagent needing no shell
# gets --restricted alone; a subagent that genuinely needs Bash gets --tools/--allowedTools WITHOUT
# --restricted. The two are never combined here -- see -Restricted's own doc comment above for why
# (a --tools grant alongside --restricted would silently reopen the "tool present but denied" gap
# --restricted exists to close by removing the tool from the surface entirely).
$usingAllowedToolsFlag = $false
if ($effectiveRestricted) {
    if ($Tools -or $AllowedTools) {
        Write-Warning "Invoke-ReadOnlyAgent: '$AgentName' is running -Restricted; the -Tools/-AllowedTools value(s) supplied are ignored under --restricted (plan's invocation shape uses --restricted instead of --tools, never alongside -- see this script's -Restricted parameter help)."
    }
    $claudeArgs += '--restricted'
} else {
    if (-not $Tools) {
        Write-Host "Invoke-ReadOnlyAgent: -Tools is required when the run is not -Restricted (no safe default -- see this parameter's own long-standing rule). '$AgentName' resolved to NOT restricted (readonly.settings.json readonly != 'tools', or -Restricted:`$false was passed) but no -Tools was supplied." -ForegroundColor Red
        exit 5
    }
    $claudeArgs += @('--tools', (ConvertTo-QuotedArg $Tools))
    # Added 2026-09-18: --allowedTools is the only flag that accepts fine-grained Bash(cmd)
    # specifiers (verified against `claude --help`; --tools above is whole-category only). Omitted
    # entirely when not passed, so a caller that never sets -AllowedTools (and is not restricted)
    # gets the exact same $claudeArgs as before this parameter existed -- no default value, no
    # behaviour change when unused.
    if ($AllowedTools) {
        $claudeArgs += @('--allowedTools', (ConvertTo-QuotedArg $AllowedTools))
        $usingAllowedToolsFlag = $true
    }
}

$claudeArgs += @(
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

if ($Model) {
    $claudeArgs += @('--model', $Model)
}

# Added 2026-09-18, second defect found proving -AllowedTools: --allowedTools is variadic, so a
# trailing positional prompt is swallowed into it -- exactly the gap headless_agent_permissions.md's
# own verification log already names ("a prompt passed as a trailing positional argument is
# swallowed by it and the CLI exits 1 with 'Input must be provided'. Pass the prompt on stdin, or
# put it before the flags."), reproduced live here. Fixed by following that same standard's own
# tested pattern: when --allowedTools is actually in the built args, the prompt goes on stdin
# instead of as a positional argument. Otherwise (including a -Restricted run, which never adds
# --allowedTools) behaviour is unchanged from before this parameter existed -- the positional
# prompt stays exactly as it was.
$promptFile = $null
if ($usingAllowedToolsFlag) {
    $promptFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($promptFile, $Prompt, [System.Text.UTF8Encoding]::new($false))
} else {
    $claudeArgs += $Prompt
}

if ($DryRun) {
    # Test seam (tools/README.md: "Test seam is mandatory"). Never resolves or launches `claude`.
    Write-Host "DRYRUN AgentName=$AgentName Restricted=$effectiveRestricted (explicit=$restrictedExplicit)"
    Write-Host "DRYRUN ARGS: $($claudeArgs -join ' ')$(if ($promptFile) { ' (prompt on stdin)' })"
    exit 0
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
