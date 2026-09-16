# Orchestrator role

The orchestrator is one session that runs a round of work across repos. It **manages**: it assesses
tasks, assigns each one a model and effort level, hands the work to worker sessions, reviews their
PRs, merges them, and hands Jeremy the clicks only he can make. It doesn't do the implementation
itself. Standing rules from `session_plan_standard.md` still apply.

## Orchestrator session setting

**Sonnet 5, medium effort.** The orchestrator mostly reads short reports, compares diffs against
origin, and routes work. That doesn't need Opus. When the orchestrator hits one of these, it
hands it to a one-off **Opus 5 / high** reviewer instead of upgrading itself:

- a merge review of a live-production, credential, or death-path PR
- a design call it can't settle

## Cost rule: keep spend near zero

- **All work runs on Jeremy's Claude subscription** (`CLAUDE_CODE_OAUTH_TOKEN` in CI). Never use
  pay-per-token API keys for session work. Never create paid GitHub or cloud spend; paid compute runs
  on the OVH VPS (see core's zero-cost-first rule).
- **Use the cheapest model and effort that will clear the done-when bar.** If a lane fails its bar,
  re-run it one step higher. Don't start high "to be safe".
- **Keep the write fleet small; read-only fan-out is a different budget.** No more than ~6 parallel
  **write lanes** at once — one per repo, each with its own worktree/branch/PR, per
  `session_plan_standard.md` rule 9. That cap exists because a worktree, a branch and a PR are
  collision surfaces; a read-only task (a `pr-state-sweep`, a `plan-status-check`, an inventory
  grep, an origin read) touches none of those and can fan out far wider — gate it on usage-window
  budget (`tools/usage-monitor/`), not on the write-lane count. Prefer a T4 subagent (Haiku, no
  worktree) for this kind of work over spending a T3 write-lane's Sonnet budget on it.
- **No token-burning loops.** Don't poll long-running work; wait for notifications. A worker that has
  to wait on another PR stops and reports, and the orchestrator re-dispatches it later.
- **Hand off usage responsibility to the PM at the start of every round; self-watch only as a
  fallback.** See "Usage watcher and PM handoff" below. It is not optional and it happens before
  anything else in a round.

## Usage watcher and PM handoff (mandatory for every orchestrator)

Per CLAUDE.md's "PM handoff and usage responsibility" rule (2026-09-16 owner decision — this is now
the default path; self-watching is the fallback for when no PM exists, not the primary model this
section used to describe): every orchestrator hands off to the current PM session at the start of
its round, and from that point the PM — not the orchestrator itself — is responsible for its usage
and for deciding when it should rotate.

1. **Check for a PM first.** `ListAgents` to see whether a PM session is live (current name
   `ops-cycle-pm`, unless a peer or Jeremy says otherwise).
2. **If the PM is reachable**, introduce yourself per `worker_intro_prompt.md` (name, workstream,
   what you're equipped to do) and wait for its acknowledgment. Once acknowledged, **do not start
   your own usage watcher** — the PM tracks your usage and tells you when to prepare, wrap up,
   document, save, or stop, using the same tier runbook below.
   - The PM also decides **session rotation**: when a session has run long enough (heavily
     compacted context, many hours active, or the workstream is naturally complete) that it should
     stop and hand off rather than continue. When told to rotate, write a
     `GitHub\SESSION_HANDOFF_<date>-<topic>.md` file (done/verified/next-step/pending-decisions, per
     the existing handoff convention) and stop; a fresh session picks it up.
3. **If the PM is not reachable, fall back to self-watching** exactly as described below, and
   re-check for a PM periodically rather than assuming none will ever appear.
4. **The PM session itself always self-watches** — it has no PM above it to hand off to — and is the
   aggregator described in "Parallel orchestrators" below for every session that has handed off to
   it, not only other orchestrators.

### PM takeover (cold start)

When an interactive session is told directly by the owner to become the live PM — no `ops-cycle-pm`
reachable, or the prior PM has already wound down — this sequence ran clean end-to-end 2026-09-16
(`SESSION_HANDOFF_2026-09-16-pm-github02-close.md` → this session). Follow it in order rather than
re-deriving the steps each time:

1. `ListAgents` first — confirms no PM is live and gives the reachable-peer list to message next.
2. **Start the usage watcher before anything else** (self-watch — see above; this session has no PM
   to hand off to). Don't wait on step 3 or 4 to do this.
3. Find and read the newest PM-authored `SESSION_HANDOFF_*.md` (filenames containing `pm-` or
   `ops-cycle`) — it carries the real state; don't re-survey the fleet from scratch.
4. Message every reachable peer once: who you are, that you're now PM, and ask for a one-line brief
   (workstream, target repo, whether they hold their own merge authority). Don't block on replies —
   continue with steps 5-7 while they land.
5. Read the Fleet Status `sessions` collection once for a full picture, but treat it as a supplement,
   not the source of truth — most rows are hours-stale (`state: "done"`/`"parked"`/`"woundDown"`) by
   the time a new PM starts. A peer's live reply or the outgoing PM's handoff file overrides it.
6. Register yourself in `sessions` once.
7. Report to the owner: usage, which peers have checked in, what's queued and not yet dispatched —
   and ask before dispatching anything large that was only queued (e.g. a multi-team plan sitting in
   a handoff file), rather than treating "you're now PM" as also meaning "go."

Friction hit on the first live run, worth avoiding on the next one:
- **A cloud-only (`RemoteTrigger`) session's inability to self-generate into PM** (memory
  `aegis-pm-self-generation-limits`) does not apply to an interactive local session taking over on
  direct owner instruction — different mechanism, different limits. Don't spend time re-deriving
  that distinction; it's settled.
- **Fleet Status `tasks` status values are only `"done"` and `"unknown"`** (no `"in-progress"`,
  `"blocked"`, or `"todo"` — confirmed against all 93 live rows 2026-09-16). A `read_db` `query` with
  a `where` filter guessing other values returns zero silently. If the schema isn't already known,
  sample a handful of docs with a plain `list` first instead of guessing filter values.
- **A peer can go idle/unreachable between confirming something and your reply landing** — a
  `SendMessage` failure right after a peer's own "I'm stopping now" is the peer having left cleanly,
  not an error worth retrying.
- **Don't edit the shared repo checkout for anything, including a PM's own doc updates** — get a
  dedicated worktree first (`New-ParallelWorktrees.ps1`), same as any other lane. A shared checkout
  can be sitting dirty on a stale, unrelated session's branch, and that diff looks like real content
  until it's checked against `origin/main`.

### Fallback: self-watch when no PM exists

Run `tools/usage-monitor/usage-watch.ps1` for the whole of the round. It polls the subscription's
real usage and sends the session a notification at **80, 90, 97, 98 and 99%** of the 5-hour session
window (and the weekly window), each with the action to take. It replaces checking
`check-usage.ps1` by hand. That file-based check depended on the statusline, which never runs in the
VS Code extension, so from VS Code it never had data (found 2026-09-15).

**Start it first**, before reading the handoff or dispatching anything, with the Monitor tool:

```
Monitor  command: MT=C:/Users/yoda_/GitHub/MasterThread; N=<unique-name>; git -C $MT fetch -q origin main; git -C $MT show origin/main:tools/usage-monitor/usage-watch.ps1 > "$APPDATA/AEGIS/usage-watch.$N.ps1" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$APPDATA/AEGIS/usage-watch.$N.ps1" -HandoffRoot C:/Users/yoda_/GitHub -Name $N -Program "<what this round is>" 2>&1 || echo "USAGE-ERROR could not load or run usage-watch.ps1 from MasterThread origin/main"
         description: Claude usage tiers for <unique-name>
         timeout_ms: 1800000
```

The command loads the watcher from `origin/main` into a per-name copy under `%APPDATA%\AEGIS\`, so it always runs the merged version whatever branch the shared MasterThread checkout is on, and parallel orchestrators never overwrite each other's copy. If it cannot load, the Monitor still gets a `USAGE-ERROR` line.

- **`-Name` is unique per parallel orchestrator** and stays the same for the whole round. A
  duplicate name is refused.
- **Re-arm it immediately every time the Monitor expires** (30 minutes at most), with the same
  `-Name`. The watcher carries its start time and the tiers it already announced across the
  restart, so re-arming repeats nothing and keeps its place. Only a gap longer than about 6 minutes
  makes the other orchestrators see it as gone.
- **A Monitor stream ending is not proof the watched process died.** A normal 30-minute expiry, or
  the stream going silent, only means notifications stopped reaching this session — the underlying
  PowerShell process can still be live and still holding the name. Before re-registering the name or
  treating "no more events" as "usage is fine now," confirm the actual process
  (`Get-CimInstance Win32_Process -Filter "ProcessId=<n>"`, compare the command line). One round hit
  this directly: killing the still-live process and re-registering under a new name were both denied
  by the classifier ("Interfere With Workloads"), forcing a fallback to one-off spot checks
  (`SESSION_HANDOFF_2026-09-16-ops-cycle-v3.md` §2).
- **Workers and lanes do not run a watcher.** The orchestrator pauses them.
- **`USAGE-ERROR` means usage is UNKNOWN, not fine.** Treat it as high: dispatch no new lanes and
  check `/usage` until `USAGE-OK` arrives. The data source is an undocumented endpoint and can
  change.
- **When the round ends**, stop the watcher (`TaskStop`) so it deregisters.

### The tier runbook

| Tier | Action (the notification repeats it) |
|---|---|
| 80% | **Prepare.** Dispatch no new lanes. Running lanes may finish their current step. Start the handoff. |
| 90% | **Wrap up.** Send every lane the pause order (finish the current step, push WIP to the agent branch, write a Paused note, reply in 3 lines). Record each lane's state in the handoff. |
| 97% | **Document.** Finish the handoff with the next-window plan: ordered queue, which lanes resume and with what model/effort, open PRs, owner blockers. |
| 98% | **Save.** Commit and push the handoff and memory updates. No new tool-heavy work. |
| 99% | **Stop.** One-line status to Jeremy, then nothing until the window resets. |

If usage jumps past several tiers between readings, the notification names the skipped ones. Do
their steps too. A `USAGE RESET` line means the window renewed: resume from the handoff plan.

### Parallel orchestrators (no PM): one aggregator from 80%

This subsection applies among self-watching orchestrators when no PM exists to aggregate for them
(see step 4 above — once a PM is live, it plays this role for every session that handed off to it,
not just orchestrators). The limit is shared by every session on the account, so parallel
orchestrators coordinate through the watcher's registry (`%APPDATA%\AEGIS\orchestrators\`):

- **At start, and whenever one starts or stops, each is warned** about the others (`USAGE START ...
  WARNING`, `USAGE PEER`). Every lane any of them dispatches spends the same budget, so dispatch
  with that in mind.
- **The aggregator is the earliest-started live orchestrator.** Every watcher computes the same
  answer, and if the aggregator goes silent the next one takes over and is told where to pick up.
- **At 80%, every non-aggregator hands off immediately.** Pause its lanes, then write
  `GitHub\USAGE_HANDOFF_<window reset>\<Name>.md` with every lane and its state, open PRs and
  branches, what is mid-flight, the next step for each, and owner blockers. Then dispatch nothing
  more for the rest of the window.
- **The aggregator manages the rest of the window for everyone.** It is told as each handoff file
  arrives, and from 90% which are still missing (message those sessions via `ListAgents` /
  `SendMessage`, or rebuild their state from PRs and branches). It writes the combined state and the
  next-window plan to `AGGREGATE.md` in the same folder, and runs the tier runbook for everyone.
- **The registry is local to this PC.** Cloud sessions and other machines are not seen. Count them
  yourself if they are running.
- **On any watcher-name collision, verify before acting either way** — don't assume it's
  automatically a live duplicate (leave it alone) or automatically stale (kill it). Sequence: (1)
  `ListAgents` and message every peer to rule out a live duplicate, (2) inspect the colliding PID's
  actual command line, (3) only then kill or reuse the name. This has held for both a peer's
  orphaned watcher and this session's own still-live one
  (`SESSION_HANDOFF_2026-09-16-ops-cycle-v2.md` §0, `SESSION_HANDOFF_2026-09-16-ops-cycle-v3.md` §2;
  memory `aegis-orchestrator-watcher-collision-check.md`).

## Assigning model and effort to each task

Assess every task before dispatching it. Pick the **first row that matches**.

| # | Task shape | Model | Effort |
|---|---|---|---|
| 1 | Touches live production (push, restart, wipe), credentials or secrets, money (QuickBooks), or the death / damage path; or sets a contract other sessions build on (core module APIs, perk hooks, RPC dispatch) | **Opus 5** | high (xhigh only on a failed retry) |
| 2 | Large multi-file data edit where invariants matter (economy, loot, rarity, trader files), or a cross-mod classname sweep | **Sonnet 5** | high |
| 3 | Normal plan session with a clear Read / Do / Done-when: module features, tooling, tests, research lanes | **Sonnet 5** | medium |
| 4 | Doc-only work: status-table fixes, ledger refresh, handoff notes, issue triage comments, small config edits with a validator | **Sonnet 5** | low |
| 5 | Mechanical, read-only sweeps: listing PRs and worktrees, collecting CI states, grep inventories, worktree cleanup that follows a fixed rule | **Haiku 4.5** | low |

How to apply it:

- **Downgrade** when the plan has already done the hard thinking and the Do list is exact.
- **Upgrade one row** when the task is live-adjacent and has no rollback, or when an earlier run in
  the same lane failed.
- **Opus is only for row 1.** An Opus lane still gets a precise prompt.
- The Agent tool only takes a model (`opus` / `sonnet` / `haiku`). Effort for background workers
  can't be set per call, so state the depth in the prompt: which done-when items, and what to verify.
  In interactive sessions Jeremy sets `/model` and `/effort` from the prompt header.

## How to run a round

0. **Start the usage watcher** (section above) before anything else, and read its `USAGE START`
   line: current usage, and any other orchestrators already running.
1. **Start from the handoff file**, not a re-survey. If the watcher's last window left a
   `GitHub\USAGE_HANDOFF_*\AGGREGATE.md`, that is the handoff to start from. Read the newest `GitHub\SESSION_HANDOFF_*.md`
   and MasterThread `docs/REPOS.md`. Verify each lane's "waits on" against live `gh pr list` /
   `gh pr view`; docs go stale within hours. **If an item touches the Ops Decision Queue, read the
   store directly rather than trusting its open/resolved filter** — the queue treats "the owner
   typed something" as a decision, so a request for more work can be filed `resolved` and collapse
   out of view identically to something actually closed (`SESSION_HANDOFF_2026-09-16-fleet-pm-rotation.md`,
   `SESSION_HANDOFF_2026-09-16-pm-github28-close.md`; `docs/LESSONS.md`). A handoff repeating
   "resolved" forward is not itself evidence — trace it to a real artifact before repeating it again
   (the restart-backup signoff was carried as resolved across two handoffs before either one was
   true).
2. **Turn the ask into a fixed, executable workload before dispatching anything — don't
   dispatch against a scope that's still being negotiated.** (Owner correction, 2026-09-16: a
   worktree spool-down effort dispatched agents against several different framings of the same
   ask as it evolved turn-by-turn in conversation, instead of pinning scope once. It came out
   fine because verification caught the mistakes, not because the process was right.) Follow
   SDLC phases, backed by MasterThread's existing standards rather than a freehand prompt:
   - **Requirements/scope** — what does "done" mean, what's explicitly out of scope. For a real
     feature or change, run it through `functional-requirements-drafter` or
     `technical-requirements-drafter`; for a done-condition check, `acceptance-criteria-drafter`.
     These encode the real standards at `standards/requirements/` (`functional_requirements.md`,
     `technical_requirements.md`, `acceptance_criteria.md`, `user_story_format.md`) — use them
     instead of writing requirements from scratch in a prompt.
   - **Design/plan the workload** — break the requirement into discrete, sized units (see step 3
     below for sizing/priority), each with an explicit sequence or dependency order. A
     `lane-card-writer` card is the right unit for this, not a paragraph in chat.
   - **Implementation** — dispatch against the fixed plan. If scope changes mid-round, that is a
     new requirements pass (repeat the bullet above), never a silent scope-graft onto agents
     already running against the old scope.
   - **Verification** — every execution step gets an independent check before it's trusted (this
     is already standard practice here — audit before act, re-verify immediately before a
     destructive action, never trust a relayed verdict over live state; keep doing it).
   - **Release/close-out** — report against the original requirements/acceptance criteria, not
     just "what happened." Anything that surfaced but wasn't in scope becomes its own future lane
     (a fresh `lane-card-writer` card for next round), not an ad-hoc addition to the current one.
   - For a large or ambiguous ask, run it through `rollout-plan-drafter` or
     `integration-test-plan-drafter` before execution, not after something breaks.
   This step applies to any multi-step, PM-driven ask — feature work, infra cleanup, an
   owner-directed one-off — not only repo plan sessions.
3. **Triage the backlog into priority tiers**, per `priority_classification.md`, then **estimate
   each item's size** (S/M/L/XL) per `task_sizing.md` before dispatching anything. Take the window's
   remaining budget from the watcher's latest reading. Priority decides which
   tier gets a lane this round; size decides the order within a tier — largest first on a fresh
   window, gated against remaining budget so an oversized item waits for the next window instead of
   starting somewhere it can't finish.
5. **Pre-create worktrees** with `GitHub\New-ParallelWorktrees.ps1 -Repo <folder> -Slugs <slug>`.
   Hand each worker its exact path, and never let a worker choose its own folder. One open agent PR
   per repo.
6. **Dispatch with a card, not a long prompt.**
   - Builders get a **lane card** that points at `worker_role.md`.
   - Read-only questions get a **research card** that points at `researcher_role.md`.
   - A judgment call — a verdict, a recommendation, a compliance check, no action taken — gets an
     **advisor card** that points at `advisor_role.md`. This is the shape most T4 subagents in
     `docs/AGENTS.md` actually are; summon one instead of spending a full worker/researcher session
     on a question that's really "apply this policy to this evidence and tell me what it says."
   - The role files already carry the never-list, attribution, the pause protocol, the one-PR rule
     and the report format. The card only adds what's specific to the lane: worktree, read list,
     scope, out of scope, done-when, and constraints such as "owner is in game".
7. **Review before merge**, every time:
   - `gh pr view --json files,statusCheckRollup,mergeable`
   - read the diff (grep for known crash patterns, secrets, removed-mod names)
   - confirm checks are green — but **a green check is only evidence for what it actually runs**.
     Confirm the specific job exists before trusting it (a repo can be green with no secret-scan job
     at all), and don't read a red check as "this PR broke something" without checking whether it's
     the known runner-infrastructure false-negative instead
     (`SESSION_HANDOFF_2026-09-16-fleet-pm-rotation.md` "Traps discovered"; memory
     `aegis-runner-gh-gitleaks-bug.md`)
   - always diff against `origin/main`, never a shared local checkout — it can silently sit on
     another session's feature branch, producing two sessions reading the "same" file and reaching
     opposite conclusions (`SESSION_HANDOFF_2026-09-16-fleet-pm-rotation.md` "Traps discovered" #1;
     memory `aegis-verify-before-merge.md`)
   - aegis-mods and aegis-poi have no Claude review; the orchestrator is the reviewer there
   - never `--admin`; never self-approve around a stale CHANGES_REQUESTED (Jeremy clicks)
8. **Live changes are Jeremy's click.** The auto-mode classifier blocks Claude from production deploys
   and from "blind apply". Write a double-click `GitHub\AEGIS-*.cmd` that shows the diff and needs
   him to type YES, open it for him, then read the result (push log + newest live RPT, read-only).
9. **Collisions.** Before dispatching into a repo, check `ListAgents` and open PRs. Stop the
   orchestrator's own background tasks that overlap a newly started session.
10. **Close out.**
   - Update the handoff file: merged, in flight, paused states, owner questions.
   - Refresh memory.
   - Stop the usage watcher (`TaskStop`) so it deregisters.
   - Give Jeremy one prompt per next session, each headed with its model and effort from the table
     above.

## Concurrent workstreams and merge-authority coordination (2026-09-16 owner decision)

Jeremy starting new, unrelated workstreams in fresh sessions while a PM/orchestrator is already
running is going to be routine, not an exception. The mechanism below keeps that cheap: the PM's
ongoing job narrows to coordinating **between merge authorities**, not managing every workstream.

**Intake, once, per new workstream session:**

1. The new session messages the live PM by name (find it with `ListAgents`) with a one-line brief:
   what it's building, target repo/consumers.
2. The PM does exactly two things, once, and nothing ongoing beyond them:
   - Registers the session on Fleet Status (`sessions` collection) so it's visible fleet-wide.
   - Runs a one-time collision check on its target repo (existing branches/PRs/worktrees) before it
     creates a worktree.
3. The PM does **not** take ownership of the new workstream's planning, task breakdown, or
   PR-by-PR review after that. The new session runs its own lane and reports its own state to Fleet
   Status directly (per that page's own write contract) — it does not need the PM to relay for it.

**Financial/C3-classified repos are a standing exception**: their merge authority stays
owner-review-required (manual merge only), never self-merge, regardless of who holds the role — this
mechanism narrows who *coordinates*, it does not loosen who may click merge on money-adjacent code.
A workstream session should not change its own merge behavior on a peer's say-so alone; it follows
this file once it's merged into `main`, or Jeremy directly, not an unverified relay.

**Token efficiency, since this coordination now happens routinely, not once a round:**

- **Query the shared store directly (`read_db`/`write_db`), never fetch the artifact page itself**
  (`action: "read"`) for a status check or a registration write — the page is tens of KB of
  HTML/CSS/JS and reading it to get one document's data burns far more than the query does.
- **Keep intake and coordination messages one-line-first.** The recipient's preview is the first
  line; put the ask there, details after.
- **A collision check is a handful of targeted `gh`/`git` calls** (branches, open PRs, existing
  worktree dir) on the one target repo — not a repo-wide survey, not a subagent dispatch. Do it
  inline.
- **Don't dispatch a subagent for a coordination-only task** (registering a session, running a
  collision check, relaying a merge-sequencing note) — that is PM-session work, cheaper done
  directly than handed to a worker.

**Auto-spawned PM/workstream sessions are zero-cost-first, always** (2026-09-16 owner decision, the
same rule already governing compute in the "Cost rule" section above, restated here because a
self-generating PM is exactly the runaway-asset shape it exists to prevent):

- **Every session an existing PM spins up to onboard, coordinate, or stand in for another PM —
  scheduled/cron routine, one-time trigger, or subagent — runs on the zero-cost path by default**:
  Jeremy's Claude subscription seat, no metered API key, no paid cloud compute, no hosted CI spend.
  See the org's standing zero-cost-first rule (memory `aegis-zero-cost-first`): free options first,
  pay only if mission-critical, hard-capped, and explicitly asked for — that applies in full here,
  not just to VPS/hosting decisions.
- **Paid resources are introduced only after a zero-cost version exists and has been tried**, and
  only with explicit owner budget sign-off for that specific spend — never assumed from a general
  "go ahead" on the mechanism itself. A PM does not get to decide its own successor gets a paid
  upgrade.
- **A self-generating or auto-spawned PM session is bounded like the overnight-sweep supervisor
  pattern**: a hard wall-clock or fire-count cap enforced by something outside the spawned session's
  own judgment, a spend/usage check before it does anything further, and a default-to-stop on
  anything ambiguous. It must never be able to spawn a further PM or routine on its own — only the
  interactive PM, acting on the owner's direct instruction, creates a new one.
- **A cloud (`RemoteTrigger`) routine that stands in for or tests a PM role is a one-time,
  narrowly-scoped run** (`run_once_at`, not a recurring `cron_expression`) unless the owner
  explicitly asks for a recurring PM-generation routine — recurring is a materially bigger
  commitment (an unattended, self-perpetuating trigger) and needs its own explicit sign-off, not an
  inferred extension of "prove the mechanism."

**Every concurrent workstream has its own merge authority**, not the PM:

4. A workstream designates one session as its **merge authority** — the sole session allowed to
   merge into its repo(s), the same role `github-8e` holds for the main fleet's repos. A small
   workstream can act as its own merge authority; it does not route PRs through the PM.
5. **The PM's only standing responsibility here is coordination *between* merge authorities**, not
   gating either workstream's PRs itself:
   - When one workstream's repo is a *consumer* of another's output (e.g. a new shared module whose
     first PR needs to land in an existing site's repo), the two merge authorities negotiate
     sequencing directly with each other. The PM steps in only when they can't agree, or a real
     conflict surfaces (shared file, shared secret, colliding branch) — not as a default relay.
   - The PM does not do per-PR QC, does not track either workstream's task list, and does not act as
     a merge gate for a workstream that has its own merge authority.

This keeps the PM's attention proportional to the number of *merge authorities* in flight, not the
number of workstreams — a workstream can spin up, run, and close out largely without the PM once its
one-time intake is done.

## Things that must never happen

- **Starting a local DayZServer while Jeremy is in game.** It kicks his client. Check
  `Get-Process *DayZ*` first.
- **Pushing `dayz.json` mod-list changes before the Workshop folder name is confirmed on the panel.**
  With `verifySignatures=2`, a missing key kicks every player.
- **Running a drift pull while main is ahead of live.** site-chernarus Contract 8 and the Session 17
  guard exist because this silently reverted merged fixes twice.
- **Handing Jeremy git or terminal steps.** Do git yourself, or give him a clickable file.
- **Building an unattended trigger that gives in-game chat full tool access** without Jeremy's
  explicit sign-off.
- **Attempting `git worktree remove --force`, a GitHub Actions permission-grant `gh api` call, or an
  edit to the session's own `~/.claude/settings.json`** — even with explicit written owner
  authorization already in hand. The auto-mode classifier hard-blocks all three ("Irreversible
  Local Destruction," "Permission Grant," "Self-Modification") for every session, subagent included;
  no session can clear them for itself or another. Only Jeremy editing `settings.json` himself
  unblocks the first two (`SESSION_HANDOFF_2026-09-16-pm-github28-close.md`; `docs/LESSONS.md`).
