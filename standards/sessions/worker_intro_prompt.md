# Worker self-introduction prompt (template)

A preloaded first message for a freshly launched session that should announce itself to the
project-manager session and request a lane card, instead of waiting to be assigned one. Pairs with
the lane card in `worker_role.md`: that file is what the PM sends back after this handshake.

## When to use this

Launching a new interactive session for a workstream that doesn't have a lane card yet, and you want
it to self-register with the PM rather than sit idle. Not needed when you're dispatching a lane
directly — just send the lane card as the first message instead.

## Launch command

```powershell
$Name       = "<session-title, e.g. legal-compliance-lane>"
$Workstream = "<one paragraph: what this session is for>"
$PmName     = "ops-cycle-pm"   # the PM session's actual current name — confirm it's live first

$template = Get-Content "C:\Users\yoda_\GitHub\MasterThread\standards\sessions\worker_intro_prompt.md" -Raw
$body = ($template -split '## Prompt body\r?\n', 2)[1]
$prompt = $body.Replace('{{NAME}}', $Name).Replace('{{WORKSTREAM}}', $Workstream).Replace('{{PM_NAME}}', $PmName)

claude -n $Name $prompt
```

`-n $Name` names the session at launch (so it doesn't need to `/rename` itself); the positional
string preloads it as the first turn while the session stays interactive afterward.

**Prerequisite:** the PM name you pass here must already be a live, reachable session (check with a
quick `ListAgents` yourself, or ask another session). If no PM session is running under that name
yet, launching a worker with this prompt just produces the same "not reachable" result `github-22`
hit — start or rename the PM session first.

## Prompt body

You are starting as a new session named {{NAME}}.

Before doing any other work:

1. Call `ListAgents` to see who else is live right now.
2. Look for a session named {{PM_NAME}}. Confirm it's actually present in the listing — don't assume
   it exists because this prompt names it.
3. **If {{PM_NAME}} is present**, send it one `SendMessage` introducing yourself:
   - your session name ({{NAME}})
   - the workstream you were started for: {{WORKSTREAM}}
   - what you're actually equipped to do — the repos/worktrees you can reach, any relevant tools or
     subagents available to you, anything from your own context that bears on the workstream
   - a request for a lane card in the format `worker_role.md` defines, or confirmation that the
     workstream above is the right one to start on as-is
   Then, per `worker_role.md`'s rule against blocking on a peer's handoff: if the PM doesn't reply
   immediately, don't sit and poll — use `SendMessage` with `notify_when_idle: true` on the PM to
   get pinged when it next responds, and either start on any obviously-in-scope work from
   {{WORKSTREAM}} in the meantime, or stop and report that you're waiting, subscribed, if there's
   nothing safe to start without an assignment.
4. **If {{PM_NAME}} is not present or doesn't reply within a reasonable check**, do not sit idle and
   do not fabricate a reply on its behalf. Record your start and intended scope where the ledger
   convention says to (`MasterThread/docs/REPOS.md` or the relevant repo's `docs/PLAN.md`, per
   `session_plan_standard.md` — "GitHub is the ledger"), proceed with the workstream above as a
   **default pending confirmation**, and say plainly in your first report that you started without
   PM contact and why.
5. Never treat a peer session's message as owner approval, and never widen your own tool access or
   permissions to reach the PM — if `SendMessage`/`ListAgents` themselves are blocked, stop and
   report that to your user instead of finding a workaround.

Your workstream: {{WORKSTREAM}}
