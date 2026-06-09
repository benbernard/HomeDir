# Implementation Plan

## Phase 0: Scaffold

Goal: create the project skeleton without committing to UI polish too early.

Deliverables:

- `Package.swift` with app, core library, CLI, and tests.
- App bundle build script.
- Test runner scripts for unit, integration, UI/E2E, and benchmark suites.
- Minimal `LSUIElement` app that launches and stays resident.
- CLI that can find or launch the app and query `status`.
- Log directory under `~/Library/Logs/FzfPalette/`.

Exit standard:

- `scripts/build-app.sh` creates a runnable local `.app`.
- `fzf-palette status` can talk to the running app over a socket.
- `scripts/test-unit.sh` and `scripts/test-integration.sh` run successfully,
  even if the first assertions are skeletal.

## Phase 1: Warm Native Panel

Goal: prove the instant popup path before adding real source commands.

Deliverables:

- Global hotkey registration.
- Preallocated `NSPanel`.
- Native query field, result list placeholder, preview pane placeholder, and
  status line.
- Metrics for hotkey to visible panel.
- `bench panel` command.
- UI/E2E test for hotkey-to-visible-panel.

Exit standard:

- Warm hotkey to visible panel p95 is under 60 ms.
- Hotkey to interactive panel max is under 200 ms.
- Hotkey to interactive panel p95 is under 75 ms.
- Panel has no visible resize jump or blank white flash.
- Unit, UI/E2E, and `bench panel` coverage all pass.

## Phase 2: Source Commands And List

Goal: stream rows from configurable starting commands into a native list.

Deliverables:

- Source command runner.
- Incremental row ingestion.
- Static and stdin source support.
- Native virtualized result list.
- CLI `open` command that can pass a source command.
- `bench source` command.
- Integration tests for source streaming, stdin input, and cancellation.

Exit standard:

- Default file source from `FZF_DEFAULT_COMMAND` shows rows in native UI.
- Ctrl-T-style file source from `FZF_CTRL_T_COMMAND` shows rows in native UI
  through the built-in `ctrl-t` profile, with fallback to
  `FZF_DEFAULT_COMMAND`.
- Caller-provided starting command works.
- Closing the picker kills source commands.
- Source command integration tests pass without leaked subprocesses.
- Command-backed sources display first rows before command completion.

## Phase 3: fzf-Compatible Engine

Goal: match and rank rows with behavior close to the local `fzf` subset.

Current status: a first in-process Swift `NativeFuzzySearchEngine` exists and is
wired into the native panel. It covers simple fuzzy matching, exact terms,
prefix terms, suffix terms, inverse terms, standalone-bar OR clauses, cached row
storage, incremental row append, source-order empty queries, and case-sensitive
or case-insensitive matching, including smart-case default behavior. It also
handles escaped-space query terms and `--exact`/`-e` exact-match mode, including
fzf's quote-unquote behavior inside exact mode. Runtime requests now apply
`--query`/`-q`, `-i`, `+i`, `-e`/`--exact`, and `+e`/`--no-exact` to the native
panel. Runtime option resolution now parses `FZF_DEFAULT_OPTS` and
`FZF_DEFAULT_OPTS_FILE` with shell-style quoting, merges those defaults before
profile/request options, and supports `+m`/`--no-multi` to disable a default
`-m`. The search engine now also honors `+s`/`--no-sort` for source-order
filtering when a picker wants filtering without score-based reordering.
`--ansi` is supported by stripping ANSI sequences for matching and selected
output, and native result rows render named colors, xterm-256 colors, truecolor,
backgrounds, and common text-style SGR spans. Common terminal-control output is
also interpreted into a final visible screen state for carriage return,
backspace, cursor movement, cursor next/previous line, absolute
horizontal/vertical cursor positioning, clear-line, clear-screen,
insert/delete-line, and simple scroll up/down sequences. `--tiebreak=chunk`, `--tiebreak=begin`,
`--tiebreak=end`, ordered chunk/begin/end/index lists, and `--tiebreak=index`
are supported for tied scores, `--scheme=path` is supported for a first local
path-ranking subset, and `--scheme=history` is supported for score-only tie
ordering.
The native engine now owns multi-select state by source index, and the app panel
uses that engine state for toggle, select-all, deselect-all, source-order accept,
and multi-row result delivery for `--multi`/`-m` requests. The panel path can
defer match-range allocation and compute highlight ranges lazily for visible
rows, which keeps 100,000-row broad queries inside the large-keystroke budget.
It has unit tests, `fzf --filter` parity tests, live E2E coverage, `bench
engine`, `bench keystroke`, and `bench large-keystroke`.

Deliverables:

- Engine decision: keep the existing Swift engine as the product engine while it
  stays under the 10 ms p95 query/keystroke target and local parity remains
  testable. Revisit a Go helper or vendored `fzf` extraction only when the
  decision triggers in `native-engine.md` fire.
- Deeper query parsing for remaining local behavior not covered by the current
  extended-search subset, such as unsupported search-mode toggles or future
  local query forms that fail `fzf --filter` parity.
- Engine-level multi-select state and parity behavior are implemented for the
  supported local subset.
- Support for remaining local defaults beyond the current `-i`, `+i`, `-e`,
  `+e`, `--exact`, `--no-exact`, `-m`, `+m`, `--multi`, `--no-multi`,
  `--delimiter`, `--nth`, `--with-nth`, `--query`, stripped `--ansi`, and
  `--tiebreak=chunk`, `--tiebreak=begin`, `--tiebreak=end`, ordered
  chunk/begin/end/index lists, and `--tiebreak=index` support. `--scheme=path` is
  supported for a first local path-ranking subset, and `--scheme=history` is
  supported for score-only tie ordering. Native SGR
  rendering now covers named colors, xterm-256 colors, truecolor, backgrounds,
  and common text styles. Common
  terminal-control output is rendered to final visible screen state, including
  insert/delete-line and simple whole-buffer scroll controls; full interactive
  terminal-screen previews remain outside the current native renderer.
- Engine parity tests against real `fzf --filter` for supported behavior.
- `bench engine` command.
- `bench keystroke` command.
- `bench large-keystroke` command for the documented 100,000-row panel budget.
- Unit tests for query parsing, option validation, display parsing, selection,
  and result formatting.

Exit standard:

- Direct engine query max is under 50 ms and p95 is about 10 ms or less on the
  medium fixture.
- Supported local queries produce expected ordering and selected output.
- Query keystroke to visible rows max is under 50 ms on tiny and medium
  fixtures.
- Query keystroke to visible rows p95 is about 10 ms or less on tiny and medium
  fixtures.
- Unsupported options produce clear validation errors.
- Engine unit tests and parity tests pass for the supported local subset.

## Phase 4: Preview Panes

Goal: make previews a first-class native feature.

Current status: preview commands run as cancellable subprocesses, use
placeholder expansion, update from the active native row, debounce cursor/query
changes, suppress stale output with generation checks, and apply native
`--preview-window` right/up/left/down orientation, percentage sizing, and wrap
hints. Preview-window scroll expressions for literal lines and row fields are
applied to the native text view. Native preview rendering supports named
foreground/background colors, xterm-256 colors, truecolor, bold, dim, italic,
underline, and strikethrough SGR spans. Live E2E verifies preview updates after
cursor movement and query filtering, rich preview ANSI rendering,
terminal-control preview final-screen rendering, right/up preview layout,
preview scroll expressions, preview toggling, and preview child cleanup on
cancel.

Deliverables:

- Preview command runner.
- Field placeholder expansion for `{}`, `{1}`, `{2}`, etc.
- Right and up preview layouts.
- Wrap support.
- ANSI stripping plus row and preview SGR rendering for named colors,
  xterm-256 colors, truecolor, backgrounds, and common text styles.
- Common terminal-control final-screen rendering for preview output.
- Preview cancellation and debounce.
- `bench preview` command.
- Integration and UI/E2E tests for preview rendering, cancellation, stale-output
  suppression, and query responsiveness while previews run.

Exit standard:

- Local git, status, `bat`, and Claude session preview patterns work.
- Common `git show --color=always`, `rg --color=always`, and
  `bat --color always` preview output does not show raw escape sequences for
  supported SGR color and text-style spans.
- Progress-style preview output that uses carriage returns, cursor movement, and
  line clearing renders its final visible state without raw escape sequences.
- Preview output that uses insert/delete-line or simple scroll up/down controls
  renders its final visible state without raw escape sequences.
- `--preview-window=right:60%:wrap` and `--preview-window=up:60%` produce
  native panes with the requested orientation, approximate size, and wrap state.
- `--preview-window '+{2}-/2'` scrolls native previews to the target row field.
- Rapid cursor movement does not leak preview processes or show stale output for
  long.
- Preview commands never cause query keystrokes to exceed the 50 ms hard max.
- Preview tests prove stale previews cannot overwrite the current selection.

## Phase 5: Profiles

Goal: add useful workflows without hardcoding them into app control flow.

Current status: the core profile model, validation, built-in profile catalog,
and JSON profile loading are implemented. The app loads profiles at startup,
reloads them on `env reload`, resolves named `open --profile ...` requests
before source loading, and merges profile source/display/preview/result settings
with CLI request overrides. Live E2E covers a caller-provided JSON profile that
defines a starting command, native chrome, hidden-field display/result parsing,
and preview command without passing those settings on the CLI. Two-stage sources
are also implemented: the first picker selection is transformed through its
stage result rules and used as `{}` input for the second picker. The built-in
`context-files` profile uses this to choose `~` or a direct child of
`~/projects`/`~/repos`, then pick a file or directory under that root. Live E2E
also covers the built-in `repos`, `downloads`, and `context-files` profiles
against an isolated temp `$HOME`.

Deliverables:

- Profile model.
- Profile validation.
- `context-files` two-stage root picker.
- `repos` picker.
- `downloads` picker.
- Git branch, commit, and status examples.
- Per-profile result mode.
- Unit tests for profile parsing, validation, unsupported options, and
  placeholder expansion.
- E2E tests for at least one custom starting-command picker.

Exit standard:

- The old Alfred-style `context-files` workflow exists in native app form.
- A brand-new picker can be created with only a starting command, display rules,
  preview command, and result rules.
- Profile tests cover both built-in and caller-provided picker definitions.
- Live E2E covers a caller-provided two-stage profile, including stage
  transition, second-stage preview, and hidden final output.
- Live E2E covers the built-in `repos`, `downloads`, and `context-files`
  profiles with deterministic temp-home fixtures.

## Phase 6: Paste And Focus

Goal: support paste into the previously focused app without making it mandatory.

Deliverables:

- Frontmost app capture before panel activation. Implemented in the app request
  path and reused across two-stage pickers.
- Accessibility permission check before sending Cmd-V.
- Paste mode that always writes the selected result to the pasteboard before
  attempting the keyboard event.
- Failure reporting when Accessibility permission, target restoration, pasteboard
  write, or event creation fails.
- E2E tests for return, copy, and paste result modes. Paste E2E uses
  `FZF_PALETTE_PASTE_LOG` so the normal suite proves result formatting and
  pasteboard behavior without sending Cmd-V to another app.
- E2E tests for command result mode and result-command process cleanup.

Exit standard:

- Paste works in normal text fields when Accessibility permission is granted.
- Copy mode remains available without Accessibility permission.
- CLI return mode remains unaffected by paste failures.
- Result-delivery tests pass without requiring paste mode for normal CLI usage.

## Phase 7: Polish

Goal: make the app feel durable.

Deliverables:

- Theme-aware visual design.
- Proper app icon.
- Login item or launch agent install path.
- Error view.
- Minimal settings or config file reload command.
- Full benchmark suite.
- Full test suite documented in `testing.md`.

Exit standard:

- Warm popup feels instant.
- Benchmarks enforce the latency budget.
- Visual checks catch blank or broken window states.
- The app can be installed and updated without manual bundle surgery.
- `scripts/test-all.sh`, `scripts/bench.sh smoke`, `scripts/bench.sh full`, and
  release-relevant `scripts/bench.sh soak` gates pass on the supported local
  machine.

Current implementation note: app bundle install plus per-user LaunchAgent
install/uninstall are implemented in `scripts/install-app.sh` and covered by
`scripts/test-install.sh`. The bundle build generates a deterministic `.icns`
icon and verifies `CFBundleIconFile` during install tests. The LaunchAgent
preserves safe hotkey environment values, including `FZF_PALETTE_HOTKEY_PROFILE`.
JSON-configured profile hotkeys, UserDefaults-backed settings hotkeys, a native
settings window, and `env reload` hotkey refresh are implemented. The panel has
an initial theme-aware visual pass with a vibrant rounded surface, rounded
results/preview panes, and custom rounded row selection; app-internal visual E2E
assertions cover those styling facts without requiring Screen Recording
permission. `scripts/test-visual-internal.sh` now also forces light and dark app
appearances and checks app-rendered internal snapshots for nonblank/nonflat
content plus luminance separation in the default `test-all` gate.

## Testing Gate

No feature is done when it only works manually. Each phase needs unit or
integration coverage for the logic it adds, plus UI/E2E coverage when user
interaction changes. Any feature that touches startup, filtering, preview,
rendering, result delivery, source commands, or engine behavior needs a matching
performance test or benchmark assertion.

Minimum local command surface:

```bash
scripts/test-quiet.sh
scripts/test-unit.sh
scripts/test-integration.sh
scripts/test-ui.sh
scripts/test-e2e.sh
scripts/bench.sh smoke
scripts/test-all.sh
```

`scripts/test-quiet.sh` should stay a no-popup development gate for logic edits
while the laptop is in active use. `scripts/test-all.sh` should run unit,
integration, UI, live app E2E, permission-free internal visual snapshots,
external screenshot attempts, install checks, and smoke benchmark gates.
`scripts/bench.sh full` should run before release points and before
performance-sensitive architecture changes land.
`scripts/bench.sh soak` should run before release points that touch lifecycle,
subprocess cancellation, panel show/hide, or memory behavior.

The current benchmark surface includes native engine, panel, direct hotkey,
Carbon event hotkey, 10,000-row keystroke, 100,000-row large-keystroke,
main-thread query task, source, preview, lifecycle cleanup, and CLI roundtrip
gates. The lifecycle cleanup gate covers repeated panel show/hide, source
cancellation, preview cancellation, RSS growth, and marker-tagged child-process
leaks. The release-scale wrapper runs the same lifecycle gate for 500 measured
cycles after warmup.

## First Technical Spike

The first spike should answer one question: can a resident Swift/AppKit app show
a native panel, stream rows from a starting command, and filter them fast enough
to feel instant?

Build only:

- Resident app.
- Preallocated panel.
- Native list UI.
- Source command runner.
- Simple in-process matcher if the Go engine is not ready yet.
- `bench panel`, `bench source`, and a minimal `bench keystroke`.

Do not build settings, profile editors, paste automation, or complex file
pickers until this spike passes. If the native UI cannot hit the latency target,
the project needs a different rendering strategy before anything else matters.
