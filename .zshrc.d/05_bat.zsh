if command -v bat >/dev/null 2>/dev/null; then
  if [[ -n "$CODEX_SHELL" ]]; then
    export BAT_THEME="GitHub"
  fi

  # set bat as the default pager
  export PAGER=bat
  export BAT_PAGER="less -XRMSIF"
  export MANPAGER="sh -c 'col -bx | bat -l man'"

  # Alias cat to bat
  alias 'cat=bat'
else
  echo "No bat installed?"
fi
