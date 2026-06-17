# Testing Plan

`fzf-palette` needs full functional and performance coverage from the start.
Manual testing is not enough for a hotkey app with strict latency goals, native
focus behavior, subprocess previews, and compatibility with local `fzf`
workflows.

The suite should prove four things:

- The supported `fzf` subset behaves correctly.
- Native UI workflows work end to end.
- Subprocesses, previews, and result delivery are reliable.
- The hard latency budgets stay enforced as tests, not after-the-fact notes.

The expected bar is full coverage for shipped behavior: unit tests for pure
logic, integration tests for subprocess/socket behavior, UI/E2E tests for real
macOS interaction, and performance tests for every latency-sensitive path. A
feature that changes user-visible behavior or timing is not done with only one
of those layers.

## Required Test Layers

### Unit Tests

Unit tests should cover logic that can run without the app bundle:

- Profile parsing, inheritance, defaults, and validation.
- Supported, ignored, and unsupported `fzf` option classification.
- `FZF_DEFAULT_OPTS`, `FZF_DEFAULT_COMMAND`, and `FZF_CTRL_T_COMMAND` parsing.
- Query parsing for plain, extended, exact, prefix, suffix, inverse, and case
  behavior.
- Matching and ranking wrapper behavior for the supported engine subset.
- Multi-select state: toggle, select all, deselect all, accept, and cancel.
- `--delimiter`, `--with-nth`, hidden fields, and selected output formatting.
- Placeholder expansion for source, preview, and result commands.
- Preview debounce, cancellation, and stale-result suppression state machines.
- Result mode decisions for return, copy, paste, open, command, and ignore.
- Socket request and response encoding.
- Metrics aggregation, p50/p95/p99/max calculations, and budget failure logic.

Unit tests should include negative tests. Unsupported options must fail
predictably instead of being silently approximated.

### Engine Compatibility Tests

The engine should be tested against real `fzf --filter` for the supported local
subset. This does not mean shipping a terminal or PTY mode; it means using
upstream `fzf` as a non-interactive oracle in tests.

Compatibility cases:

- Plain fuzzy matching and ranking.
- Extended search syntax.
- Case-sensitive, case-insensitive, and smart-case behavior.
- `--tiebreak=chunk`, `--tiebreak=begin`, `--tiebreak=end`, ordered tiebreak
  lists, and `--tiebreak=index`.
- `+s`/`--no-sort`.
- `--scheme=path` for local path-ranking behavior.
- `--scheme=history` score-only ordering for command-history style pickers.
- ANSI input stripping or rendering behavior where it affects matching.
- `--delimiter`, `--nth`, `--with-nth`, and hidden return fields.
- `--query` initial query handling.
- Match range output for native highlighting.
- Multi-select selected output order.

The compatibility suite should use committed small fixtures plus generated
larger fixtures. Do not commit large generated datasets.

Current implementation status: the first native engine unit tests cover
empty-query source order, contiguous-ranking preference, incremental row append,
case-sensitive matching, exact/prefix/suffix/inverse terms, and standalone-bar
OR clauses, plus fuzzy/exact match range reporting and search-to-display range
projection for visible `--nth` fields. The first oracle tests
cover empty-query source order, simple fuzzy
filtering/ranking, exact/prefix/suffix/inverse terms, standalone-bar OR clauses,
smart-case behavior with local default options disabled, and
ANSI-stripped matching/output behavior. Unit tests also cover SGR span parsing
for named colors, xterm-256 colors, truecolor, backgrounds, bold, dim, italic,
underline, strikethrough, and partial resets. They also cover
terminal-control ANSI parsing for cursor next/previous line, vertical cursor
positioning, insert/delete-line, and simple scroll controls, plus
engine-owned multi-select state by source index, source-order selected output,
accepted-row fallback, append preservation, and replace-row clearing, plus
delimiter/`--with-nth` original-output behavior, `--nth` search-scope behavior,
negative field indexes, `--tiebreak=chunk`, `--tiebreak=begin`,
`--tiebreak=end`, ordered tiebreak-list, and `--tiebreak=index` ordering, and
`+s`/`--no-sort` source-order filtering, plus `--scheme=path` path-ranking
behavior for the supported local fixture and `--scheme=history` score-only
ordering. Live E2E covers initial
`--query` filtering, case-sensitive `+i` runtime requests, ANSI-stripped
`--ansi` output, `--nth` search scope, `--tiebreak=index` source-order ties,
ordered `--tiebreak=begin,end` ranking, `--tiebreak=chunk` ranking, `--no-sort`
source-order filtering, `--scheme=path` path ranking, `--scheme=history`
score-only tie ordering, and hidden-field multi-select output for space and JSON
joins. Match highlight and ANSI row rendering still need external
visual/screenshot coverage.

### Integration Tests

Integration tests should exercise the app logic below the visual UI:

- Source command startup, row streaming, exit codes, stderr, and cancellation.
- Stdin and static source input.
- Environment snapshot capture and reload.
- Preview subprocess launch, output truncation, cancellation, and stale output
  prevention.
- Socket server request routing and concurrent request rejection or queuing.
- CLI `status`, `open`, `bench`, and result-return flows.
- Result command execution, timeout handling, cancellation, and failure
  reporting.
- Process cleanup for source, preview, engine, and helper processes.

Every subprocess-owning feature needs a leak test. Closing the palette, changing
selection rapidly, or cancelling a request should not leave child processes
behind.

### UI And E2E Tests

UI/E2E tests should run against the real app bundle on macOS. They should test
observable behavior, not implementation details.

Required E2E workflows:

- Resident app launches and reports socket readiness.
- Global hotkey opens the panel.
- Query field is focused immediately.
- Typing filters visible rows.
- A typed query remains visible and focused after idling; the panel must not
  disappear without accept, cancel, or timeout.
- Arrow Up/Down move the selection while the query field is focused.
- Escape closes the panel.
- Accepting a row returns the expected selected text.
- Multi-select, select all, and deselect all work.
- Caller-provided starting command opens a custom picker.
- Stdin input opens a picker and returns selection.
- JSON-configured profiles work with source, display, preview, and result rules.
- JSON-configured two-stage profiles transition from the first picker to the
  second picker and return the second picker's hidden-field result.
- Single-select Tab accepts the current row so Alfred-style two-stage profile
  flows can transition without closing the popup unexpectedly.
- Built-in repo, downloads, and `context-files` profiles work before release.
- Hotkey-triggered opens resolve program context for Codex, Claude, and
  Ghostty/tmux when those apps are frontmost.
- Preview pane updates for cursor movement.
- Preview pane toggles when `ctrl-/:toggle-preview` is configured.
- Slow previews do not block typing or list updates.
- Return, copy, paste, open, and command result modes behave as configured.
- Accessibility permission failure falls back or reports clearly for paste mode.

Visual E2E checks should include screenshots or pixel assertions:

- Panel appears inside the latency budget.
- Query field is focused.
- Rows are nonblank when source rows exist.
- No blank white first frame.
- No resize jump between show and first rows.
- Preview pane is visible when configured.
- Long paths, headers, counts, and multi-select indicators do not overlap.
- Dark and light mode contrast is readable.

## Performance Tests

Performance tests are part of the main test plan. They should fail the build or
local gate when a hard maximum is exceeded after warmup.

Hard requirements:

- Hotkey keypress to interactive panel: 200 ms maximum.
- Query keystroke to adjusted visible rows: 50 ms maximum.

Design targets:

- Hotkey keypress to interactive panel: under 75 ms.
- Query keystroke to adjusted visible rows: about 10 ms or less.

Required benchmark coverage:

- Panel show/hide without source work.
- Synthetic hotkey to interactive panel.
- Source command first row and completion.
- Engine query latency without UI rendering.
- UI keystroke to visible-row update.
- UI selection movement, including preview-enabled rows.
- Preview responsiveness while query input continues.
- CLI-to-app roundtrip.
- Selection to result delivery.
- Repeated open/close memory growth.
- Child process cleanup after cancellation-heavy runs.

Keystroke tests must measure every keypress in the corpus. A low average with a
single 100 ms stall is a failure.

## Test Commands

The repo should expose a small stable command surface:

```bash
scripts/test-quiet.sh
scripts/test-unit.sh
scripts/test-integration.sh
scripts/test-ui.sh
scripts/test-e2e.sh
scripts/test-install.sh
scripts/bench.sh smoke
scripts/bench.sh full
scripts/bench.sh soak
scripts/test-all.sh
```

Expected behavior:

- `test-quiet.sh`: no-popup development gate. It runs unit, integration, and
  lightweight UI support tests only, so it does not launch or activate the
  AppKit panel.
- `test-unit.sh`: fast Swift and Go unit tests.
- `test-integration.sh`: subprocess, socket, CLI, profile, and engine
  integration tests.
- `test-ui.sh`: lightweight Swift UI test target for app-facing protocol and UI
  support assertions.
- `test-e2e.sh`: live resident-app accept/cancel smoke test using gated
  test-control socket actions, including native prompt/header/pointer/marker
  and inline-info chrome, JSON-configured profile behavior, built-in profile
  behavior against an isolated temp `$HOME`, focused-query Arrow Up/Down
  navigation, single-select Tab transition for the built-in `context-files`
  profile, return, copy, open, command, source cancellation, preview
  cancellation, result-command cancellation, optional physical keyboard input
  through `CGEvent`, and cancel behavior.
- `test-visual-internal.sh`: permission-free visual gate. It launches the real
  resident app in forced light and dark appearances, opens the same picker in
  each run, captures app-rendered internal snapshots, and verifies nonblank
  pixels, nonflat luminance, focused query input, preview content, no layout
  violations, and light/dark luminance separation.
- `test-visual.sh`: external macOS screenshot check. It launches the app in
  forced light and dark appearances, captures the real panel window with
  `screencapture`, samples PNG pixels with `visual-metrics.swift`, and skips by
  default if Screen Recording permission blocks capture. Set
  `FZF_PALETTE_REQUIRE_EXTERNAL_VISUAL=1` to make this a hard gate.
- `bench.sh smoke`: fast performance gate for routine changes.
- `bench.sh full`: larger performance suite for releases and performance work.
- `bench.sh soak`: release-scale lifecycle soak, running 500 measured
  panel/source/preview cancellation cycles with RSS and leaked-process gates.
- `test-all.sh`: unit, integration, UI, live app E2E, mandatory internal
  light/dark visual snapshots, external visual screenshot attempt, install, and
  smoke performance gates.

Use `test-quiet.sh` while actively using the laptop for other work. It is not a
substitute for `test-all.sh` because it does not verify focus, hotkey,
app-backed preview, app-backed result delivery, live visual rendering, install,
or performance gates.

Smoke performance should be practical before commits. Full performance can take
longer, but it must be easy to run locally and should emit machine-readable
JSON.

Test-control hooks are acceptable only when explicitly gated by the app process
environment. They should never be enabled by default in normal user launches.

Current implementation status:

- `swift test` covers core protocol, row formatting, option classification,
  command runner behavior, source streaming, preview placeholder expansion,
  process-tree cancellation, native fuzzy engine behavior, native engine
  benchmarks, extended-query parsing, smart-case parsing, ANSI stripping,
  rich SGR row span parsing, terminal-control ANSI parsing including
  insert/delete-line and simple scroll controls, `--tiebreak=chunk`,
  `--tiebreak=begin`, `--tiebreak=end`, ordered tiebreak lists,
  `--tiebreak=index`, `+s`/`--no-sort`, `--scheme=path`, `--scheme=history`,
  `FZF_DEFAULT_OPTS` parsing and
  option-file merging, `FZF_DEFAULT_COMMAND`/`FZF_CTRL_T_COMMAND` source
  resolution, multi-select source-order selection, multi-select result joining
  across newline, space, NUL, and JSON modes, engine-owned multi-select state,
  deferred match-range computation for native panel rendering,
  program-context app classification, Codex/Claude bridge-file resolution,
  Ghostty/tmux cwd resolution,
  launch-time hotkey binding
  parsing, and initial `fzf --filter` oracle parity.
- `scripts/bench.sh smoke` launches the resident app and verifies the app-backed
  panel, direct hotkey, Carbon event hotkey, native-panel 10,000-row
  keystroke, native-panel 100,000-row large-keystroke, main-thread query task,
  source-command, preview, preview-enabled selection movement, result-delivery,
  lifecycle cleanup, and CLI roundtrip benchmarks in addition to the local
  native engine benchmark.
- `scripts/test-quiet.sh` covers the no-popup subset for routine logic edits:
  unit tests, integration tests, and lightweight UI support tests. It
  intentionally avoids live app E2E, visual, install, and benchmark gates.
- `scripts/test-install.sh` verifies app bundle installation and LaunchAgent
  plist generation/removal in temporary directories, including generated app icon
  metadata and the optional `FZF_PALETTE_HOTKEY` and
  `FZF_PALETTE_HOTKEY_PROFILE` LaunchAgent environment values.
- `scripts/test-e2e.sh` launches the resident app with test controls enabled and
  a custom `FZF_PALETTE_HOTKEY`, `FZF_PALETTE_HOTKEY_PROFILE`, and a JSON-defined
  profile hotkey. It also uses an isolated `FZF_PALETTE_USER_DEFAULTS_SUITE` to
  verify `settings get`, `settings set`, a settings-defined hotkey, settings
  window show/close status, and settings clear. It verifies normalized bindings
  and Carbon registration state through `status --json`, verifies direct and
  lower-level Carbon event hotkey panel show for the mapped default binding,
  settings binding, a simulated Codex frontmost-app bridge context, and a
  profile-specific JSON binding, app-internal visual
  snapshot metrics for nonblank pixels, focused
  query input, preview pane visibility, stable panel size, styling, and basic
  layout violations, `FZF_DEFAULT_OPTS` merge behavior with `+m` override of
  default multi-select, `FZF_DEFAULT_COMMAND` and `FZF_CTRL_T_COMMAND` profile
  source resolution, built-in `repos`, `downloads`, and `context-files`
  workflows against an isolated temp `$HOME`, app-backed panel benchmark, native
  `--prompt`/`--header`/`--pointer`/`--marker` and `--info=inline` chrome,
  JSON-configured profile source/display/preview/result behavior, accept,
  initial query filtering, case-sensitive `+i` filtering,
  ANSI-stripped `--ansi` output, `--tiebreak=index` source-order ties, ordered
  `--tiebreak=begin,end` ranking, `--tiebreak=chunk` ranking, `--no-sort`
  source-order filtering, `--scheme=path` path ranking, `--scheme=history`
  score-only tie ordering, hidden result fields, multi-select
  select-all/deselect-all/toggle, hidden-field multi-select output for space and
  JSON joins, copy mode, side-effect-safe paste mode through
  `FZF_PALETTE_PASTE_LOG`, side-effect-safe open mode through
  `FZF_PALETTE_OPEN_LOG`, command mode, preview updates after
  cursor movement and query filtering, focused-query Arrow Up/Down selection
  movement, the built-in `context-files` `ava<Tab>` then `gohan` transition
  with idle pauses after both typed queries to catch unintended panel hiding,
  rich SGR preview ANSI rendering without raw escape leakage, terminal-control
  preview rendering to final visible screen state, insert/delete-line and simple
  scroll-control preview rendering, preview toggling, native right/up
  preview-window layout and wrap snapshot assertions, preview-window
  scroll-expression assertions, source child
  cleanup, preview child cleanup, result-command child cleanup, and
  cancel.
- `fzf-palette bench lifecycle --json` covers repeated panel show/hide, source
  cancellation, preview cancellation, RSS growth, and marker-tagged
  child-process leak detection.
- `scripts/bench.sh soak` covers the same lifecycle checks at release scale:
  500 measured cycles plus 10 warmup cycles.
- Paste mode is covered in live E2E through the gated `FZF_PALETTE_PASTE_LOG`
  app environment so tests do not send Cmd-V to another app. The production path
  writes to the pasteboard, restores the captured frontmost app, checks
  Accessibility permission, and reports `paste_failed` for permission or focus
  restoration failures.
- `open` mode is covered in live E2E through the gated `FZF_PALETTE_OPEN_LOG`
  app environment so tests do not launch external apps.
- Visual snapshot mode is app-internal and permission-free: it renders the real
  panel content view into a bitmap, samples pixels, luminance, effective
  appearance, and layout frames, and asserts native vibrant/rounded panel
  styling plus custom row-selection styling.
- Internal light/dark visual coverage exists in `scripts/test-visual-internal.sh`
  and is mandatory in `scripts/test-all.sh`.
- External visual screenshot coverage exists in `scripts/test-visual.sh`: it
  captures the real macOS panel window in forced light and dark appearances,
  verifies nonblank/nonflat pixel metrics, and checks that light/dark screenshots
  are visually distinct. It skips by default when macOS denies Screen Recording;
  use `FZF_PALETTE_REQUIRE_EXTERNAL_VISUAL=1` on a permissioned machine to make
  it mandatory.
- Physical hotkey coverage exists as an opt-in local path:
  `fzf-palette test-control physical-hotkey [profile]` and
  `fzf-palette bench physical-hotkey --json`. `scripts/test-e2e.sh` attempts the
  test and skips it by default if macOS denies event posting; set
  `FZF_PALETTE_REQUIRE_PHYSICAL_HOTKEY=1` to make it a hard gate on a
  permissioned machine.
- Physical keyboard UI coverage exists as an opt-in local path:
  `fzf-palette test-control physical-type value` and
  `fzf-palette test-control physical-key key`. `scripts/test-e2e.sh` attempts a
  type-filter-return accept flow and skips it by default if macOS denies
  Accessibility permission; set `FZF_PALETTE_REQUIRE_PHYSICAL_UI=1` to make it a
  hard gate on a permissioned machine.

## CI And Local Policy

For normal development:

- Run unit and integration tests for logic changes.
- Run UI/E2E tests for any panel, focus, trigger, result, preview, or visual
  change.
- Run smoke benchmarks for any change touching startup, source commands, engine,
  rendering, preview, result delivery, metrics, or hotkey handling.
- Run full benchmarks before releases and before landing major architecture
  changes.

Flaky performance failures should be treated as evidence that the implementation
is too close to the budget. Add headroom or fix the source of the variance; do
not mark the latency gate as optional.

## Fixtures

Use a mix of committed small fixtures and generated large fixtures.

Committed fixtures:

- Small file lists.
- ANSI git rows.
- Ripgrep-style `file:line:column:text` rows.
- Tab-delimited rows with hidden fields.
- Query corpora.
- Profile examples.

Generated fixtures:

- Tiny: 100 rows.
- Medium: 10,000 rows.
- Large: 100,000 rows.
- Repeated prefixes.
- Long paths.
- Spaces in names.
- Nested directories.
- Ignored directory names such as `.git`, `node_modules`, and `.cache`.

Generated fixtures should be deterministic and created by scripts. Keep their
outputs out of git.

## Done Definition

A feature is complete only when:

- Functional behavior is covered by unit or integration tests.
- User-visible behavior is covered by UI/E2E tests when applicable.
- Performance-sensitive behavior has a benchmark or metric assertion.
- Unsupported behavior has explicit validation tests.
- All relevant tests pass from the documented scripts.
- Metrics output includes enough detail to diagnose regressions without reruns.
