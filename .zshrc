# Eanble this section to log everything zsh does at startup
# zmodload zsh/datetime
# setopt PROMPT_SUBST
# PS4='+$EPOCHREALTIME %N:%i> '
#
# logfile=$(mktemp zsh_profile.XXXXXXXX)
# echo "Logging to $logfile"
# exec 3>&2 2>$logfile
#
# setopt XTRACE

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Fix when setenv isn't available, should probably just move to export at some
# point.
setenv() {
  export $1=$2
}

# Add helper for getting submodule directories
SUBMODULE_DIR=${HOME}/submodules
submodule() {
  echo ${SUBMODULE_DIR}/$1
}

if [[ -e "${HOME}/site/use_minimal" ]]; then
  source ${HOME}/.minimal/zsh/zshrc
fi


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

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
### BEGIN--Instacart Shell Settings. (Updated: Wed Jan 27 10:08:40 PST 2021. [Script Version 1.2.6]) NO-TOUCH
# This Line Added Automatically by Instacart Setup Script
# The sourced file contains all of the instacart utilities and shell settings
# To remove this functionality, leave the block, and enter "NO-TOUCH" in the BEGIN line, and comment the line below:
# source /Users/benbernard/.instacart_shell_profile
### END--Instacart Shell Settings.
