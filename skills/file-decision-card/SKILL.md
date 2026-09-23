---
name: file-decision-card
description: Use when a session needs to file a card to the Ops Decision Queue — a decision the owner must make, or a click only the owner can perform — and wants it to pass every standing schema/format rule (card shape, required fields, writing-to-be-scanned, executability check, links) on the first write.
---

# file-decision-card

## When to use this

- A session has hit a point CLAUDE.md's "Owner decisions go through the Ops Decision Queue by
  default" rule covers: something the owner must decide, or a click only the owner can make (a
  click-file, an owner-only merge, a repo setting flip).
- A permission-classifier denial needs to become a card (route the drafting itself to
  `denial-card-drafter` — see step 2).
- Before relaying any existing action card to the owner, to confirm it still meets the
  executability bar.
- Not for something an existing standard already answers — check `bestPractice` first; if a real
  standard covers it, decide it yourself and skip the queue.

## Procedure

1. **Get the current artifact URL and collection, don't hardcode one.** Read
   `standards/sessions/decision_queue_standard.md` from `origin/main` for the live `Current URL:`
   line (`decisions` collection) — it drifts on redeploy. If it 404s, check
   `MasterThread/docs/REPOS.md` or ask in the fleet before filing.

2. **Decide `kind` and route drafting appropriately:**
   - **Permission-classifier denial** (`[Remote Shell Writes]`, `[Production Reads]`,
     `[Interfere With Workloads]`, `[Irreversible Local Destruction]`, `[Permission Grant]`,
     `[Self-Modification]`, etc.): hand the raw facts (exact tool call/command verbatim, the
     classifier's reason verbatim, what it would change and on which host/file/repo) to the
     `denial-card-drafter` agent. It drafts the card in the "Permission-denial cards" shape but
     never files it — filing is still this session's job, after step 6.
   - **A click only the owner can perform** (click-file, owner-only merge, repo setting): `kind:
     "action"`.
   - **Everything else the owner must decide**: `kind: "decision"`.
   - Set `kind` explicitly on every card — an un-kinded card whose first option reads as a
     completion claim ("Done", "Merged") is treated as an action card by the page's own logic,
     which changes its shape without anyone choosing that.

3. **Write to be scanned, one card per decision.** `title` is the question, as a question.
   `summary` is one plain sentence under ~200 characters, no jargon — a second sentence means a
   second card or a `points` bullet. `points` is at most 5 one-line bullets: only what changes the
   answer (cost, what it unblocks, what it arms, how to undo), not the history of how it arose.
   `details` (decision cards) holds everything else, shown collapsed. Don't bundle several
   decisions behind one merge/hold choice — five decisions is five cards, plus one for the merge if
   useful. `category` is free text (`security/access`, `cost/infra`, `process/governance`,
   `permission/denial` for a denial card). `source` names the actual session or PM relay, not "the
   fleet" or "a peer said".

4. **`bestPractice` is required on every card, no exceptions.** Name the specific
   `MasterThread/standards/` or `_security-public/policies/` doc if one applies (a denial card
   cites `headless_agent_permissions.md`), cite recognized general practice if no standard exists,
   or state plainly nothing covers it. Never invent one. If it disagrees with the suggestion, say
   so in `divergenceNote` — that's the field the owner's judgment is actually needed for.

5. **Decision cards:** `options` + `recommendedOption` + `recommendedRationale` together, or no
   `options` at all. Labels under ~90 characters; the reasoning lives in `recommendedRationale`,
   which stays visible. `recommendedOption` is shown as "ops recommends," never preselected or
   copied into `resolution` — the owner still clicks one. An option is never a completion claim
   ("Done - merged") — a click he owes is an action card, which has no options.

6. **Action cards:** steps go in `context` (numbered, with line breaks: what to click, in what
   order, what he'll see, what "wrong" looks like, how to undo) and it stays visible, unlike a
   decision card's collapsed `context`/`details`. **Run the executability check before filing or
   relaying**: every step traces to a primary source (current vendor doc fetched at filing time,
   read date recorded) or was actually performed by the filer; every named UI screen/button cites
   that doc, never memory. Ask, per step, "what artifact does it produce, and can the next step
   consume it?" — not just "is it clear?" Route this to the `owner-instruction-verifier` agent
   (verdict EXECUTABLE / UNVERIFIED-STEP n / IMPOSSIBLE-STEP n; it has no `ArtifactData` tool, so
   export the steps to a file or paste them). Record who/when/what in `executabilityCheck` — a
   card left `"not-checked"` is held by the PM, not relayed. One click per card; number dependent
   steps ("Step 1 of 3") rather than splitting cards. Before a merge card: confirm the PR's base is
   the default branch (`gh pr view <n> --json baseRefName` vs `gh repo view --json
   defaultBranchRef`), check for absorbed PRs (`gh pr list --state merged --base <head-branch>` —
   link each ahead of the merge link), and pull the file list from `gh pr view <n> --json files
   --jq '.files[].path'` at filing time, naming every path outside `docs/`.

7. **Links and paths — one destination per bullet, never just named.** A URL or path the owner
   must use goes on its own `points` bullet. A PR gets its side-by-side diff link first
   (`https://github.com/<owner>/<repo>/pull/<n>/files?diff=split`), then the PR page. A click-file
   is given as its full path (`C:\Users\...\AEGIS-Thing.cmd`), never a bare filename.

8. **Stamp `createdAt` from the real clock**, never typed from memory: `date -u
   +%Y-%m-%dT%H:%M:%SZ`, read at the moment of the write. A hand-typed stamp has produced cards
   that look answered before they were filed.

9. **File the card** (never `status: 'resolved'`, never populate `resolution` at filing — only the
   owner's own action on the page ever writes those):

   ```js
   db.collection('decisions').add({
     kind: 'decision', // or 'action'
     title, summary, points, details, // or `context` for an action card's steps
     ownerRequired, category, source,
     bestPractice, // required
     options, recommendedOption, recommendedBy, recommendedRationale, // decision cards only, all together
     executabilityCheck, // action cards only
     status: 'open', resolution: '', comment: '',
     createdAt: '<date -u output>',
   })
   ```

10. **Read the card back to confirm it landed as intended** (`ArtifactData` `get` on the new doc
    id) — check `kind`, `status: "open"`, and that `resolution`/`resolvedAt` are empty.

11. **Once the card is open, start the 5-minute watcher** for it (`/loop 5m …` /
    `CronCreate "*/5 * * * *"`) that reads the `decisions` store, checks only this session's own
    open cards by doc id (not a full `list`), reports changes, and acts on an answer within its
    own permissions. Cancel the job once none of the session's cards are open or pending
    follow-up.

## Stop conditions

- Do not file if an existing `MasterThread/standards/` or `_security-public/policies/` doc already
  answers the question — decide it yourself instead.
- Do not set `status: "resolved"`, populate `resolution`, or otherwise resolve a card on the
  owner's behalf — the sole exception in the standard is a session closing an **action** card on
  verified live evidence after the owner has pressed "I did it - check it," or on evidence alone
  with that noted in `resolution`; a decision card is never resolved by a session under any
  circumstance.
- Do not write `options`/`recommendedOption` on an action card, and do not write action-card steps
  as a decision card's collapsed `details`/`context` — they must stay visible.
- Do not relay, or let a PM relay, an action card whose `executabilityCheck` still reads
  `not-checked`.
- Do not write a secret or credential value into any card field — the queue is a shared artifact
  database, not secret storage.
- Do not bundle more than one decision behind a single set of options.
- Do not invent a `bestPractice` citation — name a real doc, name recognized general practice, or
  say plainly that none applies.

## Grounded in

- `standards/sessions/decision_queue_standard.md` (`origin/main`) — "Card shape", "Permission-denial
  cards", "Executability check", "Writing a card to be scanned" (incl. "Links and paths"), "Filing
  a card", "Action cards", "What this queue is explicitly not".
- `docs/LESSONS.md` (`origin/main`) — "A hand-typed timestamp rule needs a machine, not another
  reminder" (2026-09-17, `createdAt` from the clock) and "`claimedAt` is stamped on any button
  press, not only on 'Done'" (2026-09-18, read `checkResult`/`claimComment` alongside it, never
  write them).
- `docs/AGENTS.md` (`origin/main`) — roster rows for `denial-card-drafter` and
  `owner-instruction-verifier`.
- `C:\Users\yoda_\.claude\CLAUDE.md`, "Owner decisions go through the Ops Decision Queue by
  default" — file-then-say-so, one decision per card, never resolve on the owner's behalf, secrets
  never in the db, the 5-minute watcher once a card is open.
- `skills/land-pr/SKILL.md`, `skills/owner-click/SKILL.md` (`origin/main`) — format followed here.
