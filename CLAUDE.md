# Agent Kit — Working Rules

These rules apply to every project, Zenyra or client. Project-specific settings live in
`profiles/<project>.yaml`. If a profile conflicts with this file, the stricter rule wins.

---

## 1. Session start

1. Identify the project and load its profile (`agent-profile.yaml` in the repo root,
   or `profiles/<project>.yaml` in the kit). If no profile exists, stop and ask.
2. Identify the mode: `/new`, `/feature`, `/fix`, `/pair`, `/handoff`, `/report`.
   If unclear, ask in one line.
3. Read the repo's own CLAUDE.md, README, and lint/format config if present.
   In client repos, their conventions override the defaults in this file.
4. Post a "session started" line to the project's Discord log channel.

## 2. Plan before code (always)

- Before writing any code, post a plan to Discord: what will change, which files,
  any schema or env var changes, and how it will be verified live.
- Wait for approval. "Approved", "go", or a thumbs-up counts. Silence does not.
- If the work turns out to differ from the approved plan, stop and re-post the
  changed part of the plan before continuing.

## 3. Edit style

- Default: surgical, targeted edits. Change only what the task requires.
  No unrelated refactors, renames, or formatting sweeps.
- Full file rewrite only when:
  (a) the task or profile explicitly asks for it, or
  (b) the file is too broken to patch safely — in that case, say why and ask first.
- One task at a time. When given a numbered list, work it in order and confirm
  each item is verified before starting the next.

## 4. Approval gates (stop and wait for Golden)

1. Spec / plan approval
2. Merge to the production branch
3. Any SQL against a production database
4. Any change to production environment variables

Everything else (branches, commits to feature branches, preview deploys, Supabase
preview-branch migrations, preview env vars) proceeds without asking, but is logged.

## 5. Build and deploy flow

1. Create a feature branch. Never commit directly to the production branch.
   In cloud sessions, use the branch the session was assigned (e.g. `claude/...`)
   instead of naming your own — don't ask which branch to use.
2. Schema changes go in migration files, applied to a Supabase preview branch first.
   No ad-hoc SQL against production.
3. Open a PR. Post the diff summary to Discord.
4. After every commit: post "pushed <short sha> to <branch>" to Discord.
5. Vercel preview deploy → run the verification protocol (section 6) on the preview.
6. Request the merge gate. After merge, run verification again on production.
7. Don't offer to watch a PR for comments or CI unless the repo actually has CI checks.
8. You never merge to the production branch yourself. When you see a PR was merged,
   report it as "PR #X merged by Golden", then run post-merge verification.

## 6. Verification protocol — "done" means proven live

A task is not done until all applicable checks pass and the proof is posted:

- **Live page:** load the deployed URL and confirm the change is visible and works.
- **Network:** check the actual API/function response body, not just the status code
  and not just what is in the repo.
- **Data:** run a read-only SQL query confirming the expected rows/columns changed.
- **Config:** confirm required env vars exist in the target environment (names only).
- **Scheduled jobs/crons:** confirm the job is registered and, where possible, trigger
  a test run and show its output.

If any check cannot be completed, the task stays open and the report says so.
Never report a feature as done based on the code alone.

## 7. Known failure patterns — check these every time

- Placeholder values (e.g. `YOUR_SUPABASE_URL`, `xxx`, `TODO`) shipped in code or config.
- Env vars set in code but missing in Vercel (or set only in Preview, not Production).
- Features that "succeed" silently but change nothing (verify with SQL, section 6).
- Single-file HTML: closing tags like `</script>`, `</style>`, `</head>` inside JS
  template literals break the page. Avoid; validate extracted JS with `node --check`.
- Vercel request body limit (~4.5 MB): large uploads go browser → Supabase Storage directly.
- Vercel function timeouts: long jobs go to Inngest (or equivalent), with each step
  writing results to the database and returning only small values.
- Inngest: import the shared client from one module; don't create new instances.
- Dates/weeks: compute in the business's time zone (usually ET), Monday week start,
  regardless of server or browser time zone.
- Schema assumptions: inspect the real tables (`list_tables` / information_schema)
  before writing queries. Don't guess column or table names.

## 8. Client work

- Use only the credentials named in the client's profile. Never use Zenyra or other
  clients' tokens, and never reference other clients' code or data.
- Open PRs for the client's team; never push to their protected branches.
- `/pair` mode: stay inside the assigned scope, keep PRs small, no surprise refactors,
  and leave review comments rather than rewriting a teammate's code.

## 9. Secrets

- Never post secret values to Discord, PRs, commits, reports, or logs. Names only.
- Never commit `.env` files or keys. Check the diff for secrets before every commit.
- If a needed secret is missing, ask for it to be set in Vercel/Supabase directly.

## 10. Communication (Discord)

- **Log channel:** session start/end, plans, commits, deploys, verification proof, errors.
- **Approval channel:** gate requests only, each with a one-line summary and link.
- Errors: post the raw error output, what was tried, and the next step.
  Don't paraphrase errors.

## 11. Reports

At session end, produce a session report (see `/report`):

- Written for a non-technical reader, in the client's time zone from the profile.
- Order: tasks completed (verified) → in progress → blocked/needs input → proof links
  → time → next session.
- Time is reported in two separate lines: Golden's hands-on time (planning, reviews,
  approvals, pairing) and agent run time. Never combine them.
- Only list work that actually happened in the session, backed by commits, PRs,
  deploys, or verification output. No estimates presented as facts.
- Strip secrets, internal notes, file paths (unless the profile says the reader is
  technical), and anything from other projects.
- Deliver as a Discord message plus an attached PDF, using `/report` (it measures the
  time and builds the PDF — never write times yourself). Weekly rollup: `/report weekly`.

## 12. Learning and self-improvement

- Lessons live in `lessons/` in the kit repo: `fixes.md` (symptom → root cause → fix),
  `working-style.md` (how Golden works, from his corrections), `playbooks/` (repeatable procedures).
  Lesson titles are listed at session start.
- When an error occurs, run `lessons.sh search "<error>"` before debugging from scratch.
  State which lesson was applied (by ID).
- At session end, `/report` proposes new lessons as a PR on agent-kit (`lessons.sh propose`)
  and posts each one to #lessons with the PR link (`lessons.sh announce`).
- Golden approves by merging the PR, edits inside the PR, or rejects by deleting entries or
  closing it. Never merge it yourself. Never edit kit files (rules, lessons, modes, hooks,
  profiles) any other way.
- Lessons from client work must be generalized: no client code, data, names, repos, or URLs
  (`lessons.sh propose` blocks them). Client-specific knowledge goes in that client's profile only.
- Monthly: `/lessons-review` proposes consolidating duplicates and retiring outdated ones (as a PR).
- Sessions in other project repos need `agent-kit` attached to propose lessons.

## 13. Tools

- **You can post to Discord.** Use `hooks/discord-post.sh <logs|approvals|reports|lessons> "message"`
  (the exact path is printed at session start). Never say you have no way to post to Discord.
- Automatic (hooks): session start/end, commits, pushes, PRs → #logs.
- You post yourself: plans, gate requests (#approvals), verification proof, raw errors (#logs),
  reports (#reports), lesson proposals (#lessons).
- **Verify deployed pages** with `hooks/verify.sh <url> [expected text]`. It checks status,
  expected text, and placeholder values, and posts the result to #logs.
- **Modes:** `/new`, `/feature`, `/fix`, `/pair`, `/report`, `/handoff`
  (long form `/agent-kit:<mode>` when the kit is used as a desktop plugin).
- **Installing the kit in a project:** `bash install.sh <project path>` from an agent-kit clone
  (see `docs/INSTALL.md`). In installed projects the kit lives in `.agent-kit/`.
