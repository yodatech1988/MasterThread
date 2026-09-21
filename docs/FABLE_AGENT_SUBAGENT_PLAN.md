# Fable → Agent → Subagent: how the three layers should be built headless

Status: **DRAFT for owner review, 2026-09-21.** Plan only. Nothing here is built, no lane is
dispatched, no standard is edited, no Decision Queue card is filed. Every task below is written to
be handed to a worker; **the Fable seat writes this plan and does not build it.**

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
| pinning `model:` | 86 (37 haiku, 48 sonnet, 1 opus) |
| pinning `maxTurns:` | 86 |
| **pinning `effort:`** | **0** |

So today the estate pins the cheap half of the cost lever and lets the expensive half float: every
subagent inherits whatever effort its caller happens to be running at. A Haiku reporter summoned
from an `xhigh` seat thinks at `xhigh`. This is the single largest correctable gap in the roster,
and it is a file edit, not new machinery.

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
$0.0531 reported); at 1.25× it would be ~$0.033. `tools/cost-monitor/config.json` carries the
cache-write multiplier as **ASSUMED**, a 1.25×–2× range, and PR #159 says alerts use the high end.
This measurement says the high end is not a safety margin for headless runs — it is the actual
rate. That is a finding for PR #159, not a change this plan makes.

**Derived per-invocation floor by model** (25K-token preamble, cold, 1h TTL at 2× input):

| Model | input $/MTok | output $/MTok | cache read $/MTok | cold preamble cost | warm preamble cost |
|---|---|---|---|---|---|
| Haiku 4.5 | 1 | 5 | 0.10 | ~$0.051 | ~$0.0026 |
| Sonnet 5 | 2 | 10 | 0.20 | ~$0.102 | ~$0.0051 |
| Opus 5 | 5 | 25 | 0.50 | ~$0.255 | ~$0.0128 |
| **Fable 5.1** | **10** | **50** | **0.25** | **~$0.509** | **~$0.0064** |

Rates from the bundled Claude API reference, cross-checked against the Fable
`cache_read_factor_override` (0.025) that `ops-policies` `routing/models.yaml` already carries per
PR #159. Fable's cache-write multiplier is **not** separately documented and is assumed standard —
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
| `tools/pm-heartbeat/` | Built (PR #108); watchdog task **not registered** |
| `tools/cost-monitor/` | PR #159 **open, draft** |
| `standards/sessions/headless_readiness_ladder.md` | **Proposed**, not owner-merged; fleet at **L0** |
| `skills/round-start`, `dispatch-lane`, `land-pr`, `round-closeout`, `owner-click` | Built |
| Decision Queue, Fleet Status, `merge_authority.md` routes A/B/C | Built |

Not built, per the ladder's own build-state table: any scheduled L1 run, the per-agent
`--allowedTools` overlay, the reports drop folder and PM ingest, the L2 comparator, the L4
UNENFORCED=0 gate.

---

## 2. The three layers

**Fable is not a new tier.** The estate already has T0 owner → T1 program PM → T2 round
orchestrator → T3 lane lead → T4 task subagent → T5 deterministic script
(`orchestrator_role.md`, `docs/AGENTS.md`). Adding a "Fable tier" would add a relay hop, and
`fleet_structure.md` is explicit that a layer which only forwards is not earning its place. Fable is
a **model assignment available to an existing seat**, and the most expensive one in the estate.

| Layer | What it is | Seat | Model | Effort | Headless shape |
|---|---|---|---|---|---|
| **Fable** | The round's *designer*: turns a negotiated ask into a fixed executable workload, settles a design call, does a hard three-way merge | T1/T2 (PM or round orchestrator), **one at a time** | `claude-fable-5-1` | `high`, `xhigh` on a failed retry | **One long-lived session, resumed** (`--session-id` / `--resume`), never a per-task spawn |
| **Agent** | The lane worker: one repo, one worktree, one branch, one PR | T3 | `claude-sonnet-5` (Opus 5 for row 1) | `medium` (`high` for invariant-heavy edits) | `claude -p` per lane, own worktree |
| **Subagent** | The roster agent: a report or a verdict, no worktree, no PR | T4 | pinned in frontmatter (haiku / sonnet / opus) | **pinned in frontmatter** (task F1) | `claude -p --agent <name> --restricted`, batched |

### The two jobs Fable must not take

1. **It never builds.** No worktree, no branch, no PR authored by the Fable seat. Its outputs are a
   dispatch plan, a design verdict, or a resolved merge conflict. Everything that produces lines of
   code or documentation is a Sonnet lane. Cost says so (2× Opus on output); `orchestrator_role.md`
   already says so of the orchestrator generally ("It doesn't do the implementation itself").
2. **It never holds merge authority headless.** `merge_authority.md` principle 3 and the ladder's
   L4 row: route A stays a CI job, routes B and C stay a session or the owner. A Fable seat running
   unattended is still a headless session.

### Why one resumed session, not per-task spawns

At ~$0.51 of cold preamble per invocation, N Fable spawns cost N × $0.51 before work. One resumed
session pays it once and then reads its own context at $0.25/MTok — the cheapest cached-input rate
of any model above Sonnet. This is the only layer where "resume, don't respawn" is worth the
session-persistence complexity; Haiku subagents at $0.0026 warm should stay stateless.

Two Fable-specific API behaviours the seat must handle (both from the Claude API reference, neither
currently anywhere in `standards/`):

- **`stop_reason: "refusal"`** — a safety classifier can decline at HTTP 200. A headless seat that
  reads `content` without checking the stop reason will treat a refusal as an empty answer. The CLI
  exposes `--fallback-model <model>` (comma-separated, retries the primary at the start of each
  user turn) — the Fable seat should run with `--fallback-model opus`.
- **Thinking is always on and its raw chain is never returned**; `budget_tokens` is rejected with a
  400. Depth is controlled *only* by `--effort`. Forced tool choice is also rejected. None of this
  bites the CLI path today, but it constrains any future direct-API caller.

---

## 3. Model and effort for every task

Supersedes nothing until merged; written to slot into `orchestrator_role.md`'s existing
"Assigning model and effort to each task" table, which stays the first-row-that-matches rule.

| # | Task shape | Model | Effort | Layer | Headless form |
|---|---|---|---|---|---|
| 0 | Turning a still-negotiated ask into a fixed workload; a design call the round cannot settle; a three-way merge after two sessions already collided | **Fable 5.1** | `high` (`xhigh` on a failed retry) | Fable | one resumed session, `--fallback-model opus` |
| 1 | Touches live production, credentials/secrets, money, or the death/damage path; or sets a contract other sessions build on | **Opus 5** | `high` (`xhigh` on a failed retry) | Agent / Subagent (`live-reviewer`) | interactive only for `live-reviewer`, per its own file |
| 2 | Large multi-file data edit where invariants matter; cross-mod classname sweep | **Sonnet 5** | `high` | Agent | `claude -p`, own worktree |
| 3 | Normal plan session with a clear Read / Do / Done-when | **Sonnet 5** | `medium` | Agent | `claude -p`, own worktree |
| 4 | Doc-only work: status-table fixes, ledger refresh, handoff notes, small config edits with a validator | **Sonnet 5** | `low` | Agent | `claude -p`, own worktree |
| 5 | An **advisor**: renders a verdict against a named standard, no action, Read/Grep only | **Sonnet 5** or Haiku per its file | `low` | Subagent | `--restricted --agent <name>`, batched |
| 6 | A **drafter**: produces content in a standard's format, never places it | **Sonnet 5** | `medium` | Subagent | `--restricted --agent <name>`, batched |
| 7 | Mechanical read-only sweep: PR/CI state, worktrees, grep inventories, fixed-rule cleanup | **Haiku 4.5** | *(see note)* | Subagent | `--agent <name> --tools "Bash,Grep" --allowedTools <read verbs>`, batched |
| 8 | Anything with a deterministic answer | **no model** | — | T5 | a script; `generate_agents_md.py --check` is the pattern |

Rules that carry over unchanged: **pick the first row that matches**; downgrade when the plan has
already done the hard thinking; upgrade one row when the task is live-adjacent with no rollback, or
when an earlier run in the same lane failed; never start high "to be safe"
(`orchestrator_role.md`, cost rule). Priority (P0–P3) and model/effort stay independent axes
(`priority_classification.md`).

**Note on row 7 (Haiku + effort).** The Claude API reference states `effort` errors on Haiku 4.5.
A probe of `claude -p --model haiku --effort low` **exited 0 and produced correct output**, so the
CLI does not fail — but that does not prove the effort was applied rather than dropped. Until
measured (task F1a), **do not pin `effort:` on a Haiku agent**; pin it on the Sonnet and Opus ones,
where it is documented to work.

**Row 1 vs row 0 is deliberately left alone.** On the cache-read economics above, Fable is cheaper
on input than Opus for a long read-heavy review, which is what row 1's `live-reviewer` is. That is
an argument, not evidence: `live-reviewer` is built, proven, pinned `opus`, and marked interactive-
only. Changing the model on the estate's irreversibility reviewer is an owner decision that should
follow a measurement, not precede one — see §6 open decision 2.

---

## 4. The headless invocation contract

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
  --max-budget-usd <small>
```

**Subagent needing read-only `gh`/`git` (row 7):**

```
claude -p --agent <name> --tools "Bash,Grep,Read" \
  --allowedTools "Bash(gh pr list:*)" "Bash(gh pr view:*)" "Bash(git ls-remote:*)" ... \
  --settings <abs>/tools/headless/readonly.settings.json \
  --permission-mode dontAsk --permission-prompts none \
  --strict-mcp-config --disable-slash-commands \
  --output-format json --json-schema <abs>/tools/headless/schemas/<name>.json \
  --max-budget-usd <small>
```

`--restricted` is omitted here only because the agent genuinely needs `Bash`; the `--allowedTools`
allow-list is then the real boundary, exactly as the standard already says, with the deny-list
behind it.

**Fable seat:**

```
claude --model fable --effort high --fallback-model opus \
  --session-id <stable uuid>   # then --resume <same> on every later turn
```

Never `-p` per task. Never with a write-capable permission mode while unattended.

Three invariants for every line above:

1. **Subscription token only** (`CLAUDE_CODE_OAUTH_TOKEN`), never a metered API key
   (`orchestrator_role.md` cost rule). **`--bare` is forbidden fleet-wide**: it forces
   `ANTHROPIC_API_KEY`/`apiKeyHelper` auth and never reads OAuth, so it silently moves work onto
   metered billing. It also skips CLAUDE.md discovery and hooks.
2. **Hard timeout and `--max-budget-usd`**, enforced from outside the process, per the standard.
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

## 5. Build plan

Format matches `docs/PHASE_6_PERSONAL_FINANCE_PLAN.md`: id, task, who / size / model / effort,
depends on. Sizes per `standards/sessions/task_sizing.md`. **Nothing below is dispatched.**

### Group A — make the lever real (no rung change, no scheduled run)

| ID | Task | Who / size / model / effort | After | Brief |
|---|---|---|---|---|
| F1a | Measure whether `--effort` changes Haiku behaviour or is silently dropped | agent / XS / Haiku+Sonnet / low | — | Two identical prompts at `low` and `max` on Haiku; compare `usage.output_tokens_details.thinking_tokens` from the JSON envelope. Report only. Settles row 7 above. |
| F1 | Pin `effort:` in every non-Haiku agent file; extend `roster_meta.json` with an `effort` field; make `generate_agents_md.py --check` fail on a missing pin and surface an Effort column in `docs/AGENTS.md` | agent / M / Sonnet / medium | F1a | One PR, `claude-agents/` + `tools/`. Advisors `low`, drafters `medium`, `live-reviewer` `high`. Mechanical: the judgment is already encoded in each file's existing model pin. `agents-roster-check.yml` gates it. |
| F2 | Add `-Restricted` to `Invoke-ReadOnlyAgent.ps1`, defaulting **on** for agents whose `roster_meta.json` `readonly` is `tools`; keep `readonly.settings.json` as layer 3; document the three-layer ordering in `headless_agent_permissions.md` | agent / M / Sonnet / medium | F1 | Follows `tools/README.md` testing-seam conventions. Must add a regression test proving a `--restricted` run has no Bash tool (the probe in §1a is the test case). |
| F3 | Capture the CLI's own JSON envelope as the L1 report: wrapper adds `checkedAt` (clock at write time, never typed) + the exact command, and writes `{envelope, checkedAt, command}` to the drop folder | agent / M / Sonnet / medium | F2 | Replaces the hand-rolled shape in `headless_readiness_ladder.md`. `permission_denials`, `total_cost_usd` and `usage` come from the CLI, not from the agent's own prose. |
| F4 | One `--json-schema` per L1 reporter under `tools/headless/schemas/` | agent / M / Sonnet / low | F3 | Schema per agent, matching that agent's documented output section. Makes the L2 comparator's input machine-checkable instead of prose-parsed. |

### Group B — schedule it (this is what reaches L1)

| ID | Task | Who / size / model / effort | After | Brief |
|---|---|---|---|---|
| F5 | One scheduled task firing the whole L1 reporter set in sequence inside one hour, not N tasks | agent / M / Sonnet / medium | F4 | Registration is an **owner click-file** (`skills/owner-click`, `click-file-builder`): typed-YES gate, `-WhatIf`, same-folder `zz-UNDO`. Follows `AEGIS-Register-PmHeartbeat-Watchdog.cmd`'s shape exactly. |
| F6 | Prefix-stability measurement: 10 consecutive batched runs, assert `cache_read_input_tokens > 0` on runs 2-10; report any invalidator found | agent / S / Haiku / low | F5 | Pure measurement against the envelope. If it fails, the batching saving in §4 is not real and the scheduler design changes before anything else is built on it. |
| F7 | PM heartbeat ingest: read unread drop-folder files each tick, write Fleet Status `prs`/`health` with `writtenBy: "<pm session> from <report file>"`, archive the file | agent / M / Sonnet / medium | F3, F5 | Exactly as `headless_readiness_ladder.md` L1 already specifies. `claude -p` cannot hold `ArtifactData` — the PM writes, the reporter files. Unchanged by this plan. |
| F8 | Wire `total_cost_usd`/`usage` from the drop folder into `tools/cost-monitor` as a headless ledger source | agent / M / Sonnet / medium | F3, PR #159 merged | Blocked on #159. Also carries the §1b finding that the 1h cache-write multiplier measured at 2×, resolving that file's ASSUMED range. |

### Group C — the Fable seat (owner-gated)

| ID | Task | Who / size / model / effort | After | Brief |
|---|---|---|---|---|
| F9 | Draft `standards/sessions/fable_seat.md`: when the seat is taken, what it may produce, the never-builds and never-merges rules, `--fallback-model`, refusal handling, and the one-resumed-session invocation | agent / M / Sonnet / medium | — | **Route C** (`merge_authority.md`): `standards/sessions/*` is owner-merge. A session drafts it; the owner merges it. The drafter must not also be its reviewer. |
| F10 | Correct `orchestrator_role.md`'s "Effort for background workers can't be set per call" to distinguish the `Agent` tool (model only) from `claude -p` (`--effort`), and add the row-0 Fable line to the model/effort table | agent / S / Sonnet / low | F1a | **Route C**, owner-merge. Smallest possible edit; it is a factual correction plus one row, not a rewrite. |
| F11 | Decision Queue card: authorise the Fable seat, naming its cost envelope from F8's real numbers | PM / XS / — / — | F8, F9 | One card, `decision_queue_standard.md` shape, options + recommendedOption + rationale, never filed resolved. Not filed until its parent (F8) is real — per the standing rule that cards depend on their entry gate. |

### Group D — the rungs above L1 (unchanged by this plan, listed so nothing is assumed done)

L2 comparator, L3 drafter PRs and L4's UNENFORCED=0 gate stay exactly as
`headless_readiness_ladder.md` specifies. This plan changes **how** an L1 run is invoked and
reported, not what any rung permits. Every "Never" in that file still holds, including: no headless
session merges anything; nothing above L0 holds a self-scheduling tool; no drafter touches
`standards/sessions/*`, `policies/*`, or a CLAUDE.md-feeding doc.

### Critical path

`F1a → F1 → F2 → F3 → F4 → F5 → F6`, then L1's own 7-day exit criterion.
Parallel: F9 and F10 (docs, no dependency on the tooling); F7 after F3+F5; F8 after #159 merges.
F6 is a **gate, not a step**: if the prefix does not cache across invocations, F5's design is wrong
and Group B is re-planned before F7 starts.

Write-lane cap ~6 (`session_plan_standard.md` rule 9); realistically 2–3 at a time here because
F1–F4 all touch `tools/headless/` and `claude-agents/`.

---

## 6. Entry gate — do not dispatch any F-task until all true

1. `headless_readiness_ladder.md` is **owner-merged** (it is currently *proposed*, route C). Until
   then L1 has no authorised existence and F5 would be registering a scheduled task against a
   standard the owner has not approved.
2. F1a has reported, so row 7's effort question is settled by measurement rather than by this doc.
3. The `readonly` classification in `roster_meta.json` is confirmed on `origin/main` — F2 keys its
   default off that field, and the ladder already records it as unconfirmed.
4. PR #159 (cost-monitor) is merged, or F8 is explicitly deferred. F8 is the only task that can
   price the fleet, and a cost plan whose meter is an open draft is a plan with no feedback loop.
5. The PM heartbeat watchdog is registered (owner card
   `action-register-pm-heartbeat-watchdog-2026-09-18`), since F7 ingests on the heartbeat tick.

---

## 7. Risks

- **The batching saving may not be real.** Everything in §4 rests on a byte-identical prefix
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
- **Headless removes the peer reviewer.** This is the ladder's own founding constraint and this plan
  does not weaken it: nothing here raises a rung, and every F-task lands as a reviewed PR at L0.
- **A Fable seat is the most expensive thing in the estate.** ~$0.51 cold per spawn. The one-resumed-
  session rule is a cost control, not a style preference, and F11's card should carry F8's measured
  numbers rather than these derived ones.
- **Fable refusals are HTTP 200.** A headless seat that does not check `stop_reason` reads a refusal
  as an empty answer and may report "nothing found." `--fallback-model opus` covers overload and
  unavailability; the refusal path needs F9 to say explicitly what the seat does.
- **Derived prices are not quoted prices.** The per-invocation table in §1b is arithmetic over a
  cached rate table plus one measured reconciliation. It is a what-if, not a bill — same caveat
  PR #159 puts on its own output.

---

## 8. Open decisions (each would be its own Decision Queue card; **none filed**)

1. **Is the Fable seat authorised at all**, and at what monthly envelope? (F11; recommend deciding
   after F8 can measure it.)
2. **Does row 1 stay Opus 5?** Fable's cached-input rate is half of Opus's, which makes a long
   read-heavy irreversibility review *cheaper* on Fable than on Opus. Recommend: **no change until
   measured** — run one row-1 review both ways on the same PR and compare findings and cost before
   touching `live-reviewer`.
3. **Does `--restricted` become the documented default** for every `readonly: tools` agent, i.e. is
   F2's default-on behaviour correct, or should it be opt-in per agent?
4. **Haiku effort**: once F1a reports, does `roster_meta.json` carry `effort: null` for Haiku agents
   (explicitly not applicable) or omit the field? Affects whether `--check` can require it.
5. **Where the drop folder lives.** The ladder specifies `%APPDATA%\AEGIS\reports\`, which is this
   PC only and puts every L1 report behind `needs-local-keys`-shaped locality. Worth asking whether
   it should be somewhere a second machine can read, given the owner's stated goal ("the sooner we
   get to headless automation, the less I will be creating sessions too").

---

## 9. Gaps in this document (not done unless documented)

- **Verified**: `claude --help` on 2.1.278; the installed `cli.js` agent-config parser; four probe
  runs (restricted/no-Bash, json-schema, cold cache, warm cache) with their JSON envelopes read;
  effort/model/maxTurns pin counts across all 88 agent files in this checkout; the contents of
  `tools/headless/`, `claude-agents/roster_meta.json`, `.github/workflows/*`, and the
  `standards/sessions/` files cited.
- **Not verified**: anything on `origin/main` newer than this checkout (HEAD, `origin/main` and
  the branch are all `3ca73d0` as fetched at session start; not re-fetched since); any live host, scheduled task, or the owner's machine; whether
  `--effort` is honoured by Haiku (F1a); whether Fable's *cache-write* multiplier is standard;
  current published prices (the rate table is cached, and `ops-policies` `routing/models.yaml` was
  not read — it is not in this repo); whether the prefix caches across separate scheduled
  invocations (F6).
- **Deliberately absent**: any code, any edit to a standard, any Decision Queue card, any dispatch,
  any date commitment, any dollar figure presented as a bill.
- The per-invocation cost table is arithmetic from a 25K-token preamble measured on **one** agent
  shape. A heavier agent (more tools, a longer definition, CLAUDE.md loaded) has a larger preamble
  and a proportionally larger floor.
