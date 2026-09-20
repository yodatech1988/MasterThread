# Unversioned-files archive, 2026-09-16

A git-backed snapshot of files that had no version history anywhere before tonight, taken after
the near-loss of 72 agent definitions that existed only as an unreachable commit on one machine.
Same condition, originally found in three places; this commit covers two of them.

- **`_security-public/policies/`** (12 files, org-wide C0-C3 data-classification policy) is
  **deliberately excluded from this push** — the auto-mode classifier flagged pushing that content
  to a remote as data exfiltration and declined it twice. Not worked around; verified locally
  backed up at `<USER_HOME>\AEGIS-Backups\unversioned-2026-09-16\security-public-policies\`,
  and flagged to Jeremy directly for an explicit decision on how (or whether) to push it.
- **`session-handoffs/`** — the ~36 loose `.md` files (session handoffs, `NEXT_STEPS_*`,
  `SESSION_ROUNDS_*`) that live at `<USER_HOME>\GitHub\` root, itself not a git repo.
- **`tooling/`** — `AEGIS-Merge-Queue.ps1`, `AEGIS-Push-Agent-Roster-Backup.cmd`,
  `New-ParallelWorktrees.ps1`, `merge-queue.json`, also loose at that same root.

## This is an archival copy, not a relocation

The live originals stay exactly where they are. Two reasons, checked before archiving here rather
than moving anything:

1. **The `session-handoffs/` files are loose at `GitHub\` root by design, not by accident.**
   `MasterThread/.claude/agents/handoff-writer.md` and `MasterThread/skills/round-closeout/SKILL.md`
   both document writing `GitHub\SESSION_HANDOFF_<date>-<topic>.md` directly at that path — it's
   the convention every orchestrator round already follows. Moving the working copies into a repo
   would break that convention for every session that reads or writes them next.
2. **The `tooling/` scripts are invoked from `GitHub\` root by existing, already-written
   instructions** (e.g. `orchestrator_role.md`'s worktree step calls
   `GitHub\New-ParallelWorktrees.ps1` directly). Relocating them without updating every reference
   is a larger, riskier change than tonight's ask, and wasn't requested.

So: this directory exists so the *content* survives in git history even if the live copies are
ever lost again, verified byte-for-byte against
`<USER_HOME>\AEGIS-Backups\unversioned-2026-09-16\` before this commit. It is a safety copy,
refreshed periodically or after major rounds — not the new canonical location.

## What this deliberately does NOT decide

**Standing up `_security-public` as its own real git repository remains an explicit owner
decision**, not resolved by archiving its content here. Another session already correctly declined
to make that call tonight (it's adjacent to, but distinct from, the paused security program, which
stays paused until 2026-09-19 per standing memory). This archive gives the policy text a git
history without pre-empting that decision either way.

Recommendations from tonight's inventory, still open:
- `security-public-policies/` → deserves a real private repo eventually, once the owner decides.
- `session-handoffs/` → the working convention (loose files at `GitHub\` root) is fine to keep;
  this archive is the durability fix, not a request to change the convention.
- `tooling/` → candidate for eventually living in `MasterThread/tools/` for real, once every
  caller's path is updated in the same change — not attempted here.
