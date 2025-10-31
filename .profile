export PATH="$HOME/.cargo/bin:$PATH"

if [[ -e ~/site/use_zsh ]]; then
  if [[ -x /usr/local/bin/zsh ]]; then
    export SHELL=/usr/local/bin/zsh
    exec /usr/local/bin/zsh
  fi
fi

[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm" # Load RVM into a shell session *as a function*

. "$HOME/.grit/bin/env"

# >>> gohan setup, do not edit this section <<<
# !! Contents within this block are managed by gohan !!
[ -f "/Users/benbernard/.config/gohan/gohan.sh" ] && source "/Users/benbernard/.config/gohan/gohan.sh"
# <<< gohan setup end <<<
