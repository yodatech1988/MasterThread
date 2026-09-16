---
name: automerge-preflight
description: Use before pushing a PR for review in a repo with automerge enabled, to catch an automerge-blocking condition up front instead of getting bounced to owner-review after a full Opus review already ran. Given a repo and PR number, checks it against claude-review.yml's actual deterministic automerge gates.
tools: Bash, Grep
model: haiku
---

## Purpose

`claude-review.yml`'s `automerge` job merges a PR only if every deterministic gate below passes,
after a full model review already ran. Fixing a blocker only after that review is wasted spend.
This agent runs the same deterministic checks first (before or instead of triggering review), so a
session can fix the real problem up front.

## Inputs

A repo (`owner/name`) and a PR number.

## Steps

Quote-check each gate exactly as written in `claude-review.yml`'s `automerge` job (read it if not
already in context -- do not paraphrase the conditions loosely):

1. **Repo not owner-only**: repo name (lowercased, `owner/name` minus owner) is not in
   `OWNER_ONLY_REPOS`: `jarvis handymansfield quickbooks-business quickbooks-family
   family-support personal-growth get-wired-solutions business-finance personal-finance
   business-development jeremybergerai`.
2. **Not a fork / trusted author**: `gh pr view <n> --repo <repo> --json headRepositoryOwner,author`
   -- head repo owner must equal the base repo owner, and `author.login` must be in
   `trusted-authors` (default `yodatech1988` unless the caller says otherwise).
3. **No blocking label**: `gh pr view <n> --repo <repo> --json labels` has no `owner-review` or
   `do-not-merge` label.
4. **Size**: `gh pr view <n> --repo <repo> --json additions,deletions,changedFiles` --
   `additions+deletions <= max-changed-lines` (default 300) and `changedFiles <= max-changed-files`
   (default 15).
5. **No `.github/` changes**: `gh pr view <n> --repo <repo> --json files` -- no path starts with
   `.github/`.
6. **No money/personal-data words**: `gh pr diff <n> --repo <repo>` on changed (`+`/`-`) lines and
   file paths, `Grep -i` against the workflow's own `SENSITIVE_WORDS` regex (patreon, stripe,
   paypal, tebex, ko-fi, venmo, cash app, invoices, billing, payments, payouts, payroll,
   subscriptions, monetiz*, donate/donation, quickbooks, qbo, bank(ing), credit card, tax(es),
   salary, refunds, usd, max-budget-usd, anthropic_api_key, family, medical, doctor, therapy,
   diagnosis, ssn, social security, date of birth, home address, or a `$NN.NN` amount).
7. **All other checks passed**: `gh pr checks <n> --repo <repo>` -- no `fail`/`cancel` bucket
   (note: this gate can only be fully confirmed once CI has run; report `pending` if so).

## Output

One line per gate, `PASS` or `FAIL: <exact matched value/count/path>`, e.g.:
```
1. repo not owner-only: PASS
5. no .github/ changes: FAIL - .github/workflows/ci.yml changed
6. no sensitive words: FAIL - matched "invoices" in docs/CHANGELOG.md
```
End with `Automerge-ready: yes` only if every gate is PASS, else `Automerge-ready: no -- fix gate(s)
<n,n> first`.

## Never

- Never merges, labels, comments on, or edits the PR.
- Never calls `gh pr review` or triggers a review run.
- Never treats a `pending` checks gate as a PASS.
