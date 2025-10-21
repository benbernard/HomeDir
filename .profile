export PATH="$HOME/.cargo/bin:$PATH"

if [[ -e ~/site/use_zsh ]]; then
  if [[ -x /usr/local/bin/zsh ]]; then
    export SHELL=/usr/local/bin/zsh
    exec /usr/local/bin/zsh
  fi
fi

[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm" # Load RVM into a shell session *as a function*

. "$HOME/.grit/bin/env"

# Job-specific login-shell setup lives in the private site repo, not this public repo.
[ -f "$HOME/site/site.sh" ] && . "$HOME/site/site.sh"
