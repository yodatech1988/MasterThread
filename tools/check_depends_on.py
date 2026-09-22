#!/usr/bin/env python3
"""Mechanical block for dependent PRs: the `depends-on` check.

Owner order 2026-09-22: "These need better blocking mechanisms, or to be built as stacks so I
cannot merge something unless the one beneath it is done." In one round #175 merged before #169,
and #176 and #186 merged into side branches instead of main. This script is what
`.github/workflows/depends-on.yml` runs. The rule it enforces is in
`standards/sessions/merge_authority.md`, section "Dependent PRs: the depends-on check".

A PR declares what it depends on with lines in its body:

    Depends-on: #169
    Depends-on: yodatech1988/ops-platform#42
    Depends-on: https://github.com/yodatech1988/core/pull/7
    Depends-on: none

Several refs may share one line, separated by commas or spaces. The keyword is case-insensitive,
must be hyphenated (prose such as "depends on: ..." is not read), and may follow a list bullet
(`- Depends-on: #12`) or be bold (`**Depends-on:** #12`). Lines inside fenced code blocks are ignored,
so a PR body can show examples. A `Depends-on:` line that matches no ref form and is not `none` is
an error: fail closed, never "probably fine" (merge_authority.md principle 5).

`check` (the pull_request job) FAILS when:
  - the PR's base branch is not its repository's default branch, or
  - any declared dependency is not a merged PR whose merge commit is on its repository's default
    branch (still open, closed unmerged, merged into a side branch, an issue rather than a PR,
    unreadable with this token, or unparseable).
It passes when every declared dependency is merged into its default branch, or there are none.

`recheck` (the schedule / workflow_dispatch job) finds open PRs whose dependencies have all landed
since their last `depends-on` run failed, and re-runs that failed run so the PR's check turns green
without anyone editing it. The re-run only fires inside GitHub Actions against the repository the
workflow is running in; anywhere else it prints `RERUN suppressed (non-default target = test)`
(tools/README.md, "Destructive and notifying paths key off the REAL path").

Standard library only. Reads GITHUB_TOKEN from the environment.
"""
import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request

API = "https://api.github.com"
WORKFLOW_FILE = "depends-on.yml"

_KEYWORD = re.compile(
    r"^\s*(?:[-*+]\s+)?(?:\*\*|__)?depends-on(?:\*\*|__)?\s*:\s*(?:\*\*|__)?\s*(?P<rest>.*)$",
    re.IGNORECASE)
_FENCE = re.compile(r"^\s*(```|~~~)")
_REF = re.compile(
    r"^(?:https?://github\.com/(?P<u_owner>[\w.-]+)/(?P<u_repo>[\w.-]+)/(?:pull|issues)/(?P<u_num>\d+)/?"
    r"|(?:(?P<owner>[\w.-]+)/(?P<repo>[\w.-]+))?#(?P<num>\d+))$")
_NONE_WORDS = {"none", "n/a", "-", "nothing"}


class ParseError(ValueError):
    pass


def parse_depends_on(body, default_repo):
    """Return (refs, errors). refs is an ordered, de-duplicated list of (owner/repo, number);
    errors is a list of human-readable problems with Depends-on lines that could not be read."""
    refs, errors, seen = [], [], set()
    in_fence = False
    for raw in (body or "").splitlines():
        if _FENCE.match(raw):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = _KEYWORD.match(raw)
        if not m:
            continue
        rest = m.group("rest").strip().strip("`").strip()
        if rest.lower().rstrip(".") in _NONE_WORDS:
            continue
        tokens = [t.strip("`.;()[]") for t in re.split(r"[\s,]+", rest) if t.strip("`.;()[]")]
        if not tokens:
            errors.append(f"empty Depends-on line: {raw.strip()!r}")
            continue
        for tok in tokens:
            if tok.lower() in {"and", "&"}:
                continue
            r = _REF.match(tok)
            if not r:
                errors.append(f"could not read {tok!r} in line {raw.strip()!r} "
                              "(use #N, owner/repo#N or a PR URL)")
                continue
            if r.group("u_num"):
                repo = f"{r.group('u_owner')}/{r.group('u_repo')}"
                num = int(r.group("u_num"))
            else:
                repo = f"{r.group('owner')}/{r.group('repo')}" if r.group("repo") else default_repo
                num = int(r.group("num"))
            key = (repo.lower(), num)
            if key not in seen:
                seen.add(key)
                refs.append((repo, num))
    return refs, errors


class GitHub:
    """Minimal REST client. `get` returns (status, json-or-None)."""

    def __init__(self, token):
        self.token = token

    def _req(self, method, path):
        req = urllib.request.Request(API + path, method=method)
        req.add_header("Accept", "application/vnd.github+json")
        req.add_header("X-GitHub-Api-Version", "2022-11-28")
        if self.token:
            req.add_header("Authorization", f"Bearer {self.token}")
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = resp.read()
                return resp.status, (json.loads(data) if data else None)
        except urllib.error.HTTPError as e:
            return e.code, None

    def get(self, path):
        return self._req("GET", path)

    def post(self, path):
        return self._req("POST", path)


def check_dependency(gh, repo, num):
    """Return (ok, message) for one dependency."""
    ref = f"{repo}#{num}"
    status, pr = gh.get(f"/repos/{repo}/pulls/{num}")
    if status == 404:
        istatus, _ = gh.get(f"/repos/{repo}/issues/{num}")
        if istatus == 200:
            return False, f"{ref} is an issue, not a pull request"
        return False, f"{ref} not found, or not readable with this workflow's token"
    if status != 200 or not pr:
        return False, f"{ref} could not be read (HTTP {status})"
    title = pr.get("title", "")
    if not pr.get("merged"):
        state = "closed without merging" if pr.get("state") == "closed" else "still open"
        return False, f"{ref} ({title}) is {state}"
    base = (pr.get("base") or {}).get("ref")
    default = ((pr.get("base") or {}).get("repo") or {}).get("default_branch")
    if not default:
        return False, f"{ref} merged, but its repository's default branch could not be read"
    if base != default:
        return False, f"{ref} ({title}) was merged into '{base}', not '{default}'"
    sha = pr.get("merge_commit_sha")
    if not sha:
        return False, f"{ref} merged, but has no merge commit to verify"
    cstatus, cmp_ = gh.get(f"/repos/{repo}/compare/{default}...{sha}")
    if cstatus != 200 or not cmp_:
        return False, f"{ref} merged, but its merge commit could not be checked against '{default}' (HTTP {cstatus})"
    if cmp_.get("status") not in ("identical", "behind"):
        return False, f"{ref} merged, but merge commit {sha[:12]} is not on '{default}'"
    return True, f"{ref} ({title}) merged into '{default}'"


def evaluate(gh, repo, pr):
    """Evaluate one PR object. Returns (ok, lines, deps) where lines is the report."""
    lines, ok = [], True
    number = pr["number"]
    default = ((pr.get("base") or {}).get("repo") or {}).get("default_branch")
    base = (pr.get("base") or {}).get("ref")
    if not default:
        ok = False
        lines.append("FAIL base: this repository's default branch could not be read")
    elif base != default:
        ok = False
        lines.append(f"FAIL base: this PR targets '{base}', not '{default}'. Dependent work "
                     f"targets '{default}' and declares Depends-on lines; retarget it with "
                     f"'Edit' next to the title.")
    refs, errors = parse_depends_on(pr.get("body"), repo)
    for err in errors:
        ok = False
        lines.append(f"FAIL parse: {err}")
    for dep_repo, dep_num in refs:
        if dep_repo.lower() == repo.lower() and dep_num == number:
            ok = False
            lines.append(f"FAIL {dep_repo}#{dep_num}: a PR cannot depend on itself")
            continue
        dok, msg = check_dependency(gh, dep_repo, dep_num)
        ok = ok and dok
        lines.append(("ok   " if dok else "FAIL ") + msg)
    if not refs and not errors:
        lines.append("ok   no Depends-on lines")
    return ok, lines, refs


def _summary(text):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(text + "\n")


def cmd_check(gh, repo, number):
    status, pr = gh.get(f"/repos/{repo}/pulls/{number}")
    if status != 200 or not pr:
        print(f"::error::depends-on: could not read {repo}#{number} (HTTP {status}); failing closed")
        return 1
    ok, lines, _ = evaluate(gh, repo, pr)
    header = f"depends-on check for {repo}#{number}: {'PASS' if ok else 'FAIL'}"
    print(header)
    for line in lines:
        print("  " + line)
    if not ok:
        blocked = [l[5:] for l in lines if l.startswith("FAIL")]
        print("::error title=depends-on::Do not merge yet. " + " | ".join(blocked))
    _summary("### " + header + "\n\n" + "\n".join(f"- {l}" for l in lines))
    return 0 if ok else 1


def _is_real_target(repo):
    return (os.environ.get("GITHUB_ACTIONS") == "true"
            and os.environ.get("GITHUB_REPOSITORY", "").lower() == repo.lower())


def cmd_recheck(gh, repo, only_pr=None, dry_run=False):
    if only_pr:
        status, pr = gh.get(f"/repos/{repo}/pulls/{only_pr}")
        prs = [pr] if status == 200 and pr else []
    else:
        status, prs = gh.get(f"/repos/{repo}/pulls?state=open&per_page=100")
        if status != 200:
            print(f"::error::depends-on recheck: could not list open PRs (HTTP {status})")
            return 1
    rc = 0
    for pr in prs or []:
        refs, _ = parse_depends_on(pr.get("body"), repo)
        if not refs:
            continue
        ok, lines, _ = evaluate(gh, repo, pr)
        num, sha = pr["number"], pr["head"]["sha"]
        if not ok:
            print(f"#{num}: still blocked; " + "; ".join(l[5:] for l in lines if l.startswith("FAIL")))
            continue
        rstatus, runs = gh.get(f"/repos/{repo}/actions/workflows/{WORKFLOW_FILE}/runs"
                               f"?event=pull_request&head_sha={sha}&per_page=1")
        latest = (runs or {}).get("workflow_runs") or []
        if rstatus != 200 or not latest:
            print(f"#{num}: dependencies met, but no pull_request run found for {sha[:12]}")
            continue
        run = latest[0]
        if run.get("status") != "completed" or run.get("conclusion") == "success":
            print(f"#{num}: dependencies met; latest run is {run.get('status')}/{run.get('conclusion')}, nothing to do")
            continue
        if dry_run or not _is_real_target(repo):
            print(f"#{num}: dependencies met; RERUN suppressed (non-default target = test) for run {run['id']}")
            continue
        pstatus, _ = gh.post(f"/repos/{repo}/actions/runs/{run['id']}/rerun-failed-jobs")
        if pstatus in (201, 204):
            print(f"#{num}: dependencies met; re-ran run {run['id']}")
        else:
            print(f"::warning::#{num}: dependencies met, but re-run of {run['id']} failed (HTTP {pstatus})")
            rc = 1
    return rc


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check", help="evaluate one PR; exit 1 if blocked")
    c.add_argument("--repo", required=True)
    c.add_argument("--pr", type=int, required=True)
    r = sub.add_parser("recheck", help="re-run failed depends-on runs whose dependencies have landed")
    r.add_argument("--repo", required=True)
    r.add_argument("--pr", type=int)
    r.add_argument("--dry-run", action="store_true")
    a = p.parse_args(argv)
    gh = GitHub(os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN"))
    if a.cmd == "check":
        return cmd_check(gh, a.repo, a.pr)
    return cmd_recheck(gh, a.repo, a.pr, a.dry_run)


if __name__ == "__main__":
    sys.exit(main())
