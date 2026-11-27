---
description: Review a PR and post a short verdict for Golden
argument-hint: "<PR number>"
---

Review PR $ARGUMENTS.

1. Read the description, the full diff, and the linked issue or comments. Check the code against the repo's conventions, Section 7 (known failure patterns), and `lessons.sh search` for anything relevant.
2. Run the tests/build if the repo has them.
3. Post to #approvals, five lines at most:
   - What it changes (one sentence)
   - Risks or problems found (or "none found")
   - Tests: passed / failed / none
   - Verdict: approve / changes needed
   - The PR link
4. If changes are needed and the PR is yours (the agent's), fix them yourself. If it's someone else's, leave review comments on the PR instead of rewriting their code.
5. Never approve or merge on GitHub — Golden approves, the client's developer merges.
