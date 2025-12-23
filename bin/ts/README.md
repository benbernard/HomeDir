# bin/ts - Personal TypeScript Utilities

A collection of TypeScript utility scripts compiled to standalone executables using Bun, with automatic rebuild on source changes.

## Scripts

Run `ben-scripts` to see all available scripts with descriptions.

Key scripts:
- **ic**: Interactive Container/Session Manager - Clone GitHub repos and manage nested tmux sessions
- **wt**: Git worktree manager for efficient branch management
- **s3upload**: Upload files to S3 with automatic configuration
- **downloader**: Queue-based download manager with DynamoDB backend
- **git-cleanup**: Clean up merged and gone git branches
- **git-prune-old**: Delete branches older than specified days
- **claude-notify**: Smart notification system for Claude Code with tmux awareness
- **close-prs**: Bulk close GitHub PRs with filters
- **read-tree**: Recursive file tree scanner
- **analyze-zsh-startup**: Analyze zsh startup timing
- **converter**: Convert maildir email format to mbox

## Architecture

This project compiles TypeScript scripts to standalone Bun executables with intelligent wrapper scripts:

```
bin/ts/
├── src/              # TypeScript source files
├── bin/              # Wrapper scripts (auto-rebuild on change)
├── dist/             # Compiled Bun executables (~57MB each)
└── scripts/          # Build scripts
```

### How It Works

1. **Source files** (`src/*.ts`) - Your TypeScript code
2. **Build process** - Compiles to standalone executables in `dist/`
3. **Wrapper scripts** (`bin/*`) - Smart wrappers that:
   - Check if source is newer than binary
   - Auto-rebuild if needed (~0.9s)
   - Execute the compiled binary

The `bin/` directory is on PATH, so changes to source files are automatically picked up on next run.

## Development

### Running Scripts

Scripts are available directly in your PATH:

```bash
ic clone user/repo
s3upload file.txt
wt list
```

When you edit a source file, the wrapper automatically rebuilds it on next execution.

### Testing

This project uses [Vitest](https://vitest.dev/) for testing.

#### Running Tests

```bash
# Run all tests
bun test

# Run tests in watch mode (re-runs on file changes)
bun run test:watch

# Run tests with UI (interactive test explorer)
bun run test:ui

# Run tests with coverage report
bun run test:coverage
```

#### Test Structure

Tests are located next to the files they test:
- `src/ic.test.ts` - Tests for ic.ts
- `src/lib/testing/` - Shared test utilities and mocks

#### What's Tested

Currently, tests focus on business logic and pure functions:

**ic.ts (Interactive Container Manager)**:
- GitHub URL parsing (HTTPS, SSH, user/repo format)
- Setup hooks resolution
- Config loading and merging

More tests will be added incrementally for other scripts.

#### Test Coverage

Coverage thresholds are configured in `vitest.config.ts`:
- Lines: 70%
- Functions: 70%
- Branches: 70%
- Statements: 70%

Coverage reports are generated in `coverage/` directory (not tracked in git).

### Code Quality

```bash
# Type checking only
bun run typecheck

# Format code
bun run format

# Run linter
bun run lint

# Run all checks (format + lint)
bun run check
```

### Building

Build all scripts to standalone executables:

```bash
# Build once
bun run build

# Build and watch for changes (development mode)
bun run build:watch

# Or use the dev command (ensures setup + watch)
bun run dev
```

Compiled executables go to `dist/`, wrapper scripts are generated in `bin/`.

**Note**: You don't need to manually rebuild during development - the wrapper scripts auto-rebuild when you run them.

## Shared Utilities

Common functionality has been extracted to `src/lib/`:

- **logger.ts**: Shared logging functions (logError, logInfo, logSuccess, logWarning, logDebug)
- **git.ts**: Git execution helpers (execGit, execGitSafe)
- **prompts.ts**: User input functions (prompt, confirmAction, promptYesNo)
- **testing/**: Mock helpers for testing

## Project Structure

```
bin/ts/
├── src/
│   ├── lib/           # Shared utilities
│   │   ├── git.ts
│   │   ├── logger.ts
│   │   ├── prompts.ts
│   │   └── testing/   # Test mocks and helpers
│   ├── manifest.ts    # Script registry
│   ├── ic.ts          # Main scripts
│   ├── wt.ts
│   ├── *.test.ts      # Test files
│   └── ...
├── bin/               # Wrapper scripts with auto-rebuild
├── scripts/
│   └── build.ts       # Build script using Bun
├── dist/              # Compiled Bun executables (not tracked)
├── coverage/          # Test coverage reports (not tracked)
├── package.json
├── tsconfig.json
├── vitest.config.ts
├── biome.json         # Code formatting/linting config
└── README.md
```

## Adding New Scripts

To add a new script:

1. Create your TypeScript file in `src/` (e.g., `src/my-script.ts`)
2. Add an entry to `src/manifest.ts`:
   ```typescript
   export const scripts: Record<string, ScriptEntry> = {
     "my-script": {
       file: "my-script.ts",
       description: "What my script does",
     },
     // ... existing scripts
   };
   ```
3. Run `bun run build` to generate the executable and wrapper
4. The script is now available as `my-script` in your PATH

## Technology Stack

- **Runtime**: [Bun](https://bun.sh) - Fast JavaScript runtime and bundler
- **Language**: TypeScript
- **Testing**: [Vitest](https://vitest.dev)
- **Linting/Formatting**: [Biome](https://biomejs.dev)
- **Build**: Bun's `--compile` for standalone executables
