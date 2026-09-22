# Fable seat — the continuity contract (F9 draft)

**Status: DRAFT, not a standard.** This file is a working draft for plan task F9
(`docs/FABLE_AGENT_SUBAGENT_PLAN.md`, PR #169), produced by the `fable/f9` lane
(round `wave3-F12-F9`). Its content is intended to become
`standards/sessions/fable_seat.md`. It is **deliberately not placed at that path in
this PR** — this lane's dispatch keeps it out of `standards/sessions/*`, which is
owner-merge (Route C, `merge_authority.md`): the plan itself says "a session drafts
it; the owner merges it," and relocating this file into the real standards path is
that merge step, done by a session authorized to touch that path. Do not treat this
file as in force. Do not cite it as a standard until it is relocated and merged.

Per owner decision Q4/E10 (issue #187, comment 5770413629, 2026-09-22): F9 is
drafted in parallel with F12, and review of this draft is **held until F12 is
approved**, since several sections below depend on F12's not-yet-built wrapper
interface (marked `TODO(F12)`).

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
- `TODO(F12)`: F12's regression checks are the natural place to add a probe for
  what autocompact actually does to a Fable resume; this draft does not have that
  evidence yet.

## 7. The resume contract

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
    --max-budget-usd <cap, TODO(F12)> "<first question>"

  # every question after that: a separate process, same id, warm context, same boundary flags
  claude -p --resume <stable uuid> \
    --restricted --tools "Read,Grep,Glob" \
    --settings <abs>/tools/headless/readonly.settings.json \
    --permission-mode dontAsk --permission-prompts none \
    --strict-mcp-config --disable-slash-commands \
    --output-format json --json-schema <abs>/tools/headless/schemas/<schema>.json \
    --max-budget-usd <cap, TODO(F12)> "<next question>"
  ```

  (Lines reproduced from plan §5; the concrete `<schema>` and `<cap>` values are
  F12's to set — see §9.)

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

## 9. `TODO(F12)` — points this draft cannot settle

F12 (`Seat-side wrappers so the seat never hand-assembles a flag line`) is the
plan task that owns the `Ask-Fable` / `Invoke-Lane` / `Invoke-Subagent` wrapper
this standard describes the seat operating under. **As of this draft, F12 has no
open PR, issue, or branch** (checked via `gh pr list`, `gh issue list`, and
`git ls-remote` against `origin` on 2026-09-22). The following are therefore left
explicit gaps rather than guessed:

1. **The concrete per-call `--max-budget-usd` figure.** The plan requires F12 to
   set this from F3's measured envelopes; "a line with no concrete cap does not
   run." This draft cannot supply a number.
2. **The wrapper's exact enforcement behavior on a missing boundary flag** —
   refuse to launch vs. exit non-zero after launch, and what that failure looks
   like to the Sonnet seat calling it.
3. **The hard timeout-and-kill value** for the Fable seat / lane lines. F12 must
   carry the same kind of outside-the-process wall-clock kill that
   `tools/headless/Invoke-ReadOnlyAgent.ps1` already has via `-TimeoutSec`
   (default 300s for subagents), but no default has been set for this layer yet.
4. **The cold-start path in full detail** — what exactly happens, mechanically,
   when a pinned `--session-id` no longer resolves. §8 above states the seat-side
   policy (report it, don't swallow it, cold-reopen from the durable record); the
   wrapper-side mechanics (what `Ask-Fable` returns, what exit code, what the
   caller does next) are F12's to define.
5. **`Ask-Fable`'s and `Invoke-Lane`'s exact argument shapes** (2-3 arguments
   each, per the plan's F12 row). This draft cites the plan's provisional raw CLI
   lines (§7) rather than a wrapper call signature, because that signature does
   not exist yet.
6. **`maxTurns` and budget enforcement** generally fold into F12 per owner
   decision E7 (issue #187, comment 5770413629) — whether that becomes its own
   F-task is tracked on Decision Queue card
   `fable-maxturns-budget-enforcement-2026-09-22`, not resolved here.

This draft should be revisited once F12 lands, both to fill in the above and
because — per owner decision Q4/E10 — this draft's review is held until F12 is
approved.
