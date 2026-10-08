#!/usr/bin/env bash
# One line per PR the sweep knows about: furthest stage reached, head, slot, and how to resume the reviewer.
#
# Usage: status.sh

. "$(dirname "$0")/lib.sh"
[ -d "$SWEEP" ] || { echo "STATUS: nothing swept yet"; exit 0; }

for dir in "$SWEEP"/[0-9]*/; do
  [ -d "$dir" ] || continue
  n="$(basename "$dir")"; r="${dir%/}"
  sha="$(jq -r .sha "$r/meta.json" 2>/dev/null)"
  stage="queued"
  [ "$(cat "$r/prepare.ok" 2>/dev/null)" = "$sha" ] && stage="prepared"
  [ "$(cat "$r/findings.sha" 2>/dev/null)" = "$sha" ] && stage="reviewed"
  [ "$stage" = reviewed ] && [ -f "$r/anchors.json" ] && stage="validated"
  [ "$stage" = validated ] && [ -f "$r/payload.json" ] && stage="commented"
  [ "$(jq -r .sha "$r/posted.json" 2>/dev/null)" = "$sha" ] && stage="posted $(jq -r .url "$r/posted.json")"
  [ -f "$r/failed" ] && stage="FAILED at $(cat "$r/failed") ($stage)"
  slot="$(slot_of "$n")"
  sid="$(cat "$r/reviewer.sid" 2>/dev/null)"
  echo "#$n ${sha:0:7} $stage${slot:+ · slot $slot}${sid:+ · resume: cd $r/wt && claude --resume $sid}"
done
echo "slots in use: $(ls "$SWEEP/slots" 2>/dev/null | wc -l | tr -d ' ')/$MAX_SLOTS"
