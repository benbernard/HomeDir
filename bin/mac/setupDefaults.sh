#!/bin/bash

# Force compatibility with django and mysql
# defaults write com.apple.versioner.python Prefer-32-Bit -bool yes

# Speed up expose / mission control animation time
defaults write com.apple.dock expose-animation-duration -float 0.1

# Turn on "always remember" checkbox for external URL handlers in Chrome
defaults write com.google.Chrome ExternalProtocolDialogShowAlwaysOpenCheckbox -bool true

# Set google to check less frequently
# https://www.macobserver.com/tmo/article/how-manage-the-secret-software-that-google-chrome-installs-on-your-mac
defaults write com.google.Keystone.Agent checkInterval 172800

# if [ -e /Applications/Android\ File\ Transfer.app/Contents/Resources ];
# then
#   echo "Attempting to turn off auto-pop up of android file transfer"
#   rm -r ~/Library/Application\ Support/Google/Android\ File\ Transfer/Android\ File\ Transfer\ Agent.app
#   cd /Applications/Android\ File\ Transfer.app/Contents/Resources
#   mv Android\ File\ Transfer\ Agent.app Android\ File\ Transfer\ Agent.app.DISABLED
# else
#   echo "Could not modify Andriod file transfer: not present"
# fi
#
#
# echo "Remember to symlink jshint, jscs, and node into /bin"
