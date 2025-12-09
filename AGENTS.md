# AGENTS.md

## Repository Structure and Source Control

### Source-Controlled Areas
- **Root home directory**: The home directory itself (`/Users/benbernard`) is under source control (git)
- **bin/ts**: Contains TypeScript modules that are source-controlled. This includes:
  - TypeScript source files in `bin/ts/src/` (executable with `tsx`)
  - Configuration files (package.json, tsconfig.json, biome.json, etc.)
  - Symlinks in `bin/ts/src/` for command names without `.ts` extension
  - Note: `node_modules/` and `dist/` (if present) are not tracked
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
- `repos/` contains numerous project subdirectories, each with its own `node_modules/` directory
- `bin/ts/` has its own `node_modules/` directory with hundreds of dependencies
- Recursive searches will scan thousands of dependency files causing severe slowdowns
- This makes glob patterns and grep searches extremely slow
- Other paths like some submodules also contain lots of library code that should not be searched

**⚠️  CRITICAL: NEVER run recursive searches in `repos/` or `bin/ts/` without excluding `node_modules/`**

### Solutions

**✅ Option 1: Search Only Git-Tracked Files (RECOMMENDED)**
```bash
# Use git ls-files to limit search scope
git ls-files | grep pattern
git ls-files | xargs grep search-term

# With Grep tool, specify the path to stay in source-controlled areas
# Use Grep with path: /Users/benbernard and avoid repos/ subdirectory
```

**This is the BEST approach** - it automatically excludes `repos/`, `bin/ts/node_modules/`, and other untracked files.

**Option 2: Explicitly Exclude node_modules**
```bash
# With find
find . -name node_modules -prune -o -name "*.ts" -print

# With grep/rg
grep -r --exclude-dir=node_modules pattern .
rg --glob '!node_modules' pattern .

# With Glob tool - avoid these patterns:
# ❌ Glob(pattern='**/*.ts')  # BAD - searches ALL of repos/
# ✅ Glob(pattern='bin/ts/src/**/*.ts')  # GOOD - specific directory
```

**Option 3: Search Specific Directories**
Limit searches to known source-controlled directories:
- ✅ `bin/ts/src/` (TypeScript modules - safe)
- ✅ `.config/` (configuration files)
- ✅ `.claude/` (Claude Code settings)
- ✅ `.zshrc.d/` (zsh configuration)
- ✅ Root-level dotfiles (`.tmux.conf`, `.bash_profile`, etc.)
- ❌ `bin/` (DO NOT - includes `bin/ts/node_modules/`)
- ❌ `repos/` (DO NOT - contains many `node_modules/` directories)

### Examples of What NOT to Do

```bash
# ❌ BAD - Searches all of home directory including repos/ and bin/ts/node_modules/
Glob(pattern='**/*.ts')
Grep(pattern='function', path='/Users/benbernard')
find . -name '*.ts'

# ❌ BAD - Will hit bin/ts/node_modules/
Glob(pattern='bin/**/*.ts')

# ❌ BAD - Will scan all projects under repos/
Grep(pattern='TODO', path='/Users/benbernard/repos')

# ✅ GOOD - Specific to source files only
Glob(pattern='bin/ts/src/**/*.ts')
Grep(pattern='function', path='/Users/benbernard/bin/ts/src')
git ls-files | grep pattern
```

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
- Source files in `bin/ts/src/` (executable TypeScript files)
- **No compilation needed** - runs directly using `tsx`
- Includes utilities like:
  - `ic` (interactive container/session management - wrapped by shell function)
  - `wt` (worktree management - wrapped by shell function)
  - `read-tree` (file tree scanner)
  - `git-cleanup`, `git-prune-old` (git utilities)
  - And more
- Has its own package.json, tsconfig.json, and node_modules (not tracked)
- `bin/ts/src/` is on PATH via `~/.zshrc.d/01_bin_ts.zsh`

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
2. Start with the shebang: `#!/usr/bin/env tsx`
3. Use `yargs` for CLI argument parsing (already in dependencies)
4. For scripts that interact heavily with shell commands, use the `zx` library (already in dependencies)
5. Make the file executable: `chmod +x bin/ts/src/your-script.ts`
6. **Add an entry to `bin/ts/manifest.ts`** with the command name and description
7. Run `npm run build` in `bin/ts/` to generate symlinks
8. The script is now available as `your-script` in your PATH

**Note**: Scripts run directly using `tsx` which compiles TypeScript on-the-fly. The `bin/ts/src/` directory is on PATH via `~/.zshrc.d/01_bin_ts.zsh`, along with `bin/ts/node_modules/.bin/` for accessing `tsx`.

### Script Manifest System

Scripts are managed through `bin/ts/src/manifest.ts`:
- **Manifest location**: `bin/ts/src/manifest.ts`
- **Purpose**: Defines all executable scripts with their descriptions
- **Symlinks**: The build process auto-generates symlinks in both `src/` and `dist/`
- **List all scripts**: Run `ben-scripts` to see all available scripts with descriptions

**DO NOT manually create symlinks** - they are auto-generated from the manifest.

To add a new script to the manifest:
```typescript
// In bin/ts/src/manifest.ts
export const scripts: Record<string, ScriptEntry> = {
  // ... existing scripts ...
  "your-script": {
    file: "your-script.ts",
    description: "What your script does",
  },
};
```

For library modules (non-executable code), add them to `excludedFiles` in the manifest.

### Example Script Structure

```typescript
#!/usr/bin/env tsx

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
2. Edit the `.ts` file directly - changes take effect immediately (no build step required!)
3. The module has its own dependencies in `bin/ts/node_modules/`
4. For development with type checking: `npm run build:watch` in `bin/ts/` (optional - runs TypeScript type checker in watch mode)
5. All executable scripts have:
   - Shebang: `#!/usr/bin/env tsx`
   - Execute permission: `chmod +x`
   - Entry in `bin/ts/manifest.ts` with description
   - Auto-generated symlink (created by `npm run build`)

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
- **Primary shell**: zsh
- **Configuration convention**: Use `~/.zshrc.d/` for shell configuration, NOT `~/.zshrc` directly
  - Files in `~/.zshrc.d/` are automatically sourced by `~/.zshrc` (sorted alphabetically)
  - Prefix with numbers for ordering (e.g., `00_`, `01_`, `02_`, etc.)
  - Examples: `04_nvm_lazy.zsh`, `04_pyenv_cached.zsh`, `05_ic.zsh`
  - This keeps configuration modular and organized
  - When adding new shell features, create a new file in `~/.zshrc.d/`, don't edit `~/.zshrc`
- Check `site/` for job-specific environment variables or aliases

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
- 🚨 **NEVER run recursive searches in `repos/` or `bin/ts/` without excluding `node_modules/`** (this includes from the root home dir)
- 🔒 Be careful not to commit secrets from source-controlled configs
- 🔍 **ALWAYS prefer `git ls-files` or targeted searches over broad recursive searches**
- ⚡ Search `bin/ts/src/` for TypeScript code, NOT `bin/ts/` (which includes node_modules)
