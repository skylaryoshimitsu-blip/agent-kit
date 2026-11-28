---
description: Draft the next 48-hour progress report in the same format as the previous one
---

Draft the next progress report. Paths are given in the task (previous report = `last.md`, output = `draft.md`).

1. **Read the previous report** in full. It defines the format: title line, number, reporting period, issue, previous-report line, status key, the numbered sections and their order, table layouts, wording style, and the closing security confirmation. Copy that structure exactly.
2. **Number and period:** the number is the previous number + 1. The period starts at the previous report's end time and ends now. Use the same time zone and date format as the previous report (e.g. "28 November 2026, 09:30, Philippine Standard Time (UTC+8)"). "Previous report" points to the previous number and the time it was posted.
3. **Gather facts for the period only,** from GitHub with `gh`. Never invent anything.
   - PRs merged, opened or updated in the period (`gh pr list --state all --search "updated:>=<start date>"`), with merge times in the report's time zone, and who merged them.
   - Review rounds and corrections addressed (PR comments and reviews).
   - Issue comments on the tracked issue(s) in the period: submissions, approvals, revision requests, acknowledgements.
   - Commits on the working branches; documentation commits and their status (accepted / pending approval / superseded / revision requested), as stated in the thread.
   - CI results for the latest merged and open PRs (`gh pr checks`), and test counts as reported in PR descriptions or CI.
   - Anything still waiting on Developer 2 or the Project Owner.
4. **Carry forward** items from the previous report that are still true (open blockers, integration requirements, pending approvals), updated with their current status. Drop items that were resolved, and say how they were resolved.
5. **Accuracy rules:**
   - Work not merged or accepted goes under "Work in Progress", never "Completed".
   - Untested work is labelled not yet tested.
   - Use exact PR numbers, commit SHAs, times and test counts. If a figure can't be confirmed, leave it out rather than estimate.
   - No hours or time tracking.
   - Keep the security confirmation section, adjusted only if something actually changed.
6. **Save** the report as Markdown to the draft path. Don't post it anywhere: Golden reviews it first. When done, post one line to #logs: `📝 Report #<n> drafted (<period>)`.
