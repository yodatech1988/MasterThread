# pr-digest

PC-local, read-only-first half of the PR/CI digest work approved via the Ops Decision Queue on
2026-09-26 (`cost-monitor-pr-digest-vps-federated-2026-09-26` option 0,
`cost-monitor-behind-pr-updater-writes-2026-09-26` option 0). Background:
`PM_INBOX\cost-monitor\SELF_IMPROVEMENT_PLAN_2026-09-26.md` section R3.

Uses only `gh` and whatever `gh auth status` already provides on this machine -- no new token, no
secret, no VPS. **The VPS deployment with a federated GitHub App credential named in card
`cost-monitor-pr-digest-vps-federated-2026-09-26` is explicitly out of scope here** and needs the
owner to provision that credential; it is not attempted or scaffolded by anything in this folder.
Nothing in this folder is registered with Task Scheduler, `cron`, or any other scheduler -- that is
a separate follow-up after review.

## Get-PrDigest.ps1

Sweeps open PRs across a configurable repo list (`config.json`), writes `pr-digest.json` (state,
draft, mergeStateStatus, checks rollup, head sha, age, and the `stuck` / `ciFailure` / `noCiRun` /
`rule4Violation` flags -- the same flag rules `claude-agents\pr-state-sweep.md` already defines),
and appends one line per state transition to a change log a `Monitor tail -F` can watch, in the
shape `tools\owner-wait-watch.sh` already uses. Read-only. See the script's own comment-based help
(`Get-Help .\Get-PrDigest.ps1 -Full`) for every parameter, in particular the mandatory `-StateDir`
test seam -- never point a test at the real default path.

## Update-BehindPrs.ps1

For PRs where `mergeStateStatus == BEHIND`, the repo is not in `owner_only_repos` (personal/
financial, per `aegis-automerge-policy`), and the same `github-actions[bot]` review verdict
`core/.github/workflows/claude-review.yml`'s own automerge job requires (`APPROVED` on the current
head commit, body carries `AUTOMERGE: eligible`) is present, calls
`gh api -X PUT repos/{owner}/{repo}/pulls/{n}/update-branch`. On a real conflict (HTTP 422) it only
reports the conflict -- conflict resolution is explicitly out of scope (Decision Queue card option
0). **Defaults to dry run** (`-Execute` is required to actually call the API) and has not been run
with `-Execute` against a real PR; that verification is left to whoever adopts this for real use.

## Status

Both scripts were exercised read-only against real repos on 2026-09-26 (`gh auth status` already
authenticated as `yodatech1988`): the digest correctly reported MasterThread's and services' open
PRs including the `services` rule-4 violation (#112 and #109 both `agent/`-prefixed) and services
PR #109's real `BEHIND` state; the updater correctly skipped #109 (no `github-actions[bot]` review
on its head commit yet) and correctly refused to touch `jarvis` (owner-only). No real PR was
updated or merged by any of this testing.
