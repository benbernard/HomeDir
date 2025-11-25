# bin/ts - Personal TypeScript Utilities

A collection of TypeScript utility scripts for managing git repositories, uploads, and notifications.

## Scripts

- **ic**: Interactive Container/Session Manager - Clone GitHub repos and manage nested tmux sessions
- **s3upload**: Upload files to S3 with automatic configuration
- **git-cleanup**: Clean up merged and gone git branches
- **git-prune-old**: Delete branches older than specified days
- **claude-notify**: Smart notification system for Claude Code with tmux awareness
- **downloader**: Queue-based download manager with DynamoDB backend
- **wt**: Git worktree manager for efficient branch management
- **read-tree**: Recursive file tree scanner

## Development

### Running Scripts

All scripts run directly using `tsx` (no compilation needed):

```bash
./src/ic.ts clone user/repo
./src/s3upload.ts file.txt
```

The `src/` directory is on PATH, so you can also run:

```bash
ic clone user/repo
s3upload file.txt
```

### Testing

This project uses [Vitest](https://vitest.dev/) for testing.

#### Running Tests

```bash
# Run all tests
npm test

# Run tests in watch mode (re-runs on file changes)
npm run test:watch

# Run tests with UI (interactive test explorer)
npm run test:ui

# Run tests with coverage report
npm run test:coverage
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
# Format code
npm run format

# Run linter
npm run lint

# Run all checks (format + lint)
npm run check
```

### Building

While scripts run directly with `tsx`, you can build compiled versions:

```bash
# Build once
npm run build

# Build and watch for changes
npm run build:watch
```

Compiled files go to `dist/` directory.

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
│   ├── ic.ts          # Main scripts
│   ├── s3upload.ts
│   ├── *.test.ts      # Test files
│   └── ...
├── scripts/           # Build scripts
├── dist/              # Compiled output (not tracked)
├── coverage/          # Test coverage reports (not tracked)
├── package.json
├── tsconfig.json
├── vitest.config.ts
└── README.md
```
