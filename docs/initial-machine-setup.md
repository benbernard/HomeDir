# Initial Machine Setup

This is an agent runbook for setting up a new Mac from an old Mac without
Migration Assistant. It is based on the 2026 transfer captured in
`transfer.md`, but written as a reusable procedure rather than an execution log.

The goal is not a perfect byte-for-byte clone. The goal is to make the target
machine usable quickly, preserve local working state, and leave a clear audit
trail for what still needs GUI validation.

## Operating Model

Use two machine roles:

- Source: the old Mac that already has the desired state.
- Target: the new Mac being set up.

Prefer staged, resumable work:

1. Bootstrap the target enough for SSH, Git, Homebrew, and `rsync`.
2. Temporarily enable passwordless sudo on both machines for the active admin
   user.
3. Snapshot source state and generate transfer artifacts.
4. Install packages and apps on the target.
5. Restore tracked dotfiles and submodules.
6. Restore separate workspaces and app state with scoped `rsync` passes.
7. Validate shell, tmux, terminal fonts, URL routing, notifications, and key
   apps.
8. Remove temporary passwordless sudo.

Do not treat this as a blind recursive copy. Broad home-directory copies are
slow, noisy, and dangerous on macOS because protected Apple data stores and
File Provider folders frequently reject SSH writes.

## Historical Bootstrap References

The old `bin/mac/setupMac.sh` flow is a reference, not the strategy. Do not run
it blindly from an agent session. Use this document as the setup path and borrow
from the older scripts only when a specific step is still useful.

Useful historical files:

- `bin/mac/setupMac.sh`: old end-to-end setup script. Good for remembering
  categories of setup work, but stale as an execution path.
- `bin/mac/brew-installs.sh`: Homebrew package inventory reference.
- `bin/mac/installApps.sh`: older app install helper.
- `bin/mac/setupDefaults.sh`: macOS defaults and preferences reference.
- `.gitmodules`: submodule inventory.
- `.mackup.cfg` and `.mackup/`: older Mackup configuration; treat as legacy
  unless the user explicitly asks to revive it.

Useful lessons from the old script:

- Install CLT, Homebrew, shell/editor dependencies, fonts, and fzf early.
- Initialize submodules before relying on prompt, shell, tmux, or plugin state.
- Set `/opt/homebrew/bin/zsh` as the login shell only after it exists and is in
  `/etc/shells`.
- Restore app-specific state deliberately; old OneDrive backup paths may not
  exist and should not be assumed.
- Configure Touch ID sudo after `pam-reattach` is installed.
- Run interactive auth setup such as GitHub, Copilot, cloud CLIs, and app
  licenses as validation work, not as unattended bootstrap.

Known rot to avoid:

- The script assumes a fresh clone flow that may not match the current checked
  out home directory.
- It has machine/user path assumptions.
- It includes an old `instalApps.sh` typo.
- It uses stale manual post-install instructions for apps and browser profiles.
- It changes system files and login shell state, so individual commands need to
  be reviewed before reuse.

Submodules include shell/editor/tooling dependencies such as Oh My Zsh, fzf,
fonts, fast syntax highlighting, tmux plugins, and personal helper repos.

Useful commands:

```bash
git submodule status
git submodule update --init --recursive
```

Avoid broad searches inside submodules unless the task targets one directly.

## First Facts To Collect

Collect these before copying anything substantial:

```bash
hostname
sw_vers
uname -m
df -h
xcode-select -p 2>/dev/null || true
brew --prefix 2>/dev/null || true
git -C /Users/benbernard status --short --branch 2>/dev/null || true
git -C /Users/benbernard/site status --short --branch 2>/dev/null || true
```

On the target, also find the current LAN address and confirm SSH:

```bash
ifconfig | grep inet
ssh TARGET_IP 'hostname; sw_vers; id; sudo -n true && echo sudo_ok || echo sudo_needs_auth'
```

Record facts in a transfer log before doing destructive or long-running work.

## Temporary Passwordless Sudo

Agents need independent sudo access on both source and target for app bundles,
system config, ownership-preserving copies, and protected install paths. Use a
temporary sudoers drop-in, then remove it during cleanup.

This is intentionally a temporary setup. It is broader than normal day-to-day
sudo policy and should not survive the migration.

### Install The Drop-In

Run once on each machine as the active admin user. The command requires one
manual admin authentication on that machine.

```bash
sudo grep -q '^#includedir /private/etc/sudoers.d' /etc/sudoers
USER_NAME="$(id -un)"
TMP_SUDOERS="/tmp/99-agent-temp-nopasswd"
cat > "$TMP_SUDOERS" <<EOF
$USER_NAME ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 "$TMP_SUDOERS"
sudo mkdir -p /etc/sudoers.d
sudo cp "$TMP_SUDOERS" /etc/sudoers.d/99-agent-temp-nopasswd
sudo chown root:wheel /etc/sudoers.d/99-agent-temp-nopasswd
sudo chmod 0440 /etc/sudoers.d/99-agent-temp-nopasswd
sudo visudo -cf /etc/sudoers
sudo -k
sudo -n true
rm -f "$TMP_SUDOERS"
```

If the agent cannot complete the first authenticated `sudo` on the source
machine, ask the user to run the block locally. Do not ask for or capture the
password.

For the target over SSH, keep the bootstrap readable. Create the sudoers file
locally, copy it to the target, then use one interactive remote sudo step:

```bash
TARGET=TARGET_IP
USER_NAME="benbernard"
TMP_SUDOERS="/tmp/99-agent-temp-nopasswd"
cat > "$TMP_SUDOERS" <<EOF
$USER_NAME ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 "$TMP_SUDOERS"
scp "$TMP_SUDOERS" "$TARGET:/tmp/99-agent-temp-nopasswd"
ssh -tt "$TARGET" 'sudo grep -q "^#includedir /private/etc/sudoers.d" /etc/sudoers && sudo mkdir -p /etc/sudoers.d && sudo cp /tmp/99-agent-temp-nopasswd /etc/sudoers.d/99-agent-temp-nopasswd && sudo chown root:wheel /etc/sudoers.d/99-agent-temp-nopasswd && sudo chmod 0440 /etc/sudoers.d/99-agent-temp-nopasswd && sudo visudo -cf /etc/sudoers && sudo -k && sudo -n true'
ssh "$TARGET" 'rm -f /tmp/99-agent-temp-nopasswd'
rm -f "$TMP_SUDOERS"
```

If the remote sudo prompt cannot be handled through the agent session, stop
being clever: ask the user to paste the local install block into a target
terminal once, then continue over SSH.

### Verify Before Long Runs

Verify independently on both machines:

```bash
sudo -k
sudo -n true
```

If this fails, do not start app-bundle or system-state transfers. Fix sudo
first, or every protected copy will fail partway through.

### Remove The Drop-In

At the end of setup, remove the temporary sudoers entry on both machines:

```bash
sudo rm -f /etc/sudoers.d/99-agent-temp-nopasswd
sudo visudo -cf /etc/sudoers
sudo -k
sudo -n true && echo "ERROR: passwordless sudo still active" || echo "passwordless sudo removed"
```

After removing it, configure normal Touch ID sudo if desired:

```bash
brew install pam-reattach
cat > /tmp/sudo_local.touchid <<'EOF'
# sudo_local: local config file which survives system update and is included for sudo
# uncomment following line to enable Touch ID for sudo
auth     optional     /opt/homebrew/lib/pam/pam_reattach.so  ignore_ssh
auth     sufficient   pam_tid.so
EOF
cat /tmp/sudo_local.touchid | /usr/libexec/authopen -c -m 0444 -w /etc/pam.d/sudo_local
rm -f /tmp/sudo_local.touchid
```

`pam_reattach` is needed for Ghostty/tmux workflows because `pam_tid.so` alone
can fall back to password prompts when sudo is not attached to the GUI session.
The `ignore_ssh` option skips GUI reattachment in probable SSH sessions.

## Source Snapshot

Create inventories and patch files before copying:

```bash
mkdir -p /tmp/mac-transfer-logs
brew tap > /tmp/transfer-brew-taps.txt
brew list --formula > /tmp/transfer-brew-formulae.txt
brew list --cask > /tmp/transfer-brew-casks.txt
brew services list > /tmp/transfer-brew-services.txt
brew bundle dump --describe --force --file /tmp/Brewfile.transfer
ls -1 /Applications > /tmp/transfer-applications.txt
ls -1 ~/Applications > /tmp/transfer-user-applications.txt
launchctl print "gui/$(id -u)" > /tmp/transfer-user-launchctl.txt
git -C /Users/benbernard status --porcelain=v1 > /tmp/home-status.txt
git -C /Users/benbernard diff > /tmp/home-uncommitted.patch
git -C /Users/benbernard/site status --porcelain=v1 > /tmp/site-status.txt
git -C /Users/benbernard/site diff > /tmp/site-uncommitted.patch
```

Do not print `.env` files, tokens, keychains, or other secrets into logs. Copy
secret-bearing files as files, not as pasted text.

## Target Bootstrap

On the target:

```bash
sudo xcode-select --reset || true
xcode-select -p || true
```

If Command Line Tools are missing, install them through the GUI or
`softwareupdate`. Then install Homebrew and core tools:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"
brew update
brew install git rsync zsh
```

Copy SSH material before private GitHub clones:

```bash
RSYNC=/opt/homebrew/bin/rsync
TARGET=TARGET_IP
"$RSYNC" -aAXN --protect-args ~/.ssh/ "$TARGET:/Users/benbernard/.ssh/"
ssh "$TARGET" 'chmod 700 ~/.ssh; chmod 600 ~/.ssh/* 2>/dev/null || true; chmod 644 ~/.ssh/*.pub 2>/dev/null || true'
ssh "$TARGET" 'ssh -T git@github.com || true'
```

## Home Repo And Submodules

Restore the tracked home repo before copying large untracked state:

```bash
ssh "$TARGET" 'cd /Users/benbernard && git init && git remote add origin git@github.com:benbernard/HomeDir.git 2>/dev/null || true'
ssh "$TARGET" 'cd /Users/benbernard && git fetch origin master && git reset --hard origin/master'
ssh "$TARGET" 'cd /Users/benbernard && git submodule update --init --recursive'
```

If submodule metadata breaks after later copies, sync `.git/modules/` from the
source without deleting target-only metadata, then rerun `git status`.

## Package And App Install

Use the generated Brewfile, but filter known skips before running it. During the
2026 transfer, `visual-studio-code` and `warp` were intentionally excluded.

```bash
grep -Ev 'cask "(visual-studio-code|warp)"' /tmp/Brewfile.transfer > /tmp/Brewfile.transfer.filtered
scp /tmp/Brewfile.transfer.filtered "$TARGET:/tmp/Brewfile.transfer"
ssh "$TARGET" 'eval "$(/opt/homebrew/bin/brew shellenv)"; brew bundle --file /tmp/Brewfile.transfer'
```

Only start services that are actually wanted. The source transfer only had
MySQL started.

## Rsync Defaults

Use Homebrew `rsync` and run major copies independently with logs:

```bash
TARGET=TARGET_IP
RSYNC=/opt/homebrew/bin/rsync
RSYNC_REMOTE=/opt/homebrew/bin/rsync
RSYNC_BASE=("$RSYNC" -aAXN --human-readable --info=progress2 --stats --partial --append-verify --protect-args)
RSYNC_TEXT=("$RSYNC" -aAXN --human-readable --info=progress2 --stats --partial --append-verify --protect-args --compress --compress-choice=zstd)
```

Use `RSYNC_TEXT` for mostly text config. Use `RSYNC_BASE` for apps, browser
profiles, media, archives, and dependency trees. Do not add `-H` globally.
Do not use `--fileflags` unless the target `rsync` supports it.

For protected app bundles or `/Library` paths, use sudo on both sides:

```bash
sudo "${RSYNC_BASE[@]}" --rsync-path="sudo $RSYNC_REMOTE" /Applications/Foo.app "$TARGET:/Applications/" \
  2>&1 | tee /tmp/mac-transfer-logs/app-Foo.log
```

## Copy Order

Use this order unless there is a concrete reason to deviate:

1. `site/` fast pass.
2. Active `repos/` fast pass.
3. Remaining `repos/` fast pass.
4. Browser profile state.
5. Selected app state from `Library/Application Support` and
   `Library/Preferences`.
6. Language/runtime state such as `.bun`, `.cargo`, `.rustup`, `.npm`, `.nvm`,
   `.yarn`, `.gem`, `.gradle`, `.rbenv`, `.pyenv`, and `.cache/uv`.
7. Top-level dot-state and ignored config not covered by the tracked home repo.
8. Dependency/build/cache completion pass where rebuilds are slower or less
   reliable than copying.
9. Non-hidden home folders, excluding `Library`, `repos`, `site`,
   OneDrive/CloudStorage, and `OrbStack`.

First passes should exclude rebuildable heavyweight folders:

```text
node_modules/
.next/
.turbo/
.cache/
dist/
build/
target/
.venv/
.gradle/
.terraform/
logs/
```

Copy `.env` and other ignored local files as files, but do not open or print
their contents.

## Ownership Audit

After copying dot-state, run a bounded ownership audit before declaring shell
or editor setup healthy. The 2026 transfer exposed a concrete failure here:
`~/.config/nvim/tmp` and `~/.config/nvim/tmp/RCSFiles` arrived root-owned after
sudo/editor activity, which caused saves to report:

```text
E828: Cannot open undo file for writing
rcsvers.vim: Permission denied
```

Classic Vim also had a root-owned `~/.viminfo`, which can break history/state
writes. `.ssh` had a related transfer problem: ownership was correct, but
runtime directories such as `~/.ssh/agent` and `~/.ssh/temp` had mode `600`,
which made them non-traversable. These are local runtime files, not valuable
portable config.

Do not copy or preserve these paths as source-of-truth state:

```text
~/.config/nvim/tmp/
~/.local/state/nvim/nvim.log
~/.viminfo
~/.ssh/agent/
~/.ssh/temp/
```

Repair pattern on the target:

```bash
mv ~/.config/nvim/tmp ~/.config/nvim/tmp.root-owned-transfer-$(date +%Y%m%d%H%M%S) 2>/dev/null || true
mkdir -p ~/.config/nvim/tmp/RCSFiles
chmod 700 ~/.config/nvim/tmp ~/.config/nvim/tmp/RCSFiles
rm -f ~/.local/state/nvim/nvim.log
sudo chown "$(id -un):staff" ~/.viminfo 2>/dev/null || rm -f ~/.viminfo
```

Repair SSH ownership and permissions explicitly instead of relying on a broad
home-directory `chown`:

```bash
chown -R "$(id -un):staff" ~/.ssh
chmod 700 ~/.ssh
find ~/.ssh -maxdepth 1 -type d -exec chmod 700 {} \;
chmod 600 ~/.ssh/config ~/.ssh/authorized_keys ~/.ssh/known_hosts ~/.ssh/known_hosts.old 2>/dev/null || true
find ~/.ssh -maxdepth 1 -type f \( -name 'id_*' -o -name '*.key' \) ! -name '*.pub' -exec chmod 600 {} \;
find ~/.ssh -maxdepth 1 -type f -name '*.pub' -exec chmod 644 {} \;
rm -f ~/.ssh/.DS_Store
```

If `~/.ssh/agent` contains socket files, remove only stale sockets. Check
current use first:

```bash
printf 'SSH_AUTH_SOCK=%s\n' "$SSH_AUTH_SOCK"
lsof -U 2>/dev/null | rg "$HOME/.ssh/agent|$SSH_AUTH_SOCK"
find ~/.ssh/agent -maxdepth 1 -type s -exec ls -l {} \; 2>/dev/null
```

Then verify with bounded scans. Keep these scoped; do not recurse blindly
through `repos/`, `site/`, `Library`, or dependency trees:

```bash
find ~/.config ~/.local ~/.cache ~/.claude ~/.codex ~/.aws ~/.docker ~/.gnupg \
  -xdev \( -path "$HOME/.codex/worktrees" -o -path "$HOME/.codex/sessions" \
  -o -path "$HOME/.cache/go-build" -o -path "$HOME/.cache/pip" \
  -o -path "$HOME/.cache/uv" \) -prune -o ! -user "$(id -un)" \
  -exec stat -f '%Su:%Sg %OLp %Sp %N' {} \;

find "$HOME" -xdev -maxdepth 2 \
  \( -path "$HOME/Library" -o -path "$HOME/repos" -o -path "$HOME/site" \
  -o -path "$HOME/node_modules" -o -path "$HOME/.Trash" \) -prune \
  -o ! -user "$(id -un)" -exec stat -f '%Su:%Sg %OLp %Sp %N' {} \;

find ~/.ssh -maxdepth 3 -exec stat -f '%Su:%Sg %OLp %Sp %N' {} \;
```

If `nvim` is part of the setup, run a real save test:

```bash
TEST="$HOME/codex-nvim-permission-test"
RCS="$HOME/.config/nvim/tmp/RCSFiles/codex-nvim-permission-test,_Users_benbernard"
UNDO="$HOME/.config/nvim/tmp/%Users%benbernard%codex-nvim-permission-test"
rm -f "$TEST" "$RCS" "$UNDO"
nvim --headless "$TEST" +'set nomore' +'call setline(1, "permission test")' +write +qa
ls -l "$TEST" "$RCS" "$UNDO"
rm -f "$TEST" "$RCS" "$UNDO"
```

## Special Cases

OneDrive:

- Do not rsync OneDrive synced folders, CloudStorage provider folders, or sync
  databases.
- Install and sign into OneDrive on the target.
- Validate with `fileproviderctl` and GUI state.

Photos, Photo Booth, TCC, and protected Apple stores:

- Expect SSH writes to fail even with sudo.
- Treat failures under Apple privacy-protected paths as GUI/privacy validation,
  not as ordinary rsync misses.

Chrome and other live apps:

- A live-copy first pass is useful, but final session fidelity requires closing
  the app and running a small delta.

OrbStack:

- Copy state only after quitting OrbStack, or let it recreate state if that is
  cleaner.

## Validation

Run on the target:

```bash
zsh -lc 'echo $SHELL; command -v brew git rg fd jq gh bun node go pyenv rbenv fnm tmux nvim gohan gws codex claude'
zsh -lc 'ben-scripts | head'
zsh -lc 'ic --help >/dev/null'
zsh -lc 'tmux -V'
zsh -lc 'git -C ~ status --short --branch'
zsh -lc 'git -C ~/site status --short --branch'
zsh -lc 'brew services list'
```

Interactive checks:

- Open Ghostty and confirm the Nerd Font prompt renders correctly.
- Confirm zsh startup, PATH, tmux keys, and nested tmux behavior.
- Open Cursor and confirm settings/extensions enough to work.
- Open Chrome and confirm profiles, extensions, and Finicky routing.
- Open MeetingBar and trigger a dry test.
- Open BetterTouchTool and Karabiner and grant permissions.
- Open OrbStack and confirm Docker CLI works.
- Run `gh auth status`; re-auth if needed.
- Refresh `gcloud`, `aws`, and other expiring credentials.

## Final Cleanup

Before declaring the migration done:

1. Remove temporary passwordless sudo from both machines.
2. Confirm `sudo -n true` fails after `sudo -k`.
3. Configure Touch ID sudo if desired.
4. Remove temporary transfer bundles and logs that contain machine state.
5. Record unresolved GUI/TCC/license items in the transfer log.
6. Check `git status --short --branch` in `/Users/benbernard`, `site/`, and
   any repo touched during the setup.
