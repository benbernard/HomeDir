# Bootstrap And Machine Setup

The setup scripts in this repo are useful historical references, not a
guaranteed clean-room bootstrap system. Read them before running them.

## Main Files

- `bin/mac/setupMac.sh`: historical end-to-end Mac setup script.
- `bin/mac/brew-installs.sh`: Homebrew package install list.
- `bin/mac/installApps.sh`: application install helper.
- `bin/mac/setupDefaults.sh`: macOS defaults and preferences.
- `.gitmodules`: submodule list.
- `.mackup.cfg` and `.mackup/`: older Mackup config, probably rarely used.

## What `setupMac.sh` Tries To Do

At a high level, `bin/mac/setupMac.sh`:

1. Installs Xcode Command Line Tools.
2. Clones `HomeDir`.
3. Initializes submodules.
4. Installs Homebrew.
5. Runs Homebrew and app install scripts.
6. Configures Touch ID for sudo.
7. Applies macOS defaults.
8. Restores some iTerm/BetterTouchTool config from OneDrive.
9. Installs fonts and fzf.
10. Sets the login shell.
11. Installs the MeetingBar event script symlink.
12. Runs interactive setup for p10k, GitHub auth, and Copilot.

## Known Rot And Sharp Edges

Treat the script as stale until proven otherwise. Obvious risks:

- It assumes a fresh clone flow that may not match the current checked-out home
  directory.
- It references OneDrive backup paths that may not exist.
- It has machine/user path assumptions.
- It includes a likely typo: `instalApps.sh` versus `installApps.sh`.
- It uses old manual post-install instructions for apps and browser profiles.
- It changes system files and login shell state.

Do not run it blindly from an agent session.

## Submodules

Submodules include shell/editor/tooling dependencies such as Oh My Zsh, fzf,
fonts, fast syntax highlighting, tmux plugins, and personal helper repos.

Useful commands:

```bash
git submodule status
git submodule update --init --recursive
```

Avoid broad searches inside submodules unless the task targets one directly.

## New Machine Strategy

For a new setup, prefer a staged approach:

1. Clone this repo and inspect `git status`.
2. Initialize submodules.
3. Install Homebrew and core packages.
4. Install shell/editor dependencies.
5. Bring up zsh with minimal assumptions.
6. Restore app-specific configs manually.
7. Validate tmux, `bin/ts`, notifications, and URL routing separately.

This is slower than one giant script but much easier to debug.

## Agent Guidance

- Do not modify setup scripts just to make docs look cleaner.
- If asked to repair bootstrap, first identify which parts are still desired.
- Keep job-specific values in `site/`, not in this repo.
- Document stale assumptions instead of silently preserving them.
