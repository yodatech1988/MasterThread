---
name: bootstrap-new-repo
description: Use when a repo was just created from repo-template (or an existing repo is still carrying repo-template's stub CLAUDE.md/README.md/docs/PLAN.md placeholders) and needs turning into a working repo — branch protection, filled stubs, the CI secrets the pipeline silently no-ops without, and a real CI check job.
---

# bootstrap-new-repo

## When to use this

- Right after `gh repo create --template yodatech1988/repo-template <owner>/<repo>` (or the
  "Use this template" button on GitHub).
- Any time a repo's `CLAUDE.md`, `README.md`, or `docs/PLAN.md` still reads exactly like
  `repo-template`'s own copies (`<repo>`/`<command>` placeholders, "Plan: not written yet") — the
  repo was created but never bootstrapped.
- Not for a repo that already has a filled `CLAUDE.md` and a real `docs/PLAN.md` — that repo is
  past this step even if branch protection or a secret still needs checking separately.

## Procedure

1. **Resolve the real default branch first, never assume `main`.**
   `gh repo view <owner>/<repo> --json defaultBranchRef --jq .defaultBranchRef.name`.
   `repo-template` itself defaults to `master`; its own `scripts/setup-branch-protection.sh` reads
   this live rather than hardcoding it, for the same reason (`session_plan_standard.md` rule 9).

2. **Branch protection is an owner-only repo-security-setting change — route it, don't run it.**
   `repo-template/scripts/setup-branch-protection.sh <owner>/<repo>` (`gh api --method PUT
   repos/<owner>/<repo>/branches/<branch>/protection`, requiring the `check` status context,
   `enforce_admins`, no force-push/deletion) is the exact, already-written command. Per
   `skills/owner-click/SKILL.md`, wrap it — don't hand it to the owner to type — in
   `GitHub\AEGIS-SetupBranchProtection-<repo>.cmd`: show the repo/branch and the settings it will
   apply, gate on a typed `YES`, then run the script. After the owner runs it, read back
   `gh api repos/<owner>/<repo>/branches/<branch>/protection` to confirm it applied — don't assume
   from the click alone.

3. **CI secrets are credential values — the session never handles them, but it does name exactly
   which ones and why, and routes each through the same click-file pattern.**
   - `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` — `pr-review.yml` calls
     `core/.github/workflows/claude-review.yml` with `secrets: inherit`; without one of these two,
     that workflow no-ops visibly rather than failing (`repo-template/README.md` and
     `.github/workflows/pr-review.yml`'s own comment, confirmed live: `payments`' repo secret list
     currently holds only `CLAUDE_CODE_OAUTH_TOKEN`, nothing else).
   - `DISCORD_WEBHOOK_DEVLOG` — **conditional, not a default step.** `repo-template`'s own
     `.github/workflows/ci.yml` has no Discord notify step at all (verified by reading its content
     directly); the "no-ops without `DISCORD_WEBHOOK_DEVLOG`" pattern lives in
     `claude-agents/docs/ops/DISCORD-NOTIFICATIONS.md`, a different repo's `ci.yml` with a devlog
     step this template doesn't ship. Only add this secret (and the matching notify step) if the
     new repo is deliberately adopting that pattern — don't set it by default off this skill.
   - For each secret that does apply: `GitHub\AEGIS-SetSecret-<repo>-<name>.cmd` that states the
     repo, the secret name, and what it's for, gates on typed `YES`, then runs
     `gh secret set <NAME> --repo <owner>/<repo>` and lets the owner paste the value at that live
     prompt — the `.cmd` file itself never contains or receives the value. Bundle all of a new
     repo's secret prompts into one file with one `YES` gate if that's less friction than several
     separate clicks; the owner still types the value at each interactive prompt.

4. **Fill the stub placeholders — this is session-side work, done as a normal PR.** Per
   `session_plan_standard.md` rules 1/9: `git fetch origin`, `git worktree add
   ../_wt-<repo>-bootstrap -b agent/<repo>/bootstrap origin/<default>`, then in that worktree:
   - `CLAUDE.md` — replace `<repo>` with the real repo name and `<command>` with the project's real
     test command (check `package.json`/`pyproject.toml`/etc. for what that is; if genuinely
     unknown yet, write `TODO: needs owner input` rather than guessing).
   - `.github/workflows/ci.yml` — replace the `check` job's `- run: echo "no checks configured
     yet"` stub with the real lint/build/test invocation, same command as `CLAUDE.md`'s `Tests:`
     line so they can't drift apart. Keep the job id `check` — branch protection's required status
     context (step 2) is literally the string `check`, and renaming the job breaks the gate
     silently.
   - `docs/PLAN.md` and `README.md` — leave the `docs/PLAN.md` placeholder in place *except* for
     confirming the goal paragraph is either filled or explicitly still `<owner: one paragraph>`;
     don't invent a plan here (step 5). Only fix `README.md` if it's still the literal
     `repo-template` copy (as found live in `payments`, see Stop conditions).
   - Open the PR, then hand it to `skills/land-pr/SKILL.md` for review/merge — default reviewer
     `diff-reviewer`, not `live-reviewer` (this isn't live/credential/money/death-path/contract
     scope).

5. **Session 0 planning is not built into this skill.** Once the stub PR above is merged, the next
   step is Session 0 exactly as `standards/sessions/session_plan_standard.md` rule 8 and
   `standards/sessions/PLAN_template.md` define it: read the README and open issue/PR *titles*
   only (no repo-wide survey), then replace `docs/PLAN.md` using the template. Hand that off to the
   `session-plan-drafter` agent (`docs/AGENTS.md`) to produce the draft, and
   `session-plan-advisor` to check it against `PLAN_template.md` before it's relied on for
   dispatch. `"plan-session"` is not an approved skill — don't build planning logic here or invoke
   anything by that name.

6. **gh-federation allow-list enrolment — only if the new repo needs another repo's bot to write to
   it (`gh-federation/README.md`'s pull-queue design).** This is owner-provisioned Worker
   configuration (a per-caller secret in the `gh-federation` Worker, not this repo), out of scope
   for this skill. If a lane determines it's needed, name it as a stop condition (step below), not
   a step this skill executes.

## Stop conditions

- Branch protection and any `gh secret set` are never run directly by the session — always the
  `.cmd`-file pattern in step 2/3, never a raw command handed to the owner to type.
- If `CLAUDE.md`'s real test command can't be determined from the repo's own manifest, write `TODO:
  needs owner input` rather than guessing one.
- Do not write `docs/PLAN.md`'s actual plan content from this skill — that's Session 0's job via
  `session-plan-drafter`, not this skill's.
- Do not attempt gh-federation allow-list enrolment — flag it as a follow-up needing the owner's
  Worker-config action instead.
- **Known live finding, report only, do not fix here:** `payments` (`origin/master`) still carries
  `repo-template`'s literal `CLAUDE.md`, `README.md`, and `docs/PLAN.md` unmodified, though its
  branch protection is applied and `CLAUDE_CODE_OAUTH_TOKEN` is already set. It's an unfilled
  template that this skill's steps 3-5 would resolve, but doing so is a separate dispatch, not a
  side effect of building this skill.
- If the repo's default branch can't be resolved (`gh repo view` fails, repo not found, no push
  access), stop and surface that rather than guessing `main` or `master`.

## Grounded in

- `repo-template` `origin/master`: `README.md` ("What's included", "After creating a repo from
  this template"), `CLAUDE.md`, `docs/PLAN.md`, `scripts/setup-branch-protection.sh`,
  `.github/workflows/ci.yml`, `.github/workflows/pr-review.yml` — all read directly via `gh api
  repos/yodatech1988/repo-template/contents/<path>` against the live default branch (`master`, not
  `main`).
- `payments` `origin/master`: `CLAUDE.md`, `README.md`, `docs/PLAN.md` (confirmed still identical
  to `repo-template`'s stubs), `branches/master/protection` (confirmed applied), `actions/secrets`
  (confirmed only `CLAUDE_CODE_OAUTH_TOKEN` present) — read live via `gh api`.
- `gh-federation`, `claude-session-archive`, `jarvis` `CLAUDE.md` (`gh api ... /contents/CLAUDE.md`)
  — confirmed already filled in, not unbootstrapped.
- `claude-agents/docs/ops/DISCORD-NOTIFICATIONS.md` (`gh api`) — the actual source of the
  `DISCORD_WEBHOOK_DEVLOG` no-op pattern; confirmed it belongs to a `ci.yml` shape `repo-template`
  does not ship, hence step 3's "conditional, not default".
- `gh-federation/README.md` (`gh api`) — pull-queue design, confirms allow-list enrolment is
  Worker-side config, not a repo setting this skill can apply.
- `MasterThread` `origin/main`: `standards/sessions/session_plan_standard.md` (rules 1, 8, 9) for
  worktree/branch/PR convention and Session 0's no-survey rule; `docs/AGENTS.md` for
  `session-plan-drafter` and `session-plan-advisor`; `skills/land-pr/SKILL.md` and
  `skills/owner-click/SKILL.md` for the review-routing and click-file conventions this skill
  follows.
