if [[ ! $IS_REMOTE_INSTANCE -eq "true" ]]; then
  test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"
fi
