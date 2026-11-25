---
description: Fix a bug, or work a numbered bug list in order
argument-hint: <bug description or numbered list>
---

Fix: $ARGUMENTS

Follow the agent-kit rules. Steps:

1. **Check lessons first.** Search the kit's `lessons/` folder (and Section 7 of the rules) for a matching symptom. Say which lesson applies, if any.
2. **Reproduce.** Confirm the bug exists (live page, logs, SQL, or failing command). Post the raw error to #logs — don't paraphrase it.
3. **Plan.** Post root cause + the smallest fix + how it will be verified to #logs and #approvals. Wait for approval in this session.
4. **Fix** on a branch named `fix/<short-name>`. Surgical change only. Commit and push.
5. **Verify** the fix (rerun the reproduction; `verify.sh` for deployed pages). Post proof.
6. **Gate — merge.** Post the PR link and proof to #approvals; wait.
7. For a numbered list: finish and verify each item before starting the next.
8. Note anything worth a lesson for `/report`.
