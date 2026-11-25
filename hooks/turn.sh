#!/usr/bin/env bash
# UserPromptSubmit / Stop hook: records when Golden sends a message ("prompt")
# and when the agent finishes responding ("turn_end"). Used for time tracking.
# Usage: turn.sh prompt|turn_end   (hook JSON on stdin)
source "$(dirname "$0")/lib.sh"

kind="${1:-}"
input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // "unknown"')"
case "$kind" in
  prompt|turn_end) log_event "$kind" "$sid" ;;
esac
exit 0
