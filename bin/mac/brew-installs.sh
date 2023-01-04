brew install reattach-to-user-namespace \
 git-delta \
 rcs \
 neovim \
 python3 \
 rg \
 go \
 zsh \
 autoconf \
 automake \
 bat \
 fontconfig \
 git \
 imagemagick \
 jq \
 moreutils \
 readline \
 ripgrep \
 ssh-copy-id \
 wget \
 gh \
 shellcheck \
 mackup \
 pkg-config \
 libevent \
 ctags \
 yq \
 fx \
 lazygit \
 coreutils

# Blank screensaver installs
brew tap theseal/blank-screensaver
brew install --cask blank-screensaver

# Install Fonts
brew tap homebrew/cask-fonts
brew install --cask font-hack-nerd-font

pip3 install pynvim

sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs \
       https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'

/usr/bin/python3 -m pip install pynvim
