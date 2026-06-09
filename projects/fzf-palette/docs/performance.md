# Performance Plan

Performance is one of the core product requirements for `fzf-palette`. The app
is not successful if it is merely prettier than terminal `fzf`; it has to feel
instant.

The hard requirements:

- From global hotkey keypress to an interactive panel: **200 ms maximum**.
- From each query keystroke to an adjusted visible result list: **50 ms
  maximum**.

The design targets:

- Hotkey keypress to interactive panel: **under 75 ms**.
- Query keystroke to adjusted visible result list: **about 10 ms or less**.

These are not aspirational notes. They are benchmark gates. If a change cannot
stay inside the hard maximums, it should not ship.

## Definitions

### Interactive Panel

The panel is interactive when all of these are true:

- The panel is visible on the active screen.
- The query field is first responder.
- Typed characters are accepted without waiting for source commands.
- The list area is visible, even if source rows are still streaming.
- The app can close the panel with Escape.

The panel does not need to have all source rows loaded to be interactive. It does
need to accept input immediately and update as rows arrive.

### Adjusted Visible Result List

A query keystroke has adjusted the list when:

- The query text has been applied to the engine.
- The visible rows reflect the newest query, or the UI explicitly shows that
  current results are pending.
- The main thread is not blocked.

For normal warm source sets, the visible rows should update for every keystroke.
For pathological source or preview cases, stale results are allowed only if the
UI remains responsive and clearly converges to the latest query. The hard 50 ms
budget still applies to the UI acknowledging the keystroke and starting the
latest filter work.

## Latency Budgets

Warm resident app, hotkey path:

| Metric | Hard max | Target | Notes |
| --- | ---: | ---: | --- |
| Physical hotkey event to app event received | 15 ms | 5 ms | Carbon/keyboard event dispatch. |
| App event received to panel ordered front | 60 ms | 25 ms | Preallocated panel, no source work. |
| App event received to query focused | 75 ms | 35 ms | Query field accepts input. |
| Physical hotkey event to interactive panel | 200 ms | 75 ms | Primary product gate. |
| Interactive panel to first rows, warm source | 100 ms | 35 ms | Rows may stream after panel is ready. |
| Selection accepted to panel hidden | 60 ms | 35 ms | No slow close animation. |
| Selection accepted to CLI stdout | 80 ms | 45 ms | Socket plus formatting. |

Per-keystroke filtering:

| Metric | Hard max | Target | Notes |
| --- | ---: | ---: | --- |
| Key down to query text painted | 16 ms | 8 ms | One frame at 60 Hz, ideally less. |
| Key down to engine request queued | 10 ms | 3 ms | Main-thread handoff. |
| Key down to visible rows updated, tiny fixture | 50 ms | 10 ms | 100 rows. |
| Key down to visible rows updated, medium fixture | 50 ms | 10 ms | 10,000 rows. |
| Key down to visible rows updated, large fixture | 50 ms | 20 ms | 100,000 rows; may require cancellation and snapshots. |
| Key down while preview is running | 50 ms | 10 ms | Preview must never block filtering. |

Cold app launch is not the main interaction, but it still matters:

| Metric | Hard max | Target | Notes |
| --- | ---: | ---: | --- |
| CLI launches app to socket ready | 1500 ms | 500 ms | Not the hotkey target. |
| Login auto-start to idle resident app | 3000 ms | 1500 ms | Should not block user workflows. |

## Measurement Rules

- Measure from user-facing events, not convenient internal boundaries.
- Report p50, p95, p99, and max.
- Hard maximums use max after warmup, not p95.
- Targets use p95 unless stated otherwise.
- Separate panel, source, engine, preview, render, and result-delivery costs.
- Record hardware model, macOS version, power state, app commit, and engine
  revision with every full benchmark.
- Do not hide slow runs by averaging them away.

For local benchmark gates, a single run over hard max after warmup is a failure.
If macOS scheduling noise makes that too flaky, the implementation is too close
to the edge and needs more headroom.

## Instrumentation

Add `os_signpost` markers and in-memory metric events for every invocation:

- `physical_hotkey_event`
- `hotkey_received`
- `frontmost_app_captured`
- `panel_order_front_begin`
- `panel_order_front_end`
- `query_focus_begin`
- `query_focus_end`
- `interactive_ready`
- `source_start_begin`
- `source_start_end`
- `first_source_row`
- `source_finished`
- `key_down`
- `query_text_painted`
- `engine_request_queued`
- `engine_query_begin`
- `engine_snapshot_received`
- `rows_render_begin`
- `rows_render_end`
- `preview_start_begin`
- `preview_first_output`
- `preview_rendered`
- `preview_cancelled`
- `selection_received`
- `result_delivery_begin`
- `result_delivery_end`
- `panel_closed`

The app should retain the last few hundred invocation and keystroke metrics in
memory. The CLI should expose them:

```bash
fzf-palette status --recent-metrics --json
```

Use monotonic time. In Swift, prefer `ContinuousClock` for app-local durations
and `os_signpost` for Instruments.

## Benchmark Commands

Initial benchmark surface:

```bash
fzf-palette bench panel --runs 500 --warmup 50 --json
fzf-palette bench hotkey --runs 300 --warmup 30 --json
fzf-palette bench carbon-hotkey --runs 300 --warmup 30 --json
fzf-palette bench source --runs 100 --warmup 10 --json
fzf-palette bench engine --runs 500 --warmup 50 --json
fzf-palette bench keystroke --runs 120 --warmup 20 --json
fzf-palette bench large-keystroke --runs 60 --warmup 10 --json
fzf-palette bench main-thread --runs 120 --warmup 20 --json
fzf-palette bench preview --runs 100 --warmup 10 --json
fzf-palette bench result --runs 300 --warmup 30 --json
fzf-palette bench lifecycle --runs 100 --warmup 10 --json
fzf-palette bench cli-roundtrip --runs 300 --warmup 30 --json
scripts/bench.sh soak
```

Current implementation status:

- `fzf-palette bench engine --json` runs in the CLI against
  `NativeFuzzySearchEngine` with 10,000 cached generated rows and enforces the
  50 ms max plus 10 ms p95 score/order query budget with lazy match-range
  resolution for the first visible rows, without UI rendering.
- `fzf-palette bench panel --json`, `fzf-palette bench hotkey --json`,
  `fzf-palette bench carbon-hotkey --json`, and
  `fzf-palette bench physical-hotkey --json` run against the resident app and
  enforce the 200 ms max plus 75 ms p95 panel/hotkey budget. The `hotkey`
  benchmark measures the app callback path. The `carbon-hotkey` benchmark posts a
  `kEventHotKeyPressed` Carbon event through the installed handler. The
  `physical-hotkey` benchmark posts a real `CGEvent` keyboard sequence through
  `.cghidEventTap` and is meant for permissioned local machines, not the default
  smoke gate.
- `fzf-palette bench keystroke --json` runs against the resident app and
  enforces the 50 ms max plus 10 ms p95 query/filter/table-reload budget on
  10,000 generated rows.
- `fzf-palette bench large-keystroke --json` runs against the resident app and
  enforces the 50 ms max plus 20 ms p95 query/filter/table-reload budget on
  100,000 generated rows.
- `fzf-palette bench main-thread --json` runs against the resident app and
  enforces a 16 ms hard max plus 10 ms p95 target for the synchronous
  main-thread query/filter/table-reload task on 10,000 generated rows.
- `fzf-palette bench source --json` runs against the resident app and enforces
  first-row and completion budgets for a generated 100-row no-PTY source
  command.
- `fzf-palette bench preview --json` runs against the resident app and enforces
  a 300 ms preview-render hard max, 250 ms preview-render p95 target, and the
  50 ms max plus 10 ms p95 query responsiveness budget while a slow preview
  command is running.
- `fzf-palette bench result --json` runs against the resident app and enforces
  the 80 ms max plus 45 ms p95 selection-to-result budget. It shows a native
  picker, accepts the active row through the normal completion handler, verifies
  hidden-field selected output, verifies the panel was hidden, and measures the
  app-side time from accept to completed result response.
- `fzf-palette bench lifecycle --json` runs against the resident app and
  repeatedly shows/hides the panel, starts and cancels marker-tagged source and
  preview subprocesses, measures app RSS growth, and enforces zero leaked
  marker-tagged child processes.
- `scripts/bench.sh soak` is the release-scale lifecycle profile. It builds and
  launches the resident app, then runs
  `fzf-palette bench lifecycle --runs 500 --warmup 10 --json` with the same
  cycle-latency, RSS-growth, and leaked-process failure gates.
  The lifecycle loop explicitly drains per-cycle autorelease pools so the 500
  cycle run measures retained memory growth rather than temporary objects held
  until the benchmark request finishes.
- `fzf-palette bench cli-roundtrip --json` runs in the CLI and enforces the
  socket request/response roundtrip budget.
- `fzf-palette bench --json` defaults to the native engine benchmark.
- Launch-time hotkey configuration, the lower-level Carbon event handler path,
  the opt-in `CGEvent` physical hotkey path, opt-in physical keyboard UI input,
  and main-thread query task stalls are covered by status/E2E/benchmark checks,
  but the mandatory default physical-keydown/input gate remains
  permission/signing-gated.
- Permission-free app-internal visual snapshots are covered by live E2E for
  nonblank rendering, focused query input, preview pane width, stable panel size,
  and basic layout violation checks.
- `scripts/test-visual-internal.sh` is a mandatory permission-free light/dark
  visual gate. It launches the real app twice with forced appearances, samples
  the app-rendered internal bitmap for nonblank/nonflat content and luminance,
  and checks light/dark separation without using Screen Recording.
- External OS-level screenshot checks are covered by `scripts/test-visual.sh`.
  It launches the real app in forced light and dark appearances, captures the
  panel with `screencapture`, and samples PNG pixels for size, nonblank/nonflat
  content, and light/dark luminance separation. The default gate skips if macOS
  denies Screen Recording permission; set `FZF_PALETTE_REQUIRE_EXTERNAL_VISUAL=1`
  to require it on a permissioned machine.
- Source and preview cancellation are covered by the live E2E script, including
  cleanup of child processes launched by shell commands.
- Result command delivery is covered by the live E2E script. The dedicated
  `result` benchmark covers app-side selection-to-return-result latency;
  command-mode subprocess latency remains covered by E2E correctness and
  lifecycle cleanup, not by a separate performance budget.
- The current keystroke benchmark directly drives the native panel query path,
  but it is still synthetic: it sets the query string in-process rather than
  measuring physical keydown to paint via the macOS event system.

Benchmark types:

- `panel`: show/hide preallocated panel without running a source command.
- `hotkey`: app callback hotkey path to interactive panel.
- `carbon-hotkey`: Carbon `kEventHotKeyPressed` event handler path to
  interactive panel.
- `physical-hotkey`: CGEvent keyboard dispatch to interactive panel; requires
  Accessibility permission and is opt-in from `scripts/bench.sh`.
- `source`: start a profile source command and measure first row and completion.
- `engine`: query updates against cached generated fixture rows without UI
  rendering.
- `keystroke`: app-controlled query changes drive the focused native-panel
  query path and visible rows update.
- `main-thread`: synchronous main-thread query/filter/table-reload task duration
  during repeated query updates.
- `preview`: run preview commands and measure first output and render.
- `result`: selection accept to app result response through the normal panel
  completion path.
- `lifecycle`: repeated panel show/hide plus source and preview cancellation,
  with RSS growth and leaked-process checks.
- `cli-roundtrip`: CLI to socket to app to response without UI.

The benchmark split matters. Without separate panel, source, engine, preview,
lifecycle, and render metrics, a regression in one layer can be masked by noise
in another.

## Test Fixtures

Generated fixture directories live outside the repo:

```text
/tmp/fzf-palette-fixtures/
|-- tiny/      # 100 files
|-- medium/    # 10,000 files
`-- large/     # 100,000 files
```

Fixture generation should include:

- Short file names.
- Long file names.
- Nested directories.
- Spaces in names.
- Repeated prefixes.
- Common ignored directories: `.git`, `node_modules`, `.cache`.
- Git-style rows with ANSI color.
- Ripgrep-style `file:line:column:text` rows.
- Tab-delimited rows with hidden return fields.

Do not commit large generated fixtures. Commit only generators, small fixture
samples, and query corpora.

## Keystroke Test Corpus

Keystroke tests should replay realistic query sequences:

- File-name narrowing: `s`, `sr`, `src`, `src/`, `src/f`.
- Fuzzy jumps: `fp`, `fzp`, `fpl`.
- Extended terms: `'exact`, `^prefix`, `suffix$`, `!exclude`.
- Git branch names.
- Ripgrep line matches.
- Queries that produce no results.
- Backspace-heavy corrections.

For each sequence, measure every keypress individually. A fast average with one
100 ms hiccup is a failure.

## Preview Performance

Preview panes must never block query input or list updates.

Rules:

- Preview command launch is asynchronous.
- Cursor movement cancels stale previews.
- Only the newest preview may render.
- Preview output is size-limited.
- Preview rendering is budgeted separately from filtering.
- Slow preview commands show a pending state instead of freezing the list.

Preview benchmarks should cover:

```bash
git show --color=always {1}
~/bin/status-preview.sh {}
bat --color always --highlight-line {2} {1}
```

Hard gate:

- While a preview command is running, query keystrokes still update the query
  field and visible rows within 50 ms.

Longer-term target:

- Preview pane first useful output under 100 ms for normal local commands.

Current smoke gate:

- Shell-backed preview render p95 under 250 ms.
- Shell-backed preview render max under 300 ms.
- Query updates while a slow preview is running still meet the 50 ms max and
  10 ms p95 filtering budgets.

## Test Gates

The broader test strategy lives in `testing.md`. Performance gates are part of
that test suite, not a separate optional benchmark track.

Smoke mode should be fast enough to run before commits:

```bash
scripts/bench.sh smoke
```

Smoke gates:

- Hotkey to interactive panel max under 200 ms.
- Hotkey to interactive panel p95 under 75 ms.
- Keystroke to visible rows max under 50 ms on tiny and medium fixtures.
- Keystroke to visible rows p95 under 10 ms on tiny and medium fixtures.
- Main-thread query task max under 16 ms on tiny and medium fixtures.
- CLI roundtrip p95 under 80 ms.
- No blank panel frames after `panel_order_front_end`.
- No measured main-thread query task stalls over 16 ms during typing.

Current smoke implementation covers the native engine benchmark, app-backed
panel benchmark, direct hotkey benchmark, Carbon event hotkey benchmark,
app-backed native-panel 10,000-row and 100,000-row synthetic query-path
keystroke benchmarks, main-thread query task benchmark, app-backed source
benchmark, app-backed preview responsiveness benchmark, app-backed lifecycle
cleanup benchmark, and CLI roundtrip benchmark. An opt-in
physical hotkey benchmark exists for permissioned local machines through
`FZF_PALETTE_RUN_PHYSICAL_HOTKEY_BENCH=1 scripts/bench.sh smoke`; a mandatory
default OS-level physical-keydown gate still needs the signing/permission story.
Release-scale lifecycle coverage lives in the dedicated soak mode.

Full mode is for performance-sensitive changes and release points:

```bash
scripts/bench.sh full
```

Full gates:

- All smoke gates.
- Large fixture keystroke max under 50 ms.
- Large fixture keystroke p95 under 20 ms.
- Source benchmarks across tiny, medium, and large fixtures.
- Local compatibility profiles from `local-fzf-compatibility.md`.
- Preview responsiveness while moving quickly through results.
- Memory growth after 500 open/close cycles under an agreed threshold.
- No leaked source, preview, engine, shell, or helper processes.

## Visual Performance Checks

A fast popup that visually flashes, resizes, or shows a blank white panel is not
good enough. The current implementation has mandatory permission-free
app-internal snapshots plus an external screenshot script. Visual checks cover:

- Panel is visible within the hard budget.
- Query field is focused.
- Native rows are nonblank after first render when source rows exist.
- Native vibrant/rounded panel styling and custom rounded row selection are
  present in the app-internal snapshot.
- Match highlights are visible for direct display-text matches and visible
  field-projected `--nth` matches.
- No resize jump between panel show and first rows.
- Dark and light themes both have readable contrast through internal luminance
  checks, with OS-level screenshot confirmation available on permissioned
  machines.
- Long paths and multi-select output do not overflow critical chrome.
- Preview pane does not flash stale output after cursor movement.

The remaining visual work is to make the external screenshot path mandatory once
the signing/Screen Recording permission story is reliable.

## Regression Output

Benchmarks should emit JSON like:

```json
{
  "name": "keystroke-medium",
  "runs": 500,
  "warmup": 50,
  "budgets": {
    "hard_max_ms": 50,
    "target_p95_ms": 10
  },
  "metrics": {
    "key_to_query_painted_ms": {"p50": 3.1, "p95": 5.8, "p99": 8.4, "max": 10.2},
    "key_to_rows_rendered_ms": {"p50": 6.7, "p95": 9.6, "p99": 14.8, "max": 24.1}
  },
  "failures": []
}
```

Keep historical benchmark snapshots under an ignored local directory such as:

```text
projects/fzf-palette/.bench/
```

Only commit curated benchmark notes when they explain a design decision.

## Engineering Rules

- Keep the app resident.
- Preallocate the panel and native list view.
- Keep the query field and list rendering on a minimal main-thread path.
- Cache shell environment off the hot path.
- Keep the engine warm.
- Keep source rows in memory structures optimized for incremental filtering.
- Cancel stale engine and preview work aggressively.
- Render only visible rows plus overscan.
- Never run preview commands on the main thread.
- Avoid shell startup during invocation.
- Avoid Terminal.app, AppleScript, and external terminal emulators.
- Separate app latency from source, engine, preview, and filesystem latency in
  every benchmark.
- Treat blank-first-frame and keystroke-stall regressions as failures, even if
  aggregate latency looks acceptable.
