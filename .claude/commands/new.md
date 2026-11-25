---
description: Start a new project from an idea — spec first, then scaffold and build
argument-hint: <idea or project name>
---

New project: $ARGUMENTS

Follow the agent-kit rules. Steps:

0. **Kit.** If the repo has no `.agent-kit/` folder, install it first: clone agent-kit next to the project and run `bash install.sh <project path>`. Commit that on its own branch.
1. **Profile.** Look for `agent-profile.yaml` in the repo root. If missing, draft one from the kit's `profiles/_template.yaml`, show it, and ask Golden to confirm owner (Zenyra / client / personal), time zone, and accounts.
2. **Spec.** Write a short spec: goal, users, features for v1 (and what's deferred), data model (tables and key columns), pages, background jobs, env var NAMES needed, and how each feature will be verified live.
3. **Gate 1 — spec approval.** Post the spec summary to #approvals with `discord-post.sh approvals`, then stop and wait for Golden's approval in this session.
4. **Build in order**, one feature at a time, on a feature branch: scaffold → schema migrations (staging/preview database first) → each feature → commit and push after each.
5. **Verify each feature** per Section 6 (`verify.sh` on the preview URL, read-only SQL for data). Post proof to #logs. A feature without proof is not done.
6. **Gate 2 — merge to production.** Post to #approvals with the PR link and verification proof; wait.
7. After merge, verify again on production, then run `/report`.
