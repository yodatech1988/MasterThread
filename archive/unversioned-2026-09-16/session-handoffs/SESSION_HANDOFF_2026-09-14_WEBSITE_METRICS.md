# Session handoff — 2026-09-14 — website network-status/metrics page

Scoped and designed a public stats/leaderboard page for aegisdirective.net, end to end: design
draft → data-source research → service scoping → player-leaderboard expansion → competitive
research → two real bugs found and fixed. **Nothing was built to running code this session** —
everything below is design + planning documents, verified against live GitHub state. Per owner
instruction, holding here rather than starting NS1's actual implementation.

## What exists now (merged)

| Repo | PR | What | State |
|---|---|---|---|
| website | #22 | `docs/design/network-status-mockup.html` — full page mockup (population chart, faction standing, economy pulse, leaderboard, field log, Site Two/Badlands teaser), built on the site's real design tokens (Spectral/Saira Condensed/IBM Plex Mono, amber/rust/green palette) | merged |
| website | #23 | Session 4 scoped in `docs/PLAN.md`: promote the mockup into a real `src/pages/status.html`, client-side fetch, blocked on `stats-api` | merged |
| services | #76 | New track `stats-api` scoped in `docs/PLAN.md`: a public read-only Node HTTP service (NS1 build → NS2 deploy → NS3 reputation export) | merged |
| services | #74 | Unrelated economy fix (catalog-sku reconciliation), merged same session, not part of this thread | merged |
| services | #80 | Expanded `stats-api` scope: added a real **richest-survivors leaderboard** (buildable now); corrected "AI kills" to **not** a tracked counter, only a reputation score; added Session NS4 for zombie/PvP kills, gated on the unbuilt `event-relay` pipeline | merged |
| website | #24 | **Bug fix**: the mockup invented a "Cordon" faction that doesn't exist in this site's real canon — replaced with the actual 5 factions from `factions.html`. Also reworded "AI kills" → "Reputation" to match the services-side correction. Added Session 5 (server-connect widget) and Session 6 (Archon-style rules cards), sourced from competitive research | merged |
| services | #82 | **Bug fix**: dropped the PvP-kill leaderboard entirely — this is a PVE-only server with "No PvP" as an enforced rule (`start.html`), not just missing data | merged |

Also merged this session, unrelated to website metrics (a general "merge everything mergeable"
pass): `site-chernarus` #68-72, `core` #69, `jarvis` #13, `claude-session-archive` #11,
`gh-federation` #6. Not covered further in this doc — see each repo's own `docs/PLAN.md`.

## The two real bugs this session caught (worth remembering)

1. **Don't invent lore/facts for a mockup, even a "just placeholder" one.** The first mockup pass
   used "Cordon" as a faction name without checking `aegis-website/src/pages/factions.html` first.
   The site's real, live canon is 5 confirmed factions (Coalition, People's Front, Chernarus
   Police, Collectors, Medics) plus a deliberately unconfirmed sixth — never "Cordon." Caught only
   because a later research pass happened to read that page for unrelated reasons. **Lesson:**
   when a mockup references in-universe facts (faction names, rules, lore), read the real content
   pages first even for "just design," not just the CSS/design-token system.
2. **"AI kills" was never a real, tracked number.** `AEGIS_Metrics` stores a composite
   `Reputation`/`HighestReputation` score (25 points ≈ Tier 3), not a per-kill counter. A
   leaderboard column literally labeled "AI kills" would have shown reputation points mislabeled
   as a kill count once real data landed. Fixed by renaming to "Reputation" everywhere and scoping
   a real counter as separate, later mod work if ever wanted.
3. **This is a PVE server — "No PvP" is an enforced rule, not flavor text.** `start.html` states
   it plainly. A PvP-kill leaderboard was scoped into NS4 without checking this and had to be
   removed outright (not deferred — it should never exist), since celebrating player kills
   publicly would contradict the server's own rules.

## Data reality check (what's actually sourceable today)

| Stat | Real data today? | Source |
|---|---|---|
| Population, uptime | Yes | `dayz_ops.player_sessions` / `server_instances` |
| Economy pulse (trades, volume) | Yes | `dayz_economy.ledger_transactions`/`ledger_entries` |
| Richest survivors | Yes | `dayz_economy.wallets.balance_units` joined to `dayz_community.players.display_name` |
| Leaderboard by playtime | Partial | `player_sessions` gives "sessions today" now; real cumulative hours blocked on `dayz_ops` Session O5 (ADM log parsing, blocked on an owner-supplied log sample) |
| Faction standing / reputation tier | No — mod-only | Lives in Expansion save data (`AegisMetrics.c`), never written to any DB. Needs NS3 (mod-side export, unscheduled) |
| Zombie/infected kills | No | Not tracked anywhere. Needs the `event-relay` pipeline (only 1/3 built) + NS4 |
| PvP kills | **N/A — out of scope by design** | Server rule is no-PvP; not a feature to build |

## Competitive research (2026-09-14, informed Sessions 5 & 6)

Looked at archondayz.com, dayzunderground.com, rankly.gg, killfeed.com, and the open-source
Mirasaki dayz-community-template. Findings:

- Most DayZ server sites **don't build native leaderboards** — they embed third-party widgets
  (CFTools, Rankly.gg). AEGIS building `stats-api` natively (matching brand, not an embed) is the
  right call given that.
- Near-universal and missing from AEGIS's site: a server-IP **copy-to-clipboard connect widget**
  with a `steam://connect/...` link. `start.html` currently just prints the address as plain text.
  → Session 5.
- archondayz.com's "Survival Handbook" turns rules into expandable cards instead of a flat list —
  fits AEGIS's existing lore/document tone well. → Session 6.
- Anti-patterns to avoid: unstyled raw third-party iframes, and gating stats behind a login/
  whitelist wall (bad for the public-facing recruitment goal, and the owner confirmed the
  whitelist is testing-phase only, not a permanent production gate).

## Current plan state (all "not started," ready to pick up any time)

**`aegis-website` `docs/PLAN.md`:**

| Session | Blocked on | What |
|---|---|---|
| 4 | `stats-api` NS1+NS2 | Wire `docs/design/network-status-mockup.html` into a real `src/pages/status.html` |
| 5 | nothing | Server-connect widget (IP copy button, `steam://` link) on `start.html` |
| 6 | nothing | Restructure `start.html`'s existing rules into expandable cards, no new rules |

**`aegis-services` `docs/PLAN.md`, track `stats-api`:**

| Session | Blocked on | What |
|---|---|---|
| NS1 | nothing | Build `stats-api/` itself — population, uptime, economy, richest-survivors, sessions-today leaderboard |
| NS2 | NS1 | Deploy to the OVH VPS, reusing existing DB credentials (Shockbyte can't create scoped read-only users — confirmed, documented) |
| NS3 | owner wants it enabled | Mod-side reputation export → faction standing + "Directive Standing" leaderboard |
| NS4 | `event-relay` EV2/EV3 (owner decision: mod vs. log-scraper) | Zombie/infected-kill leaderboard only |

## Starter prompt for next session

`Read GitHub\SESSION_HANDOFF_2026-09-14_WEBSITE_METRICS.md in full, then aegis-website's
docs/PLAN.md and aegis-services' docs/PLAN.md (track "stats-api"). Owner said "document everything
and hold off" on 2026-09-14 — confirm with the owner before starting any build. The
lowest-friction next steps with zero blockers are website Sessions 5/6 or services NS1; NS1 is the
one that unblocks the most downstream work (website Session 4).`
