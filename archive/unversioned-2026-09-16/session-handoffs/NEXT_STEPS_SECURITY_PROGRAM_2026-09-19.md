# Next steps: security program documents (Saturday 2026-09-19, 6:00 AM)

Paused by the owner on 2026-09-14. That week is for game-server stability only. **Documents only:
nothing is deployed, migrated, pushed, or changed on GitHub, the VPS, or any account.** The enclave
build (E-sessions) and the AEGIS implementation (I-sessions) wait until the game server is stable
and the owner gives a separate go-ahead.

## How it starts (automatic)

- **Scheduled task:** Windows task `AEGIS Security Docs (Sat 2026-09-19 0600)` runs `C:\Users\yoda_\GitHub\AEGIS-Security-Docs-Saturday.cmd` at 06:00 EDT.
  - Settings: wake the PC, catch up if missed, run only while logged on.
- **Session it opens:** an interactive Claude Code session named "AEGIS security docs D1-D5".
  - Remote Control is on, so it can be opened from the Claude phone app or claude.ai/code.
  - Runs Opus in auto mode.
  - Denied tools: `git push`, `gh`, `ssh`, `scp`, `wrangler`, and the Gmail/Drive/Calendar/QuickBooks/Notion/Zapier connectors.
- **Cancel:** delete the task in Task Scheduler.
- **Manual fallback:** double-click the `.cmd`, or paste the prompt below.

## Starter prompt (manual fallback; paste into a fresh Claude Code session at `C:\Users\yoda_\GitHub`)

```
Read C:\Users\yoda_\GitHub\NEXT_STEPS_SECURITY_PROGRAM_2026-09-19.md and the plan it points to,
then finish sessions D1–D5 as documents only. Do not push, open PRs, use gh write commands, SSH,
change settings, or use the Gmail/Drive/Calendar/QuickBooks/Notion/Zapier connectors. Check usage
with MasterThread tools/usage-monitor/check-usage.ps1 first and stop cleanly at ~80%.
```

## Read

- **Plan (spec):** `C:\Users\yoda_\.claude\plans\ive-changed-you-to-immutable-forest.md`, whole file. Its STATUS block is the pause record.
- **House style:** `MasterThread\standards\sessions\priority_classification.md` and `PLAN_template.md`.

## State at pause

- **`_security-public\policies\`** holds 10 drafts from workers stopped mid-run. They are **unverified**, so re-review each one against the plan before building on it:
  - `README.md`
  - `compliance/{governance,privacy,audit_logging}.md`
  - `data/{classification,retention}.md`
  - `security/{enclaves,secrets_handling,incident_response,agents_and_automation}.md`
- **Missing:**
  - `policies/data/access_control.md`
  - `docs/ENCLAVE_MIGRATION_PLAN.md`
  - all of `_security-aegis\` and `_security-personal\`
- **Private folders:** `_security-aegis` and `_security-personal` are already local git repos with no remote and a pre-push hook that always fails. Neither has commits yet.

## Do (order)

Lanes can run in parallel. Each lane owns different files.

1. **D1/D2 (public-safe).** Review the 10 drafts. Then write `access_control.md` and `ENCLAVE_MIGRATION_PLAN.md` (PLAN_template format, E1–E9).
   - Public-safety rule: no IPs, hostnames, Steam64s, emails, the AEGIS domain, `clixml`, `%APPDATA%`, `/etc/aegis`, `/srv/`, or personal-data table names.
   - Also no standalone words "son", "care" or "autism" (write "child-family"). Repo names and doc paths are fine.
2. **D3 (`_security-aegis`).** Write: README, DATA_INVENTORY, CREDENTIAL_REGISTER, AUDIT_LOG_DESIGN, GAP_REGISTER, ROADMAP (I1–I6, I8–I10; I7 moved to the personal enclave), SEED_EVENTS.jsonl, RECOVERY_KIT.
   - Read services files from `origin/main`. The local `aegis-services` checkout is stale.
3. **D4 (`_security-personal`).** Write: HANDLING, DATA_INVENTORY, CREDENTIAL_REGISTER, HOST_BUILD (Ubuntu runbook for the interim Hyper-V VM and the later dedicated host), AUDIT_DEPLOYMENT, GAP_REGISTER, RECOVERY_KIT.
   - Read repo files only. Never open `.env`, `*.db`, logs, `secrets.local.env`, geofence seed files, or any clixml.
4. **D5.** Run the plan's Verification section: leak scan, firewall scan, gitleaks, cross-references, seed-event JSON parse. Then commit locally in the two private repos. Never push.

**Firewall while drafting:** AEGIS docs never describe personal/financial data, and personal docs never describe AEGIS data. Cross-enclave items appear only as pointer IDs.

## Contracts

### Gap IDs
Verify each gap before recording it.

**Tracked in `_security-aegis\GAP_REGISTER.md`:**

| Priority | IDs |
|---|---|
| Shared core | SC-P0-1 child-family exposure in the public shared-core ledger (containment: owner makes MasterThread private) · SC-P1-1 REPOS.md row 10 asks for settings.json allow rules · SC-P1-2 Claude account connectors visible to AEGIS sessions · SC-P1-3 PC holds both enclaves' stores and transcripts |
| P0 | A-P0-1 DayZ join/#login passwords in site-chernarus history |
| P1 | A-P1-1 public Business-development panel login address · A-P1-2 session archive has no PII redaction and unencrypted raw backups · A-P1-3 security events from 2026-09-14 unrecorded · A-P1-4 classify.js drift · A-P1-5 plaintext email with no erasure path · A-P1-6 LOG_RAW chat on disk and chat-ai IPs · A-P1-7 admin_actions weaknesses · A-P1-8 backups only on the VPS and age key custody · A-P1-9 runner on a public repo check · A-P1-10 inconsistent secret scanning |
| P2 | A-P2-1 key windows don't log · A-P2-2 CODEOWNERS · A-P2-3 label sync · A-P2-4 bi_uid mismatch · A-P2-5 Steam64s in docs and scripts, DayZServer lists, SuperAdmins.txt · A-P2-6 gh-federation rejected auth · A-P2-7 economy retention · A-P2-8 cloudflared root · A-P2-9 port 22 · A-P2-10 Anthropic admin-key tooling in jarvis |
| P3 | A-P3-1 hash chain · A-P3-2 SECURITY.md · A-P3-3 mod-log minimization · A-P3-4 SECRET-ROTATION alignment |

**Tracked in `_security-personal\GAP_REGISTER.md`:**

| ID | Gap |
|---|---|
| SC-P0-1, SC-P1-2, SC-P1-3 | Pointers only |
| P-P1-1 | Interim VM shares hardware with the AEGIS console (closed by E9) |
| P-P2-1 | Personal repos in the AEGIS GitHub account (E4) |
| P-P2-2 | vehicle-tracker in the shared Cloudflare account (E5) |
| P-P2-3 | vehicle-tracker has no retention (P1 once the device is live) |
| P-P2-4 | jarvis runtime files in the PC host profile (E7) |
| P-P2-5 | No connector-grant register (E6) |
| P-P3-1 | Archived financial repos: confirm they hold no data (E4) |

### Seed events for `SEED_EVENTS.jsonl` (2026-09-14 UTC)
- **Actor:** `claude-code:4a574179-7ed7-4455-9f46-bcd9da61f709`.
- **IDs:** each event gets a UUIDv7 generated from its timestamp.

| Time (UTC) | Event type | Detail |
|---|---|---|
| ~20:23:40 | `repo.protection_changed` | core main `enforce_admins` disabled; approval owner_explicit ("Admin-merge core #74 now"); shares a correlation id with the next two rows |
| 20:23:52 | `repo.admin_override` | core#74 squash-merged (required checks queued on the billing-blocked hosted runner) |
| ~20:23:55 | `repo.protection_changed` | `enforce_admins` restored |
| 21:09:42 | `repo.merged_unverified` | services#88 (checks pending on the not-yet-working runner; services main has no required checks) |
| 21:15:05 | `repo.merged_unverified` | services#89 |
| 22:06:47 | `infra.hardening_changed` | services#90 removes RestrictSUIDSGID from the runner unit; approval owner_explicit; merged, apply pending on the owner-click installer |
| ~22:40 | `agent.prompt_injection_suspected` | Research subagent output flagged by the harness; not acted on; `time_approximate: true` |
| ~23:30 | `data.exposure_found` | SC-P0-1; severity critical; tag child-family; no content in details |

## Owner decisions

- **S0 / SC-P0-1:** the owner declined to make MasterThread private (2026-09-14, "already private enough"). Record it as an **owner-accepted risk** for now. **The owner will address it on Saturday 2026-09-19**, so put it on that session's agenda for him and don't raise it before then.
- **Heads-up:** VPS CI is now handled by another session (github-e2) through `AEGIS-VPS-CI-All.cmd`. It is not part of this program.
