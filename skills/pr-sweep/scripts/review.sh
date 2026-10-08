#!/usr/bin/env bash
# Runs the Opus reviewer headless in the PR's worktree and stores its schema-checked findings.
#
# Usage: review.sh <pr>                 fresh review session (needs prepare.sh first)
#        review.sh <pr> --fix <file>    resume the same session with validator errors from <file>
# Writes $SWEEP/<pr>/{reviewer.sid,review.json,findings.json}; the reviewer writes review.md itself.

. "$(dirname "$0")/lib.sh"
N="${1:?usage: review.sh <pr> [--fix <file>]}"
RUN="$(run_dir "$N")"; WT="$(wt_dir "$N")"
LOG="$RUN/review.log"
SHA="$(meta "$N" .sha)"
[ "$(cat "$RUN/prepare.ok" 2>/dev/null)" = "$SHA" ] || die REVIEW "#$N not prepared at $SHA: run prepare.sh $N"

FLAGS=()
while IFS= read -r f; do FLAGS+=("$f"); done < <(reviewer_flags "$RUN")
SCHEMA="$(cat "$SCRIPTS/findings.schema.json")"

if [ "${2:-}" = "--fix" ]; then
  SID="$(cat "$RUN/reviewer.sid")"
  SESSION=(--resume "$SID")
  PROMPT="The validator rejected your findings JSON. Fix exactly these problems and return the complete corrected JSON:

$(cat "${3:?--fix needs a file}")"
else
  rm -f "$RUN/anchors.json" "$RUN/comments.json" "$RUN/payload.json"
  SID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  echo "$SID" > "$RUN/reviewer.sid"
  echo "$(date -u +%FT%TZ) $SHA $SID" >> "$RUN/sessions.log"
  SESSION=(--session-id "$SID" --name "pr-$N review")
  PROMPT="/pr-review $N"   # the skill's render.sh prints context.md instead of re-rendering (PR_SWEEP_CONTEXT)
fi

cd "$WT" || exit 1
export PR_SWEEP_CONTEXT="$RUN/context.md"
cap "$REVIEW_TIMEOUT" claude -p "${SESSION[@]}" "${FLAGS[@]}" \
  --output-format json --json-schema "$SCHEMA" "$PROMPT" < /dev/null > "$LOG" 2>&1
RC=$?
grep '^{' "$LOG" | tail -1 > "$RUN/review.json"   # cap folds stderr in; the result is the one JSON line
kill_ports "$N"

[ "$RC" -eq 124 ] && die REVIEW "#$N timed out after ${REVIEW_TIMEOUT}s (resume: cd $WT && $CLAUDE_HINT --resume $SID)"
if ! jq -e '.structured_output' "$RUN/review.json" > "$RUN/findings.json" 2>/dev/null; then
  rm -f "$RUN/findings.json"
  echo "REVIEW FAIL: #$N returned no structured output (exit $RC, log: $LOG)"
  { jq -r '.result // empty' "$RUN/review.json" 2>/dev/null || cat "$RUN/review.json"; } | tail -15
  exit 1
fi
echo "$SHA" > "$RUN/findings.sha"

COUNTS="$(jq -r '[.findings[].severity] | group_by(.) | map("\(length) \(.[0])") | join(", ")' "$RUN/findings.json")"
DENIED="$(jq -r '.permission_denials | length | select(. > 0)' "$RUN/review.json" 2>/dev/null)"
COST="$(jq -r '.total_cost_usd // 0 | . * 100 | round / 100' "$RUN/review.json")"
echo "REVIEW PASS #$N (${COUNTS:-no findings}; refuted $(jq .refuted_count "$RUN/findings.json"); \$$COST${DENIED:+; $DENIED tool calls denied})"
