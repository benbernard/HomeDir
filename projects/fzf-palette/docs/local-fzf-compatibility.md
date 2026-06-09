# Local fzf Compatibility

The goal is not to implement every upstream `fzf` option. The goal is to support
the `fzf` defaults and picker patterns used in this home directory.

## Shell Defaults

From `.zshrc.d/02_environment.zsh`:

```bash
FZF_DEFAULT_COMMAND='rg --hidden -g '!.git/' --files'
FZF_CTRL_T_COMMAND=${FZF_DEFAULT_COMMAND}
FZF_DEFAULT_OPTS='--height 40% --reverse --border -i -m --bind ctrl-A:select-all,ctrl-d:deselect-all'
```

Codex-shell-only color overrides add `--color=...`. Native UI can map these
colors later or ignore them in favor of a native theme. It should not reject the
profile because of local color options.

Required support:

- `FZF_DEFAULT_COMMAND` as the default source command.
- `FZF_CTRL_T_COMMAND` for the native Ctrl-T-style file profile, falling back to
  `FZF_DEFAULT_COMMAND`.
- `FZF_DEFAULT_OPTS`/`FZF_DEFAULT_OPTS_FILE` parsed with shell-style quoting
  for the supported local subset.
- `--height`, `--reverse`, and `--border` as native presentation hints.
- `--border-label` as a native presentation hint that does not reject profiles.
- `-i` as case-insensitive matching.
- `-m`/`--multi`.
- `+m`/`--no-multi` so a picker can disable the global `-m` default.
- `--bind ctrl-A:select-all`.
- `--bind ctrl-d:deselect-all`.
- `--color` accepted as a theme hint or ignored.

Current implementation covers `FZF_DEFAULT_COMMAND` for the built-in `default`
profile, `FZF_CTRL_T_COMMAND` for the built-in `ctrl-t` profile, fallback from
Ctrl-T to the default command, `FZF_DEFAULT_OPTS`/`FZF_DEFAULT_OPTS_FILE`
parsing and merging, `+m`/`--no-multi`, the supported select-all/deselect-all
binds, and ignored native-presentation options including `--height`,
`--reverse`, `--border`, `--border-label`, and `--color`.

## Tmux File Pickers

From `.tmux.conf` and `bin/ts/src/tmux-fzf-picker.ts`, current picker workflows
include:

- Pick files in current pane directory.
- Pick directories in current pane directory.
- Pick files/directories under `$HOME`, excluding `repos`.
- Pick direct repo directories under `$HOME/repos`.
- Pick files under `$HOME/repos`.
- Pick newest files in `$HOME/Downloads` with `ls -1t`.

Required support:

- Profile working directory.
- Source command based on `fd` or `ls -1t`.
- File versus directory filtering.
- Hidden files.
- No-ignore behavior.
- Exclude patterns such as `repos`, `.git`, and `node_modules`.
- Max depth for repo directory picker.
- Prefixing selected paths, such as `~/repos/`.
- Preview pane for file content and directory listing.
- Basic in-picker actions: toggle files/directories, go up, drill into
  directory, and jump to path can be later native commands.

Current implementation includes built-in `repos`, `downloads`, and two-stage
`context-files` profiles. Live E2E verifies those profiles with deterministic
temp-home fixtures so the checks do not depend on this machine's real project
and downloads directories. The native engine also supports a first
`--scheme=path` ranking subset for path-heavy pickers, with unit, parity, and
live E2E coverage, plus a first `--scheme=history` score-only ordering subset
for command-history style pickers.

## Git Shell Widgets

From `.zshrc.d/09_fzf.zsh`, current git pickers use:

- `--tiebreak=index`
- `--tiebreak=chunk|begin|end` and ordered tiebreak lists where useful for
  ranking path or git rows
- `-m`
- `--ansi`
- `--preview`
- `git log ... --color=always`
- `git show --color=always ...`
- `~/bin/status-preview.sh {}`

Required support:

- Preserve source order when `--tiebreak=index` is used.
- Support `--tiebreak=chunk`/`--tiebreak=begin`/`--tiebreak=end` and ordered
  tiebreak lists for the tested local subset.
- Multi-select with space-joined output.
- ANSI input stripping for matching and output, with SGR rendering for named
  colors, xterm-256 colors, truecolor, backgrounds, and common text styles in the
  native list and preview output.
- Common terminal-control preview output, such as progress/status repainting
  with carriage return, cursor movement, line clearing, insert/delete-line, and
  simple scroll controls.
- Preview commands with `{}` and field placeholders.
- Preview command cancellation while moving quickly.

Current implementation covers `--tiebreak=chunk`, `--tiebreak=begin`,
`--tiebreak=end`, ordered chunk/begin/end/index tiebreak lists,
`--tiebreak=index`, `+s`/`--no-sort`, `--scheme=path`, `--scheme=history`
score-only tie ordering, `-m`, ANSI stripping, rich SGR row and preview
rendering, common terminal-control preview final-screen rendering for cursor
movement, line clearing, insert/delete-line, and simple scroll controls, preview
commands, cancellation, exact-mode search, escaped-space query terms, local
`FZF_DEFAULT_OPTS` merging, `+m`/`--no-multi` override of a default `-m`, and
engine-owned multi-select state with hidden-field output. Space joined output is
covered in live E2E through `--join space`.

## Vim fzf Patterns

From `.vimrc.fzf`, useful behaviors include:

- `rg --column --line-number --no-heading --color=always --smart-case`.
- `--ansi`.
- `-d:`.
- `--preview 'bat --color always --highlight-line {2} {1}'`.
- `--preview-window '+{2}-/2'`.
- `right:50%` and `up:60%` preview layouts.
- Initial query via `-q` in older examples.

Required support:

- Colon delimiter.
- Field placeholders for preview commands.
- Highlight-line style previews through `bat`.
- Preview layout hints: right percentage and up percentage.
- Initial query.

Current implementation applies right/up percentage preview layouts and wrap
hints in the native split pane. It also applies the local scroll-expression
subset used by Vim-style previews, including literal `+25` and field-backed
`+{2}-/2` expressions that scroll the native preview around the target line.

The first `fzf-palette` app does not need to replace Vim's embedded fzf UI, but
these patterns are strong evidence for the option subset this user actually
expects.

## Claude Session Picker

`bin/claude-session-picker` uses:

- `--ansi`
- `--delimiter='\t'`
- `--with-nth=1`
- `--header`
- `--preview`
- `--preview-window=right:60%:wrap`
- `--height=100%`
- `--border`
- `--prompt`
- `--pointer`
- `--marker`
- `--bind ctrl-/:toggle-preview`
- `--info=inline`

Required support:

- Tab delimiter.
- Display first field while returning hidden path field.
- Native selected-output extraction through profile result fields or
  `--result-fields`.
- Header text.
- Prompt text.
- Pointer/marker as native style hints.
- Toggle preview with `ctrl-/`.
- Inline info as native count/status line.

Current implementation covers tab delimiters, `--with-nth=1`, hidden-path
return through `--result-fields`, native `--header`/`--prompt` chrome, native
`--pointer` current-row prefixes, native `--marker` multi-select prefixes,
`--info=inline` count/status mapping, preview commands, `right:60%:wrap`
preview hints, and `ctrl-/:toggle-preview`.

## Unsupported For Now

Unsupported does not mean impossible. It means do not block the first native
product on it.

- Arbitrary transform bindings.
- Reload bindings.
- Full terminal color-theme parity.
- Every `fzf.vim` window mode.
- Shell widgets that require ZLE integration.
- Interactive terminal cursor behavior that requires terminal input, alternate
  screen state, or scroll regions.

If a local workflow later needs one of these, add it deliberately with tests.
