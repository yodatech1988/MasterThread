# Ops Decision Queue page

The source of the Ops Decision Queue artifact, the page the owner answers cards on, plus the two
harnesses that test it. Until 2026-09-17 this source existed only in whichever session's scratchpad
last published it.

- **Live page:** https://claude.ai/artifact/1fMqNA1zdQKsq1FDEFvyzf
- **This copy is:** artifact **Version 19**, publish label "No pre-highlight on decision cards",
  platform version id `1789668310-a0f2`, published 2026-09-17 by github-dc. Verified identical to
  the live page body when it was committed.
- **Contract for cards:** `standards/sessions/decision_queue_standard.md`. The page footer carries
  the same rules for whoever is looking at the page.

| File | What it is |
|---|---|
| `ops-decision-queue.html` | The page, exactly as passed to the publish call. No `<!doctype>`, `<html>`, `<head>` or `<body>`: the platform wraps it. |
| `click-harness.js` | Runs the real page script in jsdom with a fake database and real click events. Covers the write paths: what gets written, and that nothing is written when it should not be. |
| `render-harness.js` | Calls the page's card builders and checks the HTML strings: escaping of database text, the scannable-card layout, the collapsed Background section. |

## Run the tests

```
cd tools/decision-queue
npm ci
npm test
```

Both print one `PASS`/`FAIL` line per check and end with `ALL PASS`; the exit code is non-zero on
any failure. `click-harness.js` takes the page file as an argument, so you can point it at another
copy: `node click-harness.js some-other-version.html` (the file must be in this directory).

What the harnesses cannot tell you: jsdom has no layout, so the phone/desktop approval gate,
clipboard, focus restore and how the armed (red) state looks are untested, and so is how the
platform carries an open tab across a republish. Click through a real browser after any change to
those.

## Changing the page

The repo copy and the live page must never drift. Any session can republish the page, so assume
someone else may have since this file was committed.

1. **Read the live page in full first** (Artifact `read` on the URL, then Read every line of the
   saved file). The platform refuses a publish from a session that has not.
2. **Diff live against this copy before editing anything.** Save the live page with Artifact
   `read` + `path: "index.html"`, take what is between `<body>` and `</body></html>`, and compare it
   with `ops-decision-queue.html`. If they differ, someone changed the page without updating the
   repo: bring that change into the repo copy first (and find out who and why), or you will
   silently undo it.
3. Edit `ops-decision-queue.html` here, in a worktree. Add or update harness checks for what you
   changed; a fix to a write path gets a check that fails on the old version.
4. `npm test` passes.
5. **Publish** with the artifact's `url`. Never `force`. Omit `capabilities` and `favicon` so the
   stored `db` capability and the icon carry forward. Give it a short `label`.
6. **Read it back** (`path: "index.html"`) and confirm the body is identical to the file you
   tested.
7. **Same PR:** the updated `ops-decision-queue.html`, the harness changes, and the new version
   number, label and version id in this README. A republish with no matching PR is a defect.

Every string that comes from the database is untrusted: it goes through `esc()` or `rich()` (which
escapes first) before it reaches `innerHTML`. Keep it that way; `render-harness.js` checks it for
each card builder.

## Things the page must keep doing

These are the behaviours the harness pins. Each one exists because of a real incident.

- Nothing is preselected on a decision card; Approve is disabled until the owner picks (owner
  decision 2026-09-17).
- His pick survives the page rebuilding itself (every database snapshot, and once a minute). Before
  Version 17 a rebuild reset the pick and Approve could write the recommended option instead.
- Every write is two clicks. An armed confirm survives a rebuild only for the option it was armed
  for and only within 8 seconds; changed options drop both the pick and the confirm.
- An action card's button records a claim and never resolves; no option on an action card can
  resolve it; "It looked wrong" writes `checkResult` with `checkedBy: "owner"` and leaves it open.
- Copy buttons stay usable while a card is saving.
