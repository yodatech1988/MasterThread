# Decisions of record

**Status:** draft for owner review (2026-09-17). Asked for by the owner on Decision Queue card
`ops-infra-decision-a-tailscale-vs-cloudflare-conflict-2026-09-17` ("create a policy specific to
this... inform me of my choices better"). Takes effect when the owner merges it.

An owner decision is made **once**, recorded in **one place**, and every other document **points at
that place** instead of repeating the answer. This standard says where that place is, how other
documents refer to it, and how a "waiting on the owner" flag gets cleared when the answer lands.

## Why it exists: the worked example

On 2026-09-15 the owner chose Cloudflare Tunnel + Access over Tailscale for reaching the vault. The
choice was written, with its accepted trade-off and the domain he bought for it, into the program's
authority artifact - whose own header says "if another copy disagrees with it, this one wins".

`ops-infra/docs/PLAN.md` was never updated. Its "Decision A" section still read **held: no session
that depends on it starts until you choose**, still recommended Tailscale, and its Session 5 was
still written as a Tailscale build - while a different section of the *same file* already said
"over the vault's Cloudflare Tunnel (superseded from the original tailnet plan)".

Two days later that one stale flag cost:

- a worker session correctly refusing to guess, and filing an owner card;
- the owner answering with a question ("can we create a policy standard to cover this?") because the
  card gave him nothing to choose between;
- two PM sessions each "reopening" the card, neither write taking effect;
- ops-infra Sessions 5 and 6 blocked the whole time;
- a third session finding, in ten minutes, that the decision had been on record all along.

Nobody was careless. The plan said *held*, and a session that respects a hold does exactly what
these did. The defect was structural: the answer lived in one document and the question lived in
another, with nothing connecting them.

## The rule

1. **One place of record per decision.** For an owner decision it is, in this order of preference:
   - the **Ops Decision Queue card** the owner answered (the card id is the citation); or
   - for a program that has one, its **authority artifact**, in a section headed `Decided: ...`
     with the date - and then a queue card is still filed as a one-click *confirm-the-record* card
     the first time a session needs to rely on it, so the citation exists in the queue too.
   A decision made in chat is not yet on record. The session he said it to files a card that quotes
   him and asks him to confirm it (`decision_queue_standard.md`); until he does, it is a claim.
2. **Everything else cites, never restates.** A `PLAN.md`, a standard, a handoff file, a PR body or a
   memory note that depends on the decision carries a one-line pointer:

   ```
   **Decided:** Cloudflare Tunnel + Access - record: queue card `ops-infra-decision-a-...-2026-09-17`
   (owner, 2026-09-15; confirmed 2026-09-17).
   ```

   One line of *what* was decided, so the document reads on its own; the *why*, the options, the
   trade-off and any conditions live only at the record. A copied rationale is the thing that goes
   stale and then argues with the record.
3. **A document never argues against a recorded decision.** Analysis that recommended the losing
   option moves under a heading `Considered and not chosen` or is deleted. Left as the main text,
   it reads to the next session as the current recommendation.
4. **Memory notes are pointers, not records.** A session memory that says "owner chose X; don't
   re-raise" is a useful lead and nothing more - it names where to look. It is never cited as the
   authority for building against X.

## Clearing a "held" flag

`PLAN_template.md` gives every plan an **Open decisions** section; some plans mark one **held**
(no dependent session starts). A held flag is a lock, and a lock needs a release procedure.

**When a decision lands** (the owner answers a card, or a `Decided:` section appears in the authority
artifact), the session that receives the answer - or the PM, if that session has ended - does all of
this in the same working pass, not "later":

1. Find every holder. Search the org for the decision's name and its option names:
   `gh search code --owner yodatech1988 "<term>"`, plus `git grep` on `origin/<default>` of each repo
   the decision touches. Holders are usually one `PLAN.md` "Open decisions" entry, the sessions it
   gates, a Status-table row reading *blocked: decision X*, and sometimes a Fleet Status `blocked` doc.
2. In each, replace the held entry with the `**Decided:**` pointer line (rule 2), move losing-option
   analysis under `Considered and not chosen`, and rewrite any dependent session that was drafted
   against the recommendation instead of the decision.
3. Clear the gate: Status rows go from *blocked: decision X* to *ready*, and the Fleet Status
   `blocked` doc is removed.
4. Open the PR(s) and put their URLs in the queue card's `followUpNote` with
   `followUpPending: true`. The card stays visibly open-ended until those PRs merge - an answered
   decision whose plan still says *held* is not finished.

**Before a session honours a held flag** - before it stops work, and before it files an owner card
asking the held question - it checks that the hold is still real:

1. the Decision Queue store, read directly (all statuses), for the decision's name;
2. the program's authority artifact, if there is one, for a `Decided:` section;
3. the *same repo* for text already written against an outcome ("superseded", "now that", a session
   built on one option) - the plan in the worked example contradicted itself forty lines apart.

If a record exists, the hold is stale: the session files a **confirm-the-record** card - the
recorded answer as the recommended option, the evidence in the card, "I have changed my mind" as an
explicit option - rather than a fresh choose-one card. One click for the owner instead of a
re-decision. If no record exists, the hold is real and the card presents the actual choices with
their costs.

## Reopening

A recorded decision stays decided until the **owner** reopens it, knowingly. A session that thinks a
decision has aged badly says so on a card citing the record; it does not quietly build the other
way, and it does not treat his thinking aloud in chat as a reversal. When he does change his mind,
the change is recorded the same way as the original - a new card (or a `corrections` entry on the
old one) - and the clearing procedure above runs again, because every pointer now points at a
superseded answer.

## What this does not cover

- Decisions a session is entitled to make itself (`session_plan_standard.md` rule 7). Those are
  recorded in the repo's own `PLAN.md` and that *is* their place of record.
- How a card is written or answered - `decision_queue_standard.md`.
- Who may merge the PR that updates a plan - `merge_authority.md`. A plan edit that records an owner
  decision is his click.

Related: `decision_queue_standard.md`, `session_plan_standard.md` rules 7 and 10,
`PLAN_template.md`, `pm_role.md`, `docs/LESSONS.md` ("Held in one document, decided in another").
