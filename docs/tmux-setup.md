# Nested Tmux Setup Documentation

## Overview

This setup runs **two levels of tmux** to manage different contexts:

1. **Outer tmux** (default socket) -- The "always-on" session, typically named `default`. Contains top-level windows, one per project/context.
2. **Inner/nested tmux** (socket: `nested`, config: `~/.tmux.nested.conf`) -- Runs inside an outer tmux window, providing per-project windows/panes.

The two layers are visually distinguished by color theme (outer = green accent, inner = blue accent) and the inner has a rainbow separator bar between its two status lines.

## Architecture Diagram

```
Ghostty Terminal
  |
  +-- Outer tmux (default socket, prefix: C-x)
  |     |
  |     +-- Window 0: "default shell"
  |     +-- Window 1: "ic: myproject"  <-- runs nesttm/ic attach
  |     |     |
  |     |     +-- Inner tmux (socket: nested, prefix: C-x via C-o)
  |     |           +-- Window 0: shell in ~/repos/myproject
  |     |           +-- Window 1: shell in ~/repos/myproject
  |     |           +-- Window 2: shell in ~/repos/myproject
  |     |
  |     +-- Window 2: "paste-tracker"  <-- from startupServerScreen.sh
```

## Key Files

| File | Purpose |
|------|---------|
| `~/.tmux.shared.conf` | Shared settings sourced by both outer and nested configs |
| `~/.tmux.conf` | Outer-only config: sources shared, adds outer bindings + green styling |
| `~/.tmux.nested.conf` | Nested-only config: sources shared, adds nested bindings + blue styling |
| `~/.config/ghostty/config` | Terminal keybindings for modifier combos that reach nested tmux |
| `~/.zshrc.d/02_functions.zsh` | Shell functions: `nesttm`, `nt` |
| `~/.zshrc.d/05_ic.zsh` | `ic` shell wrapper (sources output script from TS binary) |
| `bin/ts/src/ic.ts` | `ic` TypeScript binary: clone, attach, tmux renumber, symlinks |
| `bin/tmux-swap-or-move-window` | Shell script: swap two tmux windows by index |
| `bin/ts/src/tmux-fzf-picker.ts` | FZF file/directory picker in a tmux popup |
| `bin/ts/src/tmux-health-check.ts` | Verify nested tmux keybinding chain and config health |
| `bin/tmux-sub-session-window.sh` | Create a "mini session" linked to an existing session |
| `bin/startupServerScreen.sh` | Legacy startup script for server-like windows |
| `submodules/tmux` | Custom tmux build (amling fork), on PATH |
| `.tmux/plugins/tpm` | Tmux Plugin Manager (submodule) |

## Config File Structure

```
~/.tmux.shared.conf          <-- Sourced by BOTH outer and nested
  ├── Extended keys, prefix (C-x), terminal settings
  ├── Mouse, scrollback, aggressive-resize
  ├── Standard key bindings (vi movement, splits, etc.)
  ├── Copy mode (vi keys, Cmd+C via Ghostty User0)
  ├── Plugins (TPM, copycat, yank)
  └── Shared Catppuccin Macchiato base styling

~/.tmux.conf (outer)          <-- Sources shared, then adds:
  ├── C-M-Arrow window movement (intercepted before nested)
  ├── C-o send-prefix (sends C-x to nested tmux)
  ├── MouseDragEnd1Pane → copy-pipe-and-cancel "pbcopy" (auto-copy)
  ├── DoubleClick/TripleClick1Pane → select + copy-pipe-and-cancel "pbcopy"
  ├── FZF file/dir pickers (M-p, M-P, M-h, M-H, M-r, M-R)
  ├── Green accent styling (#a6da95)
  └── Site-specific overrides (~/site/tmux.conf)

~/.tmux.nested.conf (nested)  <-- Sources shared, then adds:
  ├── C-M-S-Arrow window movement (via Ghostty escape sequences)
  ├── Copy mode: Enter/y → copy-pipe-and-cancel "pbcopy"
  ├── MouseDragEnd1Pane → copy-pipe-and-cancel "pbcopy" (auto-copy)
  ├── DoubleClick/TripleClick1Pane → select + copy-pipe-and-cancel "pbcopy"
  ├── OUTER_TMUX_WINDOW environment variable tracking
  ├── Blue accent styling (#8aadf4)
  └── Double status bar with rainbow separator + "NESTED" label
```

This split means the nested config **no longer** inherits outer-only bindings like `C-M-Arrow` or `C-o send-prefix`. Each layer only has the bindings it needs.

## The Two Sockets Model

### Outer tmux (default socket)

- Started normally: `tmux new -s default`
- Uses `~/.tmux.conf` (which sources `~/.tmux.shared.conf`)
- Prefix: **C-x**
- Visual: **Green** accent (Catppuccin Macchiato theme)
- Window movement: **C-M-Arrow** (Ctrl+Alt+Arrow)

### Inner/nested tmux (`-L nested` socket)

- Started via `nesttm` or `ic attach`
- Uses `~/.tmux.nested.conf` (which sources `~/.tmux.shared.conf`)
- Separate socket (`-L nested`) so the two tmux instances don't share state
- Prefix: still **C-x**, reached via **C-o** (which sends the prefix to the inner layer)
- Visual: **Blue** accent, darker background (`#1e2030` vs `#24273a`)
- Has a **double status bar** (`status 2`) with a rainbow separator line on the second row
- Window movement: **C-M-S-Arrow** (Ctrl+Alt+Shift+Arrow)
- Status bar shows "NESTED" label

### How the prefix reaches nested tmux

```
C-x           -> outer tmux captures this (it's the prefix)
C-o           -> outer tmux sends C-x to the inner terminal (via send-prefix)
               -> inner tmux captures C-x as ITS prefix
C-x C-o      -> sends literal C-o to the terminal app (double-escape)
C-x o         -> also sends literal C-o
```

This is configured in `~/.tmux.conf` (outer only):
```
bind-key -n C-o send-prefix          # No-prefix binding: C-o sends C-x to inner
bind-key C-o send-keys C-o           # C-x C-o sends literal C-o
bind-key o send-keys C-o             # C-x o also sends literal C-o
```

## Ways to Create Nested Sessions

### 1. `ic attach` / `ic a` (Primary method)

The `ic` command (`bin/ts/src/ic.ts` + `~/.zshrc.d/05_ic.zsh`) is the main tool for attaching to nested tmux sessions.

**How it works:**
1. Detects current directory context (git repo, workspace, or arbitrary dir)
2. For workspaces: names the session `ic_ws_<name>`, for repos: `ic_<dirname>`
3. Checks if a session already exists on the `nested` socket
4. If session exists: attaches (with `--force` to detach other clients)
5. If session doesn't exist: creates a new session with 3 windows, all cd'd to the repo root
6. Outputs a shell script that the zsh wrapper sources (this is the "shell integration" pattern)
7. Sets the outer window title to `ic: <dirname>` via escape codes

**The shell integration pattern:** The TypeScript binary writes commands to a temp file (via `--shell-integration-script`), and the zsh wrapper sources it. This is needed because the binary can't change the parent shell's state (like cd or exec tmux).

**Key function:** `execNestedTmux()` in `ic.ts` wraps all tmux commands as `tmux -L nested -f ~/.tmux.nested.conf <command>`.

### 2. `nesttm <name>` (Manual method)

Defined in `~/.zshrc.d/02_functions.zsh`. Simpler than `ic attach`:
1. Captures the outer tmux window name as `OUTER_TMUX_WINDOW`
2. Sets that variable in the nested tmux's global environment
3. Uses `env -u TMUX` to hide the outer TMUX variable (otherwise tmux refuses to nest)
4. Creates or attaches to a session named `<name>` on the `nested` socket

### 3. `nt <name>` (Minimal helper)

Defined in `02_functions.zsh`:
```zsh
nt() {
  tmux attach-session -t "$@" || tmux new-session -s "$@"
}
```
This is a bare-bones "attach or create" on the **default socket**. No nesting awareness.

## Keybinding Architecture

### Ghostty -> Outer tmux -> Inner tmux key chain

The modifier key combinations are carefully partitioned between layers:

| Keys | Where handled | Action |
|------|---------------|--------|
| C-x | Outer tmux prefix | Activates prefix mode |
| C-o | Outer tmux (no prefix) | Sends C-x (prefix) to inner tmux |
| C-M-Arrow | Outer tmux (no prefix) | Move window in outer tmux |
| C-M-S-Arrow | Inner tmux (no prefix) | Move window in inner tmux |
| M-p, M-P, M-h, M-H, M-r, M-R | Outer tmux (no prefix) | FZF file/dir picker |
| Super+C | Shared (Ghostty -> tmux) | Copy in copy-mode, or C-c in normal mode |

**Ghostty's role:** Ghostty sends specific escape sequences that tmux can recognize:
- `C-M-S-Arrow`: Sends `\x1b[1;8{D,C,A,B}` (modifier 8 = Shift+Alt+Ctrl)
- `Super+C`: Sends `\x1b[99;9~` (custom CSI sequence, registered as `User0` in tmux)

### Extended keys

The shared config sets `set-option -s extended-keys always` to ensure modifier combinations actually reach tmux properly. Both layers inherit this.

### Window movement (`tmux-swap-or-move-window`)

`bin/tmux-swap-or-move-window` handles window reordering:
- Takes a direction (`:-1` for left, `:+1` for right) or an absolute index
- Accepts an optional `pane_id` parameter (e.g., `%5`) to target the correct session
- When `pane_id` is provided, uses `tmux display-message -t $pane_id` to resolve the session/window context — critical for multi-session nested tmux
- Finds the adjacent window by iterating sorted window indices
- Swaps the two windows and follows focus to the moved window
- Called by outer (`C-M-Arrow`) and inner (`C-M-S-Arrow`) configs, both passing `#{pane_id}`
- Also called by `prefix m` (move to absolute index), which also passes `#{pane_id}`

## FZF File Picker (`tmux-fzf-picker`)

`bin/ts/src/tmux-fzf-picker.ts` provides a rich file/directory picker inside a tmux popup:

- **M-p / M-P**: Pick files/dirs in current pane's directory
- **M-h / M-H**: Pick files/dirs in `$HOME` (excluding `repos/`)
- **M-r / M-R**: Pick dirs/files in `~/repos/`

**How it works:**
1. Writes a state file (tracks current dir, type, hidden/ignore toggles)
2. Writes a helper shell script for fzf's `--preview` and `transform` bindings
3. Writes a runner script that launches fzf and sends selection to the originating pane
4. Opens a tmux popup (`tmux display-popup`) running the runner script
5. Internal shortcuts: `ctrl-t` toggle files/dirs, `ctrl-i` drill into dir, `ctrl-o` go up, `ctrl-j` jump to path, `ctrl-g` toggle gitignore, `ctrl-h` toggle dotfiles

## `ic tmux renumber` / `ic t rn`

Renumbers tmux windows to remove gaps (e.g., 0,2,5 -> 0,1,2). Bound to `prefix R` in both layers (defined in shared config). The implementation:
1. Detects if running in nested tmux (checks socket name for "nested")
2. Uses the socket path from `$TMUX` to send commands to the correct tmux instance
3. Uses tmux's built-in `move-window -r` command

## `ic attach-dirs` / `ic ad`

Creates one tmux window per subdirectory of the current (or specified) directory. Useful for quickly setting up windows for multiple repos in a project.

## `tmux-health-check`

Diagnostic tool that verifies the entire nested tmux keybinding chain is healthy. Run it anytime `C-M-S-Arrow` window movement stops working in nested tmux, or after making config changes.

**What it checks:**
1. **Config files** -- All three configs exist, source the right files, nested doesn't source outer, outer has explicit unbinds
2. **Outer tmux server** -- Has `C-M-Arrow` bindings, does NOT have `C-M-S-Arrow` (stale binding detection), has `C-o send-prefix`, extended-keys enabled
3. **Nested tmux server** -- Has `C-M-S-Arrow` bindings, does NOT have `C-M-Arrow` or `C-o send-prefix` (stale binding detection), extended-keys enabled
4. **Tools on PATH** -- `tmux-swap-or-move-window`, `tmux-fzf-picker`, `ic`
5. **Ghostty config** -- All `C-M-S-Arrow` keybinds and `Super+C` present

**Important:** The script always uses explicit socket names (`-L default` for outer, `-L nested` for nested) rather than bare `tmux`. This is critical because bare `tmux` inherits `$TMUX`, which points to whichever server the current pane belongs to — running it from inside a nested pane would check the nested server twice and the outer server never.

**Common failure scenario:** After a config change, `tmux source-file` (reload) is additive — it adds new bindings but never removes old ones. If the outer tmux previously had `C-M-S-Arrow` bindings, they persist as stale bindings that intercept keys meant for nested tmux. The explicit `unbind-key` lines in both configs prevent this, but if stale bindings are detected, a full server restart is needed: `tmux -L default kill-server && tmux -L nested kill-server`.

## Visual Theming

Both layers use **Catppuccin Macchiato** with different accent colors:

| Element | Outer (Green) | Inner (Blue) |
|---------|---------------|--------------|
| Background | `#24273a` (Base) | `#1e2030` (Mantle, darker) |
| Active window pill | Green `#a6da95` | Blue `#8aadf4` |
| Active pane border | Green `#a6da95` | Blue `#8aadf4` |
| Status bar right | Date + time | "NESTED" label + date + time |
| Status lines | 1 | 2 (second line is rainbow separator) |
| Inactive pills | `#363a4f` (Surface0) | `#363a4f` (Surface0) |
| Clock | Purple `#c6a0f6` | Purple `#c6a0f6` (shared) |

## Plugins

Managed via TPM (Tmux Plugin Manager), submodule at `.tmux/plugins/tpm`. Defined in the shared config so both layers get them:
- `tmux-copycat`: Better search
- `tmux-yank`: System clipboard integration (`@override_copy_command = pbcopy`)

## Copy/Paste Architecture

Multiple layers cooperate for clipboard:

1. **Ghostty** `Super+C` -> sends `\x1b[99;9~` (CSI 99;9~)
2. **Tmux shared config** registers this as `User0`:
   - In copy-mode-vi: `copy-pipe-and-cancel "pbcopy"`
   - In root (normal): sends `C-c` (interrupt)
3. **Mouse drag** in both layers: `copy-pipe-and-cancel "pbcopy"` (auto-copies on mouse-up)
4. **Double-click/triple-click** in both layers: select word/line and `copy-pipe-and-cancel "pbcopy"`
5. **vi copy-mode keys** (inner tmux): `y`, `Enter` -> `copy-pipe-and-cancel "pbcopy"`
6. **tmux-yank plugin** (shared): Uses `pbcopy`, mouse selection to clipboard

## The Custom tmux Build

`submodules/tmux` points to `git@github.com:amling/tmux.git` (amling's fork). This is on PATH via `$(submodule tmux)` in `02_environment.zsh`. The fork may include custom features like `change-joinmode` (commented out in config).

## Legacy / Startup Scripts

- **`bin/startupServerScreen.sh`**: Creates named windows (web, paste-tracker) with specific commands. Disables `allow-rename` on those windows during setup.
- **`bin/tmux-sub-session-window.sh`**: Creates a "mini session" linked to an existing one, allowing a separate view of the same windows.

---

## Known Brittleness and Past Issues

### 1. Extended Keys Sensitivity

The `C-M-S-Arrow` keybindings for nested window movement require:
- Ghostty to send the right escape sequence (configured in `~/.config/ghostty/config`)
- Tmux `extended-keys always` to be set (in shared config)

If any of these break (e.g., different terminal, tmux version change), the nested window movement stops working silently.

### 2. OSC 52 Clipboard Passthrough Doesn't Work Nested

Tmux's default `copy-pipe-and-cancel` (without a pipe command) relies on OSC 52 (`set-clipboard external`) to reach the system clipboard. This works in the outer tmux (OSC 52 → Ghostty), but fails in nested tmux because the outer tmux doesn't pass OSC 52 through. All mouse copy bindings (`MouseDragEnd1Pane`, `DoubleClick1Pane`, `TripleClick1Pane`) in both configs explicitly pipe to `pbcopy` to avoid this. If new copy bindings are added, they must also use explicit `pbcopy`.

### 3. `escape-time 0` in Shared Config

`set -s escape-time 0` is in the shared config, inherited by both layers. While this is good for responsiveness, it means any escape sequence that arrives in parts (e.g., over a slow SSH connection) could be misinterpreted. This is unlikely in the current local setup but would break if nested tmux were used over SSH.

### 4. `C-Enter` Fix-up Chain

Ctrl+Enter autosuggest acceptance requires coordination across three layers:
1. Ghostty's `ctrl+enter` sends `\x1b[27;5;13~` (may rely on Ghostty default behavior)
2. Tmux translates `C-Enter` via `bind-key -n C-Enter send-keys "\e[27;5;13~"` (shared config)
3. Zsh binds `\e[27;5;13~` to `autosuggest-accept` (`.zshrc.d/02_prompt.zsh`)

If any of these three components changes, Ctrl+Enter stops accepting autosuggestions.

### 5. Window Title Escape Codes

`nesttm` and `ic attach` use raw escape codes (`\033k...\033\\`) to set the outer window title. If the terminal or tmux version changes how these escape codes are interpreted, window titles may show garbled text or not update.

### 6. `ic attach` Session Name Format

The `ic` tool uses `ic_<dirname>` for session names and `ic_ws_<workspace>` for workspace sessions. If directory names contain characters that tmux doesn't allow in session names (like `.` or `:`), session creation may fail. There's no sanitization of the session name.

### 7. Custom tmux Binary Version Sensitivity

Using amling's fork of tmux (`submodules/tmux`) means configuration options may differ from upstream tmux. If the submodule is updated or the system tmux is accidentally used instead, features like `change-joinmode` or specific escape code handling could break.

### 8. TPM Plugin Loading Runs Twice

TPM is initialized at the bottom of `~/.tmux.shared.conf`. Since both outer and nested configs source the shared config, TPM runs once per layer. The plugins (tmux-yank, tmux-copycat) load independently in each layer, which is the desired behavior but means plugin config changes need to be verified in both layers.

### 9. `$TMUX` Socket Inheritance

When running inside a nested pane, `$TMUX` points to the nested socket (`/tmp/tmux-*/nested`). Bare `tmux` commands (without `-L`) inherit this and target the nested server. This means:
- `tmux source-file ~/.tmux.conf` from a nested pane reloads into the **nested** server, not the outer
- `tmux list-keys` shows nested bindings, not outer

Always use explicit sockets: `tmux -L default` for outer, `tmux -L nested` for nested. The `tmux-health-check` script handles this correctly.

### 10. Stale Bindings After Config Reload

`tmux source-file` is additive — it adds/overrides bindings but never removes them. Both `.tmux.conf` and `.tmux.nested.conf` include explicit `unbind-key` lines to clean up keys that belong to the other layer. Without these, stale bindings from old configs persist indefinitely and silently intercept keys. Run `tmux-health-check` to detect this.

### 11. `run-shell` Session Context

tmux's `run-shell` executes in the context of the **client's currently-active session**, not the session where the keybinding was triggered. In nested tmux with multiple sessions (e.g., `ic_benbernard`, `ic_RecordStream`), pressing `C-M-S-Arrow` in one session could move a window in a *different* session if the client's focus had shifted.

All bindings that call `tmux-swap-or-move-window` pass `#{pane_id}` so the script can use `-t $pane_id` to resolve the correct session. Without this, the script falls back to bare `tmux display-message -p` which uses the client's current session — often wrong in multi-session setups.

---

## Historical Issues (Resolved)

- **`reattach-to-user-namespace` (removed)**: The nested config previously used `reattach-to-user-namespace pbcopy` for clipboard, which silently failed on modern macOS where it's unnecessary. Fixed by switching to bare `pbcopy`. The stub binary and all references have been removed.
- **Nested config sourced entire outer config (fixed)**: The nested config used to `source-file ~/.tmux.conf`, inheriting outer-only bindings like `C-M-Arrow` and `C-S-Arrow`. Fixed by extracting shared settings into `~/.tmux.shared.conf` -- both configs now source only the shared file.
- **Duplicated `wta` implementation (removed)**: `wta` was defined in both `03_git_worktree.zsh` and `04_git_worktree_ts.zsh` with hardcoded DEBUG output and socket inconsistencies (used default socket instead of `-L nested`). The `wt`/`wta` system has been removed entirely.
- **`sychronize-panes` typo (removed)**: The old `.tmux.conf` had a typo `sychronize-panes` (missing 'n') on a duplicate binding that silently did nothing. Removed during the config split.
- **Stale C-M-S-Arrow bindings in outer tmux (fixed)**: The outer tmux had `C-M-S-Arrow` bindings left over from the old config, intercepting keys meant for nested tmux. Fixed by adding explicit `unbind-key` lines in both configs and the `tmux-health-check` diagnostic tool.
- **`run-shell` session context bug (fixed)**: `tmux-swap-or-move-window` used bare `tmux display-message -p '#{window_index}'` which resolves to the client's currently-active session, not the session where the keybinding was pressed. In multi-session nested tmux, this caused `C-M-S-Arrow` to silently move windows in the wrong session (or fail when the window index didn't exist). Fixed by passing `#{pane_id}` from all bindings and using `-t $pane_id` in the script.
