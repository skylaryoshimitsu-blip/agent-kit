#!/usr/bin/env bash
# PostToolUse hook (Bash): post commits, pushes, and opened PRs to #logs.
source "$(dirname "$0")/lib.sh"

input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // "unknown"')"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
out="$(printf '%s' "$input" | jq -r '[.tool_response.stdout // "", .tool_response.stderr // ""] | join("\n")')"

case "$cmd" in *git*|*gh\ pr*) ;; *) exit 0 ;; esac

repo="$(repo_name)"

# Commit: git prints "[branch abc1234] subject" on success.
if printf '%s' "$cmd" | grep -qE 'git( -C [^ ]+)?( -c [^ ]+)* commit'; then
  line="$(printf '%s' "$out" | grep -oE '^\[[^]]+ [0-9a-f]{7,}\] .*' | tail -1)"
  if [ -n "$line" ]; then
    br="$(printf '%s' "$line" | sed -E 's/^\[([^] ]+).*/\1/')"
    sha="$(printf '%s' "$line" | sed -E 's/^\[[^ ]+ ([0-9a-f]+)\].*/\1/')"
    subj="$(printf '%s' "$line" | sed -E 's/^\[[^]]+\] //')"
    log_event "commit" "$sid" "$(jq -cn --arg sha "$sha" --arg b "$br" --arg s "$subj" '{sha:$sha, branch:$b, subject:$s}')"
    post logs "📝 Committed \`$sha\` on \`$br\` — $subj"
  fi
fi

# Push: git prints "   old..new  local -> remote" or "* [new branch] x -> x".
if printf '%s' "$cmd" | grep -qE 'git( -C [^ ]+)?( -c [^ ]+)* push'; then
  pline="$(printf '%s' "$out" | grep -E -- '->' | grep -vE 'rejected|error' | tail -1)"
  if [ -n "$pline" ]; then
    rb="$(printf '%s' "$pline" | sed -E 's/.*-> *([^ ]+).*/\1/')"
    sha="$(git -C "$PROJECT_DIR" rev-parse --short "$rb" 2>/dev/null || git -C "$PROJECT_DIR" rev-parse --short HEAD)"
    log_event "push" "$sid" "$(jq -cn --arg sha "$sha" --arg b "$rb" '{sha:$sha, branch:$b}')"
    post logs "⬆️ Pushed \`$sha\` to \`$rb\` (\`$repo\`)"
  elif printf '%s' "$out" | grep -qE 'rejected|error:|fatal:'; then
    post logs "❌ Push failed (\`$repo\`):
\`\`\`
$(printf '%s' "$out" | grep -E 'rejected|error|fatal|hint' | head -8)
\`\`\`"
  fi
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
