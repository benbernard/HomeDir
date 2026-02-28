# Put default nvm node's bin on PATH for immediate access to node/npm/yarn/etc.
# Only nvm itself is lazy-loaded. When nvm is sourced, it takes over PATH management.

export NVM_DIR="$HOME/.nvm"

_nvm_default_version=$(cat "$NVM_DIR/alias/default" 2>/dev/null)
if [[ -n "$_nvm_default_version" ]]; then
  [[ "$_nvm_default_version" != v* ]] && _nvm_default_version="v$_nvm_default_version"
  _nvm_default_bin="$NVM_DIR/versions/node/$_nvm_default_version/bin"
  if [[ -d "$_nvm_default_bin" ]]; then
    export PATH="$_nvm_default_bin:$PATH"
  fi
  unset _nvm_default_bin
fi
unset _nvm_default_version

# Lazy-load nvm itself (the version manager) — it's slow (~1s) to source
nvm() {
  unset -f nvm
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  nvm "$@"
}
