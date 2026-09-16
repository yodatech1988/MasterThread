# Session handoff: merge-authority tool (session github-85, Team B)

## Done / verified
- Built `C:\Users\yoda_\GitHub\AEGIS-Merge-Queue.cmd` + `AEGIS-Merge-Queue.ps1`: a standing,
  human-gated merge tool for the merge-authority lane (github-8e), matching the existing
  `AEGIS-*.cmd` wrapper convention (echo context -> `pause` -> invoke same-named `.ps1`).
- Reads a queue file (default `C:\Users\yoda_\GitHub\merge-queue.json`, JSON array; schema
  documented in the `.ps1` header comment: repo, pr, tier, qcVerdict, qcVerifier, qcSummary,
  authorSession, mergeMethod, liveWarning).
- Groups PRs by tier, shows full QC context per PR (not just repo+number) before the decision
  point.
- **2026-09-16, later same session — gate mechanism changed from typed to clickable, per
  Jeremy's direct request** ("I don't want to have to type approve, clicking an approve, then
  an are you sure is enough... from my pc which is the only trusted device"). The typed `YES`
  Read-Host gate is GONE — replaced with Windows Forms dialogs: a per-PR dialog (full context +
  live-warning banner) with **Approve / Skip this PR / Stop this pass** buttons, then on
  Approve a second dialog naming the specific PR ("Merge `<repo> #<pr>` into main now?") that
  must be clicked Yes. **Read this carefully before touching the gate again**: this is NOT a
  downgrade from the original design intent. The control was never "typing" for its own sake —
  it was "a present human acts deliberately." Two clicks with a safe default satisfy that the
  same way a typed word did. Specifically, and verify these three things stayed true if you
  ever touch this file:
  1. The approval dialog's `AcceptButton` is wired to **Skip**, not Approve — a reflexive
     Enter/Space on that dialog skips, never merges.
  2. The confirm dialog uses `MessageBoxDefaultButton.Button2` (**No**) as its default.
  3. The confirm text names the specific repo+PR, never a generic "Are you sure?".
  If any of those three regress, the control is actually weaker than before — don't "simplify"
  them away.
- Tier 4 (or any entry with a `liveWarning` field) gets a red banner before its prompt.
- Syntax-validated via `[System.Management.Automation.Language.Parser]::ParseFile` — no parse
  errors. **Not yet exercised against a real queue file or a real `gh pr merge` call.**
- `C:\Users\yoda_\GitHub` is NOT a git repo (`git status` -> "not a git repository"), same as
  the other top-level `AEGIS-*.cmd` tools — nothing to commit/push here; this note is the
  durable record instead.
- Added real dependency enforcement (github-8e flagged the original script had none): a new
  `dependsOn` field (string or array of `"owner/repo#pr"` refs, bare number = same repo).
  Before the YES prompt, every dependency is resolved live via `gh pr view --json state` and
  must be MERGED or the entry is auto-skipped with a red banner — no YES prompt is ever
  offered out of order. Fails closed: a `gh` error, missing state, or nonexistent PR all count
  as unmet. Explicitly NOT display-only, per PM's rejection of an inert interim version.
  Verified standalone against real `gh` data (not the full interactive tool): a known-merged
  PR (yodatech1988/aegis-poi#1) resolved `Merged=True`; a nonexistent PR
  (aegis-poi#99999) correctly failed closed (`Merged=False`, "no state returned").
  `merge-queue.json` has no `dependsOn` entries yet — ops-infra #10/#11 are still held out of
  the queue file per the PM's note; whoever re-adds them should use this field.

## Next step
- **DONE, not open anymore**: github-8e wrote `C:\Users\yoda_\GitHub\merge-queue.json` —
  26 entries (Tier 1: 19, Tier 2: 1, Tier 3: 2, Tier 4: 4), JSON-validated, independently
  spot-checked by this session (tier distribution and the 4 Tier-4/`liveWarning` entries —
  site-chernarus #96/#94/#88 live economy, ops-infra #10 vault auth — match what was
  expected). Reported dry-run tested against the tool (loads, tiers correctly, stops at the
  typed-YES prompt, zero merges) — this session verified the file's shape/content directly
  but has not itself run the interactive tool end-to-end.
- Remaining actual next step: **a real live click-through**. This session syntax-validated
  the GUI version and statically confirmed the three safety-critical wiring points above, but
  deliberately did NOT trigger `ShowDialog()` itself — that pops a real modal window on
  Jeremy's live desktop that only he can click through, and this session has no way to drive it
  safely without risking a surprise popup mid-conversation. Jeremy (or github-8e with Jeremy
  present) needs to run `AEGIS-Merge-Queue.cmd` for a real dry run — click Skip/Stop only
  first to confirm the flow feels right — before trusting it for the actual 26 pending merges.
- **2026-09-16, briefly superseded then reversed back — this script is the ONLY merge path.**
  Jeremy briefly wanted approvals moved into the Fleet Status dashboard instead (github-54
  building it); that plan was withdrawn shortly after: github-8e declined to build the
  executor side because the proposed gates checked PR safety, not approval authenticity — a
  db approval row is not proof of a human click, same principle this note already flagged.
  `AEGIS-Merge-Queue.ps1/.cmd` was never touched during this detour and remains current/only.
  Separately, Jeremy also pushed back on the manual-queue approach itself long-term — most of
  this volume should be handled by automerge, which is dead in 5 repos due to a read-only
  GitHub Actions token setting (not a missing system) and is being fixed at that source
  instead. This session made no changes for either development — informational only.

## Other lanes this session (github-85) touched tonight

- **Ops Roster artifact** (`https://claude.ai/artifact/U23uudrKWTT1RJ8rrews4N`, part of a
  3-artifact pack with Fleet Status and Decision Queue): assigned to read and assess, not build.
  Finding: it's a static draft org-chart proposal (fixed named seats — pm/leads/qc/merge-
  authority/12 workers), NOT redundant with Fleet Status (which is live/db-backed) — different
  jobs, don't merge/retire. Made one approved factual fix (republished, version 3): §8's
  "unauthorized CLAUDE.md edit still open" line marked resolved, since Jeremy confirmed directly
  to this session earlier tonight. Coordinated with github-54 (owns the pack's design system and
  the Decision Queue's write path) before doing anything further — they added a card,
  `decisions/ops-roster-adoption`, asking Jeremy to adopt/amend/reject the Roster design; this
  session independently verified that card via `read_db` (real, content accurate) rather than
  taking the report at face value. No further Roster work planned unless reassigned.
- **Review-gate assessment: DONE, reported to github-fa, nothing built.** Confirmed directly
  (not assumed): none of the three have a `pr-review.yml`; ops-policies has `policy-ci.yml`
  but it's `workflow_dispatch`-only (blocked on `docs/OPEN_QUESTIONS.md` Q15, runner choice);
  MasterThread has no `.github/workflows/` at all and isn't even in its own `docs/REPOS.md`
  ledger. Recommendation: all three should get review — ops-platform most urgently (live
  PM/router/ledger/egress-gateway code on the vault, zero review today), ops-policies next
  (gates data-classification/egress-zone config; needs Q15 answered to wire `policy-ci` to PRs
  too), both via the standard `pr-review.yml` -> `core/.github/workflows/claude-review.yml@main`
  pattern with `automerge: false` (row-1 territory). MasterThread is the odd one out: it's the
  repo grounding tonight's own CLAUDE.md incident, so a Claude-reviewed automerge gate on the
  documents that tell Claude sessions how to behave has a circularity problem — recommended
  Claude review as a first pass but never automerge there, with a stronger owner-required bar
  specifically for `standards/sessions/*` and anything a launch prompt reads automatically.

## Pending decisions / open flags
- Origin of today's "2 teams of 6" restructure and PM-handoff chain had two retracted/false
  claims earlier in the session (`ops-cycle-pm` being live; a "mandatory effort telemetry"
  requirement that turned out to be an uncommitted local diff in MasterThread). Jeremy has
  since confirmed directly ("I have been directly overseeing all work that has been planned
  in claude.md") — treating the chain as legitimate from that point forward, but flagging the
  history here in case a successor session needs the context.
- Fleet-wide safety instruction relayed via github-fa (PM/Jeremy), still in effect: do **not**
  summon the `vps-drift-checker` agent (live-reviewer verdict: CHANGES REQUESTED/HOLD FOR
  OWNER — unenforced read-only claim, needs passwordless root sudo on vault + live server,
  bypasses `Invoke-Ansible.ps1`). Do **not** read, copy, or use the vault-admin or
  aegis-vps-admin-bot SSH keys in `C:\Users\yoda_\.ssh\` for any reason, including from the
  merge tool.
- **Flagged risk (not acted on — placement is Jeremy's call, not ours)**: the merge tool
  (`AEGIS-Merge-Queue.cmd/.ps1`) and its state (`merge-queue.json`, now gating 26 real PRs
  including 4 live-system Tier-4 items) both live in `C:\Users\yoda_\GitHub\`, which is not a
  git repo — a single unversioned, unbacked-up copy on one machine. Same structural problem as
  the `_security-public` policy tree (per PM). Where this should actually live long-term
  (`claude-agents` alongside the other `*Key.ps1` tools? `MasterThread`? deliberately stay
  put?) needs an owner decision — do not relocate it without one.
