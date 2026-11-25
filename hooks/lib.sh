#!/usr/bin/env bash
# Shared helpers for the hook scripts.

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Project folder: from Claude Code, else the git repo we're in, else the repo this kit
# belongs to (kit repo itself, or the project that has .agent-kit/ installed).
find_project_dir() {
  local top kit_parent
  top="$(git rev-parse --show-toplevel 2>/dev/null)" && { echo "$top"; return; }
  kit_parent="$(cd "$HOOK_DIR/.." && pwd)"
  if [ "$(basename "$kit_parent")" = ".agent-kit" ]; then dirname "$kit_parent"; else echo "$kit_parent"; fi
}
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(find_project_dir)}"
AGENT_DIR="$PROJECT_DIR/.agent"
SESSION_LOG="$AGENT_DIR/session-log.jsonl"
mkdir -p "$AGENT_DIR" 2>/dev/null

post() { "$HOOK_DIR/discord-post.sh" "$@"; }

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Times shown in Golden's time zone and US Eastern.
now_human() {
  printf '%s (Manila) / %s (ET)' \
    "$(TZ=Asia/Manila date '+%a %b %-d %-I:%M %p')" \
    "$(TZ=America/New_York date '+%-I:%M %p')"
}

repo_name() {
  local r
  r="$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null | sed -E 's#(\.git)?$##; s#.*[/:]([^/]+/[^/]+)$#\1#')"
  echo "${r:-$(basename "$PROJECT_DIR")}"
}

branch_name() { git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?"; }

head_sha() { git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null; }
upstream_sha() { git -C "$PROJECT_DIR" rev-parse --short '@{u}' 2>/dev/null; }

# Per-session state files (kept in .agent/, never committed).
state_get() { cat "$AGENT_DIR/state-$1-$2" 2>/dev/null; }
state_set() { printf '%s' "$3" > "$AGENT_DIR/state-$1-$2" 2>/dev/null; }

# Post "Session started" once, at the session's first real action.
# Background helper sessions never use tools, so they never get announced.
announce_if_needed() {
  local sid="$1"
  [ -n "$(state_get "$sid" announced)" ] && return 0
  state_set "$sid" announced 1
  local started="$(state_get "$sid" started_human)"
  local br="$(state_get "$sid" start_branch)"
  post logs "🟢 **Session started** — \`$(repo_name)\` on \`${br:-$(branch_name)}\`
${started:-$(now_human)}"
}

# Append one event to the local session log (feeds the step 4 reports).
log_event() {
  # usage: log_event <type> <session_id> [json-extra]
  local extra="${3:-{\}}"
  jq -cn --arg t "$1" --arg s "$2" --arg at "$(now_utc)" --argjson x "$extra" \
    '{type: $t, session: $s, at: $at} + $x' >> "$SESSION_LOG" 2>/dev/null || true
}
