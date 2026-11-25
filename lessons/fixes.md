# Fixes

Symptom → root cause → fix. Search with `lessons.sh search "<error text>"`.
New entries arrive only through a PR that Golden merges.

### L-001 · Setup docs not updated with the code that needs them
- **Symptom:** A feature adds a new env var, required repo, or external dependency, but `docs/INSTALL.md` doesn't mention it, so new installs miss a setup step.
- **Root cause:** Setup docs weren't updated in the same PR as the code that needs them.
- **Fix:** Any PR that adds an env var, required repo, or external dependency must update `docs/INSTALL.md` in the same PR.
- **Source:** agent-kit /fix, PR #11 (2026-11-25)

### L-002 · Report archive fails: agent-reports not reachable
- **Symptom:** `/report` prints `ARCHIVE FAILED: could not clone agent-reports` in a cloud session.
- **Root cause:** Cloud sessions only reach repos attached to them; agent-reports wasn't attached.
- **Fix:** Attach `agent-reports` (push access) mid-session, then run `report.sh archive`. Never rerun `report.sh session` — it would post the report to #reports twice. Don't start sessions with extra repos attached (see L-003).
- **Source:** agent-kit /report (2026-11-25)

### L-003 · Hooks didn't run: session started with several repos attached
- **Symptom:** No automatic "Session started" in #logs, `.agent/` is empty, and `/report` says "No session start in .agent/session-log.jsonl".
- **Root cause:** A cloud session with two or more repos attached starts in a parent folder, so the project's `.claude/settings.json` hooks never load.
- **Fix:** Start sessions with only the project repo attached; attach `agent-reports` / `agent-kit` mid-session when needed. If it already happened, tell Golden at once; `/report` still works but shows time as not measured.
- **Source:** agent-kit /report (2026-11-25)
