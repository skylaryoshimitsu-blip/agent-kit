# Using agent-kit in a project

Add this file to the project repo as `.claude/settings.json` (merge with any existing settings):

```json
{
  "extraKnownMarketplaces": {
    "agent-kit": {
      "source": { "source": "github", "repo": "skylaryoshimitsu-blip/agent-kit" }
    }
  },
  "enabledPlugins": {
    "agent-kit@agent-kit": true
  }
}
```

Or install it by hand inside Claude Code:

```
/plugin install agent-kit --marketplace skylaryoshimitsu-blip/agent-kit
```

Then add `agent-profile.yaml` to the repo root (copy `profiles/_template.yaml` from this kit and fill it in).

New sessions in that repo get: the rules, the modes (`/new`, `/feature`, `/fix`, `/pair`, `/report`, `/handoff`), Discord logging, and `verify.sh`.
If a command name clashes with another plugin, use the long form, e.g. `/agent-kit:fix`.

Required environment variables (set in Claude Code's environment settings, never in a repo):
`DISCORD_LOG_WEBHOOK`, `DISCORD_APPROVALS_WEBHOOK`, `DISCORD_REPORTS_WEBHOOK`, `DISCORD_LESSONS_WEBHOOK`.
