# Worktree archive — 2026-09-16 lane L2

Captures for worktrees flagged dirty-but-merged in the 2026-09-16 spool-down, per
`standards/sessions/worker_role.md`. One file per worktree that was genuinely dirty and safe to
capture; worktrees suspected of case-collision corruption were left untouched and are only noted
here, not archived.

## Archived (genuinely dirty, capture done, original removed after this PR merged)

- `_wt-ops-infra-session7-encryption` — see `_wt-ops-infra-session7-encryption.md`. PR ops-infra#8
  merged; one local-only commit (content already on origin via the merge) plus one real uncommitted
  diff to `tools/Vault-AideBaseline.ps1` (captured, flagged for owner follow-up).

## Left in place — possible case-collision corruption, needs manual look

All 5 are `MasterThread`-prefixed worktrees. Each showed `git status` reporting **"No commits yet on
<branch>...origin/<branch> [gone]"** together with an identical, full-repo-tree list of hundreds of
files staged as brand-new additions (`A`) — the same list, byte-for-byte, across all five worktrees
regardless of the worktree's actual name/purpose (e.g. `advisor-role` and `task-sizing-note` both
show the entire `Agents/`, `docs/`, `policies/`, `standards/`, `workflows/` catalog as newly staged).
That is the documented `agent/MasterThread/...` vs `agent/masterthread/...` casing-collision symptom
(known cause, not a new finding) — local ref resolution is corrupted, so `git status`/`git diff` in
these worktrees cannot be trusted to reflect that worktree's real content. Per the lane card, these
were NOT captured or archived — left in place for manual (non-agent) investigation:

- `_wt-MasterThread-advisor-role` — branch `agent/MasterThread/advisor-role`, corrupted status
- `_wt-MasterThread-ledger-ops-policies-security-public-2026-09-16` — branch
  `agent/MasterThread/ledger-ops-policies-security-public-2026-09-16`, corrupted status
- `_wt-MasterThread-t4-agents-round2` — branch `agent/MasterThread/t4-agents-round2`, corrupted status
- `_wt-MasterThread-task-sizing-note` — branch `agent/MasterThread/task-sizing-note`, corrupted status
- `_wt-MasterThread-usage-watch` — branch shows as `agent/MasterThread/usage-watch-launch` (note: not
  exactly `usage-watch`, an extra mismatch signal on top of the same corrupted-status pattern),
  corrupted status

None of these had `git worktree remove` run against them. Fixing the underlying casing-collision bug
is out of scope for this lane (bigger than this lane, per the card) — flagging only.
