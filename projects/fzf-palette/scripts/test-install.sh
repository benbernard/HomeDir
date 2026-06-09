#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

INSTALL_DIR="$TMPDIR/Applications/FzfPalette.app"
LAUNCH_AGENT_DIR="$TMPDIR/LaunchAgents"
LOG_DIR="$TMPDIR/Logs"
LAUNCH_AGENT_LABEL="dev.benbernard.fzf-palette.test"
PLIST="$LAUNCH_AGENT_DIR/$LAUNCH_AGENT_LABEL.plist"
HOTKEY="ctrl+option+shift+f18"
HOTKEY_PROFILE="context-files"

CONFIGURATION=debug \
INSTALL_DIR="$INSTALL_DIR" \
LAUNCH_AGENT_DIR="$LAUNCH_AGENT_DIR" \
LOG_DIR="$LOG_DIR" \
LAUNCH_AGENT_LABEL="$LAUNCH_AGENT_LABEL" \
FZF_PALETTE_HOTKEY="$HOTKEY" \
FZF_PALETTE_HOTKEY_PROFILE="$HOTKEY_PROFILE" \
"$ROOT/scripts/install-app.sh" --launch-agent >/tmp/fzf-palette-test-install.out

if [[ ! -x "$INSTALL_DIR/Contents/MacOS/FzfPaletteApp" ]]; then
  echo "installed app executable is missing or not executable" >&2
  exit 1
fi

if [[ ! -s "$INSTALL_DIR/Contents/Resources/FzfPalette.icns" ]]; then
  echo "installed app icon is missing or empty" >&2
  exit 1
fi

if [[ ! -f "$PLIST" ]]; then
  echo "LaunchAgent plist was not written: $PLIST" >&2
  exit 1
fi

/usr/bin/plutil -lint "$INSTALL_DIR/Contents/Info.plist" >/dev/null
/usr/bin/plutil -lint "$PLIST" >/dev/null

python3 - "$PLIST" "$INSTALL_DIR/Contents/Info.plist" "$INSTALL_DIR/Contents/MacOS/FzfPaletteApp" "$LOG_DIR" "$LAUNCH_AGENT_LABEL" "$HOTKEY" "$HOTKEY_PROFILE" <<'PY'
import plistlib
import sys

plist_path, info_path, executable, log_dir, label, hotkey, hotkey_profile = sys.argv[1:]
with open(info_path, "rb") as file:
    info = plistlib.load(file)

assert info["CFBundleIconFile"] == "FzfPalette", info
assert info["CFBundlePackageType"] == "APPL", info
assert info["LSUIElement"] is True, info

with open(plist_path, "rb") as file:
    plist = plistlib.load(file)

assert plist["Label"] == label, plist
assert plist["ProgramArguments"] == [executable], plist
assert plist["RunAtLoad"] is True, plist
assert plist["KeepAlive"] == {"Crashed": True}, plist
assert plist["StandardOutPath"] == f"{log_dir}/launchd.out.log", plist
assert plist["StandardErrorPath"] == f"{log_dir}/launchd.err.log", plist
assert plist["EnvironmentVariables"]["FZF_PALETTE_HOTKEY"] == hotkey, plist
assert plist["EnvironmentVariables"]["FZF_PALETTE_HOTKEY_PROFILE"] == hotkey_profile, plist
PY

INSTALL_DIR="$INSTALL_DIR" \
LAUNCH_AGENT_DIR="$LAUNCH_AGENT_DIR" \
LOG_DIR="$LOG_DIR" \
LAUNCH_AGENT_LABEL="$LAUNCH_AGENT_LABEL" \
"$ROOT/scripts/install-app.sh" --uninstall-launch-agent >/tmp/fzf-palette-test-uninstall.out

if [[ -e "$PLIST" ]]; then
  echo "LaunchAgent plist still exists after uninstall: $PLIST" >&2
  exit 1
fi

echo "install app/launch-agent test passed"
