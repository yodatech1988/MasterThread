# Skills (Tier-1, batch 1)

Procedures a session loads into its own context and runs itself — distinct from the 70 read-only
advisor/reviewer subagents in `docs/AGENTS.md`, which only grade work after the fact. The owner
approved exactly these 5 Tier-1 skills, in this order, to close the gap that let 6 real incidents
happen with zero skills in place (a `--force` worktree removal that lost uncommitted work, a
session collision from two lanes racing the same repo, a push onto an already-merged PR, a
stacked-PR mis-merge, a corrupted secret, and a skipped usage watcher).

| Skill | Purpose |
|---|---|
| [`round-start`](round-start/SKILL.md) | Arms the usage watcher, re-verifies the ledger against live `gh` state, triages/sizes the backlog, and produces a dispatch plan — the first thing an orchestrator/PM round does. |
| [`dispatch-lane`](dispatch-lane/SKILL.md) | Collision-checks, creates the lane's isolated worktree in-process, and emits a properly formatted lane card before handing work to a worker. |
| [`land-pr`](land-pr/SKILL.md) | Re-checks live PR state before every push, routes review to the correct reviewer agent by scope, verifies a stacked-PR merge really landed on `main`, and updates `docs/PLAN.md`. |
| [`owner-click`](owner-click/SKILL.md) | Packages any action that needs Jeremy's hands — a credential, a production apply, an elevated-risk merge — as a double-click `.cmd` that shows the change and requires a typed `YES`. |
| [`round-closeout`](round-closeout/SKILL.md) | Writes the next `SESSION_HANDOFF_*.md`, refreshes stale ledger/memory facts, promotes seen-twice lessons, and emits the next round's launch prompts with model/effort rows. |

## Not approved for this batch

These 9 skills were scoped during the same review but **not** approved — their absence here is
deliberate, not an oversight. Do not build them without a fresh owner sign-off:

- `go-live`
- `boot-test`
- `secret-rotate`
- `plan-session`
- `deliver-lane`
- `verify-against-origin`
- `mod-review`
- `econ-change`
- `new-agent`

See `docs/LESSONS.md` for the running lessons-learned ledger that feeds future skill/standard
promotions.

## Added after batch 1

| Skill | Purpose |
|---|---|
| [`architecture-doc-rubric`](architecture-doc-rubric/SKILL.md) | The seven-section rubric from `architecture_doc_standard.md`, shared by the `architecture-doc-advisor` and `architecture-doc-drafter` agents (now thin wrappers). Owner re-scoped issue claude-agents#33 to this repo on 2026-09-19; it is a pilot for one pair, not a program expansion. |

## Batch 2: estate review, 2026-09-22

Found by a read-only review of every repo, the workspace handoffs, and past session transcripts, looking for multi-step procedures that sessions repeat by hand. Every skill was built from files read on `origin/<default>` and checked by a separate reviewer. Anything live, credential, secret, repo-security or merge-related is routed to [`owner-click`](owner-click/SKILL.md) or a Decision Queue card; no skill here performs it.

| Skill | Purpose |
|---|---|
| [`file-decision-card`](file-decision-card/SKILL.md) | Files one owner decision or action per Ops Decision Queue card in the shape `decision_queue_standard.md` requires, with a recommendation, and never resolves it. |
| [`revendor-core-sync`](revendor-core-sync/SKILL.md) | Reconciles drift between core's `sync/` and a site repo's vendored copy, re-vendors, tests, and lands it before `CORE_READ_TOKEN` is touched. |
| [`workshop-publish-module`](workshop-publish-module/SKILL.md) | Takes a Workshop module from boot test and build to a staged publish; the owner runs `publish.ps1`. Then records the workshopId and updates the site mod tracker. |
| [`session-cost-audit`](session-cost-audit/SKILL.md) | Answers "what did this cost" with `tools/cost-monitor` and `tools/cost-steward`, never a naive tally or a guessed rate. |
| [`derive-headless-allowlist`](derive-headless-allowlist/SKILL.md) | Derives and live-proves the exact tool grant a headless agent needs, and proposes it by PR without editing any settings file. |
| [`repair-phantom-staged-worktree`](repair-phantom-staged-worktree/SKILL.md) | Diagnoses the "hundreds of staged files, unborn branch" worktree symptom and repairs it with a zero-content `git update-ref`; includes a read-only `diagnose.ps1`. |
| [`prove-it-can-fail`](prove-it-can-fail/SKILL.md) | Operationalises the LESSONS rule that every negative test needs a positive control: a test, gate, watcher or deny rule must be shown to fail before it counts. |
| [`ops-policies-add-policy`](ops-policies-add-policy/SKILL.md) | Adds a normative YAML file or Rego rule to ops-policies per `docs/CONVENTIONS.md`, avoiding its two recorded silent-allow bugs; excludes `make go-live`. |
| [`apply-db-migration`](apply-db-migration/SKILL.md) | Applies a merged migration to the economy, community or ops MySQL database via an owner click, then verifies with that schema's own status check and audit views. |
| [`bootstrap-new-repo`](bootstrap-new-repo/SKILL.md) | Turns a repo made from repo-template into a working repo; branch protection and secrets go to the owner, and Session 0 goes to the existing planning agents. |

None of these rebuilds a skill from the not-approved list above. Candidates reviewed and rejected: reputation wipe (draft, marked do-not-run), restart backup (research only), canon merge (go-live overlap), deploy-loot fallback, VPS runner onboarding (already scripted), website page add, be-rcon submodule bump, ops-infra drills (owner-gated and scripted), release signing, and secret rotation (not approved).
