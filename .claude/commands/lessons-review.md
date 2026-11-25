---
description: Monthly lessons cleanup — propose merging duplicates and retiring stale lessons (as a PR)
---

Monthly lessons review for agent-kit. Run in a session on the agent-kit repo.

1. Read every file in `lessons/`.
2. Find: duplicates or near-duplicates (propose one merged entry, keeping the lowest ID), lessons that are outdated because the kit or rules changed (propose retiring them), and fixes that have come up often enough to become a playbook in `lessons/playbooks/`.
3. Make those edits on the session branch. Keep IDs stable: a merged lesson keeps one ID and notes "(merged L-00X)"; a retired lesson is removed and listed in the PR description with the reason.
4. Open a PR into `main` titled "Lessons review: <month year>", with one line per change and the reason. Never merge it.
5. Post a one-line summary with the PR link to #lessons. If nothing needs changing, post that instead and open no PR.
