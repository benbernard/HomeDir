#!/bin/bash

set -e

echo "Setting up Mac..."

echo "Setup sudo to use touch id, this may need your password..."
sudo sed -i bak '1 i\
auth sufficient pam_tid.so
' /etc/pam.d/sudo


echo "Installing Xcode Command Line Tools..."
xcode-select --install

echo "Cloning HomeDir..."
cd ~
git clone git@github.com:benbernard/HomeDir.git
cd HomeDir
git submodule init
git submodule update
cd ..
rsync -av HomeDir/ .

# Install Homebrew
echo "Installing Homebrew..."
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

BIN_DIR=${HOME}/bin/mac
echo "Running brew-installs.sh"
${BIN_DIR}/brew-installs.sh

echo "Running setupDefaults.sh"
${BIN_DIR}/setupDefaults.sh

echo "Installing Apps"
${BIN_DIR}/instalApps.sh


# echo "Installing autin"
# bash <(curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh)

# Check if ~/OneDrive exists
if [! -d ~/OneDrive ]; then
    echo "OneDrive not found. Please install OneDrive, sync config_content_backup, and hit enter"

    # Wait for user to hit enter
    read
fi

cp ~/OneDrive/config_content_backup/com.googlecode.iterm2.plist ~/Library/Preferences/com.googlecode.iterm2.plist

# Install fonts
echo "Installing fonts..."
cd ~/submodules/fonts
./install.sh

echo 'Setup Zsh'
NEW_ZSH=/opt/homebrew/bin/zsh
if ! fgrep -q ${NEW_ZSH} /etc/shells; then
    echo "Adding ${NEW_ZSH} to /etc/shells"
    echo ${NEW_ZSH} | sudo tee -a /etc/shells
fi
chsh -s ${NEW_ZSH}

echo 'Fixing better touch tool'
cp -r ~/OneDrive/Mackup/Library/Application\ Support/BetterTouchTool /Users/ben/Library/Application\ Support/

echo Installing VimPlug
sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs \
       https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'

echo Installing pynvim
/usr/bin/python3 -m pip install pynvim

echo Installing fzf
~/submodules/fzf/install --completion --key-bindings --no-update-rc

echo "Installing event script"
mkdir ~'/Library/Application Scripts/leits.MeetingBar'
cd ~'/Library/Application Scripts/leits.MeetingBar'
ln -s ~/bin/eventStartScript.scpt
cd

echo "================================================================================"
echo "========================== Interactive Section!      ==========================="
echo "================================================================================"
echo
echo "I'm going to run p10k configure, answer yes to installing fonts"
# Run with zsh so that we can get the modern evironment
echo "% p10k configure"
zsh -c 'p10k configure'


echo
echo "Now loggin into gh"
echo "% gh auth login"
zsh -c 'gh auth login'

echo
echo "Installing copilot extension"
echo '% gh extension install github/gh-copilot'
zsh -c 'gh extension install github/gh-copilot'

echo "================================================================================"
echo "========================== POST INSTALL INSTRUCTIONS ==========================="
echo "================================================================================"

echo <<EOF

Karabiner:
1. Grant karabiner-grabber full disk access, or it won't working

Better Touch Tool
1. Grant better touch tool full disk access, or it won't working
2. Sync config with dropbox
3. Turn on window moving/resize keys in preferences
4. If better touch tool isn't working properly, good luck.
   Maybe look at: https://community.folivora.ai/t/btt-not-opening/27402

Iterm:
1. Try in general/settings setting the setting to ~/OneDrive/config_content_backups/iterm-new

If that doesn't work:
1. Be sure to set the Meslo NF font, this should've been installed by powerline
   (p10k configure)
2. Set ctrl-enter to send ctrl-6 (hex code 0x1E) so that zsh-suggestions works

Chrome:
1. Be sure to setup both chrome profiles, name one 'Work' and one 'Home', then
   alfred should work

Finicky:
1. Start it, make sure meetings load correctly (may need to look at
   ../openMeetAndUrl.mjs for node version)

MeetingBar:
1. Start it, sync mac calendar, make sure new notifications work
2. You may need to save an event start script with the contents of
   ~/bin/eventStartScript.scpt

DONE!
EOF

# echo "1. Re-save iterm2 window profile, otherwise you'll startin in /"


echo "Done!"
