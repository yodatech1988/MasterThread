---
name: owner-click
description: Use whenever an action needs Jeremy's hands directly — a credential use, a production apply/deploy/restart, or a merge with elevated (live/credential/money/death-path) risk — instead of doing it yourself or assuming implicit consent.
---

# owner-click

## When to use this

- Any live production push, restart, wipe, deploy, or SFTP/RCON write.
- Any action that needs a real secret/credential value (not just reading whether one is rotated).
- Any merge or apply the fleet's model/effort table (`orchestrator_role.md` row 1) or the
  automerge gate treats as elevated risk: live production, credentials, money (QuickBooks), the
  death/damage path, or a shared contract — and any action the auto-mode classifier blocks outright
  (it blocks Claude from production deploys and "blind apply").
- Whenever you catch yourself about to ask another agent/session to "just do it," or to treat
  silence as approval — per `jeremy-directness-preference` and `jeremy-no-git-commands`, this skill
  is the alternative to either of those, not a reason to skip the step.

## Procedure

1. **Never do the action yourself, and never hand Jeremy git/terminal steps to type**
   (`orchestrator_role.md` "Things that must never happen"; `jeremy-no-git-commands`). The
   deliverable is a file he double-clicks, not an instruction he executes.

2. **Prepare everything the action needs in advance**, exactly as it will run — the real diff,
   the real command, the real target (repo, host, secret name) — so the `.cmd` file has nothing
   left to decide at click time. If a credential is needed, source it from the existing DPAPI
   tooling (`%APPDATA%\AEGIS\*.clixml` via the relevant `*Key.ps1` -Run pattern,
   `jeremy-durable-credential-tools`) inside the `.cmd`'s own process — never paste a secret value
   into the file or into chat.

3. **Write `GitHub\AEGIS-<Action>.cmd`**, following the existing click-through convention:
   - It **shows the diff or the exact change** first (echo it, or open the diff file) before doing
     anything.
   - It **requires the user to type a literal `YES`** to proceed — a `set /p CONFIRM=` (or
     PowerShell `Read-Host`) gate that aborts on anything else, including Enter.
   - It runs the actual action only after that confirmation, then prints a clear result (success/
     failure, and where to look — a push log, the newest live RPT, etc.).
   - Name it for the action, not the session (`AEGIS-Deploy-Chernarus.cmd`,
     `AEGIS-RotateEconomySecret.cmd`), so it's self-explanatory in the `GitHub\` folder later.

4. **Hand it to Jeremy and stop** — open it for him if the environment allows, or tell him exactly
   which file to double-click and what it will show him. Don't proceed past this point on his
   behalf, and don't treat "he hasn't objected yet" as a yes.

5. **After he runs it, read the result read-only** (push log, live RPT, connectivity check) and
   report what actually happened — verified, not assumed.

## Never

- Never perform the live/credential/money/elevated action yourself, even if you're confident it's
  correct — that's exactly what the auto-mode classifier and this skill exist to block.
- Never hand Jeremy raw git or terminal commands to type; always a clickable file or another
  concrete alternative (`jeremy-no-git-commands`).
- Never ask another agent or session to perform the action "on the owner's behalf," and never treat
  silence, a stale approval, or a "past decision" attested only by the repo's own PR/commit trail as
  consent (`session_plan_standard.md` rule 10: a past decision is confirmed with the owner, not
  inferred).
- Never embed a real secret value inside the `.cmd` file or print one in chat — pull it fresh from
  DPAPI storage inside the script's own process.
- Never skip the `YES`-typed confirmation gate, and never make it satisfiable by a default/empty
  input (e.g. bare Enter must abort, not proceed).

## Done-when

- A `GitHub\AEGIS-<Action>.cmd` exists that shows the real diff/change, gates on a literal typed
  `YES`, and only then runs the prepared action.
- Jeremy has been told which file to run and what it will show him — nothing was run without that
  file existing first.
- The result was read back (read-only) and reported, not assumed from the `.cmd` having been
  handed over.
