---
name: repair-phantom-staged-worktree
description: Use when a git worktree reports hundreds of "staged" files and `git log` fails with "no commits yet" or "unborn branch" — diagnoses whether this is a phantom index artifact from a deleted branch ref (not real uncommitted work) and, only after confirming, reattaches the branch ref with `git update-ref`. Applies estate-wide to any repo using worktrees after a squash-merge + auto-delete-branch + prune.
---

# repair-phantom-staged-worktree

## When to use this

- A worktree (any repo, `git worktree list`) shows a very large "staged" file count in
  `git status`, and `git log` in that worktree fails with `fatal: your current branch '<branch>'
  does not have any commits yet` (an "unborn branch" state) — the exact symptom recorded in
  `docs/LESSONS.md`'s 2026-09-18 entry "A worktree's index can show hundreds of 'staged' files with
  nothing actually staged."
- The likely cause: the branch was squash-merged, the remote auto-deleted the branch, and a local
  `git worktree prune` / branch cleanup removed the local ref — but the worktree's on-disk files and
  index still hold the full tree, so git reads it as an unborn branch with everything staged. This
  is an index artifact, not lost work.
- Do **not** use this skill's repair step to "rescue" a worktree just because it shows staged
  files — confirm the specific failure signature first (Procedure step 1-2). A worktree with a real
  branch ref and genuinely staged changes is not this case.

## Procedure

1. **Identify the branch and confirm the ref is missing.**
   ```
   git -C <worktree-path> symbolic-ref HEAD
   ```
   This returns the branch the worktree's HEAD points at (e.g. `refs/heads/<branch>`). Then:
   ```
   git -C <worktree-path> show-ref --verify refs/heads/<branch>
   ```
   If this fails ("not a valid ref"), the branch ref is genuinely missing while HEAD still points at
   it — the unborn-branch symptom. If it succeeds, this is not the phantom-staged case; stop and
   look elsewhere.

2. **Confirm the staged count is the whole tracked tree, not real staged work.**
   ```
   git -C <worktree-path> ls-files | wc -l
   git -C <worktree-path> status --porcelain | wc -l
   ```
   These two counts should match (or be very close). If they match, this is the index-artifact
   pattern from `docs/LESSONS.md` — the "staged" files are just every tracked file, not something a
   session added. If they don't match, stop; this may be real staged work and needs a human look,
   not this skill's repair step.

3. **STOP — determine whose worktree this is before going further.** Check the path against the
   convention `worker_role.md` and `orchestrator_role.md` use for session-created worktrees
   (`_wt-<repo>-<topic>` under `C:\Users\yoda_\GitHub\`). If the worktree path does **not** match
   that `_wt-*` pattern — i.e. it looks like the owner's own primary checkout of a repo, not one a
   session created for a lane — **do not run step 5. Ask the owner first** (a Decision Queue card
   or, if the owner is actively present, ask in chat per this estate's owner-decision rules) before
   touching it. `docs/LESSONS.md` records this exact ambiguity was seen once on the owner's own
   shared `MasterThread` checkout (779 files, diagnosed, repair recommended but not applied) and
   once on a session-created `_wt-MasterThread-buildstate-paths` worktree (883 files, repaired) —
   the two cases get different handling. Only a session-created `_wt-*` worktree may proceed
   straight to step 5 on the session's own authority.

4. **Find the target SHA from the matching merged PR.**
   ```
   gh pr list -R <owner>/<repo> --state merged --head <branch> --json number,headRefOid,mergedAt
   ```
   If more than one merged PR matches the branch name, do not guess — stop and ask (this is
   underdetermined, not a case to auto-resolve). If none match, stop; there is no known-good SHA to
   reattach to and this needs a human look.

5. **Reattach the ref — never commit, never reset.**
   ```
   git -C <worktree-path> update-ref refs/heads/<branch> <headRefOid-from-step-4>
   ```
   This is a zero-content-change ref write: it does not touch the index or working files. Per
   `docs/LESSONS.md`, **never** run `git commit` here (it fabricates a parentless root commit
   capturing nothing real) and **never** run `git reset` (wrong tool for a missing ref, not a wrong
   index).

6. **Re-verify.**
   ```
   git -C <worktree-path> log --oneline -3
   git -C <worktree-path> status --porcelain | wc -l
   ```
   `git log` should now show real history ending at the reattached SHA, and the "staged" count from
   step 2 should have dropped to reflect only genuine differences (typically 0, since the ref now
   matches the tree that was already checked out).

## Helper script (diagnose-only)

`diagnose.ps1` in this folder runs steps 1, 2, and 4 read-only and prints the exact
`git update-ref` command for the session to run itself after completing step 3 (the owner-check).
It never writes anything — no `update-ref`, no `commit`, no `reset`. Usage:
```
powershell -File diagnose.ps1 -WorktreePath <path> -Owner <gh-owner> -Repo <repo>
```

## Stop conditions

- Step 1's `show-ref --verify` succeeds (ref exists) — this isn't the phantom-staged case.
- Step 2's two counts don't roughly match — possible real staged work; get a human to look rather
  than treating it as an artifact.
- Step 3 shows the worktree is **not** a session-created `_wt-*` worktree — stop, do not run
  `update-ref`, ask the owner first (Decision Queue card, per this estate's default channel for
  owner decisions — `standards/sessions/decision_queue_standard.md`).
- Step 4 finds zero or more than one matching merged PR for the branch — stop and ask rather than
  guessing the SHA.
- Any point where `git status --porcelain` shows content that doesn't look like the full tracked
  tree (e.g. a handful of files unrelated to the branch's known scope) — treat as possible real
  work, not an artifact, and stop.

## Grounded in

- `docs/LESSONS.md`, 2026-09-18 entry "A worktree's index can show hundreds of 'staged' files with
  nothing actually staged" (`origin/main`) — the symptom, root cause, diagnosis commands, the
  `update-ref` fix, the "never commit / never reset" rule, and both prior sightings (the
  session-created `_wt-MasterThread-buildstate-paths` worktree, repaired, and the owner's own
  shared `MasterThread` checkout, diagnosed but left unrepaired pending owner input — the source of
  this skill's step-3 stop condition).
- `gh pr list --help` (verified live) — confirms `--state merged --head <branch> --json
  number,headRefOid,mergedAt` are all valid flags/fields.
- `claude-agents/worktree-sweep.md` and `claude-agents/worktree-prune-executor.md` (`origin/main`)
  — related but distinct: they report/prune worktree *registrations*, never touch a worktree's ref
  or index, and are referenced here only for context, not reused as steps (neither of them performs
  this repair).
- `skills/owner-click/SKILL.md` and `standards/sessions/decision_queue_standard.md` (referenced by
  name, not quoted) — the routing this skill uses when step 3 finds a non-session worktree: an
  owner decision goes through the Decision Queue by default, never assumed or auto-resolved.
