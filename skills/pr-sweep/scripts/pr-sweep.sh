#!/usr/bin/env bash
# Command-line entry point: sweeps the current repo's open PRs headless, no orchestrating session.
#
# Usage: pr-sweep [mine] [<pr>...]          preflight, discover, then run.sh per PR (max 4 at once, 3 MIG)
#        pr-sweep status                    furthest stage per PR, resume commands
#        pr-sweep ask <pr> <question...>    ask that PR's reviewer session, print the answer
#        pr-sweep open <pr>                 bring its stack back, print the interactive resume command
#        pr-sweep teardown <pr> [--full]    free its stack (--full: worktree and artefacts too)
#
# Stage lines stream prefixed with [#<pr>]; each PR's full output is in $SWEEP/<pr>/run.log.
# Exit 1 if any PR failed. Ctrl-C stops every run and frees their stacks; re-running resumes them.

SCRIPTS="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# --glm: route every headless claude through settings-glm.json's env (the claude-glm alias)
ARGS=()
for a in "$@"; do
  if [ "$a" = "--glm" ]; then export PR_SWEEP_CLAUDE_ENV="$HOME/.claude/settings-glm.json"; else ARGS+=("$a"); fi
done
set -- ${ARGS[@]+"${ARGS[@]}"}

case "${1:-}" in
  status|ask|open|teardown) exec "$SCRIPTS/$1.sh" "${@:2}" ;;
esac

. "$SCRIPTS/lib.sh"
MAX_RUNS="${PR_SWEEP_RUNS:-4}"
set -m   # each run gets its own process group, so stopping one kills everything under it and nothing above

"$SCRIPTS/preflight.sh" || exit 1
"$SCRIPTS/discover.sh" "$@" || exit 1

QUEUE=()   # MIG PRs first: they wait on slots and take longest
while read -r n; do [ -n "$n" ] && QUEUE+=("$n"); done \
  < <(jq -r 'sort_by(.mig | not) | .[].number' "$SWEEP/queue.json")
[ "${#QUEUE[@]}" -gt 0 ] || { "$SCRIPTS/status.sh"; exit 0; }

PIDS=(); PRS=(); FAILED=()
is_mig() { [ "$(jq -r ".[] | select(.number==$1) | .mig" "$SWEEP/queue.json")" = "true" ]; }
running_mig() { local c=0 p; for p in "${PRS[@]+"${PRS[@]}"}"; do is_mig "$p" && c=$((c + 1)); done; echo "$c"; }

stop_all() {
  echo "stopping: ${PRS[*]-}"
  for pid in "${PIDS[@]+"${PIDS[@]}"}"; do kill -TERM -- "-$pid" 2>/dev/null; done
  wait
  for p in "${PRS[@]+"${PRS[@]}"}"; do "$SCRIPTS/teardown.sh" "$p" >/dev/null; done
  exit 130
}
trap stop_all INT TERM

launch() {
  local n="$1"
  mkdir -p "$SWEEP/$n"
  ( "$SCRIPTS/run.sh" "$n" 2>&1 | tee "$SWEEP/$n/run.log" | perl -pe 'BEGIN { $| = 1 } s/^/[#'"$n"'] /' ) &
  PIDS+=("$!"); PRS+=("$n")
}

reap() {
  local i keep_p=() keep_n=()
  for i in "${!PIDS[@]}"; do
    if kill -0 "${PIDS[$i]}" 2>/dev/null; then
      keep_p+=("${PIDS[$i]}"); keep_n+=("${PRS[$i]}")
    else
      grep -q '^RUN PASS' "$SWEEP/${PRS[$i]}/run.log" || FAILED+=("${PRS[$i]}")
    fi
  done
  PIDS=("${keep_p[@]+"${keep_p[@]}"}"); PRS=("${keep_n[@]+"${keep_n[@]}"}")
}

# a MIG PR waiting on a slot doesn't hold back the non-MIG PRs queued behind it
while [ "${#QUEUE[@]}" -gt 0 ] || [ "${#PIDS[@]}" -gt 0 ]; do
  reap
  WAITING=()
  for n in "${QUEUE[@]+"${QUEUE[@]}"}"; do
    if [ "${#PIDS[@]}" -ge "$MAX_RUNS" ] || { is_mig "$n" && [ "$(running_mig)" -ge "$MAX_SLOTS" ]; }; then
      WAITING+=("$n")
    else
      launch "$n"
    fi
  done
  QUEUE=("${WAITING[@]+"${WAITING[@]}"}")
  sleep 5
done

echo
"$SCRIPTS/status.sh"
if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "failed: ${FAILED[*]} (re-run pr-sweep ${FAILED[*]} to resume each from its failed stage)"
  exit 1
fi
