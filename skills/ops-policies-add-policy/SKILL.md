---
name: ops-policies-add-policy
description: Use when adding a new normative YAML file or a new Rego rule to the ops-policies pack — authors it per docs/CONVENTIONS.md, runs the local checks (make manifest, make check), then hands the branch to land-pr. Does not run make go-live and does not touch live systems.
---

# ops-policies-add-policy

## When to use this

- A new normative YAML file (a policy input the runtime loads) is being added to `ops-policies`.
- A new Rego rule (or rule package) is being added under `ops-policies/policies/<area>/`.
- Not for: making the pack go-live (`make go-live` is a separate, not-approved step this skill does
  not run or cover), and not for merging — that's `land-pr`.

## Procedure

Read every source from `origin/main`, never a local working tree
(`git -C ops-policies show origin/main:<path>`).

1. **Read the authority document section this policy implements** and confirm the file you're about
   to add doesn't already exist (`git ls-tree -r --name-only origin/main` on `ops-policies`).

2a. **If it's a normative YAML file**, per `docs/CONVENTIONS.md` "Normative YAML":
   - Give it a `version` (integer, bumped on any breaking change) and `source` field naming the
     authority-document heading(s) it implements. A value from a verified correction or an owner
     answer gets a comment citing `docs/VERIFICATION.md` or the relevant `docs/OPEN_QUESTIONS.md`
     entry.
   - Write one JSON Schema for it under `schema/`, draft 2020-12, with `additionalProperties: false`
     on every object.
   - Register it so it's actually enforced: `tools/check.py`'s `PACK_FILES` list only holds the
     always-loaded core files (currently just `zones.yaml`); every area module registers its own
     files by calling `check.register_file("<path>", "<schema-file>.schema.json")` at import time
     (see `tools/checks_agents.py` line 11 for the working example). Add the same call in the area
     module the new file belongs to, or create one if the area has none yet.
   - Quote anything YAML 1.1 could reinterpret: times like `"02:00"`, bare `yes`/`no`/`on`/`off`.
   - Where the source document says something must *never* happen, make the schema structurally
     unable to express it (`const`, or omit the key under `additionalProperties: false`) — not a
     boolean defaulting to the safe value.
   - An identifier not yet created is `TBD` in the document's own form (`TBD`, `fdrl_TBD`); never use
     `TBD` for an undecided *question* — that goes in `docs/OPEN_QUESTIONS.md` instead, following the
     existing entries' shape (state, document quote, shipped default, blocks).
   - No secrets: names, IDs and host/service names are fine; token/key/password values are never
     written.

2b. **If it's a Rego rule**, per `docs/CONVENTIONS.md` "Rego" (OPA 1.x, Rego v1: `if`/`contains`):
   - Put it in the right `policies/<area>/` package with a sibling `*_test.rego`, and declare
     `default allow := false` (or the package's equivalent default-deny outcome) before any rule.
   - Write both a firing test (a violating/missing input that gets denied) and a non-over-firing test
     (a compliant input that is not denied) for the rule.
   - **Never negate an expression that references `input` directly** — OPA evaluates the reference
     outside the `not`, so a missing field leaves the rule body undefined and the deny silently does
     not fire. Read every input field once through `object.get(input, <path>, <default>)` into a
     local object first, as `policies/agents/allowlist.rego` does, and write the rule against that
     local copy. (Real bug, quoted from `docs/CONVENTIONS.md`: "Found by
     `policies/agents/allowlist_test.rego` during S4; see `test_missing_credential_side_is_denied`.")
   - **Never compare a possibly-missing value with `<`, `<=`, `>` or `>=`** — Rego orders values
     across types and `null` sorts before every number, so the comparison silently fails to fire for a
     null value. Guard with `is_number` first. (Real bug, quoted from `docs/CONVENTIONS.md`: "Found in
     S5; `test_invoice_with_null_amount_counts_as_over_threshold`.")
   - Remember `object.union` merges recursively and cannot remove a nested key (build a modified copy
     and replace it instead), and `with` cannot target a dynamic data path like `data.x[var]` (build a
     modified copy of the parent object and use `with data.x as copy`).
   - A `deny` returns a machine-readable `reason` code, not the payload.

3. **Regenerate the manifest and run the local checks**, exactly as `README.md` and the `Makefile`
   state (`Makefile`: "The gate for this repo. CI runs exactly this."):
   ```
   make manifest    # python tools/pack_manifest.py --write
   make check       # python -m unittest discover -s tests && python tools/check.py
   ```
   `tools/check.py` needs `opa` on `PATH` or `OPA_BIN` set — a missing binary is a failure, never a
   skip (`docs/CONVENTIONS.md` "Tests"; `tools/check.py`'s own docstring). Do not pass `--go-live` and
   do not run `make go-live` — that gate (every TBD/open question/go-live item resolved) is
   out of scope for this skill.

4. **Write the PR body per `docs/CONVENTIONS.md` "Pull requests"**: what changed and the document
   section it implements, real validator output (actual counts from step 3, not assumed), anything
   simulated rather than verified, and any owner decision together with its `docs/OPEN_QUESTIONS.md`
   entry. Update `docs/PLAN.md`'s Status table in the same PR (repo convention, same section).

5. **Hand off to `land-pr`** for PR state re-check, review routing, and merge verification. Do not
   merge from inside this skill.

## Stop conditions

- **Never run `make go-live`** and never treat resolving a `TBD` or an `OPEN_QUESTIONS.md` entry as
  in scope here — that belongs to a separate, not-approved go-live procedure.
- If `opa` is not on `PATH`/`OPA_BIN` and cannot be installed in this environment, stop and report —
  `tools/check.py` treats a missing binary as a hard failure, not something to work around or skip.
- If the authority-document section for the new policy is genuinely unclear or unwritten, write the
  gap as a new `docs/OPEN_QUESTIONS.md`-shaped note in the PR body rather than guessing at the rule,
  and flag it for the owner.
- If the new file would need a secret value (not just a name/ID), stop — this skill never writes
  secret values into the pack.
- Never merge, never run `make go-live`, never touch a live system from inside this skill — merging
  is `land-pr`'s job and any live/credential action is `owner-click`'s.

## Grounded in

- `ops-policies` `docs/CONVENTIONS.md` (`origin/main`) — "Normative YAML" and "Rego" sections, quoted
  verbatim above for the two real bugs; "Pull requests" section for the PR-body shape.
- `ops-policies` `README.md` (`origin/main`) — `make check` / `make go-live` commands, `opa`
  requirement, "run `make manifest` after any policy change".
- `ops-policies` `Makefile` (`origin/main`) — `check`, `go-live`, `manifest` targets and their real
  underlying commands.
- `ops-policies` `tools/check.py` (`origin/main`) — `PACK_FILES`, `register_file()`, docstring on
  `--go-live` and the missing-`opa`-is-fatal rule.
- `ops-policies` `tools/checks_agents.py` line 11 (`origin/main`) — working example of
  `check.register_file(ROSTER, "roster.schema.json")`.
- `ops-policies` `policies/agents/allowlist.rego` (`origin/main`) — working example of the
  `object.get` pattern and default-deny/reason-code shape.
- `ops-policies` `docs/OPEN_QUESTIONS.md` (`origin/main`) — entry shape (state, document quote,
  shipped default, blocks) reused above for the "unclear authority" stop condition.
- `MasterThread` `skills/land-pr/SKILL.md`, `skills/owner-click/SKILL.md` (`origin/main`) — format and
  the boundary this skill hands off across (land-pr for merge, owner-click for anything live/secret).
