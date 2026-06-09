# Trigger Protocol

The app needs two primary trigger paths:

- Global hotkey for interactive use.
- Local script/CLI trigger for automation.

Both paths should converge on one internal request model so profiles, metrics,
and result handling stay consistent.

## Request Model

```json
{
  "id": "uuid",
  "profile": "default",
  "cwd": "/Users/benbernard",
  "query": "",
  "source": {
    "type": "profile"
  },
  "fzfOptions": [],
  "display": {
    "ansi": false,
    "delimiter": null,
    "nth": null,
    "withNth": null,
    "prompt": null,
    "header": null,
    "pointer": null,
    "marker": null,
    "info": null
  },
  "preview": null,
  "env": {},
  "input": null,
  "result": {
    "mode": "return",
    "fields": null,
    "join": "newline",
    "command": null
  },
  "resultMode": "return",
  "timeoutMs": 0
}
```

Fields:

- `id`: caller-provided or app-generated request id.
- `profile`: named profile, defaulting to `default`.
- `cwd`: working directory for source and preview commands.
- `query`: initial query.
- `source`: profile source, caller-provided command, stdin, or static items.
- `fzfOptions`: supported `fzf`-style options for native mode.
- `display`: native display parsing and chrome derived from supported
  `fzf`-style options such as `--ansi`, `--delimiter`, `--nth`, `--with-nth`,
  `--prompt`, `--header`, `--pointer`, `--marker`, and `--info=inline`.
- `preview`: optional preview command override.
- `env`: environment overrides.
- `input`: optional newline-delimited input supplied by the caller.
- `result`: result delivery settings, including mode, selected fields, join
  strategy, and optional result command.
- `resultMode`: compatibility field for `return`, `copy`, `paste`, `open`,
  `command`, or `ignore`.
- `timeoutMs`: optional watchdog for automation.

The internal model should be richer than the first CLI. That keeps the socket
protocol stable as workflows grow.

## Global Hotkey

Use the resident app to register hotkeys. Current implementation:

- Start with Carbon `RegisterEventHotKey` for low overhead and no Accessibility
  requirement.
- Wrap it behind `HotKeyController` so it can be replaced by a package or event
  tap later.
- Read the legacy/default binding from `FZF_PALETTE_HOTKEY`, optionally mapped to
  a profile with `FZF_PALETTE_HOTKEY_PROFILE`, falling back to
  `ctrl+option+space -> default`.
- Read additional profile-specific bindings from top-level `hotkeys` entries in
  the JSON profile file.
- Expose normalized bindings, profile names, registration state, and any fallback
  or Carbon registration error through `fzf-palette status --json`.

Hotkeys now open their configured profiles through the same native picker path as
script-triggered `open --profile` requests. Persistent UserDefaults and a visible
settings editor are implemented for a single user-configured hotkey/profile
binding, and launch environment plus JSON config still provide scriptable and
file-backed configuration.

Supported launch-time syntax is `modifier+modifier+key`, for example:

```bash
FZF_PALETTE_HOTKEY=ctrl+option+space
FZF_PALETTE_HOTKEY=cmd+shift+k
FZF_PALETTE_HOTKEY=ctrl+option+shift+f18
FZF_PALETTE_HOTKEY_PROFILE=context-files
```

Aliases include `control`/`ctrl`, `alt`/`option`, and `command`/`cmd`. Bare keys
are rejected because a global hotkey without a modifier is too easy to trigger
accidentally.

Testing has two non-physical hotkey paths:

- `fzf-palette test-control hotkey [profile]` exercises the app callback path
  directly.
- `fzf-palette test-control carbon-hotkey [profile]` posts a
  `kEventHotKeyPressed` Carbon event through the installed event handler.

The Carbon path is useful for permission-free E2E and benchmark coverage, but it
does not claim to be a physical keyboard event from macOS hardware dispatch.
`fzf-palette test-control physical-hotkey [profile]` posts a real `CGEvent`
keyboard sequence through `.cghidEventTap`; it is optional in default E2E because
fresh unsigned builds may lack Accessibility permission. Set
`FZF_PALETTE_REQUIRE_PHYSICAL_HOTKEY=1` to make that path mandatory on a
permissioned machine.

Physical keyboard UI automation is also available through:

- `fzf-palette test-control physical-type value`
- `fzf-palette test-control physical-key return|escape|up|down|left|right|tab|space|delete`

These commands refocus the real query field and post `CGEvent` keyboard input
through `.cghidEventTap`. The default E2E suite attempts a real type-and-return
accept flow and skips only when macOS denies Accessibility permission. Set
`FZF_PALETTE_REQUIRE_PHYSICAL_UI=1` to make that path mandatory on a permissioned
machine.

Hotkey flow:

1. Hotkey received.
2. Capture frontmost app identity and active screen.
3. Create request from the hotkey's configured profile.
4. Show preallocated panel immediately.
5. Start profile source command, if it is not already warm.
6. Stream rows into the native engine and render snapshots.
7. Deliver result according to profile.
8. Return focus to the previous app when appropriate.

The panel must show before expensive filesystem work. A visible, focused empty
native picker within a few dozen milliseconds is better than waiting to show a
fully populated list.

## CLI

Install a local CLI named `fzf-palette`.

Initial commands:

```bash
fzf-palette open --profile default
fzf-palette open --profile context-files --cwd "$PWD"
fzf-palette open --profile repos --result return
fzf-palette open --source-command 'git status -s' \
  --preview-command '~/bin/status-preview.sh {}'
some-command | fzf-palette open --stdin --preview-command 'bat --color always {}'
fzf-palette cancel
fzf-palette env reload
fzf-palette bench panel --runs 100 --json
fzf-palette bench source --runs 40 --json
fzf-palette bench cli-roundtrip --runs 200 --json
fzf-palette status
```

CLI behavior:

- Connect to the app over a Unix domain socket.
- If the app is not running, launch it and retry for a short bounded interval.
- Print selected text to stdout for `resultMode=return`.
- Let scripts cancel the active picker or long-running result action with
  `fzf-palette cancel`.
- Print structured JSON only when `--json` is passed.
- Exit nonzero on cancel, timeout, or internal errors.

The CLI should be a compiled Swift executable from this project, not a shell
script that does significant work. Startup cost matters for automation, and a
compiled helper also avoids quoting bugs.

## Unix Domain Socket

Use a per-user Unix domain socket:

```text
~/Library/Application Support/FzfPalette/fzf-palette.sock
```

The socket server lives in the resident app. The protocol can start as
newline-delimited JSON:

```json
{"type":"open","request":{...}}
{"type":"cancel","id":"uuid"}
{"type":"env.reload"}
{"type":"status"}
{"type":"bench","request":{...}}
```

Responses:

```json
{"type":"result","id":"uuid","status":"selected","text":"...","items":["..."]}
{"type":"result","id":"uuid","status":"cancelled"}
{"type":"error","id":"uuid","code":"fzf_not_found","message":"fzf not found"}
```

Use one request per connection at first. Multiplexing is unnecessary until there
is a real concurrent-use need.

## URL Scheme

Add a URL scheme only after the socket path is reliable:

```text
fzf-palette://open?profile=context-files
```

The URL scheme is useful for Shortcuts, BetterTouchTool, and app launchers. It
is not a replacement for the socket because URL schemes are poor at returning
results.

## Result Modes

### return

The CLI waits for completion and writes selected text to stdout. This is the
most scriptable mode and should be the default for CLI invocations.

For `--multi` requests, accepted rows are returned in source order. The response
includes `items` with per-row selected text and `text` joined by the request's
result join mode.

### copy

Write selected text to the pasteboard. This requires no Accessibility
permission and works even when the frontmost app cannot be safely targeted. For
multi-select, the pasteboard receives the joined selected text.

### paste

Restore focus to the app captured at invocation time, then paste the selection.
This may require Accessibility permission. Treat it as a convenience mode, not
the base architecture.

### open

Open selected path or URL through `NSWorkspace`. Multi-select opens each
selected path or URL.

### command

Run a result command after expanding selected-row placeholders such as `{}`,
`{1}`, and `{2}`. The command runs in the request `cwd`; failure is returned as
a structured CLI error. For multi-select, `{}` expands to the joined original
rows.

### ignore

Useful for profiles where `fzf` key bindings perform the action internally.

## Source Commands

Script-triggered requests must be able to define a starting command without
editing app configuration:

```bash
fzf-palette open \
  --source-command 'git log --pretty=oneline --abbrev-commit --color=always' \
  --ansi \
  --multi \
  --preview-command 'git show --color=always {1}' \
  --result return
```

Rules:

- Source commands run in the request `cwd`.
- Rows stream incrementally to the native UI.
- Closing the picker kills the source command process tree.
- Stdin source is supported for pipeline workflows.
- Static source arrays are supported for tiny menus and tests.
- Source command stderr is captured for logs and error UI.

This is what keeps `fzf-palette` from being only a file picker.

## Preview Commands

Preview commands are part of the trigger/profile contract:

```bash
fzf-palette open \
  --source-command 'rg --column --line-number --no-heading --color=always TODO' \
  --delimiter ':' \
  --preview-command 'bat --color always --highlight-line {2} {1}' \
  --preview-window 'right:60%:wrap'
```

Rules:

- Preview commands run in the request `cwd`.
- `{}` expands to the selected row.
- `{1}`, `{2}`, etc. expand to parsed fields.
- `$LINES` is set based on preview-pane height.
- Stale preview commands are cancelled when the cursor moves or the query
  changes the active row.
- Preview output is rendered in the native preview pane.

## Compatibility With Existing Prototype

There is already a `bin/ts` prototype that exposes `gui-fzf-picker paste
--preset ...` and a shared `fzf-picker` helper. The native app should not depend
on that Terminal.app flow, but it should reuse the lessons:

- Script callers need clean stdout.
- GUI workflows need context profiles, especially root-then-file selection.
- Local `FZF_DEFAULT_OPTS` should be parsed for the supported subset because
  GUI-launched processes do not inherit normal shell state.
- Source commands and preview commands are the durable abstraction, not the
  handful of current presets.
- Terminal.app automation was useful prototype evidence, not a product fallback.
