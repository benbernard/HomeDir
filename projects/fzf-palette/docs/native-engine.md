# Native Engine Plan

The preferred UI is native. To avoid building a weak imitation of `fzf`, the
native UI needs an engine that reuses or tracks the `fzf` behavior this home
directory actually depends on.

## Local fzf Source Facts

The checked-out source at `~/submodules/fzf` is a Go module:

```text
module github.com/junegunn/fzf
```

It is MIT licensed, so local reuse, modification, and vendoring are legally
plausible as long as the license notice is preserved.

Useful boundaries in the current source:

- `src/pattern.go`: query parsing and `BuildPattern`.
- `src/matcher.go`: parallel matching and ranking loop.
- `src/item.go`: item representation.
- `src/chunklist.go`: item chunk storage.
- `src/merger.go`: merged ranked results.
- `src/options.go`: option parsing.
- `src/core.go`: wires reader, matcher, and terminal together.
- `src/terminal.go`: terminal UI; this is the part the native app should avoid.

The source is not designed as a stable public library. Treat it as an internal
dependency that may need a maintained fork or a thin extraction layer. Do not
block the app on total upstream parity.

## Current First Engine

The project now has a first in-process Swift engine:

```text
Sources/FzfPaletteCore/NativeFuzzySearchEngine.swift
```

This is deliberately smaller than `fzf`. It exists to prove the native panel,
source streaming, and keystroke latency path before taking on full parser and
ranking compatibility.

Current behavior:

- Owns `PaletteRow` storage for the active source.
- Caches normalized UTF-8 row bytes on `replaceRows` and `appendRows`.
- Preserves source order for an empty query.
- Supports simple fuzzy matching with stable source-index tiebreaking.
- Parses the first supported extended-search subset: exact `'term`, prefix
  `^term`, suffix `term$`, inverse `!term`/`!^term`/`!term$`, and standalone
  `|` OR clauses.
- Treats backslash-escaped whitespace as literal query text, matching fzf's
  `hello\ world` style.
- Supports smart-case, case-insensitive, and case-sensitive modes.
- Runtime panel requests now use smart-case by default and route `-i` and `+i`
  to explicit case modes.
- Supports `--exact`/`-e` exact-match mode, plus `+e`/`--no-exact` to return to
  fuzzy mode. In exact mode, a leading quote unquotes the term back to fuzzy
  matching, matching fzf behavior.
- Uses ANSI-stripped display text for `--ansi` matching and selected output.
- Carries SGR style spans for native result row rendering while preserving
  stripped search/output semantics. Supported styles include named
  foreground/background colors, xterm-256 colors, truecolor, bold, dim, italic,
  underline, and strikethrough.
- Interprets common terminal-control output in ANSI parsing, including carriage
  return, backspace, tab stops, cursor movement, cursor next/previous line,
  absolute horizontal/vertical cursor positioning, clear-line, clear-screen,
  insert/delete line, and simple whole-buffer scroll up/down sequences, so
  preview commands that repaint progress/status output render their final
  visible screen state.
- Tracks original, display, and search text separately so `--nth` search scope
  can differ from `--with-nth` presentation and selected output.
- Supports `--nth`/`-n` field expressions for scoped matching, including open
  ranges and negative indexes.
- Sorts equal scores by fzf-like length by default, with explicit
  `--tiebreak=chunk`, `--tiebreak=begin`, `--tiebreak=end`, ordered
  chunk/begin/end/index lists, and `--tiebreak=index` support for source-order
  ties.
- Honors `+s`/`--no-sort` by preserving source order for non-empty filtered
  queries while still returning match ranges.
- Supports `--scheme=default` and a first `--scheme=path` subset that biases
  ranking toward basename matches for file/path pickers.
- Supports a first `--scheme=history` subset by matching fzf's score-only
  ordering behavior for tied scores, including fzf's behavior of ignoring
  explicit `--tiebreak` criteria in history mode.
- Owns multi-select state by source index, with toggle, select-visible,
  deselect-all, accepted-row fallback, and source-order selected-row output.
- Returns scored matches with original row indexes and byte ranges for native
  match highlighting when parity callers need full ranges.
- Can run score-only broad filtering for the native panel and compute match
  ranges lazily for visible rows, avoiding per-candidate highlight allocation on
  large result sets.
- Projects search ranges onto display ranges for visible `--nth`/`--with-nth`
  field combinations.
- Sorts lightweight index/score candidates before materializing `PaletteRow`
  results on the panel path, which keeps broad-match query sorting out of the
  keystroke budget danger zone.
- Backs the native panel and the legacy `SimpleMatcher` wrapper so tests hit one
  implementation.

Current limits:

- `--scheme=history` and `--scheme=path` are targeted local subsets rather than
  full upstream scoring clones.
- Matches in fields omitted from `--with-nth` intentionally have no visible
  highlight target.
- No full interactive terminal-screen emulator yet. The native renderer handles
  common final-screen terminal controls, but not terminal input, alternate-screen
  applications, scroll regions, or complex terminal modes.
- It is a useful first engine, not the final parity story.

## Current Engine Decision

Keep `NativeFuzzySearchEngine` as the product engine for now. The Swift engine is
already under the 10 ms p95 query target on the 10,000-row benchmark and has
parity tests for the local subset implemented so far. Adding a resident Go
helper today would add process/protocol/build complexity before the project has
evidence that Swift is the bottleneck.

Revisit the Go helper or maintained `fzf` fork only when one of these triggers is
true:

- A local profile needs `fzf` behavior that is expensive or risky to reproduce in
  Swift.
- A supported query/ranking feature cannot pass parity tests against
  `fzf --filter` without copying a large amount of upstream logic.
- `NativeFuzzySearchEngine` or native panel keystroke p95 exceeds the 10 ms
  target on representative local workloads after straightforward optimization.
- Multi-select or option semantics move from app-level state into engine-level
  state and become materially easier to keep correct by reusing upstream code.

The direct benchmark is:

```bash
fzf-palette bench engine --runs 100 --warmup 10 --json
```

It measures repeated score/order queries over 10,000 cached rows plus lazy
match-range resolution for the first visible rows, enforcing the 50 ms hard max
plus 10 ms p95 target. Full all-match range materialization remains covered by
correctness and parity tests rather than used as the typing-latency proxy. The
native panel keystroke benchmark still matters separately because UI reload cost
can regress independently from engine cost.

## Engine Options

### Option A: Go Engine Helper

Build `engine/cmd/fzf-palette-engine`, a resident helper process that imports
`github.com/junegunn/fzf/src` from the local submodule or a vendored fork.

Swift sends source items and query changes to the helper. The helper returns
ranked result snapshots, selected item text, match positions, and counts.
Source commands and preview commands remain app/profile concerns.

Pros:

- Fastest path to native UI without porting algorithms to Swift.
- Can use `fzf` parser, matcher, scoring, and option handling directly.
- Easy to compare against real `fzf --filter`.

Cons:

- Depends on `fzf` internal APIs.
- Requires a Go build in addition to Swift.
- Needs a protocol between Swift and the engine.

This is the preferred fallback if the Swift engine starts accumulating too much
duplicated `fzf` behavior or misses the latency budget on representative local
workloads.

### Option B: Maintained fzf Fork With Library API

Fork `fzf` or vendor a copy and expose a small library API:

- Parse options.
- Configure source.
- Update query.
- Return ranked results.
- Apply selection movement and multi-select operations.

Pros:

- Cleaner long-term API.
- Keeps behavior closer to upstream than a Swift rewrite.
- Lets us modify internals for incremental/native use.

Cons:

- Higher maintenance burden.
- Needs a strategy for pulling upstream `fzf` changes.

Use this if Option A proves too fragile.

### Option C: Swift Port

Port the matching/parser/ranking core to Swift.

Pros:

- Single-language app.
- No helper process.
- Native memory and concurrency model.

Cons:

- Highest parity risk.
- Slowest path to useful behavior.
- Requires a large test corpus before it can be trusted.

The current `NativeFuzzySearchEngine` is a narrow version of this option. Keep
extending it while local parity remains testable and the 10 ms p95 keystroke
target holds; switch to the Go helper or maintained fork path only when one of
the decision triggers above fires.

## Engine Protocol Sketch

Use one long-lived engine process. Start with newline-delimited JSON; optimize
later only if benchmarks say it matters.

Requests:

```json
{"type":"configure","profile":"default","options":["--multi"]}
{"type":"startSource","sourceId":"files"}
{"type":"appendItems","items":["a.txt","b.txt"]}
{"type":"sourceFinished","sourceId":"files"}
{"type":"setQuery","query":"foo"}
{"type":"move","delta":1}
{"type":"selectAll"}
{"type":"deselectAll"}
{"type":"toggleSelect"}
{"type":"accept"}
{"type":"cancel"}
```

Responses:

```json
{
  "type": "snapshot",
  "query": "foo",
  "total": 10000,
  "matched": 42,
  "cursor": 0,
  "items": [
    {"index": 15, "text": "foo.txt", "score": 123, "positions": [[0, 3]]}
  ]
}
```

Keep snapshots bounded to the visible range plus overscan. The engine should not
send 100,000 rows to Swift on every keystroke.

## Compatibility Tests

Every supported native engine feature needs a compatibility test against real
`fzf` or against an expected local behavior. The goal is the local subset, not
all upstream options.

Initial corpus:

- Current first-engine cases: empty query source order, contiguous ranking,
  incremental row append, case-sensitive matching, and smart-case matching.
- Plain fuzzy query.
- Extended terms.
- Exact terms.
- Prefix and suffix terms.
- Inverse terms.
- Case-sensitive and smart-case behavior.
- Match range output for fuzzy and exact terms.
- Search-to-display highlight range projection.
- Multi-select output order.
- `--nth` and delimiter behavior.
- ANSI-stripped input and selected output.
- `--tiebreak=chunk`, `--tiebreak=begin`, `--tiebreak=end`, ordered tiebreak
  lists, and `--tiebreak=index`.
- `--scheme=path` for the supported local path-ranking fixture.
- `--scheme=history` score-only ordering for tied scores, including explicit
  tiebreak override behavior.
- Local default binds for select-all and deselect-all.

Test method:

1. Generate fixture input.
2. Run real `fzf --filter <query>` with specific options.
3. Run the engine with the same input/query/options.
4. Compare output ordering and selected text.

Do not compare only counts. Ordering and selected output are the product.

Unsupported upstream options should get validation tests too. The expected
behavior is a clear error.

## Preview Handling

Preview is part of the local `fzf` feel and should be first-class in native UI.

Native preview path:

- Run preview commands as subprocesses.
- Debounce query/cursor changes.
- Kill stale preview processes.
- Render text output in a native scroll view.
- Interpret common noninteractive terminal controls into a final visible screen
  state, including cursor movement, clearing, insert/delete-line, and simple
  whole-buffer scroll up/down.
- Use `bat` when profiles ask for file previews.
- Support field placeholders such as `{}`, `{1}`, and `{2}`.
- Provide `$LINES` based on preview-pane height.

Preview behavior that genuinely requires terminal input, alternate-screen state,
scroll regions, or complex terminal modes is out of scope until there is a
native design for it.

## Upstream Strategy

Do not casually edit `~/submodules/fzf` in place for this app. First build the
engine as a local module that imports or vendors a known fzf revision. If we
need modifications, make them in `projects/fzf-palette/engine/vendor` or a
dedicated fork path, then document the upstream commit and local patch set.

The app should expose the engine/fzf revision in:

```bash
fzf-palette status --json
```
