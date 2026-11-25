# Using agent-kit in a project

## Main way: install script (works in cloud/phone sessions)

From a clone of agent-kit, with the project cloned next to it:

```
bash install.sh /path/to/project
```

This copies the kit into the project's `.agent-kit/` folder, adds the commands
(`/new`, `/feature`, `/fix`, `/pair`, `/report`, `/handoff`) to `.claude/commands/`,
merges the hooks into `.claude/settings.json` (existing settings are kept), adds
`@.agent-kit/CLAUDE.md` to the project's CLAUDE.md, and creates `agent-profile.yaml`
from the template if missing.

Commit the result on a branch and open a PR. To update a project to the latest kit,
rerun the script — it replaces only what it installed — and open a PR again.
`.agent-kit/VERSION` shows which kit commit a project is on.

If the project already has a command with the same name (e.g. its own `fix.md`),
the script keeps the project's version and tells you.

## Optional: plugin (desktop/terminal Claude Code only)

Cloud sessions don't load plugins from repo settings, so this is only for local use:

```
/plugin install agent-kit --marketplace skylaryoshimitsu-blip/agent-kit
```

Commands are then `/agent-kit:fix` etc. Don't use the plugin in a repo that also has
the kit installed by script — the hooks would run twice.

## Environment variables

Set in Claude Code's environment settings, never in a repo:
`DISCORD_LOG_WEBHOOK`, `DISCORD_APPROVALS_WEBHOOK`, `DISCORD_REPORTS_WEBHOOK`, `DISCORD_LESSONS_WEBHOOK`.

## Reports archive

`/report` posts to #reports and also saves each report (JSON + PDF) to the private
`agent-reports` repo under `reports/<project_id>/`. The weekly rollup reads from it.

- The repo is cloned next to the project (`../agent-reports`) on first use.
- In cloud sessions, attach `agent-reports` to the session (with push access).
  If it isn't reachable, the report still posts to #reports but is not archived,
  and an "archive failed" message goes to #logs.

Optional overrides (defaults work for most setups):

- `AGENT_REPORTS_DIR` — local path of the archive clone. Default: `../agent-reports`
  (the folder next to the project).
- `AGENT_REPORTS_URL` — git URL of the archive repo.
  Default: `https://github.com/skylaryoshimitsu-blip/agent-reports`.
