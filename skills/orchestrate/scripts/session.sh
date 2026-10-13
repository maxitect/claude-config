#!/usr/bin/env bash
# The /orchestrate skill's opening block: preflight, then (only if it passed) status and the handover. Always
# exits 0, because a failing injected command aborts the whole skill and the orchestrator must see the FAIL.
#
# Usage: session.sh <ticket dir> [team|solo] [<n>]

DIR="$(dirname "$0")"
"$DIR/preflight.sh" "$@" && "$DIR/status.sh" && "$DIR/handover.sh"
exit 0
