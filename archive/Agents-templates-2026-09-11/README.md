# Agents/ template tree — archived 2026-09-17

This is the former top-level `Agents/` directory: 608 files across 76 agent "spec" folders under
`business/`, `community/`, `core/`, `engineering/`, and `gameops/`, each with a standard
`persona.md`, `responsibilities.md`, `escalation_rules.md`, `io_contract.json`,
`dependencies.md`, `notes.md`, and `examples/` pair. Last touched 2026-09-11.

## What this is

A planning template, not a built system. Every folder sampled across all five domains (13+
checked, including `business/billing`, `business/invoicing`, `business/patreon_perks`,
`community/abuse_watch`, `community/lore`, `community/fraud_watch`, `core/architect`,
`core/risk`, `engineering/code_generator`, `engineering/sow_drafting`, `gameops/economy_dayz`,
`gameops/dayz_perk_applier`, `gameops/schema_designer`) contains identical boilerplate text with
only the agent name and domain swapped in — no real schemas, no real policy decisions, no
distinguishing content. None of it is loadable by Claude Code; there is no runtime, harness, or
tool config anywhere in the tree that would let any of these specs actually execute.

## Why it moved

MasterThread PR #84 (audit finding F8 / recommendation R9) flagged this tree: because the folder
names collide with real concepts the org actually has (`billing`, `invoicing`, `patreon_perks`,
etc.), a search for one of those terms lands on a generic template for something that was never
built, instead of the real thing. The owner approved acting on the audit's recommendations. This
archive is that action: move the dead tree out of the live path so it stops shadowing real work,
while keeping the content in git history rather than deleting it.

## Where the real agents live

- `claude-agents/` — the actual agent definitions (source of truth per `claude-agents/SYNC.md`),
  synced to `~/.claude/agents/` on machines that run sessions for this org.
- `docs/AGENTS.md` — the generated index of what's actually built and available, by scope
  (global, MasterThread-local, repo-local).

## Pulling a spec back out

If one of these folders is ever actually turned into a real, built agent, its spec can be pulled
back out with a normal `git mv` (or by copying its content into a new `claude-agents/<name>.md`
per that directory's format) — nothing here is deleted, only relocated.
