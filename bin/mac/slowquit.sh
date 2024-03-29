# Taken from: https://github.com/dteoh/SlowQuitApps

echo "Install from https://github.com/Lessica/SlowQuitApps/releases"
#brew tap dteoh/sqa
#brew install --cask slowquitapps

# Set to 5 seconds
defaults write com.dteoh.SlowQuitApps delay -int 1000

# Invert list, so only specified apps have it
defaults write com.dteoh.SlowQuitApps invertList -bool YES

# Slack
defaults write com.dteoh.SlowQuitApps whitelist -array-add com.tinyspeck.slackmacgap

# Mattermost
defaults write com.dteoh.SlowQuitApps whitelist -array-add Mattermost.Desktop

# Wavebox
defaults write com.dteoh.SlowQuitApps whitelist -array-add com.bookry.wavebox
