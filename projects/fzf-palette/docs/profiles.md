# Profiles And Starting Commands

The app should not be limited to a few hardcoded replacements. Every picker is a
profile. A profile defines where candidate rows come from, how they are displayed,
how previews work, and what happens with the selected result.

## Profile Shape

```json
{
  "name": "git-commits",
  "title": "Commits",
  "cwd": "$PWD",
  "source": {
    "type": "command",
    "command": "git log --pretty=oneline --abbrev-commit --color=always"
  },
  "query": "",
  "fzfOptions": [
    "--multi",
    "--ansi",
    "--preview",
    "git show --color=always {1} | head -$LINES"
  ],
  "display": {
    "ansi": true,
    "delimiter": " ",
    "withNth": "1..",
    "prompt": "commits>",
    "header": "Pick a commit",
    "pointer": ">",
    "marker": "*",
    "info": "inline"
  },
  "preview": {
    "command": "git show --color=always {1}",
    "window": "right:60%:wrap",
    "debounceMs": 75
  },
  "result": {
    "mode": "return",
    "fields": "1",
    "join": " "
  }
}
```

Profile JSON is loaded from:

```text
~/Library/Application Support/FzfPalette/profiles.json
```

For tests or local experiments, set `FZF_PALETTE_PROFILES_FILE` in the app
environment. The file can contain either a top-level `{"profiles": [...]}` object
or a raw JSON array of profiles. Omitted optional fields use the same defaults as
the Swift model.

Current runtime behavior:

- Built-in profiles are loaded first.
- User profiles from the JSON file override built-ins with the same name.
- `fzf-palette env reload` reloads the profile file.
- `fzf-palette open --profile name` resolves the profile before source loading.
- Explicit CLI source, display, preview, result, and query options override the
  matching profile defaults.
- Built-in profiles include `default`, `ctrl-t`, `context-files`, `repos`,
  `downloads`, `git-status`, and `git-commits`.
- Two-stage profiles are data-driven through `source.type = "twoStage"`.
- Top-level `hotkeys` entries register profile-specific global bindings. The
  first launch-env binding still comes from `FZF_PALETTE_HOTKEY`, optionally
  mapped with `FZF_PALETTE_HOTKEY_PROFILE`.

Example top-level hotkey config:

```json
{
  "profiles": [],
  "hotkeys": [
    {
      "profile": "context-files",
      "binding": "cmd+shift+k"
    }
  ]
}
```

## Source Types

### command

Run a starting command and stream stdout into the picker. This is the key feature
for arbitrary local workflows.

Examples:

```bash
rg --hidden -g '!.git/' --files
git status -s
git log --pretty=oneline --abbrev-commit --color=always
ls -1t "$HOME/Downloads"
```

Requirements:

- Run command outside the main thread.
- Stream rows incrementally.
- Support cancellation.
- Kill the process tree when the picker closes.
- Surface command failures in the UI and CLI response.

### stdin

CLI callers can pipe candidates into the app:

```bash
some-command | fzf-palette open --profile rows
```

The CLI forwards stdin to the app. This should behave like `fzf` over piped
input, with native UI on top.

### static

Profiles can provide a static list directly. This is useful for tiny menus and
tests.

### two-stage

Some profiles start with one picker and use its result to configure the next
picker. The important local example is choosing `~` or a direct child of
`~/repos`, then selecting files or directories inside that root.

Current behavior:

- A two-stage profile has `source.first` and `source.second` stage objects.
- Each stage defines its own `source`, `display`, optional `preview`, `result`,
  `query`, and `fzfOptions`.
- Stage sources can be `command` or `static`.
- The first stage runs as a normal native picker.
- The first selected row is transformed through the first stage's
  `display`/`result` rules.
- That selected text is then used as `{}` in the second stage command or static
  item templates.
- The second picker delivers the final result to the original CLI or hotkey
  caller.

Example:

```json
{
  "name": "project-files",
  "title": "Project Files",
  "source": {
    "type": "twoStage",
    "first": {
      "title": "Choose Root",
      "source": {
        "type": "static",
        "items": [
          "fzf-palette\t/Users/benbernard/projects/fzf-palette"
        ]
      },
      "display": {
        "delimiter": "\t",
        "withNth": "1",
        "prompt": "roots>"
      },
      "result": {
        "fields": "2"
      }
    },
    "second": {
      "title": "Choose File",
      "source": {
        "type": "command",
        "command": "root={}; find \"$root\" -type f -print"
      },
      "preview": {
        "command": "bat --color always {} 2>/dev/null || sed -n '1,120p' {}"
      }
    }
  }
}
```

The built-in `context-files` profile uses this source type. Its first stage lists
`~` plus direct children of `~/projects` and `~/repos`; its second stage lists
files and directories under the chosen root while pruning `.git` and
`node_modules`.

Live E2E covers the built-in `repos`, `downloads`, and `context-files` profiles
against an isolated temp `$HOME` so tests do not depend on the developer's real
directory contents.

## Preview Panes

Preview panes are first-class. They should not be treated as terminal leftovers.

Supported preview inputs:

- Current item text.
- Parsed fields such as `{1}`, `{2}`, and `{}`.
- Current query.
- Current working directory.
- Environment from the profile.

Supported preview behavior:

- Right pane, up pane, or hidden-by-default if configured.
- Wrap text.
- Debounce cursor/query changes.
- Cancel stale preview commands.
- Render ANSI color where practical.
- Show file previews with `bat` when configured.

Initial local preview commands to support:

```bash
git log -$LINES --pretty=oneline --abbrev-commit --color=always {}
git show --color=always {1} | head -$LINES
~/bin/status-preview.sh {}
bat --color always --highlight-line {2} {1}
```

`$LINES` should be provided by the app based on preview-pane height. It does not
need to match terminal `fzf` exactly, but preview commands that use it should get
a useful value.

## Display Parsing

The native UI needs to distinguish displayed text from selected output.

Support:

- `--delimiter`
- `--nth`
- `--with-nth`
- Field extraction for result output
- ANSI stripping/rendering
- Native prompt and header chrome through `--prompt` and `--header`
- Native pointer and marker prefixes through `--pointer` and `--marker`
- Native count/status placement through `--info=inline`

This covers local usages like `claude-session-picker`, which displays a friendly
column but returns a hidden session file path.

## Result Delivery

Result delivery should be configurable per profile:

- `return`: CLI prints selection to stdout.
- `copy`: write selection to the pasteboard.
- `paste`: restore previous app and paste.
- `open`: open selected path or URL with `NSWorkspace`.
- `command`: run a command with selected values.

Multi-select profiles need a join strategy: newline, space, NUL, or JSON.

The first implementation supports result field extraction for command-line
requests with `--result-fields`, using the same delimiter model as display
parsing. It also supports `return`, `copy`, `paste`, `open`, `command`, and
`ignore` delivery for single-select and `--multi`/`-m` requests. Multi-select
accepts marked rows in source order and joins selected output with the
configured `result.join` strategy. `paste` writes the joined result to the
pasteboard, restores the app captured before palette activation, and sends Cmd-V;
real paste reports a clear failure when macOS Accessibility permission or focus
restoration is unavailable.

For command results, profiles should define `result.command` and rely on the
same placeholder expansion model as previews. Example:

```json
{
  "result": {
    "mode": "command",
    "fields": "2",
    "join": "newline",
    "command": "open -R {}"
  }
}
```

That covers hidden-field pickers where the native list shows a friendly label
but the caller or command receives an underlying path or id.

## Validation

Profiles should be validated before they run. Validation should classify each
option as:

- Supported.
- Ignored by native UI.
- Unsupported.
- Requires future native implementation.

Unsupported options should fail with a clear error. Silent approximation is how
this project becomes unreliable.
