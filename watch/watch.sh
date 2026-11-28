#!/usr/bin/env bash
# agent-kit watcher — runs on your own computer; adds nothing to the client's repo.
#
# Every INTERVAL seconds during your working hours it checks the client repo on GitHub:
#   - your new PRs                  → Discord note to the reviewer: "ready for your review"
#   - your approval on a PR         → Discord note to the reviewer: "approved, ready to merge"
#   - reviewer feedback on your PRs → Claude addresses it (no size limit)
#   - reviewer comments on issues   → Claude answers, revises docs, or starts authorized work
#   - "@claude" from you/reviewer   → Claude handles the request (PRs and issues)
# Visibility (your #logs channel): a live status line edited every check, shift start/end,
# one decision line per comment, and start/finish lines for every Claude run.
# Usage limits: when Claude reports its usage limit, the watcher pauses and retries after.
#
# Usage:  bash watch.sh <name>          (reads ~/.agent-kit/watch/<name>.conf)
#         bash watch.sh <name> --once   (one check, then exit — for testing)
#         bash watch.sh <name> --sync-now  (one check now, even outside working hours — use it
#                                          after you finish manual work, so the watcher takes over
#                                          from exactly that point)
set -uo pipefail

KIT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:-}"; [ -z "$NAME" ] && { echo "usage: watch.sh <name> [--once]" >&2; exit 2; }
ONCE=0; FORCE=0
[ "${2:-}" = "--once" ] && ONCE=1
[ "${2:-}" = "--sync-now" ] && { ONCE=1; FORCE=1; }
HOME_DIR="${AGENT_KIT_HOME:-$HOME/.agent-kit}"
CONF="$HOME_DIR/watch/$NAME.conf"
[ -f "$CONF" ] || { echo "missing config: $CONF (copy watch/example.conf)" >&2; exit 2; }
# shellcheck disable=SC1090
source "$CONF"
[ -f "$HOME_DIR/secrets.env" ] && { set -a; source "$HOME_DIR/secrets.env"; set +a; }

: "${REPO:?}" "${LOCAL_PATH:?}" "${OWNER:?}" "${REVIEWER:?}" "${REVIEWER_DISCORD_ID:?}"
INTERVAL="${INTERVAL:-150}"
HOURS="${HOURS:-00-24}"                 # local hours, e.g. 22-07 (wraps past midnight)
DAYS="${DAYS:-1,2,3,4,5,6,7}"           # local weekdays a shift starts on (1=Mon)
ISSUES="${ISSUES:-}"                    # issue numbers always watched, e.g. "2"
PROFILE="${PROFILE:-$HOME_DIR/profiles/$NAME.yaml}"
STATE_DIR="$HOME_DIR/watch/state"; LOG_DIR="$HOME_DIR/watch/logs"
mkdir -p "$STATE_DIR" "$LOG_DIR"
STATE="$STATE_DIR/$NAME.json"
GH="${GH_BIN:-gh}"; CLAUDE="${CLAUDE_BIN:-claude}"

log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG_DIR/$NAME-$(date +%Y-%m-%d).log" >&2; }
# Discord posts never write to stdout (gather_target's stdout is the work list).
team() { bash "$KIT/hooks/discord-post.sh" team --mention "$REVIEWER_DISCORD_ID" "$1" >&2; }
mine() { bash "$KIT/hooks/discord-post.sh" "$1" "$2" >&2; }
short() { printf '%s' "$1" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' | cut -c1-80; }
hm() { date -r "$1" '+%-I:%M %p' 2>/dev/null || date -d "@$1" '+%-I:%M %p'; }

# --- working hours -------------------------------------------------------
in_hours() {
  [ "$FORCE" = 1 ] && return 0
  local h d start end prev
  h=$((10#$(date +%H))); d=$(date +%u)
  start=$((10#${HOURS%-*})); end=$((10#${HOURS#*-}))
  if [ "$start" -lt "$end" ]; then
    [ "$h" -ge "$start" ] && [ "$h" -lt "$end" ] && [[ ",$DAYS," == *",$d,"* ]]
  else
    prev=$(( d == 1 ? 7 : d - 1 ))
    { [ "$h" -ge "$start" ] && [[ ",$DAYS," == *",$d,"* ]]; } || \
    { [ "$h" -lt "$end" ] && [[ ",$DAYS," == *",$prev,"* ]]; }
  fi
}

# --- state ---------------------------------------------------------------
[ -f "$STATE" ] || echo '{}' > "$STATE"
st_jq() { jq "$@" "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"; }
st_jq '.seen //= [] | .noticed //= [] | .announced //= [] | .approved //= [] | .bootstrapped //= false | .since //= ""
       | .issues_bootstrapped //= false | .fails //= {} | .inflight //= null | .paused_until //= 0
       | .on_shift //= false | .shift //= {comments: 0, runs: 0, notes: 0} | .status_msg //= ""'
st_get() { jq -r "$1" "$STATE"; }
# any(...) behaves the same in every jq version (index() on arrays differs between versions).
st_has() { jq -e --arg k "$1" --arg v "$2" '(.[$k] // []) | any(.[]; . == $v)' "$STATE" >/dev/null; }
st_add() { st_jq --arg k "$1" --arg v "$2" '.[$k] += [$v] | .[$k] |= unique'; }
st_count() { st_jq --arg k "$1" '.shift[$k] = ((.shift[$k] // 0) + 1)'; }
# Count a comment once, even if it waits across several checks before it's handled.
note_comment() { st_has noticed "$1" || { st_add noticed "$1"; st_count comments; }; }

trivial() {
  local b; b="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  [ -z "$b" ] && return 0
  [[ "$b" =~ ^(thanks|thank\ you|thx|ty|lgtm|looks\ good|looks\ good\ to\ me|nice|great|perfect|ok|okay|approved|merged|done)[[:space:][:punct:]]*$ ]] && return 0
  printf '%s' "$b" | grep -qE '[a-z0-9]' || return 0
  return 1
}

# --- live status message (edited in place) --------------------------------
status() {
  local text="$1" url="${DISCORD_LOG_WEBHOOK:-}" id payload resp
  if [ "${DRY_RUN:-0}" = 1 ]; then echo "[status] $text" >&2; return; fi
  [ -z "$url" ] && return
  payload="$(jq -n --arg c "$text" '{content: $c, allowed_mentions: {parse: []}}')"
  id="$(st_get .status_msg)"
  if [ -n "$id" ] && curl -sf --max-time 10 -X PATCH -H 'Content-Type: application/json' \
       -d "$payload" "$url/messages/$id" >/dev/null 2>&1; then return; fi
  resp="$(curl -sf --max-time 10 -H 'Content-Type: application/json' -d "$payload" "$url?wait=true" 2>/dev/null)" || return
  id="$(printf '%s' "$resp" | jq -r '.id // empty')"
  [ -n "$id" ] && st_jq --arg i "$id" '.status_msg = $i'
}

# --- Claude runs (one at a time, in the background) ----------------------
prompt_for() {
  local kind="$1" n="$2"
  case "$kind" in
    feedback) echo "Address @$REVIEWER's new feedback on PR #$n in $REPO by following $KIT/.claude/commands/address-feedback.md. Check out the PR branch first with \`gh pr checkout $n\`." ;;
    issue)    echo "Address @$REVIEWER's new comment(s) on issue #$n in $REPO by following $KIT/.claude/commands/address-issue.md." ;;
    request)  echo "Handle the new @claude request on #$n in $REPO (read the conversation with gh; it may be a PR or an issue). If it approves a plan you posted earlier there (a comment starting 'Plan (waiting for Golden's approval)'), implement that plan with any changes Golden asked for. Otherwise follow $KIT/.claude/commands/fix.md or feature.md as fits; any code change goes on a branch with a PR." ;;
  esac
}

launch() {
  local kind="$1" n="$2" ids="$3" ts runlog rcfile task
  ts="$(date +%Y%m%d-%H%M%S)"; runlog="$LOG_DIR/run-$NAME-$ts-$n.log"; rcfile="$STATE_DIR/$NAME-$ts.rc"
  task="$(prompt_for "$kind" "$n")"
  (
    cd "$LOCAL_PATH" || { echo 90 > "$rcfile"; exit; }
    git fetch -q origin >/dev/null 2>&1
    "$CLAUDE" -p "$task
Project profile: $PROFILE (owner type client; reviewer $REVIEWER, Discord ID $REVIEWER_DISCORD_ID).
Discord: bash $KIT/hooks/discord-post.sh <team|logs|approvals> [--mention $REVIEWER_DISCORD_ID] \"message\".
Lessons: bash $KIT/hooks/lessons.sh search \"<error>\".
You are running headless from Golden's watcher: skip Section 1 step 0 (hooks check). There is no size limit on the work. Post a one-line decision to #logs for every comment you look at, starting with 🔎. If something only Golden can provide blocks you, post it to #approvals and stop.
No attribution footers: never add \"Generated with Claude Code\", \"Co-Authored-By: Claude\", or session links to commits, PRs, or comments.
Never approve or merge a pull request, never call the merge API, never print secret values." \
      --append-system-prompt "$(cat "$KIT/CLAUDE.md")" \
      --settings '{"attribution":{"commit":"","pr":""}}' \
      --permission-mode acceptEdits \
      --allowedTools "Read,Edit,Write,Glob,Grep,Bash(git:*),Bash(gh pr view:*),Bash(gh pr diff:*),Bash(gh pr checkout:*),Bash(gh pr comment:*),Bash(gh pr create:*),Bash(gh pr checks:*),Bash(gh run view:*),Bash(gh api:*),Bash(gh issue view:*),Bash(gh issue comment:*),Bash(npm:*),Bash(npx:*),Bash(pnpm:*),Bash(node:*),Bash(python3:*),Bash(python:*),Bash(pytest:*),Bash(pip:*),Bash(bash $KIT/hooks/:*),Bash(jq:*),Bash(ls:*),Bash(cat:*),Bash(mkdir:*)" \
      --disallowedTools "Bash(gh pr merge:*),Bash(gh pr review:*),Bash(gh api -X PUT:*),Bash(gh api --method PUT:*),Bash(git push --force:*),Bash(git push -f:*),Bash(git push origin main:*)" \
      > "$runlog" 2>&1
    echo $? > "$rcfile"
  ) &
  local pid=$!
  st_jq --arg k "$kind" --arg n "$n" --arg ids "$ids" --argjson pid "$pid" --arg log "$runlog" --arg rc "$rcfile" \
        --argjson t "$(date +%s)" '.inflight = {kind: $k, n: $n, ids: $ids, pid: $pid, log: $log, rc: $rc, started: $t}'
  st_count runs
  log "started claude for #$n ($kind), pid $pid"
  mine logs "▶️ Working on #$n ($kind) — $REPO"
}

limit_hit() { grep -qiE 'usage limit|limit reached|rate limit|hit your limit|limit will reset|resets at' "$1" 2>/dev/null; }

finish_inflight() {
  [ "$(st_get '.inflight != null')" = true ] || return 0
  local pid rcfile runlog n kind ids started rc mins
  pid="$(st_get .inflight.pid)"; rcfile="$(st_get .inflight.rc)"; runlog="$(st_get .inflight.log)"
  n="$(st_get .inflight.n)"; kind="$(st_get .inflight.kind)"; ids="$(st_get .inflight.ids)"; started="$(st_get .inflight.started)"
  if [ ! -f "$rcfile" ]; then
    kill -0 "$pid" 2>/dev/null && return 1     # still running
    rc=99                                      # died without an exit code (e.g. Mac restarted)
  else
    rc="$(cat "$rcfile")"; rm -f "$rcfile"
  fi
  mins=$(( ( $(date +%s) - started ) / 60 ))
  st_jq '.inflight = null'
  if [ "$rc" = 0 ]; then
    for id in $ids; do st_add seen "$id"; done
    st_jq --arg n "$n" 'del(.fails[$n])'
    log "finished #$n ($kind) in ${mins}m"
    mine logs "✅ Finished #$n ($kind) in ${mins}m"
  elif limit_hit "$runlog"; then
    local until epoch
    epoch="$(grep -oE 'limit reached\|[0-9]{10}' "$runlog" | tail -1 | cut -d'|' -f2)"
    until="${epoch:-$(( $(date +%s) + 3600 ))}"
    st_jq --argjson u "$until" '.paused_until = $u'
    log "usage limit reached; pausing until $(hm "$until")"
    mine logs "⏸ Claude usage limit reached — pausing until $(hm "$until"), then retrying #$n automatically."
  else
    local f; f="$(jq -r --arg n "$n" '(.fails[$n] // 0) + 1' "$STATE")"
    st_jq --arg n "$n" --argjson f "$f" '.fails[$n] = $f'
    log "run for #$n failed with code $rc (attempt $f)"
    if [ "$f" -ge 3 ]; then
      for id in $ids; do st_add seen "$id"; done
      mine approvals "❌ Watcher gave up on $REPO #$n after 3 failed runs. Comment \`@claude try again\` there, or handle it in a session. Logs: ~/.agent-kit/watch/logs on your Mac."
    else
      mine logs "⚠️ Run for #$n failed (attempt $f of 3) — retrying on the next check."
    fi
  fi
}

# --- gather work ---------------------------------------------------------
# Prints one line per target that needs Claude: "<kind> <number> <ids...>"
gather_target() {
  local n="$1" is_pr="$2" url="$3" bootstrapped="$4" items since act=0 mention=0 pending=""
  since="$(st_get '.since // ""')"
  if [ "$is_pr" = 1 ]; then
    items="$( { $GH api "repos/$REPO/issues/$n/comments" --paginate 2>>"$LOG_DIR/gh.err" | jq -c '.[] | {id: ("c" + (.id|tostring)), user: .user.login, body: (.body // ""), state: "", at: (.created_at // "")}';
                $GH api "repos/$REPO/pulls/$n/comments" --paginate 2>>"$LOG_DIR/gh.err" | jq -c '.[] | {id: ("r" + (.id|tostring)), user: .user.login, body: (.body // ""), state: "", at: (.created_at // "")}';
                $GH api "repos/$REPO/pulls/$n/reviews" --paginate 2>>"$LOG_DIR/gh.err" | jq -c '.[] | {id: ("v" + (.id|tostring)), user: .user.login, body: (.body // ""), state: .state, at: (.submitted_at // "")}'; } )"
  else
    items="$($GH api "repos/$REPO/issues/$n/comments" --paginate 2>>"$LOG_DIR/gh.err" | jq -c '.[] | {id: ("c" + (.id|tostring)), user: .user.login, body: (.body // ""), state: "", at: (.created_at // "")}')"
  fi
  while IFS= read -r it; do
    [ -z "$it" ] && continue
    local id user body state at
    id="$(jq -r .id <<<"$it")"; user="$(jq -r .user <<<"$it")"; body="$(jq -r .body <<<"$it")"
    state="$(jq -r .state <<<"$it")"; at="$(jq -r .at <<<"$it")"
    st_has seen "$id" && continue
    [ "$bootstrapped" = true ] || { st_add seen "$id"; continue; }
    if [ -n "$since" ] && [ -n "$at" ] && [[ "$at" < "$since" ]]; then st_add seen "$id"; continue; fi
    if [ "$is_pr" = 1 ] && [ "$user" = "$OWNER" ] && [ "$state" = APPROVED ]; then
      st_add seen "$id"
      if ! st_has approved "$n"; then st_add approved "$n"; team "PR #$n approved, ready to merge — $url"; st_count notes; log "approved note #$n"; fi
    elif [ "$user" = "$REVIEWER" ] && [ "$state" != APPROVED ] && ! trivial "$body"; then
      act=1; pending="$pending $id"; note_comment "$id"
    elif { [ "$user" = "$OWNER" ] || [ "$user" = "$REVIEWER" ]; } && [[ "$body" == *"@claude"* ]]; then
      mention=1; pending="$pending $id"; note_comment "$id"
    else
      st_add seen "$id"
      if [ "$user" = "$REVIEWER" ]; then
        st_count comments
        mine logs "🔎 $REVIEWER on #$n: \"$(short "$body")\" → no action (acknowledgment/approval)"
      fi
    fi
  done <<< "$items"
  if [ -n "$pending" ]; then
    local kind=request
    if [ "$act" = 1 ]; then if [ "$is_pr" = 1 ]; then kind=feedback; else kind=issue; fi; fi
    echo "$kind $n$pending"
  fi
}

check() {
  local bootstrapped prs issues work="" issue_boot
  bootstrapped="$(st_get .bootstrapped)"
  prs="$($GH pr list -R "$REPO" --author "$OWNER" --state open --json number,url,isDraft 2>>"$LOG_DIR/gh.err")" || { log "gh pr list failed (see gh.err)"; return 1; }
  issues="$($GH issue list -R "$REPO" --state open --search "involves:$OWNER" --json number,url 2>>"$LOG_DIR/gh.err")" || issues='[]'
  [ -z "$issues" ] && issues='[]'
  for i in $(echo "$ISSUES" | tr ',' ' '); do
    issues="$(jq -c --argjson n "$i" 'if any(.[]; .number == $n) then . else . + [{number: $n, url: ""}] end' <<<"$issues")"
  done

  # The first time issues are watched, existing issue comments are recorded, not acted on.
  issue_boot="$bootstrapped"
  [ "$(st_get .issues_bootstrapped)" = true ] || issue_boot=false

  while IFS= read -r p; do
    [ -z "$p" ] && continue
    local n url draft
    n="$(jq -r .number <<<"$p")"; url="$(jq -r .url <<<"$p")"; draft="$(jq -r .isDraft <<<"$p")"
    if [ "$draft" = false ] && ! st_has announced "$n"; then
      st_add announced "$n"
      if [ "$bootstrapped" = true ]; then team "PR #$n ready for your review — $url"; st_count notes; log "announced PR #$n"; fi
    fi
    work="$work$(gather_target "$n" 1 "$url" "$bootstrapped")"$'\n'
  done <<< "$(jq -c '.[]' <<<"$prs")"

  while IFS= read -r p; do
    [ -z "$p" ] && continue
    work="$work$(gather_target "$(jq -r .number <<<"$p")" 0 "$(jq -r .url <<<"$p")" "$issue_boot")"$'\n'
  done <<< "$(jq -c '.[]' <<<"$issues")"

  if [ "$bootstrapped" != true ]; then
    st_jq --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.bootstrapped = true | .since = $t'
    log "first run: recorded existing PRs and comments as already handled"
  fi
  if [ "$(st_get .issues_bootstrapped)" != true ]; then
    st_jq '.issues_bootstrapped = true'
    log "issue watching enabled: recorded existing issue comments as already handled"
  fi

  OPEN_PRS="$(jq length <<<"$prs")"; WATCHED_ISSUES="$(jq length <<<"$issues")"
  QUEUED="$(printf '%s' "$work" | grep -c . || true)"

  # Start the next piece of work (one Claude run at a time; the rest waits, unmarked).
  local now paused first
  now="$(date +%s)"; paused="$(st_get .paused_until)"
  if [ "$(st_get '.inflight != null')" != true ] && [ "$now" -ge "$paused" ]; then
    first="$(printf '%s' "$work" | grep . | head -1)"
    if [ -n "$first" ]; then
      # shellcheck disable=SC2086
      set -- $first
      local kind="$1" num="$2"; shift 2
      launch "$kind" "$num" "$*"
      QUEUED=$(( QUEUED - 1 ))
    fi
  fi
}

status_line() {
  local now running="nothing" paused extra=""
  now="$(date '+%a %-I:%M %p')"
  if [ "$(st_get '.inflight != null')" = true ]; then
    running="#$(st_get .inflight.n) ($(st_get .inflight.kind)), started $(( ( $(date +%s) - $(st_get .inflight.started) ) / 60 ))m ago"
  fi
  paused="$(st_get .paused_until)"
  [ "$(date +%s)" -lt "$paused" ] && extra=" · ⏸ paused (usage limit) until $(hm "$paused")"
  status "🟢 Watcher online — $REPO · last check $now · open PRs: ${OPEN_PRS:-?} · issues watched: ${WATCHED_ISSUES:-?} · working on: $running · waiting: ${QUEUED:-0}$extra"
}

log "watcher '$NAME' started for $REPO (hours $HOURS, days $DAYS, every ${INTERVAL}s)"
while :; do
  if in_hours; then
    command -v caffeinate >/dev/null && { caffeinate -i -t $((INTERVAL + 60)) >/dev/null 2>&1 & }
    if [ "$(st_get .on_shift)" != true ]; then
      st_jq '.on_shift = true | .shift = {comments: 0, runs: 0, notes: 0}'
      mine logs "🟢 Shift started — watching $REPO (PRs and issues)."
    fi
    finish_inflight
    check
    status_line
  else
    finish_inflight
    if [ "$(st_get .on_shift)" = true ]; then
      st_jq '.on_shift = false'
      mine logs "🔴 Shift ended — comments seen: $(st_get .shift.comments), Claude runs: $(st_get .shift.runs), notes to $REVIEWER: $(st_get .shift.notes)."
      status "😴 Watcher off shift — $REPO · resumes at the next shift ($HOURS local, days $DAYS)"
    fi
  fi
  if [ "$ONCE" = 1 ]; then
    [ "$(st_get '.inflight != null')" = true ] && wait
    finish_inflight
    break
  fi
  sleep "$INTERVAL"
done
