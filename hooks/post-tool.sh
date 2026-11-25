#!/usr/bin/env bash
# PostToolUse hook (all tools):
#  - announces the session in #logs on its first tool use
#  - posts commits (detected by HEAD changing), pushes, and opened PRs
source "$(dirname "$0")/lib.sh"

input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // "unknown"')"
tool="$(printf '%s' "$input" | jq -r '.tool_name // ""')"

announce_if_needed "$sid"

[ "$tool" = "Bash" ] || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
case "$cmd" in *git*|*gh\ pr*) ;; *) exit 0 ;; esac
out="$(printf '%s' "$input" | jq -r '[.tool_response.stdout // "", .tool_response.stderr // ""] | join("\n")')"

repo="$(repo_name)"
prev_head="$(state_get "$sid" head)"
cur_head="$(head_sha)"
br="$(branch_name)"

# Commit: HEAD moved during a command that ran `git commit`.
# Works regardless of -q, combined commands, or how output is printed.
if printf '%s' "$cmd" | grep -qE 'git( -C [^ ]+)?( -c [^ ]+)* commit' \
   && [ -n "$cur_head" ] && [ "$cur_head" != "$prev_head" ]; then
  subj="$(git -C "$PROJECT_DIR" log -1 --format=%s 2>/dev/null)"
  log_event "commit" "$sid" "$(jq -cn --arg sha "$cur_head" --arg b "$br" --arg s "$subj" '{sha:$sha, branch:$b, subject:$s}')"
  post logs "📝 Committed \`$cur_head\` on \`$br\` — $subj"
fi
[ -n "$cur_head" ] && state_set "$sid" head "$cur_head"

# Push: read git's "x -> y" line; if output was suppressed, fall back to
# checking whether the branch's upstream moved.
if printf '%s' "$cmd" | grep -qE 'git( -C [^ ]+)?( -c [^ ]+)* push'; then
  # Drop harmless push-negotiation noise ("expected 'acknowledgments'…") before judging.
  out="$(printf '%s' "$out" | grep -vE "acknowledgments|push negotiation")"
  prev_up="$(state_get "$sid" upstream)"
  cur_up="$(upstream_sha)"
  pline="$(printf '%s' "$out" | grep -E -- '->' | grep -vE 'rejected|error' | tail -1)"
  if [ -n "$pline" ]; then
    rb="$(printf '%s' "$pline" | sed -E 's/.*-> *([^ ]+).*/\1/')"
    sha="$(git -C "$PROJECT_DIR" rev-parse --short "$rb" 2>/dev/null || echo "$cur_head")"
    log_event "push" "$sid" "$(jq -cn --arg sha "$sha" --arg b "$rb" '{sha:$sha, branch:$b}')"
    post logs "⬆️ Pushed \`$sha\` to \`$rb\` (\`$repo\`)"
  elif [ -n "$cur_up" ] && [ "$cur_up" != "$prev_up" ]; then
    log_event "push" "$sid" "$(jq -cn --arg sha "$cur_up" --arg b "$br" '{sha:$sha, branch:$b}')"
    post logs "⬆️ Pushed \`$cur_up\` to \`$br\` (\`$repo\`)"
  elif printf '%s' "$out" | grep -qE 'rejected|error: failed to push|denied|Authentication failed|could not read|returned error: 4[0-9][0-9]'; then
    post logs "❌ Push failed (\`$repo\`):
\`\`\`
$(printf '%s' "$out" | grep -E 'rejected|error|fatal|hint' | head -8)
\`\`\`"
  fi
  [ -n "$cur_up" ] && state_set "$sid" upstream "$cur_up"
fi

# PR opened: gh prints the PR URL.
if printf '%s' "$cmd" | grep -qE 'gh pr create'; then
  url="$(printf '%s' "$out" | grep -oE 'https://github\.com/[^ ]+/pull/[0-9]+' | tail -1)"
  if [ -n "$url" ]; then
    log_event "pr_opened" "$sid" "$(jq -cn --arg u "$url" '{url:$u}')"
    post logs "🔀 PR opened: $url"
  fi
fi
exit 0
