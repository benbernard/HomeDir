# Shell Startup

The primary interactive shell is zsh. Startup is split between a large root
`.zshrc`, modular files in `.zshrc.d/`, and optional site-specific overrides.

## Load Order

For interactive zsh sessions, the important path is:

1. `.zshenv`
2. `.zprofile` for login shells
3. `.zshrc`
4. `.shellrc.d/*.sh` and `.shellrc.d/*.zsh`, if that directory exists
5. `.zshrc.d/*.zsh`, loaded in sorted order
6. deferred `compinit`
7. fast syntax highlighting
8. late tool-specific blocks such as SDKMAN, gcloud, pyenv path setup, Bun,
   Forge, Gohan, and OrbStack

The `.zshrc.d/` directory is the normal place to add shell behavior. Avoid
editing `.zshrc` for new aliases, functions, or PATH entries unless the change
must happen in the top-level loader.

## Numbered Modules

Files in `.zshrc.d/` are sorted lexically. The numeric prefixes matter:

- `00_*`: early setup, Homebrew, Oh My Zsh shims, completion deferral.
- `01_*`: important PATH and baseline zsh setup.
- `02_*`: aliases, completions, environment, functions, history, prompt.
- `03_*`: session pickers and prompt integrations.
- `04_*`: language/runtime managers such as `fnm`, `pyenv`, and `rbenv`.
- `05_*`: command-specific integration such as `bat`, `ic`, and p10k custom
  pieces.
- `09_*` and later: optional tools and late integrations.
- `99_site.zsh`: loads the external `site/` repo when present.

When adding a new shell feature, choose a prefix based on what it depends on.
For example, a function that uses PATH should normally be after environment
setup, while PATH construction itself belongs earlier.

## Environment And PATH

`.zshrc.d/02_environment.zsh` sets core environment variables such as `EDITOR`,
`VISUAL`, `PAGER`, `GOPATH`, `RIPGREP_CONFIG_PATH`, and `FZF_DEFAULT_COMMAND`.
It also builds the zsh `path` array with submodule tools, `~/bin`, language
tool paths, and local bin paths.

`bin/ts/bin` is added by `.zshrc.d/01_bin_ts.zsh`, which makes generated
TypeScript wrappers available on PATH.

`site/` is loaded by `.zshrc.d/99_site.zsh` if present:

```zsh
source ~/site/site.zsh
export PATH=$PATH:~/site/bin
```

Treat `site/` as a separate repo and potential source of job-specific overrides.

## Completion Strategy

`.zshrc` defers `compinit` until after the `.zshrc.d/` files load. Early files
can queue completion definitions before `compinit` is available. After loading
the modules, `.zshrc` undefines temporary wrappers, runs `compinit`, and replays
queued `compdef` calls.

This is startup-performance sensitive. Be careful adding commands that invoke
slow external tools during shell startup.

## Language Managers

Active runtime setup includes:

- `fnm` in `.zshrc.d/04_fnm.zsh`, using recursive version-file lookup.
- cached `pyenv` init in `.zshrc.d/04_pyenv_cached.zsh`.
- cached `rbenv` setup in `.zshrc.d/04_rbenv_cached.zsh`.
- Bun setup near the end of `.zshrc`.

For pyenv, regenerate the cache manually after changing pyenv:

```bash
pyenv init - > ~/.cache/pyenv.zsh
```

## Shell Integration Pattern

Some CLIs need to change the parent shell. They cannot do that directly from a
child process, so they emit shell code into a temp file and the zsh wrapper
sources it.

The main example is `ic`:

- `.zshrc.d/05_ic.zsh` defines the shell function.
- `bin/ts/src/ic.ts` writes a shell integration script.
- The wrapper sources that script, then removes it.

Do not replace this with a plain executable call unless you are sure parent
shell state no longer matters.

## Profiling And Debugging Startup

Set `ZSH_PROFILE=1` to enable `zprof` output.

Set `ZSH_CMD_LOGGING=1` to enable xtrace-style command logging to a temp file.

There are TypeScript helpers for startup analysis:

```bash
analyze-zsh-startup
analyze-by-file
```

Those live in `bin/ts/src/` and are listed by `ben-scripts`.

## Common Edit Guidelines

- Add new shell features under `.zshrc.d/`, not directly in `.zshrc`.
- Keep startup commands cheap.
- Avoid adding secrets or internal URLs to tracked files.
- Check `site/` before assuming a value is globally defined in this repo.
- After shell changes, start a new shell or run targeted `zsh -n` checks on the
  edited files.
