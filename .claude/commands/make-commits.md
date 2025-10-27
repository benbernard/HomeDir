# Make Commits

Analyze the current working tree and create logical commits from the staged and unstaged changes.

## Guidelines

1. **Logical Grouping**: Break apart changes that aren't logically connected. Look for:
   - Different features or bug fixes
   - Different components or modules being modified
   - Infrastructure vs application code changes
   - However, prefer fewer commits over excessive granularity

2. **Tests with Changes**: Always commit tests alongside their corresponding code changes in the same commit. Tests and implementation are a logical unit.

3. **No Rewrites**: NEVER rewrite, refactor, or modify existing changes during this process. Only organize what's already there. If the choice is between:
   - Making additional commits with extra/imperfect code
   - Rewriting code to make it "cleaner"

   Always choose to keep the code as-is. When in doubt, prefer one larger commit over rewriting working code.

4. **Commit Message Quality**: Each commit message should:
   - Clearly describe what changed and why
   - Follow the repository's existing commit message style (check git log)
   - Be concise but informative

## Process

1. First, check the current state:
   - Run `git status` to see all changes
   - Check the current branch - NEVER commit directly to master
   - If on master, ask the user what branch to use (you can suggest a descriptive branch name)
   - Run `git diff` for unstaged changes
   - Run `git diff --staged` for staged changes
   - Review recent commits to understand the style

2. Run lints and type-checks to ensure everything is clean before proceeding
   - Check for common commands like `npm run lint`, `npm run type-check`, `tsc`, etc.
   - If lints or type-checks fail, stop and inform the user

3. Analyze the changes and identify logical groups
   - Watch for debugging code, console.logs, commented code, or other code that shouldn't be committed
   - DO NOT remove such code yourself - ask the user if it should be removed first

4. Create a checklist using TodoWrite with one todo item for each commit you plan to make

5. Create each commit by:
   - Marking the corresponding todo as in_progress
   - Staging the appropriate files/hunks using `git add`
   - Creating the commit with a descriptive message
   - Including the standard footer with Claude attribution
   - Showing the result with `git status` after the commit
   - Marking the todo as completed

## Done Criteria

You are done when `git status` shows a clean working tree with no staged or unstaged changes remaining.

## Important Notes

- If you're uncertain about how to group changes, ask the user
- Prefer keeping changes together when there's doubt about separation
- It's acceptable to have just one commit for everything if changes are tightly coupled
- Never use `git commit --amend` or any rewriting operations
