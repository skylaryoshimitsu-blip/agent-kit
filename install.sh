#!/usr/bin/env bash
# Install (or update) agent-kit into a project repo.
#
# Usage (from a clone of agent-kit):   bash install.sh /path/to/project
#
# What it does — all inside the project, nothing is committed:
#   .agent-kit/            rules, hooks, profile template, lessons (copied from this kit)
#   .claude/commands/      /new /feature /fix /pair /report /handoff
#   .claude/settings.json  hooks merged in (existing settings and hooks are kept)
#   CLAUDE.md              one import line: @.agent-kit/CLAUDE.md
#   .gitignore             .agent/ (local session log)
#   agent-profile.yaml     created from the template if missing
#
# Safe to rerun: it replaces only what it installed. Commit the result on a
# branch and open a PR, like any other change.

set -euo pipefail

KIT="$(cd "$(dirname "$0")" && pwd)"
PROJ="${1:-}"
[ -z "$PROJ" ] && { echo "usage: bash install.sh /path/to/project" >&2; exit 2; }
PROJ="$(cd "$PROJ" && pwd)"
[ "$PROJ" = "$KIT" ] && { echo "refusing to install the kit into itself" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

MARK="<!-- installed by agent-kit -->"
version="$(git -C "$KIT" rev-parse --short HEAD 2>/dev/null || echo unknown)"

# 1. Kit files
mkdir -p "$PROJ/.agent-kit/hooks" "$PROJ/.agent-kit/profiles"
cp "$KIT/CLAUDE.md" "$PROJ/.agent-kit/CLAUDE.md"
for f in "$KIT"/hooks/*.sh; do cp "$f" "$PROJ/.agent-kit/hooks/"; done
chmod +x "$PROJ"/.agent-kit/hooks/*.sh
cp "$KIT/profiles/_template.yaml" "$PROJ/.agent-kit/profiles/_template.yaml"
if [ -d "$KIT/lessons" ]; then
  mkdir -p "$PROJ/.agent-kit/lessons" && cp -R "$KIT/lessons/." "$PROJ/.agent-kit/lessons/"
fi
printf '%s\n' "$version" > "$PROJ/.agent-kit/VERSION"

# 2. Commands (never overwrite a project's own command with the same name)
mkdir -p "$PROJ/.claude/commands"
skipped=()
for f in "$KIT"/.claude/commands/*.md; do
  dest="$PROJ/.claude/commands/$(basename "$f")"
  if [ -f "$dest" ] && ! grep -qF "$MARK" "$dest"; then
    skipped+=("$(basename "$f")"); continue
  fi
  { cat "$f"; printf '\n%s\n' "$MARK"; } > "$dest"
done

# 3. Hooks in .claude/settings.json (merge; drop any older agent-kit entries first)
settings="$PROJ/.claude/settings.json"
[ -f "$settings" ] || echo '{}' > "$settings"
kit_hooks='{
  "SessionStart": [{ "hooks": [{ "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.agent-kit/hooks/session-start.sh\"", "timeout": 15 }] }],
  "PostToolUse":  [{ "matcher": "*", "hooks": [{ "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.agent-kit/hooks/post-tool.sh\"", "timeout": 15 }] }],
  "SessionEnd":   [{ "hooks": [{ "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.agent-kit/hooks/session-end.sh\"", "timeout": 15 }] }]
}'
jq --argjson kit "$kit_hooks" '
  .hooks = (.hooks // {})
  | .hooks |= with_entries(.value |= map(select((.hooks // []) | map(.command // "") | any(test("\\.agent-kit/hooks/")) | not)))
  | reduce ($kit | to_entries[]) as $e (.; .hooks[$e.key] = ((.hooks[$e.key] // []) + $e.value))
' "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"

# 4. CLAUDE.md import line
claude_md="$PROJ/CLAUDE.md"
touch "$claude_md"
if ! grep -qxF '@.agent-kit/CLAUDE.md' "$claude_md"; then
  { printf '# Agent rules\n\n@.agent-kit/CLAUDE.md\n\n'; cat "$claude_md"; } > "$claude_md.tmp" && mv "$claude_md.tmp" "$claude_md"
fi

# 5. .gitignore
touch "$PROJ/.gitignore"
grep -qxF '.agent/' "$PROJ/.gitignore" || printf '\n# agent-kit local session log\n.agent/\n' >> "$PROJ/.gitignore"

# 6. Profile
created_profile=0
if [ ! -f "$PROJ/agent-profile.yaml" ]; then
  cp "$KIT/profiles/_template.yaml" "$PROJ/agent-profile.yaml"; created_profile=1
fi

echo "agent-kit $version installed into $PROJ"
[ "$created_profile" = 1 ] && echo "- agent-profile.yaml created from the template: fill it in before building"
[ "${#skipped[@]}" -gt 0 ] && echo "- kept the project's own commands (not overwritten): ${skipped[*]}"
echo "- next: commit on a branch and open a PR"
