# Decision Queue standard

The Ops Decision Queue is the fleet's channel for anything a session isn't sure it should call
unilaterally — an artifact-backed shared database (`db` capability), not a repo file, so it survives
across sessions without anyone needing to pull or checkout anything. This document is its durable
schema and contract; the artifact's own footer documents the same thing for whoever's actively
looking at the page, but this file is what a PM inheriting the queue without this conversation's
context should read first.

**Current URL:** https://claude.ai/artifact/1fMqNA1zdQKsq1FDEFvyzf (`decisions` collection).
Confirm this is still current before relying on it — artifacts can be redeployed to a new URL if a
session republishes without passing the existing one; check `MasterThread/docs/REPOS.md` or ask in
the fleet if this URL 404s.

**Sibling artifacts, same pack, same visual language (IBM Plex Sans/Mono, shared CSS custom
properties):**
- Ops Fleet Status — live session/queue/health/goals/cost dashboard — cross-linked via the
  `nav.pack` bar at the top of each page.
- Ops Roster — a static governance proposal for a fixed named session org chart; distinct from the
  live pages above.

## Why it exists

Built the night of 2026-09-16 after several incidents where a peer-relayed instruction was treated
as authoritative without verification (a nonexistent PM session, a retracted policy claim, a card
filed as already-resolved with the filer's own suggestion copied into the resolution field). The
queue's whole design is oriented around making an owner decision impossible to miss or
misattribute: every card is a real document, every resolution is a real write with a version
number, and the page itself never invents a status.

## Card shape (`decisions/<doc_id>`)

| Field | Type | Meaning |
|---|---|---|
| `title` | string | The question, as a question. |
| `kind` | `"decision"` \| `"action"` | **Set it on every new card.** `"action"` = a click only the owner can make (see Action cards below); `"decision"` = everything else. A card with no `kind` whose first option reads as a completion claim ("Done", "Merged", "I ran it") is treated by the page as an action card, so an un-kinded card can change shape without anyone choosing that. |
| `summary` | string | **The question he is being asked, in one plain sentence**, under ~200 characters, no jargon or internal shorthand. Shown first on the card as "In short". See Writing a card to be scanned. |
| `points` | string[] | **At most 5, one line each**: only what he needs to know to answer. Shown as "What matters". A link or path he must use goes on its own bullet. |
| `details` | string | The long explanation, line breaks kept. Shown collapsed under "Background and sources". |
| `context` | string | On a decision card: legacy long text, shown collapsed like `details` (new cards use `details`). On an action card: the numbered steps, and it stays visible. |
| `ownerRequired` | boolean | `true` = blocks until Jeremy acts; `false` = ops proceeds unless overridden. |
| `category` | string | Free text, e.g. `security/access`, `cost/infra`, `process/governance`. |
| `source` | string | Who/what raised it and when — cite the actual session or PM relay. |
| `suggestedResolution` | string | What ops would do here, in prose. Optional if `options`+recommendation cover it. |
| `rationale` | string | Why, for `suggestedResolution`. |
| `bestPractice` | string | **Required** (2026-09-16 standing rule). What established practice actually says — name the specific `MasterThread/standards/` or `_security-public/policies/` doc if one applies, the recognized general practice if it doesn't, or state plainly that no standard covers it. Never invent one. |
| `divergenceNote` | string | Required whenever the suggestion and `bestPractice` disagree — say so and explain why. This is the single most useful field on a card; it's where the owner's judgment is actually needed. |
| `options` | string[] | Discrete choices, when the decision has a small finite shape. |
| `recommendedOption` | integer | **Required whenever `options` is present** (2026-09-16 standing rule). Index into `options` — the option ops would pick, labelled "ops recommends" on the card but not selected for him (see Writing a card to be scanned). A card with options and no recommendation pushes the analysis back onto the owner, which defeats the point. |
| `recommendedBy` | string | Who made the recommendation. |
| `recommendedRationale` | string | Why that option, specifically. |
| `status` | `"open"` \| `"resolved"` | The only field the page's render logic keys off for open/resolved grouping — never inferred from whether `resolution` is non-empty. |
| `resolution` | string | The owner's actual answer. Empty until they've actually answered — never pre-filled with a recommendation copied in, even as a placeholder; that has caused real confusion when a card was miscategorized as answered. |
| `comment` | string | Free-text context the owner added alongside their resolution. |
| `followUpPending` | boolean | **Set whenever a resolution names a real action that hasn't happened yet** (an owner click, a build, a merge) (2026-09-16 standing rule). Keeps the card visible indefinitely — see Lifecycle below. `followUpNote` says what's still outstanding. |
| `corrections` | array | `{ note, correctedBy, correctedAt, previousResolution }` entries, appended — never delete or silently overwrite a resolved card's `resolution` in place; append a correction and update `resolution` to the new value. See Correcting a resolved card below. |
| `createdAt` / `resolvedAt` | ISO 8601 | Timestamps. **Real UTC, read from the clock** (`date -u +%Y-%m-%dT%H:%M:%SZ`) at the moment of the write, never typed from memory. This covers every timestamp a session writes to **either** artifact, this queue and Fleet Status (`updatedAt` on a `sessions` row included), and every `*At` field below. On 2026-09-17 hand-typed stamps ran 10-100 minutes ahead all day: cards looked answered before they were filed (`resolvedAt` earlier than `createdAt`), and a Fleet Status row stamped in the future made a live session read as wound down. |
| `claimedAt` / `claimComment` | ISO 8601 / string | Action cards only, written by the page when the owner presses **I did it - check it**. |
| `verifiedBy` / `verifiedAt` | string / ISO 8601 | Action cards only, written by the session that checked live state and closed the card. The evidence itself goes in `resolution`. |
| `checkResult` / `checkedBy` / `checkedAt` | string / string / ISO 8601 | Action cards only: what a check found when the action had **not** taken, or (with `checkedBy: "owner"`) a problem the owner reported from the card. The card stays open. |
| `executabilityCheck` | string | Action cards only, **required at filing and before relay** (see Executability check below). Who checked, when, and what was traced to a primary source or actually run — or the literal string `not-checked`, which the PM treats as a hold on relaying to the owner. |

**`claimedAt` set is evidence only that the owner pressed the claim button — it is not evidence he
meant "Done".** The page's write code (read directly from the artifact's own script —
`https://claude.ai/artifact/1fMqNA1zdQKsq1FDEFvyzf`, version `1789668310-a0f2`, 2026-09-18; re-check
the current version if this drifts) confirms the row above: exactly one button, "I did it - check
it", ever writes `claimedAt`, and it writes
`claimComment` from whatever the owner typed in the comment box alongside it — unvalidated against
the button's own label. The separate report button (for "It looked wrong" and similar) does the
opposite: it *clears* `claimedAt` and `claimComment` and writes `checkResult` / `checkedBy: "owner"`
/ `checkedAt` instead. So a card can legitimately carry a `claimedAt` and a `claimComment` that reads
as a delegation or a "not really done" note, simply because the owner used the one claim button and
typed something other than a completion — not because the page mis-stamped a different button. Two
of the six claimed cards in the 2026-09-18 pass were exactly this: ovh-edge-firewall (`claimComment`
"work this out with ops" — a delegation, written into the claim button's own comment box) and
phase0-spend-limits (`claimComment` describing a prepaid account with no auto-reload, a different and
stronger control than the Console caps the card asked for). Any sweep that treats `claimedAt` alone
as "the owner said Done" is counting button presses, not claims, and will over-report work as done —
part of the "13 of 17 claimed-but-unverified" figure from that pass came from exactly this filter. A
session checking what the owner actually said MUST read `claimComment` (and `checkResult` /
`checkedBy` / `checkedAt`, if those are also set) alongside `claimedAt` before treating a card as a
completion claim. Sessions must never write to any of these fields; they hold the owner's own words.

One card from that pass (hardware-keys) does not fit this pattern and is flagged rather than
generalized from: it carries `checkedBy: "owner"` and a `checkResult` alongside a `claimedAt` set
2.3s later — a combination the current write code cannot produce (the report path that sets
`checkedBy` also clears `claimedAt` in the same write). Left unexplained here; treat it as a
possible artifact of an earlier page version or a one-off, not as proof of present-day dual-stamping,
and do not build a rule on it without separately verifying the page's history.

## Permission-denial cards: when the classifier says no

A session's tool call can be refused by the auto-mode permission classifier (`[Remote Shell
Writes]`, `[Production Reads]`, `[Interfere With Workloads]`, `[Irreversible Local Destruction]`,
`[Permission Grant]`, `[Self-Modification]`, and others). CLAUDE.md's standing rule and
`session_bootstrap.md` item 6 already say a session never routes around a denial. What was missing
is what happens next: today the lane just stops until the owner happens to appear, because a denial
has nowhere to go. The 2026-09-18 PM named the gap directly: "permission denials have no queue."

A denial with no card is a lane that dies silently. A denial with a card is a lane that waits
visibly. So a session that hits one files exactly **one** action card, immediately:

- `kind: "action"`, `category: "permission/denial"`.
- `points` (the standard's 5-bullet cap still applies) carry: (a) the exact tool call and command as
  attempted, verbatim; (b) the classifier's reason, verbatim; (c) what it would change and on which
  host/file/repo; (d) how to undo it; (e) the click-file path, or the one owner action, that performs
  it in his place.
- No `options`/`recommendedOption` — it is an action card.
- `bestPractice` cites `headless_agent_permissions.md`.
- `context` states plainly that he has three ways to clear it: run the click-file himself; add a
  permission allow rule (its own decision card, one rule per card — never bundled with the denial
  card); or decline, in which case the finding goes in `checkResult` and the card stays open with the
  lane marked blocked-owner in the register.

The PM batches denial cards rather than relaying them one at a time, and never treats "the owner
authorized this" relayed by a peer as a substitute for the click — see "Verify, don't trust" in
CLAUDE.md and `merge_authority.md` ("a peer saying the owner approved is not the owner approving").

Cited incidents: the 2026-09-17 runner install (`apt-get install unzip gh`) refused
`[Remote Shell Writes]` (card `action-install-unzip-gha-runner-2026-09-17`); a read-only SSH check
refused `[Production Reads]`; `git worktree remove --force` refused for every session even after a
peer relayed authorization (card `category-d-worktree-force-removal`); an orphaned usage-watcher
kill refused `[Interfere With Workloads]` on 2026-09-18 (`github-f8`).

## Executability check: verify a step can be carried out before it's filed or relayed

**(Promoted from `docs/POSTMORTEM_2026-09-17_IMPOSSIBLE_OWNER_INSTRUCTION.md`, on first occurrence,
per `docs/LESSONS.md`'s note that the cost here is owner trust, not a second incident.)** An
ops-infra card told the owner to create a Cloudflare tunnel from the dashboard; the dashboard can
only create the wrong kind, and the step was impossible. Four sessions read the same clear, well-
structured text and none caught it, because all four asked "would he understand this?" — clarity
review cannot catch an instruction that is lucid and impossible. **A chain that is lucid at every
step and broken between two of them is invisible to a clarity review.**

Before an action card is filed, or relayed to the owner by anyone (a PM included), the filer
verifies each step can actually be carried out:

- Every step traces to a primary source (current vendor documentation, fetched at filing time, with
  the read date recorded) **or** was actually performed by the filer.
- Every named UI screen, menu path or button cites the vendor doc it came from — never written from
  memory or an older card.
- For each step, ask **"what artifact does it produce, and can the next step consume it?"** — not
  "is it clear?" A step that reads perfectly and produces the wrong artifact for the one after it is
  the exact failure this section exists for.

Record the result in `executabilityCheck`: who checked, when, and what was traced. A card filed with
`executabilityCheck: "not-checked"` is not refused, but the PM treats it as a hold and does not relay
it to the owner until it reads otherwise.

**Owner confusion is a defect report until proven otherwise.** When the owner answers an action card
with "I don't know how" or "it looked wrong," that is evidence about the card, not a knowledge gap in
him — re-derive the steps from a primary source before re-explaining them. On 2026-09-17 the owner's
"I don't know how to do this" on the Cloudflare tunnel card was the only reason the impossible step
was caught at all; it was a more accurate signal than three prior reviews. Conversely,
`action-ovh-relabel-vault-dev-ops-ci-2026-09-17` still carried the owner's "It looked wrong - I need
better links and instructions" unaddressed as of 2026-09-18 01:00Z (read from the store) — see incident PM-2026-09-17-01.

## Writing a card to be scanned

**(2026-09-17 owner request: "the new cards are big section of text, I struggle with that
format.")** Sessions had been filing 150-300 word `context` paragraphs with a second dense block
under them. The same day six cards were cleared in eight seconds and action cards were answered
"Done" for things nobody had done. A card that cannot be read at a glance gets clicked through, so
the card is written for the glance:

- **`summary`: one sentence, the question itself**, under ~200 characters. If it needs a second
  sentence it is two cards, or the second sentence is a bullet.
- **`points`: at most 5 bullets, one line each.** Only what changes his answer: cost, what it
  unblocks, what it arms, how to undo. Not the history of how the question arose.
- **`details`: everything else.** It is shown collapsed, along with `bestPractice`,
  `divergenceNote` and `corrections`. `bestPractice` is still required; it is just not on the face
  of the card.
- **Option labels under ~90 characters.** The reasoning belongs in `recommendedRationale`, which
  stays visible, not in the label.
- **An option on a decision card is never a completion claim** ("Done - merged", "I ran it"). An
  answer records what he decided, not what happened: on 2026-09-17 a PR-merge card was resolved as
  "merged" while the PR was still open. A click he owes is an action card, which has no options.
- **The recommendation is shown, never preselected** (2026-09-17 owner decision, card
  `decision-cards-stop-preselecting-recommendation-2026-09-17`: "No pre-highlight"). The page
  labels the recommended option "ops recommends" and keeps `recommendedRationale` visible, but no
  option starts highlighted and **Approve** stays disabled until he clicks the one he wants. This
  replaces the 2026-09-16 wording "preselected on the card". The reason: a run of one-click
  approvals of preselected options is indistinguishable in the record from a session copying its
  own suggestion into the answer, and sessions act on these answers without asking again. The
  recommendation itself is still required.
- A card without `summary`/`points` still renders (the first sentence of `context` stands in), so
  nothing breaks. It just reads worse.

### Links and paths

Never just name the place; give him the way there (2026-09-17 owner request).

- **A URL or a path he must use goes on its own `points` bullet.** The page turns `https://` URLs
  into links that open in a new tab, and Windows paths into a chip with a Copy button. Text around
  a link on the same bullet is fine ("Then merge here: <url>"); two destinations on one bullet is
  not.
- **A pull request gets its side-by-side diff link first**, then the PR page:
  `https://github.com/<owner>/<repo>/pull/<n>/files?diff=split`. He reviews from that view; the
  bare PR link drops him on the conversation tab.
- **A click-file is given as its full path** (`C:\Users\...\AEGIS-Thing.cmd`), not as a filename,
  so Copy gives him something he can paste into Explorer's address bar.

## Lifecycle: open → resolved → archived

A resolved card is never deleted, but it does age through three visibility stages so the page stays
readable on a long working night without losing the record (2026-09-16 owner instruction — ten-plus
resolved cards in one night already made the collapsed history unreadable):

1. **Open** — blocks in the "needs you" section (`ownerRequired: true`) or shows as ops's default
   plan (`ownerRequired: false`), same as always.
2. **Resolved** — for 20 minutes after `resolvedAt`, shows in a highlighted "just answered" strip so
   a burst of answers gets visible confirmation; after that, moves into the normal collapsed
   "N resolved" section.
3. **Archived** — once resolved more than 4 hours ago, moves into a separate "N archived" collapsed
   section, out of the default view but never deleted and still one click away.

**The one hard exception:** a card with `followUpPending: true` never reaches stage 3, no matter how
old `resolvedAt` gets. "Resolved" and "done" are deliberately different words here — several cards
the night this rule was written were resolved in the sense of "Jeremy answered the question" while
the actual action the answer called for (an OVH token-scope change, a cost-panel update) hadn't
happened yet. Don't let a real answer disappear from view before the thing it asked for is actually
done.

## Auditing the board: telling a session's writing from the owner's answer

The timestamp rule above — clock-read, never typed — already existed on 2026-09-17 and was broken on
26 of 126 cards that same day. Restating it would repeat the failure it describes. This section is
the **check** instead, and it is written the way it is because the first version of it was wrong.

### The discriminator that works: milliseconds

*Tool:* `tools/decision-queue/dq_monitor.py` applies this check (section D of its report) and the other audits below over an exported card directory. It is read-only; see `tools/decision-queue/README.md`.

`resolvedAt` is written two ways, and they are trivially distinguishable:

- **Page-written** stamps carry milliseconds (`…T22:09:27.260Z`). The owner clicked.
- **Session-written** stamps are whole seconds (`…T18:30:00Z`), because a session composed them.

Measured across 114 resolved cards on 2026-09-17:

| `resolvedAt` | `resolution` copies an option | `resolution` is free prose |
|---|---|---|
| has milliseconds (page) | **41** | 34 |
| whole seconds (session) | **0** | 38 |

The separation is total. Every option-copy on the board was written by the page.

### The diagnostic that does NOT work, and cost real time

**A resolution being byte-identical to `options[recommendedOption]` is not evidence of anything
wrong.** The page has an approve-the-recommendation button; pressing it writes that option verbatim.
An exact echo is the *expected* shape of a genuine answer.

An older note held the opposite — that a real answer from the owner is never byte-identical to ops's
suggestion. **That is false, and anything built on it is unsafe.** On 2026-09-17 two sessions
independently used it, both concluded a live auto-resolve defect was firing, and at least one reopened
a card that had probably been answered for real. Reopening on this fingerprint destroys genuine owner
input, which is worse than the failure it is trying to prevent.

Fast gaps do not rescue it either. A card answered seconds after filing is what happens when the owner
is already looking at the board when a session files.

### Bursts are a person working the queue

Several cards resolving within seconds of each other, across different filers, on unrelated subjects,
is **not** suspicious: the board is sorted by status, not topic, so a person working down it answers
unrelated things in sequence. The rhythm is the tell — irregular gaps of roughly 2-15 seconds, the
cadence of reading and clicking. One such run on 2026-09-17 (12 cards, gaps 3.2, 3.0, 2.7, 2.7, 10.9,
4.3, 2.8, 2.0, 11.0, 14.9, 4.6s) is separately documented as the owner genuinely working through the
queue. Treat that shape as ordinary.

### The real problem on the board

**38 resolutions were written by sessions, not by the owner** — whole-second stamps, prose in
`resolution`. That is a session filling in the owner's answer itself, and it is the standing
violation worth chasing. It is unglamorous and it is real, unlike the defect two sessions thought they
had found.

Separately, of the 26 cards whose `resolvedAt` precedes `createdAt`, 11 have a page-written
`resolvedAt` and a hand-typed `createdAt`. The bogus field is `createdAt`. Those cards were answered
normally and filed with a wrong stamp — a stamp-drift problem, not a resolution problem.

### If you do suspect a card

- **Check the milliseconds first.** A whole-second `resolvedAt` means a session wrote it; that is the
  case worth pursuing. A millisecond stamp means the page wrote it, and the owner was there.
- **Report it. Never reopen it — under any signature, including the whole-second one.** A session
  having typed the resolution is a standard violation, but the words may still be exactly what the
  owner said out loud, and reopening erases a real decision just as surely as reopening a clicked one.
  There is no fingerprint that licenses an automatic reopen. Holding and reopening have opposite
  risks: holding costs nothing.
- **Reopening costs more than the answer.** When a session reopened a correctly-answered card on
  2026-09-17, the owner's reply was *"Did I do something wrong?"* — the machinery made him doubt his
  own correct use of the approve button. Restoring his answer for him is not the repair either: that
  would be one more session typing into `resolution`, which is the violation being counted. Leave the
  card open, say plainly on it that it was reopened in error, and let him re-approve with one click.
- A resolved card still never authorises an irreversible action on its own (see below). "The answer is
  genuine" and "doing this is what he wants" are separate questions — on 2026-09-17 a card genuinely
  answered "delete the files" would also have reset every player's purchased storage level, which the
  question had not put to him in those terms.

### An unattended job must never hold a destructive default

The 5-minute card watcher every session runs (see above) is a **recurring, unattended** job. Whatever
default it carries executes on a timer with nobody reading the result first.

On 2026-09-17 two sessions independently built watchers that instructed themselves to *reopen* any
card matching the false fingerprint. Both were primed to overwrite the owner's genuine answers
automatically, every five minutes, with no human in the loop. **Neither had fired yet when the
diagnostic was overturned. That was luck, not design.**

So, for any recurring job that touches the queue:

- Its default action is **report**. Writing is for the cases the standard names explicitly — an action
  card the owner has claimed, or a relay of an answer to the lane that owns it.
- A watcher may never reopen, resolve, or edit `resolution` on a signature it detected itself.
- When a diagnostic a watcher depends on is corrected, **delete and rebuild the job**, do not reason
  about whether it would have mattered. A watcher carrying a retracted premise is a live hazard for as
  long as it exists.

### How this section got corrected

The first version of it asserted a live auto-resolve defect, with a burst of three cards as evidence.
It was wrong. What overturned it was a **testable** discriminator — split every resolution by whether
its stamp has milliseconds — run against the stored data, which no amount of re-reading the cards
would have produced. Prefer a test that can fail over a pattern that merely looks convincing.

## Correcting a resolved card

Never overwrite a resolved card's `resolution` field in place. If it needs correcting after the
fact: append `{ note, correctedBy, correctedAt: <now>, previousResolution: <the old resolution
text> }` to `corrections`, then update `resolution` to the corrected value in the same write. The
card then shows the current answer and the full correction trail, not a silent edit. Always pin the
write with `if_version` (see below) — a card can be corrected while the owner is mid-answer on it,
and a forced overwrite has already clobbered a live answer once tonight.

## Reopening a card: `status` goes in the same write as the correction

**Reopening is a special case of correcting a resolved card, and it has its own failure mode.** A
card that was wrongly marked `resolved` — an auto-resolve bug, or a reply that turned out to be a
question rather than a decision (see Action cards below and "Writing a card to be scanned") — needs
`status` flipped back to `"open"` as well as a `corrections` entry. **These are one write, not two.**

The worked example, from `ops-infra-decision-a-tailscale-vs-cloudflare-conflict-2026-09-17`
(2026-09-17): the card was reopened **three times** before it stuck.

1. github-3d appended a correction explaining the owner's reply was a question, not an answer. It
   did not include `status: "open"` in that write. The card kept reading `resolved`.
2. github-8b appended a second correction — its own note says exactly what happened: *"github-3d's
   reopen note above landed but the status field itself was never actually flipped back to 'open' —
   confirmed the bug github-91 flagged is real, not a stale read on their end."* **The note landed.
   The status did not, because it was never in the payload.** github-8b's own write repeated the
   same mistake: another `corrections` entry, still no `status` field in that update.
3. github-b5 caught it on a third pass, quoting live state directly: *"this card still read
   status=resolved despite two prior correction entries saying it should be reopened — the write
   never actually took."* Only this write actually included `status: "open"` and cleared
   `resolution`/`resolvedAt`.

This was never a platform bug and never a lost update — `db.update()` doesn't silently drop fields
that are actually passed to it. It was two sessions, independently, writing a `corrections` entry
and a prose claim ("reopening this", "setting status to open now") without putting `status` in the
same call, and neither re-read the card afterward to confirm the claim matched live state.

**The rule going forward:**

- A reopen is one `update()` call carrying **both** the `corrections` append and
  `status: "open"` (plus clearing `resolution`, `comment`, `resolvedAt` — see below). Never write
  the correction now and the status "next", even seconds later — that gap is exactly where this
  failed twice.
- Pin the write with `if_version`, same as any correction.
- **After the write returns, read the card back and confirm `status` actually reads `"open"`
  before telling anyone it's reopened.** Saying "reopening this" in a `note` is not evidence the
  reopen happened; only a re-read is. This is the same discipline the standard already asks of a
  session verifying an action card's `claimedAt` — apply it to your own writes, not only the
  owner's.

```js
db.collection('decisions').doc(id).update({
  status: 'open',
  resolution: '',
  comment: '',
  resolvedAt: null,
  corrections: [...existingCorrections, {
    note: 'Reopening: <why the resolution is wrong>',
    correctedBy: '<your session name>',
    correctedAt: new Date().toISOString(),
    previousResolution: '<the resolution text being reopened>',
  }],
}, { if_version: <version you read> })
// then re-read the doc and confirm status === 'open' before reporting it reopened.
```

**Known limitation, logged and not fixed here:** neither this write pattern nor the page's own
`resolve()`/`writeClaim()` functions (`tools/decision-queue/ops-decision-queue.html`) pin any write
with `if_version` on the page side — only sessions using the ArtifactData tool do. Two writers
racing on the same card (the owner clicking Approve while a session reopens it, or two sessions
correcting at once) is last-write-wins with no conflict detection on either side. This has not
caused a real incident — the three-reopen failure above was a missing field, not a race — so it's
recorded here as a known gap for whoever next touches concurrency on this page, not something this
PR changes.

## Filing a card

Any session can add one directly:

```js
db.collection('decisions').add({
  kind: 'decision',                   // or 'action' -- set it explicitly
  title, summary, points,             // summary: one sentence; points: <= 5 one-liners
  details,                            // the long version, shown collapsed
  ownerRequired, category, source,
  bestPractice,                       // required
  options, recommendedOption, recommendedBy, recommendedRationale,  // required together if options exist
  status: 'open', resolution: '', comment: '', createdAt: new Date().toISOString(),
})
```

Never set `status: 'resolved'` or populate `resolution` at filing time — only the owner's own
approval/override action does that, via the page.

## Action cards (`kind: "action"`): clicks only the owner can make

**(2026-09-17 owner decision, card `action-cards-done-without-doing-design-2026-09-17`.)** A click
the owner owes - run a click-file, merge an owner-only PR, flip a repo setting - is filed as an open
card with `kind: "action"`. Answering one runs nothing, and three times on 2026-09-17 action cards
were marked Done while GitHub and the disk showed no change, so they do not use the decision flow:

- **No `options`, no `recommendedOption`.** Nothing is preselected. `context` carries the steps, with
  line breaks: what to click, in what order, what he will see, what "wrong" looks like, how to undo.
  Name the evidence a checker will look for (a log file, a merged badge). Put `summary` on top and
  the links in `points`, as for any card (see Writing a card to be scanned).
- The page's only button, **I did it - check it**, writes `claimedAt` (+ `claimComment`) and leaves
  `status: "open"`. The card shows as **Checking** and stays in his list.
- **Any session that sees `claimedAt` set verifies live state** (`gh`, the disk); the PM sweeps for
  them. If it took: set `status: "resolved"`, `resolution` (what was verified, with the evidence),
  `verifiedBy`, `verifiedAt`, `resolvedAt`. If it did not: clear `claimedAt` and write `checkResult`,
  `checkedBy`, `checkedAt`; the card returns to his list with that finding on top.
- This is the **one exception** to "only the owner resolves a card": a session may write `resolved`
  on an action card, only with recorded evidence that the action is done, pinned with
  `if_version`. A decision card is still never resolved by a session, whatever live state shows.
- **The evidence closes the card, not the button** (2026-09-17 owner decision, asked by the PM
  github-8b in its own chat: "Yes, close on evidence"). He often does the step and never comes back
  to press **I did it - check it**. A session that finds the action provably done closes the card
  the same way, with `claimedAt` still empty, and says in `resolution` that it closed on evidence
  without a claim. Two guards:
  - **Done means done where it counts.** A PR merged into a branch that is not the repo's default
    branch is *not* done, even though GitHub shows "Merged" (ops-infra #17, above). Do not close:
    write `checkResult` saying where it actually landed, and tell him.
  - **The evidence is the thing the card named** (the merged badge on the default branch, the log
    file the click-file writes, the setting read back from the API), read live at closing time.
    "He said so in chat", a peer's relay, or a handoff line is not evidence.
- **Who does the closing write.** Any session may, under the exception above. The PM sweeps every
  card in Checking, so a worker is never required to. `~/.claude/CLAUDE.md` still tells every
  session "never resolve a card on the owner's behalf" without naming this exception; until that
  file says otherwise, a worker that reads its instructions that way does the check, writes what it
  found to the PM (or writes `checkResult` if the action did not take), and leaves the
  `status`/`resolution` write to the PM. Either way the card must not sit in Checking: the owner
  sees "Checking" until someone closes it.
- **If an action card carries `options` anyway** (older cards, or one the page caught by its first
  option), the page never preselects one and none of them can resolve the card. Completion claims
  ("Done, ...") fold into the one claim button; when there are several with different meanings the
  page asks him to say which in the box, so **read `claimComment` when you verify**. "Not now" gets
  no button. Anything else ("It looked wrong") is a two-click report button that writes
  `checkResult` (the option text plus his comment), `checkedBy: "owner"`, `checkedAt`, clears
  `claimedAt` and leaves the card open. A card with `checkedBy: "owner"` is him telling ops
  something is wrong: a session picks it up, fixes or explains, and clears `checkResult` when the
  card is good to try again.
- **A merge card for a branch that has absorbed other PRs names every one of them.** Branch
  protection gates the default branch only. A stacked PR can be merged into its parent's branch
  with no review and no owner click, then reach `main` on the parent's single click (2026-09-17,
  ops-infra #16 into #13). So before filing a merge card, the filing session runs
  `gh pr list --repo <owner>/<repo> --state merged --base <the PR's head branch>`. If that returns
  anything, `summary` says so in plain words ("merging #13 also lands #16") and `points` carries
  each absorbed PR's `.../pull/<n>/files?diff=split` link on its own bullet, ahead of the merge
  link. A merge click is only informed if he can see everything it lands.
- **A merge card is filed only for a PR whose base is the repo's default branch**, checked at
  filing time: `gh pr view <n> --repo <owner>/<repo> --json baseRefName` against
  `gh repo view <owner>/<repo> --json defaultBranchRef`. A card cannot carry a condition such as
  "only after #13, retarget first": he answers cards in seconds and in whatever order they sit.
  On 2026-09-17 ops-infra #17 was carded exactly that way while its base was still #13's side
  branch. He merged it 26 seconds after #13 landed; GitHub showed "Merged"; none of it reached
  `main`, and it had to be re-landed as #18. **A stack lands as one PR from the top branch to the
  default branch** (memory `github-stacked-pr-merge`), and that one PR is what gets the card. If a
  PR's base is not the default branch, there is nothing to card yet.
- **What a card says about a PR's contents comes from `gh` at filing time**, never from a handoff,
  a lane report or memory: `gh pr view <n> --repo <owner>/<repo> --json files --jq '.files[].path'`.
  That covers the file count and any claim like "docs only", "adds files only" or "no code runs".
  On 2026-09-17 site-chernarus #111 and #112 were carded as "two docs files" (each had three), and
  #113 was carded "documents only" while it also added two Python files and a README under
  `tools/quest_grounding/`. #111 and #112 were merged on the wrong description. If the file list
  changes after filing (a push, a merge of `main`), correct the card before he gets to it. Name
  every path outside `docs/` on the card. A merge state of `BLOCKED` or `UNKNOWN` is re-read after
  a minute before it goes on a card: GitHub reports `UNKNOWN` while it is still computing.
- One click per card, numbered in order when they depend on each other ("Step 1 of 3").
- Check the fix would help **before** asking for the click (does the runner exist? is the
  prerequisite merged?). An approved click that unblocks nothing is a wasted owner action.

## Editing an existing card safely

Always pin writes with `if_version` (the document's last-read `version`) and re-read on a
version-mismatch rather than forcing. The PM lost a version-conflict race twice trying to backfill
`recommendedOption` on cards Jeremy was answering live — that's the failure mode this guards
against: two writers touching the same document, last-writer-wins, no warning.

## The approval-device gate

Resolving a card (clicking Approve/Override) is only enabled on one paired browser at a time —
a client-side speed bump against an accidental phone tap or a wrong-device click while the fleet
runs headless, **not real security**: it's a `localStorage` id matched against a shared-db pairing
record, bypassable by anyone with DevTools access to the paired browser. Treat it as a policy nudge.
Pairing is deliberately re-claimable (last claim wins) so a lost browser/cleared storage doesn't
permanently lock the owner out.

## What this queue is explicitly not

- Not an authorization mechanism for irreversible actions (merges, live restarts, credential
  scope changes). A stored resolution record is an instruction, not proof a human clicked it —
  anything downstream that treats a queue answer as sufficient authorization for an irreversible
  action needs its own independent verification of the actual gates (tier, dependencies, mergeable
  state, etc.) at execution time, not trust in the queue record alone. This was tested directly the
  night this queue was built: a dashboard approval-button feature was proposed, built, and then
  fully reverted the same night once this exact distinction was raised.
- Not a place to file something the filer could reasonably decide themselves under an existing
  standard — check `bestPractice` first; if a real standard covers it, that's not a queue item.
