# Lessons-learned ledger

Every agent (lane, orchestrator, subagent) that hits a real false assumption, a near-miss, or a
rule worth generalizing emits a short lessons-learned block in its report or PR body. This file is
the running ledger of those blocks and the rule for turning a repeated one into something
permanent — a skill's Never-list, or a standards/policy doc.

## Format

Each entry:

```
### <short title> — <date first seen>
- **False assumption or none:** <what was wrongly assumed, or "none — this is a rule candidate
  from something that went right / a near-miss">
- **Rule candidate:** <the generalizable rule, stated as a "never X" or "always Y">
- **Where it belongs:** <which skill's Never-list, which standards/policy doc, or "not yet
  promoted">
- **Seen:** <count> — <dates/contexts of each occurrence>
```

## Promotion rule

- **First occurrence:** logged here only. Don't promote off a single data point.
- **Seen twice:** promote. The PM (or the orchestrator running `round-closeout`) adds the rule
  candidate to the named skill's Never-list, or to the named standards/policy doc, in the same
  close-out that recorded the second occurrence — not deferred to "later."
- **Never silently drop** a seen-once entry; it stays in this file until it's either promoted or
  explicitly marked stale (superseded, or the underlying process changed so it can't recur).

## Entries

### Admin Cost Report API gotchas — 2026-09-15 (seen enough to promote)
- **False assumption:** that the Anthropic Admin Cost Report API returns amounts in dollars, that
  `ending_at` is optional, and that a large `limit` value is honored.
- **Rule candidate:** always treat returned amounts as **cents**; always pass `ending_at`
  explicitly and expect it to **clamp to the last complete UTC day** (not "now"); never request
  `limit` above **31** — it caps there regardless of what's asked.
- **Where it belongs:** promoted — see `aegis-admin-cost-report-api-mechanics` (memory note) and
  `aegis-ops-cost-accounting`. Cited here as the worked example of the seen-twice promotion rule:
  this gotcha was independently rediscovered a second time before someone finally wrote it down,
  which is exactly the waste this ledger exists to stop ("don't rediscover a 3rd time").
- **Seen:** 2+ — first hit while building the ops cost-accounting round, rediscovered once more
  before being written down.
