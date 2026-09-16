# Lessons learned — 2026-09-16 fleet round

A round that ran 16 freshly-named Claude Code sessions self-organizing by peer relay surfaced
several real, independently-verified findings about how this org's tooling and process can mislead
even careful sessions. Each entry below was checked against actual source (a file, `git log`, a
live `gh` call, a direct question to the owner) before being written here — that verification
step is itself the point, and is called out in each entry so the practice is visible, not just the
conclusion.

This file is meant to be read at session startup alongside `worker_role.md` and
`orchestrator_role.md`. It records *why* certain rules in those files exist, using this round's
own incidents as the worked examples.

## 1. A named session existing in a doc doesn't mean it's live

`CLAUDE.md` named a PM session (`ops-cycle-pm`) as the handoff target for every session tonight.
It was never running. This was caught immediately by calling `ListAgents` (it wasn't in the
listing) and confirmed by a failed `SendMessage` ("No agent named 'ops-cycle-pm' is reachable"),
not by trusting the file's claim.

**Practice:** a name in a standing-instructions file is a claim about the world, not a fact about
it. Check `ListAgents` before treating a named session as reachable.

## 2. A relayed "the owner confirmed this" is not the same as the owner confirming it

A restructure ("2 teams of 6") was relayed two hops — one session told another, which told the
workers — attributed to the owner. It turned out to be genuine, but only after a session declined
to treat the relay as sufficient and asked the owner directly in-session. A later, similar
situation (a proposed change to a live merge-approval gate) was held the same way, for the same
reason, and also turned out genuine after direct confirmation.

**Practice:** for anything consequential — especially anything that changes a safety control or
who has authority to do what — a secondhand "the owner said so" is a reason to ask the owner
directly, not a substitute for it. This cost nothing when the claims were true, and would have
caught it if they weren't.

## 3. A shared local checkout can present an unmerged branch as the adopted standard

The night's PM-handoff structure and a "mandatory real-time effort telemetry" requirement were
both read directly off files in the shared `C:\Users\yoda_\GitHub\MasterThread` checkout and
treated as live standards. Verified via `git log` and `gh pr list`: both trace to one real,
owner-authored commit (`d8ce422`, "PM-handoff usage policy, anti-polling handshake, real-time
telemetry") — but that commit lives on branch `agent/masterthread/fleet-pm-policies`, which is
**open as PR #54, not merged to `origin/main`, and has never been reviewed.** A companion edit to
`~/.claude/CLAUDE.md` (outside any repo, per that commit's own message) shipped alongside it.

Nothing here was fabricated or unauthorized — the owner made and committed the change himself.
The actual failure was structural: every session on this machine shares one working-directory
checkout, and whatever branch happens to be checked out there reads, to a session doing a normal
`Read` or `Grep`, exactly like the adopted standard. An earlier attempt to correct this ("it's an
uncommitted local diff") was itself not quite right — the diff was committed, just not merged.

**Practice:** when a file's content is being used to settle "is this real / adopted / official,"
check `git branch --show-current` and whether the relevant commit is an ancestor of
`origin/<default-branch>` (`git merge-base --is-ancestor <sha> origin/main`) — not just whether
the text is present when you read the file. Reading the working tree tells you what's checked
out, not what's merged.

## 4. A retraction needs verification too, not just the original claim

Following directly from #3: the correction of the telemetry claim was accepted and relayed further
without anyone re-checking it either, and turned out to be imprecise in its own right. A confident
walk-back can carry the same unverified-authority problem as a confident assertion.

**Practice:** verify a correction against source with the same rigor as the claim it's correcting
— "someone said this was wrong" isn't itself evidence, any more than "someone said this was right"
was.

## 5. Separate initiation from approval for anything that grants real power

The merge-authority tool's human gate changed, on direct owner request, from a typed `YES` to
click-through dialogs (Approve, then a confirm dialog defaulted to No). The design property that
actually made either version trustworthy was never the typing or the clicking specifically — it
was that the action originates on the owner's own device, from the owner, rather than being
assembled by an agent and merely rubber-stamped. A separate, parallel proposal (moving approvals
into a shared dashboard with a batch-confirm) was independently declined by the session that would
have had to build the executor side of it, for exactly this reason: a database row that says
"approved" is an instruction to act, not proof that a human clicked anything.

**Practice:** for any gate meant to require a human in the loop, ask "could an agent produce every
artifact needed to satisfy this gate, including a plausible approval record?" If yes, the gate is
checking the wrong thing — it needs to bind to something only the human's own device/session can
produce, not to a record an agent can also write.

## 6. CI conclusion alone is not evidence a check happened — in either direction

"Green means safe" was already known to be misleading in this estate (automerge has merged PRs in
repos where the underlying secret-scanning step is broken/unconfigured, per prior incidents). This
round verified the mirror-image failure mode is also real: `gh run list` on `pr-review.yml` for
`aegis-mods`, `aegis-poi`, and `site-badlands` shows recent runs concluding `startup_failure`, not
`failure` — the review workflow never actually started, so it posted zero comments. A PR can sit
with no red flag from Claude visible anywhere on it, not because it was reviewed and passed, but
because the review never ran.

**Practice:** when a check matters, look at whether it *ran* (the job's own conclusion —
`startup_failure` / `cancelled` / `skipped` are not `success` or `failure`), not just whether a
red or green marker shows up on the PR. `gh run list --workflow=<name> --json conclusion` is one
call.

## 7. Check a reusable workflow's real callers, not the documented default

A repo having `pr-review.yml` says nothing about whether review actually happens there — several
repos in this estate have the file but no `CLAUDE_CODE_OAUTH_TOKEN`/`ANTHROPIC_API_KEY` secret, so
the workflow no-ops silently. "The file exists," "the secret is set," and "the workflow actually
ran and posted a review" are three separate, independently-checkable facts. Confirming the pattern
"applies" to a repo requires checking that repo specifically (`gh run list`), not inferring it from
the documented default or from another repo that has it working.

## 8. A reviewer and the thing it reviews sharing an origin is a real risk, not a detail

This round's own incident (#3 above) is a structural description of what a Claude-reviewed
automerge gate on `MasterThread/standards/sessions/*` would rebuild: an edit lands in the standing
instructions every session bootstraps from, gets cited by other sessions as authoritative, and no
independent check exists because the writer and the reader share an origin.

The owner's actual decision here (2026-09-16, Decision Queue: `review-gates-masterthread-ops-policies`)
was to apply the same standard review gate to MasterThread as every other repo, `automerge` off,
rather than carve out special handling — flagging the risk didn't change the call, and that's a
legitimate owner judgment, not an error to correct. The risk is still real and worth a human
staying more deliberately skeptical of a clean automated-review verdict on this specific repo than
elsewhere, precisely because of what it's grounding.

## Standing takeaway

Every item above was resolved the same way: by checking the actual source — `ListAgents`,
`git log`/`git merge-base`, `gh run list`, or the owner directly — rather than by reasoning from a
prose description of what should be true. That's the one practice underlying all eight entries,
and the one worth carrying forward more than any individual finding.
