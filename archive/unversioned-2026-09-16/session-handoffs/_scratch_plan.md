# Plan: get admin-bot from real-source to live on a VPS, with RCON on solid ground

Follows MasterThread `standards/sessions/session_plan_standard.md`. Do one session per fresh
conversation, opened in this repo's folder.

## Target (settled)

`admin-bot` (Discord admin agent) is real source today — 7 `src/` files, tested — but has never
run outside this checkout. "Done" for this plan: admin-bot deployed on its own VPS, talking to
the live Chernarus server over `packages/be-rcon` (the shared submodule) with the framing
disagreement resolved, and its own "Blocked on Jeremy" doc no longer stale.

## Backlog first

None. `gh pr list` shows no open PRs against `yodatech1988/services` as of 2026-09-12. (Other
local branches — `agent/services/automerge-opt-in`, `rebrand/admin-bot-to-aegis`,
`model/admin-bot-opus-5` — live in other worktrees; check `gh pr list --state all` before
starting a session in case one has an open PR by then, and close/merge it first per Rule 4.)

## Open decisions (default in force until the owner decides)

- **Hosting target (superseded 2026-09-14): OVH VPS, not the Raspberry Pi 5 decided
  2026-09-13.** Owner call — the Pi's zero-recurring-cost appeal lost out to wanting a real
  public-IP box. Still reached over a **Cloudflare Tunnel** (`cloudflared`), not a direct
  port-forward — that half of the 2026-09-13 decision stands regardless of hardware: no ports
  opened on the VPS's public IP, one consistent access pattern across services. Every place this
  plan (and `db/economy`/`db/community`'s hosting notes) says "the Pi," read "the OVH VPS" — same
  one box, different reasoning. **Provisioned 2026-09-13** (`vps-736c134b.vps.ovh.us`) but
  nothing deployed yet; until the "OVH VPS migration" track below lands, these processes run on
  Jeremy's own Windows dev machine under the same `cloudflared` tunnel.
- **`be-rcon` framing disagreement** (`admin-bot`'s extra leading `0xFF` byte before `'B' 'E'`
  vs the shared package/spec): default is to leave `admin-bot/src/tools/beRcon.js`'s outer
  framing untouched until a live hex-dump capture settles it (see `yodatech1988/be-rcon`
  README, "Known disagreement") — don't guess-fix this without evidence.

## Contracts

- `admin-bot` imports `crc32()` from `packages/be-rcon` (git submodule) via a relative path;
  it does not redefine or fork the CRC32 implementation. Any session touching RCON code must
  keep that import intact rather than reverting to a local copy.
- Secrets (`DISCORD_TOKEN`, `RCON_PASSWORD`, Anthropic API key, etc.) stay out of git; every
  new one lands in `admin-bot/.env.example` as a documented key, never a value.

---

## Session 1: refresh admin-bot's own "Blocked on Jeremy" list

- **Read:** `docs/aegis-admin-bot.md` (its "Blocked on Jeremy" section), this plan's Open
  decisions above.
- **Do:** Update the stale claim that RCON setup is blocked — `aegis-site-chernarus`'s sync
  tooling confirmed live RCon connectivity on 2026-09-11. Leave genuinely open items in place:
  Discord Developer Portal login + bot creation/invite, VPS/hosting account creation, and
  rotating to a longer-lived Anthropic API key (current dev key expires 2026-10-03).
- **Out of scope:** actually doing any of the Jeremy-only steps; touching RCON code.
- **Done when:** `docs/aegis-admin-bot.md` no longer lists RCON as blocked, and a PR is merged.
- **Starter prompt:** `Read docs/PLAN.md Session 1 only. Update docs/aegis-admin-bot.md's
  "Blocked on Jeremy" list per the plan, open one PR.`

## Session 2: settle the be-rcon framing disagreement (once a live capture exists)

- **You:** run `admin-bot` against the live server once and capture a raw hex dump of an
  outgoing login packet — this needs live credentials only Jeremy can supply.
- **Read:** `yodatech1988/be-rcon` README's "Known disagreement" section, `admin-bot/src/tools/beRcon.js`.
- **Do:** Compare the captured packet against the BE spec and the shared `be-rcon` framing;
  fix whichever side (admin-bot's extra `0xFF` byte, or the shared package) is wrong, and
  update the README to remove the "Known disagreement" note.
- **Out of scope:** any other RCON protocol change; chat-ai's copy of the same question (that's
  `claude-agents`' plan, not this repo's).
- **Done when:** one implementation is fixed, tests pass, PR merged, disagreement note removed.
- **Starter prompt:** `Read docs/PLAN.md Session 2 only. Resolve the be-rcon framing
  disagreement using the captured packet, open one PR.`

## Session 3: deploy admin-bot to the OVH VPS

- **You:** provision the OVH VPS, the Discord application (Developer Portal login + bot
  creation/invite), and supply the resulting `DISCORD_TOKEN`, host, and RCON credentials as
  deployment secrets. Until the VPS is provisioned, this runs on Jeremy's own Windows dev machine
  instead — same `cloudflared` tunnel, same pm2 process definitions, so nothing changes when the
  VPS takes over.
- **Read:** `admin-bot/README.md`, `admin-bot/.env.example`.
- **Do:** Write (or confirm) a minimal deploy script/README section for running `admin-bot` as
  a long-lived process under pm2, reachable via a `cloudflared` tunnel (no port-forwarding, no
  public home IP), documented in `admin-bot/README.md`.
- **Out of scope:** any Discord command/feature work; RCON protocol changes.
- **Done when:** `admin-bot` runs (on the interim dev-machine host, or the OVH VPS once it
  exists) and `docs/aegis-admin-bot.md` records it as deployed, not just real-source; PR merged.
- **Starter prompt:** `Read docs/PLAN.md Session 3 only. Document/wire up the pm2 + Cloudflare
  Tunnel deploy for admin-bot per the plan, open one PR.`

  This same host (the OVH VPS, or the interim dev machine) is also where `event-relay` (below),
  the economy API (E5), and the community API (`db/community` CS3) deploy — it's the one box on
  the network with real shell access.

---

## Status

**Track parked 2026-09-14 — Discord work is parked per standing decision.** Every remaining
session here needs either a live Discord app/token or a live-server capture; neither is being
pursued right now. Resume once Discord is unparked.

| Session | PR | State |
|---|---|---|
| 1 | | parked (Discord parked 2026-09-14); not started |
| 2 | | parked (Discord parked 2026-09-14); not started (also blocked on live capture) |
| 3 | | parked (Discord parked 2026-09-14). Interim host ran on Jeremy's dev machine 2026-09-13 (community-api first); OVH VPS is now live (V0-V4, services#69/#70) but admin-bot itself is not deployed — still needs the Discord app/token. Superseded by the OVH VPS migration track below (V3 deploys admin-bot) |

---

# Track: OVH VPS migration

Added 2026-09-14. Moves every long-lived AEGIS backend process off Jeremy's Windows dev machine
(and off the abandoned Raspberry Pi plan) onto the OVH VPS. Same session rules as the rest of this
file. It replaces admin-bot Session 3, E5 (economy API hosting), EV2 (event-relay deploy), and the
"move to the VPS once it exists" notes in O6, `db/community` and `claude-agents/docs/DEPLOY.md`.

## What exists today (checked live 2026-09-14)

| Thing | State |
|---|---|
| VPS | `vps-736c134b.vps.ovh.us`, OVH **VPS-1 2027** (2 vCPU, 4 GB RAM, 40 GB SSD), region `os-us-east-va-2`, **Ubuntu 26.04**, running. IPv4 `40.160.90.128`, IPv6 `2604:2dc0:101:200::58b2`. Created 2026-09-13, renews monthly (auto-renew on, next 2026-10-13) |
| OVH API access | `aegis-core/tools/OvhApiKey.ps1` (core#69, open). Key saved in `%APPDATA%\AEGIS\ovh-api.clixml` and working. Scope is GET/POST/PUT/PATCH on `/vps/*`, no DELETE |
| SSH | `~/.ssh/aegis-vps-admin-bot` exists on the PC, but the VPS **refuses it** for `ubuntu`, `root` and `aegis`. The key was never installed. Nothing on the box has been inspected |
| Interim host (PC) | pm2 runs `cloudflared-community-api` (online) and `community-api` (**crash-looping**: 9 restarts, empty logs, launched through `Start-CommunityApi.ps1`). `https://community-api.aegisdirective.net/health` returns **502** |
| Databases | All three MySQL schemas stay on Shockbyte (see "Not moving"). Nothing to copy |

## Target (settled)

The VPS is **cattle, not a pet**. Everything on it can be rebuilt from git plus the PC's DPAPI
credential stores in under an hour, so it needs no paid backup option. "Done" means:

- Every process in the "Moves" table below runs on the VPS under pm2 as a non-root `aegis` user and
  survives a reboot.
- Public HTTP reaches the box only through one Cloudflare Tunnel (`aegis-vps`). The only inbound
  port is SSH, key-only.
- The PC runs only what is PC-only by design: `chat-ai`, `bug-report-agent` and the DPAPI key
  windows.
- A rebuild runbook (`docs/ops/VPS.md`) has been run once end-to-end on the real box.

### Moves

| Service | Repo | Public hostname (via tunnel) | Secrets it needs |
|---|---|---|---|
| `community-api` | services `db/community` | `community-api.aegisdirective.net` (moves from the PC tunnel) | `COMMUNITY_DB_*`, `COMMUNITY_EMAIL_*`, `COMMUNITY_API_*` |
| `economy-api` | services `db/economy` | `economy-api.aegisdirective.net` | `ECON_DB_*`, `ECON_API_TOKENS`, `ECON_API_REWARDS` |
| `admin-bot` | services `admin-bot` | none (Discord gateway is outbound) | `DISCORD_TOKEN`, RCON, SFTP, Anthropic key, `OPS_DB_*` |
| `event-relay` | services `event-relay` | `events.aegisdirective.net` | `RELAY_SHARED_SECRET`, `DISCORD_WEBHOOK_EVENTS`, `ECONOMY_WORKER_*` |
| `discord-community` | claude-agents | none | `DISCORD_BOT_TOKEN`, `CF_*` (D1), `COMMUNITY_DB_*` |
| `chat-monitor` | claude-agents | none | RCON, `DISCORD_WEBHOOK_GAMECHAT` |
| `economy-log-scraper` | claude-agents | none | SFTP |
| `patreon-orchestrator` | claude-agents | `patreon.aegisdirective.net` | `PATREON_WEBHOOK_SECRET`, `CF_*` |

Rough budget: 8 Node processes at ~80–120 MB each plus `cloudflared` is about 1 GB of the 4 GB, so
there's room. Re-check with `pm2 monit` after V5. Upgrade the plan only if it gets past ~75%.

### Not moving (and why)

- **DayZ game server stays on Shockbyte.** VPS-1 has 4 GB RAM. A modded DayZ server wants 8 GB or
  more, and the Linux DayZ server build is still second-class. Moving it would mean a bigger paid
  plan, which is an owner business call and not part of this track.
- **MySQL stays on Shockbyte.** It's already reachable over TLS and costs nothing extra. Hosting it
  on the VPS would put the only copy of the ledger on a box this plan treats as disposable. Revisit
  only if Shockbyte's latency or connection limits actually bite.
- **`chat-ai` and `bug-report-agent` stay on the PC** (`claude-agents/docs/DEPLOY.md`).
  `bug-report-agent` uses the operator's own `gh` login, and bots get no PATs.
- **`economy-worker` stays on Cloudflare** (Worker + D1).
- ~~**GitHub Actions jobs** (ops hourly ingest, backups, economy sync/monitor) stay on Actions for
  now. They're free and already wired. Moving them is optional, in V7.~~ **Reversed 2026-09-14:**
  they are not free any more — Actions billing is failing and no runner is being assigned at all
  (`runner_id=0`, 0 ms, on every recent job in `services` and `core`). Both the scheduled jobs (V7)
  and the CI/PR checks (V9) move to the VPS. Raising a spending limit or adding a payment method is
  explicitly not the alternative.

## Open decisions (default in force until the owner decides)

- **How SSH access gets onto the box.** The VPS was created yesterday and has never been logged
  into by any tooling, so it's almost certainly empty. Default: **rebuild it through the OVH API**
  with Ubuntu 26.04 and the `aegis-vps-admin-bot` public key (`POST /vps/{id}/rebuild`, which
  `OvhApiKey.ps1` can already call). This wipes the disk, so it needs the owner's explicit yes. The
  alternative is Jeremy logging in once with the root password from OVH's email (or the web
  console) and pasting the public key.
- **Secrets on the VPS.** Default: the PC stays the source of truth. A new PC-side
  `tools/PushVpsSecrets.ps1` reads the existing DPAPI stores (`community-db`, `economy-db`,
  `ops-db`, `rcon`, `chernarus-sftp`, `anthropic-admin-key`, and so on) and writes
  `/etc/aegis/<service>.env` over SSH (owner `root:aegis`, mode `0640`). Nobody retypes a password
  and none enters chat. Rotation stays "rotate in the key window, then re-run the push". This is
  the one place `.env` files are accepted: on a single-purpose server, written by a tool.
- **Deploys.** Default: pull-based and PC-triggered. `ssh aegis@vps aegis-deploy <service>` runs
  `git pull` plus the repo's existing `deploy.sh` / `pm2 startOrReload`. Private repos are cloned
  with a **read-only deploy key per repo**, rotated with core's `rotate_deploy_key.py`. No
  GitHub-to-VPS push access, so no static SSH key goes into Actions secrets. Auto-deploy on merge
  can come later through gh-federation.
- **SSH exposure.** Default: port 22 open, key-only, `fail2ban`, root login off. Later (V8), move
  SSH behind the Cloudflare Tunnel with Cloudflare Access and close 22 completely.
- **Runtime.** Default: Node 22 LTS and pm2 (the existing ecosystem files assume pm2). If NodeSource
  doesn't publish for 26.04 yet, use the distro `nodejs` if it's ≥ 20.6 (needed for `--env-file`),
  otherwise `fnm`.

## Contracts

- No service on the VPS listens on a public interface. Everything binds `127.0.0.1` and is
  published only through the tunnel. `ufw` allows only 22/tcp inbound.
- No secret is typed on the VPS or pasted anywhere. Env files are written only by
  `PushVpsSecrets.ps1`, and every key it writes already exists in that service's `.env.example`.
- The PC tunnel and the VPS tunnel never serve the same hostname at the same time. Each cutover is
  one `cloudflared tunnel route dns` change, and it's reversible by pointing back.
- One service moves per session. The old PC process is stopped only after the VPS copy passes its
  smoke check.

---

## Session V0: get in (owner + agent)

- **You:** say yes to the API rebuild (or do the one-time password login instead, see Open
  decisions).
- **Do:** Rebuild via `OvhApiKey.ps1 POST /vps/vps-736c134b.vps.ovh.us/rebuild` with the public key.
  Confirm `ssh -i ~/.ssh/aegis-vps-admin-bot ubuntu@40.160.90.128` works. Record the host key
  fingerprint in `docs/ops/VPS.md`.
- **Done when:** key login works, and the fingerprint is committed.

## Session V1: harden and baseline

- **Read:** this track, `db/economy/deploy.sh`.
- **Do:** Add `ops/vps/bootstrap.sh`, which is idempotent and re-runnable on a fresh rebuild. It:
  - creates the `aegis` user
  - sets up unattended-upgrades, `ufw` (22 only), `fail2ban`, and turns off root and password SSH
  - installs Node 22, pm2 (with `pm2 startup systemd` for `aegis`) and `cloudflared`
  - creates `/etc/aegis/` and `/srv/aegis/`

  Run it on the box. Start `docs/ops/VPS.md` (what's on the box, how to rebuild it).
- **Out of scope:** any AEGIS service.
- **Done when:** a reboot comes back with `ufw` active, pm2 resurrecting (empty), and the PR merged.

## Session V2: tunnel, secrets push, community-api (first cutover)

- **You:** `cloudflared tunnel login` once in a browser on the VPS session this agent opens (the
  Cloudflare MCP connector here needs claude.ai authorization first, so it can't do this for you).
- **Do:**
  - Create tunnel `aegis-vps` with an ingress config in `ops/vps/cloudflared.yml`.
  - Write `tools/PushVpsSecrets.ps1`.
  - Add a read-only deploy key for `services`, clone to `/srv/aegis/services`, deploy
    `community-api`, and smoke-test `curl localhost:<port>/health` on the box.
  - Move the `community-api.aegisdirective.net` DNS route to `aegis-vps`, then stop the PC's
    `community-api` and `cloudflared-community-api` pm2 entries.
  - Fix `db/community/ecosystem.config.js`'s stale Pi comment.
- **Done when:** the public `/health` returns 200 from the VPS (today it's a 502), the PC processes
  are stopped, and the PR is merged.

## Session V3: economy-api + admin-bot

- **Needs:** the admin-bot Discord app/token (`AdminBotKey.ps1`, services#65/#67) for admin-bot.
  `economy-api` can go ahead without it.
- **Do:** Deploy `economy-api` behind `economy-api.aegisdirective.net` and issue the Chernarus
  server token (E5). Deploy `admin-bot`. Check from the VPS that RCON (Shockbyte port 20196, UDP)
  and SFTP reach the game server, since Shockbyte may filter by source IP. Capture the login packet
  hex dump that admin-bot Session 2 is waiting for.
- **Done when:** a `GET /v1/wallets/<test steam64>` works through the tunnel with a bearer token,
  admin-bot answers in Discord, E5 and Session 3 are marked done, and the PR is merged.

## Session V4: event-relay

- **Do:** EV2 as written, on the VPS, behind `events.aegisdirective.net`.
- **Done when:** a manual test event reaches Discord and D1, and the PR is merged.

## Session V5: claude-agents services (PR in `claude-agents`)

- **Do:** Deploy `chat-monitor`, `economy-log-scraper`, `discord-community` and
  `patreon-orchestrator` using `claude-agents/ecosystem.config.cjs`, each only once its own
  credentials exist. (`discord-community`'s GitHub ticket-linking stays off until gh-federation
  replaces the PAT.) Update `claude-agents/docs/DEPLOY.md` to name the OVH VPS and `PushVpsSecrets.ps1`.
- **Done when:** `pm2 status` on the VPS shows every service whose credentials exist as online, and
  the PR is merged.

## Session V6: rebuild drill

- **Do:** Rebuild the VPS from scratch through the API (owner yes again). Then run
  `bootstrap.sh`, `PushVpsSecrets.ps1` and each `aegis-deploy`, timing it, and fix whatever
  `docs/ops/VPS.md` got wrong.
- **Done when:** a full restore takes under an hour, and the runbook matches reality.

## Session V7: move scheduled jobs off Actions

**No longer optional** (2026-09-14): GitHub Actions billing is failing — every recent job on
`services` and `core` was queued with `runner_id=0` and 0 ms, i.e. no runner was ever assigned.
Standing owner decision, made in direct response: anything that costs money to run belongs on the
OVH VPS. Never raise a spending limit or add a payment method as the alternative.

- **Do:** Port all four scheduled workflows — `ops-scheduled` (hourly), `ops-backup` (nightly),
  `economy-catalog-sync` and `economy-monitor` (every 6 h) — to systemd timers on the VPS, running
  from `/srv/aegis/services` and reading `/etc/aegis/scheduled-jobs.env`
  (`tools/PushVpsSecrets.ps1 scheduled-jobs`). Files: `ops/vps/aegis-run-job.sh`,
  `ops/vps/systemd/aegis-*.{service,timer}`, `ops/vps/install-scheduled-timers.sh`. Reduce each
  workflow to `workflow_dispatch`-only, kept as a manual fallback.
- **Out of scope:** deleting the duplicated repo secrets — do that only once the timers have been
  observed running, so the manual fallback still works in the meantime.
- **Done when:** the units are installed, the timers are enabled on the box, and one run of each
  has been observed in `journalctl`.

## Session V9: self-hosted GitHub Actions runner for `core` and `services`

Added 2026-09-14, same root cause as V7. CI checks cannot pass at all while no runner is assigned,
so this unblocks PR checks on the two repos that have them.

- **Read:** `docs/ops/VPS.md` "Self-hosted GitHub Actions runner".
- **Do:** One runner instance per repo (the account is a personal GitHub **User**, not an org, so
  runners register per repository), both as a dedicated non-root, non-`aegis` `gha-runner` user
  with rootless Docker, labelled `self-hosted, vps`, each its own
  `aegis-gha-runner@<repo>.service`. `ops/vps/install-actions-runner.sh` installs one, taking a
  short-lived registration token on stdin (`gh api -X POST
  repos/yodatech1988/<repo>/actions/runners/registration-token`). `core-ci.yml`, `secret-scan.yml`
  and `pr-review.yml` in both repos move to `runs-on: [self-hosted, vps]`; core's
  `claude-review.yml` gains a `runner` input so every *other* caller repo keeps `ubuntu-latest`.
- **Out of scope:** every repo beyond `core` and `services` — each is a separate explicit decision,
  because each needs its own runner registration. **Superseded 2026-09-14 (vps-runners-all):** the
  owner allowlisted 13 private AEGIS repos (`RUNNER_REPOS` in `install-actions-runner.sh`; never
  public repos, never the personal/financial set), all capped together by `aegis-ci.slice`
  (`MemoryHigh=1300M MemoryMax=1600M CPUQuota=150%`, low weights). services' `claude.yml` and the four
  dispatch-only timer fallbacks also move to `[self-hosted, vps]`.
- **Owner decisions:** resource contention on a 2 vCPU / 4 GB box shared with three live pm2
  services (see the PR body and `docs/ops/VPS.md`); and whether persistent runners are acceptable
  versus `--ephemeral` (which would need a GitHub credential on the box that policy says bots don't
  get).
- **Done when:** `gh api repos/yodatech1988/<repo>/actions/runners` lists an online runner for both
  repos and a previously-stuck check re-runs green.

## Session V8 (optional): close port 22

- SSH through the Cloudflare Tunnel with Access (free tier). Then set `ufw` to deny all inbound.

## Session V10: credential/token expiry monitor for everything the VPS depends on

Added 2026-09-14 (P1, Jeremy: "VPS-side credential/token monitoring with alerts at set intervals,
not Claude Code usage"). Filed as a sub-track of the VPS migration rather than folded into V7/V9
because it monitors credentials those sessions introduced (deploy keys, the tunnel credential, the
scheduled-job env file) plus ones that predate them (the admin SSH key, DB passwords) — it's a
cross-cutting concern once the box exists, not a step in getting CI or the timers running.

- **Read:** `docs/ops/VPS.md` "Credential/token expiry monitoring" for the full item list and the
  PC-side/VPS-side split; `jarvis/tools/anthropic-key-rotation/check-expiry.cjs` for the
  age-vs-threshold-vs-alert pattern reused here.
- **Do:** `tools/CredentialCheck.ps1` (PC-side: VPS admin SSH key age, per-repo deploy key age via
  `gh api`, the Cloudflare tunnel credential's PC-side copy, DB password ages via each `*DbKey.ps1`
  store's `SavedAtUtc`, the `backup-age` store once it exists) and
  `ops/vps/aegis-credential-check.sh` + `ops/vps/systemd/aegis-credential-check.{service,timer}` +
  `ops/vps/install-credential-check.sh` (VPS-side: the live Cloudflare tunnel credential file's
  age, `/etc/aegis/*.env` file ages), alerting through the same `notify()`/`DISCORD_WEBHOOK_OPS`
  shape as the scheduled jobs.
- **Depends on / blocked by:** PR #86 (V7/V9, `ops/vps/aegis-run-job.sh`) not being merged yet — the
  VPS-side piece is a standalone script for now with a documented fold-in plan once #86 lands,
  rather than a new case in a file that doesn't exist on `main`.
- **Out of scope:** rotating anything; monitoring the self-hosted GitHub Actions runner
  registration (persistent by design, not an expiring credential — see V9 above).
- **Owner decisions:** whether/how to schedule `tools/CredentialCheck.ps1` (this session doesn't
  add a Windows Task Scheduler entry); creating the `backup-age` DPAPI store once `ops-backup` is
  actually configured; running `install-credential-check.sh` on the box (this session can't SSH).
- **Done when:** both halves exist, are documented, and — once installed by the owner — a
  `journalctl -u aegis-credential-check` shows a real run and `tools\CredentialCheck.ps1` runs
  clean on the PC.

## Track status

| Session | PR | State |
|---|---|---|
| V0 | #69 | done 2026-09-14: rebuilt via OVH API with the key, host key recorded in `docs/ops/VPS.md` |
| V1 | #69 | done: `ops/vps/bootstrap.sh` run, reboot verified (ufw, fail2ban, pm2-aegis active) |
| V2 | #69, #70 | done 2026-09-14: community-api online on the VPS, DNS cutover complete (see `docs/ops/VPS.md`'s 2026-09-14 note — the first attempt silently routed to the old PC tunnel by name; fixed by using the tunnel UUID). **Still open:** stop the PC's `community-api`/`cloudflared-community-api` pm2 entries (blocked from this session by the "interfere with workloads" auto-mode gate; owner action) |
| V3 | #70 (economy-api half) | `economy-api` deployed and live behind the tunnel; admin-bot not yet deployed (needs the Discord app/token, services#65/#67 — Discord work is parked, see admin-bot track above) |
| V4 | #70 | `event-relay` deployed and live behind the tunnel. **Still open:** a manual test event confirmed reaching Discord + D1 (this session only checked the HTTP path answers) |
| V5 | | after V2; per-service credentials |
| V6 | | after V5 |
| V7 | #86 (merged) | **in progress — partly installed.** Units, runner script and installer merged; the four workflows are `workflow_dispatch`-only (no `cron:`). As of 2026-09-14 the timers are installed with `--enable auto`: `aegis-ops-backup.timer` (no `BACKUP_AGE_RECIPIENT`, the PC `backup-age` store does not exist) and `aegis-economy-catalog-sync.timer` (no `/srv/aegis/site-chernarus` clone) are disabled. Each timer must be observed in `journalctl` before the duplicated repo secrets are deleted |
| V8 | | optional |
| V9 | #86, #88, #89, #90 (merged) | **runners registered:** `vps-core` and `vps-services` (2026-09-14). #88/#89 fixed token handling, #90 dropped `RestrictSUIDSGID` (it broke tar extraction on this kernel). Extended to 13 repos in V9b |
| V9b | vps-runners-all (open) | **in review.** Runner allowlist = 13 private repos, shared `aegis-ci.slice`, and services' `claude.yml`/`ops-scheduled`/`ops-backup`/`economy-catalog-sync`/`economy-monitor` on `[self-hosted, vps]`. Owner steps after merge: re-run the installer once for `core` or `services` (installs the slice, moves the existing two instances into it), then one token run per new repo. Timers still off: `ops-backup` lacks `BACKUP_AGE_RECIPIENT` (no `backup-age` store), `economy-catalog-sync` lacks the `/srv/aegis/site-chernarus` clone |
| V10 | #87 (merged) | credential/token expiry monitor built (PC + VPS halves); **not installed** — no SSH access that session, and the VPS half is standalone pending #86 per the note above |

---

# Track: `dayz_ops` database (`db/ops/`)

Added 2026-09-12. A separate track from admin-bot, with the same session rules.

## Target (settled)

`dayz_ops` (Shockbyte schema `716aebea0d-operations`) is the network's operations and audit
record, and it fills itself with no paid infrastructure. "Done" for this track means:

- Every production server heartbeats into `server_instances`.
- Player joins and leaves land in `player_sessions`, and AEGIS_Metrics milestones in `server_events`.
- Every deploy records a `mod_releases` row.
- Every admin-bot action writes `admin_actions` before it acts.
- Scheduled jobs and backups record `job_runs` and `backup_runs`.
- `v_stale_servers` and `v_backup_gaps` are checked by something that pings Discord.

Schema, conventions and retention are in [`db/ops/README.md`](../db/ops/README.md). The index
of all three databases is `docs/DATABASES.md`.

## Open decisions (default in force until the owner decides)

- **Where scheduled ingest runs:** default is a GitHub Actions cron in this repo, hourly. That's
  about 720 of the 2,000 free private-repo minutes a month, so it costs nothing. The inputs are
  repo secrets `OPS_DB_*`, the SFTP password and the RCon password. Move it to the admin-bot VPS
  once that exists (admin-bot Session 3).
- **Retention windows:** default is events 90 days, sessions 365 days, `ip_hash` 30 days, jobs
  90 days, backups 365 days. Admin actions and releases are kept forever.
- **DB backups destination:** default is a nightly `mysqldump` of all three schemas, encrypted
  with `age`, stored as a GitHub Actions artifact (90-day retention, free). Cloudflare R2's free
  10 GB is the fallback if artifacts turn out too small.

## Contracts

- The DayZ mod never holds MySQL credentials. Server-side data reaches `dayz_ops` through files
  the mod already writes (`$profile:AEGIS/Metrics/events.jsonl`, `.ADM`/`.RPT` logs), pulled over
  SFTP. It is never pushed from inside the game.
- Writers use `db/ops/src` helpers, not hand-written SQL, so idempotency keys (`event_id`,
  `source_ref`) are computed one way.
- Importers are re-runnable. The same file range imported twice creates no new rows.
- Column types follow `docs/DATABASES.md`. Schema changes are new migration files only.

## Session O1: schema, runner, tests, docs (services#14)

- **Done:** `0001_dayz_ops_core.sql`, a Node runner shared in shape with `db/economy`, 8 MySQL
  integration tests in CI, and the README.
- **Still open, owner:** OK to rebuild the live schema from `0001` (it is empty; the rebuild drops
  and recreates tables, so an automated session won't do it unasked). Rotate the pasted password.

## Session O2: writer helpers

- **Read:** `db/ops/README.md`, `db/ops/migrations/0001_dayz_ops_core.sql`.
- **Do:** Add `db/ops/src/recorder.js`:
  - `heartbeat`
  - `recordEvent`, which takes a deterministic event id from the caller's source key
  - `openSession` / `closeSession`, with dedupe by `source_ref`
  - `beginAdminAction` / `closeAdminAction`
  - `withJobRun(name, fn)`
  - `recordRelease(release, items)`

  Add integration tests for each.
- **Out of scope:** any importer or network access to the game server.
- **Done when:** the tests pass in CI and a PR is merged.

## Session O3: record mod releases from a site checkout

- **Read:** `aegis-site-chernarus/server/dayz.json`, `aegis-site-chernarus/sync/mods/folder-names.json`,
  `aegis-mods/mods/*/module.json`.
- **Do:** Add `db/ops/tools/record-release.js <site-checkout> --server chernarus-prod`. It builds
  load-ordered items from `dayz.json` `mods` and `serverMods`, maps folders to Workshop ids via
  `folder-names.json`, computes the SHA-256 of the pushed config files, takes the site git HEAD as
  `git_ref`, and writes one `mod_releases` row. `--dry-run` prints the rows instead.
- **Done when:** a dry run against the real site checkout prints the Chernarus release, and a PR
  is merged. The owner (or the O6 job) runs it for real after each deploy.

## Session O4: import AEGIS_Metrics events

- **You:** `@AEGIS_Metrics` live on production (site-chernarus #48).
- **Do:** Add `db/ops/tools/import-metrics.js`. It pulls `profiles/AEGIS/Metrics/events.jsonl`
  over SFTP, remembers a byte offset per file in `job_runs.details_json`, and writes
  `server_events` with `event_type` `metrics.<milestone>` and a UUID derived from file+offset.
  It runs inside `withJobRun`.
- **Done when:** a re-run imports 0 new rows, and a PR is merged.

## Session O5: player sessions from server logs

- **You:** confirm where `.ADM` files are written (the server root per admin-bot's
  `sftpFiles.js`, or `profiles/` per the sync tool), and share one real `.ADM` file with player
  names removed.
- **Do:** Write a parser for connect and disconnect lines, plus tests built from that sample.
  Import into `player_sessions` with `source_ref = <file>:<line>`, and close sessions left open by
  a restart as `unknown`.

## Session O6: scheduled ingest and alerts

- **Built** (no RCon needed: the heartbeat uses the public Steam query port). What's left for the
  owner is in #17. The original plan text follows.
- **You:** set the repo secrets `OPS_DB_PASSWORD`, `SFTP_PASSWORD`, `RCON_PASSWORD` and
  `DISCORD_WEBHOOK_OPS`.
- **Do:** Add an hourly workflow that does three things. It heartbeats from RCon `players`, runs
  O4 and O5, and posts to Discord when `v_stale_servers` or `v_backup_gaps` returns rows. Add a
  nightly workflow that dumps all three schemas, encrypts them and records `backup_runs`.

## Session O7: admin-bot writes the audit log

- **You:** admin-bot deployed (admin-bot Session 3).
- **Do:** Wrap every mutating admin-bot tool in `beginAdminAction` / `closeAdminAction`. Refuse
  to act if the audit insert fails.

## Track status

| Session | PR | State |
|---|---|---|
| O1 | #14 | merged; live rebuilt from 0001+0002 on 2026-09-13 (#17) |
| O2 | #18 | merged |
| O3 | #20 | merged (dry run against site main: 21 mods, 173 config files, 0 problems) |
| O4 | #21 | merged; first live run waits on site-chernarus #48 (Metrics upload) + #17 |
| O5 | | blocked on owner: ADM location + sample |
| O6 | #26 | merged; workflows off until owner sets repo variables + secrets (#17) |
| O7 | | blocked on admin-bot deploy |

---

# Track: `dayz_economy` database (`db/economy/`)

Added 2026-09-12. A separate track with the same session rules. Tracker issue: #19.

## Target (settled)

`dayz_economy` (Shockbyte schema `a54c4d0b96-economy`) becomes the single record of virtual value
on the network: balances, purchases, rewards, vehicle rights. "Done" for this track means:

- Every Scrip balance lives in `wallets`, and every change is a ledger transaction.
- The DayZ server reads and changes balances only through the economy API, never through Expansion
  ATM files.
- Shop purchases write `shop_orders`, and the mod reports delivery back.
- Once-per-period rewards go through `reward_claims`.
- `audit_*` views are checked on a schedule and alert on any row.

Schema, posting rules and security are in [`db/economy/README.md`](../db/economy/README.md). What
holds value today and the decisions in force are in [`db/economy/MIGRATION.md`](../db/economy/MIGRATION.md).

## Open decisions (default in force until the owner decides)

- **Canonical catalog:** default site-chernarus `main`, until market sign-off (site-chernarus #6)
  picks `main`, `economy/coherence-pass` or a fresh pull from live.
- **API host:** default is one small HTTP API process on the admin-bot VPS, shared with
  `dayz_community`'s plan (its step A1). It holds the only copy of each DB password in production.
  Until the VPS exists, the only credential store is the owner's DPAPI key file on this PC.
- **Game-server auth to the API:** default is a per-server bearer token over HTTPS, stored in the
  server profile (not the mission folder, which syncs to git), rotated like the RCon password.
  DayZ script has no HMAC primitive, so request signing isn't an option.
- **Expansion ATM stays authoritative in game until the cutover (E6).** No dual-write period.

## Contracts

- The DayZ mod never holds MySQL credentials; it calls the API.
- Money only moves through `db/economy/src/ledger.js`. Every API mutation takes a caller
  idempotency key.
- Importers are re-runnable, and the ATM import is one-time per player UID by design.
- Agents never type or store a DB password. The owner enters it in `tools/EconomyDbKey.ps1`, and
  live writes run from that window or its `-Run` mode.
- Column types follow `docs/DATABASES.md`. Schema changes are new migration files only.

## Session E1: schema, ledger API, importers, migration plan (services#15)

- **Done:** `0001` (applied live), `0002`, `ledger.js`, catalog and ATM importers, `MIGRATION.md`,
  17 MySQL integration tests in CI.

## Session E2: key tool and read-only check

- **Done:** `tools/EconomyDbKey.ps1` (DPAPI key store, Test / Save / Apply pending) and `src/check.js`.
- **Still open, owner:** rotate the password in the Shockbyte panel, enter it in the window, and
  click Apply pending (runs M2 + M3). Post the check output on #19.

## Session E3: economy API (no deploy)

- **Read:** `db/economy/README.md` (Posting protocol), `src/ledger.js`,
  `docs/community-db/MIGRATION-PLAN.md` step A1.
- **Do:** Add `api/` with a Node HTTP server (no framework, or a single small dependency) exposing:
  - `GET /v1/wallets/:steam64`
  - `POST /v1/purchase` (orders + ledger in one transaction)
  - `POST /v1/sale`
  - `POST /v1/reward/claim`
  - `POST /v1/transfer`
  - `POST /v1/orders/:id/delivery`

  Every POST requires `Idempotency-Key`. Add bearer-token auth per server, JSON schema validation,
  and integration tests against MySQL.
- **Out of scope:** hosting, TLS termination, the DayZ side.
- **Done when:** the tests pass in CI and a PR is merged.

## Session E4: DayZ bridge module (aegis-mods)

- **Read:** the E3 API contract; Expansion Market's ATM and trader script hooks (the same hook
  points `AEGIS_Metrics` uses).
- **Do:** Add the Workshop module `AEGIS_Economy`. It uses RestApi calls for balance, buy, sell and
  reward, and a retry queue that reuses the same idempotency key. Behind a settings flag, it
  replaces Expansion ATM deposit and withdraw.
- **Done when:** it's boot-tested on the local dev server against a local API with a local MySQL.
- **Done (aegis-mods#4, merged):** `AEGIS_Economy` bridges ATM balance/deposit/withdraw/transfer
  only — trader purchases stay carried-cash, per tech-requirements §3.2. Found and fixed along the
  way: stock Expansion never rejects `amount <= 0` server-side in any of the three RPC handlers,
  only the client menu does. The party locker is refused outright while bridged rather than split
  across a local file and the ledger. A lost API response is logged `UNRESOLVED <key>` for manual
  reconciliation; a disconnect mid-flight posts a compensating `:undo` transaction on the same key.
  **Still open:** a live in-game deposit/withdraw/transfer test (needs a player session).

## Session E5: API hosting

- **You:** the VPS (admin-bot Session 3).
- **Do:** Deploy the E3 API next to admin-bot with the DB passwords in its env, add HTTPS, and issue
  a server token for Chernarus.
- **Prep done, deploy still open (E5-prep lane, `GitHub\NEXT_STEPS_ECONOMY_2026-09-13.md` lane NA):**
  a pm2/systemd config and deploy script so standing it up is one command once the VPS exists.

## Session E6: cutover (MIGRATION.md M4 + M7)

- **You:** pull `profiles/ExpansionMod/ATM/` read-only, stop the server at the cutover time, and
  run the ATM import from the key tool's `-Run` mode.
- **Do:** Dry-run the import, reconcile totals, apply, check the audit views, enable the E4 flag,
  and switch the catalog listings on.

## Session E7: groups, P2P escrow, quest rewards (MIGRATION.md M8)

- **Do:** Move the party locker into `group` wallets (needs `dayz_community.player_groups`), P2P
  listing fees and escrow into `system/escrow` holds, and quest money rewards into `claimReward`.

## Session E8: bridge Market trader purchases (aegis-mods)

- **Do:** Extend `AEGIS_Economy` (not a new module) to bridge Expansion Market trader buy/sell to
  `/v1/purchase` and `/v1/sale`, the same override pattern as E4's ATM bridge, behind its own
  settings flag. Full starter prompt: `GitHub\NEXT_STEPS_ECONOMY_2026-09-13.md` lane NB.
- **Done (aegis-mods#5 + services#40, merged).** Still open: a live in-game purchase/sale test.

## Session E9: structured log for unresolved ATM reconciliation (aegis-mods)

- **Do:** `AEGIS_Economy` already logs `UNRESOLVED <key>` when an API response never arrives; also
  write it to `$profile:AEGIS/Economy/events.jsonl` in `AEGIS_Metrics`'s events-file shape, so a
  future `dayz_ops` importer (not built here — coordinate with whoever holds that track) can read
  it. Low priority until there's live traffic. Sequenced after E8 merges (same file). Full starter
  prompt: `GitHub\NEXT_STEPS_ECONOMY_2026-09-13.md` lane NC.
- **Done (aegis-mods#8, merged).** The `dayz_ops` importer that reads it is not built.

## Session: admin-bot Scrip grant/refund tool (services, not numbered — cross-cuts E3/dayz_ops)

- **Do:** `admin-bot/src/tools/economy.js`, following `moderation.js`'s audited-tool pattern:
  `grant_scrip` and `refund_transaction`, each writing a `dayz_ops.admin_actions` row whose
  `correlation_id` matches the ledger transaction's, so the two can be joined. Full starter prompt:
  `GitHub\NEXT_STEPS_ECONOMY_2026-09-13.md` lane ND.

## Track status

| Session | PR | State |
|---|---|---|
| E1 | #15 | merged; `0001` live, M2/M3 live apply waits on owner (E2 tool) |
| E2 | #24 | merged |
| E3 | #25 | merged; adds `0003` (ATM types, `system/physical-cash`) and `/v1/game/*` body-auth routes (DayZ `RestContext` can't set headers) so the bridge module could call it |
| E4 | aegis-mods#4 | merged; `AEGIS_Economy` boot-tested disabled (0 errors) and with the bridge enabled against a local API+MySQL (health probe round-tripped); not yet tested against a live deposit/withdraw/transfer |
| E5 | #35 | merged; pm2 deploy artifacts + Hosting docs ready. No longer blocked on a VPS decision — `economy-api` is deployed and live on the OVH VPS (#69/#70). What's left: issue the Chernarus server token |
| E6 | | E4 done; blocked on E5 (hosting) and the owner's ATM pull. Does not need E8 (that's additive, market-side) |
| E7 | | after E6; party locker also needs community groups |
| E8 | aegis-mods#5 | merged; trade recording behind its own `BridgeTrades` flag (off by default), boot-tested with both flags on. Found on review that `/v1/game/purchase`/`/v1/game/sale` didn't exist yet, fixed in E8-fix below. Not yet tested against a live purchase/sale |
| E8-fix | #40 | merged; adds `purchase`/`sale` to `GAME_ROUTES` in `db/economy/src/api/server.js` so E8's Market bridge can reach the existing `/v1/purchase`/`/v1/sale` handlers; docker-gated integration suite 30/30 |
| E9 | aegis-mods#8 | merged; `AegisEconomyApi.LogUnresolved` writes the `UNRESOLVED` line plus a JSON line to `$profile:AEGIS/Economy/events.jsonl`. `AEGIS_Economy` now hard-depends on `AEGIS_Metrics`. Boot-tested; not triggered against a live timeout. The `dayz_ops` importer for it is not built (db/ops track) |
| admin grants | services#37 | merged |

---

# Track: `event-relay` (game event webhook)

Added 2026-09-12. A separate track with the same session rules. Tracker issue: #33.

## Target (settled)

Kill/death and chat events reach Discord (and the `dayz_ops`/economy event log) without anyone
watching the server manually. "Done" for this track means a DayZ-side source pushes events to
`event-relay`, which forwards them to Discord and to `economy-worker`'s `/events` D1 log.

## Origin — why this exists, and the dead end that shaped it

The owner reserved a custom port on the DayZ server's Shockbyte panel (`22319`, tcp/udp, named
"claude") meaning to use it for exactly this. **That port cannot work as planned**: Shockbyte is
panel + SFTP only, with no shell access (confirmed by the owner 2026-09-12, matching
`docs/aegis-admin-bot.md`). A custom port there only routes traffic *to* the game server
container; the only process running in that container is DayZ itself, so nothing we write can
ever bind a listener to it. The reservation is a dead end and should be released or repurposed
for something Shockbyte-native (a second RCON allocation, an alternate Steam-query port) — not
retried for this or any other custom service.

## Open decisions (default in force until the owner decides)

- **DayZ-side event source:** not yet built. Default is a small mod using the engine's `RestApi`
  the same way `AEGIS_Economy` (E4) calls its API, POSTing kill/death/chat lines to the relay.
  The alternative — a log-scraper polling `.ADM`/`.RPT` over SFTP, the same pattern as
  `economy-worker/scripts/scrape-economy-logs.mjs` — avoids a new mod but adds latency and needs
  somewhere off-box to run (the VPS, once it exists). Whichever wins, it posts to `POST /events`
  with `Authorization: Bearer <RELAY_SHARED_SECRET>`; see `event-relay/README.md`.
- **Hosting:** the admin-bot VPS (admin-bot Session 3), once it exists. No other box on the
  network has shell access.

## Contracts

- `event-relay` never touches MySQL directly — it forwards to `economy-worker`'s `/events`
  endpoint, which is the only thing that writes to D1. This keeps `dayz_ops`'s "never pushed
  from inside the game" contract intact even though this track *is* a push path: the push lands
  on the relay (a boundary we control, with its own shared-secret auth), not directly on a
  database.
- Discord and economy-worker forwarding never fail or block the inbound request — see
  `event-relay/src/discord.js` and `src/forward.js`. A downstream hiccup shouldn't make the
  DayZ-side source retry-storm the relay.

## Session EV1: the relay itself (this session)

- **Done:** `event-relay/` — plain Node/ESM HTTP server (`node:test`, no framework, matching
  `economy-worker`/`admin-bot` conventions), `POST /events` with bearer-secret auth, forwards to
  a Discord webhook and to `economy-worker`'s `/events` endpoint. 14 passing tests. Not deployed
  anywhere — no VPS exists yet to run it on.
- **Still open, owner:** decide the DayZ-side event source (see Open decisions above); release
  or repurpose the dead `22319` reservation on the Shockbyte panel.

## Session EV2: deploy to the VPS

- **You:** the VPS exists (admin-bot Session 3).
- **Do:** Run `event-relay` as a long-lived process there (same pattern as admin-bot's Session 3
  deploy), with `RELAY_SHARED_SECRET`, `DISCORD_WEBHOOK_EVENTS`, `ECONOMY_WORKER_URL`, and
  `ECONOMY_WORKER_SHARED_SECRET` as deployment secrets.
- **Done when:** a manually-posted test event reaches Discord and the D1 event log; PR merged.

## Session EV3: DayZ-side event source

- **You:** pick mod vs. log-scraper (Open decisions above) if not already decided.
- **Do:** Build whichever was picked, posting real kill/death/chat events to `event-relay`.
- **Out of scope:** anything not kill/death/chat — other event types can reuse this path later,
  but scope this session to what's actually observable today.
- **Done when:** a live kill or chat message in-game shows up in Discord within a few seconds;
  PR merged.

## Track status

| Session | PR | State |
|---|---|---|
| EV1 | #32 | merged |
| EV2 | (via VPS track V4, #69/#70) | deployed and live behind the tunnel on the OVH VPS — found already running ahead of docs, confirmed via #70. Not this track's own PR. **Still open:** EV2's own done-criterion, a manual test event confirmed reaching Discord + D1, is unmet (only the HTTP path has been checked) |
| EV3 | | blocked on owner: pick mod vs. log-scraper |

---

# Track: `gateway` (personal/financial/game-server routing gate)

Added 2026-09-14, owner request. Same session rules as above (one worktree, one PR per session).

## Goal (owner request, 2026-09-14)

Every bot-initiated action that could touch something personal, financial, or the live game
server must pass through one chokepoint that classifies it and, for those three categories,
**holds it for the owner instead of letting it reach GitHub or the server** — with no PC-side
routing decision and no per-session setup from the owner. Explicitly: "a black box where all
requests route through for personal, financial, game server... processed before they go to
GitHub... run on the VPS not my PC... I don't need to be in the loop on this."

This is **additive**, not a replacement for the existing gates — it never loosens
`OWNER_ONLY_REPOS`/`SENSITIVE_WORDS` in `aegis-core/.github/workflows/claude-review.yml` (those
still apply at merge time as a second layer) or `gh-federation`'s OIDC pull/ack (that queue still
only ever contains tasks this gateway already approved for "general"). It closes two real gaps:
(1) `gh-federation`'s `POST /tasks` enqueue has no category logic at all today — anything any bot
enqueues becomes pullable; (2) `admin-bot`'s RCON/economy/moderation tool calls never go through
GitHub at all, so the existing PR-time gate can't see them — a bot with a live Discord role today
could push an economy change or run an RCON command with no hold, only a role check.

## Target (settled)

- One new VPS service, `gateway/` (plain Node/ESM, `node:test`, matching `event-relay`'s
  no-framework convention) exposing `POST /route`.
- **Callers** (each with its own shared secret, same per-caller-secret pattern as
  `gh-federation`'s `ENQUEUE_SECRETS`): `discord-community`, `bug-report-agent`, `admin-bot`
  (its RCON/economy/moderation tool layer), `economy-worker`'s automation. A caller sends
  `{ caller, action: { type, target, payload } }` instead of acting directly or enqueuing
  directly.
- **Classification** (`gateway/src/classify.js`), category = `personal | financial | game-server
  | general`, in that priority order (first match wins):
  - `target` (a repo, or for RCON a server/command name) matches `OWNER_ONLY_REPOS` → `personal`
    or `financial` per which list entry (see Contracts — list is vendored from `aegis-core`, not
    re-typed by hand).
  - `payload` text matches the `SENSITIVE_WORDS` regex (same source) → `financial`.
  - `action.type` is `rcon-command`, or `target` names an `admin-bot` tool in
    `{rcon, battleye, beRcon, economy, moderation}` → `game-server`.
  - else → `general`.
- **Routing:**
  - `general` → forwarded immediately to the real destination (`gh-federation`'s `POST /tasks`,
    or back to the calling bot as an "approved, proceed" response for a direct action like RCON).
  - `personal` / `financial` / `game-server` → **not forwarded.** Written to a `held_actions`
    row (SQLite, `gateway/data/gateway.db` — this service is small enough not to need MySQL), and
    the owner is notified (Session G2). Only an explicit owner approval releases it; nothing
    times out into auto-approval.
- **Runs on the VPS**, 127.0.0.1-bound behind the existing `aegis-vps` Cloudflare tunnel (new
  hostname `gateway.aegisdirective.net`), pm2-managed under user `aegis`, secrets at
  `/etc/aegis/gateway.env` via `PushVpsSecrets.ps1` — same pattern as `community-api`/
  `economy-api`/`event-relay` (see `docs/ops/VPS.md`, PR #71).

## Open decisions (default in force until the owner decides)

- **Approval channel:** default is Discord, reusing `admin-bot`'s existing bot connection and
  `#admin-agent` channel rather than standing up new bot infra — the gateway posts a held-action
  summary there, and a `!approve <id>` / `!deny <id>` command (new `admin-bot` tool, Session G2)
  releases or discards it. **Gated to the owner's own Discord user ID specifically**, not
  `admin-bot`'s general role table — a held personal/financial/game-server action is exactly the
  case where "has an admin role" isn't enough authority. Revisit only if the owner wants a second
  approver.
- **Category source of truth:** default is to vendor `OWNER_ONLY_REPOS` and `SENSITIVE_WORDS`
  from `aegis-core/.github/claude-review.md` as a small JSON/JS config the gateway imports,
  updated by hand when that list changes (it changes rarely and only the owner edits it). A
  live cross-repo fetch was considered and rejected — it would need `gateway` to hold a GitHub
  read credential across repos, the exact standing-credential shape `gh-federation` exists to
  avoid.
- **`held_actions` retention:** default keep forever (it's an audit log, small volume) — same
  reasoning as `dayz_ops.admin_actions`.

## Contracts

- **`held_actions` row:** `{ id, caller, category, action_type, target, payload (JSON text),
  status ('held'|'approved'|'denied'), created_at, decided_at, decided_by }`.
- **Nothing this service classifies as personal/financial/game-server can reach GitHub or the
  live server without a row in this table flipping to `approved` first.** No code path skips
  the table, including retries and re-enqueues.
- **The category lists are a straight copy of `aegis-core`'s, not a reinterpretation** — if the
  two ever disagree, that's a bug in this service, not an intentional narrower/wider gate.
- **Every session in this track gets its own worktree and its own PR**, per `session_plan_standard`
  rule 9.

---

## Session G1: classification + hold engine (no deploy, no Discord yet)

- **Read:** this track's Target/Contracts; `aegis-core/.github/workflows/claude-review.yml`'s
  `OWNER_ONLY_REPOS` list and `SENSITIVE_WORDS` regex (copy exactly); `event-relay/src/index.js`
  for this repo's no-framework HTTP server convention; `admin-bot/src/auth/permissions.js` for
  the existing tool-name list (`rcon`, `battleye`, `beRcon`, `economy`, `moderation`).
- **Do:** `gateway/` — `src/classify.js` (pure function, the priority-ordered rules above),
  `src/db.js` (SQLite `held_actions` table), `src/index.js` (`POST /route`: per-caller shared
  secret auth via `ROUTE_CALLER_SECRETS`, classify, either forward-stub or insert a held row and
  return `{ status: "held", id }`). Forwarding to `gh-federation`'s real `POST /tasks` and to
  `admin-bot`'s "proceed" response are both stubbed behind a small interface (Session G3 wires
  the real calls once callers are ready).
- **Out of scope:** Discord approval (Session G2), any real caller integration or VPS deploy
  (Session G3).
- **Done when:** tests cover one case per category (a `jarvis` target → `personal`, a payload
  containing `stripe` → `financial`, `action.type: "rcon-command"` → `game-server`, anything
  else → `general`), a held row persists and is queryable, and a `general` action never touches
  the `held_actions` table.
- **Model:** Opus 5 (this is the access-control surface — same reasoning as `gh-federation`
  Sessions 1-2).
- **Starter prompt:** `Read docs/PLAN.md, Track: gateway, Session G1 only. Build gateway/'s
  classify+hold engine, open one PR.`

## Session G2: Discord approve/deny

- **Read:** Session G1's `gateway/src/db.js`; `admin-bot/src/tools/discordBroadcast.js` and
  `src/auth/permissions.js` for the existing Discord-posting and permission-check conventions.
- **Do:** a new `admin-bot` tool that (a) on a new held row (polled or webhook-pushed from
  `gateway`), posts a summary to `#admin-agent`; (b) adds `!approve <id>` / `!deny <id>`,
  checked against the **owner's own Discord user ID** (a new, narrower check than the existing
  role table — reuse `permissions.js`'s shape but do not reuse the general-admin role list for
  this), calling back to `gateway` to flip the row's status.
- **Out of scope:** real caller integration (Session G3).
- **Done when:** a manually-inserted held row produces a Discord message, and `!approve`/`!deny`
  from the owner's account (and only that account) flips its status; a non-owner admin's
  `!approve` is rejected and logged.
- **Starter prompt:** `Read docs/PLAN.md, Track: gateway, Session G2 only. Wire Discord
  approve/deny, open one PR.`

## Session G3: deploy + wire real callers

- **You:** VPS deploy (pm2 ecosystem file + `/etc/aegis/gateway.env` via `PushVpsSecrets.ps1` +
  `cloudflared tunnel route dns --overwrite-dns aegis-vps gateway.aegisdirective.net`) — same
  "merges don't deploy, a human runs it" pattern as every other VPS service and as
  `gh-federation`'s Worker deploy.
- **Read:** Sessions G1-G2; `gh-federation`'s `POST /tasks` contract; `admin-bot`'s tool-call
  entry point for RCON/economy/moderation.
- **Do:** point `discord-community`/`bug-report-agent`'s enqueue calls and `admin-bot`'s
  RCON/economy/moderation tool calls at `gateway`'s `POST /route` instead of their current
  direct paths; `gateway` forwards `general`-category results on to `gh-federation`'s real
  `POST /tasks` or back to `admin-bot` as "proceed."
- **Done when:** a real financial-flagged and a real game-server-flagged action both stop at a
  held row and reach the owner in Discord instead of executing; a general action still completes
  end-to-end with no owner touch.
- **Starter prompt:** `Read docs/PLAN.md, Track: gateway, Session G3 only. Wire real callers
  through gateway, open one PR.`

## Status as of 2026-09-14 (end of day)

All code is merged. Session G2 (Discord approve/deny UI) was skipped by owner request in favor
of a CLI stopgap (`gateway/tools/review-held.js` / `decide-held.js`, run over SSH once deployed).

`gh-federation`'s Cloudflare Worker is separately now **live**
(https://gh-federation.<account>.workers.dev, `gh-federation`#6, pull+ack verified
end-to-end) — built by a parallel session, not part of this track, but this track's `forward.js`
depends on it and is now wired to point at it (#83).

**Three owner-only steps are all that's left before any of this actually does anything live:**

1. Grant the Bash permission rule this session asked for (`~/.claude/settings.json`,
   `permissions.allow`: `"Bash(ssh*aegis@40.160.90.128*)"` and `"Bash(*wrangler*)"`) — SSH to the
   VPS and `wrangler` deploy/secret actions are both hard-blocked by Claude Code's own auto-mode
   classifier (`[Production Reads]` / `[Production Deploy]`) until this is saved. A session
   cannot grant this to itself (`[Self-Modification]`), so it has to be a manual file edit.
2. Once granted, run `gh-federation`'s `tools/PushEnqueueSecrets.ps1` (`gh-federation`#7) — adds
   `"gateway"` as a caller in the live Worker's `ENQUEUE_SECRETS`, rebuilt from DPAPI so the
   existing `"selftest"` caller isn't lost.
3. Then `services`' `tools\PushVpsSecrets.ps1 gateway`, followed by
   `tools\PushVpsSecrets.ps1 admin-bot` (picks up its new `GATEWAY_URL`/`GATEWAY_CALLER_SECRET`),
   then `cloudflared tunnel route dns --overwrite-dns aegis-vps gateway.aegisdirective.net` (the
   ingress entry is already in `ops/vps/cloudflared.yml`, just needs copying to
   `/etc/cloudflared/config.yml` on the VPS + a `cloudflared` restart).

All three secrets involved (`ROUTE_CALLER_SECRETS`'s four callers, `GH_FEDERATION_ENQUEUE_SECRET`)
are already generated and DPAPI-stored at `%APPDATA%\AEGIS\gateway-secrets.clixml` — nothing left
to type in, just to run.

## Track status

| Session | PR | State |
|---|---|---|
| G1 (classify + hold engine) | [#73](https://github.com/yodatech1988/services/pull/73) | merged |
| G2 (Discord approve/deny) | | skipped by owner request 2026-09-14, replaced by a CLI stopgap (shipped as part of G3) |
| G3 (deploy prep + admin-bot wiring) | [#77](https://github.com/yodatech1988/services/pull/77) | merged |
| Port-collision fix (8791→8792) | [#79](https://github.com/yodatech1988/services/pull/79) | merged |
| VPS rollout tooling (`PushVpsSecrets.ps1`/`aegis-start.sh`) | [#81](https://github.com/yodatech1988/services/pull/81) | merged |
| Wire up the now-live gh-federation Worker | [#83](https://github.com/yodatech1988/services/pull/83) | merged |
| Owner: VPS deploy + DNS route | | not started — needs the permission grant above first |

---

# Track: `stats-api` (public network-status snapshot)

Added 2026-09-14. A separate track with the same session rules. Feeds
`aegis-website/docs/design/network-status-mockup.html` (design draft, PR #22) real numbers.
Tracker issue: not yet opened — open one alongside NS1.

## Target (settled)

aegisdirective.net's network-status page reads one public, cached JSON endpoint instead of a
per-page-load database query. "Done" for this track means: a small read-only HTTP service
snapshots `dayz_ops`, `dayz_economy`, and the community DB on an interval, serves the aggregate
from memory, and the website fetches it client-side. No public route ever opens a MySQL
connection per request, and no player-identifying field (steam64, Discord ID) leaves the service.

## Origin — why this is its own service, not an addition to `db/economy`'s or `db/community`'s API

Those two APIs are mutation-focused and bearer-token gated for the game server and staff tools
(`POST /v1/purchase`, admin actions, etc.) — the wrong trust boundary for a route the public
website calls with no auth. `dayz_ops` has no HTTP API at all today, only importers. A dedicated
`stats-api` keeps "public, read-only, cached" as its entire contract, rather than threading that
exception through services that are otherwise "authenticated, mutating, live."

## Open decisions (default in force until the owner decides)

- **Not a Cloudflare Worker.** Every other service in this repo (`admin-bot`, `event-relay`,
  `db/economy/src/api`, `db/community/src/api`) is a plain Node/ESM HTTP server run under pm2 on
  the OVH VPS, reached through the same `cloudflared` Tunnel — no `wrangler.jsonc`/Hyperdrive
  exists anywhere in this repo. Default: `stats-api` matches that pattern exactly rather than
  introducing Workers+Hyperdrive as a one-off. `aegis-website` itself stays a static
  Worker (assets only); the page fetches `stats-api`'s public endpoint client-side with CORS
  locked to `aegisdirective.net`, so nothing about the website's own deploy changes.
- **DB credentials: reuse the existing per-schema admin users, not a new scoped one.**
  `docs/DATABASES.md` ("Password handling") is explicit that **Shockbyte can't create narrower
  users** — one all-privileges user per schema is the only option the panel offers, so a
  `SELECT`-only `stats_reader` isn't buildable there. Default (owner-confirmed 2026-09-14):
  `stats-api` runs with the same `ECON_DB_*`/`OPS_DB_*`/community admin credentials the
  economy/community APIs already use, read via each schema's existing DPAPI key window
  (`EconomyDbKey.ps1` etc.) — no new key tool, no new panel user, nothing extra for the owner to
  create. Read-only is enforced only by code review (no write statement anywhere in `stats-api`'s
  source), the same trust level this project already accepts for every other consumer of these
  credentials.
- **Faction standing has no DB source today — v1 ships without it.** Reputation
  (`Reputation`/`HighestReputation`) lives only in Expansion mod save data, read via
  `player.Expansion_GetReputation()` in `AEGIS_Metrics`'s `AegisMetrics.c` — never written to any
  MySQL table. Building the faction-standing panel and the AI-kill leaderboard column from the
  mockup for real needs a new mod-side export (periodic POST to `stats-api`, or a file `dayz_ops`
  importer reads) — out of scope for NS1. Default: NS1 ships population, uptime, and economy
  pulse only; faction standing and the AI-kill leaderboard column stay placeholder-only until a
  future NS3 session (below) is scheduled.
- **Playtime leaderboard is blocked on `dayz_ops` Session O5** (ADM log parsing — blocked on
  owner-supplied log location/sample). Default: NS1's leaderboard panel shows a "sessions today"
  count (already available from `player_sessions`) instead of cumulative playtime hours, and gets
  upgraded once O5 unblocks — not worth waiting on.
- **"AI kills" is not a tracked number — it's a reputation score.** `AEGIS_Metrics` stores
  `Reputation`/`HighestReputation` (a composite point total gating tiers — 25 points ≈ T3 per
  `aegis-mods/mods/AEGIS_Metrics/README.md`), not a literal AI-kill counter. Showing "Most AI
  kills" honestly needs a *new* counter field added to `AEGIS_Metrics` (increment-on-kill, not
  derived from reputation math), which is mod work beyond NS3's original scope (a straight export
  of the reputation number). Default: NS3 exports and shows **reputation tier**, worded as
  "Directive Standing" or similar, not "AI kills" — a session to add a real per-kill counter is a
  separate, later mod change if the owner wants the literal number instead of the tier.
- **This server is PVE-only — no PvP leaderboard, ever.** `aegis-website/src/pages/start.html`'s
  rules are explicit: "This is a PVE server... No PvP. Survive the world, not each other." A
  public leaderboard celebrating player kills would contradict a real, enforced server rule, not
  just be missing data. Any player-kill events `event-relay` eventually logs exist for moderation
  (catching rule violations), not for a public stats feature — drop "PvP kills" from this track's
  scope entirely rather than defer it.
- **Zombie/infected kills are not tracked anywhere — no mod field, no DB column.** Would ride the
  `event-relay` pipeline (see that track above), which is only the relay itself (EV1, built, not
  deployed) — nothing posts DayZ kill events into it yet. EV3 (the DayZ-side event source) is
  already blocked on an owner decision: a new in-game mod posting events via `RestApi`, vs. a
  log-scraper polling `.ADM`/`.RPT` files. **This leaderboard cannot exist before that decision is
  made and EV2+EV3 ship** — this is real new infrastructure, not a `stats-api` query away.
  Tracked as Session NS4 below rather than folded into NS1/NS3, so it doesn't block the panels
  that already have real data.

## Contracts

- `stats-api` never accepts writes and never proxies a live query per request — every response
  is served from an in-memory snapshot recomputed on a fixed interval (default 15 minutes,
  matching the mockup's footer disclosure).
- The public payload carries in-game callsigns only — no steam64 IDs, no Discord IDs, no raw
  session/IP data.
- `stats-api`'s source contains no `INSERT`/`UPDATE`/`DELETE`/`CREATE`/`DROP` statement anywhere,
  enforced by code review, since the grant itself can't be narrowed on Shockbyte — the read-only
  guarantee lives in this repo's code, not the database.

## Session NS1: `stats-api` service (build, no deploy)

- **Read:** `db/economy/src/api/server.js` and `db/community/src/api/server.js` for the existing
  plain-Node HTTP server + `ecosystem.config.js` conventions to match; `db/ops/migrations/0001_dayz_ops_core.sql`
  for `player_sessions`/`server_instances`; `db/economy/migrations/0001_dayz_economy_core.sql` for
  `ledger_transactions`/`ledger_entries`/`wallets`; `db/community/migrations/0001_init.sql` for
  `players.display_name` (the only public-safe name to pair with any of these — never `steam_id`).
- **Do:** New `stats-api/` (plain Node/ESM, `node:test`, no framework — matching every other
  service here). `GET /v1/stats/network` returns the cached snapshot:
  - population: current session count + 24h series from `dayz_ops.player_sessions`
  - uptime: rolling 30-day % from `dayz_ops.server_instances` heartbeats
  - economy pulse: trades settled + volume moved (24h) from `dayz_economy.ledger_transactions`/`ledger_entries`
  - leaderboard: today's session counts per callsign (see Open decisions — playtime hours once O5 lands)
  - **richest survivors**: top N by `dayz_economy.wallets.balance_units` (Scrip currency only),
    joined to `dayz_community.players.display_name` by steam_id — real data, no new tracking
    needed. Round/format balance; never expose `owner_id`/steam64 in the response.

  Recompute on a `setInterval` (default 15 min), serve the cached object with `Access-Control-Allow-Origin: https://aegisdirective.net`. Config reads the same `ECON_DB_*`/`OPS_DB_*`/community env vars the existing APIs use (see Open decisions — no new credential tooling). Integration tests against MySQL (same docker-gated pattern as `db/economy`).
- **Out of scope:** faction standing, reputation/zombie-kill leaderboards, deployment, TLS. No
  PvP-kill leaderboard is ever in scope — this is a PVE server (see Open decisions).
- **Done when:** tests pass in CI, `GET /v1/stats/network` returns real shapes against a local
  MySQL, PR merged.

## Session NS2: deploy to the OVH VPS

- **You:** copy the existing `ECON_DB_*`/`OPS_DB_*`/community DB credentials into `stats-api`'s
  deployment env (`/etc/aegis/stats-api.env` via `PushVpsSecrets.ps1`, same pattern as the other
  VPS services) — no new password to create, since NS1's default reuses the existing per-schema
  admin users. Add a Cloudflare Tunnel route (e.g. `stats.aegisdirective.net` or
  `aegisdirective.net/api/stats`) to the existing tunnel config.
- **Do:** pm2 process definition matching `db/economy`'s deploy artifacts, deployment docs.
- **Done when:** `GET /v1/stats/network` is reachable from the public internet and returns live
  numbers; PR merged.

## Session NS3: faction standing + Directive Standing leaderboard (mod-side export, later)

- **Do:** Extend `AEGIS_Metrics` to periodically POST a reputation snapshot (callsign, faction,
  tier, reputation score — no steam64) to a new `stats-api` ingest route, or write it to the same
  `events.jsonl` shape E9 already established for a future `dayz_ops` importer to pick up.
- **Out of scope:** a literal AI-kill counter (see Open decisions — reputation is a score, not a
  kill count; that's a separate mod change if the owner wants the raw number instead of tier);
  zombie kills (NS4).
- **Done when:** the network-status page's faction-standing bars and a "Directive Standing"
  leaderboard column show real reputation-tier data; PR merged. Not scheduled — revisit once
  NS1/NS2 are live and the owner wants those panels enabled.

## Session NS4: zombie-kill leaderboard (needs `event-relay` shipped first)

- **You:** decide `event-relay` Session EV3's open question (mod vs. log-scraper for the
  DayZ-side event source) — this session cannot start before that pipeline exists end-to-end
  (EV1 built/undeployed, EV2 deploy not started, EV3 not started).
- **Do:** Once infected-kill events are flowing into `dayz_ops`/`event-relay`'s event log, add
  a `stats-api` query for infected-kill counts per player (exact event shape depends on what EV3
  ends up producing — this session's real scope can't be nailed down before EV3 lands).
- **Out of scope:** building `event-relay`'s pipeline itself (that's the `event-relay` track's
  job, this session only consumes it once it exists); any PvP-kill leaderboard, ever — see this
  track's Open decisions (PVE-only server, no-PvP is an enforced rule).
- **Done when:** the network-status page shows a real zombie-kill leaderboard; PR merged. Not
  scheduled — blocked on the `event-relay` track, itself blocked on an owner decision.

## Track status

| Session | PR | State |
|---|---|---|
| NS1 | | **owner said hold off (2026-09-14)** — website metrics work is paused; not started |
| NS2 | | blocked on NS1, which is itself on hold per the owner's hold-off call above |
| NS3 | | not scheduled; blocked on owner wanting faction/leaderboard panels enabled |
| NS4 | | blocked on `event-relay` EV2+EV3 (which is blocked on an owner decision — see that track) |
