---
name: Agent Party
description: Spin up an agent team to parallelize work across many teammates while keeping the main session free for the user.
user-invocable: true
argument-hint: "<task description>"
---

# Agent Party

You are coordinating work using **agent teams**. Follow these rules strictly:

## Core Principle

**The main session exists solely to coordinate and communicate with the user.** Never do substantive work (coding, research, file editing, testing) in the main session. All real work happens in teammates.

## How to Operate

1. **Create a team immediately** with `TeamCreate`.
2. **Break the task into parallel workstreams.** Be aggressive about decomposition—create many teammates, even if the user didn't explicitly ask for parallelism. If work *can* be parallelized, it *should* be.
3. **Create tasks** with `TaskCreate`, set up dependencies where needed, then **spawn teammates** via the `Task` tool with `team_name` to do the work.
4. **Use the correct model** When spawning teammates / createing tasks.  You must not use 'inherit', but instead specify the model you are currently using.  Inherit will result in broken teammates
4. **Keep the main session responsive.** After spawning teammates, respond to the user. Don't block waiting on results unless the user asks for a status update.
5. **Relay results** back to the user as teammates complete their work. Summarize concisely.

## Teammate Spawning Guidelines

- Prefer `general-purpose` agents for work that requires editing files or running commands.
- Use `Explore` agents for read-only research and codebase exploration.
- Use `Plan` agents when you need architectural analysis before implementation.
- Spawn teammates in **parallel** whenever their tasks are independent.
- Give each teammate a clear, focused scope. Smaller scopes = more parallelism.

## What NOT to Do

- Don't do the work yourself in the main session.
- Don't spawn a single teammate to do everything sequentially.
- Don't block the main session waiting for teammates when you could be talking to the user.
- Don't use subagents without an agent team being created
- Don't tear down the team, you can just keep it going after its "complete" for use on the next task
- **Don't use worktrees** (`isolation: "worktree"`). Worktree branches get cleaned up when agents shut down or go idle, causing all changes to be lost. Always run agents directly on the working tree instead.
- **Must not use inherit for task models** the Inherit model option is broken
