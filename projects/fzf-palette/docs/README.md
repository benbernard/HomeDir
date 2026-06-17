# fzf-palette Docs

`fzf-palette` is a native macOS app that makes `fzf`-style selection available
from a fast, beautiful GUI popup. The preferred product is a native AppKit list
UI backed by an `fzf`-compatible matching engine. It should support the `fzf`
features actually used in this home directory, not every upstream option.

The hard constraint is usefulness, not total parity. A pretty native list that
cannot run custom source commands, show previews, or preserve familiar matching
behavior is not enough. A native app that supports the local picker patterns
well is better than a terminal-shaped clone that supports every edge case.

## Document Map

- `architecture.md`: product requirements, app structure, and implementation
  decisions.
- `native-engine.md`: current Swift fuzzy engine and future `fzf` parity engine
  options.
- `profiles.md`: configurable picker profiles, including arbitrary starting
  commands.
- `local-fzf-compatibility.md`: the local `fzf` defaults and call sites this app
  should support first.
- `trigger-protocol.md`: how hotkeys, scripts, URL events, and result delivery
  should work, including program-context detection for Codex, Claude, and
  Ghostty/tmux.
- `performance.md`: latency budgets, instrumentation, and benchmark harness.
- `testing.md`: the required unit, integration, UI/E2E, and performance test
  plan.
- `install.md`: app bundle installation and per-user LaunchAgent setup.
- `current-status.md`: what exists now, what has been verified, and what is
  still missing.
- `implementation-plan.md`: phased plan for building the app.

## North Star

Press a hotkey and see an already-warm palette immediately. Type without waiting.
Select an item and get the result back into the triggering context with as little
ceremony as possible.
