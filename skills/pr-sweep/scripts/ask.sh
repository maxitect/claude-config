#!/usr/bin/env bash
# Asks a PR's reviewer session one question headless and prints the answer. The session keeps the turn,
# so a later interactive resume sees it.
#
# Usage: ask.sh <pr> <question...>

. "$(dirname "$0")/lib.sh"
N="${1:?usage: ask.sh <pr> <question>}"; shift
RUN="$(run_dir "$N")"; WT="$(wt_dir "$N")"
"$SCRIPTS/open.sh" "$N" >/dev/null || exit 1

FLAGS=()
while IFS= read -r f; do FLAGS+=("$f"); done < <(reviewer_flags "$RUN")
cd "$WT" || exit 1
cap "$REVIEW_TIMEOUT" claude -p --resume "$(cat "$RUN/reviewer.sid")" "${FLAGS[@]}" --output-format json "$*" < /dev/null \
  | grep '^{' | tail -1 | jq -r '.result // "ASK FAIL: no answer"'
