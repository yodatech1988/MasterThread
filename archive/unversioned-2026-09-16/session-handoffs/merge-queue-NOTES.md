# merge-queue.json — context for whoever reads this next

**Snapshot check, update this line every time you touch either file:** as of the
last edit to this notes file, `merge-queue.json` held **30 entries** — Tier 1: 21,
Tier 2: 1, Tier 3: 3 (services#97, core#78, aegis-mods#48 — the first two must be
reviewed in that order, before any Tier 1 entry, per their qcSummary text), Tier 4:
5 (including ops-infra #10 and #11). Before trusting anything below, re-run
`python -c "import json; d=json.load(open('merge-queue.json'));
print(len(d))"` (or equivalent) and confirm it still says 30 — if it doesn't, this
file is stale and the JSON is the one to believe, not this document. This exact
kind of drift (three documents, three different counts — this file, a PM handoff,
and the actual JSON) already happened once tonight; the fix is checking the
number, not assuming the prose is current.

This file exists because `merge-queue.json` (same directory) is a flat JSON array
consumed literally by `AEGIS-Merge-Queue.ps1` — every element in that array must be a
real PR entry with `repo`/`pr`, or the tool will try to `gh pr view` a bad record
mid-loop. So context that isn't a per-PR field can't live inside the queue file
itself. It lives here instead.

## Ownership

`merge-queue.json` is the durable state of the merge pipeline, not this session's
memory of it. If the session that maintains it (Merge Authority lane, `github-8e`
as of 2026-09-16) ends or is replaced, the next session should treat the JSON file
as authoritative and this file as the annotations that don't fit its schema —
not reconstruct the queue from chat history.

## ops-infra #9 is *deliberately omitted*, not just unlisted

It does not appear anywhere in `merge-queue.json`. This is not an oversight — PM
`github-64` ruled it must never appear as an approvable item, because it's blocked
on a **security finding**, not on the merge mechanism. live-reviewer returned
CHANGES REQUESTED / HOLD FOR OWNER on its `vps-drift-checker.md` half: unrestricted
`Bash` tool with no key restriction, passwordless root sudo on both hosts, bypasses
`Invoke-Ansible.ps1`'s existing read-only controls, and would go live immediately
with no enable step — the first fleet agent holding an authenticated admin session
on the vault and a live player-facing server. The PR stays whole (not split) per
PM instruction, since its authoring session is unidentified and nobody owns a split.
It needs Jeremy's decision on the substance (reject, or rework via one of
live-reviewer's three remediation routes), not a place in this queue. If it ever
does clear, it re-enters the queue as a fresh entry — don't un-omit the old one
without a fresh verdict.

## What "Tier 4" means here

Tier 4 was redefined mid-session from "content that's currently live" to
**"merging arms something that changes a live system on its next run"** — it does
not require the merge itself to touch a running service. ops-infra #10 (an Ansible
role targeting personal-vault) was the PR that forced this redefinition — it isn't
in the current queue (see "Withheld PRs" below), but if/when it returns, it belongs
in Tier 4 alongside site-chernarus #96/#94/#88 (live game-economy content) for the
same reason: merging it wouldn't change vault behavior today, but it would change
what the *next* `ansible-playbook` run against personal-vault does, possibly
without whoever runs it realizing a merge changed the auth config underneath them.
Tiers 1-3 assume "merged" and "live/applied/fixed" are different milestones that
stay separate even after merge (see per-entry caveats: #97 merged ≠ runner
reinstalled, #13 merged ≠ boot-verified, #98 merged ≠ deployed since that repo has
no deploy workflow at all).

## ops-infra #10 and #11 — RE-ADDED, real dependsOn enforcement now live

**In `merge-queue.json`, both Tier 4, as of PM `github-64`'s go-ahead.** They were
briefly withheld earlier tonight (see git history of this file / chat log if you
need the withheld-period reasoning) purely because `AEGIS-Merge-Queue.ps1` had no
dependency-awareness — a `dependsOn` field added without matching script logic
would have been cosmetic, and the standard held tonight is not to ship a
guard that looks real but enforces nothing. github-85 then built real enforcement
(confirmed by reading the script directly, not by trusting the description):
`Test-DependencyMerged` in `AEGIS-Merge-Queue.ps1` resolves each `dependsOn` ref
live via `gh pr view --json state`, requires exactly `MERGED`, and fails closed —
a `gh` error, a missing state, or any other value all count as unmet and the entry
is auto-skipped with **no YES prompt offered at all**. Once that landed, #10/#11
re-entered the queue.

**Structural reason they're linked**: #11's branch (`agent/ops-infra/session8-b3b4-
regression-tests`) is based on #10's branch (`agent/ops-infra/session8-postgres-
audit`), not main — confirmed via `git merge-base --is-ancestor`. Per the standing
stacked-PR convention, they land as **one top-branch→main PR**, not two
independent merges.

**Encoded in the JSON now**: `ops-infra#10`'s entry carries
`"dependsOn": ["yodatech1988/ops-infra#11"]`; `ops-infra#11`'s entry carries none.
**This direction is the one that matters and is easy to get backwards**: #11's
actual GitHub base is #10's branch, not main, so merging #11 is always safe
standalone — it never touches main. #10 is the one that must wait, because its
merge (into main) is what actually carries both changesets as the single
top-branch→main landing. Getting this inverted would produce a tool that blocks
the safe merge and permits the unsafe one. Re-verify with `git merge-base
--is-ancestor` after #11 merges, before #10 merges, to confirm the stack landed as
intended rather than assuming the enforcement alone guarantees it.

## services #97 — should run first, and the tool can't quite say so yet

**Currently Tier 3 in the JSON, displayed after all 19 Tier 1 entries when Jeremy
runs the tool — that ordering is wrong in spirit, and I don't yet have a clean fix
for it.** `services#97` fixes the self-hosted-runner bug (missing `gh` CLI,
missing `unzip`) that is currently the *reason* several other queued PRs
(`core#77`, `services#93`, `site-chernarus#99`) show red checks that mean nothing.
Confirmed independently: `services`' own `blocking-issues` and `secret-scan` jobs
are failing for the same reason right now. Until #97 actually merges *and* someone
re-runs the fixed installer on the VPS (merged ≠ fixed — see its `qcSummary`),
every CI check in the queue should be read with that in mind.

**Why it isn't just retiered to Tier 1 or given `tier: 0`**: `AEGIS-Merge-Queue.ps1`
groups strictly by tier, ascending, with no concept of "before all tiers" — the only
way to make an entry display first today is `tier: 0`, which the script hardcodes to
print as **"untiered"**, a label that says nothing about priority and would read as
a mistake, not an intentional signal. Retiering it into Tier 1 would bury the "read
this first, it changes what every check below means" framing among 19 ordinary docs
PRs. Neither option says what actually needs saying.

**What this needs**: a small script addition (parallel precedent: tonight's
`dependsOn` enforcement) — something like a `reviewFirst: true` field that pulls
matching entries to the very front of the whole list, before tier grouping, with
its own labeled section (not "untiered"). Flagged to PM `github-64` for github-85;
until it lands, `services#97` stays at Tier 3 with an unmissable priority line at
the front of its own `qcSummary`, and Jeremy should be told directly (not just via
this file) to look at it before the rest of the queue regardless of where it sits
on screen.

## aegis-poi #13 — pulled entirely, blocked on a pre-existing compile defect

**Not in `merge-queue.json`.** Its former Tier 3 entry said "explicitly NOT
boot-tested." That caveat was accurate — and boot-testing it (github-1e, via a
throwaway signing key and a scoped unpause) turned up a real defect: the module
**does not compile under Expansion at all**. `AEGIS_POI_BlackMarket_ReputationGate.c
:83`, inside `modded class ExpansionMarketModule.CheckCanUseTrader`, passes an
`ExpansionTraderObjectBase` into `TryGetMinReputation(EntityAI, ...)` — "Types are
unrelated. Cannot convert." That single error cascades into ~130 more and ends in
"Can't compile World script module." Any server loading `AEGIS_POI_BlackMarket`
alongside Expansion (the network's standard mod list) fails to boot entirely.

Unlike ops-infra #10/#11, **no tooling or enforcement fix unblocks this** — it needs
an actual code fix to the type mismatch, then a fresh boot test, before it can
re-enter the queue as a new entry. Two things worth being precise about:

- **Not a regression from the crash fix.** The offending line predates the
  reputation-gate dangling-handle fix that PR #13 also carries — it sits in the
  original paused Session 4 WIP, and #13 carried it forward unchanged. The crash
  fix logic itself is still independently verified sound (Unregister/Clear
  ordering in Shutdown(), no race). The module around it is broken separately.
- **No production impact.** The module was never merged or published, so nothing
  live was ever at risk — this is a "would have shipped broken had we skipped
  boot-testing" catch, not an incident.

Worked example for the same principle as the #57/#54 entry below, from the other
direction: that one showed a *phantom* dependency someone asserted without
checking. This one shows the opposite failure — a caveat ("not boot-tested") that
was honestly stated and still hid a real, boot-blocking defect until someone
actually ran it. **Unverified and fine are not the same claim**, in either
direction; only actually running the thing (or checking the actual diff, per
#57/#54) distinguishes them.

## Semantic (content) dependencies are invisible to every structural check

A full `baseRefName` sweep of all 25 queued entries (2026-09-16) found no hidden
stacking beyond the #10/#11 case above — every entry bases against its repo's real
default branch. But `git merge-base`/`baseRefName` only catches *structural*
stacking (one PR's branch built on another's). It cannot catch a PR whose *content*
assumes another unmerged PR's files exist — git has no idea a Markdown file refers
to another Markdown file.

**Worked example, resolved:** PM github-64 flagged MasterThread #57 (Skills program)
as possibly depending on #54 (unmerged), since #57's new SKILL.md files mention
`task_sizing.md`. Independently verified by hand (`git show`/`git diff` against
both branches, not just trusting either side's claim): #57's references are all to
`task_sizing.md`'s pre-existing S/M/L/XL sizing bands, which are already on main
today, independent of #54. None of #57's files reference `worker_intro_prompt.md`
or the new "Real-time effort telemetry" section #54 adds to `task_sizing.md` — those
two strings don't appear anywhere in #57's diff. So #57 has **no actual content
dependency on #54** and was correctly cleared by github-6b's original QC pass. The
lesson to carry forward isn't "#57 was fine" — it's that a same-file-name mention is
not the same as a dependency, and confirming that took reading actual diffs on both
sides, not trusting either the concern or the reassurance at face value.

## claude-agents #27's clearance is manual-read-only

Its `qcSummary` says this, but worth restating here because it's easy to miss: the
"no secrets" finding for #27 (GitHubTwoFactorKey.ps1) rests entirely on
live-reviewer's manual read of the diff. This repo has **no secret-scan CI job at
all**, so a green CI check on this PR is not secret-scan evidence and must never be
cited as if it were.

## Several entries have empty `statusCheckRollup`

MasterThread, ops-policies, and ops-platform have no CI configured at all for some
or all of their PRs in this queue (`statusCheckRollup: []` when checked via
`gh pr view`). That's not a passing check — it's the absence of one. Every PASS
verdict on those entries rests entirely on QC/live-reviewer's manual read, same as
#27. Don't let "no CI failures shown" be misread as "CI passed."

## Verification standard applied while building this file

Every entry in `merge-queue.json` was independently checked against live GitHub
state (`gh pr view ... --json mergeable,mergeStateStatus,statusCheckRollup,files`)
by the Merge Authority session before being added — not accepted on a QC verdict's
say-so alone. Where a CI failure was attributed to the known self-hosted-runner
infra bug (missing `unzip`/`bun`, broken `gh` CLI, broken gitleaks install), that
attribution was confirmed by reading the actual failing job log, not assumed from
the pattern. `AEGIS-Merge-Queue.ps1` itself was read in full before being trusted,
then dry-run non-interactively against the real queue file to confirm it displays
correctly and cannot be scripted past its `Read-Host` gate.

## Queue size over time — zero merges all night

Tracking this because it's a trend, not a fact about any single PR: the queue has
only grown, never shrunk from a merge, across an entire session. Real trajectory
(from this session's own running log, not a retrospective estimate — the number
moved for a specific verified reason every time):

25 → 26 (added aegis-poi#12, a real gap) → 25 (removed ops-infra#10, all-stop) →
24 (removed aegis-poi#13, compile defect) → 26 (re-added ops-infra#10/#11 with
real `dependsOn` enforcement) → 29 (added MasterThread#57/#58, aegis-mods#48 —
all had real unrouted QC verdicts found during the full-estate reconciliation) →
**30** (added core#78). **Zero merged**, the entire time.

This is not evidence the bar is too high or that verification should slow down —
every add/remove above was a real, checked reason, several of which caught actual
defects (aegis-poi#13's compile failure) or actual gaps (aegis-poi#12, the three
unrouted verdicts). It's evidence the fleet produces PRs faster than a
one-PR-at-a-time typed-YES desktop tool can clear them, and that restoring
automerge (services#97 → core#78 → the Actions-token permission fix on
aegis-mods/claude-agents/aegis-poi, in that order) is the actual fix, not a
convenience layered on top. If this count is still climbing next time someone
checks, that's the number to show Jeremy, not a summary of it.

## Reconciliation against every open PR across the estate (2026-09-16)

PM audit found the queue had drifted from a full sweep of open PRs. Ran that
sweep myself: `gh pr list --state open` across every repo touched tonight
(aegis-mods, aegis-pricing, site-badlands, claude-agents, MasterThread,
site-chernarus, core, services, ops-policies, ops-platform, aegis-poi, ops-infra,
website, jarvis, handymansfield) — **39 open PRs total**. 29 are now in the queue.
Below is every one of the other 10, with the real reason it isn't — split
deliberate-exclusion from simply-not-reviewed-yet, per the PM's ask not to guess.

**Deliberately excluded — do not add without a fresh decision:**
- **MasterThread #54** — reserved for Jeremy's own direct review (owner-review
  PR, per earlier standing note in this session). Also the PR several other
  queued entries semantically depend on (#55 confirmed real dependency, see its
  `dependsOn`).
- **aegis-poi #13** — blocked on the `ReputationGate.c:83` compile defect under
  Expansion. See its own section above. Returns only after a real fix + fresh
  boot test.
- **ops-infra #9** — blocked on the live-reviewer security finding
  (unrestricted Bash, passwordless root sudo, no enable step). See its own
  section above. Needs Jeremy's decision on the substance.

**Not reviewed yet — missing a QC verdict, not excluded on purpose:**
- **claude-agents #28** (`Get-StoredConfig` DPAPI hardening, the #27 follow-up)
  — PM said add once QC clears it; no verdict routed to me yet.
- **site-chernarus #87** (Community Online Tools for reputation admin testing —
  its own title flags "verify ID before merge", so this needs identity/access
  scrutiny specifically, not just a normal content read) — no QC verdict seen.
- **site-chernarus #93** ("Trader ammo categories by weapon type, not tier") —
  a different PR from `services#93` already in the queue; easy to conflate by
  number alone across repos. No QC verdict seen.
- **core #73** ("Session 5: port site-chernarus's sync improvements... add
  check_trader_items_exist") — no QC verdict seen.
- **website #27** ("Wire real PayPal donate button into /fund/") — **flag this
  one specifically**: it's payment/money-handling code on the public website.
  If it ever gets a QC pass, it should go through the same live-reviewer
  escalation path as claude-agents#27 and ops-infra#10 (row-1: money), not a
  normal diff-reviewer PASS — don't let the "#27" in its number cause it to be
  confused with the already-cleared claude-agents#27.
- **jarvis #14** (T4 subagent docs) — no QC verdict seen. Also worth noting:
  `jarvis` is on the standing exclusion list for VPS CI runners (personal
  repo / personal-financial adjacency per prior decision) — that's a runner
  placement rule, not necessarily a reason to exclude its PRs from a merge
  queue, but it's a signal to apply extra care rather than treat it as a
  routine docs PR.
- **handymansfield #10** (T4 subagent docs) — no QC verdict seen. Also worth
  flagging: HandyMansfield is a separate client-facing business, not part of
  the AEGIS ops estate — confirm whether tonight's fleet is even meant to be
  reviewing it before treating a future QC pass on it as in-scope.

None of the seven "not reviewed yet" items should be read as vetted-and-skipped
— they simply haven't reached QC/this queue. Don't assume safety from absence.

## Nothing in this file authorizes a merge

This is context, not approval. Every PR in `merge-queue.json` still requires
Jeremy to run `AEGIS-Merge-Queue.cmd` himself and type the literal, case-sensitive
word `YES` per PR. No batch approval exists or should ever be added.
