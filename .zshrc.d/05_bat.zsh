if command -v bat >/dev/null 2>/dev/null; then
  # set bat as the default pager
  export PAGER=bat
  export BAT_PAGER="less -XRMSIF"
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"

  # Alias cat to bat
  alias 'cat=bat'
else
  echo "No bat installed?"
fi
