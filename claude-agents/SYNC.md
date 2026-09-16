# Syncing this directory

This directory is a git-backed mirror of the **global** Claude Code T4 agent roster — the files
that live at `~/.claude/agents/` on the machine that runs sessions for this org. Before
2026-09-16, that local directory was the only copy of 70 agent definitions: no git history, no
backup, no way to recover a deleted or corrupted file, and nothing to check `docs/AGENTS.md`
against except a hand-maintained index someone had to remember to update. This directory and
`docs/AGENTS.md` (generated from it, see `tools/generate_agents_md.py`) close that gap.

## Direction: one-way, repo is truth

**`MasterThread/claude-agents/` is the source of truth. `~/.claude/agents/` is a local copy of
it.** Do not treat this as a two-way sync — that invites exactly the drift class the "dedicated
drift agent" part of the 2026-09-15 skills-program directive exists to catch (live vs main,
vendored copy vs upstream, worktree vs origin all being the same failure shape). One direction
only:

- **To change an agent's behavior:** edit the file in `MasterThread/claude-agents/` (in a
  worktree, on an `agent/MasterThread/<slug>` branch, same as any other change to this repo), open
  a PR, get it merged, then copy the merged file down to `~/.claude/agents/` on each machine that
  runs sessions.
- **Never** edit `~/.claude/agents/<name>.md` directly and assume it propagates anywhere. It
  doesn't — this repo has no way to see a local-only edit, and the next sync from repo → local
  would silently overwrite it.
- **Adding a new agent:** write it here first, not in `~/.claude/agents/`. `docs/AGENTS.md`'s
  "Adding a new one" section still applies (ground it in a real standard, pin the cheapest model,
  list only needed tools, add its row in the same PR — the row is now generated, see below, but
  still lands in the same PR as the new file).
- **Removing an agent:** delete the file here, regenerate `docs/AGENTS.md`, then delete the local
  copy.

## Applying the repo's copy locally

After pulling a merge that touched `claude-agents/`, sync it down (PowerShell, from the repo root):

```powershell
Copy-Item .\claude-agents\*.md "$env:USERPROFILE\.claude\agents\" -Force
```

This does not delete a local file that was removed from the repo — check `git log -- claude-agents/`
for deletions and remove the matching local file by hand if one shows up. There were 70 files here
at the time this directory was created (2026-09-16); if the count on your machine doesn't match
`ls claude-agents/*.md | wc -l` after a sync, something diverged — that's a drift-agent finding,
not something to silently resolve by copying over it.

## Regenerating the index

`docs/AGENTS.md`'s "Global" table is generated from this directory's frontmatter, not
hand-written — see `tools/generate_agents_md.py`. Run it after adding, editing, or removing any
file here, and commit the regenerated table in the same PR as the file change. Never hand-edit the
Global table directly; the next regeneration will overwrite a hand-edit without warning.
