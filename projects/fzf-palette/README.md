# fzf-palette

Native macOS palette app for fast, hotkey-triggered `fzf` workflows.

Keep this project under `projects/` because it is a standalone app, not a
single `bin/ts` utility. Generated app bundles should live outside the repo.

## Common Commands

```bash
scripts/test-quiet.sh   # no-popup unit/integration/UI-support checks
scripts/test-all.sh     # full local gate; opens the real AppKit panel
scripts/bench.sh smoke  # app-backed performance smoke gate
```

## Docs

- `docs/architecture.md`: app structure, key technical decisions, and non-goals.
- `docs/native-engine.md`: current Swift fuzzy engine and future `fzf` parity
  engine plan.
- `docs/profiles.md`: configurable picker profiles and starting commands.
- `docs/local-fzf-compatibility.md`: `fzf` features used in this home directory.
- `docs/trigger-protocol.md`: hotkey, CLI, URL, and socket trigger contract.
- `docs/performance.md`: startup targets, instrumentation, and benchmark plan.
- `docs/testing.md`: required unit, integration, UI/E2E, and performance tests.
- `docs/install.md`: app bundle installation and per-user LaunchAgent setup.
- `docs/current-status.md`: implemented pieces, verified commands, and gaps.
- `docs/implementation-plan.md`: phased build plan.
