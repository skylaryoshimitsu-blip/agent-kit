#!/usr/bin/env bash
# agent-kit PR watcher — runs on your own computer; adds nothing to the client's repo.
#
# Every INTERVAL seconds during your working hours it checks the client repo on GitHub:
#   - your new PRs                → Discord note to the reviewer: "ready for your review"
#   - your approval on a PR       → Discord note to the reviewer: "approved, ready to merge"
#   - reviewer comments/reviews   → runs Claude Code headless to address the feedback
#   - "@claude" from you/reviewer → runs Claude Code headless on that request
# Checking is a GitHub lookup only; Claude runs only when there is something to act on.
#
# Usage:  bash watch.sh <name>          (reads ~/.agent-kit/watch/<name>.conf)
#         bash watch.sh <name> --once   (one check, then exit — for testing)
set -uo pipefail

KIT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:-}"; [ -z "$NAME" ] && { echo "usage: watch.sh <name> [--once]" >&2; exit 2; }
ONCE=0; [ "${2:-}" = "--once" ] && ONCE=1
HOME_DIR="${AGENT_KIT_HOME:-$HOME/.agent-kit}"
CONF="$HOME_DIR/watch/$NAME.conf"
[ -f "$CONF" ] || { echo "missing config: $CONF (copy watch/example.conf)" >&2; exit 2; }
# shellcheck disable=SC1090
source "$CONF"
# Secrets (webhooks) live in a separate file, chmod 600, never in a repo.
[ -f "$HOME_DIR/secrets.env" ] && { set -a; source "$HOME_DIR/secrets.env"; set +a; }

: "${REPO:?}" "${LOCAL_PATH:?}" "${OWNER:?}" "${REVIEWER:?}" "${REVIEWER_DISCORD_ID:?}"
INTERVAL="${INTERVAL:-150}"
HOURS="${HOURS:-00-24}"                 # local hours, e.g. 21-06 (wraps past midnight)
DAYS="${DAYS:-1,2,3,4,5,6,7}"           # local weekdays that start a shift (1=Mon)
PROFILE="${PROFILE:-$HOME_DIR/profiles/$NAME.yaml}"
STATE_DIR="$HOME_DIR/watch/state"; LOG_DIR="$HOME_DIR/watch/logs"
mkdir -p "$STATE_DIR" "$LOG_DIR"
STATE="$STATE_DIR/$NAME.json"; LOCK="$STATE_DIR/$NAME.lock"
LOG="$LOG_DIR/$NAME-$(date +%Y-%m-%d).log"
GH="${GH_BIN:-gh}"; CLAUDE="${CLAUDE_BIN:-claude}"

log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG" >&2; }
team() { DISCORD_TEAM_WEBHOOK="${DISCORD_TEAM_WEBHOOK:-}" bash "$KIT/hooks/discord-post.sh" team --mention "$REVIEWER_DISCORD_ID" "$1"; }
mine() { bash "$KIT/hooks/discord-post.sh" "$1" "$2"; }

# --- working hours -------------------------------------------------------
in_hours() {
  local h d start end
  h=$((10#$(date +%H))); d=$(date +%u)
  start=$((10#${HOURS%-*})); end=$((10#${HOURS#*-}))
  if [ "$start" -lt "$end" ]; then
    [ "$h" -ge "$start" ] && [ "$h" -lt "$end" ] && [[ ",$DAYS," == *",$d,"* ]]
  else
    # overnight shift: evening part counts on a shift day, morning part on the day after one
    local prev=$(( d == 1 ? 7 : d - 1 ))
    { [ "$h" -ge "$start" ] && [[ ",$DAYS," == *",$d,"* ]]; } || \
    { [ "$h" -lt "$end" ] && [[ ",$DAYS," == *",$prev,"* ]]; }
  fi
}

# --- state ---------------------------------------------------------------
[ -f "$STATE" ] || echo '{"seen":[],"announced":[],"approved":[],"bootstrapped":false,"since":""}' > "$STATE"
# any(...) behaves the same in every jq version (index() on arrays differs between versions).
st_has() { jq -e --arg k "$1" --arg v "$2" '(.[$k] // []) | any(.[]; . == $v)' "$STATE" >/dev/null; }
st_add() { jq --arg k "$1" --arg v "$2" '.[$k] += [$v] | .[$k] |= unique' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"; }

trivial() {
  # Comments that need no action: thanks / lgtm / looks good / emoji-only / empty.
  local b; b="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  [ -z "$b" ] && return 0
  [[ "$b" =~ ^(thanks|thank\ you|thx|ty|lgtm|looks\ good|looks\ good\ to\ me|nice|great|perfect|ok|okay|approved|merged|done)[[:space:][:punct:]]*$ ]] && return 0
  printf '%s' "$b" | grep -qE '[a-z0-9]' || return 0   # emoji / punctuation only
  return 1
}

run_claude() {
  local pr="$1" kind="$2"
  if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
    log "claude already running; PR #$pr will be picked up next check"; return 1
  fi
  echo $$ > "$LOCK"
  local task
  if [ "$kind" = feedback ]; then
    task="Address @$REVIEWER's new feedback on PR #$pr in $REPO by following $KIT/.claude/commands/address-feedback.md. Check out the PR branch first with \`gh pr checkout $pr\`."
  else
    task="Handle the new @claude request on #$pr in $REPO (read the PR conversation with gh). If it approves a plan you posted earlier on this PR (a comment starting 'Plan (waiting for Golden's approval)'), implement that plan with any changes Golden asked for, on the PR's branch (\`gh pr checkout $pr\`). Otherwise follow $KIT/.claude/commands/fix.md or feature.md as fits; any code change goes on a branch with a PR."
  fi
  log "running claude for #$pr ($kind)"
  ( cd "$LOCAL_PATH" || exit 90
    git fetch -q origin 2>>"$LOG" || echo "$(date '+%H:%M:%S') git fetch failed; continuing" >> "$LOG"
    "$CLAUDE" -p "$task
Project profile: $PROFILE (owner type client; reviewer $REVIEWER, Discord ID $REVIEWER_DISCORD_ID).
Discord: bash $KIT/hooks/discord-post.sh <team|logs|approvals> [--mention $REVIEWER_DISCORD_ID] \"message\".
Lessons: bash $KIT/hooks/lessons.sh search \"<error>\".
You are running headless from Golden's watcher: skip Section 1 step 0 (hooks check). No one can answer questions mid-run — if you are blocked or the change is too big for feedback_autofix, post a short plan or question to #approvals and stop.
No attribution footers: never add "Generated with Claude Code", "Co-Authored-By: Claude", or session links to commits, PRs, or comments.
Never approve or merge a pull request, never call the merge API, never print secret values." \
      --append-system-prompt "$(cat "$KIT/CLAUDE.md")" \
      --settings '{"attribution":{"commit":"","pr":""}}' \
      --permission-mode acceptEdits \
      --allowedTools "Read,Edit,Write,Glob,Grep,Bash(git:*),Bash(gh pr view:*),Bash(gh pr diff:*),Bash(gh pr checkout:*),Bash(gh pr comment:*),Bash(gh pr create:*),Bash(gh api:*),Bash(gh issue view:*),Bash(npm:*),Bash(npx:*),Bash(pnpm:*),Bash(node:*),Bash(python3:*),Bash(bash $KIT/hooks/:*),Bash(jq:*),Bash(ls:*),Bash(cat:*)" \
      --disallowedTools "Bash(gh pr merge:*),Bash(gh pr review:*),Bash(gh api -X PUT:*),Bash(gh api --method PUT:*),Bash(git push --force:*),Bash(git push -f:*),Bash(git push origin main:*)" \
      >> "$LOG" 2>&1 )
  local rc=$?
  rm -f "$LOCK"
  [ $rc -ne 0 ] && log "claude run for #$pr exited with code $rc"
  return $rc
}

check() {
  local bootstrapped since; bootstrapped="$(jq -r .bootstrapped "$STATE")"; since="$(jq -r '.since // ""' "$STATE")"
  local prs; prs="$($GH pr list -R "$REPO" --author "$OWNER" --state open --json number,url,isDraft,title 2>>"$LOG")" || { log "gh pr list failed"; return; }

  while IFS= read -r p; do
    [ -z "$p" ] && continue
    local n url draft; n="$(jq -r .number <<<"$p")"; url="$(jq -r .url <<<"$p")"; draft="$(jq -r .isDraft <<<"$p")"

    # 1. New PR from you → reviewer note
    if [ "$draft" = false ] && ! st_has announced "$n"; then
      st_add announced "$n"
      [ "$bootstrapped" = true ] && team "PR #$n ready for your review — $url" && log "announced PR #$n"
    fi

    # Gather the reviewer's items and your approvals on this PR
    local items
    items="$( { $GH api "repos/$REPO/issues/$n/comments" --paginate 2>>"$LOG" | jq -c '.[] | {id: ("c" + (.id|tostring)), user: .user.login, body: (.body // ""), state: "", at: (.created_at // "")}';
                $GH api "repos/$REPO/pulls/$n/comments" --paginate 2>>"$LOG" | jq -c '.[] | {id: ("r" + (.id|tostring)), user: .user.login, body: (.body // ""), state: "", at: (.created_at // "")}';
                $GH api "repos/$REPO/pulls/$n/reviews" --paginate 2>>"$LOG" | jq -c '.[] | {id: ("v" + (.id|tostring)), user: .user.login, body: (.body // ""), state: .state, at: (.submitted_at // "")}'; } )"

    local act=0 mention=0 pending=""
    while IFS= read -r it; do
      [ -z "$it" ] && continue
      local id user body state; id="$(jq -r .id <<<"$it")"; user="$(jq -r .user <<<"$it")"; body="$(jq -r .body <<<"$it")"; state="$(jq -r .state <<<"$it")"
      st_has seen "$id" && continue
      [ "$bootstrapped" = true ] || { st_add seen "$id"; continue; }
      # Second safeguard: never act on anything posted before the watcher's first run.
      local at; at="$(jq -r '.at // ""' <<<"$it")"
      if [ -n "$since" ] && [ -n "$at" ] && [[ "$at" < "$since" ]]; then st_add seen "$id"; continue; fi
      if [ "$user" = "$OWNER" ] && [ "$state" = APPROVED ] && ! st_has approved "$n"; then
        st_add approved "$n"; st_add seen "$id"; team "PR #$n approved, ready to merge — $url"; log "approved note PR #$n"
      elif [ "$user" = "$REVIEWER" ] && [ "$state" != APPROVED ] && ! trivial "$body"; then
        act=1; pending="$pending $id"
      elif { [ "$user" = "$OWNER" ] || [ "$user" = "$REVIEWER" ]; } && [[ "$body" == *"@claude"* ]]; then
        mention=1; pending="$pending $id"
      else
        st_add seen "$id"
      fi
    done <<< "$items"

    # Items are marked handled only after a successful run, so a failed run is retried
    # on the next check — up to 3 times, then Golden is told and the items are dropped.
    if [ -n "$pending" ]; then
      local kind=feedback; [ "$act" = 1 ] || kind=request
      if run_claude "$n" "$kind"; then
        for id in $pending; do st_add seen "$id"; done
        jq --arg n "$n" 'del(.fails[$n])' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
      elif [ -e "$LOCK" ]; then :   # another run is in progress; try again next check
      else
        local f; f="$(jq -r --arg n "$n" '(.fails[$n] // 0) + 1' "$STATE")"
        jq --arg n "$n" --argjson f "$f" '.fails[$n] = $f' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
        if [ "$f" -ge 3 ]; then
          for id in $pending; do st_add seen "$id"; done
          mine approvals "❌ Watcher gave up on $REPO PR #$n after 3 failed Claude runs. Please handle it in a session. Logs: ~/.agent-kit/watch/logs on your Mac."
        fi
      fi
    fi
  done <<< "$(printf '%s' "$prs" | jq -c '.[]')"

  if [ "$bootstrapped" != true ]; then
    jq --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.bootstrapped = true | .since = $t' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
    log "first run: recorded existing PRs and comments as already handled"
  fi
}

log "watcher '$NAME' started for $REPO (hours $HOURS, every ${INTERVAL}s)"
while :; do
  if in_hours; then
    # On a Mac, stay awake until the next check (only during working hours).
    command -v caffeinate >/dev/null && { caffeinate -i -t $((INTERVAL + 60)) >/dev/null 2>&1 & }
    check
  fi
  [ "$ONCE" = 1 ] && break
  sleep "$INTERVAL"
done
