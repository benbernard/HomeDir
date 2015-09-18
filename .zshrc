# Fix when setenv isn't available, should probably just move to export at some
# point.
setenv() {
  export $1=$2
}

if [[ -z $ZSH_VERSION ]]
then
  ZSH_VERSION=`$SHELL --version | /usr/bin/cut -d ' ' -f 2`
fi

# Source all files in .zshrc.d
foreach i (`ls -1 ~/.zshrc.d/*.zsh`) {
  source $i
}

PATH=$PATH:$HOME/.rvm/bin # Add RVM to PATH for scripting

if [[ -e ~/.zproifle ]]; then
    source ~/.zprofile
fi
