---
name: resolve-conflicts
description: Resolve git merge/rebase conflicts
---

# Resolve Git Conflicts

Carefully resolve git conflicts by thoroughly researching and understanding both sides of the changes.

## CRITICAL: This is Complex Work

**Take your time. Think carefully. Research thoroughly.**

Resolving conflicts requires deep understanding of:
- What operation caused the conflict (merge/rebase/cherry-pick)
- What each side represents (this is NOT always obvious)
- WHY each side made their changes
- How to properly combine or choose between them

**When in doubt, ASK THE USER.** It's better to ask questions than to make wrong assumptions.

## Step 0: Check for Active Conflicts (or Start Operation)

First, check if there are active conflicts:

```bash
git status
```

### If NO conflicts exist:

If there are no active conflicts, check if arguments were provided to start an operation:

**Usage patterns:**
- `/resolve-conflicts merge <branch>` - Start merging `<branch>` into current branch
- `/resolve-conflicts rebase <branch>` - Start rebasing current branch onto `<branch>`
- `/resolve-conflicts cherry-pick <commit>` - Start cherry-picking `<commit>`

**Examples:**
```bash
# Start merging master into current branch
git merge master

# Start rebasing current branch onto master
git rebase master

# Start cherry-picking a specific commit
git cherry-pick abc123
```

If the operation starts successfully:
- Proceed to Step 1 if conflicts appear
- If no conflicts, inform user the operation completed successfully

If no arguments provided and no conflicts:
- Inform user there are no active conflicts
- Show usage examples above

### If conflicts exist:

Proceed to Step 1 below.

## Step 1: Identify the Operation Type

**This is the FIRST and most important step.** Before looking at any conflicts, determine what operation is in progress:

```bash
# Check for rebase
git status | grep -i rebase

# Check for merge
git status | grep -i merge

# Check for cherry-pick
git status | grep -i cherry
```

### Understanding "Ours" vs "Theirs" (THEY ARE REVERSED!)

The meaning of "ours" and "theirs" **changes based on the operation**:

#### During a REBASE:
- **"Ours" (<<<<<<< HEAD)**: The branch you're rebasing ONTO (e.g., master)
- **"Theirs" (>>>>>>> your-branch)**: YOUR original changes that are being replayed
- This feels backwards! When rebasing, you're temporarily "standing" on the target branch

#### During a MERGE:
- **"Ours" (<<<<<<< HEAD)**: Your current branch
- **"Theirs" (>>>>>>> other-branch)**: The branch being merged in (often master)

#### During a CHERRY-PICK:
- **"Ours" (<<<<<<< HEAD)**: Your current branch
- **"Theirs" (>>>>>>> commit-hash)**: The commit being cherry-picked

**ALWAYS verify which is which** by looking at the branch names in the conflict markers and the git status output.

## Step 2: Research Both Sides

**DO NOT just look at the conflict markers.** You must understand the CONTEXT and INTENT of each change.

### Understanding Diff3 Format

This repository uses `diff3` conflict style, which shows **THREE sections** instead of two:

```
<<<<<<< HEAD (or branch name)
local changes ("ours")
||||||| merged common ancestors
original code (base/ancestor)
=======
remote changes ("theirs")
>>>>>>> branch-name or commit
```

**This is extremely helpful!** The middle section (between `|||||||` and `=======`) shows the **original code before both changes**. Use this to understand:
- What the code looked like originally
- How "ours" changed it
- How "theirs" changed it
- Whether both sides changed the same thing or different things

For each conflicting file:

1. **Understand what the conflict shows:**
   ```bash
   # Read the entire conflicted file
   cat path/to/file
   ```
   - Look for all three sections in each conflict
   - The base section shows what both sides started with

2. **Research the "ours" side:**
   ```bash
   # For rebase: Look at the target branch history
   git log origin/master --oneline -- path/to/file | head -20

   # Show what changed on this side
   git show HEAD:path/to/file  # or use git log -p
   ```
   - What commits changed this code?
   - Why were those changes made?
   - What was the intent/purpose?

3. **Research the "theirs" side:**
   ```bash
   # For rebase: Look at your branch's changes
   git log REBASE_HEAD --oneline -- path/to/file | head -20

   # For merge: Look at the incoming branch
   git log MERGE_HEAD --oneline -- path/to/file | head -20

   # Show the actual changes
   git show MERGE_HEAD:path/to/file  # or REBASE_HEAD for rebase
   ```
   - What commits changed this code?
   - Why were those changes made?
   - What was the intent/purpose?

4. **Use the base section from diff3:**
   - The middle section (between `|||||||` and `=======`) IS the merge base
   - This shows the original code before both sides made changes
   - Compare each side against the base to see what changed:
     - Did "ours" add/remove/modify relative to base?
     - Did "theirs" add/remove/modify relative to base?
     - Did they change the same lines or different lines?

   **Optional: View full base version:**
   ```bash
   # If you need to see more context from the base
   git show $(git merge-base HEAD MERGE_HEAD):path/to/file
   ```

### Special Case: Merges from Master

When merging master into your branch, there may be **many changes** coming in from master. This is particularly complex:
- Master may have significant refactoring
- Multiple commits may have touched the same code
- Your changes may be based on old assumptions

**Take extra time** to understand the master changes. Don't assume your branch's code is correct just because it's "yours."

## Step 3: Analyze Each Conflict

For each conflict marker in the file:

1. **Read the full context** (not just the conflicted lines)

2. **Use the diff3 base section to understand changes:**
   - Compare "ours" vs base: What did we change and why?
   - Compare "theirs" vs base: What did they change and why?
   - This makes it clear if both sides:
     - Made the same change (easy: use either one)
     - Made different but compatible changes (easy: keep both)
     - Made conflicting changes to same code (hard: need to reconcile)
     - Changed completely different things that happen to overlap (medium: need to combine thoughtfully)

3. **Determine if the changes are:**
   - **Compatible**: Can both be kept (e.g., one side added line A, other added line B)
   - **Incompatible**: Only one can be kept (e.g., different implementations of same logic)
   - **Complementary**: Both needed but need manual merging (e.g., both refactored same function differently)

## Step 4: Ask Questions When Unclear

**ASK THE USER if:**
- The intent of either side is unclear
- Both sides seem equally valid but incompatible
- The conflict involves business logic you don't understand
- The conflict involves API or interface changes
- You're merging large changes and unsure of the impact
- The changes involve configuration or settings with non-obvious implications
- You feel uncertain about any aspect of the resolution
- The conflict is in critical code (authentication, security, data integrity)

**Examples of good questions:**
- "This conflict shows different error handling approaches. Which pattern should we use?"
- "Master refactored this function while your branch added a new parameter. Should we apply your parameter to the new structure?"
- "Both sides changed the API endpoint path. Which one is correct?"

## Step 5: Resolve Carefully

Only after understanding both sides:

1. **Edit the file** to resolve the conflict:
   - Remove `<<<<<<<`, `=======`, and `>>>>>>>` markers
   - Keep, combine, or choose between the changes based on your research
   - Ensure code quality: proper formatting, syntax, logic

2. **Stage the resolved file:**
   ```bash
   git add path/to/file
   ```

3. **Verify the resolution:**
   ```bash
   git diff --staged path/to/file
   ```
   - Does the resolution preserve functionality from both sides?
   - Is the code syntactically correct?
   - Does it maintain consistency with the surrounding code?

## Step 6: Complete the Operation

After all conflicts are resolved:

```bash
# Verify no conflicts remain
git status

# Continue the operation
git rebase --continue  # or git merge --continue, or git cherry-pick --continue
```

**Don't commit manually** unless explicitly asked by the user.

## Resolution Principles

### Safe to Combine (Keep Both)
- Different functions/methods added in same file
- Different imports that don't conflict
- Different configuration options
- Non-overlapping changes to different parts of code

### Choose One Side
- Whitespace/formatting differences (keep consistent style)
- Duplicate additions (same functionality added twice)
- One side is clearly a newer/better version
- One side is objectively incorrect

### Manual Merge Required
- Both sides modified the same function logic differently
- Both sides added different implementations of same feature
- Refactoring on one side, functionality changes on other
- API/interface changes that need reconciliation

## Important Rules

- ⏰ **TAKE YOUR TIME** - rushing leads to mistakes
- 🔍 **RESEARCH THOROUGHLY** - understand why changes were made
- ❓ **ASK QUESTIONS LIBERALLY** - when anything is unclear
- 🧪 **SUGGEST TESTING** - after resolving, recommend running tests
- ⚠️  **NEVER BLINDLY CHOOSE** - always understand both sides
- 🚫 **DON'T COMMIT** - unless explicitly asked

## Quick Reference

```bash
# 1. Identify operation type
git status

# 2. Read conflict with diff3 format
cat path/to/file
# Look for three sections:
#   <<<<<<< HEAD          (ours)
#   ||||||| base          (original)
#   =======
#   >>>>>>> branch        (theirs)

# 3. Research commits on both sides
git log --oneline --graph --all -- path/to/file

# 4. View each side's full version (if needed)
git show HEAD:path/to/file              # "ours"
git show MERGE_HEAD:path/to/file        # "theirs" (in merge)
git show REBASE_HEAD:path/to/file       # "theirs" (in rebase)

# 5. View merge base (usually shown in diff3 middle section)
git show $(git merge-base HEAD MERGE_HEAD):path/to/file

# 6. Resolve, stage, verify
# (use Edit tool to remove markers and merge code)
git add path/to/file
git diff --staged path/to/file

# 7. Continue
git rebase --continue  # or git merge --continue
```
