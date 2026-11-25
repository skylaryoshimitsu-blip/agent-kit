#!/usr/bin/env bash
# Build, post, and archive a report.
#
#   report.sh session <report.json>   session report: PDF + #reports post + archive
#   report.sh weekly [YYYY-MM-DD]     weekly rollup:  PDF + #reports post
#
# Archive: reports are saved to the private agent-reports repo
# (cloned next to the project, or at $AGENT_REPORTS_DIR) under reports/<project_id>/.
source "$(dirname "$0")/lib.sh"
set -u

mode="${1:-}"; shift || true
export AGENT_REPORTS_DIR="${AGENT_REPORTS_DIR:-$(dirname "$PROJECT_DIR")/agent-reports}"
REPORTS_URL="${AGENT_REPORTS_URL:-https://github.com/skylaryoshimitsu-blip/agent-reports}"

ensure_archive() {
  if [ ! -d "$AGENT_REPORTS_DIR/.git" ]; then
    git clone -q --depth 50 "$REPORTS_URL" "$AGENT_REPORTS_DIR" 2>/dev/null || return 1
  else
    git -C "$AGENT_REPORTS_DIR" pull -q --ff-only 2>/dev/null || true
  fi
}

case "$mode" in
  session)
    [ -z "${1:-}" ] && { echo "usage: report.sh session <report.json>" >&2; exit 2; }
    python3 "$HOOK_DIR/report.py" build "$1" || exit 1
    out="$PROJECT_DIR/.agent/out.json"
    msg="$(jq -r .message "$out")"; pdf="$(jq -r .pdf "$out")"; js="$(jq -r .json "$out")"
    pid="$(jq -r .project_id "$out")"; stem="$(jq -r .stem "$out")"
    "$HOOK_DIR/discord-post.sh" reports --file "$pdf" "$msg"

    # Archive (best effort; the report has already been delivered to Discord).
    if ensure_archive; then
      dest="$AGENT_REPORTS_DIR/reports/$pid"; mkdir -p "$dest"
      cp "$js" "$dest/$stem.json"; cp "$pdf" "$dest/$stem.pdf"
      git -C "$AGENT_REPORTS_DIR" add "reports/$pid" >/dev/null
      git -C "$AGENT_REPORTS_DIR" -c user.name="agent-kit" -c user.email="agent-kit@users.noreply.github.com" \
        commit -qm "Report: $pid $stem" >/dev/null 2>&1
      br="$(git -C "$AGENT_REPORTS_DIR" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
      [ -z "$br" ] && br=main
      if git -C "$AGENT_REPORTS_DIR" push -q origin "HEAD:$br" 2>/dev/null; then
        echo "archived to agent-reports: reports/$pid/$stem.{json,pdf}"
      else
        sb="$(branch_name)"
        if git -C "$AGENT_REPORTS_DIR" push -q origin "HEAD:refs/heads/$sb" 2>/dev/null; then
          echo "archived to agent-reports on branch $sb (main was not writable from this session)"
        else
          echo "ARCHIVE FAILED: report was posted to Discord but not saved to agent-reports" >&2
          "$HOOK_DIR/discord-post.sh" logs "❌ Report archive failed for \`$pid\` ($stem). The report is in #reports but not in agent-reports."
        fi
      fi
    else
      echo "ARCHIVE FAILED: could not clone agent-reports (is it attached to this session?)" >&2
      "$HOOK_DIR/discord-post.sh" logs "❌ Report archive failed: agent-reports repo not reachable from this session."
    fi
    ;;
  weekly)
    ensure_archive || echo "warning: agent-reports not reachable; weekly totals may be incomplete" >&2
    # Reports pushed to session branches (when main wasn't writable) are included too.
    git -C "$AGENT_REPORTS_DIR" fetch -q --depth 50 origin '+refs/heads/*:refs/remotes/origin/*' 2>/dev/null || true
    for ref in $(git -C "$AGENT_REPORTS_DIR" for-each-ref --format='%(refname)' refs/remotes/origin/ 2>/dev/null); do
      git -C "$AGENT_REPORTS_DIR" archive "$ref" reports 2>/dev/null | tar -x -C "$AGENT_REPORTS_DIR" --skip-old-files 2>/dev/null || true
    done
    python3 "$HOOK_DIR/report.py" weekly "${1:-}" || exit 1
    out="$PROJECT_DIR/.agent/out.json"
    "$HOOK_DIR/discord-post.sh" reports --file "$(jq -r .pdf "$out")" "$(jq -r .message "$out")"
    ;;
  *) echo "usage: report.sh session <report.json> | weekly [YYYY-MM-DD]" >&2; exit 2 ;;
esac
