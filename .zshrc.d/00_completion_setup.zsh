if [[ -e $HOME/zsh-completions/src ]]; then
  fpath=($HOME/zsh-completions/src $fpath);
fi

# Must have this for custom completions
autoload -U compinit
compinit

#Setup completion functions
#FPATH=/usr/local/share/zsh/4.2.0/functions
if [[ -d ~/.zshfuncs ]]; then
  fpath=(~/.zshfuncs $fpath)
  autoload -U ~/.zshfuncs/*(:t)
fi

if [[ -d /usr/local/share/zsh/site-functions ]]; then
  fpath=(/usr/local/share/zsh/site-functions $fpath)
  autoload -U /usr/local/share/zsh/site-functions/*(:t)
fi
