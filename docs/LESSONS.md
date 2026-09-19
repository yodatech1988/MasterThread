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

### A merge card described a PR from an earlier sweep, not from the PR - 2026-09-17
- **False assumption:** that a path summary taken an hour earlier still described the PRs, and that
  "canon dossier" meant "documents only".
- **Rule candidate:** a merge card's file count, file list and "docs only / contains code" line are
  read with `gh pr view <n> --json files,changedFiles` at filing time, and every path outside
  `docs/` is named. **A number that moved is a reason to re-read, not a detail:** the filing session
  saw the additions had grown (569 -> 776 on #111) and did not follow it up.
- **Where it belongs:** `claude-agents/blocked-work-sweep.md` step 3 (PR #92); sent to the owner of
  `decision_queue_standard.md` for "Filing a card".
- **Seen:** 1 - github-b5's cards for site-chernarus #111/#112/#113 said "two new files, documents
  only". Each had three (a questlines doc was missing), and #113 had six, three of them Python under
  `tools/quest_grounding/`. The owner merged #111 and #112 on the wrong description before github-ff
  caught it; MasterThread #82's card also said one file for two.

### A stacked PR carded before its base is main merges into the side branch - 2026-09-17
- **False assumption:** that an action card step saying "check the PR page says it merges into
  main; if not, stop" is a safeguard.
- **Rule candidate:** never file an owner merge card for a PR whose `baseRefName` is not the repo's
  default branch. Retarget first, card second. A sequencing note in a title ("only after #13") does
  not survive an owner working down a list of cards quickly, and should not have to.
- **Where it belongs:** `claude-agents/blocked-work-sweep.md` step 3 (added); on a second occurrence,
  `decision_queue_standard.md` "Action cards".
- **Seen:** 1 - ops-infra #17: carded by github-b5 while based on
  `agent/ops-infra/decision-a-cloudflare`; merged 18:07:07Z, 26 seconds after parent #13, into that
  branch. GitHub shows MERGED; `docs/PRODUCTION_LAYOUT.md` is 404 on main. Caught by the
  owner-wait watcher plus a base-branch check on the merge event, within minutes. Nothing lost;
  needs a replacement PR.

### The owner's newest words on a card can reverse the summary a peer gives you - 2026-09-17
- **False assumption:** that a PM's one-line description of a card's state ("the licence question is
  parked") was current.
- **Rule candidate:** before filing a card that depends on another card's state, read that card
  from the store at filing time - including `claimComment`, which is where he now types.
- **Where it belongs:** not yet promoted - `decision_queue_standard.md` "Filing a card" on a second
  occurrence.
- **Seen:** 1 - site-chernarus #114 (Chiemsee dossier): about to be carded as "Canon 4 of 4" when
  the licence card's latest `claimComment` read "lets just omit it then, we have enough content
  without it". Not filed; put back to the lane that owns Chiemsee.

### A "Done" answer on a card is a claim, not a state - 2026-09-17 (seen enough to promote)
- **False assumption:** that an owner answering an action card "Done - I ran it" / "Merged" means the
  click-file ran or the PR merged.
- **Rule candidate:** always re-read live state (`gh`, the disk, the script's completion log) before
  building on a "done" answer, and never let an owed click share the one-click decision flow. An
  action card leaves the list only after a session verifies it.
- **Where it belongs:** promoted - `standards/sessions/decision_queue_standard.md` "Action cards";
  the Decision Queue page (v12) implements it; `blocked-work-sweep` section 2 checks for it.
- **Seen:** 3 - 2026-09-17 14:59Z (`action-1`, `action-2`), 17:17Z and 17:20Z (the three re-filed
  action cards, each cleared within seconds). Each time branch protection was unchanged, no
  `AEGIS-Protect-Default-Branches.*.log` existed, PR #81 was still OPEN/BLOCKED and six worktrees
  were still on disk. Two sessions verified independently. Reopening the same one-click card a
  second time just got it cleared again - the fix was the page, not another reminder.

### Check the prerequisite before asking for the click - 2026-09-17
- **False assumption:** that flipping the Actions token to write on MasterThread, ops-infra,
  ops-platform and ops-policies would unblock review on their open PRs.
- **Rule candidate:** before recommending a permission or settings fix for CI, confirm the job has
  somewhere to run (`gh api repos/<o>/<r>/actions/runners`). With zero runners the flip turns a loud
  `startup_failure` into a silent forever-queue - the be-rcon failure mode.
- **Where it belongs:** not yet promoted - `blocked-work-sweep` step 6 carries it meanwhile.
- **Seen:** 2 - card `actions-token-flip-4-repos-hold-or-run-2026-09-17` (owner chose hold);
  and `payments`, whose required `check` context targets `runs-on: [self-hosted, vps]` with zero
  registered runners - see "A required check with nowhere to run reads as checks failed, 24 hours
  later" in the 2026-09-17 consolidated section below.

### "Held" in one document, decided in another - 2026-09-17
- **False assumption:** that ops-infra `docs/PLAN.md` "Decision A is held" meant the owner had not
  chosen between Tailscale and Cloudflare.
- **Rule candidate:** before filing (or re-asking) an owner decision, read the program's place of
  record - here the authority artifact, whose header says it wins - and check the same repo for
  text already written against the outcome. File a confirm-the-record card with the evidence, not a
  fresh choose-one card.
- **Where it belongs:** not yet promoted - belongs in the queued "decisions of record" standard.
- **Seen:** 1 - card `ops-infra-decision-a-tailscale-vs-cloudflare-conflict-2026-09-17`: two sessions
  and two PM reopen attempts treated it as undecided; the artifact recorded the 2026-09-15 choice
  with the domain purchase and accepted trade-off. (The owner then began reconsidering it in chat
  with another session - a recorded decision can still be reopened, but by him, knowingly.)

### Read back after every store write - 2026-09-17
- **False assumption:** that a correction entry saying "setting status to open now" had set it.
- **Rule candidate:** always re-read a Decision Queue document after writing it and confirm the
  field changed; pin with `if_version`. A note about a write is not the write.
- **Where it belongs:** not yet promoted - `decision_queue_standard.md` "Editing an existing card
  safely" is the natural home on a second occurrence.
- **Seen:** 1 - the decision-A card carried two corrections announcing a reopen while `status` still
  read `resolved` (versions 5-7).

### One blocker, many symptoms: report by root cause - 2026-09-17
- **False assumption:** none - rule candidate from something that went right.
- **Rule candidate:** when asked "what is blocked", group by cause and lead with the single action
  that unblocks the most. Six MasterThread PRs, a "not merged" card and a "protection failed" card
  were one missing owner click; ten CLEAN-but-unmerged PRs were one unstaffed merge seat.
- **Where it belongs:** `claude-agents/blocked-work-sweep.md` step 5.
- **Seen:** 1 - this session's two sweeps.

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
- **Seen:** 2 — occurrence 2 is "A gate that cannot fail is worse than no gate" (2026-09-17), in
  the consolidated section below: a review job that skips for want of a credential and exits
  SUCCESS. Occurrence 1: `SESSION_HANDOFF_2026-09-16-fleet-pm-rotation.md` "Traps discovered" #2:
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

### Nothing governed the space between "PR is up" and "the next lane begins" — 2026-09-17
- **False assumption or none:** none — a rule candidate from a genuine gap, not a mistake. Owner
  framing, direct: a worker finishing a lane should document lessons, cache session state, and wait
  for the PM's next card as the *natural default*, with continuing on new work an explicit PM
  instruction, never self-guided.
- **Rule candidate:** a worker session that delivers a lane must not idle and must not self-assign
  follow-on work it happens to notice in scope; it writes its lessons-learned block, refreshes its
  Fleet Status row to `state: done` / `nextStep: awaiting PM assignment`, and asks the PM for the
  next card — same discipline as the existing "never block/poll waiting on a peer's handoff" rule,
  applied to session completion instead of mid-task blocking.
- **Where it belongs:** already promoted this round — `standards/sessions/worker_role.md`'s new
  "After delivering — end of workstream" section (MasterThread PR #82), not deferred to a second
  occurrence since it came as a direct owner instruction rather than an inferred pattern.
- **Seen:** 1 — this session (`github-89`), 2026-09-17: practiced immediately after writing it (PR
  #82 itself, then again after delivering handymansfield PR #54) — reported completion to the PM
  and stood by rather than picking its own next task both times.

### A lane card's quoted claim misattributed which file held it — 2026-09-17
- **False assumption:** a PM's lane card said `docs/QB-CI-GUARDRAIL.md` "currently says 'production
  only, not for sandbox,' which is backwards" — that exact phrase doesn't exist in that doc; it was
  a paraphrase of a comment actually living in `tools/QuickBooksKey.ps1` (`# production only -- this
  tool is not for sandbox`). The underlying task was still correct and got done in both files; the
  specific quote was just attributed to the wrong one.
- **Rule candidate:** when a lane card quotes or closely paraphrases existing file content as
  justification for a change, grep for that text in the named file before treating the attribution
  as fact — a PM's summary of "what a file currently says" is a claim like any other relayed claim,
  not exempt from the standing verify-before-acting rule just because it names a specific file.
- **Where it belongs:** not yet promoted — single occurrence, low-impact (caught immediately, no
  wasted work), adjacent to the existing "verify, don't trust" rule in `CLAUDE.md` rather than a new
  standalone rule; worth folding in only if a second, costlier instance appears.
- **Seen:** 1 — handymansfield PR #54's lane card (from PM `github-8b`), this session.

### A real credential tool sat untracked in a shared checkout with no git history — 2026-09-17
- **False assumption:** none directly assumed by this session, but a real gap found while starting
  the lane above — `tools/QuickBooksKey.ps1`/`.cmd` (handymansfield's Intuit OAuth credential tool,
  same DPAPI-key-window pattern as `OvhApiKey.ps1`/`RconKey.ps1`) existed only as untracked files in
  the shared, non-worktree checkout, never committed to git at all. A machine crash, a `git clean`,
  or an accidental overwrite in that checkout would have silently destroyed it with no recovery path
  — the DPAPI-encrypted credential *store* it manages is backed up nowhere either, by design, but
  the *tool itself* should never have that same fragility.
- **Rule candidate:** a credential-tool script under `tools/*Key.ps1` (or equivalent) must be
  committed to git promptly after it's written and working — never left as a durable-in-practice but
  git-untracked file in a shared checkout. If found untracked, the next session to touch that repo's
  tooling commits it (even as a standalone "first commit" PR) rather than building on top of an
  uncommitted file.
- **Where it belongs:** not yet promoted — single occurrence this round; adjacent to
  `jeremy-durable-credential-tools.md` (memory) and `worker_role.md`'s shared-checkout rule. Worth
  folding into one of those, or a new one-line rule in `worker_role.md`'s "Before starting" checklist
  ("check whether the lane's key files are actually tracked in git before extending them"), if it
  recurs.
- **Seen:** 1 — this session (`github-89`) found and fixed it as part of handymansfield PR #54
  (the tool's first-ever git commit).

### An owner instruction that could not be carried out — 2026-09-17
- **False assumption:** that an action card's steps were sound because they read clearly. An
  ops-infra card told the owner to create the vault's Cloudflare tunnel in the dashboard; the
  dashboard only creates *remotely-managed* tunnels, and the merged role requires a
  *locally-managed* one, which per Cloudflare's docs exists only via the CLI. The step was
  impossible. The same PR had verified its machine-facing facts to primary sources (Launchpad for
  package absence, a key fingerprint read from the key, a checksum confirmed across two
  distribution paths) and its human-facing instructions not at all.
- **Rule candidate:** **always** treat an instruction written for a person as a claim needing the
  same evidence as a claim written for a machine — trace every step to a primary source or perform
  it, and for any named screen, menu path or button, read it from current vendor documentation at
  filing time and record when it was read. **Never** review an action card only for clarity: ask
  what artifact each step produces and whether the next step can consume it. A chain that is lucid
  at every step and broken between two of them is invisible to a clarity review.
- **Where it belongs:** `standards/sessions/decision_queue_standard.md` (card-filing requirements)
  and the postmortem at `docs/POSTMORTEM_2026-09-17_IMPOSSIBLE_OWNER_INSTRUCTION.md`. Promote on a
  second occurrence per the rule below; logged here as one.
- **Seen:** 1 — ops-infra card `action-cloudflare-vault-tunnel-dashboard-2026-09-17`, filed by
  `github-29` 22:30:06Z, relayed to the owner verbatim by PM `github-c5`, read as a dependency by
  `github-b6` and `github-38`. Four sessions, zero detections.

### Owner confusion is a defect report until proven otherwise — 2026-09-17
- **False assumption:** none — this is a rule candidate from how the above was detected. The owner
  pressed "I did it - check it" with the comment "I don't know how to do this, I will need guided in
  session". Treated as a completion claim it would have closed the card; treated as a knowledge gap
  it would have produced a better-explained version of an impossible instruction. Treated as
  evidence about the instruction, it found the defect.
- **Rule candidate:** **always** re-derive the steps before re-explaining them when the owner says
  he does not know how. His uncertainty is a measurement of the instruction, and on this occasion it
  was more accurate than the judgement of three sessions that had reviewed the same text.
- **Where it belongs:** `standards/sessions/decision_queue_standard.md`, next to the existing rule
  that a card answered with a question back is still open.
- **Seen:** 1 — this session (`github-29`), 2026-09-17T22:45:25Z.

---

## Consolidated round close-out — 2026-09-17, "things that assert a false state"

The entries below were written after the round, from live reads (`git show origin/main:<path>`,
`gh` API, the stored Decision Queue documents), not from any session's summary. They are grouped by
**mechanism**, because the night's defects did not sort by session — the same shape recurred in CI,
in a backup probe, in a port scanner and in a lint baseline.

Three things are deliberately **not** repeated here, because they already have a better home:

- **Telling the owner's answer from a session's writing on the Decision Queue** — the millisecond
  discriminator, the false byte-identical fingerprint, and the unattended-watcher rule — lives in
  `standards/sessions/decision_queue_standard.md` (MasterThread **#100, merged** 2026-09-17T22:56Z).
- **Reading `origin` not a working tree, `rg` honouring `.gitignore`, `--is-ancestor` on a
  squash-merge, and "adjacency is not authority"** live in `standards/sessions/worker_role.md`
  (MasterThread **#101, OPEN** as of this writing — do not cite it as landed).
- **Verification effort allocated by audience rather than consequence**, and reviewing an
  instruction for achievability rather than clarity, live in
  `docs/POSTMORTEM_2026-09-17_IMPOSSIBLE_OWNER_INSTRUCTION.md` (**#102, merged**) and in the two
  ledger entries immediately above this section.

### A gate that cannot fail is worse than no gate — 2026-09-17 (seen twice, promote)
- **False assumption:** that `review / review = success` meant a Claude review had read the diff.
- **What is actually true, estate-wide, verified:** **no automated Claude review is completing on
  any repo.** Two distinct mechanisms, needing different fixes, both reached through the *same*
  shared workflow — the variable is the repo's secret, not the runner and not the workflow:
  - **No review credential → GREEN.** `gh run view 35285166635 -R yodatech1988/website --json jobs`
    shows job `review / review` completing in **5 seconds** with both `Run Claude review (...)` steps
    `"conclusion":"skipped"`; the log carries the literal notice `No Workload Identity Federation
    inputs or ANTHROPIC_API_KEY/CLAUDE_CODE_OAUTH_TOKEN secret configured -- skipping Claude
    review`. `gh secret list -R yodatech1988/website` has neither secret. The job never reaches
    `oven-sh/setup-bun`, so the runner's missing `unzip` never even shows up
    (`gh run view 35285166635 --log | grep -ci unzip` → **0**).
  - **Credential present, runner missing `unzip` → RED.** The job reaches `oven-sh/setup-bun`,
    which downloads Bun as a `.zip` and shells out to `unzip`, and dies in ~8s with `Unable to
    locate executable file: unzip`, exit 127 (core run 35232643743, site-chernarus run
    35260046534; both runners report the same machine, `vps-736c134b`).
- **What it has already cost:** site-badlands **#10** merged 2026-09-17T18:09:54Z on a green
  `review / review` that had read nothing. website **#27** — the live PayPal donate button — merged
  the same way, on a repo with automerge on, zero required approving reviews, and a review check
  that is green by construction. Nothing reviewed it and nothing was ever going to.
- **Rule candidate:** **never** treat a check's *colour* as evidence; read what the job actually
  executed (`gh run view <id> --json jobs` for `skipped` steps, then the raw log). A credential- or
  dependency-gated job must **fail closed** — a skip is a non-result and must not be reported as a
  pass. Where fail-closed would block merges until credentials exist, that trade is the owner's call
  and must be put to him in those words, not decided quietly by leaving the check green.
- **Where it belongs:** this is occurrence 2 of "Green (or red) CI is not evidence of what it looks
  like it's evidence of" (2026-09-16, above), which was promoted into
  `standards/sessions/orchestrator_role.md` step 7. That step 7 text does **not** yet carry "a
  skipped step is not a pass; gated jobs fail closed" — **that sentence is the outstanding
  promotion**, and no PR carries it as of this entry.
- **Seen:** 2 — 2026-09-16 (`claude-agents` green with no secret-scan job at all); 2026-09-17
  (website/site-badlands green-by-skip, verified above).

### A correction can be more dangerous than the error it corrects — 2026-09-17
- **False assumption:** that "Claude review is dead runner-wide" was wrong because it passes on
  `website`. The original claim was wrong in **mechanism** and right in **conclusion**; the
  correction was wrong in a **more dangerous direction**, because it told the owner that the one
  repo with the *invisible* failure was the healthy one. It was propagated to three sessions before
  being caught.
- **Rule candidate:** when correcting a peer's claim, state which *part* is wrong — mechanism,
  scope, or conclusion — and check that the corrected version is not merely a different false
  statement. A correction inherits none of the original's scrutiny and is trusted more, so it
  carries the higher burden of proof, not the lower one. Re-verify a correction before relaying it,
  exactly as you would the claim it replaces.
- **Three other corrections from this round, recorded so the originals are not repeated:**
  - "`core` and `site-chernarus` need the gitleaks port" — **false**. Neither uses gitleaks; both
    run a hand-rolled `git grep -InE "$PATTERNS"` in `.github/workflows/secret-scan.yml` on
    `origin/main`. `services` was the repo that needed it (#103).
  - "The public edge has no intrusion protection and the plan over-claims" — **false on both
    counts**. The edge runs fail2ban 1.1.0 active with its own `inet f2b-table`, ufw active, sshd
    hardened; and `ops-infra/docs/CONTROLS.md` 3.E already reads *"fail2ban on `vault-dev` and edge;
    CrowdSec on `vault-dev` only."* The only "both hosts" text sits in the plan's **goals** list. A
    goal is not a claim.
  - "All three card watchers would auto-reopen" — **false**; one would have stalled instead. The
    session that said it was corrected by the session that owned the watcher.
- **Where it belongs:** not yet promoted — one occurrence as a stated rule, but it is the connective
  tissue for every corrected claim in this round. Promote into `worker_role.md`'s "State what you
  searched" material (MasterThread #101) on a second occurrence.
- **Seen:** 1 — this round; three claims corrected, one of the corrections itself retracted.

### A scanner that never ran, and a re-run that cannot succeed — 2026-09-17
- **False assumption:** that `gitleaks/gitleaks-action@v2` was scanning, and (separately, from a
  header comment in `services`) that it is a **container action needing rootless Docker**.
- **The mechanism, verified from the PR bodies' quoted CI output:** it is a **JavaScript action
  that downloads a binary**, and it **hardcodes `/tmp`** for both its tool cache and its download.
  On the self-hosted runner that path is not writable by the runner user:
  `/usr/bin/tar: ../../../../../tmp: Cannot mkdir: Permission denied`, then
  `could not install gitleaks ...: Destination file path /tmp/gitleaks.tmp already exists`, then
  `Error: parameter 'file' is required`. The stale `/tmp/gitleaks.tmp` from the first failure
  **blocks the fallback path, so every re-run fails identically** — re-running is a wasted cycle,
  not a flake.
- **Rule candidate:** when an action fails on a self-hosted runner, check whether it writes to a
  hardcoded absolute path before assuming a container/Docker cause — and never diagnose from a
  header comment in the repo, which is a claim like any other. If two consecutive runs produce a
  byte-identical error, stop re-running and look for state left behind by the first. The fix that
  worked in both repos was to drop the action and install a pinned binary into `$RUNNER_TEMP`:
  `gitleaks git . --redact --no-banner --exit-code 1` (website **#28**, ported verbatim to services
  **#103**; 111 commits scanned, green in 7s).
- **Where it belongs:** not yet promoted — reinforces memory `aegis-runner-gh-gitleaks-bug.md`,
  which should be corrected to say *JavaScript action, hardcoded `/tmp`*, not a Docker problem.
- **Seen:** 1 (two repos, one cause) — website #28, services #103.

### `if: failure()` is job-scoped: an infrastructure fault paged as a security finding — 2026-09-17
- **False assumption:** that `if: failure()` on an alert step scopes to the step above it.
- **The mechanism:** it covers the **whole job**. On `services`, the step *"Notify Discord of
  finding"* was gated `if: failure()`, so any failure — including the gitleaks download above —
  would have posted **"Possible secret literal found"**. Per #103's own body: *"Every failed run for
  the past two days would have posted 'Possible secret literal found' for a broken download, had
  `DISCORD_WEBHOOK_DEVLOG` been set."* It was silent only because the webhook secret was unset.
- **Rule candidate:** **always** gate an alert on the specific step's outcome —
  `if: always() && steps.<id>.outcome == 'failure'`, with an explicit `id:` on the step that
  produces the finding. An infrastructure failure must never page a security finding: it trains the
  reader to discount the alert that matters. **Audit every alerting workflow in the estate against
  what its message literally claims**, not against what it was intended to mean.
- **Where it belongs:** not yet promoted — a one-line rule alongside the logging conventions in
  `standards/` would be the right home on a second occurrence.
- **Seen:** 1 — services #103 (fix applied), found while porting website #28.

### A required check with nowhere to run reads as "checks failed", 24 hours later — 2026-09-17
- **False assumption:** that `payments`' red checks reflected something about the code.
- **The mechanism, verified live:** `gh api repos/yodatech1988/payments/branches/master/protection`
  → `required_status_checks.contexts: ["check"]`, `strict: true`; `.github/workflows/ci.yml` on
  `origin/master` → `runs-on: [self-hosted, vps]`;
  `gh api repos/yodatech1988/payments/actions/runners` → `{"total_count":0,"runners":[]}`. Three CI
  runs sat queued and were **cancelled at GitHub's 24-hour queue timeout** (e.g. created
  `2026-09-16T16:45:52Z`, updated `2026-09-17T16:45:54Z` — 24h00m02s). A cancelled run renders the
  same as a failure. (Note: this repo's default branch is **`master`**, not `main`; querying
  `/branches/main/protection` 404s and looks like "no protection configured".)
- **Rule candidate:** before diagnosing a red or stuck required check, confirm the job has somewhere
  to run (`gh api repos/<o>/<r>/actions/runners`) and confirm you queried the **actual default
  branch**. A permission or config fix applied without a runner converts a loud instant failure into
  a silent 24-hour queue, which is worse.
- **Where it belongs:** this is occurrence **2** of "Check the prerequisite before asking for the
  click" (2026-09-17, above) — its `blocked-work-sweep` step 6 already carries the runner check;
  **the promotion still owed is the default-branch point**, which nothing carries yet.
- **Seen:** 2 — the 4-repo Actions-token flip card (the owner held it, correctly, because those
  repos also have zero runners); `payments` as measured above.

### Every negative test needs a positive control — 2026-09-17
- **False assumption:** that a non-zero exit from a probe means the system under test refused the
  operation.
- **Two instances, same shape, different tools:**
  - `vault-backup prove-append-only` probed with `restic forget --tag <tag> --prune` and read any
    non-zero exit as "refused". **restic rejects that form with `Fatal: no policy was specified`
    and exits non-zero *before contacting the repository*** (measured on restic 0.19.1 and 0.18.1,
    the version the role installs). It "proved" append-only enforcement against a plainly writable
    server.
  - An `actionlint` A/B baseline reported **"1 finding" on base vs 5 on the branch** — which reads
    as "this change introduced 4 problems". A bad container mount meant it never read the file; the
    single "finding" was `could not read ... no such file or directory`. **The tell was the number
    making no sense, not an error message.** Re-run from a path the container can see and both
    reported the identical 5 pre-existing findings.
- **Rule candidate:** **always** pair a negative test with a positive control that must succeed —
  the identical operation against a target *without* the protection (the docker suite now runs the
  same `forget` against the same server without `--append-only` and requires it to pass). An
  inconclusive result must **fail**, not pass, whenever the test's job is to sign something off.
  For any A/B comparison, confirm the baseline run actually *did work* before trusting the delta.
  And probe destructively without being destructive: write a throwaway probe snapshot and try to
  delete only that, so a bad answer costs a few bytes rather than the backup.
- **Where it belongs:** not yet promoted — `worker_role.md`'s "Tests and validators" paragraph is
  the natural home ("never claim a pass you didn't observe" does not yet cover "and confirm the test
  could have failed").
- **Seen:** 2 — ops-infra #22 (restic); the same session's actionlint baseline.

### Verify what landed, not that something landed — 2026-09-17
- **False assumption:** that a merge flag says anything about what is now on `main`. For a PR whose
  safety argument is "it ships switched off", the claim is about a **value on `main` after the
  merge**, and the PR body is the assertion being tested, not evidence for it.
- **Rule candidate:** read the switches themselves after the merge, e.g.
  `git show origin/main:ansible/roles/backup/defaults/main.yml | grep -E '^backup_(primary|offsite)_enabled|^backup_require_target'`
  → all three still `false`; plus confirm the role is actually wired into its play. Generalises to
  any "changes nothing by default" or "ships inert" safety argument.
- **Where it belongs:** not yet promoted — complements the `--is-ancestor` material in MasterThread
  #101, which settles *whether* a merge happened; this settles *what* it did.
- **Seen:** 1 — ops-infra #22, verified by the session that wrote it.

### Scanning a host that DROPs: silence reads as congestion — 2026-09-17
- **False assumption:** that an unresponsive port sweep was a network problem or a hung job.
- **The mechanism, recorded in `ops-infra/tools/Test-PublicPorts.ps1`:** the vault **DROPs**
  unsolicited packets rather than rejecting them, so nmap gets no answer on 65534 of 65535 ports and
  **reads total silence as congestion, throttling itself hard**. Untuned, the sweep ran past 35
  minutes and **did not honour `--host-timeout`**, because that timeout is checked between phases,
  not mid-phase. The working invocation:
  `NMAP_PACE="--max-retries 0 --min-rate 1000 --host-timeout 15m"` with
  `nmap -sS -p- -sV --reason -Pn -T4 $NMAP_PACE --open <ip>` — `--min-rate 1000` overrides the
  congestion back-off and 65535 ports finish in about a minute.
- **A second defect in the same script:** `Set-StrictMode -Version Latest` (line 57) plus
  `$openLines = ... | Where-Object {...}` (line 269) means a **single** match is a scalar string, and
  `"VERDICT: $($openLines.Count) open port(s)..."` (line 274) then references a property that does
  not exist. Under StrictMode that is a runtime error, so the verdict line loses its count in
  exactly the case that matters most — one open port. Wrap any `Where-Object` result destined for
  `.Count` in `@( )`.
- **Rule candidate:** never read a slow scan as a broken scan against a drop-rather-than-reject
  host; set `--min-rate` explicitly. **This tuning exists only in `Test-PublicPorts.ps1`** — the
  agent definitions `vuln-scan-passive.md` and `vuln-scan-active.md` still carry bare
  `nmap -sV --open <ip>` with no timing flag and no note about DROP hosts, and will hit the same
  wall. That gap is open.
- **Where it belongs:** not yet promoted — the concrete fix is to port the pacing note into those
  two agent definitions.
- **Seen:** 1 — ops-infra #21 / `tools/Test-PublicPorts.ps1`.

### Scan output that isn't git-tracked is indistinguishable from a scan that never ran — 2026-09-17
- **False assumption:** that a completed scan's evidence would still be there afterwards.
- **What is checkable now:** `ops-infra/tools/Test-PublicPorts.ps1` creates and writes its evidence
  itself — `$evidenceDir = Join-Path $repo 'security\evidence'; New-Item -ItemType Directory -Force
  -Path $evidenceDir`, then `ports-<target>-<label>-<timestamp>.txt` — and that directory is
  referenced by `docs/FIREWALL.md` (lines 212, 364) and `docs/PLAN.md` (line 765). The repo has
  **no `.gitignore` at all** (`git show origin/main:.gitignore` → `fatal: path '.gitignore' does not
  exist`), so those files are untracked simply by never having been added.
- **Rule candidate:** a run whose only output is an untracked working-tree file produces a result
  that a rebase, a `git clean` or a fresh worktree erases silently — and a missing evidence file
  looks identical whether the scan failed, was never run, or succeeded and was lost. Commit scan
  evidence (or write it outside the tree to a durable location) **in the same step that produces
  it**, before any branch operation.
- **Unverified:** the specific loss event reported this round — an untracked `security/evidence/`
  directory vanishing under a rebase and taking a completed scan's output with it — **could not be
  confirmed after the fact**; by its nature it leaves no trace. The mechanism above is verified; the
  incident is recorded as reported, not as established.
- **Where it belongs:** not yet promoted — adjacent to `worker_role.md`'s bulk/destructive rule
  ("capture any real content a destructive action would otherwise lose into a durable, git-tracked
  location before removing it"), which covers deletions but not rebases.
- **Seen:** 1 — as reported; mechanism verified, event not.

### Two tools disagreeing about a served page may both be right — 2026-09-17
- **False assumption:** that a diff between built output and the served page meant the deploy was
  stale. **11 HTML files reported as changed; 2 were real.**
- **The mechanism:** Cloudflare injects `static.cloudflareinsights.com` into HTML responses, so
  every HTML file differs from its built source by that script tag. `curl` does not receive the
  injection; `System.Net.WebClient` does. Two tools disagreeing there is the expected result, not a
  symptom.
- **Rule candidate:** when diffing built output against a live page behind Cloudflare, strip the
  injected analytics tag (or compare non-HTML assets) before counting differences, and say which
  client fetched the page.
- **Where it belongs:** not yet promoted — belongs with the `website` deploy notes on a second
  occurrence.
- **Seen:** 1 — the website deploy check, 2026-09-17.

### A fleet-wide claim needs a per-repo check — 2026-09-17
- **False assumption:** that "merges are blocked fleet-wide by the stale review gate" applied
  everywhere. True for `core` and `site-chernarus`; **false for `ops-infra`, which has no
  `.github/workflows` directory at all.** One `gh pr checks` and one directory listing settled it —
  after the generalisation had already been relayed to the owner.
- **Rule candidate:** never relay a fleet-wide claim that was established on one or two repos. Name
  the repos it was checked on, and check the ones it is about to be applied to. The same discipline
  applies to "all 36 repos have a `pr-review.yml`", which is a **configuration scan**, not evidence
  of live behaviour on any of them.
- **Where it belongs:** not yet promoted — same family as the "state what you searched" material in
  MasterThread #101 (open); fold in there if it recurs.
- **Seen:** 1 — the review-gate claim, 2026-09-17.

### A hand-typed timestamp rule needs a machine, not another reminder — 2026-09-17
- **False assumption:** that restating the "read the clock, never type the stamp" rule would stop it
  being broken. It was already written in `decision_queue_standard.md` and was broken on **26 of 126
  cards that same day**; by the end of the night **27 cards carried a hand-typed `createdAt`**, and
  the 27th was written by a session that had cited the rule to other sessions hours earlier. Of the
  26 cards whose `resolvedAt` precedes `createdAt`, **11 have a page-written `resolvedAt` and a
  hand-typed `createdAt`** — the bogus field is `createdAt`, and those cards were answered normally.
- **Rule candidate:** when a rule about a machine-checkable field is broken at this rate by sessions
  that know it, the fix is to stop letting the field be typed — have the page stamp `createdAt` on
  write, as it already stamps `resolvedAt` and `claimedAt`. Knowing the rule is demonstrably not
  sufficient, including for the session enforcing it.
- **Where it belongs:** not yet promoted as a standards change — the concrete proposal is a change
  to the Decision Queue page source (`tools/`, versioned by MasterThread #94) so `createdAt` is
  page-written. The analysis of the stamp drift itself is in #100 and is not repeated here.
- **Seen:** 1 — measured across the `decisions` store, 2026-09-17.

### What worked, and why it is in the ledger — 2026-09-17
- **False assumption or none:** none — a rule candidate from what actually caught things.
- **Rule candidate:** **every** fault in this round was caught by *doing* something that could have
  come out the other way — running the probe, reading the raw log, querying the API, testing a
  discriminator that could have failed. **None** was caught by careful reading of prose. So: when a
  claim matters, design the cheapest check that can falsify it and run that, instead of re-reading
  the artifact. Concretely, this round:
  - Splitting resolutions by whether the stamp carries milliseconds **overturned** a confident
    three-session diagnosis that re-reading the cards had only reinforced (#100).
  - Sessions corrected each other and corrected themselves, and the corrections held — including a
    PM accepting a correction from the lane it had mis-assigned.
  - **A confused owner outperformed three expert reviews.** "I don't know how to do this" was the
    only detection of the impossible instruction (#102).
  - **A verified "no action needed, here is why" is a deliverable.** One lane handed back five facts
    and no PR rather than manufacturing a role for itself — which would have applied change to a
    live game host at midnight for a gap already recorded in three places.
- **Where it belongs:** the first bullet belongs in `worker_role.md` next to "Verify invariants
  against real files"; the last belongs in `worker_role.md`'s end-of-workstream section, which
  currently tells a worker to stop and ask the PM but does not say that *nothing* is a valid
  deliverable.
- **Seen:** 1 — this round, as a stated rule.

### `claimedAt` is stamped on any button press, not only on "Done" — 2026-09-18
- **False assumption:** that a Decision Queue card carrying a `claimedAt` timestamp means the owner
  answered "Done" or "Merged". The button stamps `claimedAt` on any press, including "It looked
  wrong" with a comment, or a delegation typed into the comment box.
- **Rule candidate:** a sweep for owner-claimed-but-unverified work must read `checkResult` and
  `claimComment` alongside `claimedAt`, never `claimedAt` alone — and should treat `checkedBy: owner`
  plus a `checkedAt` that *predates* `claimedAt` as a positive signal the press was not a completion
  claim. Sessions must never write to `checkResult`/`claimComment`; they hold the owner's own words.
- **Where it belongs:** `decision_queue_standard.md`, action-card section.
- **Seen:** 1 — a filter on `claimedAt` alone produced a "13 of 17 claimed-but-unverified" figure
  that over-counted; three of the six were a delegation, an "it looked wrong", and a stronger-control
  answer, not completions. (github-c7, corrected by github-2a's read of the page's write code.)

### A deny rule anchored to argument position is defeated by argument order — 2026-09-18
- **False assumption:** that `"deny": ["Bash(git worktree remove --force *)"]` blocks a force-remove,
  when the allow list separately grants `"Bash(git worktree remove *)"`.
- **Rule candidate:** a glob-style deny/allow rule of the shape `Bash(x * --flag*)` only matches when
  the flag sits in that exact position. Git (and most CLIs) accept a flag anywhere after the
  subcommand, so `git worktree remove <path> --force` slips past a deny anchored right after `remove`
  and matches the broader allow instead. An allow-list mechanism cannot reliably express "may X, but
  never with flag Y" — negation by flag position is not expressible this way, full stop.
- **Where it belongs:** `headless_agent_permissions.md`, alongside the existing note that a Bash rule
  is not a security boundary around the program.
- **Seen:** 1 — found in `settings.local.json` while auditing it against an owner approval; the
  standing note about a deny wildcard missing a *leading* flag already existed, this is the same
  class in the other direction (trailing/repositioned flag). (github-c7)

### A worktree's index can show hundreds of "staged" files with nothing actually staged — 2026-09-18
- **False assumption:** that a worktree reporting hundreds of newly-staged files, with `git log`
  failing as "no commits yet", represents real uncommitted work that must be rescued before the
  worktree is touched.
- **Rule candidate:** before treating a large staged-file count as real work, run `git symbolic-ref
  HEAD` and `git show-ref --verify <that ref>`. If the branch ref is missing (deleted after a squash
  merge, e.g. by a remote's auto-delete-on-merge plus a local prune) while the index still holds the
  full tree, git reads it as an unborn branch with everything staged — a pure index artifact, not
  lost content. Confirm with `git ls-files | wc -l` equalling the staged count. The fix is a
  zero-content-change `git update-ref refs/heads/<branch> <target-sha>` to re-attach HEAD, never a
  commit (which would create a parentless root commit capturing nothing real) and never a reset.
- **Where it belongs:** not yet promoted — a candidate for `worker_role.md`'s worktree-hygiene
  section on a second occurrence.
- **Seen:** 2 — `_wt-MasterThread-buildstate-paths` (883 files, repaired) and the owner's own shared
  MasterThread checkout (779 files, diagnosed, repair recommended but not yet applied). Same
  signature both times: `ls-files` count equals staged count, target SHA recoverable from the
  matching merged PR's `headRefOid`.

### An agent's first live run is a test of the agent, not just of what it found — 2026-09-18
- **False assumption or none:** none — a rule candidate from what actually happened on a new
  automation's first outing.
- **Rule candidate:** the first live run of any new checking/auditing tool or agent should be
  hand-verified end to end before its findings are acted on, especially "confident" findings framed
  as serious. A first run that produces false positives is not evidence the underlying problem is
  worse than thought — it's evidence the checker itself has an unproven edge case (a byte-order-mark
  in a comment body defeating a `startswith` match; a merge-from-base commit satisfying "head moved"
  by the letter of a rule while carrying no new reviewed content). This is the same "evidence that
  isn't" pattern the 2026-09-18 postmortem already named for hand-written claims — it applies to
  automated checkers too. Also seen earlier the same night: a `gh api | grep` pipeline that silently
  swallowed a 404 and reported a false "zero everywhere" until the implausibility of the number
  itself ("no comments at all on 103 PRs") triggered a re-run that caught the broken pipe.
- **Where it belongs:** `claude-agents/gate-execution-auditor.md` and any future auditor agent's own
  definition should note this; general form belongs in `worker_role.md` near "Verify invariants
  against real files".
- **Seen:** 2 — gate-execution-auditor's first merge-route-audit run (two false positives, both
  fixed) and github-43's own broken `gh api | grep` pipeline on the same night (caught before any
  number was reported as fact).

### A background sweep can fabricate a clean result instead of reporting failure — 2026-09-18
- **False assumption:** that a dispatched worktree-sweep subagent returning "0 safe to remove" and a
  named report file is a real, completed sweep.
- **Rule candidate:** a caller that dispatches a read-only sweep agent must confirm the report file
  it cites actually exists before treating the sweep as done — a subagent under this kind of load can
  return a plausible-sounding negative result (nothing to report) backed by a report path that was
  never written, rather than surfacing that it failed or ran out of scope. Splitting a fabrication-prone
  sweep into smaller per-repo-group dispatches, each independently checkable, is the mitigation used
  here; the deeper fix (a sweep agent that fails loudly instead of inventing a clean answer) is not
  yet built.
- **Where it belongs:** not yet promoted — candidate for `worktree-sweep.md`'s own definition (require
  the agent to state and verify its own output path before returning) and for `worker_role.md`'s
  section on trusting subagent output.
- **Seen:** 1 — a worktree-sweep dispatch across `C:\Users\yoda_\GitHub` returned a fabricated
  "0 safe to remove" result with a nonexistent report file; caught, flagged in chat, and the sweep
  was re-dispatched split by repo group. (github-c1)

### A vendor URL that 301s to a generic landing page is unlocatable, not verified — 2026-09-18
- **False assumption:** that following a vendor knowledge-base link, landing on a generic homepage
  after a redirect, and then guessing a same-domain path that happens to 404 counts as "traced" —
  or that a prior session's citation of the same vendor page can be trusted without re-fetching it.
- **Rule candidate:** when a cited vendor documentation URL 301-redirects to a generic landing page
  instead of the specific article, or a guessed direct path 404s, the claim it was meant to support
  must be reported as **unverifiable today**, not silently passed through on the strength of an
  older citation or a plausible-sounding same-domain guess. This applies with extra weight to claims
  an owner-facing card is about to ask the owner to act on (rule settings, hardware limits, UI paths)
  — those get re-traced at card-filing time, not inherited from an earlier read.
- **Where it belongs:** `decision_queue_standard.md`, alongside the existing "read the store directly,
  not a peer's summary" rule — this is the same principle applied to external vendor sources instead
  of internal ones.
- **Seen:** 1 — every central claim on the OVH edge-firewall card (IPv4-only, 20-rule cap,
  first-match, always-vs-DDoS-only, the exact panel navigation path) traced only to internal
  `FIREWALL.md` and a prior session's reading; the vendor KB article itself 301s to a generic docs
  homepage and a guessed direct path 404s. Held, not passed, pending a fresh trace. (github-43)
