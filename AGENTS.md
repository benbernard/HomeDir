# AGENTS.md

## Repository Structure and Source Control

### Source-Controlled Areas
- **Root home directory**: The home directory itself (`/Users/benbernard`) is under source control (git)
- **bin/ts**: Contains TypeScript modules that are source-controlled. This includes:
  - TypeScript source files in `bin/ts/src/`
  - Configuration files (package.json, tsconfig.json, biome.json, etc.)
  - Build output in `bin/ts/dist/` (not tracked)
- **Configuration files**: Most dotfiles and `.config/` subdirectories are tracked

### NOT Source-Controlled
- **repos/** directory: Everything under `repos/` is NOT part of this repository
- **site/** directory: Contains useful job-specific configurations but is in a SEPARATE repository (not part of the home directory repo)

### Critical: Be Careful With Secrets
Since configuration files are source-controlled, never commit:
- API keys, tokens, or credentials
- Job-specific secrets or internal URLs
- Personal identification information

## File Search Best Practices

**CRITICAL WARNING**: Generic file searches in this directory will have severe performance issues.

### The Problem
- `repos/` contains numerous project subdirectories
- Each project under `repos/` has its own `node_modules/` directory
- Recursive searches will scan thousands of dependency files
- This makes glob patterns and grep searches extremely slow
- Other paths like bin/ts and some submodules also contain lots of library code
  that should not be searched

### Solutions

**Option 1: Search Only Git-Tracked Files (RECOMMENDED)**
```bash
# Use git ls-files to limit search scope
git ls-files | grep pattern
git ls-files | xargs grep search-term

# With Grep tool, specify the path to stay in source-controlled areas
# Use Grep with path: /Users/benbernard and avoid repos/ subdirectory
```

**Option 2: Explicitly Exclude node_modules**
```bash
# With find
find . -name node_modules -prune -o -name "*.ts" -print

# With grep/rg
grep -r --exclude-dir=node_modules pattern .
```

**Option 3: Search Specific Directories**
Limit searches to known source-controlled directories:
- `bin/ts/src/` (TypeScript modules)
- `.config/` (configuration files)
- `.claude/` (Claude Code settings)
- `bin/` (DO NOT DO THIS ONE, includes bin/ts/node_modules)
- Root-level dotfiles (`.tmux.conf`, `.bash_profile`, etc.)

## Key Directories

### site/
- Contains job-specific configurations and utilities
- Managed in a separate git repository
- Safe to reference but understand it's work-specific
- May contain overrides for configurations (e.g., `site/tmux.conf`)

### bin/
- Personal utility scripts (mix of shell, Perl, TypeScript)
- Mostly source-controlled
- Contains compiled binaries and one-off scripts

### bin/ts/
- TypeScript project with custom CLI utilities
- Source files in `bin/ts/src/`
- Built with npm/TypeScript
- Likely includes utilities like `ic` (interactive container/session management)
- Has its own package.json, tsconfig.json, and node_modules (not tracked)

### .config/
- Standard XDG config directory
- Contains configurations for:
  - nvim (Neovim)
  - fish (Fish shell)
  - git
  - ghostty (terminal)
  - Various other tools
- Most files are source-controlled

### repos/
- Working directory for various projects
- NOT part of the home directory repository
- Each subdirectory is typically its own git repository
- Avoid searching here unless specifically needed

## Working with TypeScript Modules (bin/ts)

### Creating New Scripts

**IMPORTANT**: All new utility scripts should be written in TypeScript in `bin/ts/src/`.

When creating a new script:
1. Write the TypeScript source in `bin/ts/src/your-script.ts`
2. Start with the shebang: `#!/usr/bin/env node`
3. Use `yargs` for CLI argument parsing (already in dependencies)
4. For scripts that interact heavily with shell commands, use the `zx` library (already in dependencies)
5. Build with `npm run build` in `bin/ts/`
6. The compiled script will be at `bin/ts/dist/your-script.js` and will be automatically available on PATH (via `~/.zshrc.d/01_bin_ts.zsh`)

**Note**: No need to create wrapper scripts or set execute permissions - the `bin/ts/dist` directory is on PATH, and Node.js will execute the scripts directly.

### Example Script Structure

```typescript
#!/usr/bin/env node

import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';
import { $ } from 'zx'; // Optional: for shell interactions

$.verbose = false; // Silence zx output

async function main() {
  const argv = await yargs(hideBin(process.argv))
    .option('option', {
      alias: 'o',
      type: 'string',
      description: 'Description',
      default: 'default-value',
    })
    .help()
    .alias('help', 'h')
    .example('$0 -o value', 'Example usage')
    .argv;

  // Your script logic here
}

main();
```

### Modifying Existing TypeScript Utilities

1. Source files are in `bin/ts/src/`
2. Check `bin/ts/package.json` for build commands
3. Compiled output goes to `bin/ts/dist/` (without `.js` extensions)
4. The module has its own dependencies in `bin/ts/node_modules/`
5. Build with: `npm run build` (runs biome check, esbuild, and removes `.js` extensions)
6. Watch mode available: `npm run build:watch` (automatically rebuilds and removes extensions on file changes)

## Configuration Management

This setup uses a "dotfiles in home directory" approach:
- Most configuration is directly in the home directory
- Some tools use `.config/` (XDG Base Directory standard)
- Site-specific overrides may exist in `site/`
- Configurations are source-controlled for portability

## Common Patterns

### Tmux Configuration
- Base config: `.tmux.conf`
- Nested tmux config: `.tmux.nested.conf` (sources base config, then overrides)
- May have site-specific overrides in `site/tmux.conf`

### Shell Configuration
- Check `site/` for job-specific environment variables or aliases
- I use zsh for my shell.  You can see my .d directory in ~/.zshrc.d which is
  where different types of settings should go rather than .zshrc

## Search Strategy Recommendations

When you need to find something:

1. **For specific files**: Use `git ls-files | grep filename`
2. **For code patterns**: Use `git grep` or `grep -r` with `--exclude-dir=node_modules`
3. **For general exploration**: Start with `ls` in known directories rather than recursive searches
4. **For TypeScript code**: Search specifically in `bin/ts/src/`
5. **For configs**: Search in `.config/` or root-level dotfiles

## Summary

- ✅ Home directory is source-controlled
- ❌ `repos/` is NOT source-controlled (separate projects)
- ⚠️  `site/` is separate repo with job-specific configs
- 🚨 ALWAYS avoid recursive searches that include `repos/` and `node_modules/`
- 🔒 Be careful not to commit secrets from source-controlled configs
- 🔍 Prefer `git ls-files` or targeted searches over broad recursive searches
