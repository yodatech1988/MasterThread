#!/usr/bin/env bash
# owner-wait-watch.sh - emit one line whenever something a session is waiting on the owner for
# changes state. Built to run under Claude Code's Monitor tool (each stdout line = one event).
# Read-only: gh reads and path-existence checks. Never writes, merges or runs anything.
#
# Usage: owner-wait-watch.sh <watchlist> [interval_seconds=60]
# Watchlist: one item per line, '#' comments allowed:
#   pr    <owner/repo> <number>            PR state / draft / mergeStateStatus / head sha
#   gone  <path>                           waiting for a path to disappear
#   exists <glob>                          waiting for a file to appear (e.g. a click-file's log)
#   api   <gh-api-path> <jq-filter>        any gh api value (branch protection, workflow perms)
# The Decision Queue store is not reachable from a shell; pair this with a scheduled re-read.

set -u
list="${1:?watchlist file required}"
interval="${2:-60}"
declare -A last

probe() {
  local kind="$1"; shift
  case "$kind" in
    pr)     gh pr view "$2" --repo "$1" --json state,isDraft,mergeStateStatus,headRefOid \
              --jq '"\(.state) draft=\(.isDraft) \(.mergeStateStatus) head=\(.headRefOid[0:7])"' 2>/dev/null || echo "UNREADABLE" ;;
    gone)   [ -e "$1" ] && echo "still-present" || echo "GONE" ;;
    exists) compgen -G "$1" >/dev/null && echo "PRESENT: $(compgen -G "$1" | tail -1)" || echo "absent" ;;
    api)    gh api "$1" --jq "$2" 2>/dev/null | tr '\n' ' ' || echo "UNREADABLE" ;;
    *)      echo "BAD-WATCHLIST-LINE" ;;
  esac
}

first=1
while true; do
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|'#'*) continue ;; esac
    # shellcheck disable=SC2086
    set -- $line
    key="$line"
    now="$(probe "$@")"
    if [ "${last[$key]-__unset__}" != "$now" ]; then
      # UNREADABLE is reported once, then again only when it recovers - a gh blip is not an event.
      if [ "$first" = 1 ]; then echo "WATCHING  $key => $now"
      else echo "CHANGED   $key => $now   (was: ${last[$key]})"; fi
      last[$key]="$now"
    fi
  done < "$list"
  first=0
  sleep "$interval"
done
