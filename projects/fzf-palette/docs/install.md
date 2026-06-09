# Install And Launch Agent

`fzf-palette` is a resident app. The bundle can be installed manually for
development, and the installer can also write a per-user LaunchAgent so the app
starts at login.

## Build

```bash
scripts/build-app.sh
```

This creates:

```text
.build/FzfPalette.app
```

The bundle includes a generated `FzfPalette.icns` app icon under
`Contents/Resources`, and `Info.plist` points `CFBundleIconFile` at that icon.

## Install The App Bundle

```bash
scripts/install-app.sh
```

Default install location:

```text
~/Applications/FzfPalette.app
```

Set `INSTALL_DIR` to install into another location.

## Install At Login

```bash
scripts/install-app.sh --launch-agent
```

This writes:

```text
~/Library/LaunchAgents/dev.benbernard.fzf-palette.plist
```

The LaunchAgent runs the installed app executable directly, writes launchd logs
under `~/Library/Logs/FzfPalette`, starts at login, and asks launchd to restart
the app after a crash.

To load it immediately after writing:

```bash
scripts/install-app.sh --launch-agent --load
```

To remove the LaunchAgent:

```bash
scripts/install-app.sh --uninstall-launch-agent
```

The uninstall command unloads the per-user LaunchAgent if it is running and
removes the plist. It does not remove the installed app bundle.

## Hotkey Configuration

If `FZF_PALETTE_HOTKEY` is set when the LaunchAgent is written, the installer
stores that safe environment value in the plist. `FZF_PALETTE_HOTKEY_PROFILE`
can be set with it to choose which profile that binding opens:

```bash
FZF_PALETTE_HOTKEY=ctrl+option+shift+f18 \
FZF_PALETTE_HOTKEY_PROFILE=context-files \
scripts/install-app.sh --launch-agent
```

The installer does not copy arbitrary shell environment into launchd.

## Test Coverage

```bash
scripts/test-install.sh
```

The install test uses temporary `INSTALL_DIR`, `LAUNCH_AGENT_DIR`, and `LOG_DIR`
locations. It validates the app copy, plist syntax, LaunchAgent fields, hotkey
environment value, and uninstall removal without loading the real user
LaunchAgent.
