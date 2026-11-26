---
description: Start a new project from an idea — spec first, then scaffold and build
argument-hint: <idea or project name>
---

New project: $ARGUMENTS

Follow the agent-kit rules. Steps:

0. **Kit.** The kit is installed before this command can run (see `docs/INSTALL.md`, "Brand-new repo"). If `.agent-kit/` is missing, stop and say so.
1. **Profile.** Fill `agent-profile.yaml` from the template: owner type, time zone, `owner_email`, `prelaunch: true`, Supabase region, `branching` (false on the free plan). Confirm only what you can't infer.
2. **Spec.** Write `docs/SPEC.md`: goal, users, v1 features (and what's deferred), data model (tables and key columns), pages, background jobs, env var NAMES, build order, and how each feature will be verified live.
3. **Gate 1 — spec approval.** Post the spec summary to #approvals with `discord-post.sh approvals`, then stop and wait for Golden's approval in this session. Ask any open questions in the same message — all at once, not one per turn.
3a. **Provision everything yourself** after approval (Section 9 — never print secret values, never ask Golden to copy keys):
   - Supabase: create the project (Supabase MCP or Management API with `SUPABASE_ACCESS_TOKEN`) in the profile's region.
   - Vercel: create or reuse the project for this repo via the API with `VERCEL_TOKEN` (framework preset, GitHub link), and create the Protection Bypass for Automation so `verify.sh` can check protected previews. Each session, read it back from the Vercel API into `VERCEL_AUTOMATION_BYPASS_SECRET` for the verify command only — never print it.
   - Env vars in Vercel (Preview and Production): Supabase URL, publishable key, service role key (piped from the Supabase API), `APP_URL`, and service keys from the Claude environment when the feature needing them is built (`CAPTIONS_ANTHROPIC_API_KEY` → `ANTHROPIC_API_KEY`). While `prelaunch: true`, production env vars need no approval — log names only.
   - Supabase auth: sign-ups off, invite `owner_email`, allow redirects for production and the preview URL pattern.
   - Only stop to ask if a required key name is missing from the environment.
4. **Build in order**, one feature at a time, on a feature branch: scaffold → schema migrations (per Section 5.2) → each feature → commit and push after each.
5. **Verify each feature** per Section 6 (`verify.sh` on the preview URL, read-only SQL for data). Post proof to #logs. A feature without proof is not done.
6. **Gate 2 — merge to production.** Post to #approvals with the PR link and verification proof; wait.
7. After merge, verify again on production, then run `/report`.
