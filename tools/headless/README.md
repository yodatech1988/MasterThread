# tools/headless

Read `standards/sessions/headless_agent_permissions.md` first — it has the full rationale, verified
facts with citations, known gaps, and real test results. This directory is just the artifacts it
references:

- `readonly.settings.json` — a `permissions.deny` baseline (defense-in-depth, not the primary
  control) for running a Claude Code subagent with `claude --print --agent <name> ...`. Load with
  `--settings <abs path to this file>`.
- `Invoke-ReadOnlyAgent.ps1` — a thin PowerShell wrapper that builds the recommended headless
  invocation line (this settings file + `--restricted` or a `--tools` allow-list + `dontAsk` +
  `--permission-prompts none` + a budget ceiling + a hard timeout).

Neither file decides what a given agent is allowed to do — that's the caller's `--tools`/
`-Tools` argument, scoped per agent per the standard's Bash-usage table.

## L1 report mode (`-Report`, plan task F3)

`-Report` (or an explicit `-ReportDir`) runs the agent with `--output-format json` and writes one
file per run to the drop folder, default `%APPDATA%\AEGIS\reports\` (on this PC, per owner decision
D6):

```
<agent>.<yyyyMMdd-HHmmss>.json   (UTC)
{"envelope": <the CLI's own JSON result, verbatim>, "checkedAt": "<UTC clock at write time>",
 "command": "<exact invocation>", "exitCode": <the CLI process's exit code>}
```

- `envelope` is the CLI's stdout embedded as-is (its trailing newline included), never parsed and
  re-serialised, so `permission_denials`, `total_cost_usd`, `usage`, `subtype`, `is_error` and
  `num_turns` are the CLI's numbers, not the agent's prose.
- `checkedAt` comes from the wrapper's clock just before the write, never from inside the envelope.
- `exitCode` is the CLI process's own exit code, so a failed run is visible without inferring it
  from `is_error`/`subtype`.
- A report written through the `-ClaudePath` test seam also carries `"testSeam": true`; treat such a
  file as not being evidence of a real run. `-ClaudePath` is refused unless `AEGIS_TEST_SEAM=1`.
- The file is written to a temp name and renamed, so a reader never sees half a report.
- If the CLI prints no envelope, invalid JSON (checked with two parsers, since Windows PowerShell's
  own is lenient), or an object missing a key the report relies on, nothing is written and the
  wrapper exits 6. If the file cannot be written it exits 7. A complete envelope from a failed run
  (for example `error_max_budget_usd`) is still written, with its `exitCode`, and the CLI's exit
  code is passed through.

**This shape is not yet the one `standards/sessions/headless_readiness_ladder.md` describes.** The
ladder (in force) still lists a hand-built `{agent, checkedAt, command, exitCode,
permissionDenials, findings[]}`. Updating that standard is a separate, owner-merged (route C)
change; until it lands, nothing (F7's heartbeat ingest included) should be built against the
ladder's old shape.

### What a report contains, and how long it stays

`command` records the full prompt, and `envelope.result` holds the model's own output, both in
plain text. Reports stay in the drop folder until someone deletes them. Do not put a secret in a
prompt. `-RedactPrompt` replaces the prompt in `command` with its length and SHA-256; it cannot
redact what the model writes into `envelope.result`.

### How the prompt reaches the CLI

The prompt always goes on stdin, never on the command line. `claude.cmd` runs through `cmd.exe`,
which ignores `\"` escapes, so a prompt containing a double quote could otherwise run `&`, `|` or
`>` as shell commands outside every Claude permission layer. For the same reason the wrapper
refuses (exit 2) an `-AgentName` or `-Model` outside a plain character set, and a `-Tools`,
`-AllowedTools` or `-SettingsPath` containing a double quote, `%` or a line break.

The per-agent `findings[]` shape inside `envelope.result` is F4's `--json-schema` work, not this
script's. Tests: `tools/tests/test-invoke-readonly-agent-report.ps1` (add `-RunLive` for two real
Haiku runs).
