#!/usr/bin/env bash
# Prints the active run's state dir and the last session's handover.
#
# Usage: handover.sh

. "$(dirname "$0")/lib.sh"
echo "STATE $STATE"
echo "--- HANDOVER ($STATE/HANDOVER.md)"
cat "$STATE/HANDOVER.md" 2>/dev/null || echo "none: first session"
