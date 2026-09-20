# dayz_ops / admin-bot / event-relay: next steps (prepared 2026-09-13)

**Starter prompt** — paste this into a fresh Claude Code conversation (any folder is fine; it
`cd`s where it needs to) to run the walkthrough below:

> Read `<USER_HOME>\GitHub\NEXT_STEPS_OPS_2026-09-13.md` in full, then walk me through it one
> step at a time in order. Do every step marked **[Claude does this]** yourself and tell me the
> result before moving on. Stop and wait for me at every step marked **[You click this]** — tell
> me exactly what to click, and confirm you got what you need before continuing. Skip a step only
> if the file says it's already done.

This assumes `<USER_HOME>\GitHub\aegis-services`, `aegis-core`, and `aegis-site-chernarus` are
the checkouts already on this machine (they are, as of 2026-09-13).

## What's already done (verified 2026-09-13) — nothing to do here

- **`dayz_ops` is live**, password rotated via `db/ops/tools/OpsDbKey.ps1`, `OPS_DB_PASSWORD` set
  as a `services` repo secret, hourly heartbeat/alerts running (`OPS_SCHEDULE_ENABLED=true`,
  confirmed with a green manual run). Full history: services#17.
- The MySQL-password rotation procedure (all three databases) is written up in `aegis-core`
  `docs/ops/SECRET-ROTATION.md` §6 — a future session doing any of the password steps below should
  read that first rather than reinvent it.
- `event-relay`'s code is built and tested (services PR #32), just not deployed. Its own owner
  checklist is services#33 — steps 4-6 below are that checklist, walked through.

## Round 0 — do these in order. Each is quick; none needs you to open a terminal.

### 1. [Claude does this] Confirm nothing has drifted since 2026-09-13

Before touching anything: `gh secret list -R yodatech1988/services`, `gh variable list -R
yodatech1988/services`, and re-run `db/ops/tools/OpsDbKey.ps1 -Run tools/check-connection.js` to
confirm ops is still healthy. If anything differs from "What's already done" above, say so and
stop — don't proceed on stale assumptions.

### 2. [You click this] Rotate the `dayz_economy` and `dayz_community` passwords

Nightly backups (step 3) need both, and both are still the passwords pasted into chat on
2026-09-12 — see `SECRET-ROTATION.md` §6.

- **Economy** has its own detailed walkthrough already: `<USER_HOME>\GitHub\NEXT_STEPS_ECONOMY_2026-09-13.md`,
  "Round 0," item 1. Do that item now (rotate + run `EconomyDbKey.ps1`'s **Apply pending**).
- **Community**: Shockbyte panel → Databases → the `f3ff781782-community` database → change the
  password. Then run `db\community\tools\CommunityDbKey.ps1` from `aegis-services` (double-click,
  or right-click → Run with PowerShell) — paste the new password, click **Test**, then **Save**.
  Leave **Build database** for later; that's a separate decision (services#28), not needed here.

Tell the assisting session once both are done — it needs to set the matching repo secrets next.

### 3. [Claude does this] Turn on nightly encrypted backups

Once step 2 is done, the assisting session should:

- Set `ECON_DB_PASSWORD` and `COMMUNITY_DB_PASSWORD` as `services` repo secrets, read from each
  database's DPAPI store (`OpsDbKey.ps1`'s pattern: `--body $plain`, **never** piped through
  stdin — see `SECRET-ROTATION.md` §6 for why that breaks).
- Generate an `age` key pair (installs `age` if it isn't already on this machine, runs
  `age-keygen`, no typing required from you) and save the private key file to your Desktop as
  `aegis-backup-key.txt`.
- Set the public key (`age1...`) as the `BACKUP_AGE_RECIPIENT` repo variable, and set
  `OPS_BACKUP_ENABLED=true`.
- Manually dispatch `ops-backup.yml` once and confirm it goes green — all three databases dumped,
  restore-tested, and encrypted.

**[You click this]** — the one thing only you can do: move `aegis-backup-key.txt` off this PC to
somewhere safe (a password manager, or a USB drive kept offline) and delete it from the Desktop.
**This file is the only way to ever read a backup.** Losing it doesn't lose the databases (they're
still live), but it does lose every backup taken until a new key pair is generated and used going
forward.

### 4. [You click this] Decide event-relay's event source (services#33, "Session EV3")

Pick one — no wrong answer, just tell the assisting session which:

- **A new small Workshop mod** (like `AEGIS_Economy`'s ATM bridge) posts kill/death/chat lines to
  `event-relay` directly. Lower latency, needs a bit of new Enforce Script.
- **A log-scraper** polls `.ADM`/`.RPT` over SFTP, same pattern as
  `claude-agents/packages/economy-worker/scripts/scrape-economy-logs.mjs`. No new mod, more
  latency, and it's a good excuse to build the ADM-sample tool from step 6 first.

### 5. [You click this] Release the dead-end port reservation

Shockbyte panel → your server → Network/Ports → find the custom allocation `22319` ("claude") →
remove it (or repurpose it for a second RCon allocation or Steam-query port if you want one — just
not a custom listener; Shockbyte has no shell access for that box, so nothing can ever bind to a
custom port there). Nothing depends on this reservation existing.

### 6. [You click this] The VPS — one decision unblocks three things

`dayz_ops` O7 (admin-bot writes its own audit log), `event-relay`'s deploy, and admin-bot itself
all wait on the same VPS. Pick a provider (suggested: DigitalOcean $6/mo or Hetzner ~€4/mo — your
call, either is fine) and create the account + a small droplet yourself; account creation is not
something Claude can do on your behalf. Tell the assisting session the IP/hostname once it exists.

Once it exists, that's a coding session's job (systemd/Docker Compose, not a click-through step):
deploy `admin-bot`, `event-relay`, and (optionally) the economy API there. Not part of this plan —
open a fresh session against `docs/PLAN.md`'s admin-bot Session 3 when the VPS is ready.

### 7. [You click this] Create the Discord bot application

`#admin-agent` channel already exists (private, only you can see it). What's still missing is the
Developer Portal side:

- Go to https://discord.com/developers/applications → **New Application** → name it (e.g. "AEGIS
  Admin") → **Bot** tab → **Add Bot** → **Reset Token** and copy it somewhere safe (you'll paste it
  into the VPS's `.env` as `DISCORD_BOT_TOKEN` once that exists — not needed today).
- **OAuth2 → URL Generator** → scope `bot`, permissions: Send Messages, Read Message History, View
  Channels → open the generated URL → invite the bot to The AEGIS Directive server → confirm it can
  post in `#admin-agent`.
- Right-click `#admin-agent` → **Copy Channel ID** (enable Developer Mode first: User Settings →
  Advanced → Developer Mode) — that's `DISCORD_ADMIN_CHANNEL_ID`.

Nothing needs to be typed into a secret store today; just hold onto the token and channel ID until
the VPS deploy session asks for them.

### 8. [Optional] A Discord webhook for ops alerts

Right now `tools/alerts.js` only prints to the run log (there's nothing to alert on — 0 issues
found so far). If you want alerts to actually land in a channel: pick or create a channel → Edit
Channel → Integrations → Webhooks → **New Webhook** → **Copy Webhook URL**. Give the URL to the
assisting session; it sets `DISCORD_WEBHOOK_OPS` as a repo secret. Skip this if the log is enough
for now — nothing breaks either way.

## After this: the one item still genuinely open

**`.ADM` log sample for dayz_ops Session O5** (player-session import) isn't in this round on
purpose — pulling one safely (over SFTP, with names stripped before it ever leaves this machine)
needs a small tool built first, the same DPAPI pattern as the database key windows. Next session
to open once the above is done: *"Build `db/ops/tools/AdmSample.ps1`: a window that takes the
Shockbyte SFTP password once (Test/Save like the DB key tools), pulls the newest `.ADM` file, and
shows a preview with every Steam64 ID and player name redacted before saving it anywhere. Then use
it to pull one real sample and hand it to the O5 session."* That keeps the SFTP password out of
chat entirely, the same way the DB passwords now are.
