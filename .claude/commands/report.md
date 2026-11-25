---
description: Session report (Discord message + PDF), or the weekly rollup with "weekly"
argument-hint: "[weekly [YYYY-MM-DD]]"
---

Report: $ARGUMENTS

If the argument starts with `weekly`: run `bash <hooks>/report.sh weekly [date]` and stop. (`<hooks>` is the hooks path printed at session start.)

Otherwise, write the session report:

1. **Get the facts:** `python3 <hooks>/report.py data`. It prints times (measured, not estimated), commits, pushes, and PRs for this session. If the hooks didn't run, it says so and times are marked "not measured" — continue anyway, and list commits/PRs from `git log` and GitHub in the content. Never fill in times yourself.
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
4. If the archive step fails because agent-reports isn't reachable: attach the `skylaryoshimitsu-blip/agent-reports` repo to this session (push access), then run `bash <hooks>/report.sh archive`. Never rerun `report.sh session` — that would post the report to #reports twice. If it still fails, say so plainly; the Discord report still counts as delivered.
5. Post "Session ended" with the end time to #logs.
6. **Lessons** (Section 12). If this session produced anything worth remembering — a solved bug, a correction from Golden, a rejected plan, a failed verification — write `.agent/lessons-input.json`:
   ```json
   [{"type": "fixes", "title": "...", "symptom": "...", "cause": "...", "fix": "...", "source": "<project> /fix (date)"}]
   ```
   (`"type": "working-style"` for how Golden wants things done: symptom = when it comes up, cause = why, fix = what to do.)
   - General enough to help on any project. For client work: no client names, code, data, repos, or URLs.
   - Check `lessons.sh search` first; don't propose a duplicate of an existing lesson.
   Then run `bash <hooks>/lessons.sh propose .agent/lessons-input.json`, open a PR on `skylaryoshimitsu-blip/agent-kit` from the branch it prints into `main` (title: "Lessons: <ids>"), and run `bash <hooks>/lessons.sh announce <pr-url>`. Never merge it — Golden approves by merging, edits in the PR, or rejects by deleting entries / closing it.
   If nothing is worth a lesson, skip this step and say so.
7. In the report's "next" items, note any lesson that was applied this session (by ID).
