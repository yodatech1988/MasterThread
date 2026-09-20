# Handoff — Autonomous ops cycle PM (2026-09-15 evening)

**You are the project manager for the autonomous ops cycle program.** Sonnet 5 / low effort. You
manage; lanes do the building. Read this file first. It is written so you can act without
re-deriving anything.

---

## 0. Do these two things before anything else

**1. Start the usage watcher** (required of every orchestrator; do not skip):

```
Monitor  command: MT=<USER_HOME>/GitHub/MasterThread; N=ops-cycle-pm; git -C $MT fetch -q origin main; git -C $MT show origin/main:tools/usage-monitor/usage-watch.ps1 > "$APPDATA/AEGIS/usage-watch.$N.ps1" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$APPDATA/AEGIS/usage-watch.$N.ps1" -HandoffRoot <USER_HOME>/GitHub -Name $N -Program "autonomous ops cycle PM" 2>&1 || echo "USAGE-ERROR could not load or run usage-watch.ps1 from MasterThread origin/main"
         description: Claude usage tiers for ops-cycle-pm
         timeout_ms: 1800000
```

Re-arm it with the same `-Name` every time it expires (every 30 min). Act on `USAGE TIER` lines:
80 = stop dispatching, 90 = pause lanes, 97 = write the next handoff, 98 = commit it, 99 = stop.
`USAGE-ERROR` means usage is unknown — treat it as high. Full runbook:
`MasterThread\standards\sessions\orchestrator_role.md`, "Usage watcher".

**2. Read the authority document.** It is the single source of truth for the design and the 93-task
work tree. If anything disagrees with it, it wins:

- `Artifact` tool, `action: "read"`, `url: https://claude.ai/artifact/WZsmRodvsHAbVFj54JghKf`
- It saves a local copy and tells you the path. The task list is the `PHASES` array inside the
  `<script id="appjs">` block; the prose is the rest. **Do not reuse any `extract.txt` from an
  older session directory — those go stale and already caused one lane to write wrong text.**

There is also a status report for the owner:
`https://claude.ai/artifact/FNaa1dZWGDd6sN9vsuvhcZ` ("Ops Cycle Checkpoint").

---

## 1. Standing rules you must not break

| Rule | Detail |
|---|---|
| **Nothing AEGIS-branded touches personal or financial** | Owner rule. The vault has its own key, users, paths, Discord, CI and gateway. Never put the `aegis-vps-admin-bot` key, the `aegis` user, `/srv/aegis`, `/etc/aegis`, an AEGIS bootstrap script or a CI runner on the vault. |
| **No git or terminal steps for Jeremy** | Do git yourself, or give him a clickable `.cmd`. He merges nothing by hand — see §5. |
| **No stacked PRs** | Tell every lane: one PR per session, based on `main`. Stacks tangled three repos today. |
| **Zero cost first** | Free options first. Flag anything that costs money before doing it. Paid compute runs on the VPS, not GitHub-hosted runners. |
| **No PATs for bots; no static Anthropic API keys** | Federated access only. |
| **Verify before merge** | Check the diff against `origin/main`, not a stale checkout. Don't trust a lane's report without a spot check. |
| **Don't re-raise settled decisions** | Discord (not Signal), Cloudflare (not Tailscale), OVH Object Storage, separate gateway. All decided by the owner. |
| **Don't boot a local DayZ server while Jeremy is in game** | It kicks his client. |

Model/effort per task: `MasterThread\standards\sessions\orchestrator_role.md`. Short version —
Opus 5 only for live hosts, credentials, money, or a contract other sessions build on; Sonnet 5
medium for normal build lanes; Sonnet 5 low for docs; Haiku 4.5 for mechanical read-only sweeps.

---

## 2. Where things stand

**Progress: 11 of 93 tasks done, 8 more built but not deployed, 25 PRs merged, nothing open.**

### Hosts

| | Public edge | Personal vault |
|---|---|---|
| OVH label | `aegis-public-edge` | `personal-vault` |
| Service | `vps-736c134b.vps.ovh.us` | `vps-6bfe4b32.vps.ovh.us` |
| IP | `40.160.90.128` | `<vault IP: see ops-infra/ansible/inventory/hosts.yml>` |
| SSH | `ssh -i ~/.ssh/aegis-vps-admin-bot ubuntu@40.160.90.128` | `ssh -i ~/.ssh/vault-admin ubuntu@<vault-ip>` |
| Host key | `SHA256:G13wP9RUgI4bgz2vgY6uQSmlmyMav54c9MeUFZBpjQw` | `SHA256:MopRFgQX4nTI4rCrE/zqHDYTnpzULoOmvlKDz+QGDes` |
| Role | AEGIS game zone. **Live players. Don't change it.** | Vault: PM, router, ledger, gateway, approval app, finance, household |

OVH API from the PC: `core\tools\OvhApiKey.ps1 -Call GET /vps` (scope `/vps/*` only, no DELETE, no
`/cloud/project`). Vault runbook for the *edge* box: `services` repo `docs/ops/VPS.md`.

### Repos (all five created, seeded, and their first work merged)

`ops-infra` · `ops-policies` · `ops-platform` · `ops-business` · `ops-household`, all under
`yodatech1988`, all private, all cloned at `<USER_HOME>\GitHub\<name>`.

### What is live on the vault (verified on the box)

Ubuntu 26.04, rebuilt clean. ufw default-deny with only 22/tcp open, fail2ban, no root login,
unattended upgrades rebooting at 04:00 UTC. Per-zone users (`vault-platform`, `vault-business`,
`vault-household`, `vault-finance`) with rootless Podman, cross-zone and internet traffic blocked.
auditd, AIDE and CrowdSec (local-only). SOPS/age path proven with a throwaway key — **no real key
exists yet, deliberately**, because OVH images the unencrypted disk daily.

### What is built but NOT deployed

`ops-platform` (149 tests passing): router, cost estimator, budget ledger, batch lanes, Discord
bridge, project-manager agent. `ops-policies` (172 tests + OPA): data classes, routing, tool
allowlists, egress rules, the AEGIS-separation invariants, redaction corpus.

### Owner decisions already made (do not reopen)

- Chat: **Discord**, private server that is not the AEGIS community server, D0/D1 only.
- Vault access: **Cloudflare Tunnel + Access** on **`bergervault.link`** — same Cloudflare account
  as AEGIS, but its own tunnel, Access app, policy and token. (Owner chose this over Tailscale;
  Cloudflare can see traffic, accepted.)
- Encryption: **split** — data volume auto-unlocks, a small sealed volume for finance credentials
  needs the owner's passphrase.
- Backups: **OVH Object Storage** in Public Cloud project "vault"
  (`<ovh-project-id>`) + an append-only copy on the PC.
- Egress gate: **a new separate gateway** in `ops-platform`, never the AEGIS `services` one.
- Budgets: game $10/month; platform, business, household, finance $0.

---

## 3. In flight right now

**ops-infra Session 11 — AppArmor. Nearly done; paused for the session change.**
Branch `agent/ops-infra/apparmor` @ `2cf4c80` (WIP, pushed), **draft PR
[#7](https://github.com/yodatech1988/ops-infra/pull/7)**, worktree
`<USER_HOME>\GitHub\_wt-ops-infra-apparmor`.

- **Root cause found:** Ubuntu 26.04 sets `kernel.apparmor_restrict_unprivileged_unconfined=1`, so an
  unprivileged process that *asks* for a profile (systemd `AppArmorProfile=`, `aa-exec`, crun,
  podman) lands in the stack `unconfined//&<profile>`; the moment Podman creates its user namespace
  the unconfined half becomes `unprivileged_userns`, which denies all capabilities. The fix is
  exec-time attachment by path through a per-zone `user@UID` wrapper, which that restriction doesn't
  cover.
- **Already verified live on the vault** (I re-checked independently): all four zones' payloads run
  confined — e.g. `conmon`, `pasta`, `httpd` under `vault-zone-business (enforce)`. Negative tests
  were refused and logged; the Session 2 floor still holds (no capabilities, no-new-privileges,
  seccomp, read-only root, cross-zone and internet blocked); no Ubuntu profile or sysctl was
  weakened.
- **Left to do:** one clean `-Apply` to confirm `changed=0` (a single `canary-platform` HTTP check
  failed on what looked like a restart race and passed after a manual restart; the other three zones
  passed in the same run); review the AIDE diff and refresh its baseline only if every entry is
  explained (**not done — do not refresh blindly**); update `docs/PLAN.md` status and clear the
  Session 8 blocker; take PR #7 out of draft and merge it.

**Your first lane: finish it.** Opus 5 / high (live host + security control). Card:

> Lane card: **ops-infra Session 11 — AppArmor, final steps.** Opus 5 / high.
> Role: follow `MasterThread\standards\sessions\worker_role.md`.
> Worktree: `<USER_HOME>\GitHub\_wt-ops-infra-apparmor`, branch `agent/ops-infra/apparmor`
> (work ONLY here). A previous session got the profiles enforcing and paused; read draft PR
> `yodatech1988/ops-infra#7` and `docs/PLAN.md` Session 11 first, then do exactly what remains:
> one clean `-Apply` proving `changed=0` and settling the `canary-platform` restart race; review the
> AIDE diff and refresh the baseline only if every entry is explained by this work; update
> `docs/PLAN.md` and clear the Session 8 blocker; mark PR #7 ready for review.
> Vault: `ssh -i ~/.ssh/vault-admin ubuntu@<vault-ip>`. **Never touch the edge box**
> (40.160.90.128, live players).
> Done when: the zone containers run under an enforcing AppArmor profile, proven by a negative test
> (a denied action inside a container is actually blocked and logged) and by
> `/proc/<pid>/attr/current`; the earlier checks (no-new-privileges, seccomp, read-only root,
> cross-zone and internet blocks) still pass; a re-apply changes nothing; AIDE's diff is reviewed and
> its baseline refreshed only if every entry is explained; `docs/PLAN.md` status and the Session 8
> blocker are updated. **One PR against `main`. Never push to `main`. No stacking.**
> Owner rule: nothing AEGIS-named on the vault. Zero cost. If the only fix would weaken something
> else or needs a vault reboot, stop and report options instead of choosing.

---

## 4. The queue after that, in order

Each is one lane, one PR against `main`. Dependencies are real — don't start one early.

1. **Session 7 — encryption and real keys** (Opus 5 / high; after AppArmor). Split LUKS per the
   decision above: auto-unlocking data volume, passphrase-sealed finance volume (an encrypted
   container file on the existing disk; no OVH console needed). Then create the vault's first real
   age/SOPS keys on the encrypted volume. The passphrase step needs the owner.
2. **Sessions 5 + 6 — Cloudflare Tunnel + Access, then close port 22** (Opus 5 / high; after
   `bergervault.link` resolves — it had not been published by the `.link` registry at 18:33 on
   2026-09-15; check with `nslookup -type=NS bergervault.link 1.1.1.1`). The vault's own tunnel,
   Access application and scoped token. Include a break-glass path (OVH rescue mode) and drill it
   **before** closing 22. Then confirm zero public ports with an outside scan.
3. **Session 9 — backups** (Sonnet 5 / medium; after the owner sets the OVH spending cap). restic to
   OVH Object Storage in project "vault" + append-only PC copy. The S3 credential must go through a
   DPAPI key window on the PC (pattern: `services\tools\*Key.ps1`), never into git or an env file
   Jeremy has to retype.
4. **Session 8 — Postgres + hash-chained audit log** (Opus 5 / high; after 7 and 11).
5. **Session 10 — restore test** (Sonnet 5 / medium; after 8 and 9). **This completes Phase 1.**
   Afterwards, tell the owner to switch OVH automatic backup off on the vault only.
6. **Phase 2 build-out** (mixed): SPIRE identity + the federation rules the owner creates in the
   Console (2.1–2.4, 2.6); GitHub branch protection, CI, cosign signing, pull-based deploys
   (2.7–2.14) — **blocked, see the CI problem below**; agent runtime and sandbox (2.16–2.18);
   deploying the already-built router/ledger/PM/Discord bridge onto the vault; the new egress
   gateway and passkey approval app (2.27–2.30); then the gate test with dummy D3 data (2.31), which
   is the Phase 2 exit.
7. **Phase 3 game zone**, **Phase 4 business**, **Phase 5 household**, **Phase 6 personal finance**,
   **Phase 7 review** — all per the work tree. Phases 4 and 5 already have merged plans in their
   repos; Phase 6's redaction test corpus already exists in `ops-policies`.

### Known blocker to raise early

**The ops repos have no CI home.** GitHub-hosted runners fail on this account's billing, and the
edge box's self-hosted runners are AEGIS-side and must never be given personal/financial repos.
Phase 2's signed releases depend on solving this. Options to put to the owner: a runner on the vault
(**the standard forbids this** — never a CI runner on the vault), a third small host, or fixing
GitHub billing. This is an owner decision; don't pick one silently.

---

## 5. Merging: how not to repeat today's mess

Lanes sometimes open stacked PRs anyway. If a PR's base is not `main`, merging it puts the code into
that parent branch, **not** `main`, and every PR above it shows a false "Conflict".

- `gh pr merge` fails on stacked PRs with "must be merged using the asynchronous merge REST API".
- Helper written today: `<USER_HOME>\AppData\Local\Temp\...\scratchpad\merge-async.ps1` is gone
  with the old session; it was just
  `gh api -X PUT repos/yodatech1988/<repo>/pulls/<n>/merge-async -f merge_method=merge`, then poll
  `gh api repos/.../pulls/<n>/merge-async/<uuid>`.
- **Safe way to land a stack:** confirm the top branch contains every PR head
  (`git merge-base --is-ancestor <head> <top-branch>`), merge `origin/main` into the top branch, run
  the repo's tests, open ONE PR from the top branch to `main`, merge that, then verify with
  `git merge-base --is-ancestor <each head> origin/main`. Close leftovers with a comment saying
  where the code landed.
- **Jeremy should not merge these himself.** He asked for help after hitting exactly this. Do it for
  him and tell him when it's done.

Also in memory: `github-stacked-pr-merge`.

---

## 6. Waiting on the owner

Chase these; several block the queue above.

1. **Spending cap** on the OVH Public Cloud project "vault" — blocks backups (Session 9).
2. **Move `vps-736c134b…-storage`** (the edge box's storage) out of the "vault" project into its own
   AEGIS/game project — separation hygiene.
3. **Create a private Discord server** for business and household — blocks the Discord bridge going
   live and both domain lanes.
4. **Anthropic Console:** create Platform, Business, Household and Finance workspaces; then disable
   API key creation and set spend limits on all five (tasks 0.6, 0.7). Blocks Phase 2 federation.
5. **Confirm GitHub 2FA uses a hardware key or passkey**, not only TOTP (task 0.8).
6. Optional: ask Anthropic about zero data retention (task 0.10).
7. **Phase 4 answers, only when Phase 4 starts:** one QuickBooks company or two, the confidence
   threshold for auto-categorising, the invoice auto-send threshold, Applewood's metering, and the
   Notion database IDs + a scoped token.
8. **Phase 5 default to confirm:** teens get reminders through a guardian's Discord, not their own.

`ops-policies` has 31 open questions in `docs/OPEN_QUESTIONS.md`, all running on safe defaults. None
blocks work today; raise each when its phase arrives.

---

## 7. Cost so far

At API prices this program would have cost **$143.10** (Opus $116.49, Sonnet $26.61) across 948
calls — actually paid by the subscription. At 18:33 on 2026-09-15 usage was 28% of the 5-hour window
and 7% of the week. Caching saved roughly $850 of that; keep prompts cache-friendly (stable prefix
first, volatile content last). Method and full breakdown: the Ops Cycle Checkpoint artifact.

---

## 8. Memory files worth knowing

`aegis-autonomous-ops-cycle` (this program, all decisions) · `github-stacked-pr-merge` ·
`aegis-usage-monitor-tool` (the watcher) · `jeremy-no-git-commands` · `jeremy-directness-preference`
· `aegis-orchestrator-role` · `aegis-zero-cost-first` · `aegis-parallel-worktree-system` ·
`aegis-worktree-remove-no-force` · `aegis-verify-before-merge`.

Worktrees for finished lanes can be pruned once their PR is merged — check `git status` first and
never use `--force`.
