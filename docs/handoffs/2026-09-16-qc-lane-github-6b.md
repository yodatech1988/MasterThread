# QC lane handoff — github-6b [534bc0], 2026-09-16

Session `github-6b`. Role tonight: read-only QC review lane, reporting to PM `github-64`. Per
Jeremy's full-rotation order relayed by `github-64` ("we need to end all current sessions and
begin anew they need to ensure their session memory is documented for the new sessions to use"),
this session ends and a fresh one starts. Per the same instruction, **nothing this session knows
counts as closed unless it's in GitHub** — an artifact write or a chat message doesn't satisfy that,
so this is a PR, not just a local file or a `SendMessage`.

**The new structure (PR #60, `standards/sessions/fleet_structure.md`) combines peer review and
merge authority into one seat.** The successor to this seat inherits `github-8e`'s job as well as
this one. Write and read this doc with that in mind — it now needs both halves.

## 1. The merge queue is the queue-of-record, and it is *not* this document

`<USER_HOME>\GitHub\merge-queue.json` (+ `merge-queue-NOTES.md` for context outside the JSON
schema), maintained by `github-8e`, is the authoritative, continuously-verified state of every PR
this fleet touched tonight — tier, CI check state, mergeable/behind status, dependency chains,
per-entry `qcSummary`. **Read that file directly.** It is far more current and detailed than
anything below could stay — it was last updated after multiple live re-checks tonight (07:01Z and
07:18Z runs both referenced in several entries), including independent verification passes this
session didn't even know about until reading it just now (e.g. `github-7a` ran a second,
execution-based live-reviewer pass on ops-infra#10's B3/B4 guards, separate from this session's
own read-based pass — both agree, and the entry documents both).

**Mandatory three-way CI classification, as of tonight** — do not report "CI is failing" as a bare
fact. Every red check in the queue is one of exactly three things, and the entry should say which:
1. **Runner-funding**: GitHub Actions is deliberately left unfunded on some repos; a red hosted-
   runner check there is expected, not a defect.
2. **Known runner-provisioning bugs**: the self-hosted VPS runner image was found missing `gh` CLI,
   `gitleaks`, `unzip`, and (separately) `jq` at various points tonight — all now fixed or in-flight
   fixes (see services#97/#99/#100, aegis-poi#15 in the queue). A red check attributable to one of
   these is a known infra gap, not content.
3. **Real content failure.** The only case that should actually change a verdict.

## 2. Standing holds — six PRs held on reasons that are *not* pending QC review

These already passed content review. They are held on decisions QC cannot make:

- **5 stub-repo workflow-removal PRs** (3d-printing#5, family-support#4, flightory-stork-vtol#4,
  get-wired-solutions#6, business-finance#4) **+ handymansfield#10** — all six PASSED content
  review, but a systemic scope question surfaced: this fleet's PM dispatch instruction said "across
  every repo in the org," not "every AEGIS repo," and swept in Jeremy's personal/business-adjacent
  repos (a business named `business-finance` being touched by an AEGIS ops fleet is the clearest
  case). This is with Jeremy as a scope question, not a content question. Do not merge until he
  answers it, and don't re-review the content — it's already clean.
- **ops-infra#9** — `mergeable: CLEAN` on GitHub, but **content-blocked**. The
  `vps-drift-checker.md` agent it adds would SSH into real production hosts (personal-vault,
  aegis-public-edge) with unencrypted, passwordless-root-capable keys, enforced only by prose
  ("Never restart/stop/install") with zero technical control, and it bypasses the repo's own real
  safe-apply tooling (`Invoke-Ansible.ps1`'s read-only container). **Green `mergeable` on GitHub is
  not a readiness signal for this PR** — say that explicitly to whoever inherits it. Deliberately
  excluded from `merge-queue.json` per `github-64`'s instruction (it's not a queue-and-wait item).
  Three remediation paths were offered on the PR itself; none applied yet. Needs Jeremy's actual
  decision.
- **site-chernarus#93** — `CONFLICTING`/`DIRTY`. Overlaps #94's edits to the same ammo-tier JSON
  files. Needs a rebase against current main (check whether #94 has landed) before re-review is
  even possible.
- **aegis-poi#13** — parked. My original review gave a *conditional* PASS scoped narrowly to the
  crash-fix logic itself (independently verified the `Unregister`/`Clear` ordering in `Shutdown()`
  is correct) and explicitly said "not boot-verified" rather than claiming it was safe to merge.
  Later, `github-1e` found the fix, while independently correct, does not resolve the actual
  blocker — an unresolved cross-PBO addon dependency in the test harness (a "CallLater defect" per
  the PM's later framing). **Next step per the PM: one boot test under aegis-mods, then owner
  escalation** — not something QC resolves by re-reading the diff again. This is the PR that
  illustrates why a verdict should be scoped to what it actually checked (see §4).
- **MasterThread#54** — reserved for the owner/PM's own review and merge from the very first
  instruction tonight. Never QC's to touch, still isn't.

## 3. Four PRs that never got a QC verdict

Found during periodic queue sweeps, never reviewed by this seat. Check `merge-queue.json` first —
if any of these still aren't in it, they need a first pass, in this order of priority:

1. **`claude-agents#28`** ("Handle undecryptable DPAPI stores in `Get-StoredConfig`") — highest
   priority of the four. This is the exact hardening-lane follow-up flagged after `claude-agents#27`
   (GitHubTwoFactorKey.ps1)'s review: `RconKey.ps1` and its siblings share an inherited error-
   handling quirk where an undecryptable `.clixml` throws a raw terminating error before the UI
   opens. Credential-tooling-adjacent — give it the same scrutiny credential PRs got tonight, not a
   docs-tier skim.
2. **`ops-platform#11`** ("Add pr-review.yml: close the zero-review gap on live vault code") —
   its own title names "live vault code." Check whether it's actually adding review coverage
   (as claimed) or itself touching anything live, before assuming the title is accurate.
3. **`aegis-poi#14`** (100+ mod survey of prebuilt third-party POI content) — research/survey doc,
   likely low-stakes, but unreviewed as of last check.
4. **`site-chernarus#100`** (vehicles/weapons/clothing/base-building/admin survey, resolves the
   MapLink Hive cross-server-transfer-mod-broken-on-1.29 risk) — same category as #14, but note the
   MapLink finding itself is consequential (see `github-4f`'s handoff,
   `SESSION_HANDOFF_2026-09-16-github-4f.md`, for detail — it means the network's whole multi-site
   transfer premise currently has no working tech).

## 4. Review method and its limits — read this before trusting any verdict in the queue

Every verdict in `merge-queue.json`'s `qcVerifier`/`qcSummary` fields, and every PR comment posted
tonight, states which of three things produced it: **this session's own direct read** (cheap, used
for small/obviously-low-stakes diffs), a **`diff-reviewer` subagent** (the default for anything with
real content), or **`live-reviewer`** (Opus-tier, only ever summoned after explicitly asking the PM
first — never unilaterally — reserved for credentials/live-prod/money; used exactly twice tonight,
both on real findings: ops-infra#9's SSH agent, and the auth-surface half of ops-infra#10). Every
verdict also names the PR's authoring session where knowable, and says "not identified" rather than
guessing when it isn't — GitHub's own metadata shows every commit as author `yodatech1988`
regardless of which fleet session wrote it, so authorship has to come from being told, not derived.

**The model case for how a verdict should be scoped is aegis-poi#13.** The original review said,
explicitly: the fix's *logic* is independently verified correct, and boot-testing is *pending* — not
"this is safe" and not "I couldn't verify this." When a real, separate blocker turned up hours
later (the cross-PBO dependency), it did not contradict the earlier verdict, because the earlier
verdict never claimed to have checked that. **A verdict that states what it did and did not check is
falsifiable and durable in a way a bare PASS/FAIL is not.** Apply this to every future review: say
which configuration was tested (vanilla vs. Expansion, for DayZ module code — see the aegis-poi#13
compile-failure lesson below), whether a "green CI" check is a real signal or a documented no-op
(several repos' checks were confirmed to be literal `echo "no checks configured yet"` placeholders),
and whether a claim is independently verified or being carried forward from someone else's report.

**The single sharpest lesson of the night, if a fresh reader wants only one thing**: `aegis-poi#13`'s
Enforce Script fix passed content review with an honest "not boot-verified" caveat, and still failed
to compile at all under Expansion (~130 cascading errors) — the defect was inside an
`#ifdef EXPANSIONMODMARKET` block a diff read cannot see. A disclosed limitation ("I didn't test
this") is not the same as a scoped one ("I tested X but not Y") — only the second tells a reader
what's actually still at risk. A longer reflective writeup (six lessons, not just this one) exists
at `<USER_HOME>\AppData\Local\Temp\claude\c--Users-<user>--GitHub\ce9674fa-46dd-43e7-a0d1-4d69ee3eb1dc\scratchpad\qc-lane-lessons-2026-09-16.md`
on this machine but is NOT itself committed anywhere — a fresh session with room to do it should
consider folding the durable parts into `MasterThread/docs/LESSONS.md` (built earlier tonight
specifically for this purpose, with a seen-twice promotion rule).

## 5. Open, unresolved: the "mass identity purging application" request

Jeremy asked this session directly whether it could also serve as "team lead R" over a set of
low-level researchers whose output would go to an "intake mechanism" rather than back to this
session, scoped to something called the "mass identity purging application." This session declined
to accept the role blind — an unfamiliar name plus a reporting structure that routes data around
the nominal lead is worth questioning on its own, independent of what the work actually is — and
asked Jeremy directly for clarification rather than guessing either "obviously fine" or "obviously
concerning."

`github-64` then explicitly overrode this session's own suggestion to have a worker research it:
dispatching researchers to investigate an unexplained project would itself be exactly the kind of
un-overseen activity the ambiguity should make everyone cautious about, so `github-64` is asking
Jeremy directly instead. **This is filed as a Decision Queue card and is unresolved as of this
handoff.** A fresh session should not accept the "team lead R" role, name or recruit researchers, or
create an intake mechanism without a real, direct answer from Jeremy first.

## Next step for whoever picks this up

1. Read `merge-queue.json`/`merge-queue-NOTES.md` first — it is the current, authoritative queue
   state; nothing above should be treated as more current than it.
2. Check whether Jeremy has answered on: the 6-PR scope question, ops-infra#9, and the
   "mass identity purging" Decision Queue card. All three were open as of this write.
3. Pick up the 4 unreviewed PRs in §3, `claude-agents#28` first.
4. If this seat now also holds merge authority per PR #60's restructure, read `github-8e`'s own
   session notes/handoff for the merge-tool side of the job — this document only covers the QC half.
5. Keep the provenance-header + dual-durability (PR comment + written record, not just chat)
   practice going. It's cheap, and it's the direct reason this section of the queue survived a
   session boundary at all.
