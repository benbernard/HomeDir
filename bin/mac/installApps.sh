#!/bin/bash

echo "Installing apps from brew cask"

# TODO: Add guards for all these to see if they've already been installed

installed_casks=$(brew list --cask)

function install_cask() {
  local cask_name=$1
  local app_name=${2:-$1}
  if [ -d "/Applications/${app_name}.app" ] || [ -d "$HOME/Applications/${app_name}.app" ]; then
    echo "$app_name is already installed in Applications."
  elif ! echo "$installed_casks" | grep -q "$cask_name"; then
    echo "Installing $cask_name..."
    brew install --cask "$cask_name"
  else
    echo "$cask_name is already installed via Homebrew Cask."
  fi
}

install_cask "google-chrome" "Google Chrome"
install_cask "onedrive" "OneDrive"
install_cask "iterm2" "iTerm"
install_cask "karabiner-elements" "Karabiner-Elements"
install_cask "bettertouchtool" "BetterTouchTool"
install_cask "krisp" "krisp"
install_cask "visual-studio-code" "Visual Studio Code"
install_cask "slack" "Slack"
install_cask "alfred" "Alfred 5"
install_cask "wavebox" "Wavebox"
install_cask "p4v" "p4v"
install_cask "finicky" "Finicky"
install_cask "cursor" "Cursor"
install_cask "linear-linear" "Linear"
install_cask "meetingbar" "MeetingBar"
install_cask "snagit" "Snagit"
install_cask "tailscale" "Tailscale"
install_cask "orbstack" "Orbstack"
install_cask "bitwarden" "Bitwarden"
install_cask "hiddenbar" "Hidden Bar"

# Graveyard
# install_cask "inkdrop"
# install_cask "dash"
# install_cask "choosy"
