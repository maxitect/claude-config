#!/usr/bin/env bash
# One PR end to end: prepare -> review -> validate -> comment -> post, then frees its stack. Each stage is
# skipped when its output already exists for the current head, so re-running after a failure resumes.
#
# Usage: run.sh <pr>
# Prints the stage lines and a final RUN PASS / RUN FAIL line. Marks $SWEEP/<pr>/failed on failure.

. "$(dirname "$0")/lib.sh"
N="${1:?usage: run.sh <pr>}"
RUN="$(run_dir "$N")"; WT="$(wt_dir "$N")"
mkdir -p "$RUN"
rm -f "$RUN/failed"

# Head moved since the last sweep: archive the old head's artefacts, keep sessions.log for resuming.
QUEUED="$(jq -r ".[] | select(.number==$N) | .sha" "$SWEEP/queue.json" 2>/dev/null)"
OLD="$(cat "$RUN/prepare.ok" 2>/dev/null)"
if [ -n "$OLD" ] && [ -n "$QUEUED" ] && [ "$OLD" != "$QUEUED" ]; then
  mkdir -p "$RUN/history/${OLD:0:7}"
  for f in prepare.ok context.md findings.json findings.sha review.json review.md anchors.json comments.json \
           commenter.json payload.json posted.json "pr-$N-review.md"; do
    [ -e "$RUN/$f" ] && mv "$RUN/$f" "$RUN/history/${OLD:0:7}/"
  done
fi

stage() {
  local name="$1"; shift
  if ! "$@"; then
    echo "$name" > "$RUN/failed"
    "$SCRIPTS/teardown.sh" "$N" >/dev/null
    echo "RUN FAIL: #$N at $name (re-run run.sh $N to resume from here)"
    exit 1
  fi
}

SHA="${QUEUED:-$(jq -r .sha "$RUN/meta.json" 2>/dev/null)}"
prepared() {
  [ -n "$SHA" ] && [ "$(cat "$RUN/prepare.ok" 2>/dev/null)" = "$SHA" ] || return 1
  [ "$(meta "$N" .mig)" != "true" ] || [ -n "$(supabase_db_url "$WT")" ]   # a failed run stopped its stack
}
prepared || stage prepare "$SCRIPTS/prepare.sh" "$N"
SHA="$(meta "$N" .sha)"
BASE="origin/$(meta "$N" .base)"

[ "$(cat "$RUN/findings.sha" 2>/dev/null)" = "$SHA" ] || stage review "$SCRIPTS/review.sh" "$N"

validate() { (cd "$WT" && python3 "$SCRIPTS/validate.py" "$RUN" "$BASE"); }
if [ ! -f "$RUN/anchors.json" ]; then
  if ! validate > "$RUN/validate.txt"; then
    cat "$RUN/validate.txt"
    stage review-fix "$SCRIPTS/review.sh" "$N" --fix "$RUN/validate.txt"
    stage validate validate
  else
    cat "$RUN/validate.txt"
  fi
fi

[ -f "$RUN/payload.json" ] || stage comment "$SCRIPTS/comment.sh" "$N"
stage post python3 "$SCRIPTS/post.py" "$RUN" "$SLUG" "$N"
"$SCRIPTS/teardown.sh" "$N" >/dev/null

echo "RUN PASS #$N $(jq -r .url "$RUN/posted.json") · report $RUN/review.md · resume: cd $WT && claude --resume $(cat "$RUN/reviewer.sid")"
