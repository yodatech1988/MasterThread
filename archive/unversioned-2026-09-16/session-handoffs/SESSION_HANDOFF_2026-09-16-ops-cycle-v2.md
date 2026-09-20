# Handoff — Autonomous ops cycle PM (round 2, supersedes 2026-09-16's)

**You are the project manager for the autonomous ops cycle program.** Sonnet 5 / low effort. You
manage; lanes do the building. Read this file first, not the 2026-09-16 one — this one reflects a
short but eventful round: a stale-watcher collision resolved, one lane landed, one review dispatched
and not yet returned.

---

## 0. Do these two things before anything else

**1. Start the usage watcher** (required of every orchestrator; do not skip):

```
Monitor  command: MT=<USER_HOME>/GitHub/MasterThread; N=ops-cycle-pm; git -C $MT fetch -q origin main; git -C $MT show origin/main:tools/usage-monitor/usage-watch.ps1 > "$APPDATA/AEGIS/usage-watch.$N.ps1" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$APPDATA/AEGIS/usage-watch.$N.ps1" -HandoffRoot <USER_HOME>/GitHub -Name $N -Program "autonomous ops cycle PM" 2>&1 || echo "USAGE-ERROR could not load or run usage-watch.ps1 from MasterThread origin/main"
         description: Claude usage tiers for ops-cycle-pm
         timeout_ms: 1800000
```

**If registration fails with "another live watcher (pid NNNNN) is already registered as
'ops-cycle-pm'"**: don't just rename yourself and move on, and don't assume it's a live session
either. This round it turned out to be an orphaned watcher script from a session that had already
exited (verified via `Get-CimInstance Win32_Process -Filter "ProcessId=NNNNN"` — the command line
showed it was literally just `usage-watch.ops-cycle-pm.ps1`, no Claude session behind it). Sequence
that worked: (1) `ListAgents` and message every peer to rule out a live duplicate, (2) inspect the
PID's command line before touching it, (3) only kill it once confirmed to be a bare watcher script
with no owning session, (4) re-register cleanly under the real name. Don't skip step 1 — killing a
process on say-so alone, without checking whether a real session still owns it, is the wrong
default.

Re-arm with the same `-Name` every ~30 min (it expires on its own timeout, that's normal, just
re-arm). Act on `USAGE TIER` lines: 80 = stop dispatching, 90 = pause lanes, 97 = write the next
handoff, 98 = commit it, 99 = stop. `USAGE-ERROR` (429s from the endpoint) means usage is
genuinely UNKNOWN, not just unlucky — treat it as high and hold all new dispatch until a clean
`USAGE-OK`/`USAGE START` line comes back. This happened twice this round and self-resolved within
a few minutes each time; no manual `/usage` check was needed either time, though the fallback if it
doesn't self-resolve is `<USER_HOME>\GitHub\MasterThread\tools\usage-monitor\check-usage.ps1` in
a real terminal (this session couldn't run it — sandboxed, working directory locked, no APPDATA
read — so it has to be you or a less-sandboxed session).

**As of this handoff:** clean read was 12-13% of the 5-hour window, 10% weekly. **Four
orchestrators now share this account's limit**: `ops-cycle-pm` (you), `agent-roster-pm` (finished
its round — see §3), `sessionless-unblock-20260915` (still active, see §3), and a short-lived
`ops-cycle-pm-2` (this session's own temporary name during the collision, already stopped — ignore
if you see it referenced anywhere, it no longer exists). You're the aggregator from 80% on.

**2. Read the authority document.** Still the single source of truth for design and the 93-task
work tree — unchanged this round, nothing in it was edited:

- `Artifact` tool, `action: "read"`, `url: https://claude.ai/artifact/WZsmRodvsHAbVFj54JghKf`
- Status report for the owner: `https://claude.ai/artifact/FNaa1dZWGDd6sN9vsuvhcZ`
- Tiered dispatch checkpoint (Scout/Builder/Operator model, real tool-call cost data):
  `https://claude.ai/artifact/6uWe34wXL6b9aERnrcnYdC`

**3. Also load `MasterThread` docs/AGENTS.md** for the T4 read-only agent roster (`collision-check`,
`pr-state-sweep`, `plan-status-check`, etc. — installed globally, use them instead of doing drift
checks by hand). Unchanged this round except: `agent-roster-pm` (github-5a) landed a third small
batch of agents mid-round (`voice-transcriber`, `voice-synthesizer`, `quote-generator`, plus a
maintenance-window-gated vuln-scanning capability — see `ops-infra#9`, open, not mine, not
reviewed by me).

---

## 0.5 OWNER DIRECTIVE — 2026-09-15 — TOP PRIORITY, ahead of the §4 queue

Relayed from `github-4b`. Jeremy put this above everything currently queued. Stated goal, his
words: **"so that we prevent future errors"** and **"machine learning development as we work."**
Three parts, A–C. A and B are the priority; C is the concrete gap that triggered it.

### A. Build the Tier-1 procedure skills

We have **70 agents and zero skills**. The roster is almost entirely *advisors* (pass/fail against
a MasterThread standard) and *drafters* (produce text) — read-only, delegated, returning a verdict
after the fact. What does not exist is the other half: **procedures the acting session runs
itself**, loaded into its own context at the moment it acts, with a never-list attached.

This matters because every incident in memory is procedural, not judgmental. No advisor agent
fires in time to stop any of these:

| Memory | Failure |
|---|---|
| `aegis-worktree-remove-no-force` | `--force` removal lost uncommitted work |
| `parallel-session-collision` | a second session reset another session's worktree |
| `aegis-check-pr-state-before-followup-push` | pushed onto a merged PR, stranded 2 commits |
| `github-stacked-pr-merge` | stacked merges landed in parent branches, not main |
| `gh-secret-set-stdin-newline-bug` | piped secret got a trailing newline |
| `aegis-usage-monitor-tool` | the watcher is step 0 of every round and still gets skipped |

Tier 1, in build order. Each one has a real incident behind it:

1. **`round-start`** — arms the usage watcher with a unique `-Name`, reads the newest
   `SESSION_HANDOFF_*.md` + `docs/REPOS.md`, re-verifies every lane's "waits on" against live `gh`
   (docs go stale within hours), triages P0–P3, sizes S–XL, gates the largest item against the
   window's remaining budget. Ends in a dispatch plan. Calls `usage-window-reporter`,
   `plan-status-check`, `pr-state-sweep`.
2. **`dispatch-lane`** — runs `New-ParallelWorktrees.ps1` itself (a worker never picks its own
   folder), runs `collision-check` + `ListAgents` first, emits the exact `worker_role.md` lane
   card, enforces one open agent PR per repo, assigns model/effort from the 5-row table.
3. **`land-pr`** — `gh pr view --json state,files,statusCheckRollup,mergeable` **before** any
   follow-up push; `diff-reviewer` vs `live-reviewer` chosen by scope (Opus only for
   live/creds/money/death-path/contract); stacked PRs land via one top-branch→main PR verified
   with `merge-base --is-ancestor`; never `--admin`, never self-approve past a stale
   CHANGES_REQUESTED; updates the PLAN.md Status row after. Covers three memory entries at once.
4. **`owner-click`** — the Jeremy-facing boundary. Generates a `GitHub\AEGIS-*.cmd` that shows the
   diff and requires typing YES, opens it, then reads the result read-only. Encodes "never hand
   him git or terminal steps" and the auto-mode classifier limits. Currently improvised
   differently every time.
5. **`round-closeout`** — writes the next handoff (merged / in flight / paused / owner questions),
   refreshes changed memory files, emits one prompt per next session headed with model and effort.

Tier 1 alone would have prevented five of the six rows in the table above.

Scoped but **not** approved for build yet — do not start these without a further owner call:
`go-live`, `boot-test`, `secret-rotate`, `plan-session`, `deliver-lane`, `verify-against-origin`,
`mod-review`, `econ-change`, `new-agent`.

**Location: `MasterThread/skills/`, synced out to `~/.claude/skills`** — versioned from day one,
for the reason in the defects note below.

### B. Every agent must emit a lessons-learned block

New mandatory section in every agent definition, alongside the existing Purpose / Inputs / Steps /
Output / Never. The agent ends its run with:

- **Assumption that turned out false** — what it expected to find vs what was actually there, or
  the literal word `none`. (Memory `aegis-verify-invariants-against-real-data` exists because
  several "obvious" DayZ XML invariants were false.)
- **Rule candidate** — one line, written as a check that could have fired *earlier* than this
  agent did.
- **Where it belongs** — a named skill's never-list, a MasterThread standard, or a memory file.

The collection is the easy half and is worthless alone. **The loop is the promotion step**, and
that is the PM's job: at round close-out, read the round's lessons, and promote anything seen
twice into the relevant skill's never-list or the governing standard. A lesson that stays in a log
is not learning. Suggested ledger: append-only `MasterThread/docs/LESSONS.md`, one row per lesson
with round date, source agent, and promoted-to (or `pending`).

Retrofitting 70 agents is mechanical and should be a lane of its own, not hand-done by the PM.

**Seed row for the ledger, already rediscovered twice** (per the PM's correction this round): the
Anthropic Admin API's Cost Report endpoint has three sharp edges — amounts are in **cents**,
`ending_at` is **required** and clamps to the last complete UTC day, and `limit` is **capped at 31**
for daily buckets. Two sessions have separately burned time rediscovering this; per part B's own
promotion rule (seen twice → promote), this should go straight into `LESSONS.md` as `promoted`, not
`pending`, and into whichever standard/skill ends up owning Anthropic Admin API calls.

### C. Dedicated drift agent — owner asked for this explicitly

Drift keeps causing silent reverts and there is no agent for it. `plan-status-check` covers exactly
one axis (PLAN.md vs live `gh` state); the new agent should call it rather than duplicate it, and
cover the three axes nothing watches:

- **Live vs repo `main`** — the site-chernarus Contract 8 / Session 17 class. `orchestrator_role.md`
  lists "running a drift pull while main is ahead of live" in its never-happens list because it
  silently reverted merged fixes **twice**.
- **Vendored copy vs upstream** — memory `aegis-guid-drop-fix`: site-chernarus's live copy of
  `restart_orchestrator` is missing a newer core-only `TransportError` guard. Still true today.
- **Local checkout/worktree vs `origin`** — memory `aegis-verify-before-merge`
  ("diff against origin/main, not a stale local checkout") and `aegis-ovh-vps-migration`
  ("check worktree drift first").

Hard constraint: **read-only, and it must never pull, sync or reconcile** — it reports divergence
with direction ("live is ahead of main on X", "main is ahead of live on Y") and stops. Reconciling
is exactly the action that caused the two reverts.

### Two defects found while scoping — both worth a small lane

1. **`MasterThread/docs/AGENTS.md` does not exist.** `agent-automation-gatekeeper` is grounded in
   it as "the org's T4 agent roster" and is therefore checking against a missing file. Verified by
   directory listing, 2026-09-15.
2. **All 70 agents live only in `~/.claude/agents` and are not in git.** No backup, no history, not
   portable to another machine. Back them the same way as the new skills.

---

## 1. What actually happened this round

1. **Collision and resolution** — see §0's box above for the mechanics. Net effect: no work was
   lost, no duplicate lanes were dispatched, ~20 minutes of PM time went into confirming it safely
   rather than assuming either "it's fine" or "kill it" up front. Worth the time; a wrong guess
   either way (ignoring a real live duplicate, or killing a live session's watcher) would have been
   worse.
2. **Session 8 dispatched and landed as a PR** — `ops-infra#10` (open, NOT merged), "platform
   Postgres and the hash-chained audit log." Opus 5/high, ran in its own worktree
   (`_wt-ops-infra-session8-postgres-audit`, branch `agent/ops-infra/session8-postgres-audit`,
   created via `New-ParallelWorktrees.ps1` before dispatch — do this yourself before every lane,
   per `aegis-parallel-worktree-system`). ~232k tokens, 77 tool calls, ~24 min wall clock.
3. **Live-tier review returned: CHANGES REQUESTED.** Posted in full as a PR comment:
   https://github.com/yodatech1988/ops-infra/pull/10#issuecomment-5691422656. **Do not merge or
   apply PR #10 as-is** — see §2 for the four blocking items. This is the single most important
   thing in this handoff: the PR looked done (all 3 lane-run "done when" checks passed, clean
   digest, careful SQL) but an independent Opus-tier review found two apply-time failures and two
   defects in the hashed write format/contract itself. This is exactly why Session 8-class PRs get
   routed to `live-reviewer` instead of `diff-reviewer` — worth remembering for future contract-
   defining sessions, not just this one.
4. **Discovered mid-round, not mine**: `ops-infra#9` (open) — "maintenance-window gate for active
   vuln testing + vps-drift-checker agent," from `agent-roster-pm`'s round. Two open PRs in
   ops-infra right now: #9 and #10. Neither reviewed/merged by me. Don't confuse #9's scope
   (maintenance-window tooling) with #10's (Postgres/audit log) when picking up review work.

---

## 2. Session 8 (`ops-infra#10`) — full detail for whoever reviews or merges it

**Built:** `db/audit/0001_audit.sql` (hash-chained `audit.event` table: `prev_hash`/`row_hash`
covering full payload via a shared `audit.row_digest()` used by both writer and verifier so they
can't drift; `audit.append()` as `SECURITY DEFINER` + `pg_advisory_xact_lock`; `audit.verify()`
returns the first broken `seq`; `audit.head()` for an off-host anchor; append-only triggers; roles
`audit_owner`/`audit_writer`/`audit_reader`), `db/audit/daily_verify.sql`, and an Ansible
`postgres` role: digest-pinned image (`postgres@sha256:051f7b7b…`, 17.11), `User=999:999`, zero
added capabilities, data on `/srv/vault/platform/pg/data`, **no TCP listener** (socket only, in a
0700 zone-private dir), read-only root-owned `pg_hba.conf`/`pg_ident.conf`, two root-owned user
timers (verify 03:30 UTC, `pg_dump` 03:45 UTC), wired into `plays/vault.yml`, AppArmor rules added
via Session 11's existing hook in `host_vars/personal-vault.yml`.

**Done-when: 3 of 5 proven with real command output in the PR, 2 implemented but unrun** (the lane
had no host access by design — these fail the Ansible apply if they don't hold, so the apply itself
is the proof):
1. ✅ 1000 events, 4 concurrent writers, `verify()` clean.
2. ✅ writer role: UPDATE/DELETE/TRUNCATE refused (and raw INSERT/SELECT too — writer gets `EXECUTE`
   on `append()` only, nothing else).
3. ✅ tamper one row in a throwaway copy → `verify()` returns exactly that `seq`.
4. ⏳ Session 2's container security checks, reapplied to the Postgres PID — written, not run live.
5. ⏳ `findmnt -T` confirming the data dir is on the LUKS mount — written, not run live.

**Live-review verdict: CHANGES REQUESTED, four blocking items** (full detail in the PR comment
linked in §1.3 — line numbers, re-derived digest verification, 10 additional non-blocking items).
Summary for planning the next lane:
- **B1 (apply-time, will fail first run):** the AppArmor rule targets `/var/run/postgresql`, but
  `postgres:17-bookworm` symlinks `/var/run` → `/run`, so the kernel mediates `/run/postgresql` and
  the rule never matches — Postgres gets denied its own socket dir under enforce mode and fails to
  start. Fix is a one-line glob change (`"/{,var/}run/postgresql/{,**} rwlk,"`).
- **B2 (apply-time, will fail first run):** `tasks/main.yml`'s first task runs `findmnt` against
  `/srv/vault/platform`, a directory nothing has created yet at that point in the play (the role's
  own directory-creation task runs later). First apply dies at task 1.
- **B3 (write-format defect, fix before any row exists):** `actor`/`kind` are unconstrained text
  fed into the hash via a delimiter join with no character exclusion — a row containing the
  delimiter byte in `actor` can be later rewritten by a superuser into a different meaning with the
  *same* `row_hash`, defeating the tamper-detection guarantee the whole design exists for. Fix:
  `CHECK` constraints excluding control characters, enforced in both the schema and `append()`.
- **B4 (contract defect, matters once Phase 2 writers exist):** `audit.append()`'s snapshot can go
  stale under REPEATABLE READ/SERIALIZABLE isolation (the advisory lock itself is correct; the gap
  is when the snapshot is taken relative to it), letting an honest concurrent writer under a
  stricter isolation level fork the chain — which then reads as tampering to `verify()`. Fix is a
  guard in `append()` requiring READ COMMITTED.

Also flagged, not blocking but important context for whoever picks this up: peer auth means any
process resolving to uid 999 inside the platform zone arrives as Postgres **superuser**, and this
is a single shared ledger across all five zones — so a platform-zone compromise becomes superuser
over every zone's audit trail. Write this into the Contract explicitly; Session 9/10 should move
`vault-pg-verify`/`vault-pg-dump` off superuser onto dedicated roles. Separately: the chain's actual
tamper-evidence only completes once Session 9 (restic, off-host anchor) lands — until then a
superuser can rewrite the chain and the local anchor file together, undetected.

**Recommended next step, not yet dispatched:** a small Sonnet/medium follow-up lane against the
same worktree/branch (`_wt-ops-infra-session8-postgres-audit`, `agent/ops-infra/session8-postgres-audit`)
to apply B1-B4, re-run the three "done when" tests plus a live apply attempt to actually clear B1/B2
(this lane had no host access — a follow-up may need it, or at minimum a dry-run/`--check` against
the real inventory), and push to the same PR. Don't spin up a fresh worktree for this — the branch
already exists and is open.

**Three decisions flagged by the original lane, still open, separate from the review findings:**
1. Writer role is `EXECUTE`-only, not a raw INSERT grant. The task card said "can only INSERT"; the
   Contracts doc says `EXECUTE` on `append` and nothing else. The lane followed the Contract
   (a raw INSERT grant would let a writer forge `prev_hash`/`row_hash`) — reasonable call, confirm
   it rather than silently accepting.
2. Peer auth inside the platform zone maps by uid. Fine today (nothing else runs as uid 999), but a
   future platform-zone container also at uid 999 would arrive as Postgres superuser. Needs an
   explicit `pg_ident` restriction or a move to SCRAM (bigger, stores a credential) before Phase 2
   adds more platform-zone services. Not urgent, but don't let it get forgotten before Phase 2.
3. No superuser password — `POSTGRES_HOST_AUTH_METHOD` + read-only `pg_hba.conf` instead of a
   stored credential, since the DB has no TCP listener at all. Reversible if a password is
   preferred.

**Also:** applying this PR restarts the platform zone's containers (AppArmor profile change) and
adds paths AIDE watches — it should land **after** the AIDE baseline refresh (click-through step 1,
still not done — see §4), not before, or the new paths will show up as unexplained AIDE drift.

---

## 3. Peer orchestrators, as of this handoff

- **`agent-roster-pm`** (github-5a) — reported its round done: 9 repo PRs total, all merged or open
  for review, nothing left running. One of those PRs is `ops-infra#9` (see §1.4) — not reviewed by
  me, pick it up if nobody else has.
- **`sessionless-unblock-20260915`** (github-34) — as of last contact, still working `gh-federation`
  Session 4 (claude-agents, discord-community enqueue, one lane running) and had just landed
  `aegis-poi` Session 6 (`PR #11`, merged). Explicitly said it is not touching
  ops-infra/ops-platform/ops-policies/ops-business/ops-household or anything Discord/personal-vault
  related — no overlap with the ops-cycle queue. Re-check with it if you need a current status,
  don't assume this is still accurate by the time you read it.
- A third, unrelated session (`github-b5`) was mid-round on a DayZ companion/hireable-NPC design
  task in `aegis-mods` — not an orchestrator, no watcher, no queue overlap. Mentioned here only so
  you don't mistake it for another PM.

---

## 4. The queue, unchanged in substance from 2026-09-16's handoff

Nothing below moved this round except Session 8 (now built, awaiting review/merge — see §2). Full
detail is in the 2026-09-16 handoff §4 if you need the reasoning; summary:

1. **Session 8 — Postgres and hash-chained audit log.** Built, PR open (`ops-infra#10`), pending
   review (see §1.3) and the three flagged decisions (§2). Not merged, not applied to the real host.
2. **Sessions 5+6 — Cloudflare Tunnel + Access, then close port 22.** Still the single biggest
   blocker, still blocked on the owner (classifier denies DNS/domain/cert changes; needs an explicit
   owner decision per 2026-09-16's §4.2 options a/b/c). Not touched this round.
3. **Session 9 — restic backups.** Ready with a caveat (OVH Object Storage primary, verify whether
   the PC append-only copy actually needs the Sessions 5/6 tunnel or can use something else in the
   interim). Not touched this round — next thing to dispatch once Session 8 clears review, if
   Sessions 5/6 are still stuck on the owner.
4. **Session 10 — restore test.** After 8 and 9.
5. **Phase 2 build-out.** Blocked on SPIRE/federation (needs Session 10) and owner Console/CI steps.

---

## 5. Not deployed / not done — unchanged from 2026-09-16

`ops-platform` (154 tests) and `ops-policies` are fully built and idle until SPIRE/federation exist.
The 8-step owner click-through (`<USER_HOME>\GitHub\Complete-OpsCycleOwnerTasks.cmd`) is
untouched this round — AIDE baseline refresh (step 1) is still the most urgent one given §2's note
about Session 8's apply colliding with AIDE drift.

---

## 6. Standing rules — unchanged, all still in force

Same table as 2026-09-16's handoff (nothing AEGIS-branded on the vault; no git/terminal steps for
Jeremy; no stacked PRs; zero cost first; no PATs/static keys; verify before merge; don't re-raise
settled decisions; no local DayZ boots while Jeremy plays; classifier denials are decision points,
not retry loops; test capability, don't assume it from "who" in the work tree). Nothing new to add
this round except the collision-handling sequence in §0.

---

## 7. Waiting on the owner (unchanged, carried forward)

1. Cloudflare classifier decision (§4.2 in 2026-09-16's handoff) — still the actual critical path.
2. AIDE baseline refresh — now also gates Session 8's apply cleanly, see §2.
3. ~~The 4 Anthropic workspaces~~ — **correction (github-4b, verified via Admin API this round):**
   these already exist, created 2026-09-16 01:50 UTC. Spend limits/key-creation-disable on them is
   still an open owner step.
4. Discord private server, GitHub 2FA method, OVH storage separation.
5. Confirm the CI VPS once it exists (owner provisioning it himself per a peer session's relay,
   unconfirmed as live).
6. Session 8's three flagged decisions (§2) — new this round, small, worth a quick answer.
7. Longer-tail Phase 4/5 items, `ops-policies/docs/OPEN_QUESTIONS.md`'s 31 open questions — not
   urgent.

---

## 8. Worktrees

Safe to prune now (PR merged, check `git status` first, never `--force`): same list as 2026-09-16 —
`_wt-ops-infra-apparmor`, `_wt-ops-infra-session7-encryption`, `_wt-ops-platform-work-issue-form`,
`_wt-MasterThread-task-sizing-note`.

**Not safe to prune**: `_wt-ops-infra-session8-postgres-audit` (PR #10 open, unmerged — new this
round), `_wt-ops-infra-maintenance-window` (PR #9 open, unmerged, not mine), `_wt-ops-infra-plan`,
`_wt-ops-infra-podman`, `_wt-ops-infra-secrets`, `_wt-ops-infra-baseline`, `_wt-ops-infra-audit` (all
still listed by `git worktree list` — check each one's PR state with `plan-status-check` or
`gh pr list` before assuming any is stale; this handoff didn't audit them individually). Leave
`_wt-ops-infra-session56-cloudflare-access` in place per 2026-09-16's note — it's for whenever the
Cloudflare lane unblocks.

**Not safe to prune, new this round**: `_wt-MasterThread-agent-roster-git-backup` (branch
`agent/MasterThread/agent-roster-git-backup`, commit `8c4da85`, no PR yet). Committed, not pushed —
`git push` from that session was denied by its own auto-mode classifier ("Out-of-Place
Publication"); not routed around via another session (that's permission laundering regardless of
how safe the change looks). `GitHub\AEGIS-Push-Agent-Roster-Backup.cmd` is a click-through for
Jeremy to push it himself — created and opened this round, not yet confirmed run. Once pushed,
opening the PR is still queued behind #52 clearing (rule 4, one open agent PR per repo) — do that
next, don't re-push.

---

## 9. Memory files worth knowing

Same list as 2026-09-16's handoff. Consider adding one this round earned: *a duplicate orchestrator
watcher registration is not automatically a live collision — check the PID's actual command line
before assuming either way, and message every live peer before killing anything.*
