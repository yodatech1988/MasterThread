# Runbook — running the estate from a phone

Status: **DRAFT, 2026-09-21.** Companion to `docs/FABLE_AGENT_SUBAGENT_PLAN.md`, which carries the
reasoning, the measurements and the build plan. This file is the operating procedure only, written
to be read on a phone.

**Most of what this runbook calls for has now merged, but not all of it.** The wrappers it calls
(F12, PR #197, `ec5e0c7`) are **built and merged** — `Ask-Fable`, `Invoke-Lane` and `Invoke-Subagent`
exist with `maxTurns`/budget enforcement. **They are not yet the resumed-Fable contract this runbook
describes**: `Ask-Fable` does not thread `--session-id`/`--resume`/`--fallback-model`/`--fork-session`
to the real `claude` call, so today the seat is single-turn per invocation, not the warm-resumed
continuity seat §3 of the plan and step 2 below assume. Two duplicate follow-up issues track this
(#198; the duplicate #205 is now CLOSED). The plan's §7 entry gate has conditions 1, 2, 4 and 5 verified (2026-09-22, each
against a merged PR or resolved card) and **condition 3 not verified** (the `readonly` classification
in `roster_meta.json` on `origin/main` — not re-checked). The F5 and F11 WAITs are still relayed,
each pending its own confirmation (plan §9), independent of the gate. Read the steps below against
that state: the wrappers exist, continuity resume does not yet.

**Wave tracking (2026-09-22):** F2 (#174), F3 (via #174/#176) and F10 (#172) merged to `main` at
2026-09-22T02:18Z (commit `10786c2` for F2/F3, `092d278` for F10). F4 (#190) merged 02:46:38Z
(`0a5ff4e`) — schemas only; per-agent verb pinning was #208's phase 1 (`pr-state-sweep` only), which
**MERGED to main** 2026-09-22T17:26:04Z (squash `c1200827b4f3cfda49c20067a02ce357a53aea37`, route B),
closing issue #204. #208's live acceptance case surfaced a pre-existing, unrelated gap, now issue
#212: a live `pr-state-sweep` run returns prose instead of schema-valid JSON under `--json-schema`
(exit 8, DRAFT PR #214 not yet ready — root cause is that `--json-schema` output lands in
`envelope.structured_output` and the CLI does not enforce the schema under `--agent`). #159
(cost-monitor) merged 03:17:07Z (`2575bf1`). F12 (#197) merged 14:59:24Z (`ec5e0c7`) — see the
caveat above. F14 (#203) merged 14:59:52Z (`928b77d`). F9's draft (#195) merged 16:38:18Z
(`9c7e791`); PR **#213** ("standards: fable_seat.md (F9) relocated from drafts, TODO(F12)
resolved", route C) **MERGED to main** 2026-09-22T17:53:49Z (commit `1fe6c04`) — the continuity
contract now lives at `standards/sessions/fable_seat.md` (the old `docs/drafts/fable_seat_draft.md`
path no longer applies). The ladder's L1 report shape (issue #184) has its fix in PR **#209**
("ladder: L1 report shape is F3's {envelope, checkedAt, command} (closes #184)", route C), which
**MERGED to main** 2026-09-22T17:54:09Z (commit `9ebd4f8`), closing #184. F8 (#202) merged
16:29:20Z (`56b9a63`) — no longer "Blocked on #159," which merged first. Issue #185 is closed (done
via #210). See the plan's §6 status table.

---

## The three things you touch

| | What | Where |
|---|---|---|
| **Seat** | One Sonnet 5 / low Claude Code session. Routes and dispatches. Derives nothing. | Phone or desk |
| **Board** | Decision Queue + Fleet Status. Read state, tap approvals. | Phone (paired device) |
| **Continuity** | The Fable seat. What changed, what we decided, what's next. | Phone or desk |
| **Tracker** | Live F-task/round/agent progress board for this plan's own build-out (plan §2, F14). Read-only for you; only the seat writes it. | Phone (paired device) |

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
On a paired phone a confirm is three taps with a 10s arm window. Decision cards resolve on your
tap, and only yours. Action cards take two steps. You do the thing and press **"I did it - check
it"**. That records your claim and leaves the card open. Then **the seat** checks the live result
and closes the card, recording what it checked. The seat never closes an action card you have not
claimed. No agent closes one either, because agents cannot write to the board (step 3). If the
check fails, the card stays open with what was found.

**5. Seat dispatches.** One wrapper call per task, by table lookup (plan §4). Never a hand-typed
flag line.

| Task shape | Wrapper | Tier |
|---|---|---|
| Design call, or continuity question | `Ask-Fable` (resume) | Fable / high |
| Row-1 review: live, credentials, money, death-path | `Invoke-Review` | Opus / high |
| Lane work: a repo, a worktree, a PR | `Invoke-Lane` | Sonnet / medium |
| Sweeps, inventories, state checks | `Invoke-Subagent` (batched) | Haiku |

F12 (PR #197, `ec5e0c7`) is merged, so `Invoke-Lane` and `Invoke-Subagent` exist as wrappers today.
`Ask-Fable` exists too, but **not yet as a resumed call**: it does not thread `--session-id`/
`--resume`/`--fallback-model`/`--fork-session`, so a design call or continuity question through it
is single-turn, not the warm-resumed contract the row above and plan §3 describe (#198
outstanding; the duplicate #205 is now CLOSED). Before F12, the seat would have composed ten-flag invocations by hand, which is
exactly what a `low` seat is bad at; that composing is now wrapped, and the resume gap is what is
left.

**6. Agents run headless** and file schema-checked JSON. They never write a card, never merge, never
schedule anything.

**7. Seat ingests the reports**, writes Fleet Status rows, updates the F-task tracker (one row per
F-task id, status only — no logs, code or secrets), files the next cards. Back to step 4.

---

## Rules that do not bend

- **The seat never upgrades itself.** A hard task dispatches a callee; it does not raise the seat's
  model or effort.
- **Only the seat writes the F-task tracker** — same rule as Fleet Status and the Decision Queue.
  An agent files a report; it never writes a tracker row, and neither does the Fable seat.
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
the step that moves the fleet to L1 is desk-only. **D5 (2026-09-22, relayed; pending the owner's
answer on card `fable-confirm-d5-rung-changes-desk-only-2026-09-22`):** rung changes stay desk-only,
and no second approval path is built.

Also worth knowing: the approval-device gate is **"not real security"** in its own words — a
`localStorage` id against a shared pairing list. It guards against a wrong-device tap. It is not
access control, and it is not the owner-initiated binding `fleet_structure.md` requires for a
hard-to-reverse action.

---

## When something looks wrong

- **A report that says nothing is not a quiet day.** A scheduled run that emitted no file is a
  finding — "a silent watcher and a quiet fleet must not look alike" (`fleet_roster_monitor.md`).
- **A refusal reads as an empty answer.** Fable can decline at HTTP 200, and a seat at `low` will
  relay that as "nothing found". A refusal is a stop. The wrapper reports it as a refusal, and it is
  filed for you. It is never retried on another model. (`--fallback-model opus` is only for when
  Fable is overloaded or unavailable. It is not a way around a refusal.)
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

Every number here is an **API-list-price-equivalent dollar figure**, read from the CLI's own
`total_cost_usd`/`modelUsage[*].costBasis: "list"` fields, even though the call itself is billed
against the Claude Code subscription, not metered API usage. See plan §11.
