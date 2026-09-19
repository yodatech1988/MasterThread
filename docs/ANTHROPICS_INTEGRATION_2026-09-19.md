# Anthropics repos integration: decision record (2026-09-19)

Where the owner's decisions on the `github.com/anthropics` review live, and what each lane
produced. Written by session github-49. It is a snapshot; live state is in the linked issues and
PRs, which win on any disagreement.

## Outcome of the review

84 repos reviewed, 7 shortlisted (skills, claude-agent-sdk-python, claude-agent-sdk-demos,
claude-code-action, claude-cookbooks, claude-plugins-official, sandbox-runtime). Verdict: copy
patterns, install nothing third-party; sandbox-runtime is adoptable on Linux only. The review was
agent-read only; nothing was executed at review time.

## Owner decisions (Decision Queue, read from the store, not a peer's relay)

| Card | Answer | Effect |
|---|---|---|
| review-anthropics-1 (skills, claude-agents#33) | Approve, start when a session is free | Lane 1 |
| review-anthropics-2 (evals, claude-agents#34) | Approve, after the skills program | Lane 2, gated on lane 1 |
| review-anthropics-3 (SDK, claude-agents#35) | Approve, run the experiment | Lane 3 |
| review-anthropics-4 (core#93) | Pattern copy only, no trial | Lane 4A; trial (4B) dropped |
| review-anthropics-5 (ops-infra#40) | Trial on a non-production Linux box only | Lane 5 |
| anthropics-6 | Owner merges core#94 himself | No non-author merge |
| anthropics-7 | vault-dev | Superseded by anthropics-9 |
| anthropics-8 | Re-scope skills lane to MasterThread, compare by reading only, no local install | Lane 1 re-run |
| anthropics-9 | Use a throwaway local Linux VM | Lane 5 target changes |

## Lane results

| Lane | Result | Evidence |
|---|---|---|
| 1 skills | Merged | MasterThread#131: one skill (`skills/architecture-doc-rubric`), two thin wrapper agents. Behaviour comparison was read-only reasoning, so simulated, not tested. |
| 2 evals | In progress when written | claude-agents#34 |
| 3 SDK experiment | Done, billing check inconclusive | Comment on claude-agents#35 |
| 4A pattern copy | PR open, owner-merge | core#94; automerge section byte-identical to main (sha256 checked) |
| 4B Action trial | Dropped | Owner answer |
| 5 srt trial | Stopped, target changed | vault-dev lacks Node, bubblewrap, socat, ripgrep and has the AppArmor user-namespace restriction on; nothing was installed. Now waits on an owner-created throwaway VM. |

## Facts worth keeping

- **Advisor/drafter pairs live in MasterThread `claude-agents/`** (39 files on origin/main), not
  in the claude-agents repo, whose `.claude/agents/` holds six unrelated agents. The lane card
  assumed otherwise and the first worker stopped. Rule candidate: a lane card names the repo that
  holds the artifact and cites `git ls-tree origin/<default>`.
- **claude-agents' default branch is `master`.**
- **SDK finding:** a run through claude-agent-sdk inherited about 150 MCP tools and
  `disallowed_tools` did not remove them, so a read-only SDK run needs an explicit allow-list.
  Reported by the lane 3 worker, from one run.
- **Unverified:** whether `CLAUDE_CODE_OAUTH_TOKEN` is accepted by the SDK; whether an env API key
  would override OAuth; Anthropic's terms on subscription use through the SDK; whether
  `claude-sonnet-5` is a valid `--model` value in core#94; whether srt works under vault-dev's
  AppArmor setting.
- Issue #33's "0 skills" premise was stale: `skills/` already held five skills (PR #57).

## Open

- Merge core#94 (owner).
- Lane 2 PR, when it exists (owner merge).
- Lane 5 in a throwaway VM (owner creates it; scope in the PM's action card).
- Sync `~/.claude/agents` after #131 per `claude-agents/SYNC.md` (PM card).
