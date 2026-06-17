#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/.build/FzfPalette.app"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications/FzfPalette.app}"
LAUNCH_AGENT_LABEL="${LAUNCH_AGENT_LABEL:-dev.benbernard.fzf-palette}"
LAUNCH_AGENT_DIR="${LAUNCH_AGENT_DIR:-$HOME/Library/LaunchAgents}"
LAUNCH_AGENT_PATH="$LAUNCH_AGENT_DIR/$LAUNCH_AGENT_LABEL.plist"
LOG_DIR="${LOG_DIR:-$HOME/Library/Logs/FzfPalette}"

INSTALL_LAUNCH_AGENT=false
LOAD_LAUNCH_AGENT=false
UNINSTALL_LAUNCH_AGENT=false

usage() {
  cat <<USAGE
Usage:
  scripts/install-app.sh [--launch-agent] [--load]
  scripts/install-app.sh --uninstall-launch-agent

Options:
  --launch-agent            Write a per-user LaunchAgent plist.
  --load                    Bootstrap the LaunchAgent immediately after writing it.
  --uninstall-launch-agent  Unload and remove the LaunchAgent plist.

Environment overrides:
  INSTALL_DIR               Default: \$HOME/Applications/FzfPalette.app
  LAUNCH_AGENT_DIR          Default: \$HOME/Library/LaunchAgents
  LAUNCH_AGENT_LABEL        Default: dev.benbernard.fzf-palette
  LOG_DIR                   Default: \$HOME/Library/Logs/FzfPalette
  FZF_PALETTE_HOTKEY        Optional hotkey passed to the LaunchAgent.
  FZF_PALETTE_HOTKEY_PROFILE Optional profile for FZF_PALETTE_HOTKEY.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --launch-agent)
      INSTALL_LAUNCH_AGENT=true
      ;;
    --load)
      INSTALL_LAUNCH_AGENT=true
      LOAD_LAUNCH_AGENT=true
      ;;
    --uninstall-launch-agent)
      UNINSTALL_LAUNCH_AGENT=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

launchctl_target() {
  echo "gui/$(id -u)"
}

xml_escape() {
  sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&apos;/g"
}

escaped() {
  printf '%s' "$1" | xml_escape
}

unload_launch_agent() {
  launchctl bootout "$(launchctl_target)" "$LAUNCH_AGENT_PATH" >/dev/null 2>&1 || true
}

write_launch_agent() {
  mkdir -p "$LAUNCH_AGENT_DIR" "$LOG_DIR"

  local app_executable="$INSTALL_DIR/Contents/MacOS/FzfPaletteApp"
  local escaped_label escaped_executable escaped_stdout escaped_stderr escaped_hotkey escaped_hotkey_profile
  escaped_label="$(escaped "$LAUNCH_AGENT_LABEL")"
  escaped_executable="$(escaped "$app_executable")"
  escaped_stdout="$(escaped "$LOG_DIR/launchd.out.log")"
  escaped_stderr="$(escaped "$LOG_DIR/launchd.err.log")"

  {
    cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$escaped_label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$escaped_executable</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>Crashed</key>
    <true/>
  </dict>
  <key>StandardOutPath</key>
  <string>$escaped_stdout</string>
  <key>StandardErrorPath</key>
  <string>$escaped_stderr</string>
PLIST

    if [[ -n "${FZF_PALETTE_HOTKEY:-}" || -n "${FZF_PALETTE_HOTKEY_PROFILE:-}" ]]; then
      escaped_hotkey="$(escaped "${FZF_PALETTE_HOTKEY:-}")"
      escaped_hotkey_profile="$(escaped "${FZF_PALETTE_HOTKEY_PROFILE:-}")"
      cat <<PLIST
  <key>EnvironmentVariables</key>
  <dict>
PLIST
      if [[ -n "${FZF_PALETTE_HOTKEY:-}" ]]; then
        cat <<PLIST
    <key>FZF_PALETTE_HOTKEY</key>
    <string>$escaped_hotkey</string>
PLIST
      fi
      if [[ -n "${FZF_PALETTE_HOTKEY_PROFILE:-}" ]]; then
        cat <<PLIST
    <key>FZF_PALETTE_HOTKEY_PROFILE</key>
    <string>$escaped_hotkey_profile</string>
PLIST
      fi
      cat <<PLIST
  </dict>
PLIST
    fi

    cat <<PLIST
</dict>
</plist>
PLIST
  } > "$LAUNCH_AGENT_PATH"
}

if [[ "$UNINSTALL_LAUNCH_AGENT" == true ]]; then
  unload_launch_agent
  rm -f "$LAUNCH_AGENT_PATH"
  echo "removed $LAUNCH_AGENT_PATH"
  exit 0
fi

"$ROOT/scripts/build-app.sh"
mkdir -p "$(dirname "$INSTALL_DIR")"
rm -rf "$INSTALL_DIR"
cp -R "$APP_DIR" "$INSTALL_DIR"

echo "$INSTALL_DIR"

if [[ "$INSTALL_LAUNCH_AGENT" == true ]]; then
  write_launch_agent
  /usr/bin/plutil -lint "$LAUNCH_AGENT_PATH" >/dev/null
  echo "$LAUNCH_AGENT_PATH"

  if [[ "$LOAD_LAUNCH_AGENT" == true ]]; then
    unload_launch_agent
    launchctl bootstrap "$(launchctl_target)" "$LAUNCH_AGENT_PATH"
    launchctl kickstart -k "$(launchctl_target)/$LAUNCH_AGENT_LABEL"
    echo "loaded $LAUNCH_AGENT_LABEL"
  fi
fi
