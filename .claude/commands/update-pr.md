---
description: Update existing pull request with new commits
---

# Update Pull Request

Push new commits to an existing pull request and optionally update its description.

## Workflow

1. **Verify branch and PR**: Ensure you're on a branch with an existing PR
2. **Review all commits**: Show all commits that will be in the PR
3. **Push any unpushed changes**: Push any new commits to origin if needed
4. **Recompute PR description**: Generate a fresh PR description based on all commits, using the previous description as a guide
5. **Update PR**: Update both title (if needed) and description
6. **Return PR URL**: Show the updated PR URL

## Instructions

1. Check current branch and PR status:
   ```bash
   git branch --show-current
   gh pr view --json number,title,url,baseRefName,body
   ```
   - If no PR exists, inform user and suggest using `/create-pr` instead
   - If on master, stop and ask user to switch branches
   - Store the current title and body for reference

2. Review ALL commits in the branch (not just unpushed ones):
   ```bash
   # Get all commits in this branch compared to the base branch
   git log <base-branch>..HEAD --oneline

   # Also check if there are unpushed commits
   git log origin/<current-branch>..HEAD --oneline
   ```
   - Show all the commits that are part of this PR
   - Note if there are unpushed commits that need to be pushed

3. Push any unpushed commits:
   ```bash
   git push
   ```
   - Only run this if there were unpushed commits
   - If already up to date, skip this step

4. Analyze all changes and recompute PR description:
   - Review ALL commits in the branch (from step 2)
   - Look at the previous PR description and title as a guide
   - Generate a fresh, comprehensive PR description that:
     - Accurately reflects ALL changes in the branch
     - Follows the same format/style as the previous description
     - Uses concise bullet points
     - Groups related changes together
     - Is complete but not verbose
   - Consider if the title needs updating to better reflect the scope

5. Update the PR:
   ```bash
   # Update title if needed
   gh pr edit <pr-number> --title "New Title"

   # Update description
   gh pr edit <pr-number> --body "$(cat <<'EOF'
   ## Summary
   - First main change
   - Second main change
   - Additional improvements
   EOF
   )"
   ```
   - Always update the description
   - Only update the title if the current one doesn't accurately reflect the changes

6. Return the PR URL and summary of what was done

## Key Principles

- **Complete recomputation**: Generate the description from scratch based on ALL commits
- **Use previous as guide**: Keep similar format and style from the previous description
- **Smart title updates**: Only change title if it's no longer accurate
- **Account for pushed commits**: Handle cases where commits were already pushed
- **Clear and comprehensive**: Description should cover everything in the branch
- **Concise format**: Keep it readable with bullet points, no unnecessary detail

## Example Output

```
✅ Found PR #123: "Add user authentication"

📝 All commits in this branch:
   - abc1234 Initial authentication setup
   - def5678 Add JWT token support
   - 789abcd Fix login validation
   - 012cdef Add password reset

📤 Unpushed commits: 2
   - 789abcd Fix login validation
   - 012cdef Add password reset

🚀 Pushing commits...
✅ Pushed to origin

🔄 Recomputing PR description based on all commits...
✅ Updated PR #123:
   - Title: "Add user authentication" (unchanged)
   - Description: Updated to reflect all changes

PR URL: https://github.com/org/repo/pull/123
```
