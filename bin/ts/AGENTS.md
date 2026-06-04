# AGENTS.md

This directory is the TypeScript utility project for `/Users/benbernard/bin/ts`.

## Edit The Source, Not Generated Files

Edit:

- `src/*.ts`
- `src/lib/**/*.ts`
- `scripts/*.ts`
- `manifest.ts`
- package/config files

Do not edit:

- `bin/`
- `dist/`
- generated command symlinks in `src/`
- `node_modules/`

The build regenerates wrappers, compiled executables, and command symlinks.

## Adding A Command

1. Create `src/<command>.ts` with `#!/usr/bin/env tsx`.
2. Add the command to `src/manifest.ts`.
3. Use `yargs` for CLI parsing.
4. Use `zx` when shell command orchestration is the main job.
5. Add focused tests when behavior is non-trivial.
6. Run relevant checks.

Library files that are not executable should be added to `excludedFiles` in
`src/manifest.ts` if the build warns about them.

## Checks

For TypeScript edits, usually run:

```bash
bun run typecheck
bun test
```

For broader changes, also run:

```bash
bun run check
```

Be careful with:

```bash
bun run build
```

`build` has a `prebuild` step that runs `biome check --apply-unsafe .`, which can
rewrite files.

## Shell Integration

Some commands need to affect the parent shell. They should write shell code to a
temp file and rely on a zsh wrapper to source it. The main example is `ic`.

Do not simplify those wrappers into plain executable calls unless parent-shell
state is no longer required.

## Search

Search `src/`, not the whole project:

```bash
rg 'pattern' src scripts
```

Avoid recursive searches that include `node_modules/`, `dist/`, or generated
wrappers.
