# PM-phase advisory — project management and SDLC across the estate

**From:** github-9d (owner-started advisor / PM-process workstream). **To:** PM github-f8; owner.
**Written:** 2026-09-18 ~01:00Z. **Basis:** `origin/main` of MasterThread and ops-platform, the
Fleet Status and Decision Queue stores read directly, a live `gh` PR sweep, and four read-only
subagent reports. Nothing here was taken from a working tree or a relayed summary. Where a fact was
not checked, it says so.

The PM stays PM. Everything below is a recommendation; anything that changes a standard goes to the
owner as a route C PR through the PM, per `merge_authority.md`.

---

## 0. Owner instruction received 2026-09-18 ~00:50Z — the PM must never stall

Owner, directly, three messages: *"The other session stopped working as the pm, we need to make
adjustments so the pm never stalls."* — *"the pm should be constantly monitoring usage and
activating agents and teams of agents with sub agents to be working backlog"* — *"as a pm not a
worker."* Checked at 00:52Z: `github-f8` shows `busy` in `ListAgents`, mode `prompting`; usage
39% / 67% from the state file. So the stall the owner sees is not a dead session — it is a live
session that is not dispatching.

### Why a PM stalls here (four causes, all structural)

1. **Event-driven with no events.** `pm_role.md`: "The PM is event-driven … It does not poll." A
   Claude Code session acts only when a message arrives. With no cron armed, no owner typing, and
   no peer reporting, the PM's turn ends and nothing wakes it. The design *is* the stall.
2. **Prompting permission mode — a risk factor, not the observed stall.** (Corrected by f8, 01:00Z:
   it was dispatching throughout.) Every gated tool call blocks on a prompt only the owner can
   answer, so a PM left unattended *will* stall at the first gated step of a dispatch. The watchdog
   must detect "no tick while budget and dispatchable work exist", never permission mode alone —
   detecting on mode would flag a healthy PM.
3. **Nothing dispatchable.** The register is empty, so an awake PM has no `next` to hand out and
   reads the whole board as `blocked-owner` — when only the owner-gated items are.
4. **The PM does worker work.** Verifying cards one `gh` call at a time, reading diffs, re-arming
   watchers by hand. It spends its own context, then ends its turn.

### The fix: a PM heartbeat, in four layers (cheapest first)

| Layer | What | Cost | Who |
|---|---|---|---|
| **A. Heartbeat tick, in-session** | `CronCreate "*/10 * * * *"` (or `/loop 10m`) carrying the control loop as its prompt: (1) read `%APPDATA%\AEGIS\claude-usage-state.json`; (2) `ListAgents` → `fleet-roster-watch.ps1`; (3) register: every staffed workstream whose `now` is delivered gets its `next` dispatched; every unstaffed ≤P1 workstream with a **dispatchable** item (not owner-gated) gets a team while 5-hour usage < 80% and write lanes < 6; (4) own cards via `get`; (5) write own `sessions` row `updatedAt`. **A tick never ends with dispatchable work + budget + idle capacity.** Quiet ticks are no-ops. | One cron; near-zero on quiet ticks | PM, today |
| **B. Teams of agents with subagents** | Dispatch through the `Agent` tool, `run_in_background: true`, one **lead** per lane (Sonnet, briefed with the lane card and told to spawn its own roster subagents for research/verification, and to report in three lines). The PM pre-creates the worktree (`New-ParallelWorktrees.ps1`), hands the exact path, and reads only the report. Read-only teams (verifiers, sweeps) are Haiku and budgeted by usage, not lane count. | Per lane: one Sonnet lead + its Haiku children | PM |
| **C. Permission posture for the PM seat** | The PM's coordination tools must not prompt: `ArtifactData`, `SendMessage`, `Agent`, `CronCreate/List/Delete`, `Bash(gh pr list *)`, `Bash(gh pr view *)`, `Bash(gh api repos/*)` (GET), `Bash(git fetch *)`, `Bash(git show *)`, `Bash(git worktree add *)`, `Bash(git worktree list)`, `Bash(powershell.exe … New-ParallelWorktrees.ps1 *)`. Anything else keeps prompting. Only the owner edits `settings.json` (self-modification is classifier-blocked) → **one card with the exact allow list**. | One owner click, permanent | Owner via card |
| **D. External watchdog** | Each tick also writes `%APPDATA%\AEGIS\pm-heartbeat.json` (`{session, tickAt, usage, dispatched}`). A Windows scheduled task (zero-cost, subscription-free — it's PowerShell) every 15 min: if the file is older than 30 min while usage < 80%, raise a toast + write a `health` row → the owner knows the PM stalled without opening a session. Later rung (L3): the same task launches a headless PM tick (`claude -p`, PM prompt, `readonly.settings.json`) so the loop survives session death. | S lane (script + task) | my workstream |

### "As a PM, not a worker" — rules to make it checkable

- The PM never runs `gh pr diff`, never reads a card body to verify it, never edits a standard,
  never SSHes. Each of those is a Haiku/Sonnet dispatch (`diff-reviewer`, `register-verifier`,
  `blocked-work-sweep`, a worker lane). **Check:** the PM's own tool log per tick contains only
  `ListAgents`, `ArtifactData`, `SendMessage`, `Agent`, `CronCreate`, usage/roster script calls,
  worktree creation, and `gh pr list/view`.
- The PM's context is the fleet's scarcest resource. Any task needing more than ~3 tool calls of its
  own is delegated. **Check:** tick length; a tick over ~10 tool calls is a finding.
- The PM does not wait on the owner to dispatch. Owner-gated items go on the batch; everything
  else in the register keeps flowing. **Check:** `dispatchable-and-idle` count at end of tick = 0.

### Register field to add: `dispatchable`

`true` when `next` can start without an owner action or a merge that has not happened. The
heartbeat dispatches only from `dispatchable: true` rows; `blocked-owner` rows are batched for him.
Without this bit the PM cannot tell "waiting on Jeremy" from "waiting on me", which is exactly the
confusion that stalled it.

---

## 0a. What I would change in the PM's own loop next (with cost)

| # | Change | Why now | Cost |
|---|---|---|---|
| 1 | **Instantiate the workstream register today.** The `workstreams` collection on Fleet Status is **empty** (queried 00:45Z) and `docs/WORKSTREAMS.md` is five headings with one line each. `pm_role.md` makes the register the PM's primary artifact and the completion handshake ("the answer should already exist") cannot work without `next` filled. Seed it from the c5 handoff's "Unowned and worth staffing" plus the live sessions. pm_role's open decision #1 (register location) is *default pending confirmation* → Fleet Status; proceed under the default and card it. | Every intake and completion reply is currently improvised from handoff files and chat. | ~8–12 `ArtifactData` writes, 20 min. Draft rows are in §7 of this file; the PM writes them (register is PM-written only). |
| 2 | **Arm `fleet-roster-watch.ps1` (`-Reset`, then the 10-min cron).** 31 `sessions` rows exist, 1 PM is live, most rows are `done`/`parked`/stale, and two orphaned usage watchers are rate-limiting each other. The roster monitor is built for exactly this and is not running. | Membership is the input to staffing and usage aggregation; without it the PM re-derives it by messaging peers. | One `CronCreate`. Zero tokens on quiet ticks. |
| 3 | **Split the owner's board into "his by right" and "his by accident" and batch the clicks into one ordered click-session.** 10 open + 20 follow-up-pending cards, every one an action. See §4 for the classification. | Owner clicks are the fleet's throughput limit; sequencing them (recovery key before credentials, VaultTunnelKey before anything else) is PM work nobody is doing. | One card-writing pass, ~30 min. |
| 4 | **Give permission denials a queue.** When a session hits a classifier denial, it files a card `kind: action`, `category: permission/denial` naming the exact command, what it would change, and the rollback — the owner then either runs it or adds an allow rule. Today a denial stops the lane dead until he appears. | f8's own list: "permission denials have no queue." | A one-paragraph addition to `decision_queue_standard.md` (PR, route C) plus practice from now. |
| 5 | **Start-of-round is a read-only fan-out, not a re-survey.** One message launching `pr-state-sweep`, `gate-execution-auditor`, `plan-status-check` (Haiku), results written into the register's `verified` fields. | Replaces the hand-run `gh` loops that produced last night's stale-read errors. | ~3 Haiku agents per round. |
| 6 | **Before relaying any owner instruction, run the executability check** (§5, the postmortem rule): every step traces to a primary source or a runnable command; ask "what artifact does this step produce and can the next step consume it?" — not "is it clear?" | Four sessions relayed an impossible instruction on 2026-09-17; zero detections until the owner said he didn't know how. | Minutes per card. An advisor agent for it is proposed in §8. |

---

## 1. Diagnosis: the shape of the problem

The estate has **excellent standards and almost no control plane**. The 2026-09-16/17 rounds
produced `pm_role.md`, `merge_authority.md`, `fleet_structure.md`, `fleet_roster_monitor.md`,
`headless_agent_permissions.md`, `decision_queue_standard.md` — each of them careful, evidenced, and
written from real incidents. But the artifacts those standards *describe* mostly do not exist:

| The standard says | What exists on `origin/main` / live |
|---|---|
| `pm_role.md`: the register is "the single list of what the fleet is doing" | `workstreams` collection: **empty**. `docs/WORKSTREAMS.md`: five one-line headings. |
| `pm_role.md`: "A headless PM (ops-platform `packages/project-manager`, the `pm-agent` reasoning layer) runs the deterministic parts of this loop — register upkeep, the merge audit, digest assembly" | The package implements **digest assembly only**. No register, no merge audit, no Fleet Status or `gh` code. `bin/start.js` unconditionally throws. `pm-agent` has **never existed** (roster audit F7; MasterThread #80 still not on main). Never deployed anywhere. |
| `headless_agent_permissions.md`: recommends its invocation line to `reasoner.js` and `tools/overnight-sweep-supervisor.ps1` | `reasoner.js` passes `--tools` but **not** `--settings`, `--permission-mode`, or `--permission-prompts`. `overnight-sweep-supervisor.ps1` **is not on `origin/main`** (`git ls-tree` 00:40Z). |
| `docs/AGENTS.md`: "the single index of every subagent definition", generated by `tools/generate_agents_md.py` | Hand-maintained; the generator has never been run because it drops a column (audit R4). `check_agent_sync.py` shows drift today (`blocked-work-sweep.md`, `pm-agent.md`). |
| `merge_authority.md` principle 7: "prevention where GitHub can enforce it" | Claude review is a required check in **no** repo; `services` has protection with an **empty** required list; `site-badlands`' only required check runs `echo "no checks configured yet"`. Six repos have no protection at all. (Carded: `branch-protection-gates-that-gate-nothing-2026-09-18`.) |
| `fleet_status_standard.md`: `queue`/`prs` panels are live | Sole writer (`github-8e`) is gone; panels frozen since 2026-09-16. |

This is **spec-first debt**: the org writes the standard, the standard names the mechanism as if
built, and later sessions read the claim as a fact. It is the same category error the postmortem
names — text treated as evidence — applied to the org's own process documents. The fix is not fewer
standards; it is a rule that a standard which names a mechanism carries its **build state** (`built
and verified on <date> by <command>` / `not built`) and a check that can fail.

## 2. Where the SDLC actually breaks, phase by phase

**Requirements.** Good: `functional_requirements`, `acceptance_criteria`, drafter/advisor agents
exist and `orchestrator_role.md` step 2 says to use them. Gap: nothing forces a lane card to cite an
acceptance-criteria ID, so "done-when" is prose and close-out reports "what happened" rather than
pass/fail against criteria.

**Planning / backlog.** `priority_classification.md` and `task_sizing.md` exist; **no artifact
applies them**. The backlog is spread across `docs/REPOS.md` (snapshot dated 2026-09-14), a stack
of `NEXT_STEPS_*` / `SESSION_ROUNDS_*` files, the 93-task Fleet Status tree whose only statuses are
`done`/`unknown`, handoff files' "unowned" sections, and memory. There is no one ranked, sized list
the PM dispatches from. That is why arriving sessions got an improvised backlog offer (pm_role's own
"why the narrow version did not hold").

**Implementation.** Strong: worktree discipline, one PR per repo, lane cards, the never-list.
Gap: the shared MasterThread checkout is a live landmine (782 staged files on a branch with no
commits); a written rule ("never work in the shared checkout") is the only guard. A `SessionStart`
hook that refuses to run in a dirty shared checkout would be a technical guard.

**Verification.** This is the estate's real strength *and* its most fragile property. Six PM
assertions were corrected in one evening, **every one by another session running something**. The
error-correction is social: it exists because peers are present. Any headless design that removes
peers removes the only mechanism that has demonstrably worked. Structural gaps: `gate-execution-
auditor` shows green checks that ran nothing; four of eleven open PRs have zero CI checks; no repo
records a review decision.

**Release / merge.** `merge_authority.md` is sound; the seat is **unstaffed** (no `role: "merge-
authority"` row live) and merges happen by owner click. Eleven open PRs, all `MERGEABLE`, all
waiting on him. Route B (seat) is effectively route C in practice.

**Operate / learn.** `docs/LESSONS.md` is rich and write-heavy: many entries read "not yet
promoted, single occurrence". Promotion needs a worker lane and nobody owns the count of
"seen". The loop is open at the promotion end.

## 3. The PM control loop as it actually runs vs as written

`pm_role.md` says event-driven: report → update register → verify with `gh` → unblock → keep
workers loaded → check limits → staff the seat. In practice (c5's and f8's own accounts): the PM
spends its context re-arming watchers, re-deriving facts other sessions already established (hence
`ESTATE_FACTS_CACHE.md`, which is a good artifact and also a symptom), relaying cards to the owner,
and hand-verifying claims one `gh` call at a time. The deterministic parts are done by hand; the
judgment parts are rushed.

Two things would invert that: (a) the register as data (§0.1) so state is looked up, not
reconstructed; (b) the deterministic checks as Haiku fan-outs on a schedule (§0.5), so the PM reads
diffs, not raw state.

## 4. The owner as bottleneck — classification of the 30 cards

Classified by a read-only subagent from the 10 open + 20 follow-up-pending cards (store read
directly, 00:45Z):

| Class | Count | Meaning |
|---|---|---|
| R1 his by right | **19** | live host, credential, money, repo security setting, purchase, business/legal call |
| R2 his by governance | **7** | `standards/sessions/*` / `policies/*` PRs (route C) |
| A1 his by accident — classifier denial | **2** | runner `apt-get install unzip gh` (`[Remote Shell Writes]`); `git worktree remove --force` (already clicked — worktrees are gone from disk and `git worktree list`) |
| A2 his by accident — no tool | **1** | OVH VPS relabel (token deliberately read-only); owner already said "It looked wrong — need better links" and the card was never rewritten |
| Q a question disguised as an action | **1** | faction boot-test "name a time window" |

Rough owner attention: **8–10 hours**, dominated not by clicks but by two in-game windows (faction
boot test, pricing Session 3) and three multi-step vendor-dashboard jobs (Cloudflare tunnel +
Access app, OVH firewall, OVH bucket/billing).

**Highest-leverage sequencing (from the blocked-work sweep, all live-verified):**

1. **Two complementary clicks restore Claude review across 13 repos, and neither alone does it:**
   `AEGIS-Flip-Actions-Token-4-Repos.cmd` (never run — `default_workflow_permissions` is still `read`
   on MasterThread/ops-infra/ops-platform/ops-policies, and the flip is *already decided* on card
   `actions-token-flip-scope-extension`) **plus** `AEGIS-Fix-Runner-Unzip.cmd` (never run — no log;
   runner `vps-core` is online and still missing `unzip`/`gh`). Nothing on the board tells him these
   are a pair. It should.
2. **Vault credential:** `VaultTunnelKey.cmd` option 1 — plaintext credential still on disk at
   `~\.cloudflared\48cb0a9e-….json`, no encrypted copy under `%APPDATA%\AEGIS` (checked 00:55Z).
   Then recovery key **before** backup credentials (ops-infra #26 ordering).
3. **Owner's own reminder request is unowned:** on the hardware-key card he wrote "schedule to
   return next Thursday to remind me" — no session has a reminder mechanism, so this will be
   re-asked instead of resurfaced. A dated action card (`notBefore`) is the cheapest fix.
4. **Two cards carry unverifiable vendor-UI steps** (`action-ovh-relabel…`, the Cloudflare Access
   app steps on `action-cloudflare-vault-tunnel…`) — exactly the postmortem shape. Neither has been
   re-derived; the first already has the owner's "looked wrong" on it.

**No open card currently disagrees with live state** — the two false "Merged" claims from earlier
(MasterThread #80/#81) have since become true. Branch protection was live-verified as actually
applied (log present, `enforce_admins: true` on six repos).

Rule of thumb for the split, for the PM to apply going forward:

- **His by right (R1):** live host change, credential/secret, money, repo security setting, purchase,
  a genuine business/legal call. These stay. Batch and sequence them; never one ping per item.
- **His by governance (R2):** `standards/sessions/*`, `policies/*` PRs — route C by decision. Keep,
  but stack them so one click lands several (github-stacked-pr-merge pattern).
- **His by accident (A1/A2):** a classifier denial blocked a session, or no tool exists. These are the
  PM's backlog, not the owner's: each one becomes either an allow-rule request (a card he answers
  once, permanently) or a tooling lane.
- **Questions disguised as actions (Q):** re-derive before re-explaining; an owner "I don't know how"
  is a defect report about the card.

## 5. Verification chain: rules to promote now

1. **Text is a claim, whoever it is addressed to.** Instructions for a human get the same evidence
   standard as facts for a machine (postmortem rule; promote to `decision_queue_standard.md` now
   rather than waiting for a second occurrence — the cost of the failure mode is the owner's trust).
2. **A gate is evidence only for what it ran.** Already in `orchestrator_role.md`; make it
   checkable: `gate-execution-auditor` runs at start of every round, and any repo whose required
   checks are `[]` or a template stub is reported as UNENFORCED in the digest until fixed.
3. **Two independent readers before a register write or an owner relay.** Not two people reading
   the same text — one reading, one *running* (a `gh` call, a `git show`, an SSH read). This is the
   social error-correction made structural, and it is the precondition for anything headless.
4. **Every "resolved"/"merged"/"done" carried forward names its artifact** (PR URL + merge SHA, card
   version, file + commit). A handoff repeating a state without an artifact is a finding.
5. **Age is a defect.** Every cached fact carries `checkedAt` + the re-check command
   (`ESTATE_FACTS_CACHE.md` already does this — make it the standard for register rows too).

## 6. Headless workteams: a readiness ladder, not a switch

The owner's goal: "the sooner we get to headless automation, the less I will be creating sessions."
The blocker is not capability. It is that the org's safety today is peers arguing, and headless
removes the peers. So widen unattended *verification* first, unattended *action* last, and make
each rung's exit criterion something a script can check.

| Rung | What runs unattended | Guard | Exit criterion to climb |
|---|---|---|---|
| **L0** (today) | Nothing. Interactive sessions + subagents. | Human sees every Bash call. | — |
| **L1 Reporters** | Read-only Haiku reporters (`pr-state-sweep`, `gate-execution-auditor`, `plan-status-check`, `worktree-sweep`, `check_agent_sync.py`) via `Invoke-ReadOnlyAgent.ps1` on a Windows scheduled task, writing `prs`/`health` rows to Fleet Status with `checkedAt` + command. | `readonly.settings.json` deny-list **plus** per-agent `--allowedTools` allow-list (the verified load-bearing finding: deny-only under `dontAsk` denies everything). Hard timeout, `--max-budget-usd`, subscription token only, no MCP. | 7 days of runs with zero `permission_denials` for legitimate reads and zero destructive attempts in logs; the `prs` panel's writer problem is closed. |
| **L2 Cross-checking verifiers** | Two reporters per fact from different evidence paths (e.g. `gh pr view` vs `git ls-remote`; branch-protection API vs a run log) and a deterministic comparator that writes only on agreement and flags disagreement. | Disagreement → card, never a write. | One month with disagreement rate measured and every disagreement explained. |
| **L3 Drafters** | Headless drafter agents produce PRs (lane cards, register row proposals, LESSONS promotions, handoff drafts). Never merge. | `Agent(claude)`/`Agent(general-purpose)` denied; one PR per repo; `automerge-preflight` before push. | PR rejection rate by the seat below an agreed bar; no drafter PR ever touched `standards/sessions/*` or `policies/*` unasked. |
| **L4 Deterministic merge** | Only the automerge job in `claude-review.yml`, only in opted-in repos, only route A. Still no headless *session* merges. | Required checks that actually run (gate audit UNENFORCED = 0 for that repo). | Owner decision per repo. |

**Never headless**: `live-reviewer`, `vuln-scan-active`, anything with a DPAPI key dependency off
this machine, anything needing an OAuth connector, and any Route C merge — `headless_agent_
permissions.md` already lists these; the ladder does not change it.

**The permission-denial queue (§0.4) is what makes L1–L3 survivable**: a headless run that hits a
denial files a card and stops, instead of failing silently or being routed around.

## 7. Draft register rows (for the PM to write; `workstreams` collection)

*(Drafted from the c5 handoff, Fleet Status, and the PR sweep. The PM verifies each against `gh`
before writing — the `verified` field is the PM's, not mine.)*

| name | goal (current milestone) | priority | repos | lead | origin | now / next / later | state | blocker | mergeRoute |
|---|---|---|---|---|---|---|---|---|---|
| pm-process | Register live; denial queue in standard; executability rule promoted | P1 | MasterThread | github-9d | owner-started | advisory → standards PR → headless L1 pilot | active | none | C |
| ci-review-gates | Every repo's required checks actually run; UNENFORCED=0 | P1 | core, services, site-badlands, payments, website | unstaffed | pm-dispatched | fix `gate-execution-auditor` signature (#106) → runner unzip click → per-repo required-check decisions | blocked-owner | runner install click; gates card | C then B |
| vault-backups | Recovery key + credentials landed; first restic snapshot verified | P0 | ops-infra | unstaffed | owner-started | VaultTunnelKey option 1 → recovery key → credentials → snapshot | blocked-owner | VaultTunnelKey click, OVH steps | C |
| roster-governance | `docs/AGENTS.md` generated not hand-kept; sync check in CI (R4/R6) | P2 | MasterThread | unstaffed | pm-dispatched | land #106 → finish `generate_agents_md.py` → CI `--check` | blocked-merge | #106 owner click | C |
| faction-quests | Six questlines merged inactive; rep flags flipped after boot test | P2 | site-chernarus | unstaffed | owner-started | #115 → #117 (boot test) | blocked-owner | boot-test card | C |
| payments-module | Plan PR #1 merged; Session 1 scoped | P3 | payments | unstaffed | owner-started | #1 merge → Session 1 card | blocked-owner | financial repo, owner merge | C |
| headless-pm-platform | `bin/start.js` runs; register/merge-audit implemented or pm_role text corrected to "not built" | P2 | ops-platform, MasterThread | unstaffed | pm-dispatched | correct pm_role claim → L1 pilot results → decide build vs drop | active | none | B / C |

## 8. Agents to scope (none exist today for these jobs)

Per the standing rule — "if a piece of work has no agent that fits it, scope and create that agent":

| Agent | Role | Model | Tools | Job | Never |
|---|---|---|---|---|---|
| `owner-instruction-verifier` | A (advisor) | Sonnet 5 / medium | Read, Grep, Bash (read-only gh/git), WebFetch (vendor docs) | Given a card's steps, trace each to a primary source or runnable command; for every named UI screen/menu, fetch current vendor docs and record the read date; ask what artifact each step yields and whether the next consumes it. Verdict: EXECUTABLE / UNVERIFIED-STEP n / IMPOSSIBLE-STEP n. | Edit the card; relay to the owner. |
| `register-verifier` | R (researcher) | Haiku 4.5 | Bash (gh, git show), ArtifactData read | For each `workstreams` row, check `now`'s PR/branch state live and report rows whose `state`/`blocker` disagree with `gh`; report rows with empty `next` for staffed workstreams; report rows older than the last state-changing event. | Write the register. |
| `denial-card-drafter` | D (drafter) | Haiku 4.5 | Read | Turn a classifier denial (tool, exact command, what it would change, rollback) into a `decision_queue_standard`-shaped action card with `category: permission/denial`. | File the card. |
| `standard-buildstate-checker` | R | Haiku 4.5 | Bash (git ls-tree/show), Grep | For every mechanism a `standards/**` file names (a script path, a tool, a collection, an agent), check it exists on `origin/main` / in the live store and report the ones that do not. | Edit standards. |

Each goes through `agent-automation-gatekeeper` and lands via `claude-agents/` (repo is truth) —
not written into `~/.claude/agents/` first.

## 9. Implementation plan for this workstream (research → plan → scope → execute)

| Phase | Deliverable | Repo / route | Size | Depends on |
|---|---|---|---|---|
| P0 (now) | This advisory; register rows drafted (§7); PM arms heartbeat tick (§0 layer A) and roster monitor | file + PM cron, none | S | — |
| P0 | Card: PM-seat permission allow list (§0 layer C) — one owner click, permanent | Decision Queue via PM | XS | — |
| P1 | `pm_role.md`: replace "does not poll" with the heartbeat tick; add `dispatchable` register field; add the "PM not worker" checks; mark the headless-PM paragraph `not built` | MasterThread, route C | S | branch off origin/main |
| P1 | `tools/pm-heartbeat/`: `pm-heartbeat.json` writer + `Watch-PmHeartbeat.ps1` scheduled-task watchdog (§0 layer D); scheduled-task registration is an owner click-file | MasterThread + `GitHub\AEGIS-*.cmd` | S | — |
| P1 | `decision_queue_standard.md`: permission-denial cards; executability check required for action cards (postmortem promotion) | MasterThread, route C | S | branch off origin/main; avoid `docs/LESSONS.md`, `worker_role.md` until #93/#101/#104 land |
| P1 | `pm_role.md`: build-state marker on the headless-PM paragraph ("not built; see ops-platform PLAN"), register instantiation under default, start-of-round fan-out, denial batching | MasterThread, route C | S | same |
| P1 | `headless_agent_permissions.md`: remove/mark the nonexistent `overnight-sweep-supervisor.ps1` reference | MasterThread, route C | XS | — |
| P2 | New `standards/sessions/headless_readiness_ladder.md` (§6) with per-rung exit checks | MasterThread, route C | M | P1 |
| P2 | Four agent definitions (§8) via `claude-agents/` after `agent-automation-gatekeeper` | MasterThread, route B (agents are seat-merged per `pr81-q3`) | M | #106 landed (path collision) |
| P3 | L1 pilot: scheduled task running `pr-state-sweep` + `gate-execution-auditor` through `Invoke-ReadOnlyAgent.ps1`, writing `prs`/`health` with `checkedAt`; 7-day log review | MasterThread tools + Fleet Status; scheduled task is an owner click (card) | M | P2 agents; `--allowedTools` per agent |
| P3 | `reasoner.js`: add `--settings/--permission-mode dontAsk/--permission-prompts none`, or mark the package dormant in its README | ops-platform, route B | S | owner decision: build or drop the headless PM package |

**Owner decisions this plan needs (each will be its own card, via the PM):** register location
(confirm Fleet Status default); whether the Claude review is a gate or advisory (already carded by
f8 — not duplicated); build vs drop for `packages/project-manager`; approve the L1 scheduled task.

## 10. Metrics the PM should read every round (so the PM role is itself verifiable)

- Owner: open action cards, split R/A/Q; median age; clicks completed per click-session.
- Flow: open PRs by route; PRs waiting on owner >48h; unstaffed workstreams with priority ≤P1.
- Verification: false assertions caught per round (from LESSONS entries); UNENFORCED gates count;
  register rows stale > last state change.
- Learning: LESSONS entries with `Seen ≥ 2` not yet promoted.
- Fleet: live sessions with no `sessions` row; ghost rows; orphaned watcher processes.

A standard nobody can check is the same shape as a gate nobody requires. Every rule above names
the check that would fail if it were ignored.
