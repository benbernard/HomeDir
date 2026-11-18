Prefer to use AskUserQuestions when responding with questions to a user, unless
that question is the last thing in the response.  If more than 1 question,
always prefer to use AskUserQuestions tool.

# Screenshots

Screenshots provided by the user (Xnapper) can be found at
`~/Library/Application Support/Xnapper/Archives/` — `Output/` is the edited
version, `Raw/` the original.

# Messages

Never send Slack messages unless explicitly asked to by the user. Reading or
searching Slack is fine; posting (status updates, replies, PR links, thread
comments) requires an explicit request in the current conversation. Messages sent
through the Slack MCP integration go out as me.

# Conditional Instructions

⚠️ **ONLY apply when working directory is `/Users/benbernard` (not subdirectories)**

When working in the home directory itself, see `AGENTS.home.md` for detailed instructions about:
- Repository structure and source control
- File search best practices (performance warnings)
- TypeScript module management
- Configuration management

**Ignore `AGENTS.home.md` when working in `/Users/benbernard/repos/*` or any other subdirectory.**

# Job-specific Instructions

Job-specific agent instructions live outside this public repo. If
`~/site/AGENTS.md` exists, read and follow it in addition to this file.
Never commit employer names, internal tools, project names, links, or other
work-specific details here, including in examples and commit messages. Follow
`docs/leak-protection.md` before committing; leave managed shell changes local.

# Worktrees

Worktrees live under `~/repos/worktrees/<repo>/<name>`. Branch names containing
slashes can produce nested directories. Paths in the old `~/repos/<repo>-<name>`
layout are stale. Use `git -C ~/repos/<repo> worktree list` to find the current
path before opening a worktree from an old plan, shell variable, or editor tab.

# Testing

- Prefer end-to-end tests where possible.
- Do not test documentation.
- Do not write tests that merely assert what was written verbatim; tests should validate behavior.
- Avoid overly obvious tests and tests that only exercise libraries.
