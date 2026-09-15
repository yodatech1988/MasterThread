# Usage monitor

Lets every orchestrator (`standards/sessions/orchestrator_role.md`, "Usage watcher") know when
Jeremy's Claude subscription usage crosses 80, 90, 97, 98 and 99%, without relying on him to say so.

## Start here: `usage-watch.ps1`

**This is the tool to use.** Every orchestrator runs it under the Monitor tool for its whole round:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:/Users/yoda_/GitHub/MasterThread/tools/usage-monitor/usage-watch.ps1" -Name <unique-name> -Program "<what this round is>" 2>&1
```

It polls `https://api.anthropic.com/api/oauth/usage` every 2 minutes (every 45 s above 75%), using
the OAuth token Claude Code keeps in `~/.claude/.credentials.json`. The token is read fresh each
poll, sent only to that endpoint, and never printed or stored. Each event prints one line, and
Monitor delivers it to the session as a notification:

| Line | Meaning |
|---|---|
| `USAGE START` | First reading, other orchestrators running, and whether this is a resumed watcher |
| `USAGE TIER <n>` | A threshold crossed, with the action for this session's role |
| `USAGE PEER` | Another orchestrator started or stopped heartbeating |
| `USAGE AGGREGATOR` | The aggregator changed, and where the new one picks up |
| `USAGE HANDOFF` | (Aggregator only) a peer's handoff file arrived |
| `USAGE RESET` | A window renewed |
| `USAGE-ERROR` / `USAGE-OK` | Data unavailable (usage is UNKNOWN; treat it as high) / flowing again |

With parallel orchestrators, each registers in `%APPDATA%\AEGIS\orchestrators\`. The
earliest-started live one is the aggregator, and at 80% the rest hand off into
`GitHub\USAGE_HANDOFF_<window reset>\`. The runbook is in `orchestrator_role.md`.

`-Once` takes a single reading and exits (0 under 80%, 1 at or above, 2 unknown). It is handy for a
spot check and does not register. It also keeps `claude-usage-state.json` and the pause flag
current, so `check-usage.ps1` still works.

**Caveats.**
- The endpoint is undocumented; it is what the `/usage` screen reads. If its shape changes, the
  watcher says so with `USAGE-ERROR` rather than reporting a wrong number.
- Monitor watches expire after 30 minutes. Re-arm with the same `-Name`. Start time and announced
  tiers survive the restart, so nothing repeats.
- The registry only sees orchestrators on this PC.

Tested 2026-09-15 with simulated readings: every tier, skipped tiers, a window reset, weekly
crossings, malformed data, three concurrent watchers with aggregator hand-off and takeover, a
duplicate name, and re-arming. Also one live reading.

## The earlier statusline approach (kept for check-usage.ps1)

**It does not work from the VS Code extension.** The statusline only runs in the terminal CLI, and
the extension never calls it, so from VS Code the state file below was never written. Use
`usage-watch.ps1` instead.

### Why this shape

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

## How the orchestrator used it (superseded by `usage-watch.ps1`)

Orchestrators now run the usage watcher instead; see the top of this file. The manual check below
still works as a spot check, as long as something keeps the state file current:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\usage-monitor\check-usage.ps1
```

Exit code 1 with `*** PAUSE THRESHOLD CROSSED ***` means: send the pause order to every session
(`ListAgents` → `SendMessage` to each, as done 2026-09-14), record their paused states in the
session handoff file, then run `check-usage.ps1 -Acknowledge`. Only a live Claude Code session can
send that message — this tool can't do it itself, it just makes the threshold crossing checkable
without asking Jeremy.

## Limits

- (statusline.ps1) Only runs in a terminal CLI session, never the VS Code extension. Needs at least one message sent in an active Claude Code session on this machine since the last
  reset before the first data point exists.
- Reports only what this machine's Claude Code process has seen; it's not a live poll of Anthropic's
  servers between sessions.
- If Anthropic ever exposes subscription usage through the Admin API or an equivalent for individual
  seats, prefer that over this file-based approach and retire the statusline dependency.
