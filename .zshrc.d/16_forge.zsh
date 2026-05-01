# Work around a Forge startup segfault triggered by the zsh shell integration.
# Define forge as a shell function so Forge's generated plugin resolves the
# command through shell lookup instead of bypassing the workaround via alias.
if [[ -z "$FORGE_SIMPLE_ZSH" ]]; then
  if typeset -f forge >/dev/null 2>&1; then
    unfunction forge
  fi
  return 0
fi

forge() {
  bash --noprofile --norc -ic 'PATH=$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin forge "$@"' bash "$@"
}
