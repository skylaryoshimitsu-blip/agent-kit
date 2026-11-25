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
- **Fix:** Attach `agent-reports` (push access), then run `report.sh archive`. Never rerun `report.sh session` — it would post the report to #reports twice.
- **Source:** agent-kit /report (2026-11-25)
