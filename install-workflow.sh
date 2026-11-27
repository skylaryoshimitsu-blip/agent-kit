#!/usr/bin/env bash
# Add the PR-feedback GitHub workflow to a project that already has the kit installed.
#
# Usage: bash install-workflow.sh <project path> --owner <github login> --reviewer <github login> --reviewer-discord-id <id>
#
# Then add repo secrets (GitHub → repo → Settings → Secrets and variables → Actions):
#   CLAUDE_CODE_OAUTH_TOKEN   from `claude setup-token` on your own computer
#   DISCORD_TEAM_WEBHOOK      the channel shared with the reviewer
#   DISCORD_LOG_WEBHOOK, DISCORD_APPROVALS_WEBHOOK   your own channels for this client
# Remove later: delete .github/workflows/agent-kit-pr-feedback.yml and those secrets,
# and revoke the token in your Claude settings.
set -euo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
PROJ="${1:-}"; shift || true
owner=""; reviewer=""; rid=""
while [ $# -gt 0 ]; do
  case "$1" in
    --owner) owner="$2"; shift 2 ;;
    --reviewer) reviewer="$2"; shift 2 ;;
    --reviewer-discord-id) rid="$2"; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
[ -d "$PROJ/.agent-kit" ] || { echo "install the kit first: bash install.sh $PROJ" >&2; exit 2; }
[[ "$owner" =~ ^[A-Za-z0-9-]+$ && "$reviewer" =~ ^[A-Za-z0-9-]+$ && "$rid" =~ ^[0-9]{5,25}$ ]] || {
  echo "usage: bash install-workflow.sh <project> --owner <login> --reviewer <login> --reviewer-discord-id <id>" >&2; exit 2; }
mkdir -p "$PROJ/.github/workflows"
sed -e "s/__OWNER__/$owner/g" -e "s/__REVIEWER__/$reviewer/g" -e "s/__REVIEWER_DISCORD_ID__/$rid/g" \
  "$KIT/kit/workflows/claude-pr-feedback.yml" > "$PROJ/.github/workflows/agent-kit-pr-feedback.yml"
echo "Workflow written: .github/workflows/agent-kit-pr-feedback.yml (owner=$owner, reviewer=$reviewer)"
echo "Next: add the repo secrets listed at the top of this script, then commit on a branch and open a PR."
