#!/usr/bin/env bash
# SessionStart hook: record the start time and current commit.
# Nothing is posted here: the "started" message goes out at the first tool use
# (see announce_if_needed in lib.sh), so background helper sessions stay silent.
source "$(dirname "$0")/lib.sh"

input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // "unknown"')"
src="$(printf '%s' "$input" | jq -r '.source // "startup"')"

# Only real starts and resumes; skip /clear and compaction restarts.
case "$src" in startup|resume) ;; *) exit 0 ;; esac

state_set "$sid" started_human "$(now_human)"
state_set "$sid" start_branch "$(branch_name)"
state_set "$sid" head "$(head_sha)"
state_set "$sid" upstream "$(upstream_sha)"
log_event "session_start" "$sid" "$(jq -cn --arg src "$src" --arg b "$(branch_name)" '{source: $src, branch: $b}')"
exit 0
