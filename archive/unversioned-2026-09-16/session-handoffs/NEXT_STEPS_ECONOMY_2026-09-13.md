# Economy track: next steps (prepared 2026-09-13)

Continues the `dayz_economy` work from services `docs/PLAN.md`'s E1–E7 track. Each lane below is one
fresh Claude Code conversation opened **in the repo folder or worktree named for the lane**, model
set via `/model`, prompt pasted as-is, conversation closed once the PR is open. Rules come from
MasterThread `standards/sessions/session_plan_standard.md`: one session = one PR, read only the Read
list. Lanes in the same repo are safe to run together only when their file scopes don't overlap
(noted per-lane below); when they do, they're sequenced into separate rounds instead.

## What things look like right now (verified 2026-09-13, ~02:30 UTC)

- **Merged:** services#15 (schema, `0001` live), #24 (key tool + plan track + `docs/DATABASES.md`),
  #25 (HTTP API + ATM types), aegis-mods#4 (`AEGIS_Economy` bridge module, ATM only). No economy-track
  PRs are open in either repo right now — the path is clear.
- **Owner-blocked, not yet done:** the `dayz_economy` password is still the one pasted into chat on
  2026-09-12. Migration `0002` (SCRIP currency, system wallets) and the catalog import are written,
  tested, and waiting for the owner to run them from `db/economy/tools/EconomyDbKey.ps1` (instructions
  on services#19). **`dayz_ops` already completed this exact rotation** on 2026-09-13 — panel → DPAPI
  key window → repo secret → scheduled job confirmed running — so that's the proof the flow works.
- **`AEGIS_Economy` bridges the ATM only** (balance, deposit, withdraw, transfer). Trader purchases
  still use carried banknotes, which is correct per the network design (site-chernarus
  `docs/aegis-network-technical-requirements.md` §3.2: only the *banked* balance is network-wide).
  The API's `/v1/purchase` and `/v1/sale` routes exist and are tested, but nothing in-game calls them
  yet — that's Lane NB below.
- **No VPS exists yet.** The API only runs locally. Lane NA prepares the deploy config so hosting it
  is a single command once a VPS exists (admin-bot's own Session 3 is waiting on the same VPS).
- **Gitleaks false-positive lesson** from getting #25 green: its `generic-api-key` rule matches the
  *substring* key/token/secret/password/credential right before a quoted string, even inside a longer
  identifier, and it scans a PR's **full commit history** — a fix-forward commit doesn't clear an
  earlier commit's finding in the same PR. Documented in services `docs/DATABASES.md`. Any lane
  writing test fixtures with literal call-ids/keys should read that note first.

## Model policy

| Model | Use for |
|---|---|
| **Sonnet 5** | Every lane below. Each has a concrete pattern to follow (an existing file to mirror) and a written Done-when; none is open-ended triage. |

If a lane's *own* research turns out to need deeper DayZ-script verification (as the ATM bridge did
for Expansion's RPC dispatch), spawn a dedicated read-only research sub-agent for that narrow
question rather than switching the whole session to a bigger model.

---

## Round 0: owner only (no Claude). Round 1 can run at the same time.

1. **Rotate the `dayz_economy` password** via `db/economy/tools/EconomyDbKey.ps1` (already open on
   your PC, or relaunch it — see services#19), then click **Apply pending**. This adds the SCRIP
   currency, the system wallets, and imports the catalog switched off. No money moves.
2. **Set `ECON_DB_PASSWORD` as a services repo secret** once rotated, so the nightly backup job
   (ops#26/#31) stops skipping economy.
3. **VPS decision** for hosting the economy API (and admin-bot): default DigitalOcean or Hetzner,
   ~$4–6/mo, per services `docs/PLAN.md`'s admin-bot track. Lane NA's output is ready the moment you
   decide.
4. **Market sign-off** (site-chernarus#6): which catalog is canonical — `main` (what's been imported,
   3,249 items), the `economy/coherence-pass` branch, or a fresh pull from live.
5. **In-game verification**, once a VPS + token exist: deposit, withdraw, and transfer real Scrip at
   an ATM with the bridge enabled, and confirm the script log shows no `UNRESOLVED` lines. This needs
   a live player session; no lane can do it for you.

---

## Round 1: three parallel lanes, no file overlap, all start now

| Lane | Repo / folder | Branch | Output |
|---|---|---|---|
| NA | services, worktree `_wt-services-economy-hosting` | `agent/services/economy-api-hosting` | Deploy config for the economy API (E5 prep) |
| NB | aegis-mods, worktree `_wt-mods-economy-market` | `agent/aegis-mods/economy-market-bridge` | Bridge Market trader purchases to the ledger (E8) |
| ND | services, worktree `_wt-services-economy-grants` | `agent/services/admin-bot-economy-grants` | admin-bot: audited Scrip grant/refund tool |

NA and ND are both in `services` but touch disjoint files (NA: `db/economy/` deploy config and
README; ND: `admin-bot/src/tools/economy.js`, `admin-bot/.env.example`) — safe together. Don't add a
fourth lane to either repo this round.

Worktree setup (run in each repo folder before opening the session):

```
cd <USER_HOME>\GitHub\aegis-services
git fetch origin
git worktree add ..\_wt-services-economy-hosting -b agent/services/economy-api-hosting origin/main
git worktree add ..\_wt-services-economy-grants -b agent/services/admin-bot-economy-grants origin/main

cd <USER_HOME>\GitHub\aegis-mods
git fetch origin
git worktree add ..\_wt-mods-economy-market -b agent/aegis-mods/economy-market-bridge origin/master
```

### NA — economy API hosting prep (Sonnet 5, open in `_wt-services-economy-hosting`)

```
Read only db/economy/README.md, db/economy/src/api/server.js, db/economy/.env.example, and the
admin-bot hosting paragraphs in docs/PLAN.md's admin-bot track (Session 3 and its "Open decisions").
No VPS exists yet; this session prepares the deploy artifacts so standing it up later is one command,
not a from-scratch job. Add: a pm2 ecosystem config (or a systemd unit, your call, pick one and say
why) that starts `node src/api/server.js` with ECON_DB_*, ECON_API_TOKENS and ECON_API_REWARDS from a
.env file it does not commit; a deploy script (deploy.sh or deploy.ps1) that installs deps and
(re)starts the service; and a README "Hosting" section covering TLS (the service binds 127.0.0.1, put
a reverse proxy in front) and how to mint a new per-server token (there's already a one-liner
in auth.js's header comment -- reuse it, don't invent a second way). Verify locally: start the service
under your chosen process manager against a throwaway MySQL, confirm /v1/health responds, stop it
cleanly. Don't touch src/api/*.js, migrations/, or any test file. Branch agent/services/economy-api-hosting,
one PR.
```

### NB — bridge Market trader purchases to the ledger (Sonnet 5, open in `_wt-mods-economy-market`)

```
Read only mods/AEGIS_Economy/README.md and its Scripts/4_World/AEGIS_Economy/ExpansionMarketModule.c
(the existing ATM overrides -- same file you're extending, same modded class), mods/AEGIS_Metrics's
Scripts/4_World/AEGIS_Metrics/ExpansionMarketModule.c (StartTrading/Callback hook, for the exact
signature Expansion uses), and services db/economy/README.md's "Economy API" section for the
/v1/purchase and /v1/sale contracts (POST steam_id+sku+quantity, Idempotency-Key in the body via
/v1/game/* if you hit the same header limitation the ATM bridge did -- read AegisEconomyApi.c's header
comment on that before assuming you need it here; trader purchases are server-authoritative anyway).
Before writing any override, spend one research pass nailing down the exact Callback/PurchaseSuccess/
SellSuccess RPC flow and which classname/price/trader-zone Expansion hands you at that point, the same
way the ATM bridge's own research (cited in its README and commit message) verified the deposit/
withdraw RPCs against the installed Expansion Market version -- don't guess at method signatures.
Add overrides (new methods on the existing modded class, alongside AegisOnDeposit/AegisOnWithdraw, not
replacing them) that post a purchase/sale to the ledger API using AegisEconomyApi.Post, gated by its
own settings flag (default off) so this ships without changing current trader behavior until enabled.
Reuse AegisEconomyApi and AegisEconomySettings as they exist; don't fork a second HTTP client. Boot-test
disabled (0 script errors) and, if you can stand up a local API+MySQL the way the ATM bridge's PR did,
enabled with a dry-run purchase. Branch agent/aegis-mods/economy-market-bridge, one PR, and note in the
PR body whether AEGIS_Economy's README needs a "Scope" update now that it covers more than the ATM.
```

### ND — admin-bot: audited Scrip grant/refund tool (Sonnet 5, open in `_wt-services-economy-grants`)

```
Read only admin-bot/src/tools/moderation.js (the exact pattern to replicate: deps object, audited
writes, no IPs/secrets in details_json), admin-bot/src/audit.js, db/economy/src/ledger.js
(postTransaction and reverseTransaction -- read the whole file, it's short), and db/economy/README.md's
"Posting protocol" and "Security checklist". admin-bot is ESM ("type": "module" in its package.json);
db/economy is CommonJS (no "type" field). Verify early how you import postTransaction/ensureWallet/
reverseTransaction from admin-bot -- Node's CJS-from-ESM interop works for simple `module.exports`
objects but test it before building the rest on an assumption. Add admin-bot/src/tools/economy.js with
two functions following moderation.js's deps-object and auditedAction shape: grant_scrip(deps, {
targetSteamId, amountUnits, reason, caller }) posts an admin_adjustment from the mint system wallet,
and refund_transaction(deps, { transactionId, reason, caller }) calls reverseTransaction. Both write a
dayz_ops.admin_actions row via the existing auditor (begin before acting, close exactly once) with
action_type grant_scrip / refund_transaction, and pass the SAME correlation_id to both the audit row
and the ledger transaction's correlationId, so the two can be joined later (docs/DATABASES.md's stated
convention). deps needs a new getEconomyPool() alongside the existing getCommunityPool()/getOpsPool();
add ECON_DB_* to admin-bot/.env.example, never commit a value. Write tests with fake pools matching
moderation.test.js's style; no live database needed. Branch agent/services/admin-bot-economy-grants,
one PR.
```

---

## Round 2: one lane, after NB merges

NC reuses the same file NB will have just changed (`ExpansionMarketModule.c`); running it before NB
merges risks a conflict for no real benefit (nothing produces `UNRESOLVED` events yet — there's no
live traffic). Low priority; fine to defer past Round 1 entirely if nothing else needs doing.

### NC — structured log for unresolved ATM reconciliation (Sonnet 5, open in a fresh `aegis-mods` worktree off the merged main)

```
Read only mods/AEGIS_Economy/README.md's "How a request flows" section (the UNRESOLVED logging it
already does) and mods/AEGIS_Metrics/README.md's "Output" section (the events.jsonl shape and
$profile:AEGIS/<Module>/ convention -- match it exactly so a future importer can treat both the same
way). Add a small AegisEconomyApi.LogUnresolved(kind, uid, steamId, amountUnits, callId) helper that
writes the existing human-readable log line AND appends one JSON line to
$profile:AEGIS/Economy/events.jsonl (event_type "reconciliation.unresolved", the fields just listed,
occurred_at in UTC ISO8601 -- AegisMetricsTime.NowISO() already does this, reuse it, don't reimplement).
Swap ExpansionMarketModule.c's three UNRESOLVED log call sites (deposit, withdraw, transfer) to call
this helper instead of Log() directly. Don't build the dayz_ops importer side of this -- that's a
separate session coordinated with whoever holds the db/ops track, not yours to start. Boot-test
disabled, 0 errors. Branch agent/aegis-mods/economy-reconciliation-log, one PR.
```

---

## Open questions for later (not lanes yet)

- **Ban enforcement on the economy API.** `db/community`'s `bans` table already has an `economy` ban
  scope, but nothing in `db/economy` checks it. Needs a design decision first: does every economy API
  call check community bans synchronously (adds a cross-database dependency to every request), or
  does banning someone with that scope instead freeze their wallet via a ledger hold posted at ban
  time? Raise with whoever holds the community track before turning this into a lane.
- **E6 cutover** (pull live ATM files, run the import, switch the mod over) stays blocked on Round 0
  item 5, Round 1's NA/NB merging, and E5's VPS. Not ready to plan in detail yet.
- **E7** (party locker → group wallets, P2P escrow, quest rewards) is blocked on `dayz_community`
  groups, which is someone else's track — don't start it from here without checking with them first.

## Deliberately not in this plan

- Hosting the API for real (Round 0 item 3 is the prerequisite; once decided, NA's output makes it a
  single command, but actually running that command against a real VPS is an owner step, not a lane).
- Anything touching `db/ops` directly — that track is actively owned by another session; NC stops at
  producing the log file and explicitly does not build the importer.
- Anything touching `db/community` or its groups/bans — same reason.
- Re-deciding the catalog or currency (Round 0 items 1 and 4 are the owner's calls, already made
  defaults are in force per `db/economy/MIGRATION.md` until overridden).
