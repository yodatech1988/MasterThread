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
| `dq_monitor.py` | Report-only audit of an exported `decisions` collection (see "Audit the board" below). Not part of the page; it never writes to the queue. |
| `dq-headless-watch.ps1` | Headless, low-context check of specific card doc ids via a `claude -p` subprocess (see "Headless card watch" below). Not scheduled by anything yet -- see that section. |

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

## Audit the board (`dq_monitor.py`)

A read-only report over the `decisions` collection: open owner-required cards oldest first, owner claims
not yet verified, resolved cards with `followUpPending`, session-written resolutions, and card hygiene
(action cards without `executabilityCheck`, cards without `kind`, options without a recommendation,
stamp drift). It exists so the audit in `standards/sessions/decision_queue_standard.md` ("Auditing the
board") is one command instead of a hand-rolled script each time.

```
# 1. export the cards: ArtifactData `list` on the decisions collection with out_dir=<dir>
# 2. run it on the exported directory (stdlib only; Python 3.8+)
python tools/decision-queue/dq_monitor.py <dir>
python -m unittest tools.tests.test_dq_monitor      # its tests, from the repo root
```

It only prints. What it prints is for a person or the PM to act on: the standard says to report a
suspect card and never reopen it, under any signature (including a whole-second `resolvedAt`), and
that a resolution matching `options[recommendedOption]` is not evidence of a defect. Section D relies on one rule, that a
`resolvedAt` with milliseconds was written by the page and one without was composed by a session
(`PAGE_WRITTEN_STAMP` in the script); if the page's stamping ever changes, change that constant and
the standard together.

## Headless card watch (`dq-headless-watch.ps1`)

Built for Decision Queue card `cost-monitor-card-watcher-headless-2026-09-26` (option 0, resolved
2026-09-26): move the 5-minute "did the owner answer?" check out of an interactive PM session's own
context into a headless `claude -p` run a scheduler can fire on a timer, per
`PM_INBOX\cost-monitor\SELF_IMPROVEMENT_PLAN_2026-09-26.md` section R2.

**Verified before this was built (2026-09-26):** the plan flagged as unverified whether a headless
`claude -p` process can call the `ArtifactData` tool at all -- subagents cannot, so it had to be
tested by actually invoking `claude -p` as a subprocess and inspecting the real
`tool_use`/`tool_result` blocks (`--output-format stream-json`), not by asking the CLI to describe
itself (a model can hallucinate a tool call). It can: a `get` against the live artifact returned the
real stored document, confirmed against `--output-format stream-json` output showing the actual
`db_read` result, not just the model's prose summary.

**Cost finding that revises the plan's own $0.01/tick estimate:** even with `-AllowedTools` limited
to exactly `ArtifactData` and a single doc id, a run costs about **$0.08-0.19** (Haiku), not $0.01 --
the fixed per-invocation baseline (system prompt, connected MCP servers, skills listing) loads
regardless of `--allowedTools`, and `--bare` (which would strip it) breaks the OAuth/keychain auth
this machine's subscription billing relies on, so `--bare` is not usable here without a paid API
key. At a 5-minute cadence that is roughly $1-2/hour if run around the clock -- still far cheaper
than the plan's own $4-14/hour estimate for an idle interactive PM running the same check, but not
the plan's "$3/day" figure. Re-check this against real `cost-monitor` data after a day of real runs
before relying on either number.

```powershell
tools\decision-queue\dq-headless-watch.ps1 -DocIds "some-card-doc-id","another-card-doc-id"
```

- Reads last-seen `{version, status}` per doc id from `-StateFile` (default
  `%APPDATA%\AEGIS\dq-watch-state.json`).
- Makes one `claude -p` call (Haiku by default), `-AllowedTools "ArtifactData"` only,
  `--permission-mode dontAsk --permission-prompts none` (nothing waits on an unanswerable prompt),
  and a `--json-schema` that forces the reply to be only `{"docs":[{doc_id, found, version,
  status}, ...]}` -- no card body ever reaches this script's parsing or its log.
- Appends **one line per doc that is new, or whose version or status changed** to `-LogFile`
  (default `%APPDATA%\AEGIS\dq-changes.log`) -- doc_id plus old/new version and status only.
- Rewrites `-StateFile` with the latest values.

Tested (this PR) against the real, already-resolved card `cost-monitor-card-watcher-headless-2026-09-26`:
a first run logged `NEW ... version=2 status=resolved`; an immediate second run with the same doc id
logged nothing (no change).

**Not done here, on purpose:** nothing schedules this. Turning it into a real Windows Task Scheduler
job, and deciding the doc-id list and cadence, is a follow-up for the owner or PM after reviewing
this PR -- this task's scope was building and testing the script, not enabling it. It also is not
wired into `tools/headless/Invoke-ReadOnlyAgent.ps1`'s roster/`-Restricted` machinery:
`ArtifactData` is not a `Bash` sub-command that harness's three-layer model was built to fence in,
it is a first-class tool granted directly by name (`--allowedTools "ArtifactData"` was verified here
to be the whole grant needed). Wiring this into that heavier harness (a `roster_meta.json` entry,
an `agent-automation-gatekeeper` pass, a `schemas/*.json` file) is left for whoever promotes this
into a standing roster agent.

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
