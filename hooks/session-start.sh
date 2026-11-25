#!/usr/bin/env bash
# SessionStart hook: log the start time and announce the session in #logs.
source "$(dirname "$0")/lib.sh"

input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // "unknown"')"
src="$(printf '%s' "$input" | jq -r '.source // "startup"')"

# Only real starts and resumes; skip /clear and compaction restarts.
case "$src" in startup|resume) ;; *) exit 0 ;; esac

log_event "session_start" "$sid" "$(jq -cn --arg src "$src" --arg b "$(branch_name)" '{source: $src, branch: $b}')"
post logs "🟢 **Session ${src/startup/started}** — \`$(repo_name)\` on \`$(branch_name)\`
$(now_human)"
exit 0
