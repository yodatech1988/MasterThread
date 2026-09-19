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

`docs/AGENTS.md`'s Model, Role and Headless cells, and which agents sit in its "Advisors against
MasterThread's own standards" section, are generated from this directory (frontmatter and
`roster_meta.json`) by `tools/generate_agents_md.py --write`. Run it after adding, editing, or
removing any file here and commit the result in the same PR. New advisor/drafter files get their row
automatically; the Purpose/Grounded-in text is yours to edit and is never overwritten. Do not
hand-edit the derived cells: `--check` (and CI) fails when they differ from what `--write` produces.

## Checking for drift

Two read-only checks, neither of which writes or copies anything — added for audit findings
R4/R6/R10 (`docs/AGENT_ROSTER_AUDIT_2026-09-17.md`, MasterThread PR #84):

- **`python tools/generate_agents_md.py --check`** — verifies `docs/AGENTS.md` against this
  directory's frontmatter (and against `claude-agents/roster_meta.json` when that file exists).
  Fails if a `claude-agents/*.md` file has no row anywhere in `docs/AGENTS.md`, a row's Model cell
  disagrees with the file's `model:` frontmatter, a row in a *global* section (heading mentions
  `~/.claude/agents/`) has no matching file here, or a `roster_meta.json` entry and its row's
  Role/Headless cells disagree. It parses whatever tables already exist — it does not require
  `docs/AGENTS.md` to have been produced by this script's own `--write`.
- **`python tools/check_agent_sync.py`** — compares the real `~/.claude/agents/*.md` files
  against this directory and reports local-only, repo-only, and content-differing filenames.
  Add `--repo-local <path-to-GitHub-root>` to also scan sibling repo clones for the same
  agent-definition file existing under more than one repo's own `.claude/agents/` with different
  content (repo-local agents, not the global mirror -- e.g. `mod-boot-test-runner.md`, copied into
  `aegis-mods`, `aegis-poi`, and `aegis-pricing`).

Both exit non-zero when they find something to report, and both are safe to run any time — they
never modify `~/.claude/agents/`, this directory, or any other repo's checkout. CI
(`.github/workflows/agents-roster-check.yml`) runs the first one plus the `tools/tests/` unit
tests on every PR that touches `docs/AGENTS.md`, `claude-agents/**`, or `tools/**`; that workflow
runs on `ubuntu-latest` (MasterThread has no self-hosted runner registered yet) and is a courtesy
signal, not a required status check, until that changes. `check_agent_sync.py`'s live-machine
comparison can only run locally, since `~/.claude/agents/` doesn't exist in CI — treat it as
something to run by hand before or after a sync, not something CI enforces.
