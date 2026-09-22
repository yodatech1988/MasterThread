# Runbook — running the estate from a phone

Status: **DRAFT, 2026-09-21.** Companion to `docs/FABLE_AGENT_SUBAGENT_PLAN.md`, which carries the
reasoning, the measurements and the build plan. This file is the operating procedure only, written
to be read on a phone.

**Nothing in this runbook is live yet.** The wrappers it calls (F12) are not built, and the entry
gate in the plan's §7 blocks every build task except the two measurements. Read this as the
procedure the build is aiming at, not as instructions that work today. Each step says what it needs.

**Wave-1 tracking (2026-09-22):** F2 (#174) and F3 (#176) are merged to `main` (commit `10786c2`,
2026-09-22T02:18:32Z — #176 landed via #174's squash), and F10 (#172) is merged to `main`
(2026-09-22T02:18:45Z). See the plan's §6 status table and issue #185. The #169 follow-up (#175) is
still open. None of the "needs F12" gates below have moved yet — those wrappers (F12) are still
unbuilt regardless of F2/F3/F10 landing.

---

## The three things you touch

| | What | Where |
|---|---|---|
| **Seat** | One Sonnet 5 / low Claude Code session. Routes and dispatches. Derives nothing. | Phone or desk |
| **Board** | Decision Queue + Fleet Status. Read state, tap approvals. | Phone (paired device) |
| **Continuity** | The Fable seat. What changed, what we decided, what's next. | Phone or desk |

Everything else is an agent. You never run a lane yourself.

---

## A round, start to finish

**1. Open the seat.** Say `round-start`.
It reads Fleet Status, the Decision Queue and the report drop folder. It does not decide anything
yet.

**2. Ask continuity what's carried over.**
The seat resumes the Fable seat by its pinned id and asks: what changed since last round, what is
still open, what did we decide.
> **Whatever comes back is a claim, not evidence.** The seat re-checks anything actionable against
> live `gh`/`origin` before acting. This estate has already carried a false "resolved" across two
> handoffs (`orchestrator_role.md:277`). Needs: F9, F12.

**3. Seat files cards for anything needing you.**
Only the seat writes the board — `claude -p` cannot hold `ArtifactData`, so no agent can file its
own approval.

**4. You read and tap.** Summary on top, links in `points`.
On a paired phone a confirm is three taps with a 10s arm window. Decision cards resolve on your tap;
action cards resolve **on evidence**, so an agent closes them once it can see the thing is done —
you do not have to come back and press the button.

**5. Seat dispatches.** One wrapper call per task, by table lookup (plan §4). Never a hand-typed
flag line.

| Task shape | Wrapper | Tier |
|---|---|---|
| Design call, or continuity question | `Ask-Fable` (resume) | Fable / high |
| Row-1 review: live, credentials, money, death-path | `Invoke-Review` | Opus / high |
| Lane work: a repo, a worktree, a PR | `Invoke-Lane` | Sonnet / medium |
| Sweeps, inventories, state checks | `Invoke-Subagent` (batched) | Haiku |

All four need F12. Until it exists the seat would be composing ten-flag invocations by hand, which
is exactly what a `low` seat is bad at.

**6. Agents run headless** and file schema-checked JSON. They never write a card, never merge, never
schedule anything.

**7. Seat ingests the reports**, writes Fleet Status rows, files the next cards. Back to step 4.

---

## Rules that do not bend

- **The seat never upgrades itself.** A hard task dispatches a callee; it does not raise the seat's
  model or effort.
- **The seat never judges production.** Row-1 work goes to an Opus callee or to an owner click-file.
- **Operations never depend on the continuity seat.** If it is unreachable the round still runs off
  the durable record — repo, Fleet Status, cards. A wrapper that blocks a lane because continuity is
  down has inverted the rule.
- **Continuity is a cache, never the record.** Anything that matters is also written where a cold
  rebuild can read it.
- **Fork for speculation, resume for record.** A speculative question goes to `--fork-session` so a
  discarded idea never enters the memory as though decided.
- **No agent merges, and no agent schedules anything.**

---

## What you cannot do from a phone

**Run a click-file.** `tools/click-files/*.cmd` are Windows double-click scripts. You can *approve*
that class from a phone; you cannot *execute* it.

This bites in one specific place: **registering the scheduled run (F5) is itself a click-file**, so
the step that moves the fleet to L1 is desk-only. Plan §9 decision 5 recommends accepting that —
rung changes are rare and deliberate and already need an owner card — rather than building a second
approval path.

Also worth knowing: the approval-device gate is **"not real security"** in its own words — a
`localStorage` id against a shared pairing list. It guards against a wrong-device tap. It is not
access control, and it is not the owner-initiated binding `fleet_structure.md` requires for a
hard-to-reverse action.

---

## When something looks wrong

- **A report that says nothing is not a quiet day.** A scheduled run that emitted no file is a
  finding — "a silent watcher and a quiet fleet must not look alike" (`fleet_roster_monitor.md`).
- **A refusal reads as an empty answer.** Fable can decline at HTTP 200. Every Fable call runs
  `--fallback-model opus`; a seat at `low` will otherwise relay "nothing found" as a finding.
- **A cold resume succeeds and costs ~70× more.** ~$0.51 against ~$0.007. It does not fail, so F12
  has to make it loud.
- **Green CI is not evidence, and neither is its absence.** Say which kind of failure you are
  looking at before citing one.
- **A denial stops the lane.** It files a permission-denial card and waits. It never retries around
  the denial.

---

## Cost, in one line

The expensive thing is not the model — it is paying for a system prompt twice. Batch the sweeps into
one hourly burst, keep the continuity seat warm, and let Haiku subagents stay stateless. Measured
figures and their caveats are in the plan's §1b.
