---
name: session-cost-audit
description: Use when the owner, PM, or cost steward needs a real, cache-inclusive token cost per model for a session, a day, or a set of sessions — instead of a naive input/output tally, a guessed rate, or a session's own self-reported figure.
---

# session-cost-audit

## When to use this

- The owner or PM asks "what did this cost", "what's Opus spend today", "is this session cheap to
  keep running", or wants a number to back a Decision Queue card or a cost-steward escalation.
- A session is asked to state its own cost. It cannot — per the recorded lesson, a live session can
  see its subagents' token totals but not its own input/output (`docs/... cost and token control`
  lesson, "A session cannot see its own input and output tokens, only its subagents"). Route the
  question to this skill's tools instead of accepting a self-report.
- Before trusting any cost figure that isn't already sourced from `tools/cost-monitor/` or
  `tools/cost-steward/` output.

This skill wraps the estate's existing cost tooling. It never computes a token count or a dollar
figure itself, and it never writes a new cost script — every lesson behind this request
("naive tally understates Opus ~10x", "dedupe duplicate transcript lines for one response id, take
the max/last `output_tokens`", "cache-read/write shown separately", "unverified model = unpriced")
is already implemented in the tools below.

## Procedure

1. **Never ask a session to self-report.** Read the number from transcripts with a script — that is
   the whole point of the lesson this skill exists for.

2. **Pick the tool by scope — don't build a new one:**
   - **Whole-estate / multi-day / multi-session ledger, with a dollar what-if and alert/stop exit
     codes:**
     ```
     python tools/cost-monitor/cost_monitor.py --no-write --days <N> --day <YYYY-MM-DD> --top <N>
     ```
     Reads `~/.claude/projects/<this-workspace-slug>/**/*.jsonl` (this project folder only) plus
     the headless drop-folder (`%APPDATA%\AEGIS\reports\`). Needs PyYAML; **exits 3 rather than
     guess a rate** if it isn't installed — don't route around that by hand-computing.
   - **Live session(s) right now, context size and next-turn cost, subagents rolled in:**
     ```
     python tools/cost-steward/cost-steward.py            # one table, all live sessions
     python tools/cost-steward/cost-steward.py --watch N   # print only on advice-level change
     ```
   - **A named set of sessions against a round's dollar cap:**
     ```
     python tools/cost-steward/round-cap.py ROUND START_ISO CAP "Name1,Name2,..."
     ```
   - **Compaction accuracy signal (re-read rate, correction phrases before/after a compact
     boundary):** `python tools/cost-steward/compactions.py [--json OUT.json] [--since ISO]`.
   - **Fable Ops Console cost doc:** `python tools/cost-steward/console-cost.py EXPORT_DIR
     OUT_JSON` — needs an `ArtifactData` export of the Execution Board `rounds`/`runs` collections
     first; this skill does not perform that export.

3. **Confirm, don't reimplement, the two hard lessons — both tools already do this:**
   - Duplicate transcript lines per response: `cost_monitor.py` explicitly "keeps the greatest per
     message id" (README, "The first snapshot undercounted output"); `cost-steward.py` and
     `round-cap.py`'s `scan()`/`spend()` keep "last line per message id wins", which the same
     measurement (40,334 responses) found is always the max. If a transcript shape ever breaks that
     equivalence, that's a real tool gap — flag it, don't patch around it by hand.
   - Cache is priced and reported apart from input/output, split by TTL where the line carries
     `cache_creation.ephemeral_5m_input_tokens` / `ephemeral_1h_input_tokens` (`cost-monitor`
     `config.json` `cache_multipliers`; `cost-steward.py`'s `PRICES` tuples).

4. **Rates only from the tool's own verified source — never from memory:**
   - `cost_monitor.py` reads `ops-policies` `routing/models.yaml` at `origin/main` via `git show`
     and prints the source, commit and `verified_on` date. A model not matched there is reported
     `UNPRICED` and excluded from the dollar total.
   - `cost-steward.py` / `round-cap.py` carry a fixed `PRICES` table dated against
     `claude.com/pricing` (read 2026-09-22, in the file's own docstring). An unmatched model
     contributes nothing to that session's cost.
   - If a model you need is in neither source, report it **unpriced** — do not estimate a rate.

5. **State what's included in the report, every time:** which script ran, which days/sessions,
   whether subagents are folded into the parent (`cost-steward.py`/`round-cap.py` do) or shown as
   separate rows (`cost_monitor.py` does), and the one-line disclosure both tools already carry:
   this is a **cache-inclusive, list-price what-if, not a bill** — the subscription's marginal cost
   is $0.

6. **Hand the number off, don't act on it.** If the audit feeds a live escalation (compact/rotate a
   session, a round over cap), that decision belongs to the cost-steward seat / PM per
   `standards/sessions/cost_steward.md` — this skill supplies the verified figure, not the
   instruction. If it should become a Decision Queue card (e.g. a threshold looks wrong), file it
   per the owner's Decision Queue standard; this skill never resolves or files one itself.

## Stop conditions

- `cost_monitor.py` exits 3 (no PyYAML, unreadable transcripts/config, stale data) — report the
  exit code and reason; do not hand-compute a substitute figure.
- A model isn't in `routing/models.yaml` or `cost-steward.py`'s `PRICES` — report **unpriced**,
  never a guessed rate.
- The session's own transcript file can't be found under `~/.claude/projects/**` — say so; don't
  substitute another session's numbers or rate.
- Anything beyond running these tools read-only and reporting their output is out of scope for this
  skill — no new script, no edit to `config.json`/`PRICES`, no write except the tools' own state
  files (`ledger-*.jsonl`, `status.json`, `cost-steward.state.json`), no compacting or rotating a
  session, no Decision Queue write.

## Grounded in

- `tools/cost-monitor/README.md`, `tools/cost-monitor/cost_monitor.py`,
  `tools/cost-monitor/config.json`, `tools/tests/test_cost_monitor.py` (dedupe-by-max-output-line,
  cache split, `UNPRICED` handling, exit codes, `--no-write`/`--days`/`--day`/`--top` flags)
- `tools/cost-steward/cost-steward.py`, `tools/cost-steward/round-cap.py`,
  `tools/cost-steward/compactions.py`, `tools/cost-steward/console-cost.py`
- `standards/sessions/cost_steward.md` (seat's authority, advice levels, what the steward owns vs.
  this skill)
- `C:\Users\yoda_\GitHub\LESSONS_INBOX_2026-09-20_github-19.md` (section D: "Cost was unmeasured
  until asked, and a naive tally understates Opus about 10 times"; "A session cannot see its own
  input and output tokens, only its subagents"; "I repeated a claim from a memory note without
  testing it, and it was wrong" — the duplicate-line/max-output finding)
- `C:\Users\yoda_\GitHub\PM_PLAN_cost_monitoring_2026-09-20_github-19.md`
