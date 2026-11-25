#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

[[ $# -eq 1 ]] || fail "Usage: $0 {01-bad-release|02-slow-release|03-crashloop|04-memory-leak|rollback}"
name=$1
case "$name" in
  01-bad-release) expression='.chaos.errorRate = "0.3"'; alert=BrewqAvailabilityBurnFast ;;
  02-slow-release) expression='.chaos.latencyMs = "400"'; alert=BrewqLatencyBurnFast ;;
  03-crashloop) expression='.chaos.crashOnStart = "true"'; alert=BrewqPodCrashLooping ;;
  04-memory-leak) expression='.chaos.leakMbPerMin = "40"'; alert=BrewqPodOOMKilled ;;
  rollback) ;;
  *) fail "Unknown drill: $name" ;;
esac

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
values=envs/local/brewq-values.yaml
[[ "$(git branch --show-current)" == main ]] || fail "Switch to main before running a drill."
[[ -z "$(git status --porcelain)" ]] || fail "Start with a clean working tree."
git fetch origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse FETCH_HEAD)" ]] ||
  fail "Local main must match origin/main. Reconcile or push pending commits before continuing."

if [[ "$name" == rollback ]]; then
  commit=$(git log -1 --format=%H --grep='^drill: ' -- "$values")
  [[ -n "$commit" ]] || fail "No drill commit found."
  reverted=$(git log -1 --format=%H --fixed-strings --grep="This reverts commit $commit.")
  [[ -z "$reverted" ]] || fail "The latest drill commit was already reverted."
  git revert --no-edit "$commit"
else
  yq -e '(.chaos.errorRate == "0") and (.chaos.latencyMs == "0") and
    (.chaos.leakMbPerMin == "0") and (.chaos.crashOnStart == "false")' "$values" >/dev/null ||
    fail "Restore the baseline chaos values before starting another drill."

  candidate=$(mktemp "${values}.XXXXXX")
  trap 'rm -f -- "$candidate"' EXIT
  yq "$expression" "$values" > "$candidate"
  if git --no-pager diff --no-index -- "$values" "$candidate"; then
    fail "The drill would make no change."
  else
    [[ $? -eq 1 ]] || fail "Could not show the drill diff."
  fi

  printf 'Commit and push drill %s to origin/main? [y/N] ' "$name"
  if ! read -r answer || [[ "$answer" != y && "$answer" != Y ]]; then
    printf '%s\n' 'Cancelled.'
    exit 0
  fi

  cat "$candidate" > "$values"
  rm -f -- "$candidate"
  git add -- "$values"
  git commit --only -m "drill: $name" -- "$values"
fi

git push origin HEAD:main ||
  fail "Push failed. The commit is local. Check origin/main, reconcile if needed, then push before continuing."

if [[ "$name" == rollback ]]; then
  printf '%s\n' 'Watch the brewq rollout recover and the firing alert clear in Grafana.'
else
  printf 'Watch for %s. See drills/%s.md for expected timing and rollback.\n' "$alert" "$name"
fi
printf '%s\n' 'Watch next with make status, make alerts and http://argocd.localtest.me.'
