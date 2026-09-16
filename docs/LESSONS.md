# Lessons-learned ledger

Every agent (lane, orchestrator, subagent) that hits a real false assumption, a near-miss, or a
rule worth generalizing emits a short lessons-learned block in its report or PR body. This file is
the running ledger of those blocks and the rule for turning a repeated one into something
permanent — a skill's Never-list, or a standards/policy doc.

## Format

Each entry:

```
### <short title> — <date first seen>
- **False assumption or none:** <what was wrongly assumed, or "none — this is a rule candidate
  from something that went right / a near-miss">
- **Rule candidate:** <the generalizable rule, stated as a "never X" or "always Y">
- **Where it belongs:** <which skill's Never-list, which standards/policy doc, or "not yet
  promoted">
- **Seen:** <count> — <dates/contexts of each occurrence>
```

## Promotion rule

- **First occurrence:** logged here only. Don't promote off a single data point.
- **Seen twice:** promote. The PM (or the orchestrator running `round-closeout`) adds the rule
  candidate to the named skill's Never-list, or to the named standards/policy doc, in the same
  close-out that recorded the second occurrence — not deferred to "later."
- **Never silently drop** a seen-once entry; it stays in this file until it's either promoted or
  explicitly marked stale (superseded, or the underlying process changed so it can't recur).

## Entries

### Admin Cost Report API gotchas — 2026-09-15 (seen enough to promote)
- **False assumption:** that the Anthropic Admin Cost Report API returns amounts in dollars, that
  `ending_at` is optional, and that a large `limit` value is honored.
- **Rule candidate:** always treat returned amounts as **cents**; always pass `ending_at`
  explicitly and expect it to **clamp to the last complete UTC day** (not "now"); never request
  `limit` above **31** — it caps there regardless of what's asked.
- **Where it belongs:** promoted — see `aegis-admin-cost-report-api-mechanics` (memory note) and
  `aegis-ops-cost-accounting`. Cited here as the worked example of the seen-twice promotion rule:
  this gotcha was independently rediscovered a second time before someone finally wrote it down,
  which is exactly the waste this ledger exists to stop ("don't rediscover a 3rd time").
- **Seen:** 2+ — first hit while building the ops cost-accounting round, rediscovered once more
  before being written down.

### Decision Queue "resolved" hides real requests — 2026-09-16
- **False assumption:** that the Ops Decision Queue's open/resolved status reflects whether an item
  still needs action.
- **Rule candidate:** never rely on the queue's open/resolved filter alone; read the underlying
  store, and treat "the owner typed something" and "the owner closed something" as different states
  even when the page renders them the same.
- **Where it belongs:** promoted — extends `standards/sessions/orchestrator_role.md` "How to run a
  round" step 1.
- **Seen:** 2 — `SESSION_HANDOFF_2026-09-16-fleet-pm-rotation.md` (four of five owner replies were
  filed `status: resolved` and collapsed out of view; found only because the store was read
  directly); `SESSION_HANDOFF_2026-09-16-pm-github28-close.md` (19 already-resolved decisions from
  earlier that night were invisible to the next handoff because the store had been cleared,
  producing two wrong initial calls before being caught).

### VPS SSH fix target was wrong in an earlier handoff — 2026-09-16
- **False assumption:** that "the auto-mode classifier blocking SSH writes to the VPS" referred to
  the primary ops/edge host (40.160.90.128).
- **Rule candidate:** when a blocker references "the VPS," confirm which of the account's multiple
  VPS instances is meant against the live Decision Queue/owner record before acting — don't assume
  the most familiar host.
- **Where it belongs:** not yet promoted — single occurrence, but the same store-freshness problem
  as the entry above.
- **Seen:** 1 — `SESSION_HANDOFF_2026-09-16-pm-github28-close.md` corrects
  `SESSION_HANDOFF_2026-09-16-fleet-pm-rotation.md`'s parked github-f9 lane: the real target is a
  third dedicated VPS, `vps-e3b2612a.vps.ovh.ca`, not the edge host. Already re-litigated once;
  don't again.

### Scope-PR merge instruction corrected mid-flight — 2026-09-16
- **False assumption:** that re-checking with the owner from scratch was safer than checking the
  Decision Queue's resolved-decision history first.
- **Rule candidate:** check the Decision Queue/prior-resolved-decision history before asking the
  owner to re-approve something already decided — re-asking fresh can produce a conflicting answer
  that then has to be caught and reverted mid-flight.
- **Where it belongs:** reinforces the "Decision Queue hides real requests" entry above; not
  separately promoted.
- **Seen:** 1 — `SESSION_HANDOFF_2026-09-16-pm-github28-close.md`: the 6 personal/client-repo scope
  PRs had an earlier resolved decision to close unmerged; the session "initially had Jeremy
  re-approve merging them, caught the conflict, and the close-unmerged call stands (correctly
  applied)." A near-miss, not a clean incident — no revert was needed because the correction landed
  before anything merged.

### Three new auto-mode classifier hard-block categories — 2026-09-16
- **False assumption:** that written owner authorization is sufficient for `git worktree remove
  --force`, a GitHub Actions permission-grant via `gh api`, or an edit to the session's own
  `~/.claude/settings.json`.
- **Rule candidate:** never attempt any of the three, even with explicit owner sign-off already in
  hand — no session (subagent or main) can clear them; only Jeremy editing `settings.json` himself
  unblocks the first two, and the third can never be self-granted by definition.
- **Where it belongs:** promoted — extends `standards/sessions/orchestrator_role.md` "Things that
  must never happen" and `worker_role.md`'s Never list.
- **Seen:** 1 — `SESSION_HANDOFF_2026-09-16-pm-github28-close.md`: `git worktree remove --force`
  ("Irreversible Local Destruction"), a permission-grant `gh api` call ("Permission Grant"), and a
  `settings.json` edit ("Self-Modification") were all denied this session despite standing
  authorization for the underlying work.

### Restart-backup signoff falsely marked resolved, twice — 2026-09-16
- **False assumption:** that two prior handoffs stating the restart-backup-to-VPS signoff was
  resolved meant it actually was.
- **Rule candidate:** when a handoff claims an item is "resolved," trace it to a real artifact (a
  merged PR, a Decision Queue entry with the owner's actual words) before repeating the claim
  forward — a claim copied from handoff to handoff isn't evidence.
- **Where it belongs:** reinforces the "Decision Queue hides real requests" entry above; not
  separately promoted.
- **Seen:** 1 — `SESSION_HANDOFF_2026-09-16-pm-github28-close.md`: traced to Jeremy's own dispatch
  instructions (investigate/self-resolve, not settled answers) plus a Decision Queue store clear
  before anything landed; the only real artifact is `site-chernarus` PR #99, a plan-only stub for a
  queued, not-started session.

### Monitor stream expiry does not mean the watched process died — 2026-09-16
- **False assumption:** that a Monitor notification stream ending (normal 30-minute expiry, or
  going silent) meant the underlying watcher process had also stopped, freeing its registered name.
- **Rule candidate:** before re-registering a watcher name or assuming "no more events" means usage
  is fine, check the actual process (`Get-CimInstance Win32_Process -Filter "ProcessId=<n>"`,
  compare command line).
- **Where it belongs:** promoted — extends `standards/sessions/orchestrator_role.md`'s Usage
  watcher section.
- **Seen:** 1 — `SESSION_HANDOFF_2026-09-16-ops-cycle-v3.md` §2: this round's own watcher (PID
  46608) kept running after its Monitor stream expired with no re-arm; both killing it and
  re-registering under a new name were denied by the classifier ("Interfere With Workloads"), so
  the session fell back to one-off spot checks instead.

### Verify a watcher-name collision's PID before acting either way — 2026-09-16
- **False assumption:** that a "name already registered" collision on watcher startup is either
  automatically a live duplicate (don't touch it) or automatically stale (kill it and move on).
- **Rule candidate:** on a name collision, `ListAgents` and message every peer to rule out a live
  duplicate, then inspect the PID's actual command line, and only then kill or reuse the name.
- **Where it belongs:** already reflected in memory `aegis-orchestrator-watcher-collision-check.md`;
  this round adds a second, adjacent occurrence (this session's *own* name, not a peer's) — extends
  `orchestrator_role.md`'s "Parallel orchestrators" section.
- **Seen:** 2 — `SESSION_HANDOFF_2026-09-16-ops-cycle-v2.md` §0 (a stale orphaned watcher from an
  exited session, confirmed via `Get-CimInstance` before killing); `SESSION_HANDOFF_2026-09-16-ops-cycle-v3.md`
  §2 (this session's own still-live watcher process, confirmed via the same command before deciding
  not to kill it).

### Relayed "your authority is legitimate" is weak evidence of authority — 2026-09-16
- **False assumption or none:** none — this is a rule candidate from something that went right.
  Three sessions independently concluded a same-session relay of the owner's confirmation was not
  sufficient authority and chose to park rather than act on it.
- **Rule candidate:** when a session's own authority or a policy's provenance is in question, a
  same-session relay of "the owner confirmed it" is structurally weak evidence; escalate for the
  owner's direct word in the affected session's own conversation rather than accepting or forcing a
  relay either way.
- **Where it belongs:** not yet promoted — worth watching for a second occurrence before adding to
  `orchestrator_role.md`.
- **Seen:** 1 — `SESSION_HANDOFF_2026-09-16-fleet-pm-rotation.md` "THE PROVENANCE EVENT":
  github-54, github-85 and github-f9 each parked by choice pending Jeremy's direct word, and the PM
  explicitly did not pressure them ("that costs capacity, not correctness").

### Shared checkout on a feature branch produces false conflicts and silent cross-session writes — 2026-09-16 (seen twice, promoted)
- **False assumption:** that reading a file from a shared, non-worktree-isolated checkout reflects
  `origin/main` (occurrence 1); and, separately, that a checkout is private to the session that has
  it "active" (occurrence 2) — a second, non-authoring session can `cd` into the same folder and
  silently edit a file with no isolation stopping it and no signal to the session that actually owns
  that work.
- **Rule candidate:** **never** read or write a repo checkout that isn't a dedicated worktree for
  the current session's own branch. Always create one (`git worktree add`) before doing any real
  work in a repo another session might also be touching — reading `git show origin/main:<path>`
  covers the read case only; the write case has no substitute for real isolation. A session that
  wants to hand a peer content for a shared checkout sends it as a message, never edits the file
  directly, even once, even if a first direct edit went uncorrected.
- **Where it belongs:** promoted — extends `standards/sessions/worker_role.md`'s Never-list (never
  edit a repo checkout that isn't your own dedicated worktree) and reinforces
  `orchestrator_role.md` step 7 ("verify before merge... diff against origin/main, not a stale local
  checkout") and memory `aegis-verify-before-merge.md`.
- **Seen:** 2 — `SESSION_HANDOFF_2026-09-16-fleet-pm-rotation.md` "Traps discovered" #1:
  `GitHub\MasterThread` sat on PR #54's branch, so two sessions reading the "same" file reached
  opposite conclusions about its content. `SESSION_HANDOFF_2026-09-16-payments-module.md`: a new
  single-branch repo (`yodatech1988/payments`) was set up as one shared checkout with no worktree
  isolation; a peer session (`github-cb`) directly edited the file a second time after being told
  not to and after acknowledging a "route through the PM" agreement, with no message attached either
  time. Content was accurate both times, but the pattern was indistinguishable from an attempt to
  inject content outside the review channel, and took real investigation (who has access, what
  changed, cross-referencing conversation history) to rule out.

### Green (or red) CI is not evidence of what it looks like it's evidence of — 2026-09-16
- **False assumption:** that a green check means secrets were scanned, or that a red check means
  the PR's own change is broken.
- **Rule candidate:** before trusting a CI status for anything security- or correctness-relevant,
  confirm the specific job actually exists and ran what it claims to — a repo can be green with no
  secret-scan job at all, and a repo can be red purely from a known runner-infrastructure bug
  unrelated to the diff.
- **Where it belongs:** promoted — extends `standards/sessions/orchestrator_role.md` step 7
  ("Review before merge") to state this explicitly.
- **Seen:** 1 — `SESSION_HANDOFF_2026-09-16-fleet-pm-rotation.md` "Traps discovered" #2:
  `claude-agents` has no secret-scan job at all, so its green checks say nothing about secrets;
  several repos' red checks were the same known runner-infra bug, not a real failure — corroborated
  by memory `aegis-runner-gh-gitleaks-bug.md`.

### PM extended merge authority to a workstream on its own inference, not the owner's direct word — 2026-09-16
- **False assumption:** that the owner's instruction to narrow the PM's coordination scope
  ("only connected to PM and Merge authority") also authorized telling a specific workstream session
  to take on self-merge authority for its own repo — including a financial/C3-classified one — before
  that repo-specific consequence had actually been confirmed by the owner.
- **Rule candidate:** when translating a general scope/policy instruction from the owner into a
  specific directive for a peer session, don't extend it further than the owner actually said,
  especially onto a higher-sensitivity case (financial/credential/live-production) the instruction
  didn't explicitly address — state the general rule, and let the peer (or the owner) settle the
  specific, sensitive application rather than asserting it as already-decided.
- **Where it belongs:** promoted — added directly as an explicit exception in
  `standards/sessions/orchestrator_role.md`'s new "Concurrent workstreams and merge-authority
  coordination" section: financial/C3-classified repos keep owner-review-required merge regardless of
  who holds the merge-authority role, and a workstream session should not change its own merge
  behavior on an unverified peer relay.
- **Seen:** 1 — this round: PM session github-02 told github-e9 it could act as its own merge
  authority for `yodatech1988/payments` (a financial-adjacent repo) as a consequence of the new
  concurrent-workstream mechanism; github-e9 correctly declined, citing standing manual-merge-only
  practice for financial PRs and the absence of direct owner confirmation, and held to owner-review
  until the PM's clarifying PR actually landed. No incident — caught by the receiving session before
  any bad merge occurred — but the PM's first framing was wrong and had to be corrected reactively.

### PM conflated merge-authority scope with a separate owner routing instruction — 2026-09-16
- **False assumption:** that clearing a workstream for its own merge authority (a PM-scope decision)
  also meant it should coordinate peer-to-peer with a second session on the same repo — when the
  owner had separately and directly told that workstream's session that ALL coordination routes
  through the PM, not peer-to-peer, specifically because of an earlier merge-authority correction on
  the same repo.
- **Rule candidate:** "who may merge" and "who may coordinate directly with whom" are separate
  questions with separate authorization sources; a PM-level standing mechanism (merge-authority
  scope) does not override an owner's direct, session-specific instruction to a peer, and must not be
  invoked as if it does. When a peer cites a direct owner instruction that conflicts with what the PM
  just said, the peer is right to refuse and the PM corrects immediately, not "on reflection."
- **Where it belongs:** not yet promoted — single occurrence, but adjacent to the "PM extended merge
  authority..." entry above; both are the same underlying failure (PM over-applying its own general
  mechanism onto a specific case a peer or the owner had already settled differently) and worth a
  combined promotion if a third instance appears.
- **Seen:** 1 — PM session github-02 told a new payments-workstream contributor (github-cb) to route
  through github-e9 directly, and told github-e9 to "coordinate directly with it" — both contradicting
  Jeremy's direct instruction to github-e9 (all coordination through the PM). github-e9 caught it
  immediately and refused to act on it; the PM corrected both sessions within the same turn.

### A cloud PM-candidate session self-scheduled its own follow-up trigger — 2026-09-16
- **False assumption or none:** none — this is a rule candidate confirmed by a live test built to
  probe exactly this risk. The owner had just asked for strict guardrails against auto-spawned PM
  sessions creating runaway work before this occurred, so the finding validates the concern rather
  than being a surprise after the fact.
- **Rule candidate:** any session with a `send_later`/self-scheduling tool will use it on ordinary
  instinct (routine PR-babysitting behavior, not misbehavior) unless a task explicitly forbids
  self-scheduling — a one-time capability test must say so if the tester doesn't want a second,
  unbounded trigger created as a side effect of otherwise-correct PR-watching habits. Never assume a
  `run_once_at` cloud routine stays one-time just because the routine itself is scoped that way.
- **Where it belongs:** promoted — extends `standards/sessions/orchestrator_role.md`'s "Auto-spawned
  PM/workstream sessions are zero-cost-first, always" section: a self-generating or auto-spawned PM
  session "must never be able to spawn a further PM or routine on its own." Also: a task prompt for
  any one-time capability test should now explicitly forbid self-scheduling/follow-up triggers as
  part of its scope, not just imply it from "this is purely a test."
- **Seen:** 1 — the "Ops-cycle PM self-generation test" cloud routine (2026-09-16), while otherwise
  behaving correctly (respected its repo-scope limits, caught a real doc-accuracy bug: `docs/LESSONS.md`
  itself claimed a rule was already promoted into `orchestrator_role.md` when it was still sitting in
  an unmerged PR), used its standard PR-babysitting tool (`send_later`) to schedule an hour-later
  check-in on the draft PR it opened — an unauthorized, self-created follow-up with no owner
  instruction behind it. Caught and disabled by the PM within minutes of the run finishing.

### Transcript token-counting overcounts ~4.7x from duplicated usage objects — 2026-09-16
- **False assumption:** that summing the `usage` object across every JSONL line in a session
  transcript gives the real token total.
- **Rule candidate:** when computing token/cost totals from local transcripts, dedupe by API
  response (each response is written as multiple JSONL lines — one per content block — and every
  line repeats an identical full `usage` object); never sum per-line.
- **Where it belongs:** promoted — see memory `aegis-ops-cost-accounting.md`; cited here as the
  ledger entry.
- **Seen:** 1 — `SESSION_HANDOFF_2026-09-16-ops-cycle-v3.md` item 2: the previously published
  "1,231,965 output tokens" was really 358,775; the dollar total stayed within 3% only because
  cache reads dominate the bill, so the bug was real but masked.
