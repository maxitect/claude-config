#!/usr/bin/env bash
# Runs the Sonnet commenter headless over the validated findings and assembles the review payload.
#
# Usage: comment.sh <pr>
# Writes $SWEEP/<pr>/{commenter.sid,comments.json,pr-body.md,payload.json}. One strict-check retry in the
# same session, then assemble.py repairs whatever is left.

. "$(dirname "$0")/lib.sh"
N="${1:?usage: comment.sh <pr>}"
RUN="$(run_dir "$N")"; WT="$(wt_dir "$N")"
LOG="$RUN/comment.log"; : > "$LOG"
[ -f "$RUN/anchors.json" ] || die COMMENT "#$N has no anchors.json: run validate first"

gh pr view "$N" --repo "$SLUG" --json body -q .body > "$RUN/pr-body.md" || die COMMENT "gh pr view $N failed"
INPUT="$(jq -n --slurpfile m "$RUN/meta.json" --slurpfile f "$RUN/findings.json" --slurpfile a "$RUN/anchors.json" '
  {pr: ($m[0] | {number, title, url}),
   reviewer_summary: $f[0].summary,
   issue_coverage: $f[0].issue_coverage,
   findings: [$f[0].findings[] | . + {anchor: $a[0][.id].kind, has_suggestion: ($a[0][.id].suggestion != null)}]}')"

SID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
echo "$SID" > "$RUN/commenter.sid"
COMMON=(--agent pr-commenter --model sonnet --permission-mode dontAsk --add-dir "$HOME/.claude/commands" --allowedTools "Read,Grep,Glob"
        --output-format json --json-schema "$(cat "$SCRIPTS/comments.schema.json")")

extract() {
  grep '^{' "$LOG" | tail -1 > "$RUN/commenter.json"   # cap folds stderr in; the result is the last JSON line
  jq -e '.structured_output' "$RUN/commenter.json" > "$RUN/comments.json" 2>/dev/null \
    || { echo "COMMENT FAIL: #$N commenter returned no structured output (log: $LOG)"; jq -r '.result // empty' "$RUN/commenter.json" | tail -10; exit 1; }
}

cd "$WT" || exit 1
cap 900 claude -p --session-id "$SID" --name "pr-$N comments" "${COMMON[@]}" \
  "Write the pending review for this PR per your protocol.

$INPUT" < /dev/null >> "$LOG" 2>&1
extract

if ! PROBLEMS="$(python3 "$SCRIPTS/assemble.py" "$RUN" "$RUN/pr-body.md" --strict)"; then
  cap 600 claude -p --resume "$SID" "${COMMON[@]}" \
    "Fix exactly these problems and return the complete corrected JSON:

$PROBLEMS" < /dev/null >> "$LOG" 2>&1
  extract
fi

python3 "$SCRIPTS/assemble.py" "$RUN" "$RUN/pr-body.md" | sed "s/^ASSEMBLE PASS/COMMENT PASS #$N/"
