---
description: Act on the reviewer's new comments on an issue — answer, revise documents, or start authorized work
argument-hint: "<issue number>"
---

Address the reviewer's new comment(s) on issue $ARGUMENTS.

Profile keys used: `team.reviewer_github`, `team.reviewer_discord_id`, `autofix_max_lines` (0 = no size limit).
You post on GitHub under Golden's account, as "Developer 3". Match the tone and format of the earlier Developer 3 comments on the issue.

1. **Read the issue:** `gh issue view <n> --comments`. Focus on the reviewer's comments posted after Golden's account last commented. Read the earlier thread too, for context: approach documents, revision numbers, what has been approved.
2. **Classify each new comment** and post one decision line per comment to #logs:
   `discord-post.sh logs "🔎 <reviewer> on issue #<n>: <type> → <what you'll do>"`
   - **Acknowledgment / approval with nothing to do:** no action.
   - **Question:** answer it on the issue.
   - **Revision requested** on a document, plan or approach: revise it.
   - **Authorization to start work** (e.g. "approved, proceed", "implementation authorized", "Phase A5 approved"): start building it.
   - **Other request:** do it.
3. **Answers:** reply on the issue (`gh issue comment <n>`), concise and specific.
4. **Revisions:** find the document (the docs branch and file named in the thread), make the requested changes as the next revision number, commit and push on that branch. Post a revision comment on the issue in the same format as earlier revision comments: what changed, point by point, with the commit. Then tag the reviewer in the shared channel: `discord-post.sh team --mention <reviewer_discord_id> "Issue #<n>: <doc> revision <k> posted for your review — <issue url>"`.
5. **Authorized work:**
   - Post a short acknowledgment on the issue, like earlier acknowledgments.
   - Announce to Golden: `discord-post.sh logs "🚀 Starting <phase/task> (authorized by <reviewer> on issue #<n>)"`.
   - Branch from the latest `main` using the existing naming (e.g. `dev3/<phase-name>`). Build to the approved approach document and its safeguards. Run the full test suite. Commit and push in logical steps, so progress is visible and nothing is lost if a run stops.
   - Open a PR when complete, with a description in the same style as earlier PRs (what, safeguards, tests, security confirmation). Then tag the reviewer: "PR #<n> ready for your review".
   - There is no size limit. If the work spans several runs, leave a short progress comment on the PR or issue so the next run can continue.
6. **Respect the repo's constraints** stated in the thread and reports: test mode only, synthetic data only, no live keys, no credentials in code or comments.
7. **Blocked** on something only Golden or the Project Owner can provide: ask the reviewer/owner on the issue, or post to #approvals for Golden. Then stop.
8. Never approve or merge pull requests. No attribution footers.
