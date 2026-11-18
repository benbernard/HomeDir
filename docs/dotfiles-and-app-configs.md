# Dotfiles and App Configs

This home directory is itself a git repository. Treat tracked config as real
source, but assume `repos/` and `site/` are separate workspaces. Use
`git ls-files` for inventory and targeted reads for evidence; do not recursively
search `repos/`, `bin/ts/node_modules/`, or other dependency trees.

## Shell

- Primary shell: zsh.
- Entry point: `.zshrc`, which sources every `.zshrc.d/*.zsh` file in sorted
  order.
- Edit modular shell behavior in `.zshrc.d/`, not directly in `.zshrc`, unless
  the startup framework itself is changing.
- `.zshrc.d/02_environment.zsh` owns core environment and PATH setup, including
  `~/bin`, `~/bin/ts/bin`, submodule tools, ripgrep config, fzf defaults, and
  language-manager paths.
- `.zshrc.d/02_aliases.zsh` and `.zshrc.d/02_functions.zsh` contain the broad
  interactive surface.
- `.zshrc.d/05_ic.zsh` wraps the TypeScript `ic` command so it can emit and
  source shell integration scripts.
- `.zshrc.d/99_site.zsh` conditionally sources `~/site/site.zsh` and appends
  `~/site/bin`; `site/` is a separate repo and may be job-specific.

Startup performance is an explicit concern. Homebrew, pyenv, and rbenv are
loaded from cached shell snippets when present. If adding shell startup work,
prefer lazy or cached setup.

## Terminal and Tmux

- Current terminal/tmux stack is Ghostty plus two-layer tmux.
- Main docs: `docs/tmux-setup.md`.
- Config files:
  - `.config/ghostty/config`: key sequences for nested tmux and Cmd-C handling.
  - `.tmux.shared.conf`: shared tmux settings, prefix `C-x`, copy behavior,
    plugins, and common styling.
  - `.tmux.conf`: outer tmux config, green accent, `C-o` sends prefix to nested
    tmux, outer file pickers.
  - `.tmux.nested.conf`: nested tmux config on socket `nested`, blue accent,
    `C-M-S-Arrow` window movement.
- Supporting scripts include `bin/tmux-swap-or-move-window`,
  `bin/tmux-resolve-pane-path`, `bin/tmux-sub-session-window.sh`, and TypeScript
  utilities `tmux-fzf-picker` and `tmux-health-check`.

Screen-era files still exist but are legacy/rarely-used; see
`docs/legacy-systems-index.md`.

## Git

- `.gitconfig` is the main tracked config; `.gitconfig.global` appears older.
- Defaults include `push.default=current`, `fetch.prune=true`,
  `branch.autosetuprebase=always`, `init.defaultBranch=main`, disabled auto-gc,
  `credential.helper=osxkeychain`, and GitHub HTTPS-to-SSH URL rewrites.
- `.config/git/ignore` and `.gitignore_global` hold ignores.
- Be careful with identity and work-specific settings. `.gitconfig` contains
  personal and work email entries; do not add secrets or internal-only URLs.

## Editors

- Neovim is primary. `.config/nvim/init.vim` uses vim-plug and then sources
  `.eihooks/dotfiles/vimrc` for older shared Vim behavior.
- VS Code Neovim uses `.config/nvim/vscode-init.vim`, which also sources
  `.eihooks/dotfiles/vimrc`.
- Classic Vim config remains in `.vimrc` and `.vim/`; it also uses the eihooks
  Vim base.
- `.ideavimrc` sources `.config/nvim/init.vim` and enables IdeaVim features.

The `.eihooks` tree is partly active because editor configs source its Vim base,
but much of the tree is old Screen-era material. Keep changes narrow.

## TypeScript Utilities

- Project root: `bin/ts/`.
- Source: `bin/ts/src/`.
- Manifest: `bin/ts/src/manifest.ts`.
- Build system: Bun compiles standalone executables into untracked `dist/` and
  generates untracked wrapper scripts in `bin/`.
- `bin/ts/bin/` is on PATH via `.zshrc.d/01_bin_ts.zsh`.
- Main documented commands include `ic`, `notifyctl`, `codex-notify`,
  `claude-notify`, `meeting-notify`, `tmux-fzf-picker`, `tmux-health-check`,
  `git-cleanup`, `git-prune-old`, `read-tree`, and `ben-scripts`.

When adding a script, create source in `bin/ts/src/`, add a manifest entry, and
build from `bin/ts/`. Do not manually create generated wrappers or `dist/`
artifacts.

## Notifications and Meeting Tools

- Full architecture: `docs/meeting-notification-architecture.md`.
- MeetingBar calls tracked AppleScript `bin/eventStartScript.scpt`, which passes
  event data to `bin/ts/bin/meeting-notify`.
- `meeting-notify` orchestrates the Swift overlay and native notification path.
- Overlay source: `bin/meeting-overlay.swift`; build helper:
  `bin/build-meeting-overlay`.
- Native notification source: `notifications/manifest.json`,
  `notifications/runtime/NotifyAgent.swift`, and TypeScript CLI `notifyctl`.
- Runtime app bundles are generated outside this repo under
  `~/Applications/NotificationApps/`.

## macOS App and Browser Routing Config

- `.finicky.js` is active browser-routing config. It routes Slack deep links,
  meeting links to a dedicated meeting app target, work domains to a work Chrome
  profile, and personal domains to a home Chrome profile.
- `.config/ghostty/config` is part of the active terminal/tmux workflow.
- `.config/btt/Default.bttpreset` and `.config/btt/Default.json` are tracked
  BetterTouchTool config exports.
- `.iterm2/com.googlecode.iterm2.plist`, `.iterm2_shell_integration.zsh`, and
  `Library/Application Support/iTerm2/parsers/*` are tracked but appear secondary
  to Ghostty in the current tmux docs.
- `Automate/*.workflow` contains tracked macOS Automator workflows for OneDrive
  sharing.
- `userScripts/` contains browser userscripts/extensions; see
  `userScripts/README.md`.

### Mouse thumb grid → BetterTouchTool

The [Karabiner rule](../.config/karabiner/assets/complex_modifications/btt-mouse-grid.js)
turns the mouse's thumb keys into **Normal Mouse Buttons** in BTT. Change what a
button *does* in BTT; change which mice send those buttons in the rule. It matches
only the listed mouse's keyboard interface, so the real keyboard still types digits.

| Thumb key | BTT button | Karabiner button |
| --- | --- | --- |
| `1` … `9` | 10 … 18 | 11 … 19 |
| `0` | 19 | 20 |
| `−` | 20 | 21 |
| `=` / `+` | 21 | 22 |

**New Mac:** Install Karabiner-Elements (16.2+ for the `.js` rule) and BTT,
sync the dotfiles, and make sure your BTT preset is active. In Karabiner's
active profile, choose **Complex Modifications → Add predefined rule** and enable
**Mouse thumb grid to BTT Buttons 10–21**. No need to copy `karabiner.json` from
another Mac or recreate the twelve bindings.

**Replacement mouse:** The same vendor/product IDs work without changes, even
in a different USB port. For a new model that sends digits and `−`/`+`, find its
keyboard interface in **Karabiner-EventViewer → Devices** and add its vendor and
product IDs to `mice` in the shared rule. Keep `is_keyboard: true`. Karabiner
copies the rule into the active profile when enabled: after syncing an edit,
remove the old copy in Complex Modifications and add the predefined rule again.

**Quick check:** In BTT's button recorder, thumb `8` should register as **Button
17**, and holding ⌘ should register **⌘ + Button 17**. In a text field, keyboard
`8` should still type `8`. If the *mouse* types `8`, check that its keyboard
interface has **Modify events** enabled in Karabiner's Devices tab. To undo the
mapping, disable the rule in Complex Modifications; leave the BTT actions intact.

## Small App Projects

- `projects/` contains standalone local project/app source, including
  `projects/RecordStream`, `projects/BOWQuotes`, `projects/commentTracker`, and
  `projects/SpeedyMeet`.
- `todo-tracker/` is a tracked Electron-style local todo app.
- `notifications/` is source for native notification apps, not the built apps.

Do not add new docs for the old meeting Electron app in this repo. That work is
moving elsewhere, and only local URL-routing hooks should be documented here.

## Legacy or Rarely Used

Mackup and Hammerspoon are explicitly considered legacy/rarely-used for current
agent work. Old Screen, Ratpoison, Irssi, and most eihooks-era terminal glue
should also be treated as legacy unless a current tracked file proves otherwise.
See `docs/legacy-systems-index.md` before changing those areas.
