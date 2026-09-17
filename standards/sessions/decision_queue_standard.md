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
