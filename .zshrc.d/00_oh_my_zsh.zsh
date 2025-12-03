# Path to your oh-my-zsh configuration.
ZSH=$HOME/.oh-my-zsh

# Defer compinit until after all .zshrc.d files load
autoload -Uz compinit
_compdef_queue=()
compinit() {
  # No-op: the real compinit will be called at the end of .zshrc
  :
}
compdef() {
  # Queue compdef calls to replay after real compinit runs
  _compdef_queue+=("${(j: :)@}")
}

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
# ZSH_THEME="robbyrussell"

# Set to this to use case-sensitive completion
# CASE_SENSITIVE="true"

# Comment this out to disable weekly auto-update checks
# DISABLE_AUTO_UPDATE="true"

# Uncomment following line if you want to disable colors in ls
# DISABLE_LS_COLORS="true"

# Uncomment following line if you want to disable autosetting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment following line if you want red dots to be displayed while waiting for completion
COMPLETION_WAITING_DOTS="true"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Example format: plugins=(rails git textmate ruby lighthouse)
#plugins=(git ruby github nyan python perl vi-mode django)
# Reduced to essentials for faster startup (was: git ruby python perl vi-mode frontend-search npm heroku kubectl)
plugins=(git vi-mode)

source $ZSH/oh-my-zsh.sh

# Plugin configurations

# History search
# Disabled plugins
# history-substring-search (don't like what it does to up/down while searching)

# # bind Ctrl-P and Ctrl-N
# bindkey '^P' history-substring-search-up
# bindkey '^N' history-substring-search-down

# # bind k and j for VI mode
# bindkey -M vicmd 'k' history-substring-search-up
# bindkey -M vicmd 'j' history-substring-search-down
