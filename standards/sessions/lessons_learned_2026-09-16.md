# Lessons learned — 2026-09-16, a worker's-eye view

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

## What this session is still holding, for the record

The desktop merge tool (`AEGIS-Merge-Queue.ps1`) this session built earlier tonight has the same gap
`fleet_structure.md`'s "Approval and authorisation" section describes in the abstract: it checks that
a human clicked, but not that the owner was the one who *started the run*. Per the handoff doc, this
tool is on hold pending an owner ruling on who may invoke it — this session will not modify it without
that direction, but flags the specific fix once directed: refuse to launch unless started interactively
by the owner (e.g. require confirmation that the invoking process is an interactive console session on
his own machine, not something launched programmatically on his behalf).
