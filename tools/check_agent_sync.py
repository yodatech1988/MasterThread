#!/usr/bin/env python3
"""Read-only drift reporter for Claude Code agent definitions.

Written for audit findings R6 and R10 in `docs/AGENT_ROSTER_AUDIT_2026-09-17.md` (MasterThread
PR #84): the audit found agent-definition drift by hand (three local-only global agents, two
files duplicated across repo-local `.claude/agents/` dirs with no check). This script automates
that comparison. It never copies, writes, or deletes anything -- it only reads and reports.

Two independent checks:

1. Live vs. mirror (R6): compares the real `~/.claude/agents/*.md` files (the ones Claude Code
   actually loads) against this repo's `claude-agents/*.md` mirror (see `claude-agents/SYNC.md`
   for why the mirror exists). Reports three lists: files only on the live machine, files only in
   the git mirror, and files present in both whose content differs (CR/LF differences ignored).
   This check always runs.

2. Repo-local cross-repo duplicates (R10): some agent definitions live under a specific repo's
   own `.claude/agents/` (not the global mirror) and are hand-copied into more than one sibling
   repo clone (e.g. `mod-boot-test-runner.md` in aegis-mods, aegis-poi and aegis-pricing). Nothing
   previously checked whether those copies stayed in sync. Pass `--repo-local <github-root>` to
   scan every sibling clone under that root for `.claude/agents/*.md` files, read each one from
   its clone's *origin default branch* via `git show` (not the working tree -- a repo-local file
   can exist on origin without ever being pulled into a given clone's checkout, which is exactly
   what happened here: aegis-mods' working tree has no `.claude/agents/` at all even though
   `origin/master` does), and report any filename whose content differs between repos. Clones of
   the same remote (this estate keeps two clones each of `core` and `site-chernarus`, named
   `aegis-core`/`core` and `aegis-site-chernarus`/`site-chernarus`) are deduped by
   `git remote get-url origin` before comparing, so two checkouts of the same repo are never
   reported as "differing" from each other.

Exit code is 1 if either requested check finds anything to report, 0 otherwise.

Usage:
    python tools/check_agent_sync.py
    python tools/check_agent_sync.py --live-dir /path/to/agents --mirror-dir claude-agents
    python tools/check_agent_sync.py --repo-local C:/Users/me/GitHub
"""
import argparse
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_LIVE_DIR = pathlib.Path.home() / ".claude" / "agents"
DEFAULT_MIRROR_DIR = ROOT / "claude-agents"
SKIP_DIR_PREFIXES = ("_", "core-tmp-")


def _normalize(text: str) -> str:
    """Line-ending-insensitive content for comparison."""
    return text.replace("\r\n", "\n").replace("\r", "\n")


def _read_md_dir(directory: pathlib.Path) -> dict:
    """Filename -> raw text, for every *.md file directly in `directory` (non-recursive)."""
    if not directory.is_dir():
        return {}
    return {p.name: p.read_text(encoding="utf-8") for p in sorted(directory.glob("*.md"))}


def live_vs_mirror(live_files: dict, mirror_files: dict) -> tuple:
    """Returns (local_only, repo_only, content_differs) -- all sorted lists of filenames.

    `live_files` and `mirror_files` are filename -> content maps, as returned by `_read_md_dir`.
    """
    live_names = set(live_files)
    mirror_names = set(mirror_files)

    local_only = sorted(live_names - mirror_names)
    repo_only = sorted(mirror_names - live_names)
    content_differs = sorted(
        name
        for name in live_names & mirror_names
        if _normalize(live_files[name]) != _normalize(mirror_files[name])
    )
    return local_only, repo_only, content_differs


# ---------------------------------------------------------------------------
# Repo-local cross-repo duplicate check (R10)
# ---------------------------------------------------------------------------


def run_git(repo_dir: pathlib.Path, *args: str) -> str | None:
    """Runs `git -C repo_dir <args>`, returns stdout stripped, or None on any failure."""
    try:
        result = subprocess.run(
            ["git", "-C", str(repo_dir), *args],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def get_origin_url(repo_dir: pathlib.Path) -> str | None:
    url = run_git(repo_dir, "remote", "get-url", "origin")
    if not url:
        return None
    # Normalize so "https://...repo.git" and "https://...repo" (or a stray trailing
    # slash/case difference) key the same -- these are display/config variance, not a
    # different remote.
    return url.strip().rstrip("/").removesuffix(".git").lower()


def get_default_branch(repo_dir: pathlib.Path) -> str:
    ref = run_git(repo_dir, "symbolic-ref", "--short", "refs/remotes/origin/HEAD")
    if ref and ref.startswith("origin/"):
        return ref[len("origin/") :]
    for candidate in ("main", "master"):
        if run_git(repo_dir, "rev-parse", "--verify", f"origin/{candidate}") is not None:
            return candidate
    return "main"


def discover_repo_clones(github_root: pathlib.Path) -> list:
    """Returns [(name, path), ...] for every git clone directly under github_root that isn't
    skipped, sorted by name for deterministic output."""
    clones = []
    if not github_root.is_dir():
        return clones
    for entry in sorted(github_root.iterdir()):
        if not entry.is_dir():
            continue
        if entry.name.startswith(SKIP_DIR_PREFIXES):
            continue
        if not (entry / ".git").exists():
            continue
        clones.append((entry.name, entry))
    return clones


def dedupe_by_origin(clones: list) -> list:
    """Collapses clones that share an origin remote URL to one representative each (first by
    name). Clones with no readable origin URL are each kept as their own group."""
    seen_origins: dict = {}
    representatives = []
    for name, path in clones:
        origin = get_origin_url(path)
        key = origin if origin else f"__no-origin__:{name}"
        if key in seen_origins:
            continue
        seen_origins[key] = name
        representatives.append((name, path))
    return representatives


def read_agent_files_from_origin(repo_dir: pathlib.Path) -> dict:
    """Filename -> content for every `.claude/agents/*.md` file on the clone's origin default
    branch, read via `git show` (never the working tree)."""
    branch = get_default_branch(repo_dir)
    listing = run_git(repo_dir, "ls-tree", "-r", "--name-only", f"origin/{branch}", "--", ".claude/agents")
    if not listing:
        return {}
    files = {}
    for line in listing.splitlines():
        line = line.strip()
        if not line or not line.endswith(".md"):
            continue
        content = run_git(repo_dir, "show", f"origin/{branch}:{line}")
        if content is None:
            continue
        files[pathlib.Path(line).name] = content
    return files


def compare_across_repos(repo_contents: dict) -> dict:
    """`repo_contents` is {repo_label: {filename: content}}. Returns {filename: [repo_label,
    ...]} for every filename that appears in more than one repo with differing content (repo
    labels sorted, only filenames with an actual difference included)."""
    by_filename: dict = {}
    for repo_label, files in repo_contents.items():
        for filename, content in files.items():
            by_filename.setdefault(filename, {})[repo_label] = content

    differing = {}
    for filename, per_repo in by_filename.items():
        if len(per_repo) < 2:
            continue
        contents = {_normalize(c) for c in per_repo.values()}
        if len(contents) > 1:
            differing[filename] = sorted(per_repo)
    return differing


def repo_local_check(github_root: pathlib.Path) -> dict:
    clones = dedupe_by_origin(discover_repo_clones(github_root))
    repo_contents = {name: read_agent_files_from_origin(path) for name, path in clones}
    # Drop repos with no repo-local agent files -- nothing to compare.
    repo_contents = {name: files for name, files in repo_contents.items() if files}
    return compare_across_repos(repo_contents)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--live-dir",
        type=pathlib.Path,
        default=DEFAULT_LIVE_DIR,
        help=f"directory of live agent files (default: {DEFAULT_LIVE_DIR})",
    )
    parser.add_argument(
        "--mirror-dir",
        type=pathlib.Path,
        default=DEFAULT_MIRROR_DIR,
        help=f"directory of the git-mirrored agent files (default: {DEFAULT_MIRROR_DIR})",
    )
    parser.add_argument(
        "--repo-local",
        type=pathlib.Path,
        default=None,
        metavar="GITHUB_ROOT",
        help="also scan sibling repo clones under this directory for cross-repo drift in "
        "repo-local .claude/agents/ files (R10)",
    )
    args = parser.parse_args()

    problems_found = False

    live_files = _read_md_dir(args.live_dir)
    mirror_files = {n: c for n, c in _read_md_dir(args.mirror_dir).items() if n != "SYNC.md"}
    local_only, repo_only, content_differs = live_vs_mirror(live_files, mirror_files)

    print(f"Live vs. mirror ({args.live_dir} vs {args.mirror_dir}):")
    if not (local_only or repo_only or content_differs):
        print("  in sync -- no local-only, repo-only, or differing files.")
    else:
        problems_found = True
        print(f"  local-only ({len(local_only)}): {local_only or '(none)'}")
        print(f"  repo-only ({len(repo_only)}): {repo_only or '(none)'}")
        print(f"  content-differs ({len(content_differs)}): {content_differs or '(none)'}")

    if args.repo_local is not None:
        print(f"\nRepo-local cross-repo drift (under {args.repo_local}):")
        differing = repo_local_check(args.repo_local)
        if not differing:
            print("  no repo-local .claude/agents/ files differ across repos.")
        else:
            problems_found = True
            for filename, repo_labels in sorted(differing.items()):
                print(f"  {filename}: differs across {', '.join(repo_labels)}")

    return 1 if problems_found else 0


if __name__ == "__main__":
    raise SystemExit(main())
