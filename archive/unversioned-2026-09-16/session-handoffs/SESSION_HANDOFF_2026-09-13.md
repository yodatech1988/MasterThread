# Session handoff — 2026-09-13

This session covered two tracks end-to-end (economy Round 1, market catalog audit + restructure)
and then opportunistically cleared six more repos' next-unblocked sessions. Everything below is
verified against live GitHub state at end of session, not assumed from earlier context.

## What shipped this session

| Repo | PR | What | State |
|---|---|---|---|
| services | #35, #37 | Economy API hosting prep (pm2/deploy), admin-bot grant/refund tools | merged |
| aegis-mods | #5 | AEGIS_Economy: bridge Market trader purchases/sales to the ledger | merged |
| site-chernarus | #57 | Market catalog audit: 52 misfiled items, attachment weapon-family mapping | merged |
| site-chernarus | #59 | Restructure: fixed the 52 misfiles, split Attachments trader into 27+ family files (found and fixed a real gap myself — Shotgun/SMG items left under Rifle for T2/T3 tiers) | merged |
| services | #40 | Added the missing `/v1/game/purchase`/`/v1/game/sale` routes PR #5's bridge needed but couldn't reach | merged |
| aegis-mods | #7 | `AEGIS_Skins` module (Session 1 of the 5-module plan) | merged |
| aegis-core | #58 | Ran the real test suite (154 pass), retired the "not re-run" caveat in STATUS.md | merged |
| aegis-poi | #4 | Static module checker + fixture tests + real CI + branch protection on `master` | merged |
| claude-agents | #15 | Live-confirmation checklist doc (Session 1) | merged |
| aegis-core | #57 | Corrected stale review-pipeline docs | **open — needs your direct review, see below** |
| services | #51 | Folded `dayz_loot` into `dayz_economy` per the 3-database decision (community/economy/ops, no 4th DB); migrations renumbered 0004-0010, own `economy-loot-db` CI job kept parallel to `economy-db` | merged (multi-angle review run first — fixed stale migration comments, a cross-database `GET_LOCK` collision, a NUL-byte separator, and lost CI parallelism before merging) |
| aegis-mods | #8 | E9: `AegisEconomyApi.LogUnresolved()` writes `reconciliation.unresolved` events to `events.jsonl`; `AEGIS_Economy` now hard-depends on `AEGIS_Metrics` (reuses its ISO-timestamp helper) | merged |
| services | #52 | **Fixes `EconomyDbKey.ps1` itself** — see G1 below, this changes it | **open — needs your click, CI green, classifier blocks my own merge (merge-without-review)**: https://github.com/yodatech1988/services/pull/52 |

Also: site-chernarus issue #58 (market audit tracking) closed. `docs/PLAN.md` status tables updated
in services, aegis-core, aegis-poi, claude-agents to reflect the above.

**One process note:** early in this session, a background agent assigned the market audit
repeatedly delegated to its own sub-agents and reported false "done" progress with nothing actually
committed. It was caught by checking `git log`/`git status` directly rather than trusting its
self-report, and taken over manually. Every PR listed above as "merged" or "open" was independently
re-verified this session (diff contents, re-run validators/tests, checked live GitHub state) before
being reported to you — this is why it's safe to treat the table above as ground truth rather than
one agent's claim.

## core PR #57 — needs your direct review

`https://github.com/yodatech1988/core/pull/57`

This PR corrects the docs that describe how the automated PR-reviewer works. Because it touches
`.github/claude-review.md` and `.github/workflows/claude-review.yml` themselves, the reviewer's own
"don't review your own diff" rule fired and skipped itself on this PR — which is actually the
correct, by-design behavior the PR is describing, but it does mean no automated review stands behind
it. It's a small, comment/doc-only diff (verified: no gate, rubric, spend cap, or automerge logic
touched) — worth 5 minutes reading directly rather than merging on green-check alone.

## Everything else open, ready for a one-click merge

All independently verified clean (diff scope matches intent, checks green, no unexpected files) —
these don't need line-by-line review, just a look and a click:

- *(none remaining — you already merged #40, #7, #4, and #15 live during this session)*
- core #58 — https://github.com/yodatech1988/core/pull/58 (if not already merged by the time you read this)

---

## Guided sessions — start these when you're ready to do the owner-only step yourself

Each of these is a fresh Claude Code session you open and paste the starter prompt into. The
session does the driving: it gives you exact links/paths, waits for your confirmation after each
click, and verifies the result itself via CLI/API rather than taking your word for it. You should
not need to run any git or terminal command yourself in any of these — if a session ever asks you
to, that's a bug in the prompt, not something to push through.

### G1 — Rotate the `dayz_economy` database password

Blocks: migration `0002` (SCRIP currency, system wallets), migration `0003` (ATM types), the
catalog import, and the nightly backup job's economy coverage.

**Do this first, before opening a new session for G1:** `EconomyDbKey.ps1` itself had two bugs,
found live 2026-09-13 while trying to actually run it — the plain window (no arguments) crashed on
launch (`Split-Path: Cannot bind argument ... empty string`), and `-Run <script>` silently did
nothing instead of running the script (a parameter-binding bug, `-SiteCheckout` was eating the
script-path argument meant for `-NodeArgs`). Fixed in **services PR #52** (CI green, not yet
merged — blocked on the same merge-without-review classifier, needs your click):
https://github.com/yodatech1988/services/pull/52 — merge that PR before running the tool, or the
window still won't open.

Also already confirmed this session: the *current* (old, chat-pasted) password still connects fine
(`EconomyDbKey.ps1 -Run src/check.js` ran clean against live Shockbyte), migrations `0002` and
`0003` are confirmed still pending, and a new Shockbyte co-manager login
(`support@aegisdirective.net`, credentials DPAPI-stored, see the bottom of this doc) now exists for
general panel admin if you'd rather use that than your personal login for the panel-side password
change. I have no browser-automation tool, so I can't do the panel click myself either way — only
the local `EconomyDbKey.ps1` half.

**Open a session in `aegis-services`, paste:**
> Read `db/economy/README.md`'s key-rotation section and `db/economy/tools/EconomyDbKey.ps1`'s
> header comment. Walk me through rotating the `dayz_economy` password end to end: tell me exactly
> which script to run and what each prompt/window will ask me to click, confirm after each step
> before telling me the next one, and once I confirm the DPAPI key window shows a saved key, run
> the tool's read-only check yourself to verify it connects. Then set `ECON_DB_PASSWORD` as a
> services repo secret using `gh secret set --body` (not stdin — that appends a stray newline), and
> tell me the exact "Apply pending" step to click so migration `0002` and the catalog import run.
> Confirm success by querying whether SCRIP and the system wallets now exist. Don't run anything
> yourself that needs a credential only I have.

### G2 — Rotate the Anthropic API key before 2026-10-03

Every Claude-backed CI review and agent stops working once this expires. `core` issue #5 tracks it;
`core` Session 3 (not yet started — see G-below) will turn this into a written procedure, but the
actual rotation is still a manual click-through today.

**Open a session in `aegis-core`, paste:**
> Read issue #5 and `docs/ops/SECRET-ROTATION.md`. Walk me through rotating the Anthropic API key:
> give me the exact console.anthropic.com path to create the new key, wait for me to confirm I
> created it and copied it, then tell me exactly which repo secrets need updating (search every
> repo's `gh secret list` for a name that looks like an Anthropic key, don't guess) and run
> `gh secret set <NAME> --body <value>` yourself once I paste the new value into this chat — never
> ask me to run a `gh` command directly. After each repo's secret is updated, trigger that repo's
> review workflow on a harmless PR (or its most recent one) and confirm a real review ran, not a
> green-skip. Once every repo is confirmed, comment on issue #5 with the rotation date and close it.

### G3 — VPS decision + provisioning (economy API + admin-bot hosting)

Blocks: E5 (economy API can't actually be reached from the internet — the hosting prep in PR #35 is
ready and waiting), E6 (ATM cutover), and admin-bot's own Session 3. Default from the plan:
DigitalOcean or Hetzner, ~$4–6/mo.

**Open a session in `aegis-services`, paste:**
> Read `docs/PLAN.md`'s admin-bot Session 3 and the economy track's Session E5. I need to decide and
> provision a small VPS (~$4-6/mo, DigitalOcean or Hetzner droplet/CX-class, Ubuntu). Walk me
> through it: give me the exact signup/provisioning page, wait for me to confirm the instance
> exists and I have its IP and an SSH key, then help me get the economy API deployed there using
> `db/economy/deploy.sh` and the pm2 config from PR #35 — tell me each command to paste into an SSH
> session to the VPS itself (that's not a credential-bearing command against my main machine, so
> it's fine for me to type it there), and verify each step by checking the output with me before
> moving on. Once `/v1/health` responds from the public IP, mint a server token for Chernarus using
> the one-liner in `auth.js`'s header comment, and tell me exactly what to paste into the
> `site-chernarus` server config to point the ATM/Market bridges at it.

### G4 — Website deploy + PayPal setup

Blocks: `/fund/` going live (it 404s today — merging code never deploys), and the whole donations
plan's real values.

**Open a session in `aegis-website`, paste:**
> Read `docs/PLAN.md` and `docs/DONATIONS_PLAN.md`'s §3. I need two things done as a click-through:
> (1) authorize the Cloudflare connector if it isn't already, then run `wrangler deploy` yourself
> and confirm `aegisdirective.net/fund/` returns 200, not 404; (2) walk me through creating a
> PayPal Business account and getting a `paypal.me` handle — give me the exact signup path, wait
> for my confirmation, then tell me exactly which `.tbc` placeholders in the repo need that handle
> and the "funded through" date, and open the PR yourself once I give you the values (never ask me
> to edit the file or run git).

### G5 — Discord app creation (admin-bot)

Blocks: admin-bot's live deployment (needs both this and G3's VPS).

**Open a session in `claude-agents`, paste:**
> Read `docs/DEPLOY.md`'s Discord app section. Walk me through creating the Discord application
> and bot: give me the exact discord.com/developers path, wait for my confirmation at each step
> (create app → add bot → copy token → set intents → generate invite link), then tell me exactly
> where the token goes (which repo secret, via `gh secret set --body`, which you run once I paste
> the value here — never ask me to run it). Confirm success by checking the bot can log in once
> it's deployed (this may need to wait on G3's VPS being ready first — check and tell me if so).

### G6 — Confirm the handymansfield goal paragraph

**Open a session in `handymansfield`, paste:**
> Read the drafted goal paragraph in `docs/PLAN.md`. Read it back to me in plain language, ask me
> whether it's right or what to change, and once I confirm, update the file and open the PR
> yourself.

### G7 — jarvis: API key + escalation consent

**Open a session in `jarvis`, paste:**
> Read `docs/PLAN.md` Session 1. I need to paste my `ANTHROPIC_API_KEY` into the local `.env` — tell
> me exactly which file and line, wait for me to confirm I saved it (don't ask me to paste the key
> itself into this chat), then ask me to choose the escalation-consent default (`ask` vs.
> auto-approve) and update the config yourself once I answer. Then run `npm run cli` with the three
> test prompts from the plan and confirm each one works.

### G8 — Locate the `P:\AEGIS_*` mod sources

**Open a session in `aegis-mods`, paste:**
> Read the "Still open" line in MasterThread's `docs/REPOS.md` about `P:\AEGIS_*` sources. No `P:`
> drive is mounted on this machine (core issue #8). Ask me where that source actually lives now
> (external drive, backup, elsewhere), and once I tell you, import it into this repo yourself
> following the existing module layout.

---

## Regular follow-up sessions — ready to run now, no owner input needed

Paste each starter prompt into a fresh Claude Code session opened in the named repo's folder (or a
fresh worktree, per that repo's own session-plan rules).

### aegis-core Session 3 — secret rotation procedure

> Read `docs/PLAN.md` Session 3 only. Turn `docs/ops/SECRET-ROTATION.md` into the complete,
> followable procedure for every credential in issue #5, with an expiry table including the
> 2026-10-03 Anthropic date. Don't perform any rotation — that's G2 above, a separate owner-guided
> session. Open one PR.

### aegis-core Session 4 — vendored-validator drift doc

> Read `docs/PLAN.md` Session 4 only. Write `docs/ops/VENDORED-VALIDATOR.md` from
> `validate-site.yml`'s drift-check block, linked from `docs/README.md`. Open one PR.

### aegis-core Session 5 — cut v0.1.0 (blocked until Sessions 1, 2, 3, 4 are all merged)

> Read `docs/PLAN.md` Session 5 only. Confirm Sessions 1-4 are merged first — if not, stop and say
> so. Tag `main` `v0.1.0`, update `README.md`'s pinned reference, add a pin issue in each consuming
> repo (site-chernarus, services, aegis-mods, aegis-poi, claude-agents). Open one PR here plus the
> pin issues.

### aegis-poi Session 2 — `AEGIS_POI` framework

> Read `docs/PLAN.md` Session 2 only. Build the `AEGIS_POI` framework module per the API research
> already resolved in this plan. Open one PR.

### aegis-mods Session 2 — move `AEGIS_PvPGuard` here

> Read `docs/PLAN.md` Session 2 only. Move `AEGIS_PvPGuard` from `site-chernarus` into
> `mods/AEGIS_PvPGuard/` here with a manifest, README, CHANGELOG. Open the matching PR in
> `site-chernarus` that deletes the old copy and installs this module instead. Open one PR here
> plus that site-chernarus PR.

### claude-agents Session 2 — durable violation-count storage

> Read `docs/PLAN.md` Session 2 only. Add durable violation-count storage for `discord-community`
> per the Open Decisions default (90-day rolling SQLite window). Open one PR.

### site-chernarus Session 1 — reconcile the docs with reality

> Read `docs/PLAN.md` Session 1 only. Correct `README.md`, `STATUS.md`, and the go-live plan to
> describe the verified current state (note: the market catalog audit/restructure this session
> completed — PRs #57 and #59 — should be reflected too, they postdate this plan's own last edit).
> Post the required issue comments per the session brief. Open one PR.

### site-chernarus Session 2 — Phase 2 decision brief (blocked until Session 1 merges — same-repo, one-PR-at-a-time rule)

> Read `docs/PLAN.md` Session 2 only. Confirm Session 1 is merged first — if not, stop and say so.
> Post the four-question Phase 2 decision brief on issue #41 exactly as the session describes (each
> question yes/no with a stated default and the one-line consequence of the alternative). Don't
> answer them yourself. Open one PR for the matching checklist on the issue body.

---

## New: Shockbyte co-manager account (support@aegisdirective.net)

Created 2026-09-13 (after this doc was first written) — Jeremy invited `support@aegisdirective.net`
as a co-manager on the Shockbyte "Yodatech" server, generated its password, accepted the invite.
Purpose, per Jeremy: **general panel admin** (DB creation, restarts, backups) — a standing login so
this doesn't always have to be his personal one.

Credentials are DPAPI-stored at `%APPDATA%\AEGIS\shockbyte-support.clixml` (local-only, this
Windows account, same pattern as every other AEGIS credential). **No automation consumes it yet —
this is storage only.** Concretely: I have no browser-automation tool, so having this credential
stored does not let a Claude session log into the Shockbyte panel and click things itself. Its
value today is (a) letting Jeremy use it manually instead of his personal login, and (b) being
ready if/when someone builds real panel automation (Shockbyte has no API for this, so that would
mean browser automation, e.g. Playwright — not yet started, not currently planned).

One side effect worth knowing: accepting this invite proves the `aegisdirective.net` mailbox
actually receives and works with Shockbyte invite emails. That was the specific reason the loot-sync
plan deferred rung 2 (subuser SFTP) in favor of rung 3 (main-account SFTP, currently configured in
`aegis-core/sync/config.toml`) — see `NEXT_STEPS_LOOT_XML_SYNC_TEST_2026-09-13.md` Phase C. Jeremy
was asked directly whether he wants this account used to revisit that subuser-SFTP path and said no
for now (general panel admin only) — don't re-raise rung 2 without him bringing it up.

## Blocked on something above — don't start yet

- **services E6 (ATM cutover)** — blocked on G3 (VPS) and your own ATM pull from the live server.
- **services E7 (groups/escrow/quest rewards)** — blocked on E6, plus `dayz_community` groups.
- **services dayz_ops O5** — blocked on you providing one `.ADM` log sample.
- **services dayz_ops O7 / event-relay deploy** — blocked on G3 (VPS).
- **aegis-mods Sessions 3-5 (Vehicles/Aircraft/Quest 1033)** — sequential after Session 2 merges;
  Quest 1033 (Session 5) also needs its "module vs. site-only" open decision settled first.
- **claude-agents Sessions 3-9** — Sessions 4 and 5 specifically need real captured output from
  running G-nothing/Session-1's live-confirmation checklist against your actual server (an owner
  step: run the checklist commands live, paste results into a new issue).
- **aegis-poi Sessions 3-6** — sequential after Session 2; Workshop publishing (eventual) needs
  your publisher account, but that's not blocking until a module is actually ready to publish.
- **core Session 5** — see above, blocked on Sessions 1-4 merging (Session 1, core PR #57, is the
  one still open and needing your direct review).
