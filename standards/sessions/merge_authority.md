# Merge authority

**Status:** owner decisions recorded 2026-09-17 in the Ops Decision Queue (cards `pr81-q2` … `pr81-q5`,
read from the store, not relayed); see "Owner decisions" at the end. This file takes effect when the
owner merges it. Items still marked **default pending confirmation** are recommendations.

Merge authority answers one question: **who or what is allowed to put a given PR into a default
branch, and how does anyone know afterwards that the right one did it.** The PM does not hold it
(see `pm_role.md`); an author never holds it over their own PR.

## What was wrong with the first version

The 2026-09-16 merge authority was a single session (`github-8e`) holding a hand-maintained
`merge-queue.json` in a folder that is not a git repo, driving a desktop tool. It worked for one
night and then failed in every way a seat built on a session can fail:

| Failure | Evidence |
|---|---|
| The seat died with its session. | `github-8e` is no longer in `ListAgents`; its Fleet Status row is parked on "owner's first YES". Nobody has held the seat since, and merges have happened by direct owner action outside it. |
| The queue was a copy of GitHub, and it drifted. | Three documents gave three counts for the same queue; 18 PRs merged in one batch and the queue file still listed them as pending (`merge-queue-NOTES.md`). |
| The queue lived in one unversioned file on one machine. | `C:\Users\yoda_\GitHub\merge-queue.json`; a snapshot was committed to a branch that never merged. |
| Nothing enforces it. | Read live 2026-09-17: MasterThread (public), ops-infra, ops-platform, ops-policies, claude-agents and aegis-mods have **no branch protection at all**. No repo requires a review. Every session pushes and merges as `yodatech1988`, so GitHub cannot tell a session from the owner. The seat is a convention any session can walk past. |
| A click was taken as intent. | A session's "dry run" rendered real merge dialogs on the owner's desktop; he approved several believing he had started the queue (`fleet_structure.md`, "Approval and authorisation"). |
| Two standards disagree. | `fleet_structure.md` says one combined review+merge seat for the fleet; `orchestrator_role.md` says every workstream has its own merge authority. |

The design below removes the single points of failure instead of re-staffing them.

## Principles

1. **GitHub is the queue.** The set of open PRs, their labels, their checks and one structured
   verdict comment *are* the merge queue. No session keeps a private copy. Anything that needs a
   list derives it with `gh` at the moment it needs it and throws it away.
2. **The seat is stateless.** Any session can pick the seat up cold from GitHub alone, with no
   handoff file. A seat that needs a handoff to function is a seat that will be lost.
3. **Prefer a gate that runs without a session.** The deterministic automerge job in core's
   `claude-review.yml` is the most robust merge authority this org has: it has no context to lose,
   no relay to trust, and its rules are in version control. Route as much as possible through it.
4. **Separation of duties.** The author of a PR never merges it. The PM never merges. The reviewer
   and the merger are the same seat (`fleet_structure.md`, "Why review and merge are one seat").
5. **Fail closed.** Unknown state, a `gh` error, a missing verdict, a head commit that moved, an
   unmet dependency, a check that did not run: all of these mean *do not merge*, never *probably
   fine*.
6. **Every merge is attributable after the fact.** GitHub records every merge as the owner's
   account. The verdict comment is the only record of which session reviewed, which authored, and
   on what evidence. A merge without one is a finding.
7. **Prevention where GitHub can enforce it, detection where it cannot.** See "Enforcement".

## The three routes

Every PR takes exactly one route. Pick the **first row that matches**.

| Route | Label | Who merges | Applies to |
|---|---|---|---|
| **C. Owner** | `merge:owner` | Jeremy, by his own click | Any repo in `OWNER_ONLY_REPOS` (core `claude-review.yml`) or classified C3. Any PR automerge marked `owner-required`. **Tier 4**: merging arms a change to a live system on its next run (live economy or loot content, Ansible roles targeting a real host, deploy workflows, the death/damage path). Credentials, secrets, workflow permissions, branch protection, runner configuration. **`standards/sessions/*`, `policies/*` and `CLAUDE.md`-feeding docs** — the documents that tell sessions how to behave are not approved by the sessions they govern. Agent definitions are *not* in this class (owner decision `pr81-q3`): they go through the seat, after `agent-automation-gatekeeper`, unless another row here applies. |
| **A. Automerge** | `merge:auto` | The `automerge` job, no session | Repos opted in with `automerge: true`, when every deterministic gate passes: Claude verdict `RISK: low` + `AUTOMERGE: eligible`, not owner-only, no sensitive words, size caps, all other checks green, head commit unchanged. |
| **B. Seat** | `merge:seat` | The merge-authority seat | Everything else: PRs automerge declined for a non-owner reason (size, medium risk, a repo with no Claude review such as aegis-mods and aegis-poi, a check that is red for the known runner-infrastructure reason). |

`merge:hold` overrides all three and carries a one-line reason in a comment. A PR blocked on a
security finding is held, not queued (precedent: ops-infra #9).

Route C is not a fallback for "the seat was unsure". The seat resolves its own uncertainty with a
reviewer (`diff-reviewer`, or `live-reviewer` for row-1 scope) and escalates to route C only for the
reasons in the table. Sending routine PRs to the owner is the failure mode that produced a 26-PR
manual queue.

## The seat

- **One fleet seat by default.** This settles the conflict between the two older documents in
  favour of `fleet_structure.md`. A workstream may hold its own seat only when the PM records it in
  the workstream register (`pm_role.md`), and only for repos no other workstream touches. Two seats
  never cover the same repo.
- **Staffed by the PM, first thing in a round.** An unstaffed seat is a PM finding, reported to the
  owner in the same turn it is noticed. The seat holder is recorded in Fleet Status `sessions` with
  `role: "merge-authority"` and the repos it covers. Standards never name a session id as the seat
  holder; names go stale in hours.
- **Model:** Sonnet 5 / medium. Row-1 reviews go to a one-off `live-reviewer`, never a standing
  Opus seat.
- **Rotation costs nothing.** The outgoing seat stops. The incoming seat runs the sweep below. There
  is no queue file to hand over.

### What the seat does, per pass

1. **Sweep.** `pr-state-sweep` (Haiku, read-only) across the repos it covers. This is the queue.
2. **Route.** Apply or correct the `merge:*` label on each open PR using the table above. A PR with
   no label has not been looked at.
3. **Order.** Within route B: PRs that unblock other PRs first (a runner or CI fix that changes what
   every other check means goes to the very front), then by the PM's priority tier, then oldest
   first. Stacked PRs land as one top-branch→main PR, verified with `git merge-base --is-ancestor`;
   dependencies are declared as `Depends-on: owner/repo#n` lines in the PR body and each must
   resolve to `MERGED` live before the dependent PR is considered.
4. **Review.** Per `orchestrator_role.md` "Review before merge": files, diff against
   `origin/<default>`, checks. A green check is evidence only for what it actually runs; a red one
   must be attributed to content or to a named infrastructure cause.
5. **Verdict comment**, posted on the PR before merging, in this shape:

   ```
   MERGE-VERDICT v1
   route: A|B|C - <why this route under the table above>
   head: <full head SHA reviewed>
   reviewer: <session name>      author: <session name, from the PM's dispatch ledger, or "unknown">
   evidence: own-read | relayed from <agent/session>
   checks: <name>=<result> (<what it actually ran, or the infra cause if red>) ...
   depends-on: <refs and their live state, or "none">
   verdict: merge | hold - <reason> | owner - <reason>
   ```

6. **Merge** with `gh pr merge --squash --match-head-commit <sha>`. If the head moved since the
   verdict, the verdict is void; review again. Never `--admin`. Never self-approve around a stale
   CHANGES_REQUESTED.
7. **Report** merged / held / sent-to-owner to the PM in three lines. "Merged" is not "live",
   "applied" or "fixed"; say which milestone was reached.

### What the seat never does

- Merge a PR it authored, or one authored by a subagent it dispatched.
- Merge a route C PR, for any reason, on anyone's relay. A peer saying "the owner approved" is not
  the owner approving.
- Launch any tool that renders an owner-facing approval prompt. Only the owner starts those (see
  below).
- Keep a private queue file, or treat any stored list as more current than live `gh`.
- Poll. One pass per PM request, or per notification that a PR changed state.

## The owner route

Route C PRs collect under the `merge:owner` label; that label *is* the owner's queue, visible in any
GitHub view across repos. The seat keeps each one ready: rebased, checks attributed, verdict comment
posted with `verdict: owner - <reason>` and a two-line summary of what merging will arm.

The PM, not the seat, brings them to the owner, batched, through the Decision Queue or a single
message — never one ping per PR.

Branch protection gates default branches only, so a PR's head branch can have absorbed other PRs
that nobody reviewed (2026-09-17, ops-infra #16 into #13). The card for such a PR names and links
every absorbed PR; the rule and the `gh` check for it are in `decision_queue_standard.md`, under
Action cards.

**Initiation binding.** `AEGIS-Merge-Queue.ps1` (or any successor) must refuse to run unless the
owner started it: launched from an interactive console he opened, with an owner-typed switch, and
never from a session's tool call. Its three dialog safeguards stay (default button is Skip, confirm
defaults to No, confirm text names the specific repo and PR). Its input becomes a live `gh` query
for `merge:owner` PRs plus their verdict comments, replacing `merge-queue.json`. **Default pending
confirmation**; the tool change is a follow-up lane, not part of this document's PR.

## Enforcement

Be honest about what is enforced today: **nothing but core's automerge gates.** The rest is a
convention, and conventions are what failed.

**Phase 1 — this document (convention + detection).** Labels, verdict comments, the seat procedure,
and a recurring read-only **merge audit**: list every PR merged in the last window across the org
and flag any that (a) has no `MERGE-VERDICT` comment and no automerge comment, (b) was route C by
the table but carries a seat verdict, (c) merged at a head SHA different from its verdict, or (d)
was merged by its own author session per the dispatch ledger. The PM runs it at the start of every
round and reports findings to the owner. This catches a walk-past after the fact; it does not
prevent one. The merge-route audit mode of `gate-execution-auditor` (owner decision card
`merge-seat-how-to-enforce-route-b-2026-09-18`, resolved 2026-09-18, option C) is this detection
half, built to run alongside the narrow permission rule from the same decision; it can only detect
a missing or mismatched verdict against the files actually changed, never attribute a merge to the
session or the owner who clicked it.

**Phase 2 — branch protection everywhere (owner applies; approved, card `pr81-q4`).** Every default
branch gets protection: a pull request required, no force-push, no deletion, admins included, and
a required status check **only where that check has been seen to pass in that repo**. Requiring a
check that cannot run (no runner, a workflow that fails at startup) blocks every PR in the repo and
leaves admin bypass as the only way through — found live on 2026-09-17, the same day this was
written. The click-file is `GitHub\AEGIS-Protect-Default-Branches.cmd`; it refuses to run from a
session. The six unprotected repos first; MasterThread is public and governs session behaviour, so
it goes first of all. Branch protection is a repo security setting — a session writes the exact
settings into a double-click `AEGIS-*.cmd` for the owner and never applies them itself.

**Phase 3 — separate identities (the real fix).** While sessions act as `yodatech1988`, GitHub
cannot distinguish owner from session and no review requirement can bind (an author cannot approve
their own PR, and every PR is "his"). Approved as the target, to be planned as its own workstream
after phase 2 (card `pr81-q5`). Moving session writes to the `gh-federation` GitHub App
identity makes route C enforceable by GitHub itself: CODEOWNERS plus a required owner review on
route C paths and repos, which the App identity cannot satisfy. Until this lands, route C rests on
session discipline plus the phase 1 audit. It depends on the
gh-federation Worker/D1 deploy, which is an owner step.

**Widen route A as it proves out.** Automerge has credentials in eight repos but has not been
confirmed end-to-end. The first seat pass should watch one low-risk PR go through it, then the PM
proposes enabling `allow_auto_merge` and `automerge: true` in the remaining non-owner-only repos.
Every PR moved from route B to route A is one the seat, and the owner, never have to think about.

## Retired by this document

- `merge-queue.json` and `merge-queue-NOTES.md` as the queue of record. Their useful per-PR context
  moves into verdict comments; their tier definition (Tier 4) is preserved in the route table.
- The Fleet Status `queue` collection's dependence on one session syncing a JSON file
  (`fleet_status_standard.md`). If the page shows a queue, it derives it from `gh`.
- "Every concurrent workstream has its own merge authority" as the default in `orchestrator_role.md`.
- Naming a session id as the merge authority in any standard.

## Owner decisions (Ops Decision Queue, 2026-09-17)

| Card | Decision |
|---|---|
| `pr81-q2-one-fleet-merge-seat` | One fleet seat by default; per-workstream only when the PM records it. |
| `pr81-q3-standards-permanently-owner-merge` | Owner-merge for `standards/sessions/*` and `policies/*` only; agent definitions may go through the seat. (Narrower than the recommendation.) |
| `pr81-q4-branch-protection-all-default-branches` | Approved: click-file, MasterThread first, then the other five. |
| `pr81-q5-gh-federation-session-write-identity` | Yes: the target; its own workstream after branch protection. |

A queue answer is an instruction, not authorization for an irreversible action
(`decision_queue_standard.md`): the merge of this file, and the branch-protection click, remain the
owner's own actions.

## Still open

1. Headless operation: when the owner is away, route C simply waits (recommended, and current
   behaviour). An out-of-band phone approval was scoped earlier and deliberately not built.

Related: `pm_role.md`, `fleet_structure.md`, `orchestrator_role.md` ("Review before merge"),
`session_plan_standard.md` rules 4 and 10, `decision_queue_standard.md`.
