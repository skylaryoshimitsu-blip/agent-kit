---
description: Add one scoped feature to an existing project
argument-hint: <feature description>
---

Feature: $ARGUMENTS

Follow the agent-kit rules. Steps:

1. **Load context.** Read `agent-profile.yaml` (ask if missing), the repo's own CLAUDE.md/README/conventions, and the files this feature touches. Inspect the real database schema before assuming any table or column.
2. **Plan.** Post a plan to #logs and #approvals (`discord-post.sh`): what changes, which files, schema/env var changes, how it will be verified live. Surgical edits only.
3. **Wait for approval** in this session. Silence is not approval.
4. **Build** on a feature branch. Commit and push in small steps. If the work drifts from the plan, stop and re-post the changed part.
5. **Verify** on the preview deploy (`verify.sh` + read-only SQL + env var names present). Post proof.
6. **Gate — merge to production.** Post the PR link and proof to #approvals; wait.
7. After merge, verify on production. Then `/report`.
