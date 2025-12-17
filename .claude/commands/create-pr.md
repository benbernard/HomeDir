---
description: Create pull requests with concise descriptions
---

# Create Pull Request

Create a pull request with a concise, well-formatted description.

## Workflow

1. **Verify branch**: If on master, automatically create a feature branch
2. **Push to origin**: Always push to `origin` from the current branch
3. **Create PR**: Use `gh pr create` with concise description
4. **Format description**: Small bullet points, derived from conversation and commits

## PR Description Format

Keep it **very concise**. Use this structure:

```
## Summary
<1-3 bullet points of what changed>

## Test plan
[Optional: Only if testing steps are needed]
```

### Good examples

```
## Summary
- Fix deduplication in welcome message
- Add sorting to package list
- Improve logging on package updates
```

```
## Summary
- Add cache timestamp on initial install
- Prevent stale cache issues
```

### Bad examples (too verbose)

```
## Summary
- This PR implements a comprehensive solution to fix the deduplication
  logic in the welcome message handler by refactoring the underlying
  data structure and adding a new sorting algorithm...
```

## Instructions

1. Check current branch: `git branch --show-current`
   - If on master, automatically create a feature branch:
     ```bash
     git checkout -b feature/<descriptive-name>
     ```
     Use a short descriptive name based on the changes (e.g., `feature/fix-cache`, `feature/add-logging`)

2. Review changes:
   - Run `git status` to see what's committed
   - Run `git log master..HEAD --oneline` to see commits
   - Review recent conversation for context

3. Push changes:
   ```bash
   git push -u origin <current-branch>
   ```

4. Create PR with concise description:
   ```bash
   gh pr create --title "Brief title" --body "$(cat <<'EOF'
   ## Summary
   - First change
   - Second change
   - Third change
   EOF
   )"
   ```

5. Return the PR URL to the user

6. Open the PR in the browser:
   ```bash
   open <PR_URL>
   ```
   Replace `<PR_URL>` with the actual PR URL returned from `gh pr create`

## Key principles

- **Be concise**: Each bullet should be one line
- **Focus on what**: Describe the change, not implementation details
- **Derive from context**: Use commit messages and conversation
- **No fluff**: Avoid phrases like "This PR implements" or "In this change"
- **Action-oriented**: Start bullets with verbs (Add, Fix, Update, Remove)
