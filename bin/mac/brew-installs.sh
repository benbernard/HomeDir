brew install reattach-to-user-namespace \
 git-delta \
 rcs \
 neovim \
 python3 \
 fzf \
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
 coreutils

# Blank screensaver installs
brew tap theseal/blank-screensaver
brew install --cask blank-screensaver

pip3 install pynvim

sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs \
       https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
