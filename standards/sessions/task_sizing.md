# Task sizing

`priority_classification.md` decides **which** tier of the backlog gets a lane this round. This
file decides **when within that tier** — biggest first while the usage window is freshest, smaller
work as it depletes — and whether a task is even safe to start with what's left.

## Why size, not just priority

A usage window (`tools/usage-monitor/`) is the scarce resource, and tasks don't spend it evenly.
A large build (multi-file, needs a local boot-test loop, several rounds of fix-and-reboot) dies
badly if it's forced to pause mid-way — the pause protocol says finish the current *step*, not the
whole task, so a big task interrupted partway through can leave a half-working branch. A small task
(one file, a doc fix, a status-table update) either finishes inside a few tool calls or costs almost
nothing to defer. So: **start the biggest thing first, when the window has the most room to let it
actually finish**, and fill the remainder of the window with work sized to what's left.

## Size tiers

Estimate from the task's *shape*, before dispatching — you won't know real token/tool-call counts
until it's done, so this is a T-shirt-size call, not a forecast. Calibration points are real lanes
from 2026-09-14.

| Size | Signals | Rough band (tool calls) | 2026-09-14 examples |
|---|---|---|---|
| **XL** | Cross-file, often cross-repo; needs at least one local boot-test cycle with a real chance of a fix-reboot-fix loop; scope was partly discovered while working, not fully known upfront | 60+ | VPS-CI lane (systemd timers + self-hosted runner design, two repos, 87 tool calls); AEGIS_Medicine build (death-path design + self-test, 76-92 calls across two runs) |
| **L** | A full plan session against a clear Do list, one repo, one boot-test cycle expected (not several) | 30-60 | aegis-mods Session 4 (Stealth/Survival skills); aegis-poi Session 3 (Trader module) |
| **M** | A handful of file edits with a validator to run, no local boot needed, or a boot-test whose outcome is expected clean | 10-30 | site-chernarus sell-only/Gator/bus PR; core Session 3 secret-rotation doc; services catalog-sync readiness check |
| **S** | One or two files, mechanical, a validator or none at all | <10 | Status-table fixes; a single safe-zone JSON edit (#85); a triage comment |

Signals that push a task UP a size, even if it looks small on paper:
- it depends on reading live data or third-party mod source to verify an assumption (that reading
  itself costs calls)
- a similar past lane needed more than one fix-and-reboot round
- the Do list has an "and verify against the real files" clause rather than a fixed list

## How to estimate

For each backlog item, before it becomes a lane card, ask:
1. How many files/repos does the Do list touch?
2. Does it need a local boot test? If yes, does history suggest one clean boot, or several rounds?
3. Is the scope fully known (a fixed list), or will part of it be discovered while working (a
   research/inventory step, an "and verify" clause)?
4. Has a similar-shaped lane run before? Use its real tool-call count as the estimate, not the
   original guess.

Pick the highest tier any signal points to. When genuinely unsure between two tiers, round up —
starting a slightly-oversized task early is cheap; starting an oversized task late is not.

## Scheduling rule

Priority still decides eligibility (P0 always, P1 next, P2 fills the fleet, P3 only with headroom —
see `priority_classification.md`). Size decides order and a start-gate, inside that:

1. **Sort dispatch order by priority tier first, size descending second.** Within P1, an XL item
   goes out before an M item, unless the M item blocks the XL one.
2. **Check `tools/usage-monitor/check-usage.ps1` before starting anything sized L or XL.** Rough gate
   (tune by feel, not a hard science):
   - **Fresh window (usage low):** anything can start, largest first.
   - **Usage climbing (past ~40-50%):** don't START a new XL. Let running ones finish; fill new
     fleet slots with M/S.
   - **Near the pause threshold (~70-80%):** only S, and only P0/P1 L if there's truly nothing
     smaller left in that tier.
3. **An oversized item for the current window doesn't lose its tier or get dropped** — it waits for
   the next fresh window, at the front of its tier's queue (see re-tiering in
   `priority_classification.md`; the same "never silently drop" rule applies to size-deferred items).
4. **P0 is exempt from the size gate.** A live-blocking fix starts regardless of size, because not
   starting it is worse than a bad pause.

## Recording it

- Put the estimate in the lane/research card: `Size: L`.
- When a lane pauses or finishes, note its *actual* shape in the handoff file next to its size guess
  (tool-call count if you have it, or "took two reboot rounds, not one") — this is the calibration
  data the bands above are built from. No separate tracking system; a one-line note is enough.

**Worked example, 2026-09-15 (ops-cycle-pm):** two lanes carded the same size ("Opus 5, high") came
back at very different shapes — AppArmor finished in 62 tool calls / 29 min, LUKS+age identities took
129 tool calls / 96 min (~2x), driven by two discovery findings (a `sops path_regex` matching bug, an
AIDE exclusion gap) that a cheap read-only pass could have surfaced first. Separately, two pieces of
manual orchestrator work that session — a stale-PLAN.md drift check across two repos, and a
merged-vs-open PR sweep across five — turned out to be exactly `plan-status-check` and
`pr-state-sweep`'s shape (see the T4 roster, `docs/AGENTS.md`), done by hand only because the roster
didn't exist yet mid-session. Concrete takeaway: front-load a T4 scout before an Opus/high lane when
the task involves reading unfamiliar state (existing configs, docs, third-party tool quirks) rather
than known-shape execution — it prices the same discovery at Haiku instead of Opus rates.
