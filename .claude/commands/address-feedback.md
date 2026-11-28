---
description: Act on the reviewer's latest PR comments — fix, push, reply, and notify them
argument-hint: "[PR number]"
---

Address reviewer feedback on PR $ARGUMENTS (if no number is given, use the PR from the triggering event).

Profile keys used: `team.reviewer_github`, `team.reviewer_discord_id`, `feedback_autofix`, `autofix_max_lines`.

1. **Read the feedback.** Fetch the PR's review comments, reviews, and conversation comments from the reviewer (`gh pr view <n> --comments`, `gh api repos/{owner}/{repo}/pulls/<n>/comments`). Only consider comments newer than your last reply on this PR.
2. **Classify each comment:** actionable (a change is requested), question (needs an answer), or no action ("thanks", "looks good", an approval). Post one decision line per comment to #logs: `discord-post.sh logs "🔎 <reviewer> on PR #<n>: <type> → <what you'll do>"`. If nothing is actionable or a question, stop after the decision lines.
3. **Check lessons** (`lessons.sh search`) for anything matching the requested change.
4. **Size check.** `autofix_max_lines: 0` means no limit: always go ahead, whatever the size (push in steps so progress is visible). Otherwise, if `feedback_autofix: true` and the total fix is within `autofix_max_lines` changed lines with no schema or env var changes, go ahead. Otherwise:
   - Post the plan **as a comment on the PR** (`gh pr comment <n> --body ...`), starting with "**Plan (waiting for Golden's approval):**" and ending with "Reply `@claude approved` to go ahead, or `@claude` with changes."
   - Post one line to #approvals with the link to that PR comment, then stop.
   - When Golden later comments `@claude approved` (or approves with changes) on the PR, the plan to implement is your most recent "Plan (waiting for Golden's approval)" comment on that PR, adjusted by what he said.
5. **Fix** on the PR's own branch. Surgical edits only. Run the project's tests/build if they exist. Commit and push.
6. **Reply on each comment** you handled: what changed and the commit (e.g. "Done in abc1234: moved the check into the handler."). Answer questions directly. If you disagree with a request, say so politely with the reason instead of changing the code.
7. **Notify the reviewer** in the shared channel, one short line:
   `bash <hooks>/discord-post.sh team --mention <reviewer_discord_id> "PR #<n>: feedback addressed (<k> changes), please re-check — <PR url>"`
8. Post one line to #logs. Never approve or merge a PR.
