# Working style

How Golden works, learned from his corrections. Same format as fixes:
when this comes up → why it matters → what to do.
New entries arrive only through a PR that Golden merges.

### L-004 · Approvals given in Discord never reach the agent
- **When:** Golden replies "go" or "approved" in a Discord channel and nothing happens; the agent keeps waiting.
- **Why:** discord-post.sh only sends messages through webhooks. The agent cannot read Discord, so replies there are invisible to it.
- **Do:** Every gate request (plan, merge, anything else) must say in Discord and in the session chat: "Approve in the Claude session". Treat a chat reply as the approval and log it to #logs as approved via session chat.
- **Source:** content-studio /feature (2026-11-27)
