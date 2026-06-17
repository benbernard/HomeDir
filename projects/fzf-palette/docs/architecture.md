# Architecture

## Product Requirements

`fzf-palette` should:

- Prefer a native macOS list UI: fast, beautiful, polished, and not terminal
  shaped.
- Preserve `fzf` semantics where they matter: matching, query syntax,
  multi-select behavior, ranking, selected output, and the options used locally.
- Support configurable picker profiles with arbitrary starting commands that
  stream candidate rows into the native UI.
- Support preview panes as a first-class feature.
- Respect the local `fzf` environment that matters here: `FZF_DEFAULT_OPTS`,
  `FZF_DEFAULT_COMMAND`, `FZF_CTRL_T_COMMAND`, and `PATH`, while only
  implementing the supported subset of options.
- Open from a global hotkey with an effectively instant visual response.
- Meet the hard performance budgets: 200 ms maximum from hotkey keypress to
  interactive panel, and 50 ms maximum from query keystroke to adjusted visible
  results.
- Aim for the design targets: under 75 ms to show an interactive panel and
  about 10 ms or less per filtering keystroke.
- Be fully tested across functionality and performance, with unit, integration,
  UI/E2E, and benchmark gates.
- Open from local scripts and return selected text to the caller.
- Stay fast under repeated use, large directories, and preview-heavy workflows.

The app should not:

- Pretend to support all `fzf` options when it only supports a small subset.
- Block custom pickers behind hardcoded file/repo/download modes.
- Depend on Terminal.app, Ghostty, iTerm, Alfred, or tmux for the primary flow.
- Source interactive shell startup files on the hot path.
- Require Accessibility permission unless a profile explicitly asks to paste
  into another app.

## Core Decision

Build a resident Swift/AppKit app with a native palette UI. Back that UI with a
warm native search engine. Each picker profile provides a starting command or
static input, optional display parsing, optional preview command, and result
delivery rules. The first implementation is an in-process Swift
`NativeFuzzySearchEngine` for the initial local fuzzy and extended-search
subset. A later Go helper or maintained `fzf` fork can replace or augment that
boundary if parity needs outgrow the Swift engine, but the current decision is
to keep the Swift engine while it stays under the latency budget and local
parity remains testable.

This is a better product than embedding a terminal view as the main UI. A native
list can be faster to show, easier to make beautiful, easier to screenshot-test,
and easier to integrate with macOS selection, preview, clipboard, and result
delivery. The cost is compatibility work. We should not chase every upstream
`fzf` option. We should support the local subset thoroughly and reject
unsupported profiles explicitly.

## Compatibility Strategy

There is one runtime mode: native AppKit UI backed by a native engine. The app
may use non-interactive `fzf --filter` in tests as a compatibility oracle, but
it should not ship a PTY or terminal UI fallback.

Initial native support should cover:

- Plain fuzzy search.
- Extended query syntax.
- Case modes.
- Sorting and ranking compatible with `fzf`.
- Multi-select.
- `--query`.
- `--prompt`, `--header`, `--border`, `--height`, and `--reverse` mapped to
  native chrome or ignored where native UI owns the concept.
- `--pointer` and `--marker` mapped to native row prefixes,
  `--info=inline` mapped to native count/status placement, and `--color`
  accepted as a later theme hint.
- `--bind ctrl-A:select-all,ctrl-d:deselect-all` because this is in the local
  default options, plus `ctrl-/:toggle-preview` for preview-backed pickers.
- `--ansi`, at least enough to strip or render common colored git/rg input.
- `--delimiter`, `--nth`, and `--with-nth` so search text, displayed text, and
  hidden result fields can intentionally differ.
- `--preview` and `--preview-window` as subprocess-backed native preview panes.
- `FZF_DEFAULT_COMMAND`, `FZF_CTRL_T_COMMAND`, piped input, and profile
  `source.command`.

Native mode should initially reject:

- Arbitrary terminal `--bind` actions beyond the local supported set.
- `reload(...)` and complex transform actions unless a later profile needs them.
- ANSI-heavy interactive previews.
- Any option whose behavior is not understood.

The rule is simple: support the local subset honestly. Unsupported options should
produce a clear profile validation error. Do not silently approximate behavior
that changes selected output.

## Proposed Layout

```text
projects/fzf-palette/
|-- Package.swift
|-- README.md
|-- docs/
|-- Sources/
|   |-- FzfPaletteApp/
|   |   |-- AppDelegate.swift
|   |   |-- PalettePanelController.swift
|   |   |-- HotKeyController.swift
|   |   |-- SocketServer.swift
|   |   `-- main.swift
|   |-- FzfPaletteCore/
|   |   |-- EngineClient.swift
|   |   |-- EnvironmentSnapshot.swift
|   |   |-- Profile.swift
|   |   |-- SourceCommand.swift
|   |   |-- PreviewCommand.swift
|   |   |-- ResultDelivery.swift
|   |   `-- Metrics.swift
|   `-- fzf-palette/
|       `-- main.swift
|-- engine/
|   |-- go.mod
|   |-- cmd/fzf-palette-engine/main.go
|   `-- internal/
|-- Tests/
|   |-- FzfPaletteCoreTests/
|   |-- FzfPaletteUITests/
|   `-- FzfPaletteBenchmarks/
|-- scripts/
|   |-- build-app.sh
|   |-- install-app.sh
|   |-- test-install.sh
|   |-- bench.sh
|   `-- make-fixtures.sh
`-- fixtures/
    |-- engine-parity/
    `-- fake-source/
```

Use Swift Package Manager for the app, core code, CLI, and tests. Use a small Go
module under `engine/` if the first implementation imports or forks `fzf`
internals. Build local app bundles with scripts. Generated `.app` bundles should
be installed outside this repo, for example under `~/Applications/FzfPalette.app`.
The installer can also write a per-user LaunchAgent plist under
`~/Library/LaunchAgents` so the resident app starts at login.

## Runtime Components

### Resident App

The app should be `LSUIElement=true`: no Dock icon and no normal menu-bar
presence. It stays alive after login and owns the hotkey, socket server, warm
environment snapshot, native engine, settings window, preallocated panel, and
recent profile cache.

The configurable hotkey surface is launch-time configuration plus JSON profile
config. `FZF_PALETTE_HOTKEY` registers the first binding and
`FZF_PALETTE_HOTKEY_PROFILE` maps it to a profile. Top-level JSON `hotkeys`
entries register additional profile-specific bindings. `status --json` reports
the first active binding, every configured profile hotkey, whether Carbon
accepted each binding, and any fallback or registration error. UserDefaults store
a single settings hotkey/profile pair edited through the native settings window
or `fzf-palette settings set`; that binding is validated, canonicalized, merged
with env/JSON bindings, and reloaded immediately.

The resident process is non-negotiable for the hotkey path. If the process is
not already running, startup will be dominated by macOS app launch, dynamic
library loading, and shell environment discovery. That can still be optimized,
but it will not be instant.

Login startup is handled by the generated per-user LaunchAgent. It runs the
installed app executable directly, uses `RunAtLoad`, restarts after crashes, and
writes launchd stdout/stderr under `~/Library/Logs/FzfPalette`. The plist is
generated by `scripts/install-app.sh --launch-agent`; `--load` bootstraps it
immediately and `--uninstall-launch-agent` removes it.

### Palette Panel

Use a borderless or compact `NSPanel` centered on the active screen. The panel
should be precreated at app startup and hidden until invocation. It should:

- Appear above normal windows.
- Capture keyboard focus while open.
- Remember the previously focused app for result delivery.
- Close on selection, Escape, or explicit cancel.
- Avoid layout work on the hot path.

The visual design should be restrained and tool-like: native shadow, tight
geometry, excellent typography, stable row heights, clear selected state, and a
preview pane that feels intentional rather than decorative.

### Native List UI

Start with AppKit, not SwiftUI. SwiftUI can be revisited later, but the first
version needs predictable focus, keyboard routing, row virtualization, and
latency instrumentation. A custom `NSView`/`NSTableView` stack is the safer
initial path.

Core UI pieces:

- Query field with direct key handling.
- Virtualized result list.
- Optional preview pane.
- Status line for count, mode, and profile.
- Multi-select indicators.
- Compact error state.

The UI should update from immutable result snapshots produced by the engine.
Avoid per-row async work on the main thread.

The query input path is performance critical. A keypress must paint in the query
field and schedule filtering without waiting on source commands, preview
commands, filesystem traversal, or result delivery.

### Engine

The engine owns active item storage, query matching, ranking, and eventually
query parsing plus selected-output state. Source commands and preview commands
are separate app-level concepts: the engine should not know how to paste into
apps or launch previews.

The first engine is `NativeFuzzySearchEngine` in `FzfPaletteCore`. It caches
normalized row bytes, supports simple fuzzy matching plus the first
extended-search subset, preserves source order for empty queries, and is
benchmarked directly with `bench engine`. The current engine decision is to keep
extending this Swift boundary until the measured triggers in `native-engine.md`
justify a Go helper or forked `fzf` extraction.

The app communicates with the engine over local stdio or a Unix domain socket.
Keep the protocol JSON or MessagePack-like and simple:

- `configure`
- `startSource`
- `appendItems`
- `sourceFinished`
- `setQuery`
- `toggleSelect`
- `selectAll`
- `deselectAll`
- `move`
- `accept`
- `cancel`

The engine should stay warm across invocations. Starting the engine on every
hotkey press is not acceptable.

The engine must support cancellation and stale-result suppression. If the user
types quickly, older query work should be abandoned or ignored so the visible
list converges on the newest query within the keystroke budget.

### Environment Snapshot

GUI apps do not naturally inherit the interactive shell environment. The app
needs a cached environment snapshot so `FZF_DEFAULT_OPTS`, custom `PATH`, and
related settings are available without sourcing shell startup files on every
hotkey press.

Recommended behavior:

1. On app launch, asynchronously run a login-shell environment capture:
   `zsh -lc 'env -0'`.
2. Merge in the current app environment.
3. Allow overrides from a future config file or CLI request.
4. Cache the result in memory.
5. Provide a `fzf-palette env reload` command.

The hotkey path must never wait for shell startup. If the snapshot is not ready,
use a minimal fallback environment and log the degraded mode.

## Profiles

A profile is a named invocation contract. Examples:

- `default`: native `fzf` semantics with user defaults.
- `files`: use the normal file command, likely inherited from
  `FZF_DEFAULT_COMMAND`.
- `context-files`: first choose a root such as `~` or a direct child of
  `~/repos`, then run a file picker under that root.
- `repos`: select a direct child of `~/repos`.
- `downloads`: select recent files from `~/Downloads`.
- `git-branches`: start from a git branch command and preview `git log`.
- `git-commits`: start from `git log --color=always` and preview `git show`.
- `custom`: caller-provided starting command.

Profiles should be data, not separate app code. A profile can define:

- Working directory.
- Source command, static source items, or stdin source.
- Supported `fzf` args.
- Environment overrides.
- Display/search parsing such as delimiter, searchable fields, and displayed
  fields.
- Preview command and preview layout.
- Result mode: return, copy, paste, open, or run command.
- Multi-select handling.

The first runtime profile store loads built-ins plus optional JSON profiles from
`~/Library/Application Support/FzfPalette/profiles.json`, or from
`FZF_PALETTE_PROFILES_FILE` when that app environment variable is set. JSON
profiles are data-only and can override built-ins by name. `fzf-palette env
reload` refreshes the loaded profile store.

The existing `bin/ts` prototype has useful profile thinking, especially the
two-stage context picker. The native app should absorb the ideas, not depend on
Terminal.app automation.

## Program Context

Hotkey-triggered pickers should understand the app the user was working in
before the palette appeared. Explicit script/CLI requests still use the cwd they
send, but hotkey requests resolve cwd from the frontmost program before profile
resolution.

Resolution order:

1. Explicit CLI `--cwd` or profile `cwd` for script-triggered requests.
2. Hotkey program context from the frontmost app.
3. Profile default cwd, if configured.
4. App fallback cwd.

Target providers:

- Codex desktop app (`com.openai.codex`): read a bridge JSON file written by
  local hooks/scripts.
- Claude desktop app (`com.anthropic.claudefordesktop`): read the same bridge
  file format.
- Ghostty (`com.mitchellh.ghostty`): use the documented Ghostty/tmux setup by
  resolving the most recent attached `default` tmux client through
  `~/bin/tmux-resolve-pane-path`, including nested tmux.

All providers share a small total hotkey budget and fail closed. A missed context
is acceptable; delaying the panel is not.

Bridge files live by default under:

```text
~/Library/Application Support/FzfPalette/program-context/
```

The bridge JSON can be minimal:

```json
{"cwd":"/Users/benbernard/projects/fzf-palette"}
```

The CLI can write those files:

```bash
fzf-palette context set --app codex --cwd "$PWD"
fzf-palette context set --app claude --cwd "$PWD"
```

This avoids scraping Electron app internals. Codex/Claude integrations should
publish their active workspace explicitly; Ghostty can be inferred from tmux
because the terminal stack already exposes active pane cwd.

## Preserving fzf Defaults

Native mode should parse `FZF_DEFAULT_OPTS` and apply the supported local subset.
It does not need to support all upstream options.

Do not rewrite user defaults into a fake equivalent without tests. For each
option, classify it as:

- Supported in native mode.
- Ignored because native UI owns that concept.
- Unsupported.
- Error because it cannot safely work in this context.

This compatibility table should be part of the implementation, not only prose.
The initial compatibility table should be derived from
`local-fzf-compatibility.md`.

## Result Delivery

Every invocation gets a request id. Results should represent the same status
surface for hotkey and script callers:

- `selected`
- `cancelled`
- `no_match`
- `error`

For script-triggered requests, write a structured response over the socket and
let the CLI print selected text to stdout. For hotkey-triggered requests, the
profile decides whether the result is copied, pasted into the previously focused
app, opened, or ignored.

Pasting should be optional. It may require Accessibility permission, and it can
be flaky if the target app handles focus oddly. Clipboard and script return
paths should work without Accessibility.

## Error Handling

Do not show stack traces in the palette. Use:

- A compact error view in the panel for user-actionable failures.
- Logs under `~/Library/Logs/FzfPalette/`.
- Structured error responses for CLI callers.
- `os_log` categories for app, hotkey, socket, engine, source, preview, and
  performance.

## Non-Goals For The First Build

- Settings UI.
- Plugin system.
- Full support for arbitrary `--bind` actions.
- Cross-platform support.
- Cloud sync.
- Deep inference of the frontmost app's project root.
- Automatic paste as the only result path.

Frontmost-app project inference is attractive, but it is easy to make slow and
wrong. Ship explicit profiles first.
