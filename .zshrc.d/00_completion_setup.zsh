if [[ -e $HOME/zsh-completions/src ]]; then
  fpath=($HOME/zsh-completions/src $fpath);
fi

#Setup completion functions
#FPATH=/usr/local/share/zsh/4.2.0/functions
if [[ -d ~/.zshfuncs ]]; then
  if ls -A ~/.zshfuncs | grep '.' 1>/dev/null 2>/dev/null; then
    fpath=(~/.zshfuncs $fpath)
    autoload -U ~/.zshfuncs/*(:t)
  fi
fi

if [[ -d /usr/local/share/zsh/site-functions ]]; then
  fpath=(/usr/local/share/zsh/site-functions $fpath)
  if ls /usr/local/share/zsh/site-functions/ | grep '.' 1>/dev/null 2>/dev/null; then
    autoload -U /usr/local/share/zsh/site-functions/*(:t)
  fi
fi
