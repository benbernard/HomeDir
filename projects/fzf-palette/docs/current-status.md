# Current Status

This document keeps the plan honest. The project now has real code, but it is
not a complete `fzf` replacement yet.

## Implemented

- Swift Package Manager project with:
  - `FzfPaletteCore` library.
  - `FzfPaletteApp` resident AppKit executable.
  - `fzf-palette` CLI executable.
  - Unit, integration, UI, and benchmark test targets.
- App-bundle build and install scripts.
- Per-user LaunchAgent install/uninstall path in `scripts/install-app.sh`:
  - Installs the app bundle to `~/Applications/FzfPalette.app` by default.
  - Writes `~/Library/LaunchAgents/dev.benbernard.fzf-palette.plist` when
    requested with `--launch-agent`.
  - Supports immediate `launchctl bootstrap`/`kickstart` through `--load`.
  - Supports plist unload/removal through `--uninstall-launch-agent`.
  - Preserves only safe hotkey launch environment values:
    `FZF_PALETTE_HOTKEY` and `FZF_PALETTE_HOTKEY_PROFILE`.
- `LSUIElement` app bundle metadata in `scripts/build-app.sh`.
- Generated app icon:
  - `scripts/generate-icon.swift` draws deterministic iconset PNGs.
  - `scripts/build-app.sh` converts them to `Contents/Resources/FzfPalette.icns`.
  - `Info.plist` sets `CFBundleIconFile` to `FzfPalette`.
- Resident AppKit app that starts a per-user Unix domain socket.
- Carbon global hotkey registration for one or more profile bindings.
- Launch-time hotkey configuration through `FZF_PALETTE_HOTKEY`, optionally
  mapped with `FZF_PALETTE_HOTKEY_PROFILE`, with normalized status fields for the
  active binding, all profile hotkeys, Carbon registration state, and
  configuration or registration errors.
- UserDefaults-backed hotkey settings:
  - `fzf-palette settings get|set|clear|show|close`.
  - Native settings window with hotkey and profile fields.
  - Settings hotkeys are validated, canonicalized, persisted, merged with
    env/JSON profile hotkeys, and reloaded immediately.
  - `FZF_PALETTE_USER_DEFAULTS_SUITE` isolates settings during E2E tests.
- CLI `status` and `env reload` requests over newline-delimited JSON.
- CLI `status --json` includes panel visibility, active query, row counts,
  preview visibility, prompt text, header text, pointer text, marker text, info
  style, settings hotkey/profile, settings-window visibility, and the last
  resolved hotkey program context for UI/E2E assertions.
- CLI `cancel` request for local scripts and tests to stop the active
  picker/action.
- CLI `context set|get|clear` bridge-file commands for Codex, Claude, and
  Ghostty program-context cwd publishing.
- CLI `open` request parsing for profile, cwd, source command, stdin, query,
  prompt, header, pointer, marker, inline info, preview command, preview window,
  fzf-style args, result mode, and timeout.
- Runtime `FZF_DEFAULT_OPTS` and `FZF_DEFAULT_OPTS_FILE` parsing:
  - Shell-like quoting is supported for the local option strings.
  - Parsed defaults are merged before profile/request fzf options.
  - Request/profile options can override defaults, including `+m` or
    `--no-multi` disabling a default `-m`.
- Native preallocated panel with:
  - Theme-aware native visual treatment using a vibrant rounded panel surface,
    rounded results/preview panes, and custom rounded row selection.
  - The panel is pinned visible across app deactivation; only accept, cancel,
    or request timeout should intentionally hide it.
  - Prompt label mapped from `--prompt`, falling back to profile/title text.
  - Query field.
  - Header label mapped from `--header`.
  - Result list.
  - Current-row pointer prefix mapped from `--pointer`.
  - Multi-select marker prefix mapped from `--marker`.
  - Preview pane.
  - Status line, with count-first mode mapped from `--info=inline`.
  - Native in-panel filtering through `NativeFuzzySearchEngine`.
  - Initial query application from `--query`/`-q`.
  - Runtime search case mode from smart-case default, `-i`, and `+i`.
  - Runtime multi-select mode from `-m`, `--multi`, `+m`, and `--no-multi`,
    including defaults from `FZF_DEFAULT_OPTS`.
  - ANSI stripping for `--ansi` display, matching, and selected output.
  - Native result-row ANSI rendering for named foreground/background colors,
    xterm-256 colors, truecolor, bold, dim, italic, underline, and
    strikethrough SGR spans.
  - Delimiter, `--nth` search scope, and `--with-nth` display transformation.
  - Native match highlighting for direct matches and `--nth` matches whose
    fields are visible in the displayed row.
  - Return-to-accept and Escape-to-cancel handling.
  - Arrow Up/Down selection movement even while the query field is focused.
  - Tab accepts the current row in single-select mode, which lets two-stage
    profile flows transition without relying on Return.
- First native fuzzy search engine:
  - Stored in `FzfPaletteCore` as `NativeFuzzySearchEngine`.
  - Caches normalized row bytes when rows are replaced or appended.
  - Supports source-order empty queries.
  - Supports simple fuzzy matching, exact terms, prefix terms, suffix terms,
    inverse terms, standalone-bar OR clauses, ranking, and smart,
    case-sensitive, or case-insensitive modes.
  - Supports backslash-escaped literal whitespace in queries, such as
    `hello\ world`.
  - Supports `--exact`/`-e` exact-match mode and `+e`/`--no-exact` fuzzy-mode
    restoration, including fzf's quote-unquote behavior while exact mode is on.
  - Supports fzf-like length tiebreaks by default and explicit
    `--tiebreak=chunk`, `--tiebreak=begin`, `--tiebreak=end`, ordered
    chunk/begin/end/index lists, and `--tiebreak=index` source-order tie
    sorting.
  - Supports `+s`/`--no-sort` to preserve source order for non-empty filtered
    queries while still computing match ranges for highlighting.
  - Supports `--scheme=default`, a first `--scheme=path` subset that prefers
    basename matches for file/path ranking, and a first `--scheme=history`
    subset that uses fzf-like score-only tie ordering.
  - Owns multi-select state by source index, including toggle, select-visible,
    deselect-all, fallback accept, and source-order selected-row output.
  - Supports field-scoped matching through `--nth`/`-n`, including ranges and
    negative indexes.
  - Returns stable row indexes, scores, and byte ranges for native match
    highlighting when callers need full ranges.
  - Supports score-only panel filtering with lazy visible-row match range
    computation, avoiding per-candidate highlight allocation on broad queries.
  - Carries search-to-display range maps so field-scoped search matches can
    highlight the corresponding visible display field.
  - Sorts lightweight index/score candidates before materializing `PaletteRow`
    results on the panel path so broad-match queries over 100,000 rows stay
    inside the large-keystroke target.
  - Backs both `SimpleMatcher` compatibility calls and the native panel.
- CLI `open` now holds the socket request while the panel is active and returns:
  - `selected` with the accepted row.
  - `cancelled` on Escape.
  - `timeout` when the request exceeds its timeout.
- Test-control socket requests gated by `FZF_PALETTE_ENABLE_TEST_CONTROL=1`:
  - `fzf-palette test-control accept`
  - `fzf-palette test-control cancel`
  - `fzf-palette test-control hotkey`
  - `fzf-palette test-control carbon-hotkey`
  - `fzf-palette test-control toggle`
  - `fzf-palette test-control toggle-preview`
  - `fzf-palette test-control select-all`
  - `fzf-palette test-control deselect-all`
  - `fzf-palette test-control query`
  - `fzf-palette test-control key`
  - `fzf-palette test-control move-down`
  - `fzf-palette test-control move-up`
- Source loading from:
  - Named built-in and JSON-configured profiles.
  - Profile default command via `FZF_DEFAULT_COMMAND`, falling back to
    `rg --hidden -g '!.git/' --files`.
  - Built-in `ctrl-t` profile backed by `FZF_CTRL_T_COMMAND`, falling back to
    `FZF_DEFAULT_COMMAND`.
  - Caller-provided source command.
  - Stdin request input.
  - Static items in the internal model.
- Hotkey program-context awareness:
  - Codex desktop app (`com.openai.codex`) uses a bridge JSON file to resolve
    cwd.
  - Claude desktop app (`com.anthropic.claudefordesktop`) uses the same bridge
    JSON format.
  - Ghostty (`com.mitchellh.ghostty`) resolves the active `default` tmux client
    through `~/bin/tmux-resolve-pane-path`, including the documented nested tmux
    setup, and falls back cleanly if no tmux context is available.
  - Context providers share one 50 ms total hotkey budget and fail closed rather
    than delaying panel display.
  - Explicit CLI/script `--cwd` requests remain authoritative; context
    inference is applied to hotkey-triggered opens.
  - Resolved context values are added to source/preview/result environments as
    `FZF_PALETTE_PROGRAM_CONTEXT_*`.
  - Built-in `context-files` includes the resolved context cwd as a `current`
    root.
- Profile store:
  - Built-in `default`, `ctrl-t`, `context-files`, `context-dirs`,
    `home-files`, `home-dirs`, `repos`, `repos-dirs`, `repos-files`,
    `downloads`, `downloads-files`, `git-status`, and `git-commits` profile
    definitions.
  - Optional JSON profile file at
    `~/Library/Application Support/FzfPalette/profiles.json`.
  - Test/config override through `FZF_PALETTE_PROFILES_FILE`.
  - `env reload` reloads both the shell environment snapshot and profile store.
  - Profile requests merge source, display, preview, result, and supported
    fzf-option settings before source loading starts.
  - Two-stage sources run one native picker, use its selected output as the
    placeholder input for a second picker, and return the second picker's final
    result to the original caller.
  - Top-level JSON `hotkeys` entries register additional profile-specific
    bindings, and `env reload` refreshes those registrations.
- Incremental source streaming for command-backed sources. The panel can show
  rows as stdout lines arrive instead of waiting for command completion.
- Result formatting with field extraction and join modes, exposed through
  `--result-fields` and `--join`.
- Multi-select result delivery for `--multi`/`-m` requests:
  - Selection state is owned by the native engine and tracked by source index so
    selected output stays in source order across filtering.
  - Space toggles the current row.
  - Control-A selects all visible rows.
  - Control-D clears marked rows.
  - Accepted rows are returned in source order.
  - Hidden-field selected output is covered for newline, space, NUL, and JSON
    joins in unit tests, with live E2E coverage for space and JSON joins.
  - `return`, `copy`, `paste`, `open`, `command`, and `ignore` modes accept multi-row
    selections.
- Result delivery modes:
  - `return`: send the selected text back to the CLI.
  - `copy`: write the selected text to the pasteboard.
  - `paste`: write the selected text to the pasteboard, restore the app captured
    before palette activation, and send Cmd-V.
    - Live E2E uses gated `FZF_PALETTE_PASTE_LOG` app environment to record
      attempted paste text without sending a keyboard event to another app.
    - Real paste reports `paste_failed` when Accessibility permission, focus
      restoration, pasteboard write, or event creation fails.
  - `open`: open the selected path or URL with `NSWorkspace`.
    - Live E2E uses gated `FZF_PALETTE_OPEN_LOG` app environment to record
      attempted opens without launching external apps.
  - `command`: run a result command after placeholder expansion.
  - `ignore`: complete selection without emitting text.
- Command runner for source and preview subprocesses with:
  - No PTY mode.
  - Timeout handling.
  - cancellation tokens.
  - recursive process-tree termination.
  - stdout/stderr capture.
  - output size limits.
- Preview commands use cancellation tokens and generation checks so stale
  preview output cannot overwrite a newer active preview.
- Preview commands update from the active native row:
  - Initial source rows trigger preview for the first active row.
  - Cursor movement cancels stale preview work and starts the new row preview.
  - Query changes refilter the list and preview the new active row.
  - Preview launches are debounced by `PreviewConfig.debounceMs`.
  - `--preview-window` right/up/left/down orientation, percentage sizing, and
    wrap hints are applied to the native split preview pane.
  - `--preview-window` scroll expressions for literal lines and row fields,
    including `+25` and `+{2}-/2`, scroll the native preview text view.
  - Named foreground/background colors, xterm-256 colors, truecolor, bold, dim,
    italic, underline, and strikethrough SGR spans are rendered in preview
    output, with raw escape sequences stripped from the visible text.
  - Common terminal-control output in previews is interpreted into a final
    visible screen state: carriage return, backspace, tab stops, cursor
    movement, cursor next/previous line, absolute horizontal/vertical cursor
    positioning, clear-line, clear-screen, insert/delete line, and simple
    whole-buffer scroll up/down.
  - `--bind ctrl-/:toggle-preview` toggles the native preview pane when enabled.
- Source, preview, and result-command subprocesses are all cancellable through
  the same process-tree cleanup path.
- Initial profile, source, display, preview, result, selection, protocol,
  metrics, environment, placeholder, and fzf-option validation models.
- Test scripts:
  - `scripts/test-quiet.sh`
  - `scripts/test-unit.sh`
  - `scripts/test-integration.sh`
  - `scripts/test-ui.sh`
  - `scripts/bench.sh smoke`
  - `scripts/bench.sh full`
  - `scripts/bench.sh soak`
  - `scripts/test-install.sh`
  - `scripts/test-visual-internal.sh`
  - `scripts/test-all.sh`
- Native-panel E2E script:
  - `scripts/test-e2e.sh`
- App-internal visual snapshot test-control path:
  - Renders the real panel content view into a bitmap without requiring Screen
    Recording permission.
  - Reports sampled pixel diversity, non-background pixel ratio, query focus,
    average luminance, luminance standard deviation, effective appearance name,
    pane widths/heights, preview layout position/wrap state, preview content
    length, rounded/vibrant styling flags, custom row-selection styling, and
    basic layout violation counts.
  - `scripts/test-visual-internal.sh` launches the real app in forced light and
    dark appearances, captures permission-free internal snapshots, and enforces
    nonblank/nonflat rendering plus light/dark luminance separation in the
    default `test-all` gate.
- App-backed benchmark support:
  - `fzf-palette bench engine --json`
  - `fzf-palette bench panel --json`
  - `fzf-palette bench hotkey --json`
  - `fzf-palette bench carbon-hotkey --json`
  - `fzf-palette bench keystroke --json`
  - `fzf-palette bench large-keystroke --json`
  - `fzf-palette bench main-thread --json`
  - `fzf-palette bench source --json`
  - `fzf-palette bench preview --json`
  - `fzf-palette bench result --json`
  - `fzf-palette bench lifecycle --json`
  - `fzf-palette bench cli-roundtrip --json`
- Native engine benchmark over 10,000 generated rows. It measures score/order
  filtering plus lazy match-range resolution for the first visible rows,
  enforcing:
  - 50 ms max hard gate.
  - 10 ms p95 target gate.
- Native-panel keystroke benchmark over 10,000 generated rows, covering the
  query/filter/table-reload path and enforcing:
  - 50 ms max hard gate.
  - 10 ms p95 target gate.
- Native-panel large-keystroke benchmark over 100,000 generated rows, covering
  the same query/filter/table-reload path and enforcing:
  - 50 ms max hard gate.
  - 20 ms p95 target gate.
- Main-thread query task benchmark over 10,000 generated rows, enforcing:
  - 16 ms max hard gate for the synchronous main-thread query/filter/reload task.
  - 10 ms p95 target gate.
- Direct hotkey and Carbon event hotkey benchmarks covering resident-app hotkey
  dispatch to visible panel, enforcing:
  - 200 ms max hard gate.
  - 75 ms p95 target gate.
- Source-command benchmark covering first-row latency and completion time for a
  generated 100-row source command.
- Preview benchmark covering short preview render latency and query
  responsiveness while a slow preview command is running.
- Result-delivery benchmark covering accept-through-normal-panel-completion to
  returned app result response, including hidden-field selected output and panel
  hide verification.
- Lifecycle benchmark covering repeated panel show/hide, source cancellation,
  preview cancellation, app RSS growth, and marker-tagged child-process leaks.
  - The lifecycle loop drains per-cycle autorelease pools around benchmark work
    and AppKit panel show/hide to avoid hiding linear RSS growth until release
    soak runs.
- Release-scale lifecycle soak wrapper:
  - `scripts/bench.sh soak`
  - Runs `fzf-palette bench lifecycle --runs 500 --warmup 10 --json`.
  - Uses the same cycle-latency, RSS-growth, and zero-leaked-process gates as
    the shorter lifecycle benchmarks.
- CLI roundtrip benchmark covering socket connect, request write, app response,
  response read, and decode.
- Initial `fzf --filter` oracle tests for the supported local subset:
  - empty-query source order
  - simple fuzzy filtering/ranking
  - exact, prefix, suffix, inverse, and standalone-bar OR terms
  - escaped-space query terms
  - `--exact` mode and exact-mode quote unquoting
  - smart-case behavior
  - fuzzy and exact match range reporting
  - search-to-display highlight range projection
  - ANSI-stripped matching and selected output
  - SGR row span parsing for named colors, xterm-256 colors, truecolor,
    backgrounds, and text styles
  - terminal-control ANSI parsing for carriage return, backspace, cursor
    movement, absolute cursor positioning, clear-line, clear-screen,
    insert/delete line, and simple scroll controls
  - `--tiebreak=chunk`, `--tiebreak=begin`, `--tiebreak=end`, ordered
    tiebreak-list, and `--tiebreak=index` ordering
  - `+s`/`--no-sort` source-order filtering
  - `--scheme=path` path-ranking behavior for the supported local fixture
  - `--scheme=history` score-only ordering for the supported local fixture
  - `--nth` search-scope behavior
  - delimiter and `--with-nth` original-output behavior
- Fixture generator and small committed fixture samples.
- Unit and E2E coverage for `FZF_DEFAULT_OPTS` merging and `+m` override of
  the local default multi-select behavior.
- Unit and E2E coverage for `FZF_DEFAULT_COMMAND` and `FZF_CTRL_T_COMMAND`
  source resolution.
- Live E2E coverage for built-in `repos`, `downloads`, and `context-files`
  profiles using deterministic temp-home fixtures.
- Unit coverage for Codex, Claude, and Ghostty app classification, bridge-file
  parsing, cwd validation, Codex/Claude bridge resolution, and Ghostty/tmux
  directory resolution.
- Live E2E coverage that simulates Codex as the frontmost app, triggers a hotkey,
  and verifies the resolved bridge cwd in app status.

## Verified

These commands have passed locally, or exited successfully with the documented
macOS permission-gated skips noted below:

```bash
swift test
scripts/test-quiet.sh
scripts/test-all.sh
scripts/test-ui.sh
scripts/test-e2e.sh
scripts/test-visual-internal.sh
scripts/bench.sh full
scripts/build-app.sh
.build/release/fzf-palette bench engine --runs 100 --warmup 10 --json
.build/release/fzf-palette bench panel --runs 20 --warmup 2 --json
.build/release/fzf-palette bench hotkey --runs 20 --warmup 2 --json
.build/release/fzf-palette bench carbon-hotkey --runs 20 --warmup 2 --json
.build/release/fzf-palette bench keystroke --runs 36 --warmup 6 --json
.build/release/fzf-palette bench large-keystroke --runs 24 --warmup 4 --json
.build/release/fzf-palette bench main-thread --runs 36 --warmup 6 --json
.build/release/fzf-palette bench source --runs 10 --warmup 2 --json
.build/release/fzf-palette bench preview --runs 8 --warmup 1 --json
.build/release/fzf-palette bench result --runs 50 --warmup 5 --json
.build/release/fzf-palette bench lifecycle --runs 5 --warmup 1 --json
.build/release/fzf-palette bench cli-roundtrip --runs 50 --warmup 5 --json
```

The latest full local `scripts/test-all.sh` run exited successfully on
2026-06-09. Permission-gated paths behaved as designed on this machine:

- `test-control physical-hotkey` skipped because the unsigned local app was not
  allowed to post physical keyboard events through Accessibility.
- `test-control physical-type`/`physical-key` skipped for the same Accessibility
  reason.
- `scripts/test-visual.sh` skipped because `screencapture` could not capture the
  app window/rect without Screen Recording permission.

The mandatory permission-free internal light/dark visual gate did pass in that
same `test-all` run.

Release soak verification is exposed separately because it is intentionally
longer, and it passed locally:

```bash
scripts/bench.sh soak
```

The latest 500-cycle soak run reported:

- leaked processes max: `0`
- lifecycle p95: `556.2895 ms`
- lifecycle max: `733.915667 ms`
- RSS growth max: `1.40625 MB`

Live app verification also passed:

```bash
open -gj .build/FzfPalette.app
.build/release/fzf-palette status --json
.build/release/fzf-palette open --source-command "printf 'alpha\nbeta\n'" --timeout-ms 250
```

The status response confirmed the app was running and listening at:

```text
~/Library/Application Support/FzfPalette/fzf-palette.sock
```

The smoke benchmark currently exercises the native fuzzy engine, app-backed
panel show, app-backed native-panel keystroke filtering for 10,000 and 100,000
rows, source-command startup/completion, preview responsiveness, lifecycle
cleanup, and CLI roundtrip.

The native engine benchmark enforces the current 50 ms max and 10 ms p95 target
for repeated score/order queries over 10,000 cached generated rows plus lazy
match-range resolution for the first visible rows.

The app-backed panel benchmark enforces the current 200 ms hard max and 75 ms
p95 target for showing the preallocated native panel.

The app-backed direct hotkey benchmark and lower-level Carbon event hotkey
benchmark enforce the current 200 ms hard max and 75 ms p95 target from hotkey
dispatch to visible native panel. The Carbon path posts a `kEventHotKeyPressed`
event through the installed Carbon event handler; it is stronger than a direct
callback test, but it is still not a physical hardware keydown.
An opt-in physical hotkey path now exists through
`fzf-palette test-control physical-hotkey [profile]` and
`fzf-palette bench physical-hotkey --json`. It posts a real `CGEvent` keyboard
sequence through `.cghidEventTap`; default E2E/bench gates skip hard failure
unless `FZF_PALETTE_REQUIRE_PHYSICAL_HOTKEY=1` is set because macOS may block
fresh local builds without Accessibility permission.

The app-backed keystroke benchmark enforces the current 50 ms max and 10 ms p95
target for applying query changes to 10,000 generated rows in the native panel.
The app-backed large-keystroke benchmark enforces the current 50 ms max and
20 ms p95 target for the same native-panel path over 100,000 generated rows.
The panel uses score-only broad filtering and computes match highlight ranges
lazily for visible rows so large result sets do not allocate highlight ranges
for every candidate on each keystroke.

The app-backed main-thread benchmark enforces a 16 ms hard max and 10 ms p95
target for the synchronous main-thread query/filter/reload task over the same
10,000 generated rows. This is the current gate for typing-related main-thread
stalls.

The app-backed source benchmark enforces current first-row and source-completion
budgets for the no-PTY source command path.

The app-backed preview benchmark enforces a current 300 ms preview-render hard
max, 250 ms preview-render p95 target, 50 ms query-while-preview hard max, and
10 ms query-while-preview p95 target so preview subprocesses cannot quietly
block filtering.

The app-backed result benchmark enforces a current 80 ms hard max and 45 ms p95
target from accepted selection through normal panel completion to app result
response.

The app-backed lifecycle benchmark enforces a current 2,500 ms hard max and
1,500 ms p95 target for a full panel/source/preview cancellation cycle, 50 MB
hard max RSS growth, and zero marker-tagged leaked child processes.

The CLI roundtrip benchmark enforces the current socket request/response budget
from the compiled CLI process.

The bounded `open` verification confirmed that the CLI can send an interactive
request to the resident app and receive a structured timeout instead of hanging
forever.

The automated E2E script launches the app with test control enabled, a custom
`FZF_PALETTE_HOTKEY`, a `FZF_PALETTE_HOTKEY_PROFILE`, and a JSON-defined profile
hotkey, verifies the configured bindings through app status, opens a
command-backed picker, triggers both the direct hotkey callback path and the
installed Carbon event-handler path for default and profile-specific bindings,
runs app-internal visual snapshot assertions
for nonblank pixels, focused query input, native vibrant/rounded styling, custom
row-selection styling, preview pane visibility, stable panel size, and basic
layout overlap violations. The internal visual script separately verifies forced
light and dark appearances without Screen Recording permission. The E2E script
also verifies `FZF_DEFAULT_OPTS` merge behavior and `+m` default override, runs
the app-backed panel benchmark,
verifies native
`--prompt`/`--header`/`--pointer`/`--marker` and `--info=inline` chrome through
app status,
verifies built-in `repos`, `downloads`, and `context-files` profiles against a
deterministic temp `$HOME`,
accepts the first row, verifies the selected text reaches the CLI, verifies
ordered `--tiebreak=begin,end` ranking, verifies `--tiebreak=chunk` ranking,
verifies `--scheme=path` path ranking,
verifies `--scheme=history` score-only tie ordering,
verifies `--nth` search scope, verifies
hidden-field result extraction with `--delimiter`, `--with-nth`, and
`--result-fields`, verifies multi-select select-all, deselect-all, toggle,
source-order return output, and hidden-field space/JSON joins, verifies
pasteboard copy mode, verifies side-effect-safe paste mode through
`FZF_PALETTE_PASTE_LOG`, verifies side-effect-safe open mode,
verifies command result mode, verifies preview updates after cursor
movement and query changes, verifies focused-query Arrow Up/Down selection
movement, verifies JSON-configured two-stage profile transition and hidden final
output, verifies the built-in `context-files` `ava<Tab>` then `gohan` transition
stays visible and returns the nested directory, verifies rich SGR preview ANSI
rendering without raw escape leakage, verifies terminal-control preview
rendering for final visible screen state, verifies insert/delete-line and simple
scroll-control preview rendering, verifies `ctrl-/` preview toggling, verifies
right/up preview-window layout and wrap behavior, verifies result-command child-process
cleanup through `fzf-palette cancel`, verifies source and preview child-process
cleanup, then opens another picker and verifies cancel behavior.

The `fzf` parity tests use the local `fzf` binary when available and skip only
if no executable is present. On this machine they run against
`~/submodules/fzf/bin/fzf`.

The install test builds a debug app bundle into temporary directories, writes a
temporary LaunchAgent plist, validates app metadata including the generated icon,
validates the plist content and optional hotkey environment value, then verifies
`--uninstall-launch-agent` removes it without touching the real user LaunchAgent
state.

## Resolved Alfred Workflow Regressions

Reported on 2026-06-12 after switching Alfred from the old TypeScript
`gui-fzf-picker` launcher to the native `fzf-palette` backend. These are now
covered by live E2E and smoke benchmark gates:

- Pressing `option+p`, typing `ava<Tab>`, then typing `gohan` makes the popup
  disappear. Fixed by handling Tab as accept in single-select mode and covered
  by an E2E `context-files` flow that chooses `ava`, transitions to the second
  picker, searches `gohan`, and returns the nested directory.
- While focus is in the search field, the popup does not accept arrow up/down
  for selection movement. Fixed by routing Arrow Up/Down through the shared
  palette key handler while the query field is focused and covered by E2E
  synthetic key assertions.
- When arrow up/down does work, selection movement is slow. Fixed by removing
  duplicate active-row preview notifications from selection movement and covered
  by `fzf-palette bench movement`, which is included in smoke benchmarks.
- Switching from `ava` to inside `ava` from `option+p` is slow. Reduced by
  making built-in context source commands stream their first rows directly
  instead of buffering through `awk`; the same `ava<Tab>` then `gohan` E2E flow
  covers the regression.
- Typing a query and then idling can make the palette disappear. Hardened by
  disabling AppKit panel auto-hide-on-deactivate and covered by E2E idle pauses
  after typing both `ava` and `gohan`.

## Not Done Yet

- Mandatory default E2E coverage for OS-level physical keyboard events. An
  opt-in `CGEvent` path exists, but it is not safe to require by default until
  the app has a reliable permissioned/signing/install story.
- Mandatory default UI automation through macOS keyboard input events. The
  opt-in physical UI path exists and E2E attempts it, but it skips by default
  when macOS denies Accessibility permission.
- Go helper or maintained `fzf` fork integration remains intentionally deferred:
  the current decision is to keep the Swift engine until a measured parity or
  latency trigger justifies the extra process/build complexity.
- Full interactive terminal-screen previews. Common noninteractive
  terminal-control output is rendered to final visible screen state, including
  simple line insertion/deletion and whole-buffer scroll controls, but
  alternate-screen apps, scroll regions, and terminal input are still out of
  scope.
- Mandatory external screenshot checks across dark/light mode. Permission-free
  internal dark/light pixel checks are now mandatory in `test-all`, but the
  OS-level `screencapture` path still skips by default when macOS denies Screen
  Recording permission.
- Mandatory OS-level physical-keydown timing benchmark in the default gate. The
  opt-in benchmark exists as `fzf-palette bench physical-hotkey --json`.
- Automatic Codex/Claude GUI workspace scraping. The implemented path is an
  explicit bridge file (`fzf-palette context set --app ... --cwd ...`) because
  scraping Electron internals is brittle; Codex/Claude hooks still need to write
  those bridge files in normal use.

## Next Slice

The next implementation step should deepen the engine path and close remaining
performance coverage:

- Make the opt-in OS-level physical keydown test mandatory once signing,
  installation, and Accessibility permission can be made reliable without
  weakening the permission model.
- Make the opt-in physical keyboard UI automation mandatory once Accessibility
  permission can be made reliable in the installed/signed app path.
- Add real visual screenshot or pixel checks for the native panel.
- Keep deepening the Swift engine against local parity tests; revisit a Go
  helper or forked `fzf` engine only if the measured triggers in
  `native-engine.md` fire.

That turns the current native fuzzy engine into a stronger local
`fzf`-compatible engine without weakening the latency gates that are already in
place.
