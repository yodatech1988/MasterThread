# tools/headless

Read `standards/sessions/headless_agent_permissions.md` first — it has the full rationale, verified
facts with citations, known gaps, and real test results. This directory is just the artifacts it
references:

- `readonly.settings.json` — a `permissions.deny` baseline (defense-in-depth, not the primary
  control) for running a Claude Code subagent with `claude --print --agent <name> ...`. Load with
  `--settings <abs path to this file>`.
- `Invoke-ReadOnlyAgent.ps1` — a thin PowerShell wrapper that builds the recommended headless
  invocation line (this settings file + `--restricted` or a `--tools` allow-list + `dontAsk` +
  `--permission-prompts none` + a budget ceiling + a hard timeout). Plan task F12 added an
  additive `-JsonSchemaPath` passthrough (`--json-schema <path>`); a caller that never passes it
  gets byte-identical behaviour to before that parameter existed.
- `schemas/*.json` — plan task F4: one `--json-schema` per L1 reporter agent, so a run's answer is
  machine-checkable, not prose-parsed. `JsonSchemaLite.ps1` is the subset validator shared between
  the offline test suite and the live wrappers below.
- `budgets.json` — plan task F12: concrete per-line `--max-budget-usd` figures, derived from F3's
  measured envelopes with a stated margin. A line with no entry here, and no explicit override,
  is refused rather than run with a guessed budget.

Neither `readonly.settings.json` nor `Invoke-ReadOnlyAgent.ps1` decides what a given agent is
allowed to do — that's the caller's `--tools`/`-Tools` argument, scoped per agent per the
standard's Bash-usage table.

## Seat-side wrappers (plan task F12)

One command per layer, so a caller (in particular a `low`-effort seat) never hand-assembles a
`claude -p` flag line (docs/FABLE_AGENT_SUBAGENT_PLAN.md section 2/section 5). All three enforce
their boundary flags and a concrete budget before launch, and all three reuse
`Invoke-ReadOnlyAgent.ps1`'s own process management (timeout-and-kill, stdin prompt, cmd.exe
argument safety) rather than reimplementing it.

- **`Invoke-Subagent.ps1`** — the L1/subagent layer (plan section 5 rows 5-7). Resolves the
  per-agent budget from `budgets.json` by the agent's own model frontmatter, and (with `-RunLive`)
  runs a real `claude -p --json-schema` call and validates the returned envelope against the
  agent's F4 schema with `JsonSchemaLite.ps1` — the live acceptance for F4 that PR #190 explicitly
  deferred to F12. Without `-RunLive`, no budget is spent and only the schema's own well-formedness
  is checked (same guarantee `test-headless-schemas.ps1` already gives offline).
- **`Invoke-Lane.ps1`** — a dispatched multi-turn worker session. `claude -p` has no native
  turn-count flag, so `maxTurns` is enforced here as this wrapper's own bookkeeping: a state file
  keyed by `-SessionId` counts turns, and a call once `-MaxTurns` is reached is refused (exit 9)
  before anything launches (owner decision E7: "maxTurns and budget enforcement fold into F12").
  This is this repo's own accounting, not a CLI-enforced limit — see the script's own `.NOTES` for
  what that does and does not cover.
- **`Ask-Fable.ps1`** — the Fable continuity seat (plan section 5, "Fable seat"). Enforces
  `--restricted --tools "Read,Grep,Glob"`, the settings/`dontAsk`/`--strict-mcp-config` baseline, a
  concrete cold-vs-resumed budget, and the wall-clock timeout on every call; refuses to run when
  the working directory is/contains/is inside `%APPDATA%\AEGIS`, holds a `*.clixml` file, or has a
  reparse point (junction or symlink) anywhere beneath it; and reports the CLI's own refusal as
  `stopReason: refusal` rather than retrying on another model. Its own header comment states
  plainly which of its rules are enforced on the actual `claude` command line today and which are
  still only this wrapper's bookkeeping (session-id/resume/fallback-model/fork-session are not
  yet threaded through `Invoke-ReadOnlyAgent.ps1`, which was built around a one-shot named-agent
  invocation) — not hidden as done when it is not.

Tests: `tools/tests/test-invoke-subagent.ps1`, `test-invoke-lane.ps1`, `test-ask-fable.ps1`,
`test-invoke-readonly-agent-jsonschema.ps1`. All static/offline by default; `-RunLive` on
`test-invoke-subagent.ps1` spends real budget for the F4 live-acceptance case.

## L1 report mode (`-Report`, plan task F3)

`-Report` (or an explicit `-ReportDir`) runs the agent with `--output-format json` and writes one
file per run to the drop folder, default `%APPDATA%\AEGIS\reports\` (on this PC, per owner decision
D6):

```
<agent>.<yyyyMMdd-HHmmss>.json   (UTC)
{"envelope": <the CLI's own JSON result, verbatim>, "checkedAt": "<UTC clock at write time>",
 "command": "<exact invocation>"}
```

Exactly those three keys, as plan task F3 names them (`docs/FABLE_AGENT_SUBAGENT_PLAN.md:617`).

- `envelope` is the CLI's stdout embedded as-is (its trailing newline included), never parsed and
  re-serialised, so `permission_denials`, `total_cost_usd`, `usage`, `subtype`, `is_error` and
  `num_turns` are the CLI's numbers, not the agent's prose.
- `checkedAt` comes from the wrapper's clock just before the write, never from inside the envelope.
- `command` is the exact command line launched: the executable and every argument.
- The file is written to a temp name and renamed, so a reader never sees half a report.
- If the CLI exits non-zero, prints no envelope, prints invalid JSON (checked with two parsers,
  since Windows PowerShell's own is lenient), or prints an object missing a key the report relies
  on, nothing is written and the wrapper exits 6. A failed run is never written as a report, even
  when its envelope looks complete (for example `error_max_budget_usd`); its stdout is still echoed
  to the console. If the file cannot be written the wrapper exits 7. If `-Report` is given with no
`-ReportDir` and `%APPDATA%` is unset, it exits 2 before launching anything.
- The `-ClaudePath` test seam is refused unless `AEGIS_TEST_SEAM=1`. In report mode it also needs an
  explicit `-ReportDir` that is not `%APPDATA%\AEGIS\reports`, so a fake CLI's output never lands
  in the real drop folder.

**This shape is not yet the one `standards/sessions/headless_readiness_ladder.md` describes.** The
ladder (in force) still lists a hand-built `{agent, checkedAt, command, exitCode,
permissionDenials, findings[]}`. Updating that standard is a separate, owner-merged (route C)
change, tracked in issue #184. Until it lands, nothing (F7's heartbeat ingest included) should be
built against the ladder's old shape.

### What a report contains, and how long it stays

The prompt is not stored: it goes to the CLI on stdin, and `command` holds only the command line.
So `command` alone does not re-run the same request; the prompt has to be supplied again. That is a
narrower reading of the brief's "exact invocation string", and the brief holder has not confirmed
it yet.

**Known residual, not solved:** leaving the prompt out does not keep secrets out. The whole
envelope is stored. `envelope.result` holds the model's own output in plain text, and
`permission_denials[].tool_input` holds the commands and file paths the agent tried, which can
include file contents. Nothing is redacted, and reports stay in the drop folder until someone deletes
them (D6 has no retention limit). Telling an agent not to repeat a secret back is an instruction, not
a control.

The seam's "not the real drop folder" check compares path strings. A junction, symlink, 8.3 short
name or `\\?\` path pointing at `%APPDATA%\AEGIS\reports` gets past it. It guards against a leftover
`AEGIS_TEST_SEAM=1`. It does not stop a caller who already runs code as this user.

### Behaviour changes for existing (non-report) callers

This PR changes the wrapper for every caller, not only in report mode. The F3 brief holder still
has to confirm them, or they get split into their own PR (PR #176 review):

1. The prompt always goes on stdin, never in the child's argv. This closes a `cmd.exe` injection.
2. Argument guards exit 2 before launch: `-AgentName`/`-Model` must start with a letter or digit and
   stay in a plain character set. `-Tools`/`-AllowedTools`/`-SettingsPath` may not contain `"`,
   `%`, `!` or a line break, and may not end in `\`.
3. The `-SettingsPath`/`-RosterMetaPath` defaults are resolved in the script body, so
   `powershell.exe -File` works.
4. A CLI that exits quickly now reports its real exit code. Before, it reported 0.
5. A timeout kills the whole process tree.
6. There is a new `-ClaudePath` test seam, gated by `AEGIS_TEST_SEAM=1`.

`AEGIS-Register-L1Pilot.ps1` fetches this wrapper from `origin/main` and runs it. Once this merges,
items 1, 2 and 4 change what the L1 pilot sees at its next tick.

### How the prompt reaches the CLI

The prompt always goes on stdin, never on the command line. `claude.cmd` runs through `cmd.exe`,
which ignores `\"` escapes, so a prompt containing a double quote could otherwise run `&`, `|` or
`>` as shell commands outside every Claude permission layer. For the same reason the wrapper
refuses (exit 2) an `-AgentName` or `-Model` that starts with anything but a letter or digit (so it
cannot be read as a new `--flag`) or leaves a plain character set. It also refuses a `-Tools`,
`-AllowedTools` or `-SettingsPath` containing a double quote, `%`, `!` (expanded under `cmd.exe`
delayed expansion) or a line break, or ending in a backslash (which would escape the closing quote
and swallow the arguments after it).

On timeout the wrapper kills the whole process tree (`taskkill /T /F`, from the OS System32 folder,
not `%SystemRoot%`), not only the `cmd.exe`
that runs `claude.cmd`, so the CLI does not keep running after exit 3.

The per-agent `findings[]` shape inside `envelope.result` is F4's `--json-schema` work, not this
script's. Tests: `tools/tests/test-invoke-readonly-agent-report.ps1` (add `-RunLive` for two real
Haiku runs).
