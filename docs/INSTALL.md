# Using agent-kit in a project

## One-time account setup (Claude Code environment variables)

Add these once in claude.ai/code → environment → Edit → Environment variables. Every
project reuses them; the agent copies what each project needs into its hosting itself.

| Name | Where to get it |
|---|---|
| `DISCORD_LOG_WEBHOOK`, `DISCORD_APPROVALS_WEBHOOK`, `DISCORD_REPORTS_WEBHOOK`, `DISCORD_LESSONS_WEBHOOK` | Discord channel → Edit Channel → Integrations → Webhooks |
| `VERCEL_TOKEN` | vercel.com → Account Settings → Tokens |
| `SUPABASE_ACCESS_TOKEN` | supabase.com → Account → Access Tokens |
| `CAPTIONS_ANTHROPIC_API_KEY` | console.anthropic.com → API Keys (`ANTHROPIC_API_KEY` is reserved by Claude Code, so use this name) |
| `DEEPGRAM_API_KEY` | console.deepgram.com → API Keys |
| `INNGEST_EVENT_KEY`, `INNGEST_SIGNING_KEY` | app.inngest.com → Manage (Production environment) |

New keys only reach sessions started after they're saved, and only in the environment
that holds them.

## Brand-new repo (first session)

Slash commands only exist after the kit is installed, so the first message must not start
with `/`. In a new session on the new repo, send:

> Install the agent kit into this repo: attach skylaryoshimitsu-blip/agent-kit to this
> session, clone it next to this repo, run `bash ../agent-kit/install.sh .`, commit on this
> session's branch and open a PR into main. Then follow `.claude/commands/new.md` for this
> request: <describe the project>.

The agent installs the kit, writes the spec, and stops at the spec gate. After that it
provisions Supabase and Vercel itself.

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
- **Start cloud sessions with only the project repo attached.** A session with two or
  more repos starts in a parent folder, and the kit's hooks don't load there (no
  measured time, no automatic #logs messages).
- When `/report` needs `agent-reports` (or a lesson PR needs `agent-kit`), the agent
  attaches it mid-session, then runs `report.sh archive` (or reruns `lessons.sh propose`).
  The report itself has already posted to #reports, so it is never posted twice.

Optional overrides (defaults work for most setups):

- `AGENT_REPORTS_DIR` — local path of the archive clone. Default: `../agent-reports`
  (the folder next to the project).
- `AGENT_REPORTS_URL` — git URL of the archive repo.
  Default: `https://github.com/skylaryoshimitsu-blip/agent-reports`.

## Automatic PR feedback from your Mac (no changes to the client's repo)

The watcher runs on your own computer during your working hours. Every ~2.5 minutes it
checks the client repo on GitHub and:
- tags the reviewer in the shared Discord channel when you open a PR ("ready for your review")
  or approve one ("approved, ready to merge") — no Claude run needed;
- runs Claude Code when the reviewer leaves feedback on your PRs (no tag needed; "thanks",
  "LGTM", emoji and approvals are ignored) or when you or they write "@claude";
- runs Claude Code on the reviewer's comments on issues you're involved in (plus `ISSUES` in the
  config): answers questions, revises documents, and starts work they authorize.
Visibility in your #logs: a live status line edited every check, shift start/end lines, a 🔎
decision line for every comment, and ▶️/✅ lines for every Claude run.
If Claude hits your usage limit, the watcher pauses (⏸ in #logs) and retries when it resets.
Nothing is added to the client's repo. A failed run is retried twice, then you're told in #approvals.
Set `autofix_max_lines: 0` in the profile for no size limit on feedback fixes.

One-time setup on the Mac (Terminal):
1. Install tools: `brew install gh jq` and `npm install -g @anthropic-ai/claude-code`.
   Log in: `gh auth login` and `claude` (then exit).
2. Clone the kit and the client repo: `git clone https://github.com/skylaryoshimitsu-blip/agent-kit ~/agent-kit`
   and `git clone <client repo> ~/code/<name>`.
3. Config: `mkdir -p ~/.agent-kit/watch ~/.agent-kit/profiles`, copy `watch/example.conf` to
   `~/.agent-kit/watch/<name>.conf` and fill it in; copy `profiles/_template.yaml` to
   `~/.agent-kit/profiles/<name>.yaml` (owner type client, team settings).
4. Secrets: copy `watch/secrets.env.example` to `~/.agent-kit/secrets.env`, paste the webhooks
   there (only there), then `chmod 600 ~/.agent-kit/secrets.env`.
5. Test once: `bash ~/agent-kit/watch/watch.sh <name> --once` — the first run only records
   what already exists; it doesn't act on old comments.
6. Start it at login: `bash ~/agent-kit/watch/install-mac.sh <name>`.

Keep the Mac plugged in during your shift (it stays awake by itself during working hours).
Stop: `launchctl unload ~/Library/LaunchAgents/com.agentkit.watch.<name>.plist`.
Update the kit: `git -C ~/agent-kit pull`.

## Automatic PR feedback (GitHub workflow, optional)

For client repos where a developer reviews your PRs: their comments trigger Claude in GitHub
Actions within about a minute — no server, uses your Claude subscription.

1. Install the kit in the repo (above), then:
   `bash ../agent-kit/install-workflow.sh . --owner <your login> --reviewer <their login> --reviewer-discord-id <their Discord ID>`
2. On your own computer: install Claude Code and run `claude setup-token`; copy the token.
3. Repo → Settings → Secrets and variables → Actions → add `CLAUDE_CODE_OAUTH_TOKEN` (the token),
   `DISCORD_TEAM_WEBHOOK` (shared channel), `DISCORD_LOG_WEBHOOK`, `DISCORD_APPROVALS_WEBHOOK`.
4. Commit the workflow on a branch, open a PR, and have it merged.

What triggers it: the reviewer's comments and reviews on your PRs (no tag needed; "thanks" and
approvals are ignored), and `@claude` from you or the reviewer in any PR comment or new issue.
Your PR opening and your approvals send the reviewer a Discord note without running Claude.

Remove it anytime: delete `.github/workflows/agent-kit-pr-feedback.yml` and the four secrets,
and revoke the token in your Claude settings.
