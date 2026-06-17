# bin/ts - Personal TypeScript Utilities

A collection of TypeScript utility scripts compiled to standalone executables using Bun, with automatic rebuild on source changes.

For agent-specific edit rules, see `AGENTS.md` in this directory.

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
- **notifyctl**: Build and send native macOS notification apps from a shared manifest
  with per-app icons, click actions, and first-run permission guidance
- **close-prs**: Bulk close GitHub PRs with filters
- **read-tree**: Recursive file tree scanner
- **gui-fzf-picker**: Terminal-hosted FZF picker for Alfred hotkeys that prints
  paste-ready path text
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

### Generated Files

The build process owns these paths:

- `bin/` - executable wrapper scripts that auto-rebuild stale binaries
- `dist/` - standalone Bun executables
- `src/<command>` - command-name symlinks that point at source files

Do not edit those files directly. Edit `src/*.ts`, `src/lib/**/*.ts`,
`scripts/*.ts`, and `src/manifest.ts`.

### Manifest System

`src/manifest.ts` is the source of truth for executable commands. Each entry maps
a command name to its TypeScript source file and description. The build uses this
manifest to decide which files become commands and which wrapper/symlink names to
generate.

Non-executable TypeScript files should be listed in `excludedFiles` if they live
at the top level of `src/` and are not tests. This keeps the build warning useful:
an unlisted file is either a missed command or a library file that should be
explicitly excluded.

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

**Caution**: `bun run build` runs the `prebuild` script first. That script runs
`biome check --apply-unsafe .`, so it can rewrite files. For validation without
formatting changes, prefer `bun run typecheck`, `bun test`, and `bun run check`.

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

1. Create your TypeScript file in `src/` (e.g., `src/my-script.ts`) with:
   ```typescript
   #!/usr/bin/env tsx
   ```
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

Use `yargs` for command-line parsing. Use `zx` when the script is primarily
orchestrating shell commands. Add tests next to the source file when behavior is
non-trivial or when the command handles filesystem, git, network, or process
state.

## Shell Integration Pattern

Some commands need to alter the parent shell, which a normal child process cannot
do. Those commands use a shell integration pattern:

1. The zsh function creates a temp script path.
2. The TypeScript command receives that path, writes shell code into it, and
   exits.
3. The zsh function sources the temp script and removes it.

The main example is `ic`, whose wrapper lives in `~/.zshrc.d/05_ic.zsh`. Keep
this pattern when parent shell state matters, such as changing directories,
attaching tmux sessions, or exporting variables.

## Agent Notes

When working from the home repo, use `git ls-files` or targeted searches. Avoid
searching all of `bin/ts/` because `node_modules/`, `dist/`, and generated
wrappers are large or noisy. For code search, usually use:

```bash
rg 'pattern' src scripts
```

## Technology Stack

- **Runtime**: [Bun](https://bun.sh) - Fast JavaScript runtime and bundler
- **Language**: TypeScript
- **Testing**: [Vitest](https://vitest.dev)
- **Linting/Formatting**: [Biome](https://biomejs.dev)
- **Build**: Bun's `--compile` for standalone executables
