# Priority classification

The orchestrator (`orchestrator_role.md`) uses this to decide **what runs now, what runs in the
next window, and what pauses first** when usage is tight. Usage windows are scarce (see
`tools/usage-monitor/`), so every round triages its backlog into these four tiers before dispatching
anything.

## The tiers

Pick the **first row that matches**.

| Tier | Meaning | Examples from 2026-09-14 | In this window | At the pause threshold |
|---|---|---|---|---|
| **P0 — Live-blocking** | The live server is broken or unsafe right now, a credential/secret is exposed, or Jeremy is actively waiting in real time (in-game, on a call) | a bad live boot; a leaked password; an in-game request while he's online; a restart that needs watching | Always gets a lane, first dispatched, first reviewed | Finishes its step and lands the fix even after the pause order goes out to everyone else |
| **P1 — Unblocking** | Fixing it frees up several other lanes, or it sits on the path to a P0 | CI/billing broken for every repo; a merge that's the only thing blocking 3 other sessions; a stale review blocking a ready PR | Dispatched right after P0, before any P2/P3 | Finishes its current step, then pauses and documents |
| **P2 — Plan work** | A normal `docs/PLAN.md` session with a clear Read/Do/Done-when and no one else waiting on it | most module/tooling/economy sessions | Fills the remaining fleet slots (cap ~6 total) | Pauses immediately — stop mid-step is fine, just push WIP and write the Paused note |
| **P3 — Deferred** | Research, doc grooming, nice-to-haves, anything with no deadline | mod-research triage, ledger polish, exploratory questions | Only dispatched if P0–P2 don't fill the fleet and the usage window has headroom (check `tools/usage-monitor/check-usage.ps1` first) | Never gets dispatched once usage is past ~50% for the window; already-running P3 lanes pause first, before P2 |

Assign every item a tier before it becomes a lane card. When two items compete for the last fleet
slot, the higher tier wins regardless of how it was originally shaped as Opus/Sonnet/Haiku — priority
and model/effort (`orchestrator_role.md`'s table) are independent axes. A P0 lane can still be a
cheap Sonnet/low task; a P3 lane can still need Opus if it's genuinely hard.

## How to triage a round

1. **Gather the backlog** from three places, not just the last handoff file:
   - the newest `GitHub\SESSION_HANDOFF_*.md`'s open items and paused lanes
   - each active repo's `docs/PLAN.md` "not started" Status rows
   - any owner decision recorded but not yet acted on
2. **Tier each item** with the table above. Write the tier next to it in the handoff file.
3. **Check the usage budget** with `tools/usage-monitor/check-usage.ps1`. A fresh reset (low %) means
   normal dispatch, all tiers eligible for the fleet. Usage already climbing means P3 doesn't get
   a slot this round, and P2 gets fewer lanes so more of the window is left for P0/P1 to land.
4. **Dispatch in tier order**, P0 first, filling the ~6-lane fleet cap from `orchestrator_role.md`.
5. **Carry the tier into the lane/research card** (`worker_role.md` / `researcher_role.md`), so a
   worker knows how hard to fight to finish versus pause cleanly:
   ```
   Priority: P1 (unblocks Sessions 3 and 6)
   ```
6. **At a pause order**, send it to every session as usual, but say the tier-based expectation:
   - P0/P1 lanes: finish the step, land the fix if you can, then document and stop.
   - P2/P3 lanes: stop now, mid-step is fine, push WIP and document.
7. **Next window**, anything that didn't get a slot keeps its tier (re-check it hasn't gone stale —
   a P1 blocker might already be fixed) and goes to the front of its tier's queue.

## Re-tiering

A tier isn't permanent. Re-check it every round:
- **P3 → P1**: something else now depends on it.
- **P1 → P2**: the thing it was unblocking already landed another way.
- **Anything → P0**: it turned into a live incident.

Never silently drop a P3 item. If it's been deferred more than a few rounds, say so in the handoff
file rather than letting it disappear.
