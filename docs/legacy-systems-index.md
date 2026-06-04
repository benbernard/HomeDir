# Legacy Systems Index

This index is for tracked systems that still exist in the home-directory repo
but should not be treated as the current default without fresh evidence. The
purpose is to keep future agents from "modernizing" old config accidentally or
building new work on stale assumptions.

Evidence here comes from tracked files only.

## Legacy / Rarely Used by Guidance

### Mackup

- Files: `.mackup.cfg`, `.mackup/cursor.cfg`.
- Current guidance: not really used; treat as legacy/rarely-used.
- Tracked config uses a file-system storage engine pointed at `OneDrive` and
  syncs only a small application list, with Cursor config in `.mackup/cursor.cfg`.
- `bin/mac/brew-installs.sh` still lists `mackup`, but that is install inventory,
  not evidence of active sync.

### Hammerspoon

- File: `.hammerspoon/init.lua`.
- Current guidance: not really used; treat as legacy/rarely-used.
- The config only binds Cmd-Ctrl-A/B to activate Amazon Music, send left/right
  keystrokes, and hide it again.

## Old Unix Desktop / Terminal Stack

### GNU Screen

- Files: `.screenrc`, `.screenrc.*`, `.eihooks/dotfiles/screen*`,
  `bin/screen-multiplex`, `bin/update-screen-copy`, `bin/process-scrollback-*`,
  and older startup scripts.
- Status: likely legacy. The current documented terminal stack is tmux, with
  active docs in `docs/tmux-setup.md`.
- Remaining live-ish references:
  - `.zshrc.d/02_aliases.zsh` aliases `screen` to `screen -x -RR`.
  - `.zshrc.d/02_environment.zsh` sets `SCREENDIR`.
  - `.zshrc.d/02_functions.zsh` still defines `nsc`, a nested Screen helper.
- Treat these as compatibility leftovers unless the user specifically asks for
  Screen behavior.

### Ratpoison

- Files: `.ratpoisonrc`, `.Xsession`, `bin/perl/lib/Ratpoison.pm`,
  `bin/rat_display_windows.pl`, `bin/arrange_windows.sh`, `bin/startup`,
  `bin/startup.sample`, and related window scripts.
- Status: likely legacy. `.Xsession` execs `ratpoison`, but the active macOS
  docs/configs point elsewhere: Ghostty, tmux, Finicky, notification apps, and
  MeetingBar-triggered notification workflows.
- Many paths inside these scripts are old Linux-style paths such as
  `/home/benbernard` and `/usr/local/bin/ratpoison`.

### Irssi / Old IRC

- Files: `.irssi/`, `.irclogs/archive.sh`, `.screenrc.irc`,
  `bin/growlNote.pl`, and `bin/startup` references to an IRC Screen session.
- Status: likely legacy unless proven active.
- `.gitignore` excludes volatile Irssi files such as `.irssi/config`,
  `.irssi/away.log`, and `.irssi/url`, while tracked files are themes, scripts,
  autorun plugins, and trigger rules.

### eihooks

- Files: `.eihooks/dotfiles/*`, `.eihooks/vim/**`.
- Status: mixed. Do not classify the whole tree as dead.
- Active evidence:
  - `.config/nvim/init.vim` sources `.eihooks/dotfiles/vimrc`.
  - `.config/nvim/vscode-init.vim` sources `.eihooks/dotfiles/vimrc`.
  - `.vimrc` sources `.eihooks/dotfiles/vimrc`.
  - `.zshrc.d/00_setup_envimprovement.zsh` sets `ENV_IMPROVEMENT_ZSHRC` to
    `.eihooks/dotfiles/zshrc`.
- Legacy evidence:
  - Many eihooks files are Screen-specific or old Vim plugin copies.
  - The current zsh startup does not directly source `.eihooks/dotfiles/zshrc`
    in the tracked `.zshrc.d` files.
- Practical rule: editor base behavior may depend on eihooks; Screen-era pieces
  probably do not.

## Older or Secondary Configs

### iTerm2

- Files: `.iterm2/com.googlecode.iterm2.plist`,
  `.iterm2_shell_integration.zsh`, and
  `Library/Application Support/iTerm2/parsers/*`.
- Status: secondary. Current tmux docs name Ghostty as the terminal layer, and
  iTerm shell integration in `.zshrc.d/12_iterm_integrations.zsh` and
  `.zshrc.d/98_iterm_integrations.zsh` is commented out.

### Classic Vim Tree

- Files: `.vimrc`, `.vim/**`, `.vimrc.fzf`, `.vimrc.neocomplete`,
  `.vimrc.unite`.
- Status: older but not necessarily dead. Primary config is Neovim under
  `.config/nvim/`, but `.vimrc` still exists and sources eihooks. Avoid sweeping
  cleanup unless the user asks.

### X11 Startup

- File: `.Xsession`.
- Status: likely legacy on this macOS-centered repo. It starts GNOME components
  and then execs Ratpoison.

## Current Replacements to Prefer

- Prefer tmux over Screen for terminal multiplexing.
- Prefer `docs/tmux-setup.md`, `.tmux.*`, `.config/ghostty/config`, and
  `bin/ts/src/ic.ts` for session management.
- Prefer Finicky (`.finicky.js`) for browser/app URL routing.
- Prefer `notifications/` plus `notifyctl` for native macOS notifications.
- Prefer `docs/meeting-notification-architecture.md` for MeetingBar, overlay,
  and native meeting notification workflows.

## Before Editing Legacy Areas

1. Check whether a current tracked file still sources or invokes the target.
2. Keep edits minimal; these areas have lots of old absolute paths and implicit
   tool assumptions.
3. Do not remove legacy files just because they look stale. The repo preserves
   historical config, and some old Vim/eihooks pieces still feed active editor
   startup.
