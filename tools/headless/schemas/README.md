# tools/headless/schemas

Plan task F4 (`docs/FABLE_AGENT_SUBAGENT_PLAN.md`): one JSON Schema per L1 reporter. Each schema
constrains that reporter's `result` through `claude -p --json-schema`, so the L2 comparator reads
fields it can check instead of parsing prose.

| Schema | Agent definition it mirrors (Output section) |
|---|---|
| `pr-state-sweep.json` | `claude-agents/pr-state-sweep.md` |
| `plan-status-check.json` | `claude-agents/plan-status-check.md` |
| `worktree-sweep.json` | `claude-agents/worktree-sweep.md` |
| `standard-buildstate-checker.json` | `claude-agents/standard-buildstate-checker.md` |
| `register-verifier.json` | `claude-agents/register-verifier.md` |
| `gate-execution-auditor.json` | `claude-agents/gate-execution-auditor.md` (both modes) |

The list is the L1 row of `standards/sessions/headless_readiness_ladder.md`.
`check_agent_sync.py` is also on that row, but it is a Python script rather than a `claude -p --agent`
reporter, so it has no schema. `tools/tests/test-headless-schemas.ps1` fails if this folder and the
ladder's list drift apart.

## Shape rules (checked by the test)

- `agent` is pinned with `const` to the agent's own name.
- Each schema has `findings` (`{kind, subject, detail}`, with `kind` an enum per agent) and
  `couldNotCheck` (`{subject, reason}`). An empty `findings` array is only a clean result if
  `couldNotCheck` is also empty. A schema with no place to record "could not reach" would push the
  model toward a clean-looking answer.
- Everything else follows that agent's own Output section: its tables, its flags, and its Lessons
  block where the definition requires one.
- Keywords stay inside the subset structured outputs supports: `type`, `properties`, `required`,
  `additionalProperties: false`, `items`, `enum`, `const`, `anyOf`, plus `title` and `description`.
  No `minimum`, `minLength`, `pattern` or `minItems`.
- Every object is closed (`additionalProperties: false`) and lists all of its properties in
  `required`. An optional value is written as `anyOf [x, null]`, so the model has to state it, even
  if only as `null`.
- The schemas contain no agent-typed "checked at" timestamp. The run's time is the F3 report's
  `checkedAt`, which comes from the wrapper's clock.

## Not yet verified or wired

- **Nobody has run these files through the CLI yet.** The tests check them statically: a subset
  validator, plus a Python `jsonschema` cross-check. Nothing here has been passed to a real
  `claude -p --json-schema` run.
- **Path vs. inline.** `claude --help` (2.1.278) describes `--json-schema <schema>` with an inline
  JSON example. The plan's section 5 passes a file path (`--json-schema <abs>/tools/headless/schemas/<name>.json`).
  Which form the CLI accepts has not been tested. If the flag only takes inline JSON, the caller has
  to read the file and pass its contents. Through `claude.cmd`, that contents string runs into the
  `cmd.exe` double-quote problem that `Invoke-ReadOnlyAgent.ps1` already refuses for other arguments.
- `Invoke-ReadOnlyAgent.ps1` does not pass `--json-schema` yet. Wiring it into the seat-side
  wrappers belongs to plan task F12 (after F2 and F4), not this task.
