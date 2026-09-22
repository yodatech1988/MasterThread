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
| The queue lived in one unversioned file on one machine. | `<USER_HOME>\GitHub\merge-queue.json`; a snapshot was committed to a branch that never merged. |
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

**Route B without the owner's click: ops platform classes (owner decision card
`decision-ops-platform-auto-merge-classes-2026-09-21`, answered 2026-09-21).** The seat may merge these
two kinds of PR itself even where the repo would otherwise send it to route C. Nothing else widens,
except the separate classes recorded after this list:

- (a) **Docs-only PRs, and unwired library code, in `ops-platform`.** Unwired means not imported or
  called by anything deployed, with no network or credential handling wired.
- (b) **CI workflow files (`.github/workflows/*`) in `ops-platform`, `ops-household` and `ops-business`;
  in `ops-infra` only files under `.github`, never `ansible`, plays or `tools`.**

Each merge requires **all** of: an independent read-only review (`diff-reviewer` or equivalent) that
says MERGE; a clean-clone test run that matches the claimed baseline where tests exist; every PR check
green (a `startup_failure` of `pr-review` is not green, and is reported); a verdict comment that states
the route and lists what was checked; and a merge pinned to the reviewed head SHA
(`--match-head-commit`, SHA shape asserted as above).

**Route B class: trivial reviewed ops-infra PR (owner decision card
`decision-ops-infra-auto-merge-scope-2026-09-21`, answered 2026-09-21T18:19:53Z, option A: "Trivial
reviewed ops-infra PRs only (one file, about 5 lines, comments, docs or scanner-exception files)").**
The seat may merge an `ops-infra` PR that meets **every** condition below. This is the only class
that reaches into `ops-infra` outside `.github`; it is deliberately narrow because ops-infra content
is applied to the vault by a later run.

- **One file, at most 5 changed lines, counting added plus removed.**
- **The change is only comments in a non-template file, docs (`*.md`) or scanner-exception files.**
  Docs: not `CLAUDE.md`, `standards/`, `policies/`, `.claude/agents/` or any file that holds commands
  to be run (runbooks, click-file docs). Scanner-exception files: `.trivyignore.yaml` only, or a file
  the owner names on a card; adding or widening an exception (a new finding id, path or wildcard) is
  route C, while removing an exception or fixing its comment is allowed. Not Ansible tasks, vars,
  handlers or templates; a change under `ansible/` is route C. Whether a comment-only change inside a
  rendered template may join this class is an open owner question; until he answers it, it is route C.
  Any doubt means route C (PR #48 was such a case: a comment line in a role template that tripped a
  guard).
- **Not** `tools/*Key.ps1`, not workflow permissions, secrets or `pull_request_target`.
- **An independent read-only review that says MERGE, recorded as `MERGE-VERDICT v1` (see "What the seat does")
  on the exact head SHA.**
- **All checks green.** A `startup_failure` or an absent check does not count as green.
- **The merger is not the author**, and merges with `gh pr merge --squash --match-head-commit <sha>`
  on a `<sha>` validated as 40 lowercase hex characters.
- **Logged and undoable:** every automatic merge in this class is listed in the daily digest with a
  revert link, and an owner undo pauses the class until the owner resumes it.

**Route B one-line workflow change: separate from the class above (owner decision card
`decision-review-tier-one-liners-route-b-2026-09-20`, answered 2026-09-20T15:07:04Z, "Yes: allow it
under those four conditions").** The card concerned a one-line change to a repo's review-depth setting
in `.github/workflows/pr-review.yml`. The seat may merge such a PR itself when all four hold: (1)
exactly one changed line, checked by reading the diff; (2) the repo is not owner-only; (3) a reviewer
passes it; (4) all checks are green. Any owner undo pauses this rule until the owner resumes it.
The four conditions were recorded on the card; the card's own text did not restate the pinned-SHA
and verdict-comment requirements, which apply to every route B merge regardless.

**Mechanism.** Today the acting seat (named on the Fleet Status board) performs route B by hand. For unattended operation the owner chose (card
`decision-headless-merge-mechanism-2026-09-21`, answered 2026-09-21T18:29:58Z, option A: "GitHub
workflow with fixed rules (fix the startup failure first, one repo at a time, ops-platform before
ops-infra)") a GitHub workflow: the `automerge` job in core's `claude-review.yml` with deterministic
gates. **It is not live in any repo yet.** It is to be enabled one repo at a time, `ops-platform`
before `ops-infra`, and only after the `startup_failure` on the callers is fixed. Until a repo's
workflow is live, the seat merges that repo's PRs by hand under the conditions above. Enabling
`allow_auto_merge` or changing branch protection stays the owner's own click.

**Never covered:** `ops-policies`; `ops-infra` is covered **only** by the trivial-PR class above and
by files under `.github` (CI workflow files, per class (b)), and everything else in `ops-infra`
stays route C; credentials or secrets;
money (QuickBooks, payments); repo security settings or branch protection; deploy workflows, or
workflows that use secrets, `pull_request_target`, or permissions beyond `contents: read`;
`standards/sessions/*` and `policies/*` in any repo, including MasterThread; and the approval/egress
gateway code path once it is wired or deployed. Those stay route C.

**Logging and undo.** Every such merge is logged, and the owner gets one daily digest with a revert
link per line. Any owner undo pauses that class until the owner resumes it.

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
   first. Dependent PRs each target the default branch and declare `Depends-on:` lines; the
   `depends-on` check must be green before the dependent PR is considered (see "Dependent PRs: the
   depends-on check" below).
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

   **Assert the SHA's shape before pinning it.** If `<sha>` came out of a tool (a `gh` or `git`
   read, an API response, an agent's or another session's report) rather than being read by you
   from the PR's live head, first check that it is exactly 40 characters and lowercase hex, for
   example `[[ $sha =~ ^[0-9a-f]{40}$ ]]`. If it is not, do not merge: re-read the head from the
   PR and use that. A wrong-length "SHA" has been handed to the seat before (a 41-character string
   offered as the head of MasterThread #121, caught only because the length was checked), and a
   pin the seat did not validate is not evidence that the verdict covers the head it reviewed. The
   same check applies to the `head:` line of the verdict comment.
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

### Repos with strict up-to-date protection

Where a default branch requires status checks with `strict: true` (branches must be up to date;
website's `main` requires `secret-scan` and `build`), parallel PRs merge **one at a time**. When one
lands, the base moves and every sibling's green checks go stale: GitHub refuses the merge ("2 of 2
required status checks are expected") though both passed.

- **The lane that authored the PR updates its own branch** and lets the checks re-run.
- **The seat never pushes to a lane's branch.** Updating a branch moves the head, which voids the
  pinned verdict. The seat re-reads the new
  head, checks only what moved, and posts a fresh verdict.

Sequence a set of parallel PRs in such a repo accordingly. Precedent: website #35 then #36,
2026-09-18.

## Dependent PRs: the depends-on check

Owner order 2026-09-22: *"These need better blocking mechanisms, or to be built as stacks so I
cannot merge something unless the one beneath it is done."* In one round #175 merged before #169,
and #176 and #186 merged into side branches, where no check or review on `main` could see them.
The owner merges from GitHub mobile, so ordering has to be enforced by the button, not by a note in
a PR body.

**Rules for authors (every lane, every repo that carries the workflow):**

1. **Every PR targets the default branch.** Never open a PR into another PR's branch. Branch
   protection and every required check gate the default branch only, so anything merged into a side
   branch skips them all.
2. **A PR that needs another PR merged first says so,** one line per dependency in its body:
   `Depends-on: #169`, `Depends-on: yodatech1988/ops-platform#42` or a PR URL. Several refs may
   share one line. `Depends-on: none` is allowed. Lines in fenced code blocks are ignored.
3. **Building on unmerged work:** branch from the dependency's branch, still target the default
   branch, and declare the dependency. The diff shows the dependency's commits until it lands.
   After it lands, the lane that authored the dependent PR rebases it onto the default branch (see
   "Repos with strict up-to-date protection" for who updates a branch).

**The check.** `.github/workflows/depends-on.yml` runs `tools/check_depends_on.py` on every PR
open, edit, push and reopen. The `depends-on` check **fails** when the PR's base is not the default
branch, or when any declared dependency is still open, closed unmerged, merged into a side branch,
merged at a commit not on its default branch, an issue rather than a PR, unreadable with the
workflow's read-only token, or unparseable. The failure message lists each blocker by number and
title. It **passes** when every dependency is merged into its default branch, or when there are
none. When the last dependency lands, a scheduled re-check (every 15 minutes, best effort) re-runs
the failed check so it turns green without anyone touching the PR. Editing the PR body, or "Re-run
jobs" on the check, re-evaluates it at once.

**Merge authority never merges with a failing or missing `depends-on` check,** on any route, and the
verdict comment's `depends-on:` line records the check's result. A red `depends-on` is never
attributed to infrastructure and waved through. Fix the dependency or the body, then re-run.

**Making it a real block is an owner-only step.** Until `depends-on` is a *required* status check
on the default branch's protection, it is a red X the merge button ignores. Adding it is a branch
protection change, so it is the owner's own click (route C, "Enforcement" phase 2). A session
never applies it. MasterThread's `main` protection already has "include administrators" on, so once
the check is required it binds the owner's account too. This check can be required safely: it runs
on GitHub's own runners, has been seen to pass there, and does not depend on a self-hosted runner.
Other repos get the workflow and the requirement one at a time, each after its own check has been
seen to pass.

Limits: branch protection cannot stop a merge *into* an unprotected side branch. The check turns
such a PR red and names the problem, but only rule 1 prevents it. A PR can edit the workflow or
script it is checked by, which is one more reason `.github/workflows/*` is route C.

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
convention, and conventions are what failed. The `depends-on` check ("Dependent PRs" above) becomes
the second enforced gate once the owner marks it required. Until then it is detection only.

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
| `decision-ops-platform-auto-merge-classes-2026-09-21` | Yes for ops-platform docs-only and unwired library PRs, plus CI workflow files in `ops-*` repos: the seat merges them under the conditions in "The three routes". |
| `decision-review-tier-one-liners-route-b-2026-09-20` | Yes: a one-line review-depth change in a non-owner-only repo's `pr-review.yml` may be merged by the seat under four conditions (2026-09-20T15:07:04Z). |
| `decision-ops-infra-auto-merge-scope-2026-09-21` | Option A: trivial reviewed ops-infra PRs only (2026-09-21T18:19:53Z). |
| `decision-headless-merge-mechanism-2026-09-21` | Option A: GitHub workflow with fixed rules, one repo at a time, ops-platform before ops-infra, after the startup failure is fixed (2026-09-21T18:29:58Z). Not live yet. |

A queue answer is an instruction, not authorization for an irreversible action
(`decision_queue_standard.md`): the merge of this file, and the branch-protection click, remain the
owner's own actions.

## Still open

1. Headless operation: when the owner is away, route C simply waits (recommended, and current
   behaviour). An out-of-band phone approval was scoped earlier and deliberately not built.

Related: `pm_role.md`, `fleet_structure.md`, `orchestrator_role.md` ("Review before merge"),
`session_plan_standard.md` rules 4 and 10, `decision_queue_standard.md`.
