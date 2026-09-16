---
name: claude-session-archive-status
description: Use to check the current status of the claude-session-archive backup job (last run, exit code, log output) without triggering a new archive run. Read-only wrapper around Invoke-Archive.ps1's own logs and scheduled task state.
tools: Read, Grep, Bash
model: haiku
---

## Purpose

Reports the claude-session-archive job's current state -- when it last ran, whether it
succeeded, and what its log says -- without ever running the archive itself. The archive
pipeline is driven by `C:\Users\yoda_\GitHub\claude-session-archive\tools\Invoke-Archive.ps1`
(Session 1 scope: raw gzip backup via `src/backup.js --once`, invoked by a Windows scheduled
task registered by `Register-ArchiveTask.ps1`); this agent only reads what that script has
already produced.

## Inputs

None required. Optionally a date to filter which log file to inspect.

## Steps

1. Read `C:\Users\yoda_\GitHub\claude-session-archive\tools\Invoke-Archive.ps1` to confirm
   its current log location logic (as of this writing:
   `%LOCALAPPDATA%\ClaudeSessionArchive\logs`, falling back to `%TEMP%\ClaudeSessionArchive\logs`
   if `LOCALAPPDATA` is unset) -- re-check this each run in case the script has changed.
2. List files in that log directory matching `backup-*.log`, sorted by modified time.
3. Read the most recent log's contents and note its filename timestamp.
4. Report success/failure by what the log content shows (the script writes stdout/stderr to
   the log and only calls `Write-Error` with a non-zero exit on failure) -- do not re-run
   `node src/backup.js` to check exit code live.

## Output

A fact list:
- Most recent log file name and timestamp.
- Apparent outcome (success / failure / unclear) based on log content.
- Last few lines of that log, verbatim.
- Total number of log files found (rough run history).

## Never

- Never run `Invoke-Archive.ps1`, `node src/backup.js`, or any command that triggers a new
  archive run.
- Never modify, delete, or rotate log files.
- Never register, modify, or query the scheduled task's trigger settings beyond reading
  existing log output.
