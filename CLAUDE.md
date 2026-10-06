Prefer to use AskUserQuestions when responding with questions to a user, unless
that question is the last thing in the response.  If more than 1 question,
always prefer to use AskUserQuestions tool.

# Messages

Never send Slack messages unless explicitly asked to by the user. Reading or
searching Slack is fine; posting (status updates, replies, PR links, thread
comments) requires an explicit request in the current conversation. Messages sent
through the Slack MCP integration go out as me.

# Conditional Instructions

⚠️ **ONLY apply when working directory is `/Users/benbernard` (not subdirectories)**

When working in the home directory itself, see `CLAUDE.home.md` for detailed instructions about:
- Repository structure and source control
- File search best practices (performance warnings)
- TypeScript module management
- Configuration management

**Ignore `CLAUDE.home.md` when working in `/Users/benbernard/repos/*` or any other subdirectory.**

# Job-specific Instructions

Job-specific agent instructions live outside this public repo. If
`~/site/AGENTS.md` exists, read and follow it in addition to this file.
