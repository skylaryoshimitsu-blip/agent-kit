#!/usr/bin/env bash
# Set up the watcher on a Mac so it starts at login (it keeps the Mac awake during working hours only).
# Usage: bash watch/install-mac.sh <name>     (after creating ~/.agent-kit/watch/<name>.conf)
# Stop/remove: launchctl unload ~/Library/LaunchAgents/com.agentkit.watch.<name>.plist && rm that file
set -euo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:-}"; [ -z "$NAME" ] && { echo "usage: install-mac.sh <name>" >&2; exit 2; }
H="$HOME/.agent-kit"
[ -f "$H/watch/$NAME.conf" ] || { echo "create $H/watch/$NAME.conf first (see watch/example.conf)" >&2; exit 2; }
[ -f "$H/secrets.env" ] && chmod 600 "$H/secrets.env"
for b in gh jq claude; do command -v "$b" >/dev/null || { echo "missing: $b (install it first)" >&2; exit 2; }; done
gh auth status >/dev/null 2>&1 || { echo "run: gh auth login" >&2; exit 2; }
PLIST="$HOME/Library/LaunchAgents/com.agentkit.watch.$NAME.plist"
mkdir -p "$HOME/Library/LaunchAgents" "$H/watch/logs"
PATH_LINE="$(dirname "$(command -v gh)"):$(dirname "$(command -v claude)"):$(dirname "$(command -v jq)"):/usr/bin:/bin:/usr/sbin:/sbin"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.agentkit.watch.$NAME</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>$KIT/watch/watch.sh</string><string>$NAME</string>
  </array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$PATH_LINE</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$H/watch/logs/$NAME.out</string>
  <key>StandardErrorPath</key><string>$H/watch/logs/$NAME.err</string>
</dict></plist>
PL
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "Watcher '$NAME' installed and running. Logs: $H/watch/logs/"
echo "Stop it: launchctl unload $PLIST"
