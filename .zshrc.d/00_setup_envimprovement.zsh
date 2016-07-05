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
  echo -ne "\ek$TITLE\e\\"
fi

#Will get the zsh_version from eihooks
ENV_IMPROVEMENT_ZSHRC=$HOME/.eihooks/dotfiles/zshrc
