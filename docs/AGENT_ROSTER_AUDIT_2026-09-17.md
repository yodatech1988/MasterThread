# Agent roster audit — 2026-09-17

Audit of every built Claude Code subagent against `docs/AGENTS.md`, asked for directly by the owner.
Read-only: nothing was changed except adding this file. Every finding below was checked against
live state on 2026-09-17 (the real files in `~/.claude/agents/`, each repo's origin default branch,
and `gh`), not against another document's claim.

## What exists

| Where | Count | Source checked |
|---|---|---|
| Global, `~/.claude/agents/` | 74 files | local directory listing |
| Git mirror, `MasterThread/claude-agents/` | 71 agent files + `SYNC.md` | `origin/main` |
| `MasterThread/.claude/agents/` | 2 | `origin/main` |
| Repo-local, 11 repos | 33 definitions (`mod-boot-test-runner` and `module-json-contract-checker` are copied into 3 and 2 repos) | each repo's origin default branch |
| Legacy `MasterThread/Agents/` | 76 agent spec folders, 608 files | `origin/main` |

What is healthy: every one of the 74 global files pins a model in frontmatter and lists its tools;
the 71 mirrored files are byte-identical to the live copies (line endings aside); the one Opus
agent (`live-reviewer`) is the only one; the four dormant Discord/Patreon agents all detect that
their policy file is a 0-byte stub and say so instead of inventing rules.

## Findings

### F1. Three live global agents are not in git and not in the roster

`attorney-referral-researcher`, `legal-precedent-researcher`, `legal-risk-assessor` exist only in
`~/.claude/agents/`. They are absent from `claude-agents/` and from `docs/AGENTS.md`.
`claude-agents/SYNC.md` says new agents are written in the repo first and copied down; these went
the other way, which is the exact local-only state the mirror was built to end. There is also no
record in the repo that `agent-automation-gatekeeper` reviewed them. Two of them hold
`WebSearch`/`WebFetch`, the only web-capable agents in the roster.

### F2. `docs/AGENTS.md` lists three handymansfield agents that were never merged

The roster rows for `invoice-drafter`, `expense-triage` and `quote-generator` describe agents from
handymansfield PR #10, which is **closed, not merged**. They exist only in the local worktree
`_wt-handymansfield-t4-agents`. Meanwhile the two agents that are on handymansfield's default
branch, `invoicer` and `job-intake`, have no roster row. `quote-generator`'s row even cites
`job-intake` as its grounding.

### F3. One model in the roster disagrees with the file

`rollout-plan-advisor`: roster says `sonnet`, the file (live and mirrored) says `haiku`. The roster
notes the underlying standard is thin, so haiku may be the right call, but one of the two is wrong.

### F4. The generator that was meant to stop F1–F3 has never been finished

`tools/generate_agents_md.py` exists to derive the Global table from `claude-agents/` frontmatter.
Its own docstring says it was deliberately not run because it would drop the Role column, and that
extending it is left "for the next person". So `docs/AGENTS.md` is still hand-maintained, and F1–F3
are the predictable result. Nothing in CI compares the roster, the mirror and the live directory.

### F5. Role classification is incomplete

`docs/AGENTS.md` says a blank Role is "a real gap, not a doesn't-apply". Ten rows that have a Role
column are blank (`patreon-entitlement-checker`, `support-triage`, `moderation-flagger`,
`announcement-drafter`, `vuln-scan-active`, `mod-boot-test-runner`, `invoice-drafter`,
`expense-triage`, `voice-transcriber`, `voice-synthesizer`). The two
later tables (standards advisors/drafters and mechanical reporters, 43 agents) have no Role column
at all. Drafters fit neither A nor R as `advisor_role.md` defines them, which is probably why.

### F6. "Read-only" is a promise in prose for 25 global agents, not a restriction

25 of 74 global agents (and most repo-local reporters) hold the `Bash` tool. Their descriptions say
"read-only" or "never removes anything", but `Bash` is unrestricted: nothing technical stops
`worktree-sweep` from running `git worktree remove` or `vps-drift-checker` from writing over SSH.
The instruction text is the only guard. This matters more once agents run headless
(`claude --print --agent …`, the pattern ops-platform PR #12 uses), where no human sees a permission
prompt.

### F7. `pm-agent` is reported as added but is not

`SESSION_HANDOFF_2026-09-17-headless-pm-and-ops-infra.md` says `pm-agent` was "added to
`docs/AGENTS.md` roster". MasterThread PR #80 is still open; neither the file nor the row is on
main. The ops-platform reasoner (PR #12) depends on it.

### F8. The legacy `Agents/` tree is 608 files of unused template text

`Agents/{business,community,core,engineering,gameops}/` holds 76 persona/responsibilities/
io-contract folders, last touched 2026-09-11. No file outside `Agents/` and the archives refers to
it, none of it is loadable by Claude Code, and the sampled content is generic boilerplate
("Structured and consistent", "Calm and neutral in tone"). It shares names with real concepts
(`billing`, `invoicing`, `patreon_perks`), so a search for "the billing agent" lands on a spec for
something that was never built. `docs/AGENTS.md` calls itself "the single index of every subagent
definition" and does not mention this tree.

### F9. Duplicated repo-local definitions have no drift check

`mod-boot-test-runner` is copied into `aegis-mods`, `aegis-poi` and `aegis-pricing`;
`module-json-contract-checker` into two. Same failure shape as the vendored-validator drift
`vendored-validator-advisor` already found in site-chernarus. They match today only because they
were written in one round.

### F10. Headless readiness differs by agent and is not recorded anywhere

For the headless-agent work: agents whose tools are only `Read, Grep` (47 of the 74) or
read-only `gh`/`git` calls can run unattended under `claude --print --agent`. Agents that need an
OAuth MCP connector (`invoicer`, `job-intake` — QuickBooks and Drive) cannot, because a
non-interactive session cannot complete the connector sign-in. Agents that touch DPAPI key files
(`secret-rotation-auditor`, `discord-bot-key-age-reporter`, `ovh-vps-usage-reporter`) only work as
the Windows user who owns the keys, so not on the VPS. The roster has no column for any of this.

## Recommendations

Ordered by value for effort. None of these is done in this PR.

| # | Recommendation | Fixes | Size |
|---|---|---|---|
| R1 | Bring the three legal agents into `claude-agents/` through a normal PR, run `agent-automation-gatekeeper` on each first, and add their roster rows. Decide explicitly whether web access is acceptable for `legal-*`. | F1 | S |
| R2 | Correct the handymansfield rows: remove the three unmerged agents (or reopen PR #10 if they are still wanted), add `invoicer` and `job-intake`. | F2 | S |
| R3 | Resolve `rollout-plan-advisor`'s model one way or the other. | F3 | XS |
| R4 | Finish `generate_agents_md.py`: carry Role as a frontmatter field (`role: A|R|D`) so it can be generated rather than hand-kept, generate all global tables, and add a `--check` mode that fails when the roster and `claude-agents/` disagree. Run `--check` in MasterThread CI. | F3, F4, F5 | M |
| R5 | Add a third Role value for drafters (D) to `advisor_role.md`, then classify the remaining blank rows. | F5 | S |
| R6 | Add a small sync-check script (or extend `standards-stub-finder`'s sibling, a new haiku reporter) that diffs `~/.claude/agents/` against `claude-agents/` and lists local-only, repo-only and differing files. This audit did it by hand. | F1, F4 | S |
| R7 | For agents that hold `Bash` and claim read-only: where Claude Code permission rules allow it, ship a `permissions.deny` list for the destructive verbs alongside headless invocations (`git push`, `git worktree remove`, `rm`, `ssh … sudo`, `gh pr merge`), and record in the roster which agents are "read-only by instruction" versus "read-only by tool list". Start with the ones the headless PM will call. | F6 | M |
| R8 | Land or close PR #80, and correct the handoff's claim either way. | F7 | XS (owner merge) |
| R9 | Move `Agents/` to `archive/` (or delete it) and add one line to `docs/AGENTS.md` saying it was a pre-build template set, never implemented. | F8 | S |
| R10 | Move the two duplicated repo-local agents to global, or add them to whatever check R4/R6 produces. | F9 | S |
| R11 | Add a "Headless" column to the roster (yes / needs-connector / needs-local-keys) so the headless PM and any VPS runner know what they can call. | F10 | S |

R1–R3 and R8 are corrections to bring the record back in line with reality. R4 and R6 are the ones
that stop the same drift from coming back; without them this audit will need repeating.

## Method

- Global files: listed `~/.claude/agents/*.md`, read `name`/`model`/`tools` frontmatter from each.
- Roster: parsed agent/model pairs out of `origin/main:docs/AGENTS.md` (104 rows) and compared both
  directions.
- Mirror: byte-compared each live file with `origin/main:claude-agents/<name>.md`, ignoring CR.
- Repo-local: `git ls-tree` on every local clone's origin default branch for `.claude/agents/`.
- Grounding: extracted every `standards/…md` and `policies/…md` path the global agents cite and
  checked each exists with more than 5 lines on `origin/main` or in `_security-public`; then read
  how the agents citing a stub handle it.
- PR states via `gh pr view` / `gh pr list` at audit time.

Not covered: whether each agent's instructions are good (no agent was run), repo-local agents in
unmerged worktrees other than handymansfield's, and cloud/remote agent definitions if any exist.
