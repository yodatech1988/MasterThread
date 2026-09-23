---
name: derive-headless-allowlist
description: Use when a new or changed headless subagent (one that will run as `claude --print --agent <name> ...`, no human watching) needs its `--tools`/`--allowedTools`/`--restricted` grant worked out — instead of writing a plausible-looking Bash allow pattern that silently doesn't match the agent's real commands. Applies to any repo, but the shared tooling and evidence live in `MasterThread/tools/headless/`.
---

# derive-headless-allowlist

## When to use this

- Before a new global or repo-local agent (`claude-agents/*.md`) that holds `Bash` (or another
  tool-running builtin) is first invoked headless, or before `Invoke-ReadOnlyAgent.ps1`'s per-agent
  `roster_meta.json` `allowedTools` overlay is written or changed for it.
- After an existing headless agent's real commands change (its definition file is edited) — a
  previously proven pattern can stop matching.
- Never for a decision about *whether* an agent should run headless at all, or about live/credential/
  money/death-path scope (`headless_agent_permissions.md` "Agents that must never run headless at
  all") — that's a separate call, made before this skill runs, not by it.

## Procedure

1. **Read the agent's real Bash calls verbatim.** Read the agent's definition file
   (`claude-agents/<name>.md` on `origin/<default>`) and, if it wraps a script, that script too.
   Write down each command exactly as issued, including flag order — `git -C <repo> worktree list
   --porcelain` is a different string from `git worktree list`, and only the former is what the
   agent actually runs. Do not paraphrase or infer a "likely" command from the agent's Purpose
   sentence; quote what's in the file.

2. **Check whether Bash is needed at all.** If every real command is pure computation or can be done
   with `Read`/`Grep` only, the answer is `--restricted` (layer 1), not an allow-list — this is
   structurally stronger than any pattern match (`headless_agent_permissions.md` "Three-layer
   ordering", layer 1). Check `claude-agents/roster_meta.json`'s `"readonly"` field for this agent:
   `"tools"` already defaults `-Restricted` on in `Invoke-ReadOnlyAgent.ps1`; if the agent's real
   commands show it needs no Bash but its `roster_meta.json` entry doesn't say `"tools"`, note the
   mismatch in your report rather than silently reclassifying it.

3. **If Bash is genuinely needed, derive one allow pattern per real command.** For each command from
   step 1, write the narrowest `Bash(<prefix>:*)` (or `Bash(<prefix> *)`) that matches the command as
   actually issued. Watch specifically for:
   - **A flag before the subcommand.** `git -C <repo> worktree list` puts `-C <repo>` before
     `worktree`, so `Bash(git worktree list:*)` never matches it (`worktree-sweep`'s row,
     `headless_agent_permissions.md`, confirmed live and denied). Do not reach for `Bash(git -C *)`
     as the fix — it is not safe to grant: `readonly.settings.json`'s deny rules
     (`Bash(git reset *)`, `Bash(git push *)`, etc.) are literal prefixes with no `-C`-awareness, so
     `Bash(git -C *)` would let `git -C <path> reset --hard` / `push --force` / etc. through every
     one of them. If the only pattern that matches the real command is also a deny-list bypass, this
     is a stop condition (see below), not a pattern to grant.
   - **`gh api` write-method detection is best-effort** — `-XPOST`, `--method=POST`, lowercase
     methods, or a method from a shell variable are not caught by the deny list's literal
     `-X POST`/`--method POST` forms. If the agent's real commands include `gh api`, confirm none of
     its own calls use a write method in any form, not just the two the deny list catches.
   - **Any invocation the deny-list's own documented gaps name** (`bash -c '...'`, an absolute path,
     `git -c push.default=current push`, `powershell -Command "..."`) — if the agent's real command
     (or content it reads and could be steered by) could take one of these forms, that's a gap this
     pattern doesn't close; note it rather than treating the pattern as complete.

4. **Cross-check every derived pattern against `tools/headless/readonly.settings.json`'s deny list**
   (read from `origin/<default>`, not a local copy). Confirm the pattern doesn't fall inside a
   documented gap in that file's own "What this rule syntax cannot express" section, and confirm the
   deny list still generalizes across whatever the allow pattern's wildcard covers (the
   `gate-execution-auditor` row is the worked example: `Bash(gh api repos/*)` is broad but verified
   safe because the existing `-X POST` etc. deny rules already generalize across any repo path).

5. **Live-prove the pattern with a positive control AND a negative control** — one occurrence alone
   proves nothing (`docs/LESSONS.md` "Every negative test needs a positive control"). Use
   `tools/headless/Invoke-ReadOnlyAgent.ps1` (or the documented raw `claude --print` invocation in
   `headless_agent_permissions.md` "Recommended headless invocation") with
   `--settings tools/headless/readonly.settings.json --permission-mode dontAsk --permission-prompts
   none`:
   - **ALLOWED run**: the candidate `-AllowedTools`/`--allowedTools` grant, a directive prompt (not a
     soft one the model might pre-empt on its own — see the verification log's finding 1 vs 2) that
     issues exactly the agent's real command(s) from step 1. Must complete with zero
     `permission_denials` for the commands the agent needs.
   - **DENIED run**: the same settings with the grant removed (or narrowed to exclude one command),
     same prompt. Must show the expected command in `permission_denials`, proving the grant — not
     `dontAsk`'s built-in read-only set, and not the model's own caution — is what's doing the work.
   - Save the full raw output of both runs (unedited, not a summary) as
     `tools/headless/evidence/<agent>-ALLOWED-<short-label>-<YYYYMMDD>.jsonl` and
     `tools/headless/evidence/<agent>-DENIED-<short-label>-<YYYYMMDD>.jsonl`, matching the existing
     naming convention (`gate-execution-auditor-ALLOWED-zero-denials-20260918.jsonl`,
     `pr-state-sweep-DENIED-no-allowedtools-20260918.jsonl`). Read the date from the system clock at
     write time (never hand-type it).

6. **Mark the result.** Only call a pattern **PROVEN** when both an ALLOWED and a DENIED evidence
   file exist for it and match what steps 1-4 predicted. Anything else — a pattern only reasoned
   about, a pattern with only one of the two runs, or a run whose result didn't match the
   prediction — is written up as **"not independently tested"**, exactly the phrase
   `headless_agent_permissions.md` already uses for `collision-check`'s row, not upgraded to PROVEN
   on the strength of the reasoning alone.

7. **Propose the change, don't apply it.** Granting a new allow pattern — an edit to
   `claude-agents/roster_meta.json`'s `allowedTools` array, `tools/headless/readonly.settings.json`,
   or `headless_agent_permissions.md`'s table — is a change to checked-in permission configuration,
   not a live action this skill or the session performs unattended. Open it as an ordinary PR (this
   repo's normal flow — `land-pr` once it's up) with the evidence files included, so the owner (or a
   reviewer) sees the ALLOWED/DENIED proof before the wider grant lands. Never edit any
   `settings.json` (project, user, or managed) directly — that is `[Self-Modification]`/`[Permission
   Grant]` territory per `docs/LESSONS.md` "Three new auto-mode classifier hard-block categories" and
   is blocked outright for any session, regardless of authorization already in hand.

## Stop conditions

- **The only matching pattern is also a deny-list bypass** (step 3's `-C` case, or any pattern that
  would let a destructive verb through a deny rule written without awareness of it). Stop; do not
  grant it. Report the gap as unresolved — this mirrors `worktree-sweep`'s row, which was left
  ungranted for exactly this reason.
- **The agent is on `headless_agent_permissions.md`'s "must never run headless" list** (`live-reviewer`,
  `vuln-scan-active`, anything needing live prod/credentials/money not already advisor-shaped, anything
  `needs-local-keys` or `needs-connector`). Stop before step 1 — no allow-list makes this safe to run
  unattended; route the underlying question to the owner instead.
- **A live proof run would need a real secret, touch live production, or spend beyond a small,
  explicit budget ceiling** — `--max-budget-usd` must be set to a small value on every proof run; if
  proving the agent's real behavior can't be done without one of these, stop and ask rather than
  proceeding on a best-effort substitute.
- **The DENIED run doesn't deny, or the ALLOWED run still shows a permission denial for a command the
  agent needs.** Don't loosen the pattern to make the test pass — re-derive it from the real command
  (back to step 3) or report it as not provable with this rule syntax.

## Grounded in

- `standards/sessions/headless_agent_permissions.md` (`origin/main`) — the whole threat model, the
  three-layer ordering, the Bash-usage table (`worktree-sweep`'s `-C`-before-subcommand defect and
  its rejected `Bash(git -C *)` fix; `gate-execution-auditor` and `pr-state-sweep`'s PROVEN rows and
  their evidence files; `collision-check`'s "not independently tested" row), `readonly.settings.json`'s
  documented gaps, and the Verification section's four runs (soft prompt vs directive prompt;
  allow+deny composing together).
- `tools/headless/readonly.settings.json` (`origin/main`) — the deny-list this pattern is
  cross-checked against.
- `tools/headless/Invoke-ReadOnlyAgent.ps1` (`origin/main`) — the wrapper that builds the
  `--restricted` / `--tools`/`--allowedTools` invocation and the `roster_meta.json` `allowedTools`
  lookup this skill's output feeds.
- `claude-agents/roster_meta.json` (`origin/main`) — `"readonly"` classification and the existing
  `allowedTools` entries (`pr-state-sweep`, `plan-status-check`) as the worked shape to match.
- `tools/headless/evidence/*.jsonl` (`origin/main`) — the existing ALLOWED/DENIED file-naming
  convention this skill's step 5 follows.
- `docs/LESSONS.md` (`origin/main`) "Every negative test needs a positive control" and "Three new
  auto-mode classifier hard-block categories".
- `skills/land-pr/SKILL.md`, `skills/owner-click/SKILL.md` (`origin/main`) — reused, not duplicated,
  for landing the resulting PR and for anything that turns out to need the owner's own click.
