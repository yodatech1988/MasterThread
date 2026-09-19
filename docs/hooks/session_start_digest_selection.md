# SessionStart hook: digest vs full orchestrator_role.md

Owner decision `anthropic-audit-01`: "Digest for all + full file for PM/orchestrator only."

## Rule
- Default (every session): inject `standards/sessions/orchestrator_role_digest.md` (~5KB).
- PM or orchestrator: inject the full `standards/sessions/orchestrator_role.md` (~35KB).
- Safety fallback: if the digest is missing or empty on `origin/main`, inject the full file, so the
  hook is safe to change before the digest PR merges.

## How the hook knows the role
The hook runs before the session has a role, so it cannot read one from the conversation. Proposed
signal: the environment variable `AEGIS_SESSION_ROLE`, set to `pm` or `orchestrator` by whoever
launches a PM or orchestrator session. Unset or any other value means a normal session.

Limits, stated plainly:
- A session that becomes PM mid-session (owner takeover) started with the digest. The digest tells it
  to read the full file on becoming PM or orchestrator, so it recovers by one `git show`.
- Nothing in this repo sets `AEGIS_SESSION_ROLE` today; the launcher that sets it is not built.
  Until it is, every session gets the digest and PM/orchestrator sessions rely on that pointer.
- Fleet Status is not readable from a bash hook, so it is not used as the signal.

The exact proposed hook command is in the PR body and in `GitHub\PM_INBOX\lane-A-card01-hook-change.md`.
This PR does not edit any settings file; applying the hook change is an owner click.
