# Completion style settings
zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete _approximate
zstyle ':completion:*' completions 1
#zstyle ':completion:*' expand prefix suffix
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' glob 1
zstyle ':completion:*' insert-unambiguous true
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
zstyle ':completion:*' list-suffixes true
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'l:|=* r:|=*'
zstyle ':completion:*' max-errors 2
zstyle ':completion:*' menu select=1
zstyle ':completion:*' original true
zstyle ':completion:*' preserve-prefix '//[^/]##/'
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle ':completion:*' squeeze-slashes true
zstyle ':completion:*' substitute 1
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true
zstyle ':completion:*' ambiguous true
zstyle :compinstall filename "$HOME/.zshrc"

##Setup completion for ssh from .hosts file
#zstyle -e ':completion:*:ssh:*' format
#zstyle -e ':completion:*:ssh:*' users 'reply=()'

## Set all hosts completions to use .hosts
#zstyle -e ':completion:*:*' hosts 'reply=($(cat $HOME/.hosts))'
##zstyle -e ':completion:*:*:*' hosts 'reply=($(cat $HOME/.hosts))'

autoload -U compinit
compinit 

