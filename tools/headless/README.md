# tools/headless

Read `standards/sessions/headless_agent_permissions.md` first — it has the full rationale, verified
facts with citations, known gaps, and real test results. This directory is just the artifacts it
references:

- `readonly.settings.json` — a `permissions.deny` baseline (defense-in-depth, not the primary
  control) for running a Claude Code subagent with `claude --print --agent <name> ...`. Load with
  `--settings <abs path to this file>`.
- `Invoke-ReadOnlyAgent.ps1` — a thin PowerShell wrapper that builds the recommended headless
  invocation line (this settings file + `--tools` allow-list + `dontAsk` + `--permission-prompts
  none` + a budget ceiling + a hard timeout).

Neither file decides what a given agent is allowed to do — that's the caller's `--tools`/
`-Tools` argument, scoped per agent per the standard's Bash-usage table.
