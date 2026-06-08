# Home Directory Map

This repository is the source-controlled portion of `/Users/benbernard`. It is
not a normal single-purpose application repo. It contains shell startup files,
dotfiles, personal scripts, standalone projects, small apps, submodules, and a
few active local systems.

For agent work, start with this map, then follow the subsystem docs linked from
the relevant section.

## Source Control Boundaries

The home directory itself is a git repository. Use `git status --short --branch`
from `/Users/benbernard` before editing so you can see user-owned changes.

Tracked here:

- Root dotfiles such as `.zshrc`, `.gitconfig`, `.tmux.conf`, `.finicky.js`.
- Most of `.config/`.
- Personal scripts in `bin/`.
- TypeScript utilities in `bin/ts/`.
- Native notification definitions in `notifications/`.
- Standalone local projects in `projects/`.
- Small local apps and browser scripts such as `todo-tracker/` and
  `userScripts/`.
- Submodule entries under `submodules/` and a few legacy submodule paths.

Not part of this repo:

- `repos/`: each child is normally its own independent repo.
- `site/`: a separate repo for job-specific configuration and overrides.
- Generated or dependency directories such as `bin/ts/node_modules/`,
  `bin/ts/dist/`, and `bin/ts/bin/`.

## Search Rules

Do not run broad recursive searches from the home directory. `repos/`,
`bin/ts/node_modules/`, and submodules can make generic searches painfully slow.

Preferred patterns:

```bash
git ls-files
git ls-files 'docs/*' 'bin/ts/src/*'
rg --files -g '!repos/**' -g '!**/node_modules/**'
rg 'pattern' $(git ls-files)
```

For TypeScript utilities, search `bin/ts/src/`, not all of `bin/ts/`.

## Main Areas

### Agent Instructions

- `AGENTS.md`: hard rules for agents in this home repo.
- `CLAUDE.md` and `CLAUDE.home.md`: older Claude-facing variants of the same
  repo guidance.
- `.claude/`: Claude Code settings, hooks, and limits.
- `.github/copilot-instructions.md`: currently appears to describe a different
  project workflow and should not be treated as authoritative for this repo.

Prefer putting durable explanations in `docs/` and keeping root agent files
short and directive.

### Shell Startup

- `.zshrc`: top-level interactive shell loader.
- `.zshenv`, `.zprofile`, `.profile`, `.bashrc`: login and compatibility files.
- `.zshrc.d/*.zsh`: modular zsh configuration loaded in sorted order.
- `site/`: may add shell overrides through `.zshrc.d/99_site.zsh`.

See `docs/shell-startup.md`.

### Tmux

- `.tmux.shared.conf`: shared tmux config.
- `.tmux.conf`: outer tmux config.
- `.tmux.nested.conf`: nested tmux config.
- `bin/tmux-*`: tmux helper scripts.
- `bin/ts/src/ic.ts`, `tmux-fzf-picker.ts`, `tmux-health-check.ts`: TypeScript
  helpers for nested tmux sessions and diagnostics.

See `docs/tmux-setup.md`.

### Scripts

`bin/` contains a mix of shell, Perl, AppleScript, Swift, JavaScript, and older
helper scripts. Some are active; some are historical. New utility scripts should
usually be written in `bin/ts/src/` instead of adding more one-off scripts.

`bin/ts/` is the active TypeScript CLI project. It builds Bun standalone
executables and generated wrapper scripts.

See `bin/ts/README.md` and `bin/ts/AGENTS.md`.

### Projects

`projects/` is for standalone personal projects and app source that belong in
the tracked home repository, but are larger than one-off scripts. Current
project-style submodules include `projects/RecordStream`,
`projects/BOWQuotes`, `projects/commentTracker`, and `projects/SpeedyMeet`.
New local app projects such as `fzf-palette` should also start here.

### Notifications And Meeting Alerts

- `notifications/`: manifest and Swift runtime for custom macOS notification
  apps.
- `bin/ts/src/notifyctl.ts`: build/send CLI for notification profiles.
- `bin/ts/src/meeting-notify.ts`: MeetingBar event orchestrator.
- `bin/meeting-overlay.swift`: full-screen meeting overlay.
- `bin/eventStartScript.scpt`: AppleScript bridge for MeetingBar.

See:

- `docs/meeting-notification-architecture.md`
- `docs/macos-notification-framework.md`
- `docs/meeting-notification-operations.md`

### URL Routing

- `.finicky.js`: macOS URL routing rules.
- `bin/openUrl` and `bin/perl/lib/UrlOpener.pm`: older URL opener path.
- `bin/openMeetAndUrl.mjs`: Google Meet app/browser helper.

See `docs/macos-url-routing.md`.

### Dotfiles And App Configs

Most app configuration lives in root dotfiles and `.config/`. Some files are
actively used, while many older editor, terminal, IRC, mail, screen, or window
manager configs are best treated as legacy unless the user says otherwise.

See:

- `docs/dotfiles-and-app-configs.md`
- `docs/legacy-systems-index.md`

### Machine Setup

`bin/mac/setupMac.sh` and related scripts document historical setup steps. Treat
them as a reference, not a known-good bootstrap flow.

See `docs/bootstrap-and-machine-setup.md`.

### Small Apps And Browser Scripts

- `todo-tracker/`: Electron todo JSON editor.
- `userScripts/`: Chrome user scripts and the PR Link Enhancer extension.
- `Automate/`: Automator workflows.

See `docs/browser-userscripts-and-small-apps.md`.

## Practical Rules For Future Agents

- Check git status first.
- Prefer `git ls-files` over broad filesystem walks.
- Do not touch `repos/` or `site/` unless the task explicitly targets them.
- Do not edit generated `bin/ts/bin/` or `bin/ts/dist/`.
- Be cautious with tracked config files: assume secrets and internal URLs can be
  nearby.
- For markdown-only docs changes, do not run TypeScript lints or typechecks
  unless asked.
