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

## Exit codes

| Code | Meaning |
|---|---|
| 0 | ok |
| 1 | alert (Opus what-if over the alert line, Opus share of the day, one session's output spike, or `ANTHROPIC_API_KEY` set) |
| 2 | stop-and-ask (Opus what-if over the stop line) |
| 3 | unknown / could not read (missing transcripts, rates, config or state dir), **or** nothing was read at all (an empty or mistyped folder is not a quiet week), **or** a model with no verified rate on the evaluated day |

Precedence when several apply: 2, then 1, then 3, then 0. Checks apply to the evaluated day only (today UTC, or
`--day`). A breach on an earlier day is reported in the tables but does not change the exit code.

## What it reads and writes

- **Reads** `~/.claude/projects/c--Users-yoda--GitHub/**/*.jsonl` (sessions and `subagents/`), read-only. From
  each line it takes only the usage numbers, message id, model, timestamp and the session's `aiTitle`. It never
  prints or stores message text (a test plants a sentinel in the text and checks every output for it).
- **Writes** only under `%APPDATA%\AEGIS\cost\` (override with `--state-dir`):
  - `ledger-YYYY-MM-DD.jsonl`: append-only, one file per data day, each line a full snapshot of that day (per
    model, and per session and subagent). A line is appended only if the day's content changed, so a rerun adds
    nothing. **The current day is appended at most once per `ledger_min_interval_minutes` (default 60)**; a
    finished day is appended immediately so its final line is never lost. Measured: a five-day snapshot is about
    300 KB, so an unthrottled busy day would grow by tens of KB per run.
  - `status.json`: latest totals, breaches, thresholds, rate source and timestamp. Rewritten each run.
- Session rows carry a `label` (the `aiTitle`). **Anything that ever copies the ledger off this PC must drop
  `label`**; the counts, model, day and id are content-free, the title may not be.

## Rates

Read from `ops-policies` `routing/models.yaml` on **`origin/main`** (`git show`, never a working tree), and the
output quotes the source, commit and the file's `verified_on` date. The tool does not fetch, so run
`git -C <ops-policies> fetch` first if the table may have moved.

- A model is matched by exact id, or a known id plus a dated snapshot suffix (`claude-haiku-4-5-20251001` matches
  `claude-haiku-4-5`) and the output labels that match. Nothing else is matched. **Any other model is reported
  `UNPRICED`, adds nothing to the dollar total, and makes the day's total a floor.**
- `models.yaml` prices Sonnet 5 at $2 / $10 per MTok while its own `document_draft` records $3 / $15. The tool
  trusts the file, as agreed, and does not resolve that. If the draft is the right one, every Sonnet figure is
  low by a third.
- Fable 5.1 carries its own `cache_read_factor_override` (0.025) in that file, and the tool honours it.

## Honest caveats

- **What-if, not a bill.** No API key is used, and nothing here reads Anthropic's billing.
- **Cache multipliers are ASSUMED**: read 0.1x, write 1.25x (5 minute) to 2x (1 hour). They live in
  `config.json` marked ASSUMED and have not been checked against a current price page. Cache reads are most of
  the dollars (on 2026-09-18, 467M Opus cache-read tokens against 1.3M output), so a tally without cache is
  wrong by roughly 10x. The report gives a low-high range; **alerts use the high end**, so an uncertain
  multiplier can only make the monitor louder.
- **This project folder only.** Other Claude project folders (for example the DayZ workspace) and any usage not
  written to a transcript are not included. If Claude prunes old transcripts, a live read cannot see them; the
  ledger is what keeps them.
- **Thresholds are DEFAULTS pending owner approval**: Opus what-if $50 a day alert, $100 a day stop-and-ask, Opus
  share of the day at or above 50% (only once the day is at least $10), one session's output at or above
  300,000 tokens in a day. The last was calibrated to the real distribution (p99 of 1,032 day x session rows
  over five days was about 264K; 8 rows reached 300K), so it flags the unusual and not the ordinary. They alert;
  nothing here enforces a limit.
- **`ANTHROPIC_API_KEY` check is presence only**: the current process, the User environment and the Machine
  environment (Windows registry). It records that the name exists, never the value, and scans no files. A key
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
