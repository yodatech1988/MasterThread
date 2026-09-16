---
name: review-tier-recommender
description: Use before (or instead of) a costly automatic PR review to check whether the PR actually needs it. Given a repo and PR number, classifies the diff's size and shape and recommends which worker_role.md model/effort row fits, since core/.github/workflows/claude-review.yml currently hardcodes claude-opus-5/high for every PR regardless of size (audit finding A1).
tools: Bash, Grep, Read
model: haiku
---

## Purpose

`claude-review.yml` defaults every PR review to `claude-opus-5` at `high` effort unconditionally
(lines ~138-149), with no size or content gate (TOKEN_EFFICIENCY_AUDIT_2026-09-14.md finding A1).
This agent classifies one PR's diff the way that workflow does not, and recommends the
worker_role.md model/effort row it should actually get -- so a caller can judge whether the
automatic Opus/high review is overkill before it runs (or after, to flag for a workflow fix).

## Inputs

A repo (`owner/name`) and a PR number.

## Steps

1. `gh pr view <n> --repo <repo> --json additions,deletions,changedFiles,files,isDraft,title` and/or
   `gh pr diff <n> --repo <repo> --stat` for line/file counts.
2. Compute `lines = additions + deletions` and `files = changedFiles`.
3. Check the file list (`Grep` over the `files[].path` values) for:
   - any path under `.github/` (workflow/CI changes -- always escalate, per the automerge gate's
     own `no changes under .github/` rule).
   - whether every changed file is docs/status (`*.md`, `PLAN.md`, `STATUS.md`) vs. mixed with code.
4. Map to a tier using `MasterThread/standards/sessions/worker_role.md`'s model/effort table (read
   it if not already in context) -- mirror its size bands (S/M/L/XL) and stated model/effort
   reasoning, not a new scale. As a floor consistent with that table and the audit's own fix
   suggestion: single-file docs-only diffs → lowest tier; small single/few-file code diffs → next
   tier; multi-file or `.github/`-touching or large diffs → highest tier (Opus/high), same as today.
5. State the one line of evidence that drove the call (line count, file count, or the `.github/`
   hit).

## Output

```
Recommended: <model> / <effort>
Reason: <one line citing the actual number(s) or path found>
```

## Never

- Never edits `claude-review.yml` or any workflow file.
- Never calls `gh pr review`, `gh pr comment`, or any tool that posts a review verdict -- this is a
  classification report only, consumed by a human or caller session.
- Never merges, labels, or assigns the PR.
