---
description: Session report (Discord message + PDF), or the weekly rollup with "weekly"
argument-hint: "[weekly [YYYY-MM-DD]]"
---

Report: $ARGUMENTS

If the argument starts with `weekly`: run `bash <hooks>/report.sh weekly [date]` and stop. (`<hooks>` is the hooks path printed at session start.)

Otherwise, write the session report:

1. **Get the facts:** `python3 <hooks>/report.py data`. It prints times (measured, not estimated), commits, pushes, and PRs for this session.
2. **Write the content** to `.agent/report-input.json`, following Section 11 of the rules:
   ```json
   {
     "completed":   [{"task": "plain-language result", "proof": "how it was verified"}],
     "in_progress": ["..."],
     "blocked":     ["what is needed and from whom"],
     "links":       [{"label": "PR #9", "url": "https://..."}],
     "next":        ["..."]
   }
   ```
   - Only work that actually happened this session and is backed by a commit, PR, deploy, or verification. Unverified work goes under in_progress, never completed.
   - Plain language for the profile's audience. No secrets, no internal notes, nothing from other projects; no file paths unless the audience is technical.
   - Do not write any times — the script measures them.
3. **Build, post, archive:** `bash <hooks>/report.sh session .agent/report-input.json`. This posts the message and PDF to #reports and saves both to the agent-reports repo.
4. If the archive step reports a failure, say so plainly; the Discord report still counts as delivered.
5. Post "Session ended" with the end time to #logs.
6. Then propose lessons (Section 12), one message each to #lessons.
