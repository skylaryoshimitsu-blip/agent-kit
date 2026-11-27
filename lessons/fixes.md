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

### L-005 · Magic-link sign-in fails for an invited user when sign-ups are disabled
- **Symptom:** Owner gets "Signups not allowed for this instance" (auth log error_code signup_disabled) when requesting a magic link, although the user exists. An unknown email gets "Signups not allowed for otp" (otp_disabled), which is expected.
- **Root cause:** The user was created by invite and never accepted it, so the email is unconfirmed. With sign-ups disabled, Supabase sends OTP requests for unconfirmed users down the sign-up path and blocks them.
- **Fix:** When creating the owner account during setup, confirm the email (admin API update with email_confirm: true) or create the user directly as confirmed instead of only inviting. Verification of the auth step must include one real magic-link request for the owner's email, not only test users created with email_confirm.
- **Source:** content-studio /fix (2026-11-27)

### L-006 · verify.sh flags a UUID template inside a bundled library as a placeholder
- **Symptom:** verify.sh reports "placeholder values shipped: xxxxxxxx" on a page whose own code and config have no placeholders.
- **Root cause:** The placeholder scan includes the built JS bundle, and libraries such as tus-js-client contain the UUID v4 template string 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.
- **Fix:** Check where the match is before treating it as a failure (curl the bundle and grep with context). If it is the UUID template in vendor code, record it as a false positive in the verification post. Consider narrowing the pattern so 'xxxxxxxx-xxxx-4xxx' is ignored.
- **Source:** content-studio /feature (2026-11-27)

### L-007 · Scheduling UI with a workspace time zone must show "now" in that zone
- **Symptom:** A user in one time zone (e.g. Manila) scheduling in a workspace set to another (e.g. New York) cannot drag posts to "yesterday" or enter a time, and only sees "That time is in the past".
- **Root cause:** The server correctly refuses past times, but the UI shows only workspace-zone times without the current time there, so the user cannot see that the day or hour has already passed in the workspace zone.
- **Fix:** Whenever times are shown or entered in a zone other than the viewer's: show "now" in the workspace zone and the viewer's own equivalent, grey out past slots, preview the chosen time in both zones, and refuse past times in the browser with a message naming both the chosen time and "now" in that zone.
- **Source:** content-studio /fix (2026-11-27)
