# Create New bin/ts Script

Create a new TypeScript utility script in the `~/bin/ts` project that will be compiled to a standalone executable with auto-rebuild capability.

## Required Reading

Before starting, read these files to understand the system:

1. **`~/bin/ts/README.md`** - Project architecture and workflow
2. **`~/bin/ts/src/manifest.ts`** - Script registry and examples
3. **`~/AGENTS.md`** - Section on "Working with TypeScript Modules (bin/ts)"
4. **`~/bin/ts/src/` directory** - Browse 1-2 existing scripts for patterns

## Script Requirements

Every new script must:
- Be written in TypeScript in `~/bin/ts/src/`
- Have shebang: `#!/usr/bin/env tsx`
- Use `yargs` for CLI argument parsing (already in dependencies)
- Follow existing patterns from other scripts
- Have an entry in `manifest.ts`
- Include proper error handling

## Process

### 1. Understand Requirements
- Ask the user what the script should do
- Clarify any ambiguities about behavior, inputs, outputs
- Check if similar functionality exists in other scripts

### 2. Read Context
Read the following files (in parallel when possible):
```
Read: ~/bin/ts/README.md
Read: ~/bin/ts/src/manifest.ts
Read: ~/AGENTS.md (sections on bin/ts)
Glob: ~/bin/ts/src/*.ts (to see existing scripts)
```

Pick 1-2 similar scripts to read as examples:
```
Read: ~/bin/ts/src/<similar-script>.ts
```

### 3. Design the Script
- Determine the command name (kebab-case, e.g., `my-script`)
- Plan the CLI arguments and options
- Identify any shared utilities in `src/lib/` to use:
  - `logger.ts` - logError, logInfo, logSuccess, etc.
  - `git.ts` - execGit, execGitSafe
  - `prompts.ts` - prompt, confirmAction, promptYesNo
- Check dependencies in `package.json`

### 4. Create the Script File

Write the script following this template structure:

```typescript
#!/usr/bin/env tsx

import yargs from "yargs";
import { hideBin } from "yargs/helpers";
// Import from lib/ if needed
// import { logError, logInfo, logSuccess } from "./lib/logger";

async function main(): Promise<void> {
  const argv = await yargs(hideBin(process.argv))
    .scriptName("my-script")
    .usage("$0 [options]")
    .option("option-name", {
      alias: "o",
      type: "string",
      description: "Description",
      default: "default-value",
    })
    .help()
    .alias("help", "h")
    .example("$0 --option value", "Example usage")
    .argv;

  // Your script logic here
  console.log("Script output");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

Key points:
- Use async/await for async operations
- Provide good help text and examples
- Handle errors gracefully
- Exit with proper codes (0 = success, 1 = error)

### 5. Add to Manifest

Add an entry to `~/bin/ts/src/manifest.ts`:

```typescript
export const scripts: Record<string, ScriptEntry> = {
  // ... existing scripts ...
  "my-script": {
    file: "my-script.ts",
    description: "Clear, concise description of what it does",
  },
};
```

Maintain alphabetical order within logical groupings (check existing groupings).

### 6. Build and Test

```bash
cd ~/bin/ts
bun run build
```

This will:
- Compile to standalone executable in `dist/`
- Generate wrapper script in `bin/` with auto-rebuild
- Create symlink in `src/` for development

Test the script:
```bash
my-script --help
my-script [test with actual arguments]
```

### 7. Verify Quality

Run quality checks:
```bash
cd ~/bin/ts
bun run typecheck  # Type checking
bun run check      # Linting and formatting
```

If there are issues, fix them before completing.

### 8. Document the Script

Add a comment block at the top of the script explaining:
- What it does (1-2 sentences)
- Example usage
- Any special requirements or dependencies

## Common Patterns

### Using Shared Libraries

```typescript
import { logError, logInfo, logSuccess } from "./lib/logger";
import { execGit, execGitSafe } from "./lib/git";
import { prompt, confirmAction } from "./lib/prompts";
```

### CLI with Subcommands

```typescript
const argv = await yargs(hideBin(process.argv))
  .command("subcommand", "Description", (yargs) => {
    return yargs.option("opt", { type: "string" });
  })
  .demandCommand(1, "You must specify a command")
  .help()
  .argv;
```

### Error Handling

```typescript
try {
  // risky operation
} catch (error) {
  logError(`Operation failed: ${error}`);
  process.exit(1);
}
```

## Done Criteria

The script is complete when:
- [x] Script file created in `src/`
- [x] Entry added to `manifest.ts`
- [x] `bun run build` completes successfully
- [x] Script runs and produces expected output
- [x] `bun run typecheck` passes
- [x] `bun run check` passes
- [x] Help text is clear and useful

## Important Notes

- **DO NOT** commit changes unless explicitly asked
- **DO NOT** modify other scripts while creating a new one
- **DO** ask questions if requirements are unclear
- **DO** use existing patterns from similar scripts
- **DO** leverage shared utilities in `src/lib/`
- **DO** test thoroughly before marking as complete

## After Creation

Inform the user:
1. The script is available as `<script-name>` in their PATH
2. Source changes will auto-rebuild on next execution (~0.9s)
3. They can run `ben-scripts` to see all available scripts
4. The wrapper script checks timestamps and rebuilds only when needed
