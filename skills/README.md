# Skills (Tier-1, batch 1)

Procedures a session loads into its own context and runs itself — distinct from the 70 read-only
advisor/reviewer subagents in `docs/AGENTS.md`, which only grade work after the fact. The owner
approved exactly these 5 Tier-1 skills, in this order, to close the gap that let 6 real incidents
happen with zero skills in place (a `--force` worktree removal that lost uncommitted work, a
session collision from two lanes racing the same repo, a push onto an already-merged PR, a
stacked-PR mis-merge, a corrupted secret, and a skipped usage watcher).

| Skill | Purpose |
|---|---|
| [`round-start`](round-start/SKILL.md) | Arms the usage watcher, re-verifies the ledger against live `gh` state, triages/sizes the backlog, and produces a dispatch plan — the first thing an orchestrator/PM round does. |
| [`dispatch-lane`](dispatch-lane/SKILL.md) | Collision-checks, creates the lane's isolated worktree in-process, and emits a properly formatted lane card before handing work to a worker. |
| [`land-pr`](land-pr/SKILL.md) | Re-checks live PR state before every push, routes review to the correct reviewer agent by scope, verifies a stacked-PR merge really landed on `main`, and updates `docs/PLAN.md`. |
| [`owner-click`](owner-click/SKILL.md) | Packages any action that needs Jeremy's hands — a credential, a production apply, an elevated-risk merge — as a double-click `.cmd` that shows the change and requires a typed `YES`. |
| [`round-closeout`](round-closeout/SKILL.md) | Writes the next `SESSION_HANDOFF_*.md`, refreshes stale ledger/memory facts, promotes seen-twice lessons, and emits the next round's launch prompts with model/effort rows. |

## Not approved for this batch

These 9 skills were scoped during the same review but **not** approved — their absence here is
deliberate, not an oversight. Do not build them without a fresh owner sign-off:

- `go-live`
- `boot-test`
- `secret-rotate`
- `plan-session`
- `deliver-lane`
- `verify-against-origin`
- `mod-review`
- `econ-change`
- `new-agent`

See `docs/LESSONS.md` for the running lessons-learned ledger that feeds future skill/standard
promotions.
