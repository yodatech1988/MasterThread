# cost-monitor

A meter for Claude Code token use. It reads the local transcripts, counts every API response once, and
reports input, output, cache-read and cache-write tokens **per day, per model, per session and per
subagent**, with a **what-if dollar estimate** at list rates.

**Zero model calls, ever.** No network, no model client, no key. The only subprocess is `git show` against the
local `ops-policies` checkout to read the rate table. A test parses the source and fails if an import or a
subprocess other than `git` appears.

**It is a what-if, not a bill.** Claude Code runs on the subscription today. The dollars answer "what would this
cost at API list rates", so a runaway shows up as a number before it could ever become one.

```
python tools/cost-monitor/cost_monitor.py                 # report + append the ledger + refresh status.json
python tools/cost-monitor/cost_monitor.py --no-write      # report only, touches nothing
python tools/cost-monitor/cost_monitor.py --days 3 --day 2026-09-19 --top 5
python -m unittest discover -s tools/tests                # the tests (fake data only)
```

Tested on Python 3.13; needs PyYAML (`pip install pyyaml`). Without PyYAML it exits 3 rather than guess a rate.

The tests need PyYAML too: without it, the test classes that run the tool end to end are **skipped** with the
reason "PyYAML is not installed" (they cannot pass, because the tool exits 3 by design). Install PyYAML to run
them. CI's `agents-roster-check` job does not install PyYAML today, so there those tests are skipped and CI
does not exercise the cost monitor end to end; run them locally with PyYAML installed.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | ok |
| 1 | alert (Opus what-if over the alert line, Opus share of the day, one session's output spike, or `ANTHROPIC_API_KEY` set) |
| 2 | stop-and-ask (Opus what-if over the stop line) |
| 3 | unknown / could not read (missing transcripts, rates, config or state dir), **or** nothing was read at all (an empty or mistyped folder is not a quiet week), **or** the evaluated day has no data and either some transcript files could not be read or the newest transcript is more than 24 hours old (a possible blind spot, not a quiet day), **or** a model with no verified rate on the evaluated day |

Precedence when several apply: 2, then 1, then 3, then 0. Checks apply to the evaluated day only (today UTC, or
`--day`). A breach on an earlier day is reported in the tables but does not change the exit code.

## What it reads and writes

- **Reads** `~/.claude/projects/<slug>/**/*.jsonl` (sessions and `subagents/`), read-only. `<slug>` is derived from where this checkout lives (the folder that holds the repo, with every non-alphanumeric character turned into `-` and a drive letter lower-cased), not hardcoded; pass `--projects-dir` for any other layout. From
  each line it takes only the usage numbers, message id, model, timestamp and the session's `aiTitle`. It never
  prints or stores message text (a test plants a sentinel in the text and checks every output for it).
- **Writes** only under `%APPDATA%\AEGIS\cost\` (override with `--state-dir`):
  - `ledger-YYYY-MM-DD.jsonl`: append-only, one file per data day, each line a full snapshot of that day (per
    model, and per session and subagent). A line is appended only if the day's content changed, so a rerun adds
    nothing. **The current day is appended at most once per `ledger_min_interval_minutes` (default 60)**; a
    finished day is appended immediately so its final line is never lost. Measured: a five-day snapshot is about
    300 KB, so an unthrottled busy day would grow by tens of KB per run.
  - `status.json`: latest totals, breaches, thresholds, rate source and timestamp. Rewritten each run.
- Session rows carry a `label` (the `aiTitle`). **The label reaches stdout, the ledger rows and `status.json`.** **Anything that ever copies the ledger or status off this PC must drop
  `label`**; the counts, model and day are content-free, the session id is stored as-is (not hashed), and the title may not be content-free.

## Headless drop-folder reports (F8)

In addition to interactive/subagent transcripts, the tool reads `%APPDATA%\AEGIS\reports\` (override with
`--reports-dir`) — the read-only drop folder `tools/headless/Invoke-ReadOnlyAgent.ps1` writes a report file
to (`{envelope, checkedAt, command}`) after each headless run. This stays read-only and additive:

- Only `envelope.total_cost_usd` and `envelope.modelUsage` are used; `command` (which can contain a prompt)
  is never read into any output.
- Each `modelUsage` entry's `costBasis` is asserted to be `"list"`; anything else raises a finding (surfaced
  in the report and counted toward the day's alert/stop precedence) instead of silently trusting a dollar
  figure that may not be list-price-equivalent.
- A report's own `costUSD` is trusted as-is (not re-priced against `routing/models.yaml`) — it is already a
  computed figure from the CLI's own `--output-format json` envelope, not raw token counts.
- A malformed, wrong-shape, or unreadable report file is reported as a finding, never a crash, and never
  blocks reading the rest of the folder or the transcript-based totals.
- An absent reports directory (e.g. this tool run on a machine with no headless activity yet) is not an
  error.

## Rates

Read from `ops-policies` `routing/models.yaml` on **`origin/main`** (`git show`, never a working tree), and the
output quotes the source, commit and the file's `verified_on` date. The tool does not fetch, so run
`git -C <ops-policies> fetch` first if the table may have moved.

- A model is matched by exact id, or a known id plus a dated snapshot suffix (`claude-haiku-4-5-20251001` matches
  `claude-haiku-4-5`) and the output labels that match. Nothing else is matched. **Any other model is reported
  `UNPRICED`, adds nothing to the dollar total, and makes the day's total a floor.**
- `models.yaml` prices Sonnet 5 at $2 / $10 per MTok. That is a deliberate correction of the earlier $3 / $15
  in its `document_draft`, recorded in `ops-policies` `docs/VERIFICATION.md` Record 1; it is not an open
  conflict. The tool trusts the file.
- Fable 5.1 carries its own `cache_read_factor_override` (0.025) in that file, and the tool honours it.

## Honest caveats

- **What-if, not a bill.** No API key is used, and nothing here reads Anthropic's billing.
- **Cache write multipliers are CONFIRMED per-TTL** (F8, 2026-09-22): 1.25x for a 5-minute-TTL cache write,
  2x for a 1-hour-TTL write, against `docs/FABLE_AGENT_SUBAGENT_PLAN.md` secs 1b/11 and the Anthropic pricing
  page. When a transcript response reports `usage.cache_creation.{ephemeral_5m_input_tokens,ephemeral_1h_input_tokens}`,
  each bucket is priced exactly at its own rate. Older transcript shapes (or a headless drop-folder report,
  which reports only a pre-computed dollar figure) that lack that split still price the untyped cache-write
  tokens as a low(5m)-high(1h) range, and **alerts use the high end**. The cache **read** ratio (0.1x) is
  still ASSUMED, not yet checked against a current price page. Cache reads are most of the dollars (on
  2026-09-18, 467M Opus cache-read tokens against 1.3M output), so a tally without cache is wrong by roughly
  10x.
- **This project folder only.** Other Claude project folders (for example the DayZ workspace) and any usage not
  written to a transcript are not included. If Claude prunes old transcripts, a live read cannot see them; the
  ledger is what keeps them.
- **The last hour of a day is only captured if a run happens after UTC midnight** while `--days` still covers that
  day. There is no scheduler yet (see below), so a day's final ledger line depends on someone running the tool
  after midnight; the current day is also throttled to one append per `ledger_min_interval_minutes`.
- **Thresholds are DEFAULTS pending owner approval**: Opus what-if $50 a day alert, $100 a day stop-and-ask, Opus
  share of the day at or above 50% (only once the day is at least $10), one session's output at or above
  300,000 tokens in a day. The last was calibrated to the real distribution (p99 of 1,032 day x session rows
  over five days was about 264K; 8 rows reached 300K), so it flags the unusual and not the ordinary. They alert;
  nothing here enforces a limit.
- **`ANTHROPIC_API_KEY` check is presence only**: the current process, the User environment and the Machine
  environment (Windows registry). It enumerates value **names** only and discards the data that comes back with
  each name, so the value is never stored, printed or assigned; it scans no files. A key
  there silently outranks the subscription token and turns work into metered billing.

## The first snapshot undercounted output. Do not use it.

Each API response is written on several transcript lines, and **`output_tokens` differs between them**: it grows
while the response streams (7, 7, then 920). The last line is the final count; it was the largest in all 40,334
multi-line responses measured, never lower than an earlier line. The tool keeps the greatest per message id.

The Phase 0 prototype kept the **first** line and so undercounted output, by 17-84% for Opus, 25-47% for Sonnet
and about 98% for Haiku across 2026-09-17 to 09-20. In Opus dollars that is only about $8-19 a day on top of
hundreds (cache reads dominate), but the output counts and any Sonnet or Haiku figure derived from them were
materially low. `PM_INBOX\cost-monitor\ledger\snapshot-20260920T0055Z.txt` is the file to distrust; use output
from this tool instead.

## Not in scope here

Scheduling it, anything on a VPS, any click-file, and reconciling against the Admin cost report (billed dollars).
Those are the later phases in the PM's cost-monitoring plan.
