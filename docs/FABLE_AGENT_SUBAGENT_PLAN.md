# Fable → Agent → Subagent: how the three layers should be built headless

Status: **DRAFT for owner review, 2026-09-21.** Plan only. Nothing here is built, no lane is
dispatched, no standard is edited, no Decision Queue card is filed. Every task below is written to
be handed to a worker. **This is a planning artifact: the session that wrote it does not build it.**

Scope: how the estate's existing headless infrastructure (`tools/headless/`,
`claude-agents/`, `standards/sessions/headless_readiness_ladder.md`, `tools/pm-heartbeat/`,
`tools/cost-monitor/`) should be extended so that **every task runs at a deliberately chosen model
and effort**, unattended, on the subscription, without raising the rung the
`headless_readiness_ladder.md` currently sits on (L0) until its own exit criteria are met.

---

## 1. Research findings — what is true today

### 1a. Live-verified against this checkout and the installed CLI, 2026-09-21

Claude Code **2.1.278**, `claude --help` read directly; probe runs executed and their JSON result
envelopes read. Four findings change what the current standards say is possible.

**F1 — `--effort` exists as a per-invocation flag.** `claude --effort <low|medium|high|xhigh|max>`
is a documented CLI option. `standards/sessions/orchestrator_role.md` ("Assigning model and effort
to each task") currently states: *"Effort for background workers can't be set per call, so state the
depth in the prompt."* That is still true of the in-session `Agent` tool, which takes a model only.
It is **no longer true of a headless `claude -p` run**, which is the entire shape this plan is
about. The standard needs a correction (task F10).

**F2 — agent definitions can pin `effort`, and none of ours do.** The CLI's agent-config parser
accepts `model`, `effort`, `permissionMode`, `maxTurns`, `mcpServers`, `hooks`, `skills` and
`memory` (read from the installed `cli.js` agent-config assembly). Measured across this repo:

| | count |
|---|---|
| agent files in `claude-agents/` + `.claude/agents/` | 88 |
| pinning `model:` | **88** (37 haiku, 50 sonnet, 1 opus) |
| pinning `maxTurns:` | 86 (the 2 in `.claude/agents/` do not) |
| **pinning `effort:`** | **0** |

So the pinning is total on one half of the cost lever and absent on the other: **88 of 88 pin a
model, 0 of 88 pin an effort**.

**Inferred, not probed:** that an unpinned subagent therefore inherits its caller's effort — so a
Haiku reporter summoned from an `xhigh` seat would think at `xhigh`. That follows from the config
resolution (an absent key has nothing to override the session value with), but no probe in this
document tested inheritance across a spawn. **Task F1b has now run that probe, and the answer is
worse than "inheritance works": the pin itself does nothing observable.** What remains certain is
the count itself, and that closing it would be a file edit rather than new machinery — but see
below for why closing it is not worth doing.

**F1b — measured 2026-09-22, CLI 2.1.278. Two paths tested, both negative.** The question was the
one F1 rests on: does an agent-level `effort:` pin move
`usage.output_tokens_details.thinking_tokens` at all?

Path 1 — `--agent`/`--agents` (an agent selected for a whole session), thinking tokens:

| session `--effort` | agent pin | thinking |
|---|---|---|
| low | `effort: max` | 0, 0 |
| low | none | 0, 0 |
| max | `effort: low` | 11,611, 20,084 |
| max | none | 9,368, 16,680 |

Path 2 — a real frontmatter file in `.claude/agents/*.md`, spawned via the Task tool from a parent
at `--effort low`, aggregate thinking tokens:

- subagent pinned `effort: max`: 13, then 0
- subagent unpinned: 0

For scale, a session genuinely running at `max` produced 9,000–20,000 thinking tokens. **Session
effort dominated in both directions on both paths; the agent-level pin moved nothing observable.**

**Consequence, stated plainly: F1 — pinning `effort:` across 88 agent files — buys nothing on this
evidence, and is condemned.** The owner approved cutting it *if* an independent cross-check
confirms. **That cross-check was still running when this was written**, so F1 is marked
**CONDEMNED — pending independent confirmation** in §6 rather than deleted, and this is recorded as
a negative measurement awaiting confirmation, not as a disproved claim.

**The variance is large, and the arms are not separable from each other.** 9,368 against 20,084 on
identical config is a two-fold spread, so pinned-versus-unpinned at the same session effort cannot
be told apart from noise at this sample size. The finding therefore rests on the **direction**
tests, not on that comparison: a `max` pin under a `low` session produced literally zero thinking,
and a `low` pin under a `max` session produced 11k–20k. Both directions say the session setting
wins and the pin is inert.

**F3 — `--restricted` is a stronger boundary than the deny-list we built.**
`--restricted` "removes the built-in tools that run commands or code (Bash, PowerShell, REPL and
the other code-running tools) and WebFetch unless `--tools` names them, and ignores user, project
and local settings files (managed settings and `--settings` still apply)."

Probe (Haiku, `--restricted`, `--permission-mode dontAsk --permission-prompts none`), asked to run
`echo RESTRICTED_PROBE` and report which happened:

```
NO_BASH_TOOL
```

The tool is **absent from the surface**, not denied at call time. That closes, by construction, the
gap `standards/sessions/headless_agent_permissions.md` documents against itself — that
`readonly.settings.json`'s deny rules are pattern-matched command text, "defeated by `bash -c
'...'`, an absolute path, or reordered flags." A tool that does not exist cannot be reached by a
cleverer spelling of the command. `--restricted` also ignores user/project/local settings, which
removes a second live hole: a repo's own `settings.local.json` silently widening a headless run.

This does not retire `readonly.settings.json`. It re-orders the layers: `--restricted` becomes the
primary boundary for every advisor/drafter/reporter that needs no shell, `--tools` re-admits the
exact read verbs a `gh`/`git` reporter needs, and the deny-list stays as layer 3 for the callers
that must hold `Bash` at all.

**F4 — the L1 report envelope the ladder says is "Not built" is already emitted.**
`--output-format json` returns, per run:

```
subtype, is_error, num_turns, result, total_cost_usd, permission_denials[], usage{...}
```

`usage` breaks out `input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`,
`output_tokens` (with `thinking_tokens`), `service_tier`, `speed`, and a per-iteration array.
`headless_readiness_ladder.md` specifies a wrapper-invented
`{agent, checkedAt, command, exitCode, permissionDenials, findings[]}` and marks the drop folder
**Not built**. Three of those five fields, plus full cost telemetry, come free from the CLI. And
`--json-schema <schema>` constrains `result` to a caller-supplied JSON Schema — probe returned
`{"agent":"probe-agent","findings":["a","b"]}` against a schema requiring exactly those keys. So
the L1 report should be **the CLI's envelope plus `checkedAt` and `command` from the wrapper**, with
`findings[]` schema-enforced per agent — not a hand-rolled shape the agent has to be trusted to
produce.

`permission_denials` being a first-class array matters specifically: L1's exit criterion in the
ladder is *measured on that field* ("7 consecutive days … with zero `permission_denials` against
legitimate reads"). It is machine-readable today.

### 1b. Cost, measured rather than assumed

Two probe runs, same flags, same machine, minutes apart, Haiku:

| Run | cache **write** | cache **read** | output | reported `total_cost_usd` |
|---|---|---|---|---|
| 1 (cold) | 25,469 | 0 | 234 | **$0.0531** |
| 2 (warm, same prefix) | 3,854 | 21,612 | 321 | **$0.0125** |

Three things follow.

**The system prompt is the cost, not the work.** A trivial Haiku reporter that does nothing spends
~25K cache-write tokens on its own preamble. The task itself was ~250 output tokens. Choosing Haiku
over Sonnet saves less than choosing to not pay for the preamble again.

**Warm beats cold by ~4.3×** and the cache is `ephemeral_1h` (the usage block names
`ephemeral_1h_input_tokens`, not `5m`). Back-to-back invocations sharing a byte-identical prefix
read the preamble instead of writing it.

**The 1-hour write multiplier is 2×, not 1.25×.** Run 1 reconciles at Haiku $1/MTok input only if
cache writes bill at $2/MTok (25,469 × 2/1e6 = $0.051, + 234 output × $5/1e6 = $0.0012 ⇒ $0.052 vs
$0.0531 reported); at 1.25× it would be ~$0.033. **Per PR #159's description** (the file itself is
not in this checkout — `tools/cost-monitor/` does not exist here, the PR is open and draft, see
§1c), `config.json` carries the cache-write multiplier as **ASSUMED** across a 1.25×–2× range, with
alerts on the high end. That attribution is a read of the PR body, not of the file.
This measurement says the high end is not a safety margin for headless runs — it is the actual
rate. That is a finding for PR #159, not a change this plan makes.

**Derived per-invocation floor by model** (25K-token preamble, cold, 1h TTL at 2× input):

| Model | input $/MTok | output $/MTok | cache read $/MTok | cold preamble cost | warm preamble cost |
|---|---|---|---|---|---|
| Haiku 4.5 | 1 | 5 | 0.10 | ~$0.051 | ~$0.0026 |
| Sonnet 5 | 2 | 10 | 0.20 | ~$0.102 | ~$0.0051 |
| Opus 5 | 5 | 25 | 0.50 | ~$0.255 | ~$0.0128 |
| **Fable 5.1** | **10** | **50** | **0.25** | **~$0.509** | **~$0.0064** |

Rates from the bundled Claude API reference. The Fable `cache_read_factor_override` (0.025) is
**reported by PR #159's description** to be in `ops-policies` `routing/models.yaml`; that file is
not in this repo and was not read, so this is a second-hand agreement between two documents, not a
cross-check against the rate table itself. Fable's cache-write multiplier is **not** separately documented and is assumed standard —
flag it as unverified.

**The Fable row is the important one, in both directions.**

- Cold, a Fable headless invocation costs **~$0.51 before it reads a single file** — 10× a cold
  Haiku one, 2× a cold Opus one. A design that spawns `claude -p --model fable` per task is
  paying half a dollar per spawn for nothing.
- Warm, Fable reads cached context at **$0.25/MTok — half of Opus's $0.50**, because of the 0.025×
  override. For a seat whose input is dominated by cache reads (PR #159 measured exactly that on
  the real transcripts: "cache reads dominate"), Fable's *input* line is cheaper than Opus's, while
  its *output* line is 2× Opus's.

That is the whole economic argument for the layer split, and it is independent of capability:
**Fable is cheap where it reads a lot and writes a little, and expensive where it writes.** Reading
a lot and writing a little is what planning, triage and a hard three-way merge look like. Writing a
lot is what building looks like. So Fable plans and does not build — for cost reasons that agree
with the capability reasons already in `session_plan_standard.md`.

### 1c. What the estate already has (do not rebuild)

| Exists | State |
|---|---|
| `tools/headless/readonly.settings.json` | Built, verified 2026-09-18, 4 live test runs |
| `tools/headless/Invoke-ReadOnlyAgent.ps1` | Built; resolves `claude.cmd` explicitly, quotes args, forces `--verbose` under `stream-json`, puts the prompt on stdin when `--allowedTools` is used |
| `claude-agents/` (88 defs) + `roster_meta.json` + `generate_agents_md.py --check` in CI | Built; drift-checked by `agents-roster-check.yml` |
| `tools/pm-heartbeat/` | Built (PR #108); watchdog task **registered** — owner card `action-register-pm-heartbeat-watchdog-2026-09-18` resolved `Done` 2026-09-18, and Windows scheduled task `AEGIS-PmHeartbeat-Watchdog` confirmed present and ticking every 15 minutes on 2026-09-21 (see entry gate condition 5) |
| `tools/cost-monitor/` | PR #159 **open, draft** (re-checked 2026-09-21) |
| `standards/sessions/headless_readiness_ladder.md` | **IN FORCE as of 2026-09-22** (PR #170 merged 2026-09-22T00:52Z; confirmed on `origin/main`). Formally the fleet is still at **L0**: no rung is recorded as climbed until L1's 7-day exit criterion is met and its climbing card is filed. **But an owner-approved L1 pilot is already running (next row)**, so "L0" means "no rung formally reached", not "nothing runs unattended" |
| Windows scheduled task `AEGIS-L1Pilot` | **An owner-approved L1 pilot, running since 2026-09-19.** Decision card `approve-l1-pilot-scheduled-task-2026-09-18` was resolved by the owner on 2026-09-18T11:56Z ("Approve the pilot"). Action card `action-register-l1-pilot-2026-09-18` was claimed by the owner on 2026-09-19T13:31Z and verified live by the merge seat on 2026-09-19T13:57Z. Both were read directly from the Decision Queue store on 2026-09-22. The task runs `pr-state-sweep` and `gate-execution-auditor` read-only every 4 hours through `Invoke-ReadOnlyAgent.ps1` and writes to `%APPDATA%\AEGIS\reports\`. Re-checked with `Get-ScheduledTask` at 2026-09-21 21:44 local: state `Ready`, last run 21:31, result 0. Its description says it is "self-refreshing from origin/main", so **every merge to `main` becomes code this task runs on the owner's PC at its next tick**. The owner was told this on the registration card. The ladder's build-state row on `origin/main` ("L1 scheduled task … **Not built**") predates the pilot and is stale. Correcting it is a route-C edit and not part of this plan. Whether the relayed F5 WAIT (§9) also covers this pilot is on card `fable-l1-pilot-vs-f5-wait-2026-09-22`. |
| `skills/round-start`, `dispatch-lane`, `land-pr`, `round-closeout`, `owner-click` | Built |
| Decision Queue, Fleet Status, `merge_authority.md` routes A/B/C | Built |

Not built, per the ladder's own build-state table (stale on the first item, see the pilot row above): any scheduled L1 run, the per-agent
`--allowedTools` overlay, the reports drop folder and PM ingest, the L2 comparator, the L4
UNENFORCED=0 gate.

---

## 2. The binding constraint: the owner's seat is Sonnet 5 / low

**Owner constraint, stated 2026-09-21:** *"I will have to be able to interface with this production
and development using only one session of sonnet 5 low."*

This is the constraint everything else has to fit, and an earlier draft of this document did not fit
it. That draft treated Fable as a **seat** — something a person sits in to design a round. Under
this constraint no one sits in a Fable seat, because the owner has exactly one seat and it is
Sonnet 5 at `low` effort. So:

> **The Sonnet 5 / low seat never upgrades itself. It dispatches a callee instead.** The routing
> table in §4 picks the *callee's* model and effort; it never picks this seat's, which is fixed.
> Opus is only ever a callee. **Fable is the exception**: it is also the owner's continuity seat
> (§3), a session he works in directly — and the Sonnet seat drives that same session headlessly by
> its id when it needs an answer. That is one session with two callers, not two sessions.

*"Able to interface … using only one session of sonnet 5 low"* is read here as a **capability
requirement, not an exclusivity claim**: the estate must be *operable* from that one seat. Nothing
in it forbids another session existing, so long as no round depends on one.

### What a Sonnet 5 / low seat can and cannot do

`low` effort means fewer and more-consolidated tool calls, less preamble, terser output. That is a
capable seat for *routing* and a poor one for *deriving*. Four rules follow, and they are
requirements on the system, not advice to the operator:

1. **Every decision the seat makes must be a table lookup, not a judgment.** §4's first-row-that-
   matches table is exactly this shape and is the reason it must stay mechanical. A rule the seat
   has to reason about is a rule that will be applied wrong at `low`.
2. **The seat never hand-assembles an invocation.** The lines in §5 run to ten flags; composing them
   correctly per call is precisely the work `low` effort is bad at, and a mis-typed `--settings` or
   a dropped `--permission-prompts none` fails open. They belong in wrappers the seat calls by name
   with two or three arguments (task F12).
3. **Every callee returns a schema, not prose.** A Sonnet 5 / low seat cannot deeply evaluate a wall
   of reviewer prose — it will summarise it, and a summary is the thing this estate keeps mistaking
   for a fact (`fleet_structure.md`). `--json-schema` is therefore not an optimisation at L1; it is
   how a high-tier callee's output becomes safe for a low-effort seat to act on. Every Opus- and
   Fable-tier call gets one.
4. **The seat never judges production.** Row 1 work is dispatched to an Opus callee or to an owner
   click-file (`skills/owner-click`), never decided in the seat. This was already the estate's rule;
   the constraint makes it structural rather than a discipline.

### How the Sonnet seat reaches the Fable seat — measured

The Fable seat is reached by **pinning a session id once and resuming it**, which keeps the context
warm across separate processes — so the owner's interactive turns and the Sonnet seat's headless
questions land in the same continuous context:

```
# once, to open the callee (boundary flags abbreviated here; the full line is in §5)
claude -p --model fable --effort high --fallback-model opus --restricted --tools "Read,Grep,Glob" ... \
  --session-id <stable uuid> --output-format json --json-schema <schema> "<first question>"

# every question after that, a separate process, same id, same boundary flags
claude -p --resume <stable uuid> --restricted --tools "Read,Grep,Glob" ... \
  --output-format json --json-schema <schema> "<next question>"
```

Verified on this machine with Haiku standing in for the callee: a `--session-id` call followed by a
`--resume` call **in a separate process** carried context correctly, and the resumed call reported
`cache_read_input_tokens` 28,870 against `cache_creation_input_tokens` 136 — essentially the whole
context served warm. Re-verified 2026-09-22 (CLI 2.1.278, Haiku) with the §5 boundary flags on both
calls. The resumed call recalled the codeword, served 6,398 tokens from cache against 170 written, and
reported that it had only `Glob`, `Grep` and `Read`. Asked to run `echo`, it answered
`NO_BASH_TOOL`. The boundary flags do not break resume.

That is what makes the constraint affordable. A cold Fable spawn pays ~$0.51 of preamble before it
reads anything (§1b); a resumed Fable call reading ~29K cached tokens pays about **$0.007** of
input at Fable's $0.25/MTok cache-read rate. **Per design question, resume is roughly seventy times
cheaper than respawn.** The earlier draft's "one long-lived resumed session" instinct was right; its
reason was incomplete. It is kept warm for **both** callers: for the owner, because it is where
continuity lives (§3), and for the Sonnet 5 / low seat, which cannot afford to re-explain the estate
on every question.

Caveat: `--no-session-persistence` disables resume and must never appear on a callee invocation.
Whether a pinned session id survives a machine reboot, and what the seat does when a resume target
has expired, are not verified here — F12 must define the cold-start path, because a seat at `low`
will not improvise one.

### Mobile review and approval — mostly already built

**Owner requirement, 2026-09-21:** review and approval must work from a phone, and every task is
performed by an agent. Checked against the estate rather than designed from scratch, because most of
this already exists:

| Surface | Mobile today? | Evidence |
|---|---|---|
| Decision Queue — resolving a **decision** card | **Yes** | `decision_queue_standard.md` "The approval-device gate", 2026-09-20: `settings/approval-device` is a *list*, so a computer and a phone can both be paired and both act at once. The phone-viewport check no longer blocks approving — it adds one extra tap (three total, 10s arm window) as an accidental-tap guard. |
| Decision Queue — **action** cards | **Yes** | Same gate. "I did it — check it" writes `claimedAt` and leaves the card open; a session verifies live state and closes it **on evidence, not on the button**. |
| Fleet Status — reading state | **Yes**, though tuned elsewhere | It is a web page. Its `?wallboard=1` mode is built for a second monitor, not a phone; phone layout is untuned but not blocked. |
| The seat itself | **Yes** | One Sonnet 5 / low Claude Code session, reachable from a phone. |
| **Running a click-file** | **No** | `tools/click-files/*.cmd` are Windows double-click scripts. A phone can *approve* that class and cannot *execute* it. |

Two things the owner should know about that gate, stated in its own words: it is **"not real
security"** — a `localStorage` id matched against a shared-db pairing list, bypassable with DevTools
on a paired browser — and it is **"a policy nudge … not an access-control mechanism."** It guards
against a wrong-device tap while the fleet runs headless. It is not a substitute for the
owner-initiated binding `fleet_structure.md` requires for a hard-to-reverse action.

So the mobile work left is not approval. It is **making what arrives worth approving on a phone**:

1. **The reviewable unit is the card, not the diff.** Nobody reviews a 600-line diff on a phone, and
   a Sonnet 5 / low seat cannot summarise one safely. An agent reviews the diff; the card carries
   verdict, findings (each with `file:line` and a one-line ask), and a recommendation. The owner
   approves the card. This is `decision_queue_standard.md` "Writing a card to be scanned" applied to
   review output, and it is the same requirement as §2 rule 3 — schema, not prose.
2. **Only the seat can write the mobile surfaces.** `claude -p` cannot hold `ArtifactData`
   (`headless_readiness_ladder.md`), so no agent writes a card or a Fleet Status row. Agents file
   JSON reports; the seat ingests and writes. This is not a limitation to engineer around — it is
   what keeps a headless agent from filing its own approval.
3. **The click-file class stays desk-bound** until the approval app exists. Notably **F5's own
   registration is a click-file**, so the step that reaches L1 cannot be completed from a phone. That
   is an owner decision, not something this plan designs away (§9 decision 6).

### The operating loop

One tick, with every task performed by an agent and the owner touching only a phone:

1. **Owner opens the seat** (or a scheduled trigger wakes it) and says go.
2. **Seat reads state** — `round-start`: Fleet Status, the Decision Queue read directly, the report
   drop folder. No derivation; it is reading.
3. **Seat ingests unread agent reports** → writes Fleet Status rows and files cards for anything
   needing a human. The seat is the only writer of these surfaces.
4. **Seat dispatches by table lookup** (§4), one wrapper call each (F12), never a hand-typed flag
   line: `Ask-Fable` (resume) for a design call; `Invoke-Lane` (Sonnet) for lane work;
   `Invoke-Review` (Opus, schema) for a row-1 review; `Invoke-Subagent` (Haiku, batched) for sweeps.
5. **Agents run headless** and write schema-checked JSON reports. They never write a card, never
   merge, never self-schedule.
6. **Owner reads and taps on the phone** — summary on top, links in `points`, three taps to confirm.
7. Repeat.

The owner's whole interface is: read a card, tap an option. Everything between taps is an agent.

### The F-task tracker — mobile progress board

**Owner requirement, 2026-09-22:** the estate must keep its own live progress tracker of this
plan's execution — F-tasks, rounds, agents, status — updated as each agent starts, returns or
blocks, so the owner can watch from a phone. This tracks the *plan's own build-out* (§6's
F-tasks), distinct from Fleet Status (fleet-wide) and the Decision Queue (owner decisions, not
status).

**Who writes it — the same rule as every other mobile surface, above:** the Sonnet 5 / low seat,
never an agent and never the Fable seat.

- An F-task agent files a schema-checked JSON report, exactly as it already does toward Fleet
  Status (step 5 above: agents "never write a card"). It never touches the tracker's `db`
  directly — `claude -p` cannot hold `ArtifactData` regardless of which surface is on the other
  end.
- The Fable seat does not write it either, even though the owner named it after this plan.
  Writing a row on every agent start/return/block is operational bookkeeping at dispatch
  cadence, not a per-round continuity read — exactly what §3 forbids the Fable seat: "load-
  bearing for continuity and must never be load-bearing for operations." Routing tracker writes
  through Fable would make every dispatch depend on a warm resumed session that §3 says
  operations must survive losing.
- So the tracker is written by the same seat, in the same step, that already writes Fleet Status
  rows and files cards (steps 3 and 7 above): "Seat ingests unread agent reports → writes Fleet
  Status rows and files cards for anything needing a human. The seat is the only writer of these
  surfaces." This tracker joins "these surfaces."

**Created before the first *dispatchable* F-task** — i.e. before Group A's first task that is not
F1a/F1b runs. F1a and F1b were gate-exempt and already reported (§7) before this requirement was
written, so the tracker's first write on creation is a backfill of those two rows as `done` (their
§1a-reported outcomes as the `note`), not an empty board pretending nothing happened yet.

**Row mapping.** One row per F-task id from §6's tables (`F1a`, `F1b`, `F1`, `F2`, `F3`, `F4`, `F5`
… `F14`) — the doc id in the tracker's `items` collection is the F-task id itself, so the board and
the plan's own tables stay in lockstep.

| Field | Value |
|---|---|
| `group` | The build-plan group letter and name, e.g. `"Group A"` |
| `order` | The row's position in that group's table |
| `title` | The task's one-line `Task` cell text |
| `status` | `todo` until dispatched; `in-progress` from dispatch to report; `done` on a clean report; `blocked` on a failed report, an unmet dependency, or (F1, F5) a standing gate |
| `who` | The dispatched agent/session name |
| `note` | One line, status only — e.g. `"waiting on F4"`, `"condemned pending confirmation"`, `"PR opened"` — never code, logs, secrets, or a diff |

A task that retries stays one row: `note` gets `"(retry 2)"` rather than a second row, so the
board stays a phone-scannable list rather than growing with every round.

**`meta/summary`** carries `{headline, updatedAt}`, rewritten on every seat write — e.g. `"Group A:
5/7 done, F5 waiting on owner instruction"` — so the phone view leads with one line before the list.

**At handoff or rotation:** the tracker is itself the durable record (like Fleet Status), so an
incoming seat reads it fresh rather than trusting a handoff file's claim about it — the same rule
§3 already states for continuity ("a claim, not evidence"). The one obligation on the outgoing
seat is to leave no row falsely `done` or `in-progress` — re-verify against live `gh`/report state
before rotating, per the same caution `orchestrator_role.md:277` already recorded once. The
handoff file need only name the tracker's URL; the rows are not repeated into it.

## 3. The three layers

**Fable is not a new tier.** The estate already has T0 owner → T1 program PM → T2 round
orchestrator → T3 lane lead → T4 task subagent → T5 deterministic script
(`orchestrator_role.md`, `docs/AGENTS.md`). Adding a "Fable tier" would add a relay hop, and
`fleet_structure.md` is explicit that a layer which only forwards is not earning its place. Fable is
a **model assignment on a headless callee**, and the most expensive one in the estate.

Per §2, only the first row is a seat. The other two are things that seat invokes.

| Layer | What it is | Who holds it | Model | Effort | Shape |
|---|---|---|---|---|---|
| **Seat** | The owner's single interface to production and development. Routes, dispatches, relays, files cards. Derives nothing. | T1/T2, **the only seat**, owner-operated | `claude-sonnet-5` | **`low`, always** | Interactive. Never changes model or effort to suit a task — it changes the callee instead |
| **Fable seat** | **Continuity** first — what changed, what we decided, what's next, carried across rounds. Also the *designer*: turns a negotiated ask into a fixed workload, settles a design call, resolves a hard three-way merge | the owner's, **one at a time**; never required for a round to proceed | `claude-fable-5-1` | `high` (`xhigh` on a failed retry) | **Warm and resumed**: `--session-id` once, `--resume` thereafter, `--fork-session` for speculation, `--fallback-model opus`, schema-constrained when the Sonnet seat must act on the answer |
| **Agent** | The lane worker: one repo, one worktree, one branch, one PR | invoked by the seat | `claude-sonnet-5` (Opus 5 for row 1) | `medium` (`high` for invariant-heavy edits) | `claude -p` per lane, own worktree |
| **Subagent** | The roster agent: a report or a verdict, no worktree, no PR | invoked by the seat or by a lane | pinned in frontmatter (haiku / sonnet / opus) | **pinned in frontmatter** (task F1) | `claude -p --agent <name> --restricted`, batched |

### The two jobs Fable must not take

1. **It never builds.** No worktree, no branch, no PR authored by a Fable seat. Its outputs are a
   dispatch plan, a design verdict, or a resolved merge conflict. Everything that produces lines of
   code or documentation is a Sonnet lane. Cost says so (2× Opus on output); `orchestrator_role.md`
   already says so of the orchestrator generally ("It doesn't do the implementation itself").
2. **It never holds merge authority.** `merge_authority.md` principle 3 and the ladder's L4 row:
   route A stays a CI job, routes B and C stay a session or the owner. A Fable seat is a headless
   process, so it never merges — and neither does the seat on its behalf without the route's own
   procedure.

### What the Fable seat is actually for: continuity

**Owner, 2026-09-21: *"I use the fable seat for continuity."*** An earlier draft of this document
had this wrong in both directions — first as a seat someone sits in to design a round, then
over-corrected into a callee invoked rarely for row-0 work. Neither is what it is. It is the layer
that **remembers across rounds**, and it is touched every round, not rarely.

That resolves the apparent conflict with §2. *"Able to interface … using only one session of
sonnet 5 low"* is a **capability requirement, not an exclusivity claim**: the estate must be
operable from that one seat. It does not say no other session exists. So:

> **The Fable seat is load-bearing for continuity and must never be load-bearing for operations.**
> If it is unavailable, the estate runs — degraded in memory, not in capability. Any round that
> *cannot proceed* without it has violated §2.

It also makes Fable's economics better than the row-0 framing did. A continuity layer reads a large
accumulated context and emits a little — what changed, what we decided, what's next. That is
precisely the read-heavy / write-light profile where Fable's $0.25/MTok cache read beats Opus's
$0.50, and it is the **best-fitting role for Fable anywhere in this estate**. Resume is not an
optimisation here; it *is* the continuity.

#### The three rules that make a continuity seat safe

1. **Its memory is a claim, not evidence.** This estate has already run this experiment with its
   existing continuity mechanism and lost: `orchestrator_role.md:277` records that "the
   restart-backup signoff was carried as resolved across two handoffs before either one was true",
   and `pm_role.md:266` states flatly that "a handoff repeating 'resolved' is not evidence." A warm
   Fable seat is the same failure shape with a better memory and no diff for anyone to read.
   Everything it carries forward is re-verified against live state before it is acted on — the rule
   the estate already applies to handoff files, applied to a session's context.
2. **It is a cache over a durable record, never the record itself.** Session ids expire (how long is
   unverified — F12), `--autocompact` makes a long context lossy without announcing which parts, and
   a lost session must be rebuildable. So everything the seat knows is also written where a cold
   rebuild can read it: the repo, Fleet Status, the Decision Queue. If losing the session loses
   knowledge, the design has already failed.
3. **Fork for speculation, resume for record.** `--fork-session` on a resume creates a new session id
   instead of reusing the original. A speculative or exploratory question goes to a fork, so a
   discarded line of thinking never enters the continuity memory as though it were decided.

### Does it have to be one Fable agent? No — and it must not be

**Is Fable most of the work?** No. Continuity is one job, and everything between rounds — lanes,
reviews, sweeps, drafts — stays Sonnet and Haiku. Routing the work through Fable would cost ~5×
Sonnet on input and ~5× on output to do what Sonnet does correctly, against a standing cost rule
that says use the cheapest model that clears the bar and don't start high to be safe.

**Should there be exactly one Fable seat rather than several?** Yes, and for two reasons that are
sharper now that its job is memory:

- **Resume economics.** Each distinct `--session-id` has its own cold start (~$0.51) and its own
  warm context. N Fable seats is N cold starts and N contexts to keep from going stale, to get a
  tier whose whole job is rare.
- **Two continuity contexts are two histories.** `fleet_structure.md`'s verification rules open with
  a real incident: a shared checkout left two sessions reaching opposite conclusions about the same
  file. Two warm seats are two memories of what the estate decided, and the estate has no mechanism
  for reconciling them — and unlike two reporters disagreeing (which L2 turns into a card), nothing
  would even surface the disagreement.

So: **one Fable seat, resumed, forked for speculation, retired and reopened cold on a defined
trigger (F9) — load-bearing for memory, never for operations.** Everything else stays Sonnet and
Haiku.

### Why a warm callee, not per-task spawns

At ~$0.51 of cold preamble per invocation, N Fable spawns cost N × $0.51 before any work. A resumed
callee pays it once and then reads its context at $0.25/MTok — the cheapest cached-input rate of any
model above Sonnet, and measured at ~$0.007 for a ~29K-token context (§2). **Roughly seventy times
cheaper per question.** This is the only layer where "resume, don't respawn" earns the
session-persistence complexity; Haiku subagents at $0.0026 warm should stay stateless and are
cheaper to respawn than to track.

Two Fable-specific API behaviours the caller must handle (both from the Claude API reference, neither
currently anywhere in `standards/`):

- **`stop_reason: "refusal"`**: a safety classifier can decline at HTTP 200. A headless seat that
  reads `content` without checking the stop reason will treat a refusal as an empty answer. This
  matters more under §2's constraint than it would otherwise: a Sonnet 5 / low seat reading a
  refusal as an empty report will not notice, and will relay "nothing found" as a finding. **A
  refusal is a stop, and it is reported. It is never retried on another model.** F12's `Ask-Fable`
  must read `stop_reason` from the envelope and return a refusal to the seat as a refusal. The seat
  files it for the owner and does not re-ask elsewhere. That is the same rule as a permission
  denial: never route around it. **`--fallback-model opus` is not the refusal path.** Per
  `claude --help` (2.1.278) it applies "when the default model is overloaded or not available", and
  every Fable invocation keeps it for that purpose only. If an envelope ever shows the fallback model
  answering a turn where Fable refused, the wrapper reports that turn as a refusal, not as an answer.
  F9 writes this into the callee standard.
- **Thinking is always on and its raw chain is never returned**; `budget_tokens` is rejected with a
  400. Depth is controlled *only* by `--effort`. Forced tool choice is also rejected. None of this
  bites the CLI path today, but it constrains any future direct-API caller.

---

## 4. Model and effort for every task

Supersedes nothing until merged; written to slot into `orchestrator_role.md`'s existing
"Assigning model and effort to each task" table, which stays the first-row-that-matches rule.

**Read this table as picking the callee, never the seat.** Per §2 the seat is Sonnet 5 / `low`
whatever row matches; a row-0 or row-1 task does not upgrade the seat, it dispatches a callee. The
estate's existing instruction to "hand it to a one-off Opus 5 / high reviewer instead of upgrading
itself" (`orchestrator_role.md`) is the same rule, and under this constraint it is the only
available move rather than the preferred one.

| # | Task shape | Model | Effort | Layer | Headless form |
|---|---|---|---|---|---|
| 0 | Turning a still-negotiated ask into a fixed workload; a design call the round cannot settle; a three-way merge after two sessions already collided | **Fable 5.1** | `high` (`xhigh` on a failed retry) | Fable | one resumed session, `--fallback-model opus` |
| 1 | Touches live production, credentials/secrets, money, or the death/damage path; or sets a contract other sessions build on | **Opus 5** | `high` (`xhigh` on a failed retry) | Agent / Subagent (`live-reviewer`) | interactive only for `live-reviewer`, per its own file |
| 2 | Large multi-file data edit where invariants matter; cross-mod classname sweep | **Sonnet 5** | `high` | Agent | `claude -p`, own worktree |
| 3 | Normal plan session with a clear Read / Do / Done-when | **Sonnet 5** | `medium` | Agent | `claude -p`, own worktree |
| 4 | Doc-only work: status-table fixes, ledger refresh, handoff notes, small config edits with a validator | **Sonnet 5** | `low` | Agent | `claude -p`, own worktree |
| 5 | An **advisor**: renders a verdict against a named standard, no action, Read/Grep only | **Sonnet 5** or Haiku per its file | `low` | Subagent | `--restricted --agent <name>`, batched |
| 6 | A **drafter**: produces content in a standard's format, never places it | **Sonnet 5** | `medium` | Subagent | `--restricted --agent <name>`, batched |
| 7 | Mechanical read-only sweep: PR/CI state, worktrees, grep inventories, fixed-rule cleanup | **Haiku 4.5** | *(see note)* | Subagent | `--agent <name> --restricted --tools "Bash,Grep,Read" --allowedTools <exact read verbs>`, batched |
| 8 | Anything with a deterministic answer | **no model** | — | T5 | a script; `generate_agents_md.py --check` is the pattern |

Rules that carry over unchanged: **pick the first row that matches**; downgrade when the plan has
already done the hard thinking; upgrade one row when the task is live-adjacent with no rollback, or
when an earlier run in the same lane failed; never start high "to be safe"
(`orchestrator_role.md`, cost rule). Priority (P0–P3) and model/effort stay independent axes
(`priority_classification.md`).

**Note on row 7 (Haiku + effort) — F1a has reported; this reverses the earlier advice.** The Claude
API reference states `effort` errors on Haiku 4.5, so an earlier draft of this document said not to
pin effort on a Haiku agent. **Measured 2026-09-22 (CLI 2.1.278), that advice was wrong.** Three
trials per level, `claude -p --model haiku --effort <level>`, thinking tokens:

| `--effort low` | `--effort max` |
|---|---|
| 516, 235, 472 | 676, 548, 550 |

Ranges do not overlap; ~1.45× more thinking at `max`. So `--effort` does reach Haiku through the
CLI. The likely mechanism is that Claude Code translates effort into something Haiku accepts rather
than passing it through — **that mechanism is a hypothesis, not verified**, and the API-level
restriction may still bite a direct API caller.

**This settles that effort works on Haiku. It does not settle that *pinning* works on any model** —
see F1b in §1a, which is a separate question and has reported **negative**.

**Row 1 vs row 0 is deliberately left alone.** On the cache-read economics above, Fable is cheaper
on input than Opus for a long read-heavy review, which is what row 1's `live-reviewer` is. That is
an argument, not evidence: `live-reviewer` is built, proven, pinned `opus`, and marked interactive-
only. Changing the model on the estate's irreversibility reviewer is an owner decision that should
follow a measurement, not precede one — see §7 open decision 2.

---

## 5. The headless invocation contract

One line per layer. Each extends the recommended line already in
`headless_agent_permissions.md`; the additions are `--restricted`, `--effort`, `--json-schema` and
`--fallback-model`.

**Subagent, no shell needed (rows 5 and 6 — most of the 88):**

```
claude -p --agent <name> --restricted \
  --effort <low|medium> \
  --settings <abs>/tools/headless/readonly.settings.json \
  --permission-mode dontAsk --permission-prompts none \
  --strict-mcp-config --disable-slash-commands \
  --output-format json --json-schema <abs>/tools/headless/schemas/<name>.json \
  --max-budget-usd <per-agent cap, set by F12>
```

**Subagent needing read-only `gh`/`git` (row 7):**

```
claude -p --agent <name> --restricted --tools "Bash,Grep,Read" \
  --allowedTools "Bash(gh pr list:*)" "Bash(gh pr view:*)" "Bash(git ls-remote:*)" <exact list, see below> \
  --settings <abs>/tools/headless/readonly.settings.json \
  --permission-mode dontAsk --permission-prompts none \
  --strict-mcp-config --disable-slash-commands \
  --output-format json --json-schema <abs>/tools/headless/schemas/<name>.json \
  --max-budget-usd <per-agent cap, set by F12>
```

`--restricted` stays on here too. `--tools` names `Bash` explicitly, which re-admits it, and
`--restricted` still ignores user, project and local settings files. That closes the second hole
(§1a) on this line as well. Probed 2026-09-22 (CLI 2.1.278, Haiku), with exactly these boundary flags
and `--allowedTools "Bash(echo:*)"`:

- `echo ROW7_PROBE_OK` ran.
- `mkdir row7_probe_dir` was **denied**. It was recorded in `permission_denials`, and the directory
  was not created.
- `whoami` also ran, although no allow rule named it.

So **the allow-list is not the only way a command gets in.** The CLI also auto-allows commands it
classifies as read-only. Writes are still denied, so the line holds as a read-only boundary. It is
not an exact verb list, and F4/F12 must not describe it as one. The `<exact list>` is a placeholder,
not a pattern: F4 pins each row-7 agent's verbs from that agent's documented commands, and F12
passes exactly that list. Nothing is widened with a wildcard.

**Fable seat**: the owner's continuity seat (§3). The owner works in it directly. The Sonnet 5 / low
seat drives the same session headlessly by the same id when it needs an answer. When the Sonnet seat
drives it, the line carries **the same boundary layers as a subagent line**:

```
# open the callee once
claude -p --model fable --effort high --fallback-model opus \
  --restricted --tools "Read,Grep,Glob" \
  --settings <abs>/tools/headless/readonly.settings.json \
  --permission-mode dontAsk --permission-prompts none \
  --strict-mcp-config --disable-slash-commands \
  --session-id <stable uuid> \
  --output-format json --json-schema <abs>/tools/headless/schemas/design-verdict.json \
  --max-budget-usd <cap, set by F12> "<first question>"

# every question after that: a separate process, same id, warm context, same boundary flags
claude -p --resume <stable uuid> \
  --restricted --tools "Read,Grep,Glob" \
  --settings <abs>/tools/headless/readonly.settings.json \
  --permission-mode dontAsk --permission-prompts none \
  --strict-mcp-config --disable-slash-commands \
  --output-format json --json-schema <abs>/tools/headless/schemas/design-verdict.json \
  --max-budget-usd <cap, set by F12> "<next question>"
```

Why each layer is there. Without `--strict-mcp-config` and `--restricted`, a headless resume would
load the user, project and local settings allowlists and every configured MCP server, including
write-capable connectors (mail, drive, store, accounting). Prose saying "don't" is an instruction,
not a boundary. With these flags, an unattended Fable call can read files in its working directory
and nothing else. The flags are per process, not per session, so they must be passed on **every**
call. F12's `Ask-Fable` must **enforce** them, refusing to run if any is missing, not merely default
them. The resume pair above was probed with Haiku standing in (§2): context carried and the tool
surface was `Glob`, `Grep`, `Read` only.

**Always the same `--session-id`; never `--no-session-persistence`** (it disables the resume that
*is* the continuity). Add `--fork-session` for a speculative question so a discarded line of
thinking never enters the record. The Sonnet seat calls this only through F12's `Ask-Fable`, never
by typing the flags. The owner working in the seat directly does not need the wrapper.

**One session, two callers: what does and does not carry across.** The owner's interactive turns
and the Sonnet seat's unattended resumes share one context. Two kinds of carry-over matter:

- **Permissions.** An "always allow" the owner grants interactively is saved to a settings file,
  not to the session. An unattended call under `--restricted` ignores user, project and local
  settings files, so none of those grants reach it. Only `--settings readonly.settings.json` and
  managed settings apply (per `claude --help`, 2.1.278).
- **Content.** Anything that entered the context in an interactive turn is in the context of the
  next unattended turn. That includes untrusted text: a pasted issue, a fetched page, a diff. Nothing
  removes it. Three things contain it. The unattended surface has no write, exec, web or MCP tool,
  so an injected instruction has nothing to act with. Every answer is schema-shaped and treated as a
  claim the seat re-verifies against live state (§3 rule 1). And a question whose answer would
  authorise anything irreversible is never asked of the continuity seat at all: it goes to a row-1
  callee or an owner card.

F9 must restate both points in the callee standard. F12 must include a regression check that an
unattended resume has no tool beyond `Read`, `Grep` and `Glob`.

**Operations must not depend on it** (§3): if this session is gone, the round still runs off the
durable record. A wrapper that blocks a lane because the continuity seat is unreachable has
inverted the rule.

Three invariants for every line above:

1. **Subscription token only** (`CLAUDE_CODE_OAUTH_TOKEN`), never a metered API key
   (`orchestrator_role.md` cost rule). **`--bare` is forbidden fleet-wide**: it forces
   `ANTHROPIC_API_KEY`/`apiKeyHelper` auth and never reads OAuth, so it silently moves work onto
   metered billing. It also skips CLAUDE.md discovery and hooks.
2. **Hard timeout and `--max-budget-usd`.** They are two different mechanisms, and only one exists
   today. `--max-budget-usd` is an **in-process** CLI flag ("only works with --print", per
   `claude --help`). It caps spend only while the process is healthy enough to count. The standard's
   **hard timeout, enforced from outside the process**, is a wrapper-level wall-clock limit that kills
   the process. For subagents it exists: `tools/headless/Invoke-ReadOnlyAgent.ps1` on `origin/main`
   takes `-TimeoutSec` (default 300), kills the process when it runs over, and exits 3. The Fable seat
   and lane lines have no wrapper yet, so they have no outside kill. F12's `Ask-Fable` and
   `Invoke-Lane` must carry the same timeout-and-kill, and a wrapper without one does not ship. The
   `<cap>` placeholders above are also not values yet. F12 sets a
   concrete dollar figure per line from F3's measured envelopes, and a line with no concrete cap does
   not run. `maxTurns` is not enforced by anything either (§11). Whether enforcement gets its own
   F-task is on card `fable-maxturns-budget-enforcement-2026-09-22`.
3. **No self-scheduling capability, ever** — no `CronCreate`, no `send_later`, no `Agent` call
   reaching outside the rung's roster. `Agent(claude)` and `Agent(general-purpose)` are already in
   the deny-list; the 2026-09-16 self-scheduling incident in `docs/LESSONS.md` is why.

### Batching, and why it is the main cost lever

The ladder's L1 design is "each reporter on a Windows scheduled task." At `ephemeral_1h` cache TTL,
seven reporters on seven independent schedules each pay the cold preamble: ~7 × $0.051 = **~$0.36**
per sweep on Haiku, ~$0.71 on Sonnet. The same seven fired as one burst inside one hour pay
one cold + six warm: **~$0.067**. Over 24 hourly sweeps that is ~$8.60/day against ~$1.60/day — a
5× difference produced entirely by scheduling, before any model choice.

So the scheduler should be **one task that fires the whole reporter set in sequence**, not N tasks.
Two conditions make the cache actually hit, and both must be tested, not assumed:

- the prefix must be **byte-identical** across runs — same cwd, same `--settings`, same agent
  preamble. Anything varying (a timestamp, a rendered path) in the prefix silently invalidates it.
  `--system-prompt-snapshot on` (the default) records the prompt once per conversation; the
  cross-invocation case is what needs measuring.
- **verify with `usage.cache_read_input_tokens`** from the JSON envelope. Zero across repeated runs
  means a silent invalidator, and the field is right there in the report — this is measurable on
  day one, not a modelling exercise.

Prefix-shrinking levers, in the order they should be tried: `omitClaudeMd` on read-only agents
(`omitClaudeMd: true` is already on 49 of the 88, per anthropic-audit-11), `--disable-slash-commands`, `--restricted` (which also
drops settings-file loading), `--exclude-dynamic-system-prompt-sections`, `--setting-sources` to
name exactly which settings load.

---

## 6. Build plan

Format matches `docs/PHASE_6_PERSONAL_FINANCE_PLAN.md`: id, task, who / size / model / effort,
depends on. Sizes per `standards/sessions/task_sizing.md`. **Nothing below is dispatched.**

### Group A — make the lever real (no rung change, no scheduled run)

| ID | Task | Who / size / model / effort | After | Brief |
|---|---|---|---|---|
| F1a | Measure whether `--effort` changes Haiku behaviour or is silently dropped | agent / XS / Haiku+Sonnet / low | — | Two identical prompts at `low` and `max` on Haiku; compare `usage.output_tokens_details.thinking_tokens` from the JSON envelope. Report only. Settles row 7 above. |
| F1b | Probe whether an unpinned subagent actually inherits its caller's effort | agent / XS / Haiku / low | — | **REPORTED 2026-09-22 (CLI 2.1.278) — negative on both paths; the measurement is recorded in §1a.** `--agent`/`--agents` and a real `.claude/agents/*.md` frontmatter file spawned via the Task tool were both tested: session effort dominated in both directions, and the agent-level pin moved nothing observable. |
| F1 | **CONDEMNED — pending independent confirmation.** F1b (§1a) found no observable effect from an agent-level `effort:` pin, so this task buys nothing on current evidence. The owner approved cutting it *if* an independent cross-check confirms, and that cross-check was still running when this was written: do not dispatch it, and do not delete it until the confirmation lands. Original scope, kept for the record — pin `effort:` in every non-Haiku agent file; extend `roster_meta.json` with an `effort` field; make `generate_agents_md.py --check` fail on a missing pin and surface an Effort column in `docs/AGENTS.md` | agent / M / Sonnet / medium | F1a, F1b | One PR, `claude-agents/` + `tools/`. Advisors `low`, drafters `medium`, `live-reviewer` `high`. Mechanical: the judgment is already encoded in each file's existing model pin. `agents-roster-check.yml` gates it. |
| F2 | Add `-Restricted` to `Invoke-ReadOnlyAgent.ps1`, defaulting **on** for agents whose `roster_meta.json` `readonly` is `tools`; keep `readonly.settings.json` as layer 3; document the three-layer ordering in `headless_agent_permissions.md` | agent / M / Sonnet / medium | F1 | Follows `tools/README.md` testing-seam conventions. Must add a regression test proving a `--restricted` run has no Bash tool (the probe in §1a is the test case). **Opened as PR #174** (open, re-checked 2026-09-21) — implements D3 (default-on keyed off `readonly: "tools"`, fails closed on an unresolvable roster lookup); F2 in this table is satisfied pending #174's merge, not re-dispatched. |
| F3 | Capture the CLI's own JSON envelope as the L1 report: wrapper adds `checkedAt` (clock at write time, never typed) + the exact command, and writes `{envelope, checkedAt, command}` to the drop folder | agent / M / Sonnet / medium | F2 | Replaces the hand-rolled shape in `headless_readiness_ladder.md`. `permission_denials`, `total_cost_usd` and `usage` come from the CLI, not from the agent's own prose. |
| F12 | Seat-side wrappers so the seat never hand-assembles a flag line: one command per layer (`Ask-Fable`, `Invoke-Lane`, `Invoke-Subagent`), each taking 2-3 arguments and emitting the schema-checked envelope | agent / M / Sonnet / medium | F2, F4 | The §2 rule that a `low` seat must not compose ten-flag invocations. Must define the **cold-start path**: what happens when a pinned `--session-id` no longer resolves (expired, rebooted, never created). A seat at `low` will not improvise one, and a silently-cold resume costs ~$0.51 instead of ~$0.007 without failing. Must also, per §5: **enforce** the boundary flags on every call, refusing to run if one is missing; carry a wall-clock timeout-and-kill like `Invoke-ReadOnlyAgent.ps1`'s; set a concrete `--max-budget-usd` per line; return a Fable `stop_reason: "refusal"` to the seat as a refusal, never retried on another model; and include a regression check that an unattended resume has no tool beyond `Read`/`Grep`/`Glob`. |
| F13 | A `review-verdict` schema plus a card renderer: an Opus/Fable review returns verdict + findings (`file:line`, severity, one-line ask) + recommendation, and the seat files it as a scannable Decision Queue card rather than relaying prose | agent / M / Sonnet / medium | F4, F12 | The mobile-review requirement: the reviewable unit is the card, not the diff. Follows `decision_queue_standard.md` "Writing a card to be scanned" (summary on top, links in `points`). Must cap findings per card — a card needing a scroll to judge has failed its purpose. |
| F4 | One `--json-schema` per L1 reporter under `tools/headless/schemas/` | agent / M / Sonnet / low | F3 | Schema per agent, matching that agent's documented output section. Makes the L2 comparator's input machine-checkable instead of prose-parsed. |
| F14 | Publish the F-task tracker artifact (db capability, `items` + `meta/summary` per §2's tracker subsection) and backfill F1a/F1b as `done` | seat (interactive; not a headless agent) / XS / Sonnet / low | F1a, F1b | Same shape as the reference tracker at https://claude.ai/artifact/9ahVNbZjAT1tjrm8NCFXc5. The seat publishes it directly — `Artifact`/`ArtifactData` are seat-held tools, not something a `claude -p` agent can be handed (§2 mobile rule 2). Must exist before the first F-task after F1a/F1b is dispatched. Written by the Sonnet seat per owner instruction 2026-09-22, not by a headless agent. |

### Group B — schedule it (**this is the climb to L1, not a neutral build step**)

Group A and Groups C/D change how a run is invoked and reported without moving the fleet off L0.
Group B does not: **F5 registers the first-ever unattended scheduled run, which is the definition of
L1.** So F5 is not dispatchable as ordinary lane work. It requires the ladder's own climbing
procedure — "one Decision Queue card per rung per repo class, filed by the PM, never self-declared
by the mechanism being evaluated", carrying the exit criterion's actual measurements literally.
This plan supplies the tooling for that climb and explicitly does not authorise it.

| ID | Task | Who / size / model / effort | After | Brief |
|---|---|---|---|---|
| F5 | One scheduled task firing the whole L1 reporter set in sequence inside one hour, not N tasks | agent / M / Sonnet / medium | F4 | Registration is an **owner click-file** (`skills/owner-click`, `click-file-builder`): typed-YES gate, `-WhatIf`, same-folder `zz-UNDO`. Follows `AEGIS-Register-PmHeartbeat-Watchdog.cmd`'s shape exactly. |
| F6 | Prefix-stability measurement: 10 consecutive batched runs, assert `cache_read_input_tokens > 0` on runs 2-10; report any invalidator found | agent / S / Haiku / low | F5 | Pure measurement against the envelope. If it fails, the batching saving in §5 is not real and the scheduler design changes before anything else is built on it. |
| F7 | PM heartbeat ingest: read unread drop-folder files each tick, write Fleet Status `prs`/`health` with `writtenBy: "<pm session> from <report file>"`, archive the file | agent / M / Sonnet / medium | F3, F5 | Exactly as `headless_readiness_ladder.md` L1 already specifies. `claude -p` cannot hold `ArtifactData` — the PM writes, the reporter files. Unchanged by this plan. |
| F8 | Wire `total_cost_usd`/`usage` from the drop folder into `tools/cost-monitor` as a headless ledger source | agent / M / Sonnet / medium | F3, PR #159 merged | Blocked on #159. Also carries the §1b finding that the 1h cache-write multiplier measured at 2×, resolving that file's ASSUMED range. |

### Group C — the Fable seat (owner-gated)

| ID | Task | Who / size / model / effort | After | Brief |
|---|---|---|---|---|
| F9 | Draft `standards/sessions/fable_seat.md`: the continuity contract — memory is a claim not evidence, cache over a durable record, fork for speculation; plus what it may produce, never-builds and never-merges, `--fallback-model`, refusal handling, the resume contract, the retirement/cold-reopen trigger, and a position on `--autocompact` | agent / M / Sonnet / medium | F12 | **Route C** (`merge_authority.md`): `standards/sessions/*` is owner-merge. A session drafts it; the owner merges it. The drafter must not also be its reviewer. |
| F10 | Correct `orchestrator_role.md`'s "Effort for background workers can't be set per call" to distinguish the `Agent` tool (model only) from `claude -p` (`--effort`), and add the row-0 Fable line to the model/effort table | agent / S / Sonnet / low | F1a | **Route C**, owner-merge. Smallest possible edit; it is a factual correction plus one row, not a rewrite. **Opened as PR #172** (open, re-checked 2026-09-21) — F10 in this table is satisfied pending owner merge, not re-dispatched. Row 1 stays Opus (D2); #172 does not touch it. |
| F11 | Decision Queue card: authorise the Fable seat, naming its cost envelope from F8's real numbers | PM / XS / — / — | F8, F9 | One card, `decision_queue_standard.md` shape, options + recommendedOption + rationale, never filed resolved. Not filed until its parent (F8) is real — per the standing rule that cards depend on their entry gate. **WAIT — owner instruction 2026-09-22: do not file until told, independent of F8/F9 clearing.** |

### Group D — the rungs above L1 (unchanged by this plan, listed so nothing is assumed done)

L2 comparator, L3 drafter PRs and L4's UNENFORCED=0 gate stay exactly as
`headless_readiness_ladder.md` specifies. This plan changes **how** an L1 run is invoked and
reported, not what any rung permits. Every "Never" in that file still holds, including: no headless
session merges anything; nothing above L0 holds a self-scheduling tool; no drafter touches
`standards/sessions/*`, `policies/*`, or a CLAUDE.md-feeding doc.

### Critical path

`F1a + F1b → F1 → F2 → F3 → F4 → F5 → F6`, then L1's own 7-day exit criterion. F1a and F1b run
first and in parallel; they are the two gate-exempt measurements.
Parallel: F10 (doc correction, no dependency on the tooling); F12 after F2+F4, and F9 after F12
because the callee standard should describe a contract that exists; F7 after F3+F5; F8 after #159
merges. **F12 is on the critical path for anything the seat operates**, even though it is not on
the L1 path: without it a Sonnet 5 / low seat is hand-assembling the §5 invocations.
F6 is a **gate, not a step**: if the prefix does not cache across invocations, F5's design is wrong
and Group B is re-planned before F7 starts.

Write-lane cap ~6 (`orchestrator_role.md`, "Cost rule"; note `pm_role.md` and
`docs/PHASE_6_PERSONAL_FINANCE_PLAN.md` both attribute this to `session_plan_standard.md` rule 9,
which is actually "Work in a worktree, never the shared checkout" — the pre-existing miscitation is
not repeated here and is not this plan's to fix); realistically 2–3 at a time here because
F1–F4 all touch `tools/headless/` and `claude-agents/`.

---

## 7. Entry gate

**Exempt: F1a and F1b.** Both are read-only measurements that spawn nothing scheduled, write
nothing, and change no rung; they were dispatchable immediately and existed precisely to settle
questions this document could not. **Both have now reported (2026-09-22):** F1a in §4's row-7 note,
F1b in §1a. An earlier draft made the whole gate conditional on F1a having
reported while also barring every F-task until the gate passed, which deadlocked the critical path
at its first step.

**Every other F-task: do not dispatch until all of the following are true.**

1. ~~`headless_readiness_ladder.md` is **owner-merged**~~ — **Satisfied 2026-09-22.** PR #170
   merged the flip to IN FORCE (2026-09-22T00:52Z; confirmed on `origin/main`); PR #171 (root
   `.gitignore` for Python bytecode caches) also merged (2026-09-22T00:59Z), so the
   `.pyc`-contamination defect the drafting-pass handoff flagged against #170 cannot recur. L1 now
   has an authorised existence to register a scheduled run against, subject to the conditions below.
2. **Satisfied 2026-09-22 — F1a and F1b have both reported**, so row 7's effort question and the
   pin/inheritance claim in §1a are now settled by measurement rather than by this document. F1a
   was positive (effort reaches Haiku); F1b was negative on both paths, which does not unblock F1
   but condemns it, pending the independent cross-check named in §1a. This condition no longer
   gates the other F-tasks; F1 itself must not be dispatched while it is condemned.
3. The `readonly` classification in `roster_meta.json` is confirmed on `origin/main` — F2 keys its
   default off that field, and the ladder already records it as unconfirmed.
4. ~~PR #159 (cost-monitor) is merged, or F8 is explicitly deferred.~~ — **Satisfied 2026-09-22.**
   The owner explicitly deferred F8 (owner decision 2026-09-22, relayed; see §9's provenance note). PR #159 remains open/draft
   (re-checked 2026-09-21); this condition is met by the deferral, not by a merge. F8 itself stays
   blocked and undispatched until #159 lands or the owner re-authorizes it — deferring the *gate
   condition* is not the same as dispatching F8.
5. ~~The PM heartbeat watchdog is registered~~ — **Satisfied.** Owner card
   `action-register-pm-heartbeat-watchdog-2026-09-18` is `resolved` (`Done`, 2026-09-18T03:45Z,
   read directly from the Decision Queue store), and the Windows scheduled task
   `AEGIS-PmHeartbeat-Watchdog` exists and ticks every 15 minutes (checked 2026-09-21; its most
   recent tick exited 1, `PM-HEARTBEAT STALE`, which is the watchdog reporting on the PM's
   heartbeat, not the task being missing). F7 (heartbeat ingest) may be dispatched once its own
   dependencies (F3, F5) are met.

**Conditions 1, 2, 4 and 5 are now satisfied.** Condition 3 (the `readonly` classification
confirmed on `origin/main`) is not re-verified by this follow-up and stays as written. What else
blocks a given F-task is that task's own dependency column in §6, plus the owner WAITs in §9.

---

## 8. Risks

- **The batching saving may not be real.** Everything in §5 rests on a byte-identical prefix
  surviving across separate `claude -p` processes. Measured *within* one machine minutes apart, it
  held (4.3×). Across a scheduled task's environment it is untested. F6 exists to find out before
  anything depends on it, and the failure mode is visible (`cache_read_input_tokens == 0`), not
  silent.
- **`--restricted` is a new dependency on CLI behaviour.** It is verified on 2.1.278 today. A CLI
  upgrade that changes it would silently widen every L1 run. Mitigation: F2's regression test runs
  the probe and fails if Bash reappears — this is the `gate-execution-auditor` principle (check the
  tool's own output signature, not the job's conclusion) applied to our own boundary.
- **Pinning effort could make things worse, quietly.** An advisor pinned `low` that used to inherit
  `high` from its caller will produce shallower verdicts, and a verdict is exactly the artifact this
  estate has repeatedly mistaken for a fact (`fleet_structure.md`: "a subagent's output is a report,
  not a verdict"). Mitigation: pin effort in one PR, per §1a's existing model tiers, and treat the
  first week's advisor output as suspect — F1 should name the two or three advisors whose verdicts
  gate anything, and pin those `medium`, not `low`.
- **The seat is now the estate's weakest verifier, by design.** The ladder's founding constraint is
  that headless removes the peer who catches a confident error. §2 adds a second removal: the human
  who remains is running at `low`. Everything that used to be caught by a seat reading carefully now
  has to be caught by a schema, a wrapper's exit code, or a callee — which is why §2's rules 1-3 are
  requirements rather than preferences. If those three are not built, this plan makes the estate
  *less* safe than L0, not more.
- **A warm continuity seat is a stale continuity seat — and this is now the plan's largest risk,
  because continuity is the seat's job rather than a side effect.** A seat resumed across days
  carries whatever it concluded earlier, including anything since disproved, and it carries it
  fluently. The estate has already lost this exact bet once: `orchestrator_role.md:277`, a
  restart-backup signoff "carried as resolved across two handoffs before either one was true." A
  warm seat is that failure with a better memory and no diff for a reviewer to catch it in. The
  three rules in §3 (memory is a claim; cache over a durable record; fork for speculation) are the
  mitigation, and F9 must set the retirement trigger — the answer is not "never".
- **Compaction loses memory silently.** `--autocompact` (auto, or 100k-1M) keeps a long-running seat
  inside its window, but nothing tells the reader which parts of the history were summarised away.
  For a seat whose value *is* its history, that is a correctness problem, not a housekeeping one.
  Unmeasured here; F9 and F12 need a position on it, and rule 2 (durable record) is what makes a
  wrong answer survivable.
- **Headless removes the peer reviewer.** This is the ladder's own founding constraint and this plan
  does not weaken it. Be precise about what that means, because an earlier draft of this document
  overstated it: Groups A, C and D raise no rung — every one of their tasks lands as a reviewed PR
  while the fleet stays at L0. **Group B is the climb to L1 and is not exempt**, so it is gated on
  the ladder's climbing card rather than on this plan (see Group B's header). No task in any group
  authorises a rung change by itself.
- **A cold Fable call is the most expensive routine action in the estate.** ~$0.51 per spawn against
  ~$0.007 resumed — a ~70× spread that is invisible at the call site, because a cold resume succeeds
  and just costs more. The resume contract is a cost control, not a style preference; F12 owns
  making a cold-start loud, and F11's card should carry F8's measured numbers rather than these
  derived ones.
- **Fable refusals are HTTP 200.** A headless seat that does not check `stop_reason` reads a refusal
  as an empty answer and may report "nothing found." `--fallback-model opus` covers overload and
  unavailability only. A refusal is a reported stop, never retried on another model (§3). F12
  enforces that, and F9 states it in the callee standard.
- **Derived prices are not quoted prices.** The per-invocation table in §1b is arithmetic over a
  cached rate table plus one measured reconciliation. It is a what-if, not a bill — same caveat
  PR #159 puts on its own output.

---

## 9. Open decisions (each would be its own Decision Queue card; **none of items 1–6 filed**. Three cards were filed by the follow-up PR for questions it raised: see the end of §9)

1. **Is the Fable seat authorised at all**, and at what monthly envelope? (F11; recommend
   deciding after F8 can measure it.)
2. **Does row 1 stay Opus 5?** Fable's cached-input rate is half of Opus's, which makes a long
   read-heavy irreversibility review *cheaper* on Fable than on Opus. Recommend: **no change until
   measured** — run one row-1 review both ways on the same PR and compare findings and cost before
   touching `live-reviewer`.
3. **Does `--restricted` become the documented default** for every `readonly: tools` agent, i.e. is
   F2's default-on behaviour correct, or should it be opt-in per agent?
4. **Haiku effort**: once F1a reports, does `roster_meta.json` carry `effort: null` for Haiku agents
   (explicitly not applicable) or omit the field? Affects whether `--check` can require it.
5. **The click-file class cannot be run from a phone**, and **F5's own registration is a
   click-file**, so the step that reaches L1 is desk-bound. Options: accept that rung changes are
   desk-only; build a non-click-file registration path; or wait for the approval app (Phase 6 task
   2.28, unbuilt) and its passkey (2.30, owner card parked pending hardware keys). Recommend
   accepting desk-only for rung changes specifically — they are rare, deliberate, and already
   require an owner card — rather than building a second approval path for them.
6. **Where the drop folder lives.** The ladder specifies `%APPDATA%\AEGIS\reports\`, which is this
   PC only and puts every L1 report behind `needs-local-keys`-shaped locality. Worth asking whether
   it should be somewhere a second machine can read, given the owner's stated goal ("the sooner we
   get to headless automation, the less I will be creating sessions too").

**Recorded 2026-09-22: owner decisions, as relayed.**

> **Provenance.** Everything in this list reached the session that built it through its build
> brief. It did not come from a Decision Queue card or from the owner's own words in that session.
> On 2026-09-22 the `decisions` store was read directly and **no card records D2–D6, the F5/F11
> WAITs or the F8 deferral**. Under "Verify, don't trust", a relayed instruction is not yet the
> owner's decision. Read each item below as *relayed, pending the owner's own confirmation*, not as
> a resolved decision of record. None of them authorises anything: every item either keeps
> something as it is (D2, D5, D6, the WAITs) or describes work that has its own review (D3 in
> PR #174, D4 when a field exists). The owner confirms or corrects them when he reviews this
> route-C PR, or on a card if he prefers.

- **D2 (item 2, row-1 model).** **Row 1 stays Opus 5.** No change to `live-reviewer`. The
  cache-economics argument for Fable in §1b/§9-item-2 remains an argument, not a mandate; the
  owner closed the question without the comparison measurement this document recommended.
- **D3 (item 3, `--restricted` default).** **`--restricted` is ON BY DEFAULT for every agent whose
  `roster_meta.json` `readonly` is `"tools"`.** Built in PR #174 (open, re-checked 2026-09-21):
  adds `-Restricted` to `Invoke-ReadOnlyAgent.ps1`, default-on keyed off that field, failing closed
  if the roster lookup can't resolve. F2's brief in §6 is satisfied by #174 pending its merge.
- **D4 (item 4, Haiku effort field).** **Explicit `effort: null`** for Haiku agents, once the field
  exists — **not** omission. As of 2026-09-21 **no `effort` field exists** in any
  `claude-agents/*.md` frontmatter or in `roster_meta.json`, on `origin/main` or on PR #173's head
  (grep). D4 has nothing to apply to yet; it is a standing instruction for whenever F1 (or a
  successor task) adds the field, not a change made here, and no field is invented to satisfy it.
- **D5 (item 5, click-file desk-only).** **Rung changes stay desk-only.** No second, phone-capable
  approval path is built for the click-file class. F5's own registration remains a desk-only step
  by design, not an open gap.
- **D6 (item 6, drop-folder location).** **Reports stay on this PC** (`%APPDATA%\AEGIS\reports\`).
  No move to a network-reachable location. F3's drop-folder path should still be a parameter rather
  than hardcoded — D6 resolving to "stay local" fixes its default, it is not a reason to remove the
  seam.
- **F5 and F11 — WAIT.** Both stay undispatched by owner instruction 2026-09-22 (relayed),
  independent of their dependency columns clearing. F5 (register the batched scheduled run) and F11
  (the Decision Queue card authorizing the Fable seat) do not proceed until the owner says go.
  Whether this WAIT also covers the already-running, owner-approved `AEGIS-L1Pilot` (§1c) is on card
  `fable-l1-pilot-vs-f5-wait-2026-09-22`. Until he answers, the pilot is left as it is.
- **F8 — deferred.** Cross-reference for entry-gate condition 4: F8 itself is not dispatched; only
  the *entry-gate condition* that named it is satisfied by the deferral.
- **Unchanged:** the Fable seat never builds (§3). Nothing above gives it a write lane.

**Filed by the follow-up PR, open for the owner (Ops Decision Queue, `decisions` collection):**

- `fable-l1-pilot-vs-f5-wait-2026-09-22`: does the relayed F5 WAIT also pause the running,
  owner-approved L1 pilot (§1c)?
- `fable-batched-review-rider-2026-09-22`: should the one-reviewer-per-round rider (§11) stay a
  proposal, be adopted for non-row-1 reviews, or be dropped?
- `fable-maxturns-budget-enforcement-2026-09-22`: should enforcing the `maxTurns` and budget caps
  (§5 invariant 2, §11) get its own F-task?

---

## 10. Gaps in this document (not done unless documented)

- **Verified**: `claude --help` on 2.1.278; the installed `cli.js` agent-config parser; four probe
  runs (restricted/no-Bash, json-schema, cold cache, warm cache) with their JSON envelopes read;
  effort/model/maxTurns pin counts across all 88 agent files in this checkout; the contents of
  `tools/headless/`, `claude-agents/roster_meta.json`, `.github/workflows/*`, and the
  `standards/sessions/` files cited. Every quotation from a `standards/` file was independently
  re-checked against that file by a separate read-only pass, as were the pin counts, the flag list
  and the arithmetic. That pass found one error, since corrected: the model-pin count (see the
  correction note in the PR body).
- **Headless resume carries context and serves it warm**: a `-p --session-id <uuid>` call followed
  by a `-p --resume <uuid>` call in a **separate process** returned the earlier codeword correctly,
  with `cache_read_input_tokens` 28,870 against `cache_creation_input_tokens` 136. Measured with
  Haiku standing in for a Fable seat. **Not** verified: that a pinned session id survives a
  reboot, how long it survives at all, or what a resume against an expired id does (F12).
- **`--model fable` exists**: `claude --help` gives `'fable'` as an alias for "the latest model",
  with `'claude-fable-5'` as its full-name example. **Not** verified: which concrete model id the
  alias resolves to today. This document writes `claude-fable-5-1` from the bundled API reference;
  a caller should pin the full id rather than the alias if the distinction matters.
- **Not verified**: anything on `origin/main` newer than this checkout (HEAD, `origin/main` and
  the branch are all `3ca73d0` as fetched at session start; not re-fetched since); any live host, scheduled task, or the owner's machine; whether
  `--effort` is honoured by Haiku (F1a); whether Fable's *cache-write* multiplier is standard;
  current published prices (the rate table is cached, and `ops-policies` `routing/models.yaml` was
  not read — it is not in this repo); **`tools/cost-monitor/config.json`, which is likewise not in
  this checkout** — every statement about its contents is a read of PR #159's description, not of
  the file; **whether an unpinned subagent inherits its caller's effort** (inferred in §1a, probed
  by F1b); whether the prefix caches across separate scheduled invocations (F6).
- **Re-verified by the follow-up PR (2026-09-21), superseding parts of the bullet above**: live
  state of PRs #159, #170-#174 (`gh pr view`); the ladder's IN FORCE status on `origin/main`; the
  watchdog card read directly from the Decision Queue store; the Windows scheduled tasks
  `AEGIS-PmHeartbeat-Watchdog` and `AEGIS-L1Pilot` on the owner's PC (`Get-ScheduledTask`); the
  absence of any `effort` field on `origin/main` and PR #173's head; and one live
  `claude -p --model haiku --output-format json` run (§11). In the review-fix round (2026-09-22) it
  also re-verified: the two L1 pilot cards, read directly from the Decision Queue store; the
  `AEGIS-L1Pilot` task state again; `Invoke-ReadOnlyAgent.ps1`'s `-TimeoutSec` kill on `origin/main`;
  the `--fallback-model`, `--restricted` and `--setting-sources` help text on 2.1.278; and four Haiku
  probes of the §5 boundary flags (row-7 allow, deny and auto-allow, and a restricted session-id and
  resume pair).
- **Deliberately absent**: any code, any edit to a standard, any dispatch, any date commitment, any
  dollar figure presented as a bill. The original plan filed no Decision Queue card. The follow-up PR
  filed three, for questions it raised itself (listed at the end of §9), and resolved none.
- The per-invocation cost table is arithmetic from a 25K-token preamble measured on **one** agent
  shape. A heavier agent (more tools, a longer definition, CLAUDE.md loaded) has a larger preamble
  and a proportionally larger floor.

---

## 11. API cost practice — gap check (owner requirement 2026-09-22)

**Owner requirement, 2026-09-22:** *"Build this as if we were following API best practices and
prices, but run it through the Claude Code subscription."* In practice: this estate is designed and
measured as though it paid Anthropic API list prices, even though every call is billed against the
subscription. Checked against the practices below; findings, and drafted text for what this plan did
not yet cover. The drafted riders are stated here as plan text; none of them has its own F-task
number yet. The two that need an owner call are on Decision Queue cards
`fable-batched-review-rider-2026-09-22` and `fable-maxturns-budget-enforcement-2026-09-22`.

### Model routing by task, cheapest-that-passes with escalation — COVERED

§4's table (rows 0–8) already picks the cheapest model/effort per task shape, and the carry-over
rule ("upgrade one row when the task is live-adjacent with no rollback, or when an earlier run in
the same lane failed; never start high 'to be safe'") is escalation-on-failure. No gap.

### Prompt caching discipline — COVERED

§1b (cache read/write measurements), §2 (resume mechanics: pinned `--session-id` + `--resume`
keeps context warm across separate processes), and §5 ("Batching, and why it is the main cost
lever" — byte-identical prefix requirement, `usage.cache_read_input_tokens` as the verification
field) already state stable-prefix discipline and long-lived-session reuse. The exact field names
the CLI reports are listed under the cost-ledger heading below.

### Batching: group similar tasks per run — PARTIALLY COVERED; one gap

§5 covers batching subagent sweeps into one hourly burst (reporters). It does **not** cover
batching PR review — "one reviewer per round of PRs" is not stated anywhere in this document.
Drafted rider for §5. It is **a proposal, not in force**, and not owner-approved. Its status is on
card `fable-batched-review-rider-2026-09-22`:

> **The same argument applies to non-row-1 review, not only to sweeps.** A round that opens several
> PRs and reviews each with its own `diff-reviewer` invocation pays the cold preamble once per PR,
> exactly as N independent reporter schedules did in the measurement above. Where a round's PRs are
> reviewable together (same repo, same round, no intervening merge that would change what a later
> PR's diff means), one reviewer invocation *may* process the batch in sequence within a single
> warm session, with **a separate verdict per PR**.
>
> **Row 1 is excluded.** `live-reviewer` is interactive-only per its own file (§4), and every row-1
> PR gets its own fresh session. Sharing one context across irreversibility reviews would let
> content from one PR's diff, including injected instructions, influence the review of the next.
> That is not an acceptable trade on the path where mistakes cannot be undone. The same
> cross-PR influence is a real cost for non-row-1 batches too. That is why this stays a proposal
> until its own F-task measures both the saving and the effect on findings.

### Structured outputs via `--json-schema` — COVERED

F4 (Group A) and §5's invocation contract already require `--json-schema` on every subagent and
Fable-seat call. No gap.

### Hard per-run budgets (`--max-budget-usd`, `maxTurns`) — PARTIALLY COVERED; one gap

`--max-budget-usd` is on every invocation line in §5. `maxTurns` is *measured* (86 of 88 agent files
pin it, per §1a) but this plan never turns that into a forward-looking rule for new or edited agent
files. Drafted rider for §6 (independent of F1's condemned `effort:` scope):

> **Independent of F1's condemned `effort:` pin, every new or edited agent file must pin
> `maxTurns`, and every §5 invocation line must carry `--max-budget-usd`.** These are not part of
> what F1b measured null on — F1b tested `effort`, not `maxTurns` or budget caps — and nothing in
> this document's findings bears on whether a turn/budget ceiling is effective.

**Enforcement does not exist today.** Checked 2026-09-21: `tools/generate_agents_md.py --check`
verifies each agent's Model cell (and Role/Headless) against the agent files and
`roster_meta.json`; **nothing under `tools/` or `.github/` checks `maxTurns`** (grep on
`origin/main`). An earlier draft of this section said `--check` already gated `maxTurns` presence;
that was wrong. Making the rule enforced rather than stated would need `--check` (or
`check_agent_sync.py`) extended — a task that has no F-number yet.

### Cost ledger in API-equivalent dollars, from `claude -p --output-format json` — PARTIALLY COVERED; central gap closed here

**This is the owner's central requirement and this plan's biggest blind spot.** F3/F4/F8 read
`total_cost_usd`/`usage` (§1a finding 4) but the plan never stated — and the drafting session had
not verified — that these fields are **already reported at API list-price parity while the call is
billed against the subscription**. Measured twice on CLI 2.1.278 (2026-09-21, by the drafting pass
with `--model claude-haiku-4-5-20251001`, and again when this section was built, with `--model
haiku`):

```
claude -p "reply ok" --output-format json --model haiku
```

Fields returned by the build-time run (the global CLAUDE.md was loaded, so token counts are not
directly comparable to §1b's clean-probe baseline — the same "the system prompt is the cost" effect,
not a contradiction of it):

```
total_cost_usd: 0.0738042
usage.cache_creation: { ephemeral_1h_input_tokens: 35331, ephemeral_5m_input_tokens: 0 }
usage.service_tier: "standard"
modelUsage: { "claude-haiku-4-5-20251001": {
    inputTokens: 10, outputTokens: 272, cacheReadInputTokens: 17722, cacheCreationInputTokens: 35331,
    costUSD: 0.0738042, canonicalModel: "claude-haiku-4-5", provider: "firstParty",
    costBasis: "list" } }
```

(The drafting pass's run returned the same shape: `total_cost_usd` 0.0763682, `costBasis: "list"`,
`output_tokens_details.thinking_tokens` 186.)

**`modelUsage[*].costBasis: "list"` is the load-bearing field.** The CLI already reports the
API-list-price-equivalent dollar figure for every subscription-billed run, unprompted — the owner's
"as if API prices, run on the subscription" requirement, at no cost to adopt: no new
instrumentation, just reading a field that already exists. Drafted rider for F3/F4/F8's briefs. It
is **stated here, not yet copied into the §6 rows**, following the drafted patch, which placed it only
in this section. It joins each brief when that task is next dispatched:

> F3's drop-folder envelope and F8's cost-monitor ledger must read `total_cost_usd` and assert
> `modelUsage[*].costBasis == "list"` on every entry (not merely read `costUSD`), so a future CLI
> change that stops reporting list-equivalent pricing — e.g. a `"subscription"` or `"included"`
> basis — is caught as a finding rather than silently changing what the ledger means. This is a
> one-line assertion, not new machinery, and needs no dependency beyond what F3/F4 already have.

### Current API list prices — recorded, source and date logged

Read by the drafting pass from `https://claude.com/pricing` (redirected from
`https://www.anthropic.com/pricing`) on **2026-09-21**, through a fetch tool that summarises the
page; not re-read when this section was built. Per MTok: Fable 5.1 input $10 / output $50 /
cache-read $0.25 / cache-write (5-min TTL) $12.50; Opus 5 $5 / $25 / $0.50 / $6.25; Sonnet 5 $2 /
$10 / $0.20 / $2.50; Haiku 4.5 $1 / $5 / $0.10 / $1.25. Batch API: "save 50% with batch
processing." This matches §1b's cached table and explains its "2×, not 1.25×" cache-write finding:
**1.25× is the 5-minute-TTL write price; the plan's probes wrote `ephemeral_1h` (confirmed again in
the build-time run above), whose write price is the separately documented 2× rate** — a TTL-choice
fact, not an anomaly. PR #159 should cite the price page directly rather than only its own
description. The page also carried an interpretive line ("cache write is 50× the read price") that
does not match its own figures (12.5× for Sonnet); only the raw figures are used here.

### Idle-cost rules (no always-on idle sessions; poll only as often as the thing changes) — PARTIAL

§5's batching argument reduces *scheduled* idle cost (one burst instead of N schedules) but states
no rule for (a) the Fable continuity seat's own idle cost between rounds, or (b) justifying a
reporter's polling interval against how often what it reports actually changes.
`standards/sessions/orchestrator_role.md:31` already states the parent rule ("**No token-burning
loops.** Don't poll long-running work; wait for notifications.") that this plan should inherit.
Drafted rider for §3 and for F5/F6's briefs:

> **The Fable seat holds no scheduled or cron trigger of its own.** It is opened only by the owner
> or by the Sonnet seat's own dispatch, never a timer — an idle warm session nobody is querying is a
> straight cost with no offsetting value, list-price-equivalent per the ledger above. **Every L1
> reporter's schedule interval must be justified against how often the thing it reports on actually
> changes**, not fixed at "hourly" by convention — a PR/CI sweep on a fixed cadence for a repo with
> no open PRs that day is waste. F5's brief must state each reporter's interval's justification, not
> only its batching shape.

No interval is chosen here: there is no data yet on how often any reporter's underlying state
changes, and F5 is on owner WAIT (§9).

### Tie to F8 (deferred) — what can land without it

F8 (wiring `total_cost_usd`/`usage` into `tools/cost-monitor`) is owner-deferred (§9). None of the
above needs F8:

- The `costBasis` reading discipline needs no new metering — F3/F4 (Group A, undeferred) can adopt
  the one-line assertion directly.
- The price table and the caching/batching/idle-cost text above are documentation.
- The one-reviewer-per-round batching proposal (row 1 excluded) is a dispatch-pattern question for
  the seat, not a metering feature.
- The interval-justification rule can be *required* of F5/F6's briefs now; *proving* an interval
  saves money against a real bill is F8's job and stays deferred with it.

What genuinely waits on F8: any graphed/alerted ledger, and reconciling this document's derived
dollar figures against an actual invoice.
