#!/bin/bash

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

echo "================================================================================"
echo "========================== POST INSTALL INSTRUCTIONS ==========================="
echo "================================================================================"
echo
echo "1. Re-save iterm2 window profile, otherwise you'll startin in /"
echo "2. Be sure to grant karabiner-grabber, and better touch tool full disk access"
echo "3. If better touch tool isn't working properly, good luck.  Maybe look at: https://community.folivora.ai/t/btt-not-opening/27402"
echo "4. Install Choosey - https://choosy.app/"
echo "4. Install Karabiner Elements - https://karabiner-elements.pqrs.org/"
echo "5. Install Better Touch Tool - https://folivora.ai/"
echo "6. Install Krisp.ai - https://krisp.ai/"
echo "7. Install VSCode - https://code.visualstudio.com/"
echo "8. Install Slack - https://slack.com/downloads/mac"
echo "9. Install Alfred - https://www.alfredapp.com/"
echo " -- Or just try running installApps.sh (experimental)"

echo "Done!"
