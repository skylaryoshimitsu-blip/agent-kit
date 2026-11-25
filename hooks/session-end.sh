#!/usr/bin/env bash
# SessionEnd hook: log the end time and post the session duration to #logs.
# May not fire if the app is closed abruptly; /report also records the end.
source "$(dirname "$0")/lib.sh"

input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // "unknown"')"

start="$(jq -r --arg s "$sid" 'select(.type=="session_start" and .session==$s) | .at' "$SESSION_LOG" 2>/dev/null | head -1)"
commits="$(jq -r --arg s "$sid" 'select(.type=="commit" and .session==$s) | .sha' "$SESSION_LOG" 2>/dev/null | wc -l | tr -d ' ')"

dur="unknown"
if [ -n "$start" ]; then
  secs=$(( $(date -u +%s) - $(date -u -d "$start" +%s 2>/dev/null || echo "$(date -u +%s)") ))
  dur="$((secs / 3600))h $(((secs % 3600) / 60))m"
fi

log_event "session_end" "$sid" "$(jq -cn --arg d "$dur" '{duration: $d}')"
post logs "🔴 **Session ended** — \`$(repo_name)\`
$(now_human) · duration $dur · $commits commit(s)"
exit 0
