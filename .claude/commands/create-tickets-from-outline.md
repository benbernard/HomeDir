# Create Linear Tickets From Outline

You are helping the user convert a hierarchical markdown outline into structured Linear tickets with proper parent-child relationships.

## Phase 1: Analyze the Outline

First, carefully analyze the outline structure:
1. Identify hierarchical levels (parent → sections → sub-sections → items)
2. Count total items at each level
3. Note special markers (P0, P1, etc.)
4. Identify sections with multiple sub-items vs. single-line items
5. Look for external links to preserve
6. Spot special formatting (emails, doc links, etc.)

Present your analysis to the user.

## Phase 2: Gather Requirements

**CRITICAL:** Ask these questions BEFORE creating any tickets:

1. **Team/Project name** - What is the exact Linear team name?
2. **Parent ticket title** - What should the parent ticket be called?

Assume these things unless told otherwise:

1. **Priority handling** - P0/P1 markers should be ignore in the ticket metadata (keep in the titles/text)
2. **Assignees** - Tickets should not be assined
3. **Links** - External Links should be preserved
4. **Initial state** - Put tickets in backlog
5. **Labels** - add "linear-mcp" to all created ticket's labels

Wait for user confirmation before proceeding.

## Phase 3: Create Tickets

### Step 1: Create TODO List
Create a comprehensive TODO list with items like:
- Create parent ticket
- Create N main sub-issues under parent
- Create nested sub-issues under each section
- Mark each TODO as in_progress/completed as you work
- Make sure each ticket you want to create has a TODO, and all items in the
  outline have a ticket.

### Step 2: Create Issues

When creating issues:
Format descriptions as:
```markdown
Brief summary.

#### Outline:

1. First item
   - Sub-item
   - Sub-item
2. Second item
```

So every ticket has its full sub-section of the outline.  The top / first
ticket would have the entire outline in its body

#### Creation Order

1. **Parent ticket first** - Store the UUID from response
2. **Other issues** - Fine to create these in any order, but prefer going in a
   outline order from top to bottom

### Step 3: Technical Notes
- Use **UUID** (not identifier) for `parentId` parameter
- Example: Use `0df41782-...` not `AVA-2338`
- Labels are arrays: `["label1", "label2"]`
- Description supports markdown
- Update TODOs immediately after each completion

## Phase 4: VERIFICATION (Critical!)

**ultrathink:** Go through the outline LINE BY LINE and verify:
- Every numbered/bulleted item has a ticket
- Every nested item has a ticket
- No sections were skipped
- Sub-items under sub-items weren't missed

If you find missing tickets:
1. Create TODO for each missing item
2. Note which parent it belongs under
3. Create the missing tickets
4. Mark TODOs complete

## Phase 6: Summary

Provide user with:
- Total tickets created (breakdown by level)
- How many updated with outline content
- Link to parent ticket
- Confirmation of all settings (team, labels, state)

Example:
```
✅ Created 57 tickets:
   - 1 parent
   - 7 main sections
   - 49 nested items

✅ Updated 14 tickets with outline content

✅ All tickets:
   - Team: [Team Name]
   - Labels: [labels]
   - State: [state]

🔗 Parent: [URL]
```

## Important Reminders

**Don't:**
- Skip clarifying questions
- Use identifier instead of UUID for parentId/updates
- Forget to verify against outline
- Batch complete TODOs

**Do:**
- Ask ALL questions upfront
- Create comprehensive TODO list
- Verify carefully after creation
- Update TODOs in real-time
- Use UUID for parent/update references
- Preserve links and formatting
- Add outline context to multi-item sections

## Linear MCP Functions

```javascript
// Create
mcp__natoma-linear__create_issue({
  title: string,
  team: string,
  description: string,
  state: string,
  labels: string[],
  parentId: string // UUID!
})

// Update
mcp__natoma-linear__update_issue({
  id: string, // UUID only!
  description: string
})

// Get (to retrieve UUID)
mcp__natoma-linear__get_issue({
  id: string // Can use identifier
})
```

---

Now, ask the user to provide their outline and proceed with the phases above.
