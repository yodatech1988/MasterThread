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
| `context` | string | What's actually going on, enough for someone with no prior context. |
| `ownerRequired` | boolean | `true` = blocks until Jeremy acts; `false` = ops proceeds unless overridden. |
| `category` | string | Free text, e.g. `security/access`, `cost/infra`, `process/governance`. |
| `source` | string | Who/what raised it and when — cite the actual session or PM relay. |
| `suggestedResolution` | string | What ops would do here, in prose. Optional if `options`+recommendation cover it. |
| `rationale` | string | Why, for `suggestedResolution`. |
| `bestPractice` | string | **Required** (2026-09-16 standing rule). What established practice actually says — name the specific `MasterThread/standards/` or `_security-public/policies/` doc if one applies, the recognized general practice if it doesn't, or state plainly that no standard covers it. Never invent one. |
| `divergenceNote` | string | Required whenever the suggestion and `bestPractice` disagree — say so and explain why. This is the single most useful field on a card; it's where the owner's judgment is actually needed. |
| `options` | string[] | Discrete choices, when the decision has a small finite shape. |
| `recommendedOption` | integer | **Required whenever `options` is present** (2026-09-16 standing rule). Index into `options` — the option ops would pick, preselected on the card. A card with options and no recommendation pushes the analysis back onto the owner, which defeats the point. |
| `recommendedBy` | string | Who made the recommendation. |
| `recommendedRationale` | string | Why that option, specifically. |
| `status` | `"open"` \| `"resolved"` | The only field the page's render logic keys off for open/resolved grouping — never inferred from whether `resolution` is non-empty. |
| `resolution` | string | The owner's actual answer. Empty until they've actually answered — never pre-filled with a recommendation copied in, even as a placeholder; that has caused real confusion when a card was miscategorized as answered. |
| `comment` | string | Free-text context the owner added alongside their resolution. |
| `followUpPending` | boolean | **Set whenever a resolution names a real action that hasn't happened yet** (an owner click, a build, a merge) (2026-09-16 standing rule). Keeps the card visible indefinitely — see Lifecycle below. `followUpNote` says what's still outstanding. |
| `corrections` | array | `{ note, correctedBy, correctedAt, previousResolution }` entries, appended — never delete or silently overwrite a resolved card's `resolution` in place; append a correction and update `resolution` to the new value. See Correcting a resolved card below. |
| `createdAt` / `resolvedAt` | ISO 8601 | Timestamps. |

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

## Filing a card

Any session can add one directly:

```js
db.collection('decisions').add({
  title, context, ownerRequired, category, source,
  bestPractice,                       // required
  options, recommendedOption, recommendedBy, recommendedRationale,  // required together if options exist
  status: 'open', resolution: '', comment: '', createdAt: new Date().toISOString(),
})
```

Never set `status: 'resolved'` or populate `resolution` at filing time — only the owner's own
approval/override action does that, via the page.

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
