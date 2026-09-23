---
name: prove-it-can-fail
description: Use when a session is about to trust a new or changed test, gate, watcher, deny rule, or backup/safety check — before relying on its pass, construct a genuine failure case it must catch, run a positive control, and confirm the mechanism (not a side effect) caused the result.
---

# prove-it-can-fail

## When to use this

- Before trusting a newly built or newly changed **test, CI gate, watcher, permission deny rule, or
  backup/safety protection** anywhere in the estate.
- Before relaying a check's "pass" as evidence to the owner, a Decision Queue card, or another
  session — a green result you have not stress-tested this way is a claim, not evidence.
- For deriving a headless permission allowlist specifically, use the sibling skill
  `derive-headless-allowlist` instead — it applies this same method to allow/deny permission
  patterns and their own worked precedence cases. This skill stays general; it does not duplicate
  that one's pattern-syntax detail.

## Procedure

1. **State the exact success signal.** Write down, precisely, what the check reports on a pass
   (an exit code, a specific log line, a specific HTTP status, a specific JSON field) — not "it
   worked."

2. **Ask what failure would look like, and check it's distinguishable.** If the failure case would
   produce the *same* observable signal as success, the check proves nothing yet — per the
   diagnostic question this method is built on: *"What would I observe if this had failed? If the
   answer is the same thing I'm observing now, I have no evidence."*
   (`C:\Users\yoda_\GitHub\POSTMORTEM_2026-09-18_EVIDENCE_THAT_ISNT.md` Part 1, "The diagnostic
   question.")

3. **Build a real failure scenario that reaches the real logic** — not a malformed input that fails
   early, before the mechanism under test is even exercised. The canonical trap: a `restic forget`
   probe with no policy flag exits non-zero *before contacting the repository at all*, so it "proves"
   append-only enforcement against a plainly writable server. Fix by reaching the actual guarded
   resource (forget by explicit snapshot id) and requiring the *target's own* rejection (its real
   HTTP 403), not just "some non-zero exit."
   (`C:\Users\yoda_\GitHub\LESSONS_2026-09-17_restic-and-review-gate.md` §3; mirrored at
   `docs/LESSONS.md` on origin/main, "A test that cannot fail is worse than no test — and mine
   couldn't.")

4. **Run a positive control: the identical operation with the protection absent**, and require it to
   behave differently (succeed where the protected case failed, or vice versa). Do this every time,
   not only when the negative result looks surprising.
   - This is the estate's stated rule, verbatim: **"Every negative test needs a positive control"**
     (`docs/LESSONS.md` on origin/main, dated 2026-09-17: "always pair a negative test with a
     positive control that must succeed... An inconclusive result must fail, not pass, whenever the
     test's job is to sign something off.") This skill operationalises that rule; it does not
     redefine it — if this file and `docs/LESSONS.md` ever disagree, `docs/LESSONS.md` (or wherever
     that rule is promoted to, per its own "not yet promoted" note pointing at
     `standards/sessions/worker_role.md`'s "Tests and validators" paragraph) wins.
   - Worked example for a deny rule: a permission deny-rule was verified with **four headless runs
     against a harmless analogue** (e.g. `git log` in a throwaway directory — nothing merged, no real
     repo touched), and a **control run with allow-only** confirmed the positive-case denial was the
     deny rule doing the work, not an artefact of something else.
     (`C:\Users\yoda_\GitHub\POSTMORTEM_2026-09-18_EVIDENCE_THAT_ISNT.md` §2.4.)

5. **Confirm the mechanism, not a side effect, caused the result.** Find the tool's own output
   signature rather than trusting a string the job prints unconditionally (a prompt template, a usage
   banner, and real output can all look identical at a glance) — the existing `gate-execution-auditor`
   agent (`docs/AGENTS.md`) does exactly this for CI gates specifically; reuse it rather than
   re-deriving the check by hand when the target is a CI gate. For a watcher/state-file check, verify
   the field you're rewriting to simulate failure is the *actual* field the watcher reads — a usage
   watcher test that rewrote top-level JSON keys while the real percentages were nested never
   triggered the watcher at all, and "passed" undetected until re-examined.
   (`C:\Users\yoda_\GitHub\POSTMORTEM_2026-09-18_EVIDENCE_THAT_ISNT.md` Part 6 item 1.)

6. **Record the failure-case evidence alongside the pass** — the exact command/probe run, its
   observed output, and the positive control's output — in the PR body, the lesson file, or wherever
   the check's own "done" evidence lives. A pass with no recorded failure case is not reusable proof
   for the next session; it is a claim resting on this session's memory.

7. **Route what you find:**
   - If the check is sound: land it normally (`land-pr` for the PR carrying it; `diff-reviewer` by
     default, `live-reviewer` only for live/credential/money/death-path/contract scope, per
     `docs/AGENTS.md` and `land-pr`'s own routing step).
   - If the check is broken (proves nothing, or the failure case is indistinguishable from success):
     do not ship it as evidence. Fix the check itself using the same procedure (steps 1-4 again on
     the fixed version) before it is relied on anywhere.
   - If fixing it requires touching live production, a credential, money, or a repo security
     setting: stop and route to `owner-click` or a Decision Queue card — this skill never performs
     that action itself (see Stop conditions).

## Stop conditions

- **Never run the failure probe against a live/production target, a real credential, money
  (QuickBooks), or the death/damage path** to "prove" a check — construct the failure against a
  throwaway/harmless analogue instead (a scratch directory, a throwaway probe snapshot deleted only
  by its own id, a disposable branch). Probe destructively without being destructive: write a
  throwaway probe artifact and try to delete only that, so a bad answer costs a few bytes, not the
  protected resource. (`LESSONS_2026-09-17...md` §4.)
- **If constructing a genuine failure case would itself require an owner-only action** (a live
  production change, a credential value, a repo security-setting change) — stop and hand it to
  `owner-click` or file a Decision Queue card per `decision_queue_standard.md`; do not simulate
  around the restriction to get a result faster.
- **If the failure case and success case are indistinguishable and you cannot find a way to make them
  differ** — stop and say so explicitly (to the owner or in the PR/lesson record) rather than shipping
  the check as "verified." An inconclusive result must be reported as inconclusive, never as a pass.
- **If this procedure surfaces that an existing, already-shipped check is broken** (not just the one
  you're building) — do not silently patch it as a side task; that is adjacent-scope creep. Report it
  (a lesson entry, a card, or to whoever owns that check) and get it explicitly assigned, per
  `worker_role.md`'s "Scope — adjacency is not authority."

## Grounded in

- `C:\Users\yoda_\GitHub\LESSONS_2026-09-17_restic-and-review-gate.md` §§1-5 (restic append-only
  probe exiting before reaching the server; the positive-control fix; probing destructively without
  being destructive; actionlint A/B baseline that silently read nothing).
- `C:\Users\yoda_\GitHub\POSTMORTEM_2026-09-18_EVIDENCE_THAT_ISNT.md` Part 1 ("the diagnostic
  question", "prove it can fail"), §2.4 (deny rule verified with a harmless analogue plus an
  allow-only control), Part 6 items 1, 3, 6 (usage-watcher test that rewrote the wrong JSON keys;
  finding the tool's own output signature; "run a control").
- `docs/LESSONS.md` on `origin/main` (MasterThread), "Every negative test needs a positive control —
  2026-09-17" — the estate's canonical statement of this rule; this skill operationalises it and
  must not contradict it. That entry notes the rule is "not yet promoted" into a standard, with
  `standards/sessions/worker_role.md`'s "Tests and validators" paragraph named as its natural home —
  confirmed still open as of this writing (that paragraph currently reads only "never claim a pass
  you didn't observe", which does not yet cover the positive-control requirement).
- `docs/AGENTS.md` on `origin/main` (MasterThread) — `gate-execution-auditor` (checks a CI gate's own
  output signature rather than its reported conclusion; reuse for CI-gate targets) and
  `diff-reviewer`/`live-reviewer` (routing for landing a PR that carries a fixed or newly proven
  check).
- `skills/land-pr/SKILL.md`, `skills/owner-click/SKILL.md`,
  `standards/sessions/decision_queue_standard.md`, `standards/sessions/worker_role.md` (all
  MasterThread, `origin/main`) — routing for owner-only actions and PR landing.
