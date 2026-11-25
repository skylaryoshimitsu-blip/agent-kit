#!/usr/bin/env bash
# SessionStart hook:
#  1. records the start time and current commit (the "started" message is posted
#     at the first tool use, so background helper sessions stay silent)
#  2. prints the kit's rules and tool paths; Claude Code adds this output to the
#     session's context, so every repo with the plugin enabled gets the rules.
source "$(dirname "$0")/lib.sh"

input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // "unknown"')"
src="$(printf '%s' "$input" | jq -r '.source // "startup"')"

case "$src" in
  startup|resume)
    state_set "$sid" started_human "$(now_human)"
    state_set "$sid" start_branch "$(branch_name)"
    state_set "$sid" head "$(head_sha)"
    state_set "$sid" upstream "$(upstream_sha)"
    log_event "session_start" "$sid" "$(jq -cn --arg src "$src" --arg b "$(branch_name)" '{source: $src, branch: $b}')"
    ;;
esac

KIT_DIR="$(cd "$HOOK_DIR/.." && pwd)"

cat <<EOF
## agent-kit is active

Tools (use these exact paths):
- Post to Discord: \`bash "$HOOK_DIR/discord-post.sh" <logs|approvals|reports|lessons> "message"\`
- Verify a deployed URL: \`bash "$HOOK_DIR/verify.sh" <url> [text that must appear]\`
- Reports: \`/report\` (session) and \`/report weekly\`; scripts in \`$HOOK_DIR\` (report.py, report.sh)
- Kit folder (lessons/, profiles/): \`$KIT_DIR\`

Commits, pushes, PRs, and session start/end are posted to #logs automatically.
Plans, gate requests, verification proof, and errors you post yourself with discord-post.sh.
EOF

# Inject the rules only in plugin mode (kit lives outside the project).
# In the kit repo itself and in installed projects (.agent-kit/ + CLAUDE.md import),
# the rules already load through CLAUDE.md.
case "$KIT_DIR/" in
  "$PROJECT_DIR"/*) inside=1 ;;
  *) inside=0 ;;
esac
if [ "$inside" = 0 ] && ! cmp -s "$KIT_DIR/CLAUDE.md" "$PROJECT_DIR/CLAUDE.md" 2>/dev/null; then
  printf '\n---\n\n'
  cat "$KIT_DIR/CLAUDE.md"
fi
exit 0
