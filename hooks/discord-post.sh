#!/usr/bin/env bash
# Send one message to a Discord channel via webhook, with secrets redacted.
#
# Usage:  hooks/discord-post.sh <logs|approvals|reports|lessons> "message"
#         echo "message" | hooks/discord-post.sh logs
#
# Webhook URLs come from env vars (never from the repo):
#   DISCORD_LOG_WEBHOOK, DISCORD_APPROVALS_WEBHOOK,
#   DISCORD_REPORTS_WEBHOOK, DISCORD_LESSONS_WEBHOOK
#
# DRY_RUN=1 prints the payload instead of sending it.
# This script never fails the session: missing config or network errors exit 0.

set -u

channel="${1:-logs}"
shift || true
if [ "$#" -gt 0 ]; then msg="$*"; else msg="$(cat)"; fi
[ -z "$msg" ] && exit 0

case "$channel" in
  logs)      url="${DISCORD_LOG_WEBHOOK:-}" ;;
  approvals) url="${DISCORD_APPROVALS_WEBHOOK:-}" ;;
  reports)   url="${DISCORD_REPORTS_WEBHOOK:-}" ;;
  lessons)   url="${DISCORD_LESSONS_WEBHOOK:-}" ;;
  *) echo "discord-post: unknown channel '$channel'" >&2; exit 0 ;;
esac

# Redact anything that looks like a secret before it leaves the machine.
redacted="$(printf '%s' "$msg" | sed -E \
  -e 's#https://(ptb\.|canary\.)?discord(app)?\.com/api/webhooks/[^[:space:]]+#[REDACTED_WEBHOOK]#g' \
  -e 's/gh[pousr]_[A-Za-z0-9]{20,}/[REDACTED_TOKEN]/g' \
  -e 's/github_pat_[A-Za-z0-9_]{20,}/[REDACTED_TOKEN]/g' \
  -e 's/sk-[A-Za-z0-9_-]{20,}/[REDACTED_KEY]/g' \
  -e 's/sb_(secret|publishable)_[A-Za-z0-9_-]{10,}/[REDACTED_KEY]/g' \
  -e 's/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/[REDACTED_JWT]/g' \
  -e 's/(Bearer|bearer)[[:space:]]+[A-Za-z0-9._~+\/-]{16,}=*/\1 [REDACTED]/g' \
  -e 's/(postgres(ql)?:\/\/[^:[:space:]]+:)[^@[:space:]]+@/\1[REDACTED]@/g' \
  -e 's/([A-Za-z0-9_]*(KEY|TOKEN|SECRET|PASSWORD|PASS)[A-Za-z0-9_]*[[:space:]]*[=:][[:space:]]*)[^[:space:]"'"'"']+/\1[REDACTED]/gI')"

# Discord's limit is 2000 characters; keep a margin.
if [ "${#redacted}" -gt 1900 ]; then
  redacted="${redacted:0:1880}
…(truncated)"
fi

payload="$(jq -n --arg c "$redacted" '{content: $c, allowed_mentions: {parse: []}}')"

if [ "${DRY_RUN:-0}" = "1" ]; then
  printf '%s\n' "$payload"
  exit 0
fi

if [ -z "$url" ]; then
  echo "discord-post: webhook for '$channel' not set; message not sent" >&2
  exit 0
fi

curl -sS --max-time 8 -H 'Content-Type: application/json' \
  -d "$payload" "$url" >/dev/null 2>&1 || \
  echo "discord-post: send to '$channel' failed" >&2
exit 0
