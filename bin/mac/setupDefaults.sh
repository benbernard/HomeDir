#!/bin/bash

log_command() {
  echo "% $1"
  eval $1
}

# Force compatibility with django and mysql
# log_command "defaults write com.apple.versioner.python Prefer-32-Bit -bool yes"

# Speed up expose / mission control animation time
log_command "defaults write com.apple.dock expose-animation-duration -float 0.1"

# Turn on "always remember" checkbox for external URL handlers in Chrome
log_command "defaults write com.google.Chrome ExternalProtocolDialogShowAlwaysOpenCheckbox -bool true"

# Set google to check less frequently
# https://www.macobserver.com/tmo/article/how-manage-the-secret-software-that-google-chrome-installs-on-your-mac
log_command "defaults write com.google.Keystone.Agent checkInterval 172800"

# if [ -e /Applications/Android\ File\ Transfer.app/Contents/Resources ];
# then
#   echo "Attempting to turn off auto-pop up of android file transfer"
#   log_command "rm -r ~/Library/Application\ Support/Google/Android\ File\ Transfer/Android\ File\ Transfer\ Agent.app"
#   cd /Applications/Android\ File\ Transfer.app/Contents/Resources
#   log_command "mv Android\ File\ Transfer\ Agent.app Android\ File\ Transfer\ Agent.app.DISABLED"
# else
#   echo "Could not modify Andriod file transfer: not present"
# fi
#
#
# echo "Remember to symlink jshint, jscs, and node into /bin"


# Allow key repeats in VSCode / Cursor and other apps
log_command "defaults write -g ApplePressAndHoldEnabled -bool false"
# log_command "defaults write com.microsoft.VSCode ApplePressAndHoldEnabled -bool false"              # For VS Code
# log_command "defaults write com.microsoft.VSCodeInsiders ApplePressAndHoldEnabled -bool false"      # For VS Code Insider
# log_command "defaults write com.visualstudio.code.oss ApplePressAndHoldEnabled -bool false"         # For VS Codium
# log_command "defaults write com.microsoft.VSCodeExploration ApplePressAndHoldEnabled -bool false"   # For VS Codium Exploration users
# log_command "defaults write --app Cursor ApplePressAndHoldEnabled false"                      # For Cursor.sh, may only work after install
# log_command "defaults delete -g ApplePressAndHoldEnabled"                                           # If necessary, reset global default

