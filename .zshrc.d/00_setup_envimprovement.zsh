# Sets: ENV_IMPROVEMENT_ROOT, ZSH_VERSION

if [[ "$NINJA_SEARCH_SHELL" = "YES" ]]
then
  AUTO_TITLE_SCREENS=NO
  PS1=
  PROMPT=
  RPROMPT=
fi

if [[ -n "$TITLE" ]]
then
  AUTO_TITLE_SCREENS=NO

  if [[ "$TERM" == "screen" ]]; then
    echo -ne "\ek$TITLE\e\\"
  fi
  if [[ "$TERM" == "xterm" ]]; then
    echo -ne "\e]0;$TITLE\a"
  fi
fi

#Will get the zsh_version from eihooks
ENV_IMPROVEMENT_ZSHRC=$HOME/.eihooks/dotfiles/zshrc
