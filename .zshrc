# Fix when setenv isn't available
setenv() {
  export $1=$2
}

# Add helper for getting submodule directories
SUBMODULE_DIR=${HOME}/submodules
submodule() {
  echo ${SUBMODULE_DIR}/$1
}

# VS Code shell special handling
if [[ "$TERM_PROGRAM" == "vscode" ]]; then
  # Load essential environment settings
  if [ -f ~/.zshrc.d/02_environment.zsh ]; then
    source ~/.zshrc.d/02_environment.zsh
  fi

  # Skip the rest of the startup configuration
  return 0
fi

# To do profiling ZSH_PROFILE=1

if [[ "$ZSH_PROFILE" == "1" ]]; then
 zmodload zsh/zprof
fi

# To get detailed command logging on startup (and always) ZSH_CMD_LOGGING=1
if [[ "$ZSH_CMD_LOGGING" == "1" ]]; then
  zmodload zsh/datetime
  setopt PROMPT_SUBST
  PS4='+$EPOCHREALTIME %N:%i> '

  logfile=$(mktemp zsh_profile.XXXXXXXX)
  echo "Logging to $logfile"
  exec 3>&2 2>$logfile
  setopt XTRACE
fi

# Load completion functions
autoload -Uz compinit

# Fuck it, disable compaudit
ZSH_DISABLE_COMPFIX=true

# Disable prompt to update oh my zsh
DISABLE_UPDATE_PROMPT=true

# I've decide that instant prompt isn't worth it, would rather have an initialized shell
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
#
# p10k instant prompt.  I've decided to disable this feature, as I just want an initalized shell, not a fake one
# Do not do instant prompt if we are recording a demo
# if [[ ${recording} != "true" ]]; then
#   if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
#     source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
#   fi
# fi

if [[ -e "${HOME}/site/use_minimal" ]]; then
  source ${HOME}/.minimal/zsh/zshrc
fi


if [[ -z $ZSH_VERSION ]]
then
  ZSH_VERSION=`$SHELL --version | /usr/bin/cut -d ' ' -f 2`
fi

# Source files in .shellrc.d (I don't use this, but some systems do)
if [ -d ~/.shellrc.d ]; then
  for i in $(find $HOME/.shellrc.d/ -name '*.sh' -o -name '*.zsh' | sort); do
    . $i
  done
  unset i
fi

# Source all files in .zshrc.d
if [ -d ~/.zshrc.d ]; then
  foreach i (`ls -1 ~/.zshrc.d/*.zsh`) {
    source $i
  }
fi

PATH=$PATH:$HOME/.rvm/bin # Add RVM to PATH for scripting

if [[ -e ~/.zproifle ]]; then
    source ~/.zprofile
fi

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# This was for Warp terminal, which I don't think is ready yet
# printf '\eP$f{"hook": "SourcedRcFileForWarp", "value": { "shell": "zsh"}}\x9c'

# Perform compinit after everything has loaded.  Only do a full compinit if
# zcompdump file is older than 24 hours
if [[ -n ${ZDOTDIR}/.zcompdump(#qN.mh+24) ]]; then
	compinit -u;
else
	compinit -C -u;
fi;

### BEGIN--Instacart Shell Settings. (Updated: Wed Jul 14 13:32:34 PDT 2021. [Script Version 1.3.16]) NO-TOUCH
### END--Instacart Shell Settings.

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# Print out profiling if enabled
if [[ "$ZSH_PROFILE" == "1" ]]; then
 zprof
fi

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/benbernard/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/benbernard/Downloads/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/benbernard/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/benbernard/Downloads/google-cloud-sdk/completion.zsh.inc'; fi

# Load pyenv automatically by appending
# the following to
# ~/.zprofile (for login shells)
# and ~/.zshrc (for interactive shells) :

if command -v pyenv 1>/dev/null 2>/dev/null; then
  export PYENV_ROOT="$HOME/.pyenv"
  [[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"
fi

eval "$(starship init zsh)"

# Added by Windsurf
export PATH="/Users/benbernard/.codeium/windsurf/bin:$PATH"

# Added by Windsurf
export PATH="/Users/benbernard/.codeium/windsurf/bin:$PATH"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Auto-Warpify
[[ "$-" == *i* ]] && printf 'P$f{"hook": "SourcedRcFileForWarp", "value": { "shell": "zsh", "uname": "Linux" }}œ' 
