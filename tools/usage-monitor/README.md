# Usage monitor

Lets the orchestrator role (`standards/sessions/orchestrator_role.md`, "Cost rule") auto-detect
when Jeremy's Claude Code subscription usage crosses ~80%, instead of relying on him to say so.

## Why this shape

Jeremy's usage runs through `CLAUDE_CODE_OAUTH_TOKEN` — an individual Claude.ai Pro/Max
subscription seat, not pay-per-token API billing. That rules out the pattern used by
`jarvis/tools/AnthropicAdminKeyTool.ps1` (Admin API key → `/v1/organizations/...`): the Admin API's
usage/cost endpoints and the Claude Code Analytics API are scoped to Console (API-key) workspaces
and Team/Enterprise orgs. An individual Pro/Max plan has no organization to query there, so those
endpoints report nothing for this account. (Checked against `code.claude.com/docs/en/costs`,
2026-09-14 — re-verify if Anthropic changes this.)

The one place Claude Code exposes subscription-seat usage machine-readably is the **statusline**
mechanism (`code.claude.com/docs/en/statusline`). Claude Code pipes a JSON blob to the configured
statusline command every time it redraws (new assistant message, `/compact`, a rate-limit window's
`resets_at` passing, etc.). For a Claude.ai Pro/Max subscriber, that JSON includes:

```json
"rate_limits": {
  "five_hour": { "used_percentage": 92, "resets_at": 1900000000 },
  "seven_day": { "used_percentage": 30, "resets_at": 1900500000 }
}
```

`used_percentage` (0–100) and `resets_at` (Unix epoch seconds) for the rolling 5-hour window and
the weekly window. Nothing else on an individual plan carries this data outside the interactive
`/usage` screen, which isn't scriptable.

## What's here

- **`statusline.ps1`** — install this as the statusline command. It prints a compact status line
  (model, cost, context %, both rate-limit windows) and, on every run, writes the rate-limit numbers
  to `%APPDATA%\AEGIS\claude-usage-state.json`. If either window is at or above 80% (`-PauseThreshold`
  to change it), it also writes `%APPDATA%\AEGIS\claude-usage-pause-flag.json` — that file is the
  actual trigger. It clears itself automatically once usage drops back under the threshold or the
  window resets.
- **`check-usage.ps1`** — run this from any session (the orchestrator, in particular) to read the
  last-known numbers and see whether the pause flag is raised. `-Acknowledge` marks a raised flag as
  handled so repeat checks don't tell you to pause again for the same crossing; the flag still
  clears itself for real once usage actually drops.

Both run locally, make no network calls, and read only files this repo's own script wrote — no
tokens spent checking, matching the docs' note that the statusline "runs locally and does not
consume API tokens."

## Setup (one-time, per machine)

Add to `~/.claude/settings.json` (merge with whatever's already there — don't replace the file):

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\yoda_\\GitHub\\MasterThread\\tools\\usage-monitor\\statusline.ps1"
  }
}
```

Claude Code picks this up on save; no restart needed. The first data point appears after a
session's first API response (the doc notes `rate_limits` is absent until then).

## How the orchestrator uses it

At the start of a round, and periodically during a long one:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\usage-monitor\check-usage.ps1
```

Exit code 1 with `*** PAUSE THRESHOLD CROSSED ***` means: send the pause order to every session
(`ListAgents` → `SendMessage` to each, as done 2026-09-14), record their paused states in the
session handoff file, then run `check-usage.ps1 -Acknowledge`. Only a live Claude Code session can
send that message — this tool can't do it itself, it just makes the threshold crossing checkable
without asking Jeremy.

## Limits

- Needs at least one message sent in an active Claude Code session on this machine since the last
  reset before the first data point exists.
- Reports only what this machine's Claude Code process has seen; it's not a live poll of Anthropic's
  servers between sessions.
- If Anthropic ever exposes subscription usage through the Admin API or an equivalent for individual
  seats, prefer that over this file-based approach and retire the statusline dependency.
