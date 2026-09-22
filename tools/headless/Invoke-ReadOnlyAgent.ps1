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
    The prompt to send. Always passed to the CLI on stdin, never on the command line: claude.cmd
    runs through cmd.exe, where no quoting keeps a prompt containing a double quote from being run
    as shell syntax (PR #176 review).

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

    2026-09-22 addition (phase 1 of the per-agent --allowedTools overlay
    headless_agent_permissions.md's "Three-layer ordering" section names as a tracked follow-up):
    when this run is NOT restricted, -Tools includes Bash or PowerShell, and -AllowedTools was NOT
    passed on the command line, this script now looks up the named agent's own "allowedTools"
    array in roster_meta.json (-RosterMetaPath) and uses it as if it had been passed here --
    joined the same comma-separated way a caller would hand-write it. Explicit -AllowedTools on
    the command line always wins over this lookup and skips it entirely. If the lookup finds
    nothing (roster missing/unparsable, agent not listed, or no non-empty "allowedTools" array for
    it), the run is refused rather than launched with a bare "Bash" grant and no fine-grained
    narrowing -- see -Restricted's own fail-closed convention and .NOTES exit code 7. A caller
    whose -Tools does not include Bash/PowerShell at all is unaffected by any of this (same as
    before this addition), and so is a caller that already passes -AllowedTools explicitly.

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

.PARAMETER JsonSchemaPath
    Added for plan task F12 (docs/FABLE_AGENT_SUBAGENT_PLAN.md section 5). Points at one of the
    tools/headless/schemas/*.json files built in F4. Fixed 2026-09-22 (QA, PR #197 comments): the
    CLI's --json-schema flag expects the schema file's CONTENT, not its path -- passing the path
    string made the CLI fail during its own argument/schema parsing before ever reaching the API
    (exit 1, no output, wrapper exit 6, no session transcript). This parameter's own file is read
    with `Get-Content -Raw` and that content -- not the path -- is what is passed as `--json-schema`
    (quoted with the same ConvertTo-QuotedArg helper used for every other value on this command
    line), so the CLI's own structured-output validation constrains the agent's answer to that
    schema. Optional -- a caller that never passes it gets byte-identical behaviour to before this
    parameter existed. The path itself must be an existing file; same cmd.exe-safety checks as
    -SettingsPath apply to the PATH value (refused with exit 2, nothing launched, if the path
    contains a double quote, %, !, a line break, or ends in a backslash) -- those checks do not
    re-run against the file's contents. 2026-09-22 follow-up fix (QA, PR #197 comments, second
    round): those PATH-only checks left real schema CONTENT unguarded -- a `"` or a line break in
    the schema itself (ordinary for hand-written JSON Schema) reached cmd.exe by way of claude.cmd
    and was mangled, since cmd.exe does not honour ConvertTo-QuotedArg's backslash-escaped quote and
    cannot carry a literal newline in a single command line at all. Fixed by having the executable
    resolution below prefer the native claude.exe (found next to claude.cmd) over claude.cmd itself
    whenever this parameter's content needs to survive intact -- see that resolution block's own
    comment for the verified mechanics. This parameter only threads the flag through -- it does not
    itself validate the agent's returned JSON against the schema; see
    tools/headless/Invoke-Subagent.ps1 and JsonSchemaLite.ps1 for that (F12's own wrapper, layered
    on top of this script).

.PARAMETER Report
    Added for plan task F3 (docs/FABLE_AGENT_SUBAGENT_PLAN.md:617). Turns on L1 report mode: the
    run uses `--output-format json` (the CLI's single result envelope -- subtype, is_error,
    num_turns, result, total_cost_usd, permission_denials[], usage{...}) instead of the default
    `stream-json --verbose`, and on completion the wrapper writes ONE report file to -ReportDir:

        {"envelope": <the CLI's stdout, verbatim>, "checkedAt": "<UTC clock at write time>",
         "command": "<the exact invocation>"}

    Exactly those three keys, the shape docs/FABLE_AGENT_SUBAGENT_PLAN.md:617 and the F3 brief
    name -- nothing added (PR #176 review round 2 removed an extra exitCode and testSeam field).
    The envelope is embedded as the CLI's own characters, untouched (its trailing newline
    included, as legal JSON whitespace) -- it is never parsed and re-serialised, so no field can be
    dropped, renamed, reordered or re-formatted on the way to disk. `permission_denials`,
    `total_cost_usd` and `usage` therefore come from the CLI, never from the agent's own prose.
    `checkedAt` is read from [DateTime]::UtcNow immediately before the write (tools/README.md
    "Timestamps from the clock"), never copied from inside the envelope.

    File name: <agent>.<yyyyMMdd-HHmmss>.json (UTC, same stamp as checkedAt), the shape
    headless_readiness_ladder.md's L1 section names. Written atomically (temp file in the same
    folder, then renamed), so a heartbeat-tick reader never sees a half-written file. A second
    report for the same agent in the same second gets a -2, -3 ... suffix rather than overwriting.

    `command` is the exact command line that was launched: the resolved executable and every
    argument. The prompt is not part of it -- it travels on stdin (see -Prompt) -- and it is not
    stored anywhere in the report, so a prompt built from handoff or card content is not kept
    indefinitely under %APPDATA%\AEGIS\reports (D6). As a result `command` alone does not re-run the
    same request; the prompt has to be supplied on stdin again. That is a narrower reading of the
    brief's "exact invocation string", pending the brief holder's confirmation (PR #176 review
    round 2).

    Known residual, not solved (PR #176 review round 2): keeping the prompt out does not keep
    secrets out. The envelope is stored whole, and envelope.result and
    permission_denials[].tool_input can carry file contents or command lines the agent read or
    tried. There is no redaction and no retention limit on the drop folder (D6 keeps reports on
    this PC indefinitely).

    Fails loudly, never writes a partial file: if the CLI exits non-zero, or its stdout is empty,
    is not valid JSON, is not a single JSON object, or lacks the result-envelope keys this report
    is measured on (type = "result", subtype, is_error, num_turns, total_cost_usd,
    permission_denials as an array, usage), NO report file is written and the wrapper exits 6
    (see .NOTES).

    Off by default: a caller that passes neither -Report nor -ReportDir keeps the pre-F3
    `stream-json --verbose` output and no report file is written anywhere.

.PARAMETER ReportDir
    The report drop folder. Default `%APPDATA%\AEGIS\reports` -- the folder
    headless_readiness_ladder.md's L1 section names, and owner decision D6 (2026-09-22) keeps
    agent reports on this PC. Passing -ReportDir explicitly also turns report mode on (same as
    -Report). Created if missing. Test seam (tools/README.md: "Test seam is mandatory"): a test
    passes a throwaway directory here, never the real folder.

.PARAMETER ClaudePath
    Test seam (tools/README.md: "Test seam is mandatory"). Path to the executable to launch in
    place of the resolved `claude.cmd`. Lets a test drive the real report-writing path (the call
    site, not a helper in isolation) against a fake CLI that prints a fixture envelope, an empty
    stdout, malformed JSON, or a non-zero exit -- without spending budget. Enforced, not just
    documented (PR #176 review): refused with exit 2 unless the environment variable
    AEGIS_TEST_SEAM is set to 1, and in report mode it is also refused (exit 2) unless -ReportDir
    is passed explicitly and is not the real drop folder (%APPDATA%\AEGIS\reports), so a report
    produced by a fake CLI can never land where L1 evidence is read. A real run leaves it unset and
    the script resolves `claude.cmd` itself (see .NOTES). Exit 2 if the path does not exist.

.PARAMETER AgentsDir
    2026-09-22 addition (issue #212 follow-up). Directory holding claude-agents/*.md, used only
    when -JsonSchemaPath is given: resolves claude-agents/<AgentName>.md so its body (frontmatter
    stripped) can be sent via --append-system-prompt-file instead of --agent -- see .NOTES for why.
    Default: ..\..\claude-agents next to this script (the real repo layout). Missing/unresolvable
    falls back to the old --agent path with a warning, rather than refusing the run.

.PARAMETER DryRun
    Test seam (tools/README.md: "Test seam is mandatory"). Resolves -Restricted (explicit or via
    the roster_meta.json default-on lookup), builds the full $claudeArgs the run would use, prints
    them, and exits 0 without resolving a `claude` executable or launching anything. Lets a test
    assert which flags a given -AgentName/-Restricted/-Tools combination produces without spending
    any budget or requiring `claude` to be installed at all. In report mode it also prints the
    resolved report folder and writes nothing.

.EXAMPLE
    .\Invoke-ReadOnlyAgent.ps1 -AgentName worktree-sweep -Prompt "List worktrees in MasterThread" -Tools "Bash"

.EXAMPLE
    .\Invoke-ReadOnlyAgent.ps1 -AgentName handoff-drift-reviewer -Prompt "Check the last handoff" -Restricted

.EXAMPLE
    .\Invoke-ReadOnlyAgent.ps1 -AgentName handoff-drift-reviewer -Prompt "Check the last handoff" -Report
    # L1 report mode: writes %APPDATA%\AEGIS\reports\handoff-drift-reviewer.<yyyyMMdd-HHmmss>.json

.NOTES
    Exit codes (fixed 2026-09-18, extended 2026-09-22 for F2): 0 = the `claude` process ran and
    exited 0. Any other integer = the `claude` process's own real exit code, propagated as-is.
    2 = this wrapper itself failed to resolve or launch `claude` (never reached the subprocess at
    all), or refused an argument that is unsafe on cmd.exe's command line (-AgentName or -Model
    outside their allowed character sets; -SettingsPath/-Tools/-AllowedTools containing a double
    quote, %, ! or a line break, or ending in a backslash; -SettingsPath not an existing file), or
    refused -ClaudePath (no AEGIS_TEST_SEAM=1, or a report aimed at the real drop folder), or got
    -Report with no -ReportDir while %APPDATA% is unset (no default folder to resolve). 3 = the
    run timed out and its whole process tree was killed. 4 = -Restricted was not passed explicitly and the
    default-on lookup against roster_meta.json could not be completed (file missing, unparsable,
    or the named agent is not listed) -- fails closed rather than assuming unrestricted. 5 = the
    run resolved to NOT restricted (either -Restricted:$false was passed, or the roster_meta.json
    lookup found "readonly" was not "tools") and no -Tools was supplied -- there is no safe
    default tool set, so this fails closed rather than passing an empty/absent --tools to `claude`.
    A non-zero exit here is always paired with an error written to the report output -- never a
    silent fallthrough. 8 = (added 2026-09-22, phase 1 of the per-agent --allowedTools roster
    overlay) the run resolved to NOT restricted, its -Tools includes Bash or PowerShell, no
    -AllowedTools was passed explicitly, and the roster_meta.json lookup for the named agent's own
    "allowedTools" array found nothing usable (roster missing/unparsable, agent not listed, or no
    non-empty array) -- fails closed rather than launching a Bash/PowerShell-holding agent with no
    fine-grained narrowing at all. Only an agent whose roster_meta.json entry carries a real
    "allowedTools" list (as of this change, only `pr-state-sweep`) can run headless through this
    path without either -AllowedTools or -Restricted; every other Bash/PowerShell-holding
    "readonly": "instruction" agent hits this exit until its own roster entry gets a list (tracked
    as phase 2, out of scope for this change -- see the PR that added this exit code for the
    caller-visible impact of that sequencing).

    Report mode (-Report / -ReportDir, plan task F3) adds two codes, and in report mode they are
    exactly the "no report file was written" signal: 6 = the CLI exited non-zero, or its stdout was
    empty, not valid JSON (checked by two parsers, see Test-StrictJson), not a single object, or
    missing a required result-envelope key, or the assembled report failed the same strict
    re-check -- nothing written. 7 = the envelope was valid but the report file could not be
    written (folder not creatable, disk error) -- nothing left behind but the error. Both win over
    the CLI's own exit code, which is printed in the error message instead; the CLI's stdout
    (including any envelope it did print) is still echoed to the console. A non-zero CLI exit
    writes no report even when the envelope looks complete (e.g. subtype error_max_budget_usd):
    the F3 brief says a nonzero exit must not write an envelope and must fail loudly
    (SCOPE_F3_F4.md section 6), and the plan's report shape has no field to carry the exit code.
    A timeout (3) writes no report; a missing report where one was expected is itself the finding
    (headless_readiness_ladder.md, "What every headless run must emit").

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

    2026-09-21 addition (plan task F3): -Report / -ReportDir writes the CLI's own JSON envelope
    plus checkedAt and the exact command to the drop folder as the L1 report, replacing the
    hand-rolled {agent, checkedAt, command, exitCode, permissionDenials, findings[]} shape that
    headless_readiness_ladder.md still describes (that standard is route C; updating its text is a
    separate owner-merged change, tracked in GitHub issue #184 -- nothing, F7's heartbeat ingest
    included, should be built against the ladder's old shape). The per-agent `findings[]` contract is F4's --json-schema work,
    not this script's.

    2026-09-22 addition (issue #212 follow-up, replaces the earlier live-run-confirmed root cause
    that only rewrote the agent's own Output section): a peer's live probes (8 Haiku runs, CLI
    2.1.280, same schema) found --json-schema is silently not enforced at all on any run launched
    with --agent <name> -- the validated payload (envelope.structured_output) never appears,
    regardless of agent instructions, subtype is still "success", and envelope.result is always
    prose. Every non-"--agent" invocation shape in the same probe returned structured_output. This
    matches all three real pr-state-sweep drop-folder reports exactly (145241, 172129, 173309: all
    --agent, all --json-schema, all subtype success, all no structured_output). Fix: when
    -JsonSchemaPath is given and the named agent's own claude-agents/<name>.md is resolvable (see
    -AgentsDir), this script launches WITHOUT --agent, instead sending that file's body (frontmatter
    stripped) via --append-system-prompt-file -- every other read-only boundary flag
    (--restricted, --tools/--allowedTools, --settings) is built exactly as before; only the flag
    that delivers the agent's own instructions changes. -Model, if not explicitly passed, is
    defaulted from the agent's own frontmatter 'model:' line in this path, since --agent normally
    supplies that and this path no longer does. Evidence (one live Haiku run confirming
    structured_output appears via --append-system-prompt-file, plus the ALLOWED/DENIED boundary
    proof) is recorded in tools/headless/evidence/.
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
    # Defaults resolved in the body, not here: see the $PSScriptRoot note just below param().
    [string]$SettingsPath,
    [string]$JsonSchemaPath,
    [string]$RosterMetaPath,
    [string]$Model,
    [switch]$Report,
    [string]$ReportDir,
    [string]$ClaudePath,
    [string]$AgentsDir,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# 2026-09-21 fix, found running F3's live check through `powershell.exe -File` (the way a scheduled
# task calls this script): under Windows PowerShell 5.1, a [CmdletBinding()] script invoked with
# -File sees an EMPTY $PSScriptRoot inside its param() default expressions, so the old defaults
# `(Join-Path $PSScriptRoot 'readonly.settings.json')` threw "Cannot bind argument to parameter
# 'Path' because it is an empty string" before the script body ran at all (reproduced with a
# three-line script: fails with [CmdletBinding()], works without it; `& .\script.ps1` was never
# affected, which is why the dot-sourced tests did not catch it). $PSScriptRoot is populated in the
# body, so the same defaults are applied here instead. Behaviour is unchanged for every caller
# that passes these parameters, and for every caller that relied on the defaults via `&`.
if (-not $SettingsPath) { $SettingsPath = Join-Path $PSScriptRoot 'readonly.settings.json' }
if (-not $RosterMetaPath) { $RosterMetaPath = Join-Path $PSScriptRoot '..\..\claude-agents\roster_meta.json' }
if (-not $AgentsDir) { $AgentsDir = Join-Path $PSScriptRoot '..\..\claude-agents' }

# --- cmd.exe command-line safety (PR #176 review, 2026-09-21) ----------------------------------
# The wrapper launches claude.cmd, so Start-Process hands the whole argument string to cmd.exe.
# cmd.exe does not honour backslash escapes: a double quote inside a value ends the quoted region,
# after which & | < > ^ run as shell syntax, and %VAR% is expanded even inside quotes. Anything that
# reaches that command line therefore has to be either a closed character set or free of the
# characters cmd.exe still interprets inside quotes. The prompt never goes on the command line at
# all (it is always passed on stdin, below). Every failure here exits 2 before anything is launched.
function Exit-UnsafeArg([string]$Name, [string]$Why) {
    Write-Host "Invoke-ReadOnlyAgent: refusing -$Name -- $Why. Nothing was launched." -ForegroundColor Red
    exit 2
}
# PR #176 review round 2 (safety): the first character must be alphanumeric. Both values are placed
# straight after --agent / --model, so a value starting with '-' (e.g. '--dangerously-skip-permissions'
# or '--permission-mode') could be read by the CLI's parser as a new flag instead of the option's
# value, widening permissions past every layer. Refused here rather than left to the parser.
if ($AgentName -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*\z') {
    Exit-UnsafeArg 'AgentName' "'$AgentName' must match ^[A-Za-z0-9][A-Za-z0-9._-]*$ (it is passed to cmd.exe unquoted and must not start with '-')"
}
if ($Model -and $Model -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._\[\]-]*\z') {
    Exit-UnsafeArg 'Model' "'$Model' must match ^[A-Za-z0-9][A-Za-z0-9._\[\]-]*$ (it is passed to cmd.exe unquoted and must not start with '-')"
}
foreach ($quotedName in @('SettingsPath', 'JsonSchemaPath', 'Tools', 'AllowedTools')) {
    $quotedValue = Get-Variable -Name $quotedName -ValueOnly
    # '!' added in PR #176 review round 2 (safety): with cmd.exe delayed expansion switched on
    # (Command Processor\DelayedExpansion=1 in HKCU or HKLM), cmd.exe expands !VAR! even inside quotes.
    if ($quotedValue -and $quotedValue -match '["%!\r\n]') {
        Exit-UnsafeArg $quotedName 'the value contains a double quote, %, !, or a line break, which cmd.exe would interpret even inside quotes'
    }
    # PR #176 review round 2: these values are wrapped as "value" (ConvertTo-QuotedArg). A value
    # ending in a backslash becomes "...\" and the CLI's argv parser reads that trailing \" as an
    # escaped quote, so the value swallows every argument after it (--restricted, --tools,
    # --permission-mode dontAsk, --permission-prompts none). Refused rather than escaped.
    if ($quotedValue -and $quotedValue.EndsWith('\')) {
        Exit-UnsafeArg $quotedName 'the value ends in a backslash, which would escape its closing quote and swallow the arguments after it'
    }
}

# -ClaudePath is a test seam, and a report written through it is not evidence of a real CLI run.
# Tool-level guard rather than an instruction: it is refused unless the process opts in with
# AEGIS_TEST_SEAM=1, and in report mode it may only write to an explicit -ReportDir that is not the
# real drop folder (see below), so even a leftover AEGIS_TEST_SEAM=1 cannot put a fake CLI's output
# where L1 evidence is read.
#
# Known limitation, stated rather than solved (PR #176 review round 2, safety): the "not the real
# drop folder" check below compares full path STRINGS (GetFullPath, case-insensitive). A junction or
# symlink pointing at %APPDATA%\AEGIS\reports, an 8.3 short name, a \\?\ or \\localhost\c$ path, or
# an APPDATA value changed in the same process would all pass it. The guard stops a leftover
# AEGIS_TEST_SEAM=1 or a careless test from landing fake output in the drop folder. It is not a
# boundary against a caller that already runs code as this user and sets AEGIS_TEST_SEAM=1 on purpose.
if ($ClaudePath -and $env:AEGIS_TEST_SEAM -ne '1') {
    Write-Host "Invoke-ReadOnlyAgent: -ClaudePath is a test seam and is refused unless the environment variable AEGIS_TEST_SEAM is set to 1. A real run resolves claude.cmd itself. Nothing was launched." -ForegroundColor Red
    exit 2
}

# --- F3: report mode -------------------------------------------------------------------------
# On when -Report is passed, or when -ReportDir is passed explicitly (a caller naming a drop folder
# plainly wants a report in it). Off otherwise, and then nothing below changes behaviour.
$reportMode = [bool]$Report -or $PSBoundParameters.ContainsKey('ReportDir')
if ($reportMode -and -not $ReportDir) {
    # Default resolved here rather than in param(), same reason as the two defaults above.
    if (-not $env:APPDATA) {
        # Exit 2 (refused before launch), not 7: .NOTES defines 7 as "the envelope was valid but the
        # report file could not be written", and nothing has been launched yet (PR #176 review round 2).
        Write-Host "Invoke-ReadOnlyAgent: -Report was requested with no -ReportDir and %APPDATA% is not set, so the default drop folder cannot be resolved. Pass -ReportDir. Nothing was launched." -ForegroundColor Red
        exit 2
    }
    $ReportDir = Join-Path $env:APPDATA 'AEGIS\reports'
}

# PR #176 review round 2: a fake CLI's output must never be written where real L1 evidence is read.
# The report shape is exactly {envelope, checkedAt, command} (plan:617), so there is no field to mark
# a test-seam report; instead the seam may only write to a folder the caller names explicitly, and
# never to the real drop folder.
if ($ClaudePath -and $reportMode) {
    $realDrop = $null
    if ($env:APPDATA) { $realDrop = [System.IO.Path]::GetFullPath((Join-Path $env:APPDATA 'AEGIS\reports')).TrimEnd('\') }
    $targetDrop = [System.IO.Path]::GetFullPath($ReportDir).TrimEnd('\')
    if (-not $PSBoundParameters.ContainsKey('ReportDir') -or ($realDrop -and $targetDrop -ieq $realDrop)) {
        Write-Host "Invoke-ReadOnlyAgent: -ClaudePath (test seam) in report mode needs an explicit -ReportDir that is not the real drop folder ($realDrop). Nothing was launched." -ForegroundColor Red
        exit 2
    }
}

if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
    # NOTE: Write-Error is itself a terminating error under $ErrorActionPreference = 'Stop' and
    # would skip the explicit `exit 2` below, falling through to PowerShell's own default exit 1
    # for an unhandled error -- verified empirically 2026-09-18. Write-Host + explicit exit
    # guarantees the documented code regardless of preference, same convention the estate's other
    # click-files use for a controlled, known-cause exit.
    Write-Host "Invoke-ReadOnlyAgent: settings file not found (or not a file) at $SettingsPath" -ForegroundColor Red
    exit 2
}

# F12: -JsonSchemaPath must exist too, checked before anything is launched, same convention as
# -SettingsPath above.
if ($JsonSchemaPath -and -not (Test-Path -LiteralPath $JsonSchemaPath -PathType Leaf)) {
    Write-Host "Invoke-ReadOnlyAgent: -JsonSchemaPath file not found (or not a file) at $JsonSchemaPath" -ForegroundColor Red
    exit 2
}

# --- F2: resolve whether this run is -Restricted -----------------------------------------------
# Explicit -Restricted (true or false) always wins -- the caller's stated intent is authoritative.
# Only when the caller did not pass it at all do we consult roster_meta.json's "readonly"
# classification for AgentName, per owner decision D3 (2026-09-22): --restricted is ON BY DEFAULT
# for agents classified "readonly": "tools".
$restrictedExplicit = $PSBoundParameters.ContainsKey('Restricted')
$effectiveRestricted = $false
# Initialized here (rather than left undefined) so the F2b allowedTools-roster lookup below can
# tell "already loaded by this block" apart from "never attempted" and reuse the same parsed
# object instead of reading roster_meta.json a second time, in the (common) case where
# -Restricted was not passed explicitly and this block already loaded it.
$rosterRaw = $null

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
#
# 2026-09-22 fix (PR #197 live QA, two rounds): the original version blindly replaced EVERY `"`
# with `\"`, regardless of whether it was already escaped. Real JSON Schema text passed via
# -JsonSchemaPath (tools/headless/schemas/pr-state-sweep.json) legitimately contains already-
# escaped quotes inside nested description strings -- source text like `\"3h\"` (one backslash then
# a quote: a valid JSON-escaped quote character). The blind replace turned that into `\\"3h\\"`
# (backslash-backslash-quote), corrupting the schema (CLI stderr: "Error: --json-schema is not
# valid JSON: JSON Parse error: Invalid escape character 3").
#
# ROUND 1 of this fix (leave an already-odd backslash run untouched, only escape an even/bare run)
# looked correct as a STRING transformation and passed every DryRun/static test, but a live
# -Verbose run against the real pr-state-sweep.json (this PR's own QA step 5) still failed with
# "JSON Parse error: Expected '}'". Root cause, found by writing a native argv-echoing test double
# and round-tripping the real schema file through it: this command line is consumed by Windows'
# own CreateProcess/argv decoding (standard "backslashes only special immediately before a quote"
# rule, the same one .NET's own argument parser and CommandLineToArgvW use), NOT by a simple
# find-and-replace reversal. That decode rule is: a run of N backslashes immediately before a `"`
# produces floor(N/2) literal backslashes, and if N is ODD, one literal quote character in the
# delivered argument (if N is even, the quote toggles/ends quoting instead -- never what we want
# here, since the whole value sits inside one outer pair of quotes). So a SINGLE backslash before a
# quote (`\"`, N=1) decodes to floor(1/2)=0 backslashes + a literal quote -- the backslash is
# CONSUMED by the decoder, not preserved. Verified empirically: round-tripping the real schema
# file's raw bytes through ConvertTo-QuotedArg (round-1 version) and then this exact decode rule
# does NOT reproduce the original bytes -- every already-escaped `\"3h\"` loses its backslash.
#
# Correct fix: for a source backslash run of length k immediately before a `"` (k=0 for an
# ordinary bare quote, k=1 for an already-JSON-escaped quote, k=2 for a literal escaped backslash
# followed by a bare quote, and so on), emit (2k + 1) backslashes before the quote on the command
# line. Per the decode rule above, floor((2k+1)/2) = k literal backslashes come back out, plus the
# literal quote (odd count, so it is always data, never a delimiter) -- exactly reconstructing the
# source's k backslashes and the quote itself, for any depth of pre-escaping:
#   - `foo"bar`   (k=0) -> command line `foo\"bar`     -> decodes back to `foo"bar`   (bare quote)
#   - `\"foo\"`    (k=1) -> command line `\\\"foo\\\"`  -> decodes back to `\"foo\"`   (pre-escaped
#                                                          quote survives, not stripped)
#   - `\\"foo\\"`  (k=2) -> command line `\\\\\"foo...` -> decodes back to `\\"foo\\"` (escaped
#                                                          backslash + quote survives)
# Verified live 2026-09-22: this formula, run through the same native-exe argv round-trip that
# exposed round 1's defect, reproduces the real pr-state-sweep.json's raw bytes exactly, and the
# real `claude` CLI accepted the resulting --json-schema value (see this PR's QA notes for the
# live -Verbose run's exit code and output).
function ConvertTo-QuotedArg([string]$Value) {
    $evaluator = {
        param($m)
        $backslashCount = $m.Value.Length - 1
        return ('\' * (2 * $backslashCount + 1)) + '"'
    }
    $escaped = [regex]::Replace($Value, '\\*"', $evaluator)
    return '"' + $escaped + '"'
}

# 2026-09-22 fix (issue #212 follow-up): a peer's live probes (8 Haiku runs, CLI 2.1.280, same
# schema) found --json-schema is silently NOT enforced on any run launched with --agent <name>:
# every non-agent invocation shape returned envelope.structured_output; every --agent invocation
# returned prose with no structured_output key, subtype "success" regardless. This matches all
# three real pr-state-sweep drop-folder reports (145241, 172129, 173309) exactly. So when a schema
# is in play (-JsonSchemaPath given), this script launches WITHOUT --agent, instead loading the
# named agent's own body (claude-agents/<name>.md, frontmatter stripped) via
# --append-system-prompt-file, so the model still receives the same instructions --agent would
# have loaded -- only the flag CLAUDE uses to deliver them changes. Every read-only boundary flag
# (--restricted, --tools/--allowedTools, --settings) is built exactly as it would be for the
# --agent path; nothing about what the agent is allowed to do changes, only how its prompt text
# reaches the CLI. The agent's own frontmatter 'model:' is threaded through as -Model's default
# (below) since --agent normally supplies that too and this path no longer does.
$agentDefPath = Join-Path $AgentsDir "$AgentName.md"
$useAppendSystemPromptFile = ($JsonSchemaPath -and (Test-Path -LiteralPath $agentDefPath -PathType Leaf))
$appendSystemPromptFile = $null
$agentFrontmatterModel = $null
if ($JsonSchemaPath -and -not (Test-Path -LiteralPath $agentDefPath -PathType Leaf)) {
    Write-Warning "Invoke-ReadOnlyAgent: -JsonSchemaPath was given but '$agentDefPath' does not exist -- falling back to --agent '$AgentName' (the structured_output-suppressing path this change exists to avoid). Fix -AgentsDir, or expect envelope.structured_output to be absent."
}
if ($useAppendSystemPromptFile) {
    $agentDefRaw = Get-Content -LiteralPath $agentDefPath -Raw
    # Frontmatter is a leading '---' ... '---' YAML block (see any claude-agents/*.md); the body
    # (everything after the closing '---') is what --agent would otherwise present as the agent's
    # own instructions. A simple two-marker split, matching how generate_agents_md.py already
    # parses these files -- no YAML dependency needed for a strip-only operation.
    $fmMatch = [regex]::Match($agentDefRaw, '(?s)\A---\r?\n(.*?)\r?\n---\r?\n(.*)\z')
    if ($fmMatch.Success) {
        $frontmatterText = $fmMatch.Groups[1].Value
        $agentBodyText = $fmMatch.Groups[2].Value
        $modelLineMatch = [regex]::Match($frontmatterText, '(?m)^model:\s*(\S+)\s*$')
        if ($modelLineMatch.Success) { $agentFrontmatterModel = $modelLineMatch.Groups[1].Value }
    } else {
        # No parseable frontmatter block -- use the file's own full text as the system prompt
        # rather than refuse; still strictly better than the old always-prose --agent path.
        $agentBodyText = $agentDefRaw
    }
    $appendSystemPromptFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($appendSystemPromptFile, $agentBodyText, [System.Text.UTF8Encoding]::new($false))
}

if ($useAppendSystemPromptFile) {
    $claudeArgs = @(
        '--print',
        '--append-system-prompt-file', (ConvertTo-QuotedArg $appendSystemPromptFile),
        '--settings', (ConvertTo-QuotedArg $SettingsPath)
    )
    if (-not $Model -and $agentFrontmatterModel) { $Model = $agentFrontmatterModel }
} else {
    $claudeArgs = @(
        '--print',
        '--agent', $AgentName,
        '--settings', (ConvertTo-QuotedArg $SettingsPath)
    )
}

# --- F2: --restricted (layer 1) INSTEAD OF --tools/--allowedTools (layer 2) --------------------
# Per docs/FABLE_AGENT_SUBAGENT_PLAN.md §5's own two invocation shapes: a subagent needing no shell
# gets --restricted alone; a subagent that genuinely needs Bash gets --tools/--allowedTools WITHOUT
# --restricted. The two are never combined here -- see -Restricted's own doc comment above for why
# (a --tools grant alongside --restricted would silently reopen the "tool present but denied" gap
# --restricted exists to close by removing the tool from the surface entirely).
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

    # --- F2b: per-agent --allowedTools roster lookup + fail-closed gate ------------------------
    # headless_agent_permissions.md's "Three-layer ordering" section names this overlay a "tracked
    # follow-up, not done here" for layer-2 agents (the ones that keep Bash instead of running
    # --restricted). This is that follow-up, phase 1: scoped to whichever agent(s)
    # claude-agents/roster_meta.json actually carries a non-empty "allowedTools" list for (as of
    # this change, only pr-state-sweep -- see that entry's own list and the PROVEN
    # zero-permission-denial evidence cited in headless_agent_permissions.md's Bash-usage table).
    #
    # Explicit -AllowedTools on the command line always wins -- same "caller's stated intent is
    # authoritative" rule -Restricted already follows above (F2). The roster lookup below only
    # runs when the caller did NOT pass -AllowedTools at all.
    $allowedToolsExplicit = $PSBoundParameters.ContainsKey('AllowedTools')
    if (-not $allowedToolsExplicit) {
        # Only agents whose -Tools actually includes a tool-running builtin need an allow-list at
        # all -- an agent scoped to e.g. "Read,Grep" has nothing for --allowedTools to narrow, and
        # must not be refused for lacking one (byte-identical behaviour to before this change).
        $toolTokens = $Tools -split ',' | ForEach-Object { $_.Trim() }
        $needsAllowedTools = ($toolTokens -contains 'Bash') -or ($toolTokens -contains 'PowerShell')

        if ($needsAllowedTools) {
            # Reuse the roster already loaded above by F2's -Restricted default-on lookup when
            # that ran ($restrictedExplicit was $false); otherwise (an explicit -Restricted or
            # -Restricted:$false was passed, so F2's lookup was skipped entirely) load it here.
            # Fails closed the same way F2 does: a missing/unparsable roster is treated as "no
            # allowedTools list found" (exit 7 below), never as permission to run wide-open
            # Bash/PowerShell unchecked.
            $rosterLookupOk = $true
            if (-not $rosterRaw) {
                if (-not (Test-Path $RosterMetaPath)) {
                    $rosterLookupOk = $false
                } else {
                    try {
                        $rosterRaw = Get-Content $RosterMetaPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                    } catch {
                        $rosterLookupOk = $false
                    }
                }
            }

            $agentAllowedTools = $null
            if ($rosterLookupOk -and $rosterRaw) {
                # Set-StrictMode-safe property access (tools/README.md convention), same pattern
                # as F2's own lookup above.
                $allowedToolsAgentProp = $rosterRaw.PSObject.Properties[$AgentName]
                if ($allowedToolsAgentProp) {
                    $allowedToolsProp = $allowedToolsAgentProp.Value.PSObject.Properties['allowedTools']
                    if ($allowedToolsProp -and $allowedToolsProp.Value -is [array] -and $allowedToolsProp.Value.Count -gt 0) {
                        $agentAllowedTools = @($allowedToolsProp.Value | ForEach-Object { [string]$_ })
                    }
                }
            }

            if (-not $agentAllowedTools) {
                Write-Host "Invoke-ReadOnlyAgent: refusing to launch '$AgentName' -- it resolved to NOT restricted and its -Tools ('$Tools') includes Bash/PowerShell, but roster_meta.json at $RosterMetaPath has no non-empty 'allowedTools' list for it (and no -AllowedTools was passed on the command line). Failing closed per this script's own convention -- a Bash/PowerShell-holding agent needs a scoped allow-list, not an implicit blank check. Pass -AllowedTools explicitly, or add an 'allowedTools' array to this agent's roster_meta.json entry. Nothing was launched." -ForegroundColor Red
                exit 7
            }

            # Joined the same way a caller would hand-write -AllowedTools (comma-separated); the
            # cmd.exe-safety checks below re-validate this roster-derived value before it reaches
            # the command line, the same as any other value that ends up in $claudeArgs.
            $AllowedTools = $agentAllowedTools -join ','
            if ($AllowedTools -match '["%!\r\n]') {
                Exit-UnsafeArg 'AllowedTools' "the roster_meta.json 'allowedTools' value for '$AgentName' contains a double quote, %, !, or a line break, which cmd.exe would interpret even inside quotes"
            }
            if ($AllowedTools.EndsWith('\')) {
                Exit-UnsafeArg 'AllowedTools' "the roster_meta.json 'allowedTools' value for '$AgentName' ends in a backslash, which would escape its closing quote and swallow the arguments after it"
            }
        }
    }

    $claudeArgs += @('--tools', (ConvertTo-QuotedArg $Tools))
    # Added 2026-09-18: --allowedTools is the only flag that accepts fine-grained Bash(cmd)
    # specifiers (verified against `claude --help`; --tools above is whole-category only). Omitted
    # entirely when not passed, so a caller that never sets -AllowedTools (and is not restricted)
    # gets the exact same $claudeArgs as before this parameter existed -- no default value, no
    # behaviour change when unused.
    if ($AllowedTools) {
        $claudeArgs += @('--allowedTools', (ConvertTo-QuotedArg $AllowedTools))
    }
}

$claudeArgs += @(
    '--permission-mode', 'dontAsk',
    '--permission-prompts', 'none',
    '--strict-mcp-config',
    '--max-budget-usd', [string]$MaxBudgetUsd
)

# F12 bug fix (QA, PR #197 comments 2026-09-22, zero-cost mock repro + `claude --help` text): the
# CLI's --json-schema flag expects the schema file's CONTENT, not its path. Passing the path string
# made the CLI fail during its own argument/schema parsing before ever reaching the API -- exit 1,
# no output, wrapper exit 6, no session transcript (the live QA failure signature). Fixed by reading
# the file's content here and passing that as the flag's value, quoted with the same
# ConvertTo-QuotedArg helper used for every other value on this command line. Omitted entirely when
# not passed, so a caller that never sets -JsonSchemaPath gets the exact same $claudeArgs as before
# this parameter existed.
if ($JsonSchemaPath) {
    $jsonSchemaContent = Get-Content -Raw -LiteralPath $JsonSchemaPath
    $claudeArgs += @('--json-schema', (ConvertTo-QuotedArg $jsonSchemaContent))
}

if ($reportMode) {
    # F3: `--output-format json` WITHOUT --verbose returns exactly one JSON object -- the result
    # envelope -- on stdout (verified live 2026-09-21, CLI 2.1.278, Haiku). Adding --verbose turns
    # it into an array of every event (system/init, assistant, ..., result), which is not the
    # envelope the plan names, so report mode deliberately leaves --verbose off.
    $claudeArgs += @('--output-format', 'json')
} else {
    $claudeArgs += @(
        '--output-format', 'stream-json',
        # 2026-09-18 fix, second real-invocation defect found the same night as the claude-resolution
        # bug: `claude --print --output-format stream-json` refuses to run at all without --verbose
        # ("Error: When using --print, --output-format=stream-json requires --verbose"), printed to
        # STDERR only. Without this flag every single invocation failed before doing any work -- the
        # error was invisible in normal output because stderr only reaches Write-Verbose below.
        '--verbose'
    )
}

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
#
# 2026-09-21 (PR #176 review, HIGH): the prompt now ALWAYS goes on stdin, never on the command line.
# Before this, a prompt that did not use --allowedTools was appended as a positional argument --
# first unquoted (split on spaces, so a prompt containing '--version' printed only the CLI version),
# then quoted with ConvertTo-QuotedArg. Quoting cannot make it safe: claude.cmd runs through cmd.exe,
# which ignores the \" escape, so a prompt such as `hello " & echo INJECTED & rem "` ran `echo
# INJECTED` as a shell command as this user, outside every Claude permission layer (reproduced by the
# reviewer and by this file's regression test). Prompts are often built from file, handoff or card
# content, so that was a real bypass of the read-only baseline. stdin carries the text as data only.
# Behaviour change for non-report callers: the prompt is no longer in the child's argv.
$promptFile = $null

if ($DryRun) {
    # Test seam (tools/README.md: "Test seam is mandatory"). Never resolves or launches `claude`.
    Write-Host "DRYRUN AgentName=$AgentName Restricted=$effectiveRestricted (explicit=$restrictedExplicit)"
    Write-Host "DRYRUN ARGS: $($claudeArgs -join ' ') (prompt on stdin)"
    if ($reportMode) { Write-Host "DRYRUN REPORT dir=$ReportDir (nothing written)" }
    exit 0
}

$promptFile = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($promptFile, $Prompt, [System.Text.UTF8Encoding]::new($false))

# issue #206 (Fix A): resolve the sibling native claude.exe next to a .cmd wrapper, shared by both
# the -ClaudePath test seam and the real resolution below, so a test can prove the SAME bypass the
# real run takes (rather than a test-only shortcut) actually delivers the schema content
# byte-identical through a real child process. See the extensive comment on the real-resolution
# branch below for why this bypass exists and what it fixes.
function Resolve-NativeClaudeExe([string]$CmdExePath) {
    if ($CmdExePath -notmatch '\.cmd$') { return $CmdExePath }
    $dir = Split-Path -Parent $CmdExePath
    $native = Join-Path $dir 'node_modules\@anthropic-ai\claude-code\bin\claude.exe'
    if (Test-Path -LiteralPath $native -PathType Leaf) {
        return (Resolve-Path -LiteralPath $native).ProviderPath
    }
    return $CmdExePath
}

$skipCmdExeContentCheck = $false
if ($ClaudePath) {
    # Test seam only (see -ClaudePath). A real run never sets it.
    if (-not (Test-Path -LiteralPath $ClaudePath -PathType Leaf)) {
        Write-Host "Invoke-ReadOnlyAgent: -ClaudePath '$ClaudePath' does not exist." -ForegroundColor Red
        if ($promptFile) { Remove-Item $promptFile -ErrorAction SilentlyContinue }
        if ($appendSystemPromptFile) { Remove-Item $appendSystemPromptFile -ErrorAction SilentlyContinue }
        exit 2
    }
    $claudeExe = (Resolve-Path -LiteralPath $ClaudePath).ProviderPath
    # A fake .cmd test double is exercised through the exact same native-exe bypass a real run takes
    # (Resolve-NativeClaudeExe above) when the test lays down a sibling claude.exe at the same
    # relative path claude.cmd's own body names -- this lets a test prove the real bypass, not a
    # test-only shortcut, delivers content byte-identical. If it doesn't, $claudeExe is unchanged
    # (byte-identical to before this fix): the content-safety belt below (see its own comment)
    # deliberately does NOT extend to this branch, matching this parameter's existing contract that
    # -ClaudePath "already launches whatever file a test points it at directly, never through this
    # resolution block" -- a test double commonly ignores its argv/schema content entirely (see
    # tools/tests/test-invoke-subagent.ps1's fake-claude.cmd, which always returns a canned
    # envelope), so refusing it on cmd.exe-hazard characters it never actually interprets would be a
    # false failure, not a safety improvement. A real run never sets -ClaudePath.
    $claudeExe = Resolve-NativeClaudeExe $claudeExe
    if ($JsonSchemaPath -and $claudeExe -match '\.cmd$') {
        Write-Warning "Invoke-ReadOnlyAgent: -ClaudePath resolved to a .cmd file with no sibling native claude.exe found; -JsonSchemaPath's content would be run through cmd.exe unvalidated on a real (non-test-seam) run using this same .cmd file."
    }
    $skipCmdExeContentCheck = $true
} else {
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

    # 2026-09-22 fix (F12 QA follow-up, PR #197): resolved 'claude.cmd' is a batch file, so Windows
    # launches it through cmd.exe, which re-tokenizes the WHOLE joined command-line string built
    # below and does not honour a backslash-escaped quote (`\"`) the way ConvertTo-QuotedArg (above)
    # assumes -- see that function's own comment, and the extensive cmd.exe-hazard refusal checks
    # this script already has for -SettingsPath/-Tools/-AllowedTools/-JsonSchemaPath. Those checks
    # only cover the PATH strings, never a file's CONTENT (JsonSchemaPath's own doc comment already
    # says so), and --json-schema is the one flag whose value is arbitrary file content rather than a
    # short operator-chosen string. Confirmed live 2026-09-22 (CLI 2.1.278): a --json-schema value
    # containing a `"` and a newline -- ordinary for real, human-readable JSON Schema -- reaches
    # cmd.exe as `"{\"type\":...`; cmd.exe closes the quoted region at that embedded `\"` (it does
    # not treat the backslash as an escape), after which the rest of the schema runs as unquoted
    # shell text, and the literal newline breaks the single-line command string outright. Neither
    # survives, and `claude --json-schema` has no file-path or stdin input mode to route around it
    # (verified against `claude --help` and by a real invocation: passing a path errors "not valid
    # JSON", and a JSON-Schema-without-newlines round-trips fine over stdin/argv when nothing
    # reinterprets the argument -- see this PR's test coverage).
    #
    # claude.cmd's own body is a one-line forward to the real Windows PE binary at
    # node_modules\@anthropic-ai\claude-code\bin\claude.exe, in the same folder Get-Command resolved
    # above. Launching that binary directly skips cmd.exe's re-tokenizing pass entirely --
    # CreateProcess hands it the joined command-line string as-is, and the CLI's own argv parsing
    # follows the standard Windows CommandLineToArgvW convention, where `\"` IS honoured as an
    # escaped embedded quote and a literal newline inside a quoted argument survives -- exactly what
    # ConvertTo-QuotedArg already produces, and exactly what this script's own quoting comments say a
    # normal Windows command line expects. Verified live (2026-09-22): the same quoted --json-schema
    # value that cmd.exe mangles reached the CLI's schema validator intact once claude.exe was
    # launched directly instead of claude.cmd.
    #
    # Preferred whenever the sibling .exe is found, for every run (not only -JsonSchemaPath ones) --
    # it is strictly safer for every other quoted argument on this command line too, and changes
    # nothing about which flags are passed. Falls back to the resolved claude.cmd/bare-claude
    # unchanged (byte-identical launch to before this fix) if the sibling .exe is not where
    # claude.cmd's own body names it (a future npm layout change, or a non-Windows host) -- with a
    # loud warning when -JsonSchemaPath is in play, since that fallback path is the one this fix
    # exists to avoid. -ClaudePath (the test seam) is untouched: it already launches whatever file a
    # test points it at directly, never through this resolution block.
    if ($claudeExe -match '\.cmd$') {
        $claudeExeDir = Split-Path -Parent $claudeExe
        $nativeExe = Join-Path $claudeExeDir 'node_modules\@anthropic-ai\claude-code\bin\claude.exe'
        $resolvedNative = Resolve-NativeClaudeExe $claudeExe
        if ($resolvedNative -ne $claudeExe) {
            $claudeExe = $resolvedNative
        } elseif ($JsonSchemaPath) {
            Write-Warning "Invoke-ReadOnlyAgent: expected the native claude.exe next to claude.cmd at $nativeExe but did not find it; falling back to claude.cmd. -JsonSchemaPath's value is run through cmd.exe on that path and can be mangled if the schema contains a double quote or a line break (see this script's executable-resolution comment)."
        }
    }
}

# issue #206 (Fix A), belt for the fallback: the native-exe bypass above is the real fix (it skips
# cmd.exe's re-tokenizing pass, and its OWN argv parsing honours ConvertTo-QuotedArg's escaping, same
# as every other quoted value on this command line). But the bypass is conditional -- a future npm
# layout change, a non-Windows host, or a -ClaudePath test double with no sibling native exe all fall
# back to launching a .cmd through cmd.exe, which reopens the exact hazard issue #206 describes:
# $jsonSchemaContent (unlike $JsonSchemaPath, the PATH string, checked above at the 'SettingsPath,
# JsonSchemaPath, Tools, AllowedTools' loop) was never checked against cmd.exe's own quote-breaking
# characters at all. Checked here, once, after $claudeExe is final, rather than earlier, so the
# common case (native exe found) never refuses content that is perfectly safe once cmd.exe is out of
# the picture. Fails closed -- exit 2, nothing launched -- exactly like every other unsafe-arg refusal
# in this script, rather than silently truncating or injecting.
if (-not $skipCmdExeContentCheck -and $JsonSchemaPath -and $claudeExe -match '\.cmd$') {
    if ($jsonSchemaContent -match '["%!\r\n]') {
        Write-Host "Invoke-ReadOnlyAgent: refusing -JsonSchemaPath's file CONTENT -- the schema contains a double quote, %, !, or a line break, and this run has no native claude.exe to bypass cmd.exe with (see this script's executable-resolution comment). Nothing was launched." -ForegroundColor Red
        if ($promptFile) { Remove-Item $promptFile -ErrorAction SilentlyContinue }
        if ($appendSystemPromptFile) { Remove-Item $appendSystemPromptFile -ErrorAction SilentlyContinue }
        exit 2
    }
    if ($jsonSchemaContent.TrimEnd("`r", "`n").EndsWith('\')) {
        Write-Host "Invoke-ReadOnlyAgent: refusing -JsonSchemaPath's file CONTENT -- it ends in a backslash, which would escape its closing quote under cmd.exe and this run has no native claude.exe to bypass cmd.exe with. Nothing was launched." -ForegroundColor Red
        if ($promptFile) { Remove-Item $promptFile -ErrorAction SilentlyContinue }
        if ($appendSystemPromptFile) { Remove-Item $appendSystemPromptFile -ErrorAction SilentlyContinue }
        exit 2
    }
}

Write-Verbose "$claudeExe $($claudeArgs -join ' ')$(if ($promptFile) { ' (prompt on stdin)' })"

$stdoutFile = [System.IO.Path]::GetTempFileName()
$stderrFile = [System.IO.Path]::GetTempFileName()
$proc = $null
try {
    $proc = Start-Process -FilePath $claudeExe -ArgumentList $claudeArgs -NoNewWindow -PassThru -RedirectStandardInput $promptFile -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
    # 2026-09-21 fix, found while building F3's non-zero-exit test: a Process object returned by
    # Start-Process -PassThru only records its exit code if its Handle was opened before the process
    # exited. A child that exits fast (e.g. the CLI rejecting its own arguments, the 2026-09-18
    # "--verbose required" failure) left ExitCode $null, and `exit $null` exits 0 -- a failed run
    # reported success. Verified live: same .cmd exiting 1, ExitCode was empty without this line
    # and 1 with it. Opening the handle here, immediately after launch, pins it.
    $null = $proc.Handle
} catch {
    # Write-Host, not Write-Error -- see the note above the settings-file check: Write-Error is
    # itself terminating under $ErrorActionPreference = 'Stop' and would skip the exit code below.
    Write-Host "Invoke-ReadOnlyAgent: failed to launch '$claudeExe': $($_.Exception.GetType().FullName): $($_.Exception.Message)" -ForegroundColor Red
    if ($promptFile) { Remove-Item $promptFile -ErrorAction SilentlyContinue }
    if ($appendSystemPromptFile) { Remove-Item $appendSystemPromptFile -ErrorAction SilentlyContinue }
    Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
    exit 2
}

try {
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        Write-Warning "Invoke-ReadOnlyAgent: '$AgentName' exceeded ${TimeoutSec}s, killing it. This is itself a finding worth reporting -- see headless_agent_permissions.md Verification section for why a run should not hang under --permission-prompts none."
        # PR #176 review round 2: $proc is the cmd.exe running claude.cmd. Killing only it left the
        # node CLI (and anything it started) running after this wrapper reported exit 3. Kill the
        # whole tree; fall back to the single process if taskkill did not end it. The System32 path
        # comes from the OS, not from $env:SystemRoot, which an unset or poisoned environment could
        # change (PR #176 review round 2, safety).
        & (Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe') /T /F /PID $proc.Id 2>&1 | Write-Verbose
        if (-not $proc.WaitForExit(5000)) { try { $proc.Kill() } catch {} }
        Write-Host "Invoke-ReadOnlyAgent: timeout after ${TimeoutSec}s running agent '$AgentName'" -ForegroundColor Red
        Get-Content $stdoutFile -ErrorAction SilentlyContinue
        Get-Content $stderrFile -ErrorAction SilentlyContinue | Write-Verbose
        if ($promptFile) { Remove-Item $promptFile -ErrorAction SilentlyContinue }
        if ($appendSystemPromptFile) { Remove-Item $appendSystemPromptFile -ErrorAction SilentlyContinue }
        Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
        exit 3
    }
} catch {
    Write-Host "Invoke-ReadOnlyAgent: error waiting on '$AgentName': $($_.Exception.GetType().FullName): $($_.Exception.Message)" -ForegroundColor Red
    if ($promptFile) { Remove-Item $promptFile -ErrorAction SilentlyContinue }
    if ($appendSystemPromptFile) { Remove-Item $appendSystemPromptFile -ErrorAction SilentlyContinue }
    Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
    exit 2
}

# The CLI writes UTF-8; without -Encoding, Windows PowerShell 5.1's Get-Content decodes a BOM-less
# file as the ANSI code page and mangles any non-ASCII character in the echoed output (the report
# file below is read separately, as exact UTF-8, and is unaffected either way).
Get-Content $stdoutFile -Encoding UTF8
Get-Content $stderrFile -Encoding UTF8 | Write-Verbose

$claudeExitCode = $proc.ExitCode
if ($null -eq $claudeExitCode) {
    # Belt and braces for the Handle fix above: never let an unreadable exit code become `exit $null`
    # (= 0). Treated as a wrapper-side failure, exit 2, with no report written.
    Write-Host "Invoke-ReadOnlyAgent: could not read the exit code of '$claudeExe' for agent '$AgentName' -- treating the run as failed rather than reporting success." -ForegroundColor Red
    if ($promptFile) { Remove-Item $promptFile -ErrorAction SilentlyContinue }
    if ($appendSystemPromptFile) { Remove-Item $appendSystemPromptFile -ErrorAction SilentlyContinue }
    Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
    exit 2
}

if (-not $reportMode) {
    if ($promptFile) { Remove-Item $promptFile -ErrorAction SilentlyContinue }
    if ($appendSystemPromptFile) { Remove-Item $appendSystemPromptFile -ErrorAction SilentlyContinue }
    Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
    exit $claudeExitCode
}

# --- F3: write {envelope, checkedAt, command} to the drop folder --------------------------------
# The exact command line, as launched: the executable and every argument. The prompt is not part of
# the command line (it goes on stdin) and is deliberately not stored in the report: reports are kept
# indefinitely under %APPDATA%\AEGIS\reports (D6), and prompts are often built from handoff or card
# content (PR #176 review round 2).
$command = "$claudeExe $($claudeArgs -join ' ')"

# Read the CLI's stdout as the exact UTF-8 text it wrote (no BOM added, no line splitting). The
# report embeds these characters untouched -- including the CLI's trailing newline, which is legal
# whitespace between JSON tokens -- so the envelope slot is character-for-character the CLI's stdout.
# (ReadAllText drops a leading UTF-8 BOM if one were ever present; the CLI does not write one.) A
# trimmed copy is used only for the checks below.
$rawStdout = ''
try {
    $rawStdout = [System.IO.File]::ReadAllText($stdoutFile, [System.Text.UTF8Encoding]::new($false))
} catch {
    $rawStdout = ''
}
$trimmedEnvelope = $rawStdout.Trim()
if ($promptFile) { Remove-Item $promptFile -ErrorAction SilentlyContinue }
if ($appendSystemPromptFile) { Remove-Item $appendSystemPromptFile -ErrorAction SilentlyContinue }
Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue

function Exit-NoReport([int]$Code, [string]$Why) {
    Write-Host "Invoke-ReadOnlyAgent: NO REPORT WRITTEN for '$AgentName' -- $Why (claude exit code $claudeExitCode). A missing report is itself the finding; nothing partial was left in $ReportDir." -ForegroundColor Red
    exit $Code
}

# PS 5.1's ConvertFrom-Json (JavaScriptSerializer) accepts some non-JSON (single-quoted strings,
# unquoted keys), and the WCF DataContract JSON reader accepts other non-JSON (a trailing comma, two
# concatenated objects). Requiring BOTH to accept the text is stricter than either alone, and is the
# strictest parser available in Windows PowerShell 5.1 without a dependency. Known residue both still
# accept: NaN and leading-zero numbers, neither of which the CLI's JSON.stringify can emit.
Add-Type -AssemblyName System.Runtime.Serialization -ErrorAction SilentlyContinue
function Test-StrictJson([string]$Text) {
    try { $null = $Text | ConvertFrom-Json -ErrorAction Stop } catch { return $false }
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $reader = [System.Runtime.Serialization.Json.JsonReaderWriterFactory]::CreateJsonReader($bytes, [System.Xml.XmlDictionaryReaderQuotas]::Max)
        try { while ($reader.Read()) { } } finally { $reader.Close() }
    } catch { return $false }
    return $true
}

# F3 brief (SCOPE_F3_F4.md section 6): a nonzero exit must not write an envelope; it fails loudly.
# Checked first, so a complete-looking envelope from a failed run (e.g. error_max_budget_usd) is not
# written either. The CLI's stdout was already echoed above, so nothing is hidden from the caller.
if ($claudeExitCode -ne 0) {
    Exit-NoReport 6 'the CLI exited non-zero; a failed run does not produce an L1 report'
}
if (-not $trimmedEnvelope) {
    Exit-NoReport 6 'the CLI wrote nothing to stdout (no envelope)'
}
if (-not $trimmedEnvelope.StartsWith('{')) {
    Exit-NoReport 6 'the CLI stdout is not a single JSON object (expected the --output-format json result envelope)'
}
try {
    $parsed = $trimmedEnvelope | ConvertFrom-Json -ErrorAction Stop
} catch {
    Exit-NoReport 6 "the CLI stdout is not valid JSON: $($_.Exception.Message)"
}
if (-not (Test-StrictJson $trimmedEnvelope)) {
    Exit-NoReport 6 'the CLI stdout was accepted by the lenient PowerShell parser but is not strict JSON'
}
# Set-StrictMode-safe property checks (tools/README.md): PSObject.Properties, never a dotted read.
$missing = @()
foreach ($key in @('type', 'subtype', 'is_error', 'num_turns', 'total_cost_usd', 'permission_denials', 'usage')) {
    if (-not $parsed.PSObject.Properties[$key]) { $missing += $key }
}
if ($missing.Count -gt 0) {
    Exit-NoReport 6 "the CLI JSON is missing result-envelope key(s): $($missing -join ', ')"
}
if ($parsed.PSObject.Properties['type'].Value -ne 'result') {
    Exit-NoReport 6 "the CLI JSON has type '$($parsed.PSObject.Properties['type'].Value)', not 'result'"
}
if ($parsed.PSObject.Properties['permission_denials'].Value -isnot [array]) {
    Exit-NoReport 6 'the CLI JSON permission_denials is not an array'
}

$tmpPath = $null
try {
    if (-not (Test-Path -LiteralPath $ReportDir -PathType Container)) {
        New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
    }
    # Clock at write time, never typed and never taken from inside the envelope (tools/README.md
    # "Timestamps from the clock"). The file name carries the same instant.
    $now = [DateTime]::UtcNow
    $checkedAt = $now.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    $stamp = $now.ToString('yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture)
    $safeAgent = $AgentName
    foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) { $safeAgent = $safeAgent.Replace([string]$c, '_') }

    $finalPath = Join-Path $ReportDir "$safeAgent.$stamp.json"
    $n = 2
    while (Test-Path -LiteralPath $finalPath) {
        $finalPath = Join-Path $ReportDir "$safeAgent.$stamp-$n.json"
        $n++
    }

    # The envelope goes in as the CLI's own text -- never parsed-and-re-serialised -- so the report
    # carries exactly the fields, order and number formatting the CLI emitted. Only the
    # wrapper-owned values are JSON-encoded here. Exactly {envelope, checkedAt, command} (plan:617).
    $reportText = '{"envelope":' + $rawStdout +
        ',"checkedAt":' + (ConvertTo-Json -InputObject $checkedAt -Compress) +
        ',"command":' + (ConvertTo-Json -InputObject $command -Compress) + '}'

    # Belt and braces for the "never a malformed file" promise: re-check the assembled report with
    # the same strict test before anything touches the drop folder.
    if (-not (Test-StrictJson $reportText)) {
        Exit-NoReport 6 'the assembled report did not re-parse as strict JSON'
    }

    # Atomic publish: write a temp file in the same folder, then rename. A heartbeat-tick reader
    # globbing *.json never sees a half-written report.
    $tmpPath = Join-Path $ReportDir (".$safeAgent.$stamp." + [Guid]::NewGuid().ToString('N') + '.tmp')
    [System.IO.File]::WriteAllText($tmpPath, $reportText, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::Move($tmpPath, $finalPath)
} catch {
    if ($tmpPath) { Remove-Item -LiteralPath $tmpPath -ErrorAction SilentlyContinue }
    Exit-NoReport 7 "the report could not be written: $($_.Exception.GetType().FullName): $($_.Exception.Message)"
}

Write-Host "Invoke-ReadOnlyAgent: report written to $finalPath"
exit $claudeExitCode
