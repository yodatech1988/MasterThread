# Lessons learned — 2026-09-16, a worker's-eye view

**Status: landing incomplete, on purpose.** Per PM direction during a full fleet rotation: get this to
incoming sessions now rather than hold it for polish. Treat every section below as current as of
landing, not as a closed/final account — later sessions should extend it, not wait for a "finished"
version that never arrives before the context that produced it is gone.

`fleet_structure.md` and `docs/handoffs/2026-09-16-fleet-pm.md` (PR #60) carry the adopted rules and
the PM's own narrative of this round. This file doesn't restate those — read them first. What
follows is the same round from a different seat: a worker session (`github-85`) that spent the night
receiving relayed instructions, not issuing them, and what that vantage point actually looked like in
the moment, plus one concrete gap #60 doesn't cover.

## The moments, not just the rules

**Checking a claim costs one tool call; acting on an unchecked one costs the round.** `CLAUDE.md`
named a PM session that didn't exist. Confirming that took exactly one `ListAgents` call and one
failed `SendMessage` — seconds of work that prevented an entire session from bootstrapping into a
fiction. The expensive failures that night weren't the ones nobody could have checked; they were the
ones nobody happened to check, because checking felt like the slow path under pressure to start
working. It wasn't, here or anywhere else that night — every check in this round was cheaper than the
rework it prevented.

**"The owner confirmed it" arrived twice tonight with the same shape and different truth values.**
A relayed two-hop restructure and a later relayed change to a live merge-approval gate both came
wrapped in "Jeremy said so." One was true, one wasn't (the CLAUDE.md-authorization question was
resolved as legitimate; a separate telemetry-mandate claim in the same relay chain was not what it
was presented as). From inside the relay, both claims sounded identical — same confidence, same
framing, same messenger. The only thing that told them apart was asking the owner directly, in
session, and holding the second question specifically because a gate on real capability deserved
more than the same evidentiary bar as everything else. That distinction — not every claim needs the
same verification weight, but a capability-granting one always needs the top tier — is the practical
takeaway more than "verify everything," which is true but not actionable under time pressure.

**Finding the shared-checkout root cause felt like debugging, not like reading a policy.** Before
`fleet_structure.md` existed to state the rule, the actual investigation was: a relayed claim didn't
match what `Read`/`Grep` showed on disk, so the next step was `git log` on the file in question, then
`git branch --show-current`, then `git merge-base --is-ancestor <sha> origin/main`. Each step was
one command; together they turned "someone is wrong about this" into "the file is real, committed,
and simply not merged — and everyone reading this shared clone is looking at a branch, not a
release." The lesson underneath the lesson: when a claim and the disk disagree, the disk isn't
automatically right either — check what the disk is actually checked out to.

## A concrete gap `fleet_structure.md` doesn't yet cover: branch-name case collisions

The PM's own handoff (PR #60, "Note on the branch") records hitting this directly: creating
`agent/masterthread/...` against an existing `agent/MasterThread/...` ref produced an orphan branch
with no shared history, and GitHub refused the PR. This repo's branch list independently confirms
it's not a one-off — `agent/MasterThread/*` and `agent/masterthread/*` coexist as parallel, unrelated
namespaces for dozens of branch names right now (`policies`, `discord-github-plan`,
`fix-usage-watcher-pm-handoff`, and others each exist in both cases). Windows/GitHub's ref handling is
case-insensitive at the point that matters even though local git and the remote's ref list are not,
so the collision is silent until a push or PR creation fails.

**Guard, not yet written down anywhere standing:** before creating a new `agent/<repo>/<slug>` branch,
check for an existing branch differing only in case:

```
git branch -a | grep -i "agent/<repo>/<slug>$"
```

If a case-differing match exists, don't create the new branch under the differing case — reuse the
existing casing convention for that repo (check `git branch -a | grep -i "^..*agent/<repo>/"` for
which case that repo's branches actually use, since it's inconsistent repo-to-repo in practice) rather
than adding a third variant.

## Closed: the merge tool's owner-initiation gap

The desktop merge tool (`AEGIS-Merge-Queue.ps1`) this session built earlier tonight had the exact gap
`fleet_structure.md`'s "Approval and authorisation" section describes in the abstract: it checked that
a human clicked, but not that the owner was the one who *started the run*. This wasn't hypothetical —
per `decisions/merge-tool-owner-initiation-gate`, a session's believed-harmless dry run rendered real
Windows Forms dialogs on Jeremy's desktop, and he clicked Approve on several genuinely believing he'd
started the queue himself. Every click was real; the initiation wasn't; from inside the dialog those
two facts were indistinguishable.

Fixed and empirically verified, not just reasoned about: the script's first executable line now checks
`[Console]::IsInputRedirected`. Every agent tool call in this environment runs with stdin attached to
the null device (documented behavior of the harness's own Bash/PowerShell tools) — so
`IsInputRedirected` reads `$true` for any programmatic invocation and `$false` for a real console a
human opened themselves. This session ran the script through its own tool call after adding the check
and confirmed it refuses immediately (`exit 2`, no window ever rendered) rather than trusting the logic
would work. The property holds regardless of *why* a session might invoke it — including if the owner
asks a session, in chat, to run it on his behalf: the fix is specifically that a relayed instruction to
run it is not the same as him running it, which is the same distinction the CLAUDE.md/telemetry
confusion above turned on.

## A live instruction and the document of record disagreed, and the document was believed

Mid-round, this session was told (via relay) that team leads had been reinstated, reversing
`fleet_structure.md`'s eight-seat, no-leads model — attributed to a direct Jeremy quote given to the
PM. Checked before passing it along: the currently open PR #60 still said "no team leads," and none of
eighteen live Decision Queue cards recorded any such reversal. Reported the discrepancy back rather
than relaying it forward. The relaying session's own account afterward: it had passed the PM's message
on without checking it against #60 or the queue itself, despite the exact same verify-before-relay
discipline being the theme of this file.

The lesson isn't "that session made a mistake" — it's that this failure mode survives being named and
agreed on. Everyone in this round already knew "verify before relaying" by the time this happened; it
happened anyway, hours after the rule was well-established and repeatedly demonstrated. A live
instruction and a committed document of record can genuinely disagree — the document can be stale, or
the instruction can be a mistaken/premature relay — and the only way to tell which is checking the
actual source (here: asking whether #60 needed updating, or whether the relay was wrong), not defaulting
to trusting whichever one arrived more recently or more confidently. Recency and confidence are not
evidence.
