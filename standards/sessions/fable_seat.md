# Fable seat — the continuity contract

**Status: relocated from `docs/drafts/fable_seat_draft.md` (F9, PR #195) into this
standards path.** This is the merge step the F9 draft named as still owed: "a
session drafts it; the owner merges it," done here by a session authorized to
touch `standards/sessions/*` (Route C, `merge_authority.md`). Per owner decision
Q4/E10 (issue #187, comment 5770413629, 2026-09-22), this draft's review was held
until F12 was approved; F12 (`tools/headless/Ask-Fable.ps1`, `Invoke-Lane.ps1`,
`budgets.json`) merged via PR #197, so that hold is cleared. This file remains not
yet owner-merged at this path until this PR itself merges — do not treat it as in
force before then.

All five `TODO(F12)` markers below are resolved against the merged wrappers and
`tools/headless/budgets.json`, with the source flag/value quoted at each point.
One of them (§7/§9) resolves to a real, current limitation rather than to built
behavior: per issues #198 and #205, `Ask-Fable.ps1` does not thread
`--session-id`/`--resume`/`--fallback-model`/`--fork-session` onto the actual
`claude` CLI call — those flags exist only in this wrapper's own bookkeeping and
reporting today. **Until #198/#205 land, the Fable seat is single-turn per
invocation**; do not describe continuity/resume as a built, working feature.

---

## 1. What this seat is

The Fable seat is the estate's one continuity context (plan §3): a resumed,
forkable session whose job is memory across rounds, never operations. Everything
else — lanes, reviews, sweeps, drafts — stays Sonnet and Haiku. There is exactly
one Fable seat, for two reasons (plan §3):

- **Resume economics.** Each distinct `--session-id` pays its own cold start
  (~$0.51) and keeps its own warm context. N seats is N cold starts for a job
  that is rare by design.
- **One continuity history.** Two warm seats are two memories of what the estate
  decided, with no mechanism to reconcile a disagreement between them — unlike two
  reporters disagreeing, which L2 turns into a card.

## 2. The three continuity rules

1. **Memory is a claim, not evidence.** Every answer the seat gives is schema-
   shaped and re-verified by its caller against live state before being acted on.
   A resumed session's recollection of a prior decision is never treated as the
   decision itself — the repo, Fleet Status, and the Decision Queue are.
2. **Cache over a durable record, never instead of one.** Because `--autocompact`
   is unverified (see §6) and a long context can go lossy without announcing which
   parts, everything the seat knows is also written where a cold rebuild can read
   it. If losing the session loses knowledge, the design has already failed.
3. **Fork for speculation, resume for record.** `--fork-session` on a resume opens
   a new session id instead of reusing the original. A speculative or exploratory
   question goes to a fork, so a discarded line of thinking never enters the
   continuity memory as though it were decided.

## 3. What it may produce, and what it never does

The seat answers questions and renders schema-shaped verdicts/recommendations for
its caller (the Sonnet seat, via F12's wrapper) to re-verify and act on.

**Never-builds, never-merges:**

- The Fable seat never writes code, opens a PR, or pushes a branch. Any change it
  recommends is carried out by a row-0/row-1 callee or a lane under the normal
  invocation contract, never by the continuity seat itself.
- It never merges anything, at any Route (A/B/C) — merging is a Merge Authority
  concern (`standards/sessions/merge_authority.md`), unrelated to continuity.
- It has no self-scheduling capability: no `CronCreate`, no `send_later`, no
  `Agent` call reaching outside its rung's roster (plan §5, invariant 3; the
  2026-09-16 self-scheduling incident in `docs/LESSONS.md` is why).
- **Operations must not depend on it.** If the seat is gone, the round still runs
  off the durable record (§2, rule 2). A wrapper that blocks a lane because the
  continuity seat is unreachable has inverted this rule.
- A question whose answer would authorize anything irreversible is never asked of
  the continuity seat at all — it goes to a row-1 callee or an owner Decision
  Queue card (plan §5).

## 4. `--fallback-model opus` is not the refusal path

Per `claude --help` (2.1.278), `--fallback-model` applies "when the default model
is overloaded or not available." Every Fable invocation keeps it for that purpose
only. **If an envelope ever shows the fallback model answering a turn where Fable
refused, the wrapper reports that turn as a refusal, not as an answer** — the
fallback model substituting for a declined answer is not the same event as the
fallback model substituting for an unavailable one, and the two must never be
conflated in what gets reported to the seat's caller or to the owner.

## 5. Refusal handling

`stop_reason: "refusal"` is a safety-classifier decline returned at HTTP 200. A
headless caller that reads `content` without checking `stop_reason` will treat a
refusal as an empty answer, which is worse under a `low`-effort Sonnet seat: it
will relay "nothing found" as a finding rather than surfacing that the callee
declined.

- **A refusal is a stop, and it is reported.** It is never retried on another
  model — the same rule as a permission denial: never route around it.
- The wrapper (F12's `Ask-Fable`) reads `stop_reason` from the envelope and
  returns a refusal to the caller as a refusal, not as content.
- The seat files the refusal for the owner and does not re-ask elsewhere.

## 6. A position on `--autocompact`

`--autocompact`'s behavior on a long-running resumed session is **unmeasured** —
neither this draft nor plan §3/§11 has verified what it drops or when. The
position this draft takes, pending real measurement:

- Treat `--autocompact` as **off by default** on the Fable seat's session until a
  measurement exists showing what it compacts and how that interacts with the
  resume contract (§7). An unannounced loss of context is exactly the failure §2
  rule 2 exists to prevent (a durable record outside the session), so leaving
  autocompact on without measurement doubles down on an already-mitigated risk
  rather than eliminating it.
- If a measurement later shows autocompact preserves everything the durable
  record does not already capture, this position should be revisited — it is a
  default, not a permanent prohibition.
- **`TODO(F12)` resolved: still unmeasured.** F12 landed (PR #197) without adding
  an autocompact probe — `Ask-Fable.ps1` and `Invoke-Lane.ps1` (as merged) carry
  no `--autocompact` flag or regression check for it at all (confirmed by reading
  both scripts' full parameter lists and bodies; neither mentions `autocompact`).
  This position therefore stands unchanged and unverified pending a future
  measurement; it is not blocked on anything else in F12.

## 7. The resume contract

**Current real limit (per #198/#205, checked against the merged `Ask-Fable.ps1`):
this is the seat's intended, eventual contract, not what today's wrapper actually
does.** `Ask-Fable.ps1`'s own in-file NOTE (the comment block above its
`Invoke-ReadOnlyAgent.ps1` call) states plainly: "`Invoke-ReadOnlyAgent.ps1` does
not currently expose `--fallback-model`, `--session-id`, `--resume`, or
`--fork-session` as parameters... those... are CONVENTION ONLY, NOT YET ENFORCED
ON THE CLAUDE COMMAND LINE." The wrapper tracks cold-vs-resumed state in its own
local state file (`%APPDATA%\AEGIS\fable\<SessionId>.json`) and reports
`coldStart` to its caller, but every actual `claude` invocation it launches is a
fresh, unresumed conversation regardless of that bookkeeping. **Until #198/#205
land and are confirmed live, treat every Fable seat call as single-turn: do not
drive it with a reused session id expecting real continuity**, per issue #205's
stated launch constraint (owner-accepted 2026-09-22, non-blocking for launch
since the seat is "continuity-only and never load-bearing for operations,"
#169 §3). The rest of this section describes the target contract below.

- **Always the same `--session-id`; never `--no-session-persistence`** (it
  disables the resume that *is* the continuity).
- **`--fork-session`** for a speculative question, per §2 rule 3.
- The seat's boundary flags are **per process, not per session**, and must be
  passed on **every** call — the owner working in the seat directly does not need
  them, but every unattended (Sonnet-seat-driven) call does:

  ```
  # open the callee once
  claude -p --model fable --effort high --fallback-model opus \
    --restricted --tools "Read,Grep,Glob" \
    --settings <abs>/tools/headless/readonly.settings.json \
    --permission-mode dontAsk --permission-prompts none \
    --strict-mcp-config --disable-slash-commands \
    --session-id <stable uuid> \
    --output-format json --json-schema <abs>/tools/headless/schemas/<schema>.json \
    --max-budget-usd 1.00 "<first question>"

  # every question after that: a separate process, same id, warm context, same boundary flags
  claude -p --resume <stable uuid> \
    --restricted --tools "Read,Grep,Glob" \
    --settings <abs>/tools/headless/readonly.settings.json \
    --permission-mode dontAsk --permission-prompts none \
    --strict-mcp-config --disable-slash-commands \
    --output-format json --json-schema <abs>/tools/headless/schemas/<schema>.json \
    --max-budget-usd 0.20 "<next question>"
  ```

  (Lines reproduced from plan §5. The `<cap>` values are resolved: `1.00` USD
  cold, `0.20` USD resumed — `tools/headless/budgets.json`'s `fableSeat` table,
  `"coldUsd": 1.00` / `"resumedUsd": 0.20`, merged via PR #197. The `<schema>`
  value is still open: no `tools/headless/schemas/*.json` file exists for the
  Fable seat's own question/answer shape as of this PR — the existing schemas
  under that directory are all for other L1 reporters (`gate-execution-auditor`,
  `plan-status-check`, `pr-state-sweep`, `register-verifier`,
  `standard-buildstate-checker`, `worktree-sweep`); none is Fable-shaped. That
  remains open work, not F12's to have set.)

- **The wrapper enforces these flags; it does not merely default them.** F12's
  `Ask-Fable` must refuse to run if any boundary flag is missing, not silently
  fill one in.
- **Working-directory refusal.** `Ask-Fable` must refuse to run when the working
  directory is, contains, or is inside `%APPDATA%\AEGIS`, holds a `*.clixml` or
  other key file, or has a reparse point (junction or symlink) anywhere beneath
  it (plan §5, "Fable seat"; PR #175 review round 2).
- **One session, two callers — what carries across a resume, restated here per
  plan §5's explicit instruction that F9 restate both points:**
  - **Permissions do not carry.** An "always allow" the owner grants
    interactively is saved to a settings file, not to the session. An unattended
    call under `--restricted` ignores user, project and local settings files, so
    none of those grants reach it — only `--settings readonly.settings.json` and
    managed settings apply.
  - **Content does carry**, and that includes untrusted text. Anything that
    entered the context in an interactive turn (a pasted issue, a fetched page, a
    diff) is in the context of the next unattended turn, and nothing removes it.
    Three things contain the risk: the unattended surface has no write, exec, web
    or MCP tool, so an injected instruction has nothing to act with; every answer
    is schema-shaped and treated as a claim the seat's caller re-verifies against
    live state (§2 rule 1); and a question whose answer would authorize anything
    irreversible is never asked of the continuity seat at all (§3).

## 8. Retirement and cold-reopen trigger

The plan is explicit that mitigating this is required and "the answer is not
'never'" (plan, line ~934). This draft's position:

- The seat is **retired** (its session id abandoned, not resumed further) when
  any of the following holds:
  - A resume against the pinned `--session-id` fails to resolve (expired,
    rebooted, or never created) — this is the cold-start case F12 owns (§9); a
    failed resume is never silently treated as a fresh, un-flagged session. It is
    reported as a cold reopen, not swallowed.
  - The durable record (repo, Fleet Status, Decision Queue) and the seat's
    answers disagree on a matter of fact more than once in a round — per §2 rule
    1, the durable record wins, and repeated disagreement is a signal the
    session's memory has drifted enough to distrust further, not just the one
    answer.
  - A owner-declared session rotation applies to it, same as any other session
    (per the standing CLAUDE.md rotation guidance) — heavy compaction, long
    wall-clock age, or workstream completion.
- **Cold-reopen**: a fresh `--session-id` is generated, and the seat's warm
  context is rebuilt from the durable record (§2 rule 2) — never from asking the
  retired session to "remember," since a retired session's memory is exactly what
  triggered the retirement.
- Every retirement and cold-reopen is recorded (Fleet Status or a handoff note),
  so a later reader can tell the seat's context is fresh rather than assuming
  continuity that was actually reset.

## 9. `TODO(F12)` resolutions

F12 merged via PR #197 (`tools/headless/Ask-Fable.ps1`, `Invoke-Lane.ps1`,
`Invoke-Subagent.ps1`, `budgets.json`). The five points the F9 draft left open are
resolved here from the merged wrappers and `budgets.json` only, each with the
flag or value it was taken from:

1. **Concrete per-call `--max-budget-usd`.** `tools/headless/budgets.json`,
   `fableSeat` table: `"coldUsd": 1.00` (first call on a new/expired
   `--session-id`), `"resumedUsd": 0.20` (every call after). `Ask-Fable.ps1`'s
   `Get-ResolvedFableBudget` function reads these two keys and exits 4, refusing
   to launch, if either is missing or the file cannot be parsed — it never
   guesses a default. (`Invoke-Lane.ps1`'s own per-call cap, for comparison, is
   the `lane` table: `"sonnet": 1.50`, `"opus": 4.00`, `"default": 1.50`.)
2. **Enforcement behavior on a missing boundary flag: refuses to launch, not a
   post-launch exit.** `Ask-Fable.ps1` validates `-SessionId` as a UUID and exits
   11 before anything runs if it isn't; runs `Test-UnsafeFableWorkingDirectory`
   and exits 10 before anything runs if the working directory is unsafe;
   resolves the budget and exits 4 before anything runs if no concrete figure is
   available. Its own `.NOTES` block documents this as "Exit codes: 0 = ran
   (including a reported refusal...) ... 4 = no concrete budget resolvable ...
   10 = unsafe working directory, refused before launch ... 11 = -SessionId is
   not a UUID." `Invoke-Lane.ps1` follows the same shape: exit 2 (bad session
   id), exit 5 (`-Tools` required without `-AgentName` — "there is no safe
   default tool set for a lane"), exit 4 (no budget), exit 9 (`-MaxTurns`
   already reached for that `-SessionId`, "refused before launch, turn counter
   NOT incremented").
3. **Hard timeout-and-kill value: 300 seconds, both wrappers.** `Ask-Fable.ps1`:
   `[int]$TimeoutSec = 300` (parameter default). `Invoke-Lane.ps1`: same,
   `[int]$TimeoutSec = 300`, its `.PARAMETER TimeoutSec` doc reading "Hard
   wall-clock timeout per call. Default 300, same as Invoke-ReadOnlyAgent.ps1."
   Both shell out to `Invoke-ReadOnlyAgent.ps1` for the actual process-management
   kill rather than reimplementing it.
4. **Cold-start path, mechanically.** `Ask-Fable.ps1` keeps a per-`SessionId`
   state file at `%APPDATA%\AEGIS\fable\<SessionId>.json`. `$isColdStart = (-not
   $knownOpen) -or [bool]$Fork` — true when no state file exists yet, or the call
   is `-Fork`. A cold call resolves the `coldUsd` budget tier and, on success,
   writes the state file so the *next* call for that `-SessionId` is treated as
   resumed. **But** — per §7's caveat and issues #198/#205 — this is the
   wrapper's own bookkeeping only; it does not change what actually reaches the
   `claude` CLI, which never receives `--session-id`/`--resume` at all today, so
   every call, cold-tracked or not, is a real fresh conversation. A failed
   resolve (a `-SessionId` the wrapper doesn't recognize) is therefore not
   currently distinguishable from an ordinary cold call in the wrapper's own
   terms — there is no separate "resume failed, reopening cold" code path,
   because there is no real resume to fail. This is the concrete shape of the
   single-turn limit stated in §7.
5. **`Ask-Fable`'s and `Invoke-Lane`'s exact argument shapes.** `Ask-Fable.ps1`:
   `-SessionId` (required, UUID), `-Question` (required), `-WorkingDirectory`
   (default current directory), `-Fork` (switch), `-MaxBudgetUsd` (optional
   override), `-TimeoutSec` (default 300), `-FallbackModel` (default `'opus'`),
   plus test seams `-StateDir`/`-BudgetsPath`/`-InvokeReadOnlyAgentPath`/
   `-ClaudePath` and `-DryRun`. `Invoke-Lane.ps1`: `-SessionId` (required, UUID),
   `-Prompt` (required), `-MaxTurns` (required — "there is no safe default. a
   lane with no stated cap is exactly what E7 exists to stop"), `-AgentName`
   (optional named agent), `-Tools` (required if `-AgentName` omitted), `-Model`,
   `-MaxBudgetUsd`, `-TimeoutSec` (default 300), plus the same class of test
   seams and `-DryRun`.
6. **`maxTurns`/budget enforcement folded into F12, as decided (E7).**
   `Invoke-Lane.ps1` enforces `-MaxTurns` externally, in its own per-`SessionId`
   turn-count state file under `-StateDir` (default `%APPDATA%\AEGIS\lanes`),
   since (its own `.DESCRIPTION`) "`claude -p` has no native per-process
   turn-count flag (confirmed against `claude --help` on the installed 2.1.278
   build)." It documents its own limitation plainly: "this counter is this
   wrapper's own bookkeeping, not a CLI-enforced limit... It closes the 'nothing
   enforces maxTurns' gap for every caller that goes through this script; it is
   not a boundary against a caller that does not." Decision Queue card
   `fable-maxturns-budget-enforcement-2026-09-22` tracked whether this became its
   own F-task; per E7 it did not — it is delivered as part of F12, as above.

**What remains a real, disclosed gap after F12 (not a TODO owed to this
standard, but stated so this file doesn't imply otherwise):** `--session-id`,
`--resume`, `--fallback-model`, and `--fork-session` are not passed to the actual
`claude` CLI invocation by either wrapper (§7). Tracked in issues #198 and #205.
Per #205's stated constraint, no caller — PM, a lane, or the Fable seat itself —
should drive `Ask-Fable.ps1` (or the Fable seat) with a reused session id
expecting continuity until this lands and is confirmed live. This standard's
continuity model (§1-§3, §8) describes the seat's intended role and design;
today's actual operating mode is single-turn per invocation.
